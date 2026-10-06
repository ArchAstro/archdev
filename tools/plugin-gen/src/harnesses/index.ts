import type { Catalog, Harness } from "../catalog.ts";
import type { GeneratedFile } from "../files.ts";
import * as antigravity from "./antigravity.ts";
import * as claude from "./claude.ts";
import * as codex from "./codex.ts";
import * as copilot from "./copilot.ts";
import * as cursor from "./cursor.ts";
import * as grok from "./grok.ts";
import * as opencode from "./opencode.ts";
import * as pi from "./pi.ts";

export interface Context {
  repoRoot: string;
  catalog: Catalog;
}

export interface Adapter {
  root: string;
  build(context: Context): GeneratedFile[];
}

export const ADAPTERS: Record<Harness, Adapter> = {
  claude,
  codex,
  copilot,
  cursor,
  antigravity,
  grok,
  opencode,
  pi,
};
