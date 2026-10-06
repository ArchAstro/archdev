import assert from "node:assert/strict";
import { execFileSync, spawnSync } from "node:child_process";
import {
  chmodSync,
  mkdirSync,
  mkdtempSync,
  readFileSync,
  realpathSync,
  rmSync,
  writeFileSync,
} from "node:fs";
import { tmpdir } from "node:os";
import path from "node:path";
import { describe, test } from "node:test";
import { pathToFileURL } from "node:url";
import {
  HARNESSES,
  harnessHooks,
  hookTimeout,
  loadCatalog,
  validateCatalog,
  type Catalog,
} from "../src/catalog.ts";
import { PASCAL_EVENTS, type GeneratedFile } from "../src/files.ts";
import { diffFiles, generate, OWNED_PATHS, writeFiles } from "../src/generate.ts";
import { ADAPTERS } from "../src/harnesses/index.ts";

const repoRoot = execFileSync("git", ["rev-parse", "--show-toplevel"], {
  encoding: "utf8",
}).trim();
const catalog = loadCatalog(path.join(repoRoot, "catalog", "archdev.json"));
const files = generate(repoRoot, catalog);
const byPath = new Map(files.map((file) => [file.path, file]));

function json(file: string): any {
  const entry = byPath.get(file);
  assert.ok(entry, `${file} is generated`);
  return JSON.parse(entry.content.toString("utf8"));
}

function under(prefix: string): GeneratedFile[] {
  return files.filter((file) => file.path.startsWith(`${prefix}/`));
}

describe("catalog", () => {
  test("the committed catalog is valid and names every harness", () => {
    assert.deepEqual(validateCatalog(catalog), []);
    assert.deepEqual(Object.keys(catalog.harnesses).sort(), [...HARNESSES].sort());
  });

  test("invalid fields are each reported", () => {
    const bad = structuredClone(catalog) as Catalog;
    bad.name = "Arch_Dev";
    bad.version = "1.0";
    bad.skills.push({ name: "archdev", path: "../outside" });
    bad.mcp.url = "http://archdev.ai/api/v1/mcp";
    bad.hooks.events.toolUse.timeout = 0;
    (bad.harnesses as Record<string, unknown>).windsurf = { hooksUnsupported: "x" };
    const problems = validateCatalog(bad);
    for (const expected of [
      /name "Arch_Dev"/,
      /version "1.0"/,
      /skill "archdev" is listed twice/,
      /path must stay inside the repo/,
      /must be https/,
      /toolUse.timeout/,
      /windsurf has no generator adapter/,
    ])
      assert.ok(problems.some((p) => expected.test(p)), `${expected} in ${problems.join("; ")}`);
  });
});

describe("generation", () => {
  test("is deterministic and sorted", () => {
    const again = generate(repoRoot, catalog);
    assert.deepEqual(
      again.map((f) => [f.path, f.mode, f.content.toString("base64")]),
      files.map((f) => [f.path, f.mode, f.content.toString("base64")]),
    );
    assert.deepEqual(files.map((f) => f.path), [...files.map((f) => f.path)].sort());
  });

  test("every plugin carries every skill byte for byte, with its mode", () => {
    const tracked = execFileSync("git", ["ls-files", "--stage", "--", ...catalog.skills.map((s) => `${s.path}/`)], {
      cwd: repoRoot,
      encoding: "utf8",
    })
      .trim()
      .split("\n");
    for (const harness of HARNESSES) {
      for (const line of tracked) {
        const [meta, file] = line.split("\t") as [string, string];
        const skill = catalog.skills.find((s) => file.startsWith(`${s.path}/`))!;
        const target = `${ADAPTERS[harness].root}/skills/${skill.name}/${file.slice(skill.path.length + 1)}`;
        const generated = byPath.get(target);
        assert.ok(generated, `${target} exists`);
        assert.ok(generated.content.equals(readFileSync(path.join(repoRoot, file))), `${target} matches ${file}`);
        assert.equal(generated.mode, meta.startsWith("100755") ? 0o755 : 0o644, `${target} mode`);
      }
    }
  });

  test("only the catalog's hook harnesses ship hook files", () => {
    for (const harness of HARNESSES) {
      const hookFiles = under(ADAPTERS[harness].root).filter((f) =>
        /(^|\/)(hooks\/|extensions\/|com\.github\.copilot\/)/.test(f.path.slice(ADAPTERS[harness].root.length)),
      );
      assert.equal(hookFiles.length > 0, Boolean(harnessHooks(catalog, harness)), harness);
    }
  });
});

