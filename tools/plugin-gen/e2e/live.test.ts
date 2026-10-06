/**
 * Installs each generated plugin with the real harness CLI and checks what the
 * harness reports it loaded. Every harness runs against throwaway HOME and
 * config directories, and hook runs use a fake `archdev` on PATH, so nothing
 * touches the developer's own setup or posts to an ArchDev stream.
 *
 * A harness whose CLI is not on PATH is skipped. CI runners carry none of
 * these CLIs; run `npm run e2e` locally before releasing a plugin change.
 */
import assert from "node:assert/strict";
import { execFileSync, spawnSync } from "node:child_process";
import {
  chmodSync,
  existsSync,
  mkdirSync,
  mkdtempSync,
  readFileSync,
  writeFileSync,
} from "node:fs";
import { tmpdir } from "node:os";
import path from "node:path";
import { test } from "node:test";
import { loadCatalog } from "../src/catalog.ts";

const repoRoot = execFileSync("git", ["rev-parse", "--show-toplevel"], {
  encoding: "utf8",
}).trim();
const catalog = loadCatalog(path.join(repoRoot, "catalog", "archdev.json"));
const skillNames = catalog.skills.map((skill) => skill.name);

function installed(cli: string): boolean {
  return spawnSync("sh", ["-c", `command -v ${cli}`]).status === 0;
}

/** A throwaway HOME plus a fake `archdev` that logs each hook call. */
function sandbox() {
  const home = mkdtempSync(path.join(tmpdir(), "archdev-plugin-e2e-"));
  const bin = path.join(home, "bin");
  const log = path.join(home, "archdev-calls.log");
  mkdirSync(bin);
  writeFileSync(
    path.join(bin, "archdev"),
    `#!/bin/sh\ncat >/dev/null\nprintf '%s\\n' "$*" >> '${log}'\necho '{}'\n`,
  );
  chmodSync(path.join(bin, "archdev"), 0o755);
  const project = path.join(home, "project");
  mkdirSync(project);
  execFileSync("git", ["init", "-q"], { cwd: project });
  const env = { ...process.env, HOME: home, PATH: `${bin}:${process.env.PATH}` };
  const run = (cmd: string, args: string[], extra: Record<string, string> = {}) => {
    const result = spawnSync(cmd, args, {
      cwd: project,
      env: { ...env, ...extra },
      encoding: "utf8",
      input: "",
      timeout: 120_000,
    });
    return `${result.stdout}${result.stderr}`;
  };
  const calls = () => (existsSync(log) ? readFileSync(log, "utf8").trim().split("\n") : []);
  return { home, run, calls };
}

test("Claude Code installs skills, MCP and every hook from the marketplace", { skip: !installed("claude") }, () => {
  const { home, run, calls } = sandbox();
  const env = { CLAUDE_CONFIG_DIR: path.join(home, ".claude") };

  // The marketplace at the repository root resolves ./plugins/claude.
  assert.match(run("claude", ["plugin", "validate", "--strict", repoRoot], env), /Validation passed/);
  run("claude", ["plugin", "marketplace", "add", repoRoot], env);
  assert.match(run("claude", ["plugin", "install", "archdev@archdev"], env), /Successfully installed/);

  // Claude's own inventory is the observable proof of what loaded.
  const details = run("claude", ["plugin", "details", "archdev@archdev"], env);
  assert.match(details, new RegExp(`Skills \\(${skillNames.length}\\)\\s+${skillNames.join(", ")}`));
  assert.match(details, /MCP servers \(1\)\s+archdev/);
  assert.match(details, /Hooks \(7\)\s+SessionStart, SessionEnd, UserPromptSubmit, PostToolUse, Stop, SubagentStart, SubagentStop/);

  // A headless run with a bad API key never reaches a model, but the session
  // still starts, takes the prompt and ends: the plugin's hooks call the CLI.
  run("claude", ["-p", "say hi", "--max-turns", "1"], { ...env, ANTHROPIC_API_KEY: "invalid" });
  assert.deepEqual(calls(), [
    `repo hook start --harness claude --spec ${catalog.hooks.spec}`,
    `repo hook prompt --harness claude --spec ${catalog.hooks.spec}`,
    `repo hook end --harness claude --spec ${catalog.hooks.spec}`,
  ]);
});

test("Codex installs the plugin, lists its MCP server, and runs its hooks once trusted", { skip: !installed("codex") }, () => {
  const { home, run, calls } = sandbox();
  const env = { CODEX_HOME: path.join(home, ".codex") };
  mkdirSync(env.CODEX_HOME);

  // Codex finds .agents/plugins/marketplace.json before the Claude one.
  assert.match(run("codex", ["plugin", "marketplace", "add", repoRoot], env), /Added marketplace `archdev`/);
  assert.match(run("codex", ["plugin", "add", "archdev@archdev"], env), /Added plugin `archdev`/);
  assert.match(run("codex", ["mcp", "list"], env), new RegExp(`archdev\\s+${catalog.mcp.url.replaceAll(".", "\\.")}`));

  // Untrusted plugin hooks never run. The model call fails without
  // credentials, but SessionStart and UserPromptSubmit fire before it.
  run("codex", ["exec", "--skip-git-repo-check", "say hi"], env);
  assert.deepEqual(calls(), []);

  // Trusted (bypassed here; users approve in /hooks), the plugin's hooks call
  // the CLI with Codex's harness name and the catalog's spec.
  run("codex", ["exec", "--dangerously-bypass-hook-trust", "--skip-git-repo-check", "say hi"], env);
  assert.deepEqual(calls(), [
    `repo hook start --harness codex --spec ${catalog.hooks.spec}`,
    `repo hook prompt --harness codex --spec ${catalog.hooks.spec}`,
  ]);
});

