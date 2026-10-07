import { execFileSync } from "node:child_process";
import { readFileSync } from "node:fs";
import path from "node:path";
import { NUDGE_TEXT } from "./nudge-text.ts";
import { hookTimeout, type Catalog, type HarnessHooks, type HookEvent } from "./catalog.ts";

/** One file the generator owns, at a repository-relative POSIX path. */
export interface GeneratedFile {
  path: string;
  content: Buffer;
  mode: 0o644 | 0o755;
}

export function jsonFile(file: string, value: unknown): GeneratedFile {
  return textFile(file, `${JSON.stringify(value, null, 2)}\n`);
}

export function textFile(file: string, text: string): GeneratedFile {
  return { path: file, content: Buffer.from(text, "utf8"), mode: 0o644 };
}

/**
 * Copies each catalog skill into `<prefix>/<skill name>/`. Only files git
 * tracks are copied, so untracked editor or OS files never reach a plugin and
 * the output is the same on every checkout.
 */
export function skillFiles(
  repoRoot: string,
  catalog: Catalog,
  prefix: string,
): GeneratedFile[] {
  return catalog.skills.flatMap((skill) =>
    trackedFiles(repoRoot, skill.path).map(({ file, mode }) => ({
      path: `${prefix}/${skill.name}/${file}`,
      content: readFileSync(path.join(repoRoot, skill.path, file)),
      mode,
    })),
  );
}

function trackedFiles(
  repoRoot: string,
  dir: string,
): { file: string; mode: 0o644 | 0o755 }[] {
  const listing = execFileSync(
    "git",
    ["ls-files", "--stage", "-z", "--", `${dir}/`],
    { cwd: repoRoot, encoding: "utf8" },
  );
  const files = listing
    .split("\0")
    .filter(Boolean)
    .map((entry) => {
      // "<mode> <object> <stage>\t<path>"
      const [meta, file] = entry.split("\t") as [string, string];
      return {
        file: file.slice(dir.length + 1),
        mode: meta.startsWith("100755") ? (0o755 as const) : (0o644 as const),
      };
    })
    .sort((a, b) => (a.file < b.file ? -1 : a.file > b.file ? 1 : 0));
  if (!files.some(({ file }) => file === "SKILL.md"))
    throw new Error(`${dir}/SKILL.md is not tracked by git`);
  return files;
}

/** `archdev repo hook <action> --harness <h> --spec <n>`, the CLI's own shape. */
export function hookCommand(
  catalog: Catalog,
  hooks: HarnessHooks,
  event: HookEvent,
): string {
  const { action } = catalog.hooks.events[event];
  return `${catalog.hooks.command} ${action} --harness ${hooks.harness} --spec ${catalog.hooks.spec}`;
}

/**
 * Plugin hooks run the CLI from PATH. Without it they exit 0, so a plugin
 * installed before the CLI never shows a hook error. At session start they
 * also print the catalog's missing-CLI guidance, which reaches the agent as
 * session context: the one moment a plugin-only user can be offered the CLI,
 * with the user's approval, before the session's work happens. The other
 * events stay silent.
 */
export function guardedHookCommand(
  catalog: Catalog,
  hooks: HarnessHooks,
  event: HookEvent,
): string {
  if (hooks.nudge && NUDGE_EVENTS.includes(event))
    return nudgeHookCommand(catalog, hooks, event);
  const missing =
    event === "sessionStart"
      ? `{ printf '%s\\n' ${shellQuote(catalog.hooks.missingCliGuidance)}; exit 0; }`
      : "exit 0";
  return `command -v archdev >/dev/null 2>&1 || ${missing}; exec ${hookCommand(catalog, hooks, event)}`;
}

/** Events whose hooks fall back to the nudge script when there is no CLI. */
export const NUDGE_EVENTS: readonly HookEvent[] = ["sessionStart", "promptSubmit", "toolUse", "stop"];

/** Where the generated plugin keeps the nudge script, relative to its root. */
export const NUDGE_SCRIPT = "hooks/archdev-nudge.sh";

/**
 * With the CLI on PATH the hook is exactly the CLI's. Without it the bundled
 * nudge script reads the same hook JSON and tells the model which ArchDev MCP
 * tool to call. The CLI branch exits first, so nothing is reported twice.
 */
export function nudgeHookCommand(
  catalog: Catalog,
  hooks: HarnessHooks,
  event: HookEvent,
): string {
  const { action } = catalog.hooks.events[event];
  return `if command -v archdev >/dev/null 2>&1; then exec ${hookCommand(catalog, hooks, event)}; fi; exec sh "${hooks.nudge!.pluginRoot}/${NUDGE_SCRIPT}" ${action}`;
}