describe("Claude-format hooks (Claude Code, Codex, Grok)", () => {
  for (const [harness, file] of [
    ["claude", "plugins/claude/hooks/hooks.json"],
    ["codex", "plugins/codex/hooks/hooks.json"],
    ["grok", "plugins/grok/hooks/hooks.json"],
  ] as const) {
    test(`${harness} wires each catalog event to the CLI with its harness name`, () => {
      const wiring = harnessHooks(catalog, harness)!;
      const hooksFile = json(file);
      // Codex rejects unknown top-level keys; Claude requires the wrapper.
      assert.deepEqual(Object.keys(hooksFile), ["hooks"]);
      assert.deepEqual(Object.keys(hooksFile.hooks), wiring.events.map((e) => PASCAL_EVENTS[e]));
      for (const event of wiring.events) {
        const [group] = hooksFile.hooks[PASCAL_EVENTS[event]];
        assert.equal(group.matcher, event === "toolUse" ? wiring.toolMatcher : undefined);
        assert.deepEqual(group.hooks, [
          {
            type: "command",
            command: `command -v archdev >/dev/null 2>&1 || exit 0; exec archdev repo hook ${catalog.hooks.events[event].action} --harness ${wiring.harness} --spec ${catalog.hooks.spec}`,
            timeout: hookTimeout(catalog, wiring, event),
          },
        ]);
      }
    });
  }
});

describe("manifests", () => {
  test("Claude Code and Grok use the Claude layout with an http MCP server", () => {
    for (const root of ["plugins/claude", "plugins/grok"]) {
      assert.equal(json(`${root}/.claude-plugin/plugin.json`).version, catalog.version);
      assert.deepEqual(json(`${root}/.mcp.json`), {
        mcpServers: { archdev: { type: "http", url: catalog.mcp.url } },
      });
    }
  });

  test("Codex uses its native manifest and no root plugin.json that would shadow it", () => {
    assert.equal(byPath.has("plugins/codex/plugin.json"), false);
    const manifest = json("plugins/codex/.codex-plugin/plugin.json");
    assert.equal(manifest.skills, "./skills/");
    assert.equal(manifest.mcpServers, "./mcp.json");
    assert.equal(manifest.hooks, "./hooks/hooks.json");
    assert.ok(byPath.has("plugins/codex/hooks/hooks.json"));
  });

  test("Copilot gets a closed Agent Plugins 1.0.0 manifest and MCP file", () => {
    const manifest = json("plugins/copilot/plugin.json");
    assert.equal(manifest.$schema, "https://agent-plugins.org/schemas/1.0.0/plugin.schema.json");
    const allowed = ["$schema", "name", "version", "description", "author", "homepage", "repository", "license", "keywords", "extensions"];
    for (const key of Object.keys(manifest)) assert.ok(allowed.includes(key), key);
    assert.match(manifest.name, /^(?!.*(?:--|\.\.))[a-z0-9](?:[a-z0-9.-]*[a-z0-9])?$/);
    assert.deepEqual(json("plugins/copilot/mcp.json"), {
      $schema: "https://agent-plugins.org/schemas/1.0.0/mcp.schema.json",
      mcpServers: { archdev: { type: "streamable-http", url: catalog.mcp.url } },
    });
  });

  test("Cursor names its component paths and uses a bare MCP url", () => {
    const manifest = json("plugins/cursor/.cursor-plugin/plugin.json");
    assert.equal(manifest.skills, "./skills/");
    assert.equal(manifest.mcpServers, "./mcp.json");
    assert.deepEqual(json("plugins/cursor/mcp.json"), { mcpServers: { archdev: { url: catalog.mcp.url } } });
  });

  test("Antigravity gets only the three manifest keys it allows and serverUrl", () => {
    assert.deepEqual(Object.keys(json("plugins/antigravity/plugin.json")), ["$schema", "name", "description"]);
    assert.deepEqual(json("plugins/antigravity/mcp_config.json"), {
      mcpServers: { archdev: { serverUrl: catalog.mcp.url } },
    });
  });

  test("each marketplace points at a generated plugin root", () => {
    const sources: [string, (m: any) => string][] = [
      [".claude-plugin/marketplace.json", (m) => m.plugins[0].source],
      [".grok-plugin/marketplace.json", (m) => m.plugins[0].source],
      [".github/plugin/marketplace.json", (m) => m.plugins[0].source],
      [".cursor-plugin/marketplace.json", (m) => m.plugins[0].source],
      [".agents/plugins/marketplace.json", (m) => m.plugins[0].source.path],
    ];
    const expected = ["claude", "grok", "copilot", "cursor", "codex"];
    sources.forEach(([file, source], i) => {
      const marketplace = json(file);
      assert.equal(marketplace.name, catalog.name);
      assert.equal(path.posix.normalize(source(marketplace)), `plugins/${expected[i]}`);
    });
  });

  test("the OpenCode package is the public scoped package the publish workflow expects", () => {
    const pkg = json("plugins/opencode/package.json");
    assert.equal(pkg.name, "@archastro/archdev-opencode");
    assert.equal(pkg.version, catalog.version);
    assert.deepEqual(pkg.publishConfig, { access: "public" });
    assert.deepEqual(pkg.files, ["index.js", "skills"]);
  });

  test("the root package.json points Pi at the generated package", () => {
    assert.deepEqual(json("package.json").pi, {
      extensions: ["./plugins/pi/extensions"],
      skills: ["./plugins/pi/skills"],
    });
    for (const dir of json("package.json").pi.skills)
      assert.ok(files.some((f) => f.path.startsWith(`${path.posix.normalize(dir)}/archdev/`)));
  });
});

