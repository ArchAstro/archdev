/**
 * Grok's hook docs (https://docs.x.ai/build/features/hooks) show camelCase input and do not document plugin-bundled hooks, context injection or a plugin-root variable, so the nudge is not wired.
 * Grok Build reads the Claude plugin layout. It gets its own copy so its hooks
 * pass `--harness grok`: the CLI ignores a `--harness claude` callback that
 * Grok runs, because Grok also imports Claude's own settings hooks.
 */
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

export const root = "plugins/grok";

export function build({ repoRoot, catalog }: Context): GeneratedFile[] {
  const hooks = harnessHooks(catalog, "grok");
  return [
    jsonFile(`${root}/.claude-plugin/plugin.json`, claudeManifest(catalog)),
    jsonFile(`${root}/.mcp.json`, claudeMcp(catalog)),
    ...(hooks
      ? [jsonFile(`${root}/hooks/hooks.json`, pascalHooksFile(catalog, hooks))]
      : []),
    ...skillFiles(repoRoot, catalog, `${root}/skills`),
  ];
}
