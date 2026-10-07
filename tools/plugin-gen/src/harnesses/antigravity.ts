/**
 * Google Antigravity (2.0, IDE and `agy` CLI): a closed `plugin.json` with only
 * `$schema`, `name` and `description`, and `mcp_config.json` whose remote
 * servers use `serverUrl`. Antigravity has no SessionStart event, so no hooks
 * ship until the CLI handles its PreInvocation contract. No nudge: only
 * PreInvocation/PostInvocation `injectSteps` can add context, and the hook
 * input has no prompt text, shell command or MCP tool names
 * (https://antigravity.google/docs/hooks/).
 */
import { harnessHooks } from "../catalog.ts";
import { jsonFile, skillFiles, type GeneratedFile } from "../files.ts";
import type { Context } from "./index.ts";

export const root = "plugins/antigravity";

export function build({ repoRoot, catalog }: Context): GeneratedFile[] {
  if (harnessHooks(catalog, "antigravity"))
    throw new Error("antigravity hooks are not implemented in the generator");
  return [
    jsonFile(`${root}/plugin.json`, {
      $schema: "https://antigravity.google/schemas/v1/plugin.json",
      name: catalog.name,
      description: catalog.description,
    }),
    jsonFile(`${root}/mcp_config.json`, {
      mcpServers: { [catalog.mcp.name]: { serverUrl: catalog.mcp.url } },
    }),
    ...skillFiles(repoRoot, catalog, `${root}/skills`),
  ];
}
