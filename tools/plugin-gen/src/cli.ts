/**
 * `node src/cli.ts build` regenerates every plugin from catalog/archdev.json;
 * `node src/cli.ts check` exits 1 when the committed plugins differ from what
 * the catalog produces. Both run from any directory inside the repository.
 */
import { execFileSync } from "node:child_process";
import path from "node:path";
import { loadCatalog } from "./catalog.ts";
import { diffFiles, generate, writeFiles } from "./generate.ts";

const command = process.argv[2];
const repoRoot = execFileSync("git", ["rev-parse", "--show-toplevel"], {
  encoding: "utf8",
}).trim();
const catalog = loadCatalog(path.join(repoRoot, "catalog", "archdev.json"));
const files = generate(repoRoot, catalog);

if (command === "build") {
  writeFiles(repoRoot, files);
  console.log(`Generated ${files.length} files for ${catalog.name} ${catalog.version}.`);
} else if (command === "check") {
  const problems = diffFiles(repoRoot, files);
  if (problems.length > 0) {
    console.error(
      `Generated plugins are out of date with catalog/archdev.json. Run \`npm run build\` in tools/plugin-gen.\n${problems.map((p) => `  ${p}`).join("\n")}`,
    );
    process.exitCode = 1;
  } else console.log(`${files.length} generated files match the catalog.`);
} else {
  console.error("usage: node src/cli.ts build|check");
  process.exitCode = 2;
}