describe("hook guard", () => {
  const command = JSON.parse(byPath.get("plugins/claude/hooks/hooks.json")!.content.toString()).hooks.Stop[0].hooks[0].command as string;

  test("without the CLI on PATH the hook exits 0 silently", () => {
    const result = spawnSync("/bin/sh", ["-c", command], { env: { PATH: "/usr/bin:/bin" }, input: "{}", encoding: "utf8" });
    assert.equal(result.status, 0);
    assert.equal(result.stdout + result.stderr, "");
  });

  test("with the CLI it forwards arguments, stdin, stdout and the exit code", () => {
    const bin = mkdtempSync(path.join(tmpdir(), "archdev-guard-"));
    writeFileSync(path.join(bin, "archdev"), '#!/bin/sh\nprintf "%s|" "$*"; cat; exit 2\n');
    chmodSync(path.join(bin, "archdev"), 0o755);
    const result = spawnSync("/bin/sh", ["-c", command], {
      env: { PATH: `${bin}:/usr/bin:/bin` },
      input: '{"session_id":"s"}',
      encoding: "utf8",
    });
    assert.equal(result.status, 2);
    assert.equal(result.stdout, `repo hook stop --harness claude --spec ${catalog.hooks.spec}|{"session_id":"s"}`);
  });
});

