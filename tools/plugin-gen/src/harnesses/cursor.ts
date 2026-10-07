/**
 * Cursor: `.cursor-plugin/plugin.json` naming its component paths, and a
 * `mcp.json` whose remote servers take a bare `url`. Cursor hooks would use a
 * camelCase `{ version: 1, hooks }` file; none ship until the CLI handles them.
 * No nudge: `beforeSubmitPrompt` cannot inject context, and the shell tool's
 * `tool_input` keys are undocumented (https://cursor.com/docs/hooks).
 */
import { harnessHooks } from "../catalog.ts";
import { jsonFile, skillFiles, type GeneratedFile } from "../files.ts";
import type { Context } from "./index.ts";

export const root = "plugins/cursor";

export function build({ repoRoot, catalog }: Context): GeneratedFile[] {
  if (harnessHooks(catalog, "cursor"))
    throw new Error("cursor hooks are not implemented in the generator");
  return [
    jsonFile(`${root}/.cursor-plugin/plugin.json`, {
      name: catalog.name,
      displayName: catalog.displayName,
      version: catalog.version,
      description: catalog.description,
      author: { name: catalog.author.name },
      homepage: catalog.homepage,
      repository: catalog.repository,
      license: catalog.license,
      keywords: catalog.keywords,
      skills: "./skills/",
      mcpServers: "./mcp.json",
    }),
    jsonFile(`${root}/mcp.json`, {
      mcpServers: { [catalog.mcp.name]: { url: catalog.mcp.url } },
    }),
    ...skillFiles(repoRoot, catalog, `${root}/skills`),
  ];
}
