/**
 * Marketplace catalogs at the repository root. Each harness looks for its own
 * file before `.claude-plugin/marketplace.json`, so one repository serves
 * every harness its own plugin root:
 *
 * - Codex: `.agents/plugins/` first, then `.claude-plugin/`, `.cursor-plugin/`.
 * - Copilot: `.github/plugin/` before `.claude-plugin/`.
 * - Cursor: `.cursor-plugin/`. Grok: `.grok-plugin/`. Claude: `.claude-plugin/`.
 *
 * Plugin sources are relative paths, so a marketplace added at a tag installs
 * the plugin from that same tag.
 */
import type { Catalog } from "./catalog.ts";
import { jsonFile, type GeneratedFile } from "./files.ts";
import * as claude from "./harnesses/claude.ts";
import * as codex from "./harnesses/codex.ts";
import * as copilot from "./harnesses/copilot.ts";
import * as cursor from "./harnesses/cursor.ts";
import * as grok from "./harnesses/grok.ts";

export function marketplaceFiles(catalog: Catalog): GeneratedFile[] {
  const owner = { name: catalog.author.name, url: catalog.author.url };
  const metadata = { description: catalog.description, version: catalog.version };
  const entry = (root: string) => ({
    name: catalog.name,
    source: `./${root}`,
    description: catalog.description,
    version: catalog.version,
    category: catalog.category,
  });
  return [
    jsonFile(".claude-plugin/marketplace.json", {
      name: catalog.name,
      owner,
      metadata,
      plugins: [entry(claude.root)],
    }),
    jsonFile(".grok-plugin/marketplace.json", {
      name: catalog.name,
      owner,
      metadata,
      plugins: [entry(grok.root)],
    }),
    jsonFile(".github/plugin/marketplace.json", {
      name: catalog.name,
      owner,
      metadata,
      plugins: [entry(copilot.root)],
    }),
    jsonFile(".cursor-plugin/marketplace.json", {
      name: catalog.name,
      owner: { name: catalog.author.name },
      metadata: { description: catalog.description },
      plugins: [
        { name: catalog.name, source: cursor.root, description: catalog.description },
      ],
    }),
    jsonFile(".agents/plugins/marketplace.json", {
      name: catalog.name,
      interface: { displayName: catalog.displayName },
      plugins: [
        {
          name: catalog.name,
          source: { source: "local", path: `./${codex.root}` },
          policy: { installation: "AVAILABLE", authentication: "ON_USE" },
          category: catalog.category,
        },
      ],
    }),
  ];
}
