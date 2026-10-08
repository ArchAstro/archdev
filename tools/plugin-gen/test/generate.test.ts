import assert from "node:assert/strict";
import { execFileSync, spawnSync } from "node:child_process";
import {
  chmodSync,
  existsSync,
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
import { NUDGE_EVENTS, nudgeScriptSource, PASCAL_EVENTS, shellQuote, type GeneratedFile } from "../src/files.ts";
import { NUDGE_TEXT } from "../src/nudge-text.ts";
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

  test("every distributed skill teaches server ownership while preserving plan/task risk", () => {
    for (const skill of catalog.skills) {
      const text = readFileSync(path.join(repoRoot, skill.path, "SKILL.md"), "utf8");
      assert.match(text, /[Ss]erver automation owns hosted/);
      assert.match(text, /risk\.plan/);
      assert.match(text, /risk\.task/);
      assert.doesNotMatch(text, /store that head.s review annotations|pr\.\*.*carries a sealed/);
    }
    const monitor = readFileSync(path.join(repoRoot, "archdev/references/monitor.md"), "utf8");
    assert.match(monitor, /PR reporting must not fetch, wait for, reuse, or attach/);
    assert.match(monitor, /Absent `corpus.capture` means off/);
    assert.match(monitor, /Already-latest upgrade exits before/);
    assert.doesNotMatch(monitor, /## Focus range seals|## PR review annotations/);
    for (const name of ["prCreated", "prUpdated", "prClosed"] as const) {
      assert.match(NUDGE_TEXT[name], /without fetching, waiting for, reusing, or attaching/);
      assert.doesNotMatch(NUDGE_TEXT[name], /RISK_STEPS|archdev_get_pr_risk|archdev_finalize_risk/);
    }
    assert.match(NUDGE_TEXT.plan, /RISK_STEPS/);
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
            command: wiring.nudge && NUDGE_EVENTS.includes(event)
              ? `if command -v archdev >/dev/null 2>&1; then exec archdev repo hook ${catalog.hooks.events[event].action} --harness ${wiring.harness} --spec ${catalog.hooks.spec}; fi; exec sh "${wiring.nudge.pluginRoot}/hooks/archdev-nudge.sh" ${catalog.hooks.events[event].action}`
              : `command -v archdev >/dev/null 2>&1 || ${
              event === "sessionStart"
                ? `{ printf '%s\\n' ${shellQuote(catalog.hooks.missingCliGuidance)}; exit 0; }`
                : "exit 0"
            }; exec archdev repo hook ${catalog.hooks.events[event].action} --harness ${wiring.harness} --spec ${catalog.hooks.spec}`,
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
        mcpServers: { archdev: { type: "http", url: `\${ARCHDEV_MCP_URL:-${catalog.mcp.url}}` } },
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

  const hooksFile = JSON.parse(byPath.get("plugins/claude/hooks/hooks.json")!.content.toString()).hooks;

  test("without the CLI on PATH the events the nudge script does not cover exit 0 silently", () => {
    for (const event of ["SessionEnd", "SubagentStart", "SubagentStop"]) {
      const result = spawnSync("/bin/sh", ["-c", hooksFile[event][0].hooks[0].command], { env: { PATH: "/usr/bin:/bin" }, input: "{}", encoding: "utf8" });
      assert.equal(result.status, 0, event);
      assert.equal(result.stdout + result.stderr, "", event);
    }
  });

  test("without the CLI the Stop hook runs the bundled nudge script from the plugin root, silently when nothing is owed", () => {
    const root = path.join(repoRoot, "plugins/claude");
    const result = spawnSync("/bin/sh", ["-c", command], {
      env: { PATH: "/usr/bin:/bin", CLAUDE_PLUGIN_ROOT: root, CLAUDE_PLUGIN_DATA: mkdtempSync(path.join(tmpdir(), "archdev-stop-")) },
      input: '{"session_id":"s"}',
      encoding: "utf8",
    });
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

describe("nudge script across harnesses", () => {
  const nudged = HARNESSES.filter((h) => harnessHooks(catalog, h)?.nudge);
  const scriptOf = (h: string) => byPath.get(`plugins/${h}/hooks/archdev-nudge.sh`);

  test("only the harnesses whose hook contract is verified ship it", () => {
    assert.deepEqual([...nudged].sort(), ["claude", "codex"]);
    for (const h of HARNESSES)
      assert.equal(Boolean(scriptOf(h)), nudged.includes(h), h);
  });

  test("every copy is the one rendered script: same bytes, all texts, no markers left", () => {
    const source = nudgeScriptSource(repoRoot);
    assert.ok(!source.includes("@@"));
    for (const text of Object.values(NUDGE_TEXT)) assert.ok(source.includes(text));
    for (const h of nudged) {
      assert.equal(scriptOf(h)!.content.toString("utf8"), source, h);
      assert.equal(scriptOf(h)!.mode, 0o755);
    }
  });

  test("a marker with no text, or a text with no marker, fails the build", () => {
    const dir = mkdtempSync(path.join(tmpdir(), "archdev-nudge-src-"));
    mkdirSync(path.join(dir, "tools/plugin-gen/assets"), { recursive: true });
    writeFileSync(path.join(dir, "tools/plugin-gen/assets/archdev-nudge.sh.in"), "echo @@nope@@\n");
    assert.throws(() => nudgeScriptSource(dir), /unknown text @@nope@@/);
    writeFileSync(path.join(dir, "tools/plugin-gen/assets/archdev-nudge.sh.in"), "echo hi\n");
    assert.throws(() => nudgeScriptSource(dir), /unused texts/);
  });

  test("harnesses without a verified contract keep the CLI-only hook command", () => {
    for (const h of ["grok", "pi"] as const) {
      const hooks = harnessHooks(catalog, h)!;
      assert.equal(hooks.nudge, undefined, h);
    }
    const grok = JSON.stringify(json("plugins/grok/hooks/hooks.json"));
    assert.ok(!grok.includes("archdev-nudge"));
    assert.ok(!JSON.stringify(json("plugins/pi/package.json")).includes("nudge"));
  });

  test("an invalid pluginRoot is reported", () => {
    const bad = structuredClone(catalog) as Catalog;
    (bad.harnesses.codex as { hooks: { nudge: { pluginRoot: string } } }).hooks.nudge.pluginRoot = "$(rm -rf /)";
    assert.ok(validateCatalog(bad).some((p) => /nudge.pluginRoot/.test(p)));
  });

  for (const [h, rootVar, dataVar] of [
    ["claude", "CLAUDE_PLUGIN_ROOT", "CLAUDE_PLUGIN_DATA"],
    ["codex", "PLUGIN_ROOT", "PLUGIN_DATA"],
  ] as const) {
    const hooksFile = () => json(`plugins/${h}/hooks/hooks.json`).hooks;
    const cmd = (event: string) => hooksFile()[event][0].hooks[0].command as string;
    const run = (event: string, input: unknown, extraPath = "") => {
      const data = mkdtempSync(path.join(tmpdir(), "archdev-nudge-data-"));
      const writeTo = mkdtempSync(path.join(tmpdir(), "archdev-nudge-root-"));
      writeFiles(writeTo, files.filter((f) => f.path.startsWith(`plugins/${h}/`)));
      const noCli = (process.env.PATH ?? "").split(path.delimiter).filter((d) => d && !existsSync(path.join(d, "archdev")));
      return spawnSync("/bin/sh", ["-c", cmd(event)], {
        env: { PATH: [extraPath, ...noCli].filter(Boolean).join(path.delimiter), [rootVar]: path.join(writeTo, `plugins/${h}`), [dataVar]: data },
        input: JSON.stringify(input),
        encoding: "utf8",
      });
    };

    test(`${h}: the hook command from hooks.json runs the bundled script from its documented plugin root`, () => {
      const r = run("SessionStart", { session_id: "abc", cwd: tmpdir(), hook_event_name: "SessionStart", source: "startup" });
      assert.equal(r.status, 0);
      const out = JSON.parse(r.stdout).hookSpecificOutput;
      assert.equal(out.hookEventName, "SessionStart");
      assert.match(out.additionalContext, /archdev_get_context/);
      assert.match(out.additionalContext, /"session_id":"abc"/);
    });

    test(`${h}: with the CLI on PATH every nudged event forwards to archdev and never runs the script`, () => {
      const bin = mkdtempSync(path.join(tmpdir(), "archdev-nudge-cli-"));
      writeFileSync(path.join(bin, "archdev"), '#!/bin/sh\nprintf "CLI:%s" "$*"\n');
      chmodSync(path.join(bin, "archdev"), 0o755);
      for (const event of ["SessionStart", "UserPromptSubmit", "PostToolUse", "Stop"]) {
        const r = run(event, { session_id: "abc", cwd: tmpdir() }, bin);
        assert.equal(r.status, 0, event);
        assert.match(r.stdout, new RegExp(`^CLI:repo hook [a-z-]+ --harness ${h} --spec ${catalog.hooks.spec}$`), event);
      }
    });

    test(`${h}: a failed or unrecognized payload through the hook command exits 0 silently`, () => {
      for (const event of ["SessionStart", "UserPromptSubmit", "PostToolUse", "Stop"]) {
        const r = run(event, "garbage");
        assert.equal(r.status, 0, event);
      }
      const r = run("PostToolUse", { session_id: "z", tool_name: "Read", tool_input: { file_path: "/x" } });
      assert.equal(r.stdout, "");
    });
  }
});
