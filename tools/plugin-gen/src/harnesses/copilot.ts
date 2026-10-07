/**
 * GitHub Copilot (CLI, VS Code, app): Agent Plugins 1.0.0. Copilot hooks would
 * live in `com.github.copilot/hooks/hooks.json`; the catalog ships none until
 * the CLI handles Copilot's payloads. No nudge: command hooks on
 * `userPromptSubmitted` have their output dropped, and the shell tool's input
 * keys and MCP tool names are undocumented
 * (https://docs.github.com/en/copilot/reference/hooks-configuration).
 */
import { harnessHooks } from "../catalog.ts";
import {
  agentPluginManifest,
  agentPluginMcp,
  jsonFile,
  skillFiles,
  type GeneratedFile,
} from "../files.ts";
import type { Context } from "./index.ts";

export const root = "plugins/copilot";

export function build({ repoRoot, catalog }: Context): GeneratedFile[] {
  if (harnessHooks(catalog, "copilot"))
    throw new Error("copilot hooks are not implemented in the generator");
  return [
    jsonFile(`${root}/plugin.json`, agentPluginManifest(catalog)),
    jsonFile(`${root}/mcp.json`, agentPluginMcp(catalog)),
    ...skillFiles(repoRoot, catalog, `${root}/skills`),
  ];
}