test("Copilot CLI installs its plugin from .github/plugin with skills and MCP", { skip: !installed("npx") }, () => {
  const { home, run } = sandbox();
  const env = { COPILOT_HOME: path.join(home, ".copilot"), XDG_CONFIG_HOME: path.join(home, ".config") };
  const copilot = (...args: string[]) => run("npx", ["-y", "@github/copilot", ...args], env);

  // Copilot reads .github/plugin/marketplace.json before the Claude one.
  assert.match(copilot("plugin", "marketplace", "add", repoRoot), /Marketplace "archdev" added/);
  assert.match(copilot("plugin", "install", "archdev@archdev"), new RegExp(`Installed ${skillNames.length} skills`));
  assert.match(copilot("plugin", "list", "--json"), /"installedFrom": ".*"/);
  assert.match(copilot("mcp", "list"), /Plugin servers:\s+archdev \(http\)/);
});

test("Grok validates and installs its plugin with hooks and MCP", { skip: !installed("grok") }, () => {
  const { home, run } = sandbox();
  const env = { GROK_HOME: path.join(home, ".grok") };
  const plugin = path.join(repoRoot, "plugins", "grok");

  assert.match(run("grok", ["plugin", "validate", plugin], env), /components: 1 skill dir\(s\).*hooks, MCP servers/);
  run("grok", ["plugin", "install", plugin, "--trust"], env);
  const details = run("grok", ["plugin", "details", "archdev"], env);
  assert.match(details, new RegExp(`archdev v${catalog.version.replaceAll(".", "\\.")}`));
  assert.match(details, /components: 1 skill dir\(s\).*hooks, MCP servers/);
});

test("Antigravity validates and installs its plugin with skills and MCP", { skip: !installed("agy") }, () => {
  const { run } = sandbox();
  const plugin = path.join(repoRoot, "plugins", "antigravity");

  const validated = run("agy", ["plugin", "validate", plugin]);
  assert.match(validated, new RegExp(`skills\\s+: ${skillNames.length} processed`));
  assert.match(validated, /mcpServers\s+: 1 processed/);
  run("agy", ["plugin", "install", plugin]);
  assert.match(run("agy", ["plugin", "list"]), /archdev/);
});

test("Pi installs the package from the repository root and its extension calls the CLI", { skip: !installed("pi") }, () => {
  const { home, run, calls } = sandbox();
  const env = { PI_CODING_AGENT_DIR: path.join(home, ".pi", "agent") };

  // The root package.json is what `pi install git:github.com/ArchAstro/archdev@<tag>` reads.
  run("pi", ["install", repoRoot], env);
  assert.match(run("pi", ["list"], env), new RegExp(repoRoot.replaceAll("/", "\\/")));

  // A headless turn with a bad API key starts, prompts and shuts down the
  // session, so the extension forwards those three events.
  run("pi", ["-p", "say hi"], { ...env, ANTHROPIC_API_KEY: "invalid" });
  assert.deepEqual(
    calls().map((line) => line.replace(/ --payload .*$/, "")),
    ["start", "prompt", "end"].map((action) => `repo hook ${action} --harness pi --spec ${catalog.hooks.spec}`),
  );
});

test("npx skills still finds exactly the catalog's skills, not the plugin copies", { skip: !installed("npx") }, () => {
  const { run } = sandbox();
  const listing = run("npx", ["-y", "skills", "add", repoRoot, "--list"]);
  assert.match(listing, new RegExp(`Found ${skillNames.length} skills`));
});

test("OpenCode's config hook adds the skills directory and the MCP server", { skip: !installed("opencode") }, () => {
  const { home, run } = sandbox();
  const plugin = path.join(repoRoot, "plugins", "opencode", "index.js");
  const config = path.join(home, "project", "opencode.json");
  writeFileSync(config, JSON.stringify({ $schema: "https://opencode.ai/config.json", plugin: [`file://${plugin}`] }));
  const env = { XDG_CONFIG_HOME: path.join(home, ".config"), XDG_DATA_HOME: path.join(home, ".local", "share"), XDG_CACHE_HOME: path.join(home, ".cache") };

  // `opencode debug config` prints the resolved config after plugins run.
  const resolved = run("opencode", ["debug", "config"], env);
  assert.match(resolved, new RegExp(path.join(repoRoot, "plugins", "opencode", "skills").replaceAll("/", "\\/")));
  assert.match(resolved, new RegExp(`"url": "${catalog.mcp.url.replaceAll(".", "\\.")}"`));
});
