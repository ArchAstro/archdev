/**
 * Claude Code: `.claude-plugin/plugin.json`, `.mcp.json`, `hooks/hooks.json`.
 * Without the CLI its hooks run the bundled nudge script. Contract relied on
 * (https://code.claude.com/docs/en/hooks): stdout is added as context for
 * SessionStart and UserPromptSubmit, `hookSpecificOutput.additionalContext`
 * for PostToolUse, `{"decision":"block"}` for Stop, `CLAUDE_PLUGIN_ROOT` and
 * `CLAUDE_PLUGIN_DATA` in the hook environment.
 */
import { harnessHooks } from "../catalog.ts";
import {
  claudeManifest,
  claudeMcp,
  jsonFile,
  nudgeScriptFile,
  pascalHooksFile,
  skillFiles,
  type GeneratedFile,
} from "../files.ts";
import type { Context } from "./index.ts";

export const root = "plugins/claude";

export function build({ repoRoot, catalog }: Context): GeneratedFile[] {
  const hooks = harnessHooks(catalog, "claude");
  return [
    jsonFile(`${root}/.claude-plugin/plugin.json`, claudeManifest(catalog)),
    jsonFile(`${root}/.mcp.json`, claudeMcp(catalog)),
    ...(hooks
      ? [jsonFile(`${root}/hooks/hooks.json`, pascalHooksFile(catalog, hooks))]
      : []),
    ...(hooks?.nudge ? [nudgeScriptFile(repoRoot, root)] : []),
    ...skillFiles(repoRoot, catalog, `${root}/skills`),
  ];
}
