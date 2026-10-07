/**
 * Codex: the native `.codex-plugin/plugin.json` naming its skills, MCP and
 * hooks files. Codex 0.160 loads skills and MCP from an Agent Plugins root
 * `plugin.json` but never registers its hooks, and a root `plugin.json` would
 * take precedence over this manifest, so the Codex plugin has none.
 * Codex registers plugin hooks only after the user trusts them in `/hooks`.
 *
 * Without the CLI its hooks run the bundled nudge script. Contract relied on
 * (https://developers.openai.com/codex/hooks): snake_case stdin with
 * `tool_input.command` for Bash, `hookSpecificOutput.additionalContext` out,
 * `{"decision":"block"}` on Stop, plugin root in `PLUGIN_ROOT`. apply_patch has
 * no documented file-path key, so plan-file edits are not nudged on Codex.
 */
import { harnessHooks } from "../catalog.ts";
import {
  agentPluginMcp,
  jsonFile,
  nudgeScriptFile,
  pascalHooksFile,
  skillFiles,
  type GeneratedFile,
} from "../files.ts";
import type { Context } from "./index.ts";

export const root = "plugins/codex";

export function build({ repoRoot, catalog }: Context): GeneratedFile[] {
  const hooks = harnessHooks(catalog, "codex");
  return [
    jsonFile(`${root}/.codex-plugin/plugin.json`, {
      name: catalog.name,
      version: catalog.version,
      description: catalog.description,
      keywords: catalog.keywords,
      skills: "./skills/",
      mcpServers: "./mcp.json",
      ...(hooks ? { hooks: "./hooks/hooks.json" } : {}),
      interface: {
        displayName: catalog.displayName,
        shortDescription: catalog.description,
        developerName: catalog.author.name,
        category: catalog.category,
        websiteUrl: catalog.homepage,
      },
    }),
    jsonFile(`${root}/mcp.json`, agentPluginMcp(catalog)),
    ...(hooks
      ? [jsonFile(`${root}/hooks/hooks.json`, pascalHooksFile(catalog, hooks))]
      : []),
    ...(hooks?.nudge ? [nudgeScriptFile(repoRoot, root)] : []),
    ...skillFiles(repoRoot, catalog, `${root}/skills`),
  ];
}
