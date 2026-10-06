/** Claude Code: `.claude-plugin/plugin.json`, `.mcp.json`, `hooks/hooks.json`. */
import { harnessHooks } from "../catalog.ts";
import {
  claudeManifest,
  claudeMcp,
  jsonFile,
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
    ...skillFiles(repoRoot, catalog, `${root}/skills`),
  ];
}