describe("code plugins", () => {
  const scratch = realpathSync(mkdtempSync(path.join(tmpdir(), "archdev-code-plugins-")));
  writeFiles(scratch, files.filter((f) => f.path.startsWith("plugins/pi/") || f.path.startsWith("plugins/opencode/")));

  test("OpenCode adds its skills and MCP server once and keeps a user's own server", async () => {
    const { ArchDevPlugin } = await import(pathToFileURL(path.join(scratch, "plugins/opencode/index.js")).href);
    const hooks = await ArchDevPlugin({});
    const config: any = { skills: { paths: ["/mine"] } };
    await hooks.config(config);
    await hooks.config(config);
    assert.deepEqual(config.skills.paths, ["/mine", path.join(scratch, "plugins/opencode/skills")]);
    assert.deepEqual(config.mcp, { archdev: { type: "remote", url: catalog.mcp.url, enabled: true } });

    const custom: any = { mcp: { archdev: { type: "remote", url: "https://example.test/mcp" } } };
    await hooks.config(custom);
    assert.equal(custom.mcp.archdev.url, "https://example.test/mcp");
  });

  test("Pi's extension forwards session events to the CLI and reports a missing CLI", async () => {
    const { default: register } = await import(pathToFileURL(path.join(scratch, "plugins/pi/extensions/archdev.js")).href);
    const handlers = new Map<string, Function>();
    const calls: string[][] = [];
    let missing = false;
    register({
      on: (event: string, handler: Function) => handlers.set(event, handler),
      exec: async (cmd: string, args: string[], options: { timeout: number }) => {
        calls.push([cmd, ...args.slice(0, 7), `${options.timeout}ms`]);
        if (missing) return { code: 127, stdout: "", stderr: "" };
        return args[2] === "start"
          ? { code: 0, stdout: "CONTRACT\n" }
          : { code: 0, stdout: JSON.stringify({ hookSpecificOutput: { additionalContext: `${args[2]} context` } }) };
      },
    });
    const ctx = { cwd: "/repo", sessionManager: { getSessionId: () => "s1" } };
    const spec = String(catalog.hooks.spec);

    await handlers.get("session_start")!({}, ctx);
    const turn = await handlers.get("before_agent_start")!({}, ctx);
    assert.equal(turn.message.content, "CONTRACT\n\nprompt context");
    const tool = await handlers.get("tool_result")!({ toolName: "bash", input: {}, content: [] }, ctx);
    assert.deepEqual(tool.content, [{ type: "text", text: "ArchDev monitor: post-tool context" }]);
    assert.equal(await handlers.get("tool_result")!({ toolName: "read", input: {}, content: [] }, ctx), undefined);
    await handlers.get("agent_settled")!({}, ctx);
    await handlers.get("session_shutdown")!({}, ctx);
    assert.deepEqual(
      calls.map((c) => c.join(" ")),
      // The CLI's own Pi extension gives start 30 s and every other action 10 s.
      [["start", 30000], ["prompt", 10000], ["post-tool", 10000], ["stop", 10000], ["end", 10000]].map(
        ([a, ms]) => `archdev repo hook ${a} --harness pi --spec ${spec} ${ms}ms`,
      ),
    );

    missing = true;
    await handlers.get("session_start")!({}, ctx);
    const first = await handlers.get("before_agent_start")!({}, ctx);
    assert.match(first.message.content, /^The ArchDev plugin is installed, but the ArchDev CLI is not on PATH/);
  });
});

describe("check", () => {
  test("reports missing, changed, unexpected and mode drift under owned paths", () => {
    const dir = mkdtempSync(path.join(tmpdir(), "archdev-check-"));
    writeFiles(dir, files);
    assert.deepEqual(diffFiles(dir, files), []);

    writeFileSync(path.join(dir, "plugins/claude/.mcp.json"), "{}\n");
    rmSync(path.join(dir, "plugins/codex/hooks/hooks.json"));
    mkdirSync(path.join(dir, "plugins/stale"), { recursive: true });
    writeFileSync(path.join(dir, "plugins/stale/plugin.json"), "{}");
    chmodSync(path.join(dir, "plugins/claude/skills/archdev/scripts/bootstrap.sh"), 0o644);
    writeFileSync(path.join(dir, "README.md"), "not owned");

    assert.deepEqual(diffFiles(dir, files), [
      "changed: plugins/claude/.mcp.json",
      "mode: plugins/claude/skills/archdev/scripts/bootstrap.sh should be 755",
      "missing: plugins/codex/hooks/hooks.json",
      "unexpected: plugins/stale/plugin.json",
    ]);
  });

  test("the committed plugins match the catalog", () => {
    assert.deepEqual(diffFiles(repoRoot, files), []);
  });

  test("every generated file sits under an owned path", () => {
    for (const file of files)
      assert.ok(OWNED_PATHS.some((owned) => file.path === owned || file.path.startsWith(`${owned}/`)), file.path);
  });
});