/**
 * The nudge script every harness plugin bundles: the template with each
 * `@@name@@` marker replaced by its text from `nudge-text.ts`, so no harness
 * can carry different words. A leftover or unknown marker is a build error.
 */
export function nudgeScriptSource(repoRoot: string): string {
  const template = readFileSync(
    path.join(repoRoot, "tools/plugin-gen/assets/archdev-nudge.sh.in"),
    "utf8",
  );
  const text = NUDGE_TEXT as Record<string, string>;
  const used = new Set<string>();
  const source = template.replace(/@@(\w+)@@/g, (_, name: string) => {
    if (!(name in text)) throw new Error(`archdev-nudge.sh.in uses unknown text @@${name}@@`);
    used.add(name);
    return text[name]!;
  });
  const unused = Object.keys(text).filter((name) => !used.has(name));
  if (unused.length > 0) throw new Error(`nudge-text.ts has unused texts: ${unused.join(", ")}`);
  return source;
}

export function nudgeScriptFile(repoRoot: string, root: string): GeneratedFile {
  return {
    path: `${root}/${NUDGE_SCRIPT}`,
    content: Buffer.from(nudgeScriptSource(repoRoot), "utf8"),
    mode: 0o755,
  };
}

/** POSIX single-quoted word. */
export function shellQuote(text: string): string {
  return `'${text.replaceAll("'", `'\\''`)}'`;
}

/** Event names Claude Code, Codex and Grok share. */
export const PASCAL_EVENTS: Record<HookEvent, string> = {
  sessionStart: "SessionStart",
  promptSubmit: "UserPromptSubmit",
  toolUse: "PostToolUse",
  stop: "Stop",
  subagentStart: "SubagentStart",
  subagentStop: "SubagentStop",
  sessionEnd: "SessionEnd",
};

/**
 * The `{ hooks: { Event: [group] } }` file Claude Code, Codex and Grok read:
 * one group per event, with a tool-name matcher on the tool event only.
 */
export function pascalHooksFile(
  catalog: Catalog,
  hooks: HarnessHooks,
): { hooks: Record<string, unknown[]> } {
  const out: Record<string, unknown[]> = {};
  for (const event of hooks.events) {
    out[PASCAL_EVENTS[event]] = [
      {
        ...(event === "toolUse" ? { matcher: hooks.toolMatcher } : {}),
        hooks: [
          {
            type: "command",
            command: guardedHookCommand(catalog, hooks, event),
            timeout: hookTimeout(catalog, hooks, event),
          },
        ],
      },
    ];
  }
  return { hooks: out };
}

/** Agent Plugins 1.0.0, the only version Codex accepts. */
export const AGENT_PLUGINS_SCHEMA =
  "https://agent-plugins.org/schemas/1.0.0/plugin.schema.json";
export const AGENT_PLUGINS_MCP_SCHEMA =
  "https://agent-plugins.org/schemas/1.0.0/mcp.schema.json";

/** Closed Agent Plugins 1.0.0 manifest: no component paths are allowed. */
export function agentPluginManifest(
  catalog: Catalog,
  extensions?: Record<string, unknown>,
): Record<string, unknown> {
  return {
    $schema: AGENT_PLUGINS_SCHEMA,
    name: catalog.name,
    version: catalog.version,
    description: catalog.description,
    author: catalog.author,
    homepage: catalog.homepage,
    repository: catalog.repository,
    license: catalog.license,
    keywords: catalog.keywords,
    ...(extensions ? { extensions } : {}),
  };
}

export function agentPluginMcp(catalog: Catalog): Record<string, unknown> {
  return {
    $schema: AGENT_PLUGINS_MCP_SCHEMA,
    mcpServers: {
      [catalog.mcp.name]: { type: "streamable-http", url: catalog.mcp.url },
    },
  };
}

/** Claude-format manifest fields Claude Code and Grok read. */
export function claudeManifest(catalog: Catalog): Record<string, unknown> {
  return {
    name: catalog.name,
    displayName: catalog.displayName,
    version: catalog.version,
    description: catalog.description,
    author: catalog.author,
    homepage: catalog.homepage,
    repository: catalog.repository,
    license: catalog.license,
    keywords: catalog.keywords,
  };
}

/**
 * Claude Code expands `${VAR:-default}` in `.mcp.json`, so the server URL
 * follows ARCHDEV_MCP_URL when it is set (a self-hosted or staging gateway)
 * and is the catalog's URL otherwise.
 */
export function claudeMcp(catalog: Catalog): Record<string, unknown> {
  return {
    mcpServers: {
      [catalog.mcp.name]: {
        type: "http",
        url: `\${ARCHDEV_MCP_URL:-${catalog.mcp.url}}`,
      },
    },
  };
}
