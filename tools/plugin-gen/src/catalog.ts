/**
 * The harness-agnostic catalog: what ArchDev ships (skills, the remote MCP
 * server, hook wiring) and which harnesses get hooks. Harness adapters own
 * how each harness spells it.
 */
import { readFileSync } from "node:fs";

export const HOOK_EVENTS = [
  "sessionStart",
  "promptSubmit",
  "toolUse",
  "stop",
  "subagentStart",
  "subagentStop",
  "sessionEnd",
] as const;
export type HookEvent = (typeof HOOK_EVENTS)[number];

export const HARNESSES = [
  "claude",
  "codex",
  "copilot",
  "cursor",
  "antigravity",
  "grok",
  "opencode",
  "pi",
] as const;
export type Harness = (typeof HARNESSES)[number];

export interface Skill {
  name: string;
  /** Skill directory, relative to the repository root. */
  path: string;
}

export interface HarnessHooks {
  /** Value passed to `archdev repo hook <action> --harness <harness>`. */
  harness: string;
  events: HookEvent[];
  /** Tool-name regex for the toolUse event. */
  toolMatcher: string;
  /** Per-event timeouts in seconds that replace the catalog defaults. */
  timeouts?: Partial<Record<HookEvent, number>>;
}

export type HarnessEntry =
  | { hooks: HarnessHooks }
  | { hooksUnsupported: string };

export interface Catalog {
  name: string;
  displayName: string;
  version: string;
  description: string;
  author: { name: string; url: string };
  homepage: string;
  repository: string;
  license: string;
  keywords: string[];
  category: string;
  skills: Skill[];
  mcp: { name: string; url: string; auth: "oauth" };
  hooks: {
    command: string;
    spec: number;
    /** Context for the agent when a code-based hook finds no CLI. */
    missingCliGuidance: string;
    events: Record<HookEvent, { action: string; timeout: number }>;
  };
  harnesses: Record<Harness, HarnessEntry>;
}

/** Agent Plugins 1.0.0 name rule; the strictest of every harness's rules. */
const NAME = /^(?!.*(?:--|\.\.))[a-z0-9](?:[a-z0-9.-]*[a-z0-9])?$/;
const SEMVER = /^\d+\.\d+\.\d+(?:-[0-9A-Za-z.-]+)?$/;

export function loadCatalog(file: string): Catalog {
  const catalog = JSON.parse(readFileSync(file, "utf8")) as Catalog;
  const problems = validateCatalog(catalog);
  if (problems.length > 0)
    throw new Error(`${file} is invalid:\n- ${problems.join("\n- ")}`);
  return catalog;
}

export function validateCatalog(catalog: Catalog): string[] {
  const problems: string[] = [];
  if (!NAME.test(catalog.name) || catalog.name.length > 64)
    problems.push(`name "${catalog.name}" must match ${NAME}`);
  if (!SEMVER.test(catalog.version))
    problems.push(`version "${catalog.version}" is not semver`);
  const skillNames = new Set<string>();
  for (const skill of catalog.skills) {
    if (!NAME.test(skill.name) || skill.name.length > 64)
      problems.push(`skill "${skill.name}" must match ${NAME}`);
    if (skillNames.has(skill.name))
      problems.push(`skill "${skill.name}" is listed twice`);
    skillNames.add(skill.name);
    if (skill.path.startsWith("/") || skill.path.split("/").includes(".."))
      problems.push(`skill "${skill.name}" path must stay inside the repo`);
  }
  const url = URL.parse(catalog.mcp.url);
  if (url?.protocol !== "https:")
    problems.push(`mcp.url "${catalog.mcp.url}" must be https`);
  if (!Number.isInteger(catalog.hooks.spec) || catalog.hooks.spec < 1)
    problems.push("hooks.spec must be a positive integer");
  for (const event of HOOK_EVENTS) {
    const wiring = catalog.hooks.events[event];
    if (!wiring) problems.push(`hooks.events.${event} is missing`);
    else if (!/^[a-z-]+$/.test(wiring.action))
      problems.push(`hooks.events.${event}.action must be a bare word`);
    else if (!Number.isInteger(wiring.timeout) || wiring.timeout < 1)
      problems.push(`hooks.events.${event}.timeout must be whole seconds`);
  }
  for (const harness of HARNESSES) {
    const entry = catalog.harnesses[harness];
    if (!entry) {
      problems.push(`harnesses.${harness} is missing`);
      continue;
    }
    if ("hooksUnsupported" in entry) continue;
    if (!/^[a-z]+$/.test(entry.hooks.harness))
      problems.push(`harnesses.${harness}.hooks.harness must be a bare word`);
    for (const event of entry.hooks.events)
      if (!HOOK_EVENTS.includes(event))
        problems.push(`harnesses.${harness}.hooks.events has unknown "${event}"`);
    for (const [event, seconds] of Object.entries(entry.hooks.timeouts ?? {}))
      if (!HOOK_EVENTS.includes(event as HookEvent) || !Number.isInteger(seconds) || seconds < 1)
        problems.push(`harnesses.${harness}.hooks.timeouts.${event} must be whole seconds for a known event`);
    try {
      new RegExp(entry.hooks.toolMatcher);
    } catch {
      problems.push(`harnesses.${harness}.hooks.toolMatcher is not a regex`);
    }
  }
  for (const harness of Object.keys(catalog.harnesses))
    if (!(HARNESSES as readonly string[]).includes(harness))
      problems.push(`harnesses.${harness} has no generator adapter`);
  return problems;
}

/** The hook wiring for a harness, or undefined when it ships without hooks. */
export function harnessHooks(
  catalog: Catalog,
  harness: Harness,
): HarnessHooks | undefined {
  const entry = catalog.harnesses[harness];
  return "hooks" in entry ? entry.hooks : undefined;
}

/** Seconds a harness gives the CLI for one event. */
export function hookTimeout(
  catalog: Catalog,
  hooks: HarnessHooks,
  event: HookEvent,
): number {
  return hooks.timeouts?.[event] ?? catalog.hooks.events[event].timeout;
}
