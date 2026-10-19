import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { mkdtempSync, mkdirSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import path from "node:path";
import { after, test } from "node:test";
import { fileURLToPath } from "node:url";

const repoRoot = fileURLToPath(new URL("../../../", import.meta.url));
const script = path.join(repoRoot, "scripts/opencode-release-version.mjs");
const scratch = mkdtempSync(path.join(tmpdir(), "archdev-opencode-release-"));
after(() => rmSync(scratch, { recursive: true, force: true }));

function fixture(packageVersion = "0.49.7", catalogVersion = "0.49.7", name = "@archastro/archdev-opencode") {
  const root = mkdtempSync(path.join(scratch, "fixture-"));
  mkdirSync(path.join(root, "catalog"));
  mkdirSync(path.join(root, "plugins/opencode/skills"), { recursive: true });
  writeFileSync(path.join(root, "catalog/archdev.json"), JSON.stringify({ version: catalogVersion }));
  writeFileSync(path.join(root, "plugins/opencode/package.json"), JSON.stringify({
    name, version: packageVersion, type: "module", files: ["index.js", "skills"],
  }, null, 2) + "\n");
  writeFileSync(path.join(root, "plugins/opencode/index.js"), "export const ArchDevPlugin = () => {};\n");
  writeFileSync(path.join(root, "plugins/opencode/skills/SKILL.md"), "# Fixture skill\n");
  return root;
}

function resolve(root: string, env: Record<string, string | undefined> = {}, prepare = false) {
  return spawnSync(process.execPath, [script, ...(prepare ? ["--prepare"] : [])], {
    cwd: root,
    encoding: "utf8",
    env: { ...process.env, GITHUB_REF: "refs/tags/v0.54.2", GITHUB_REF_TYPE: "tag", DRY_RUN: "false", ...env },
  });
}

function contents(root: string) {
  return ["catalog/archdev.json", "plugins/opencode/package.json", "plugins/opencode/index.js", "plugins/opencode/skills/SKILL.md"]
    .map((file) => readFileSync(path.join(root, file), "utf8"));
}

test("CLI release tags can advance without a catalog bump, without changing source during validation", () => {
  const root = fixture();
  const before = contents(root);
  const result = resolve(root);
  assert.equal(result.status, 0, result.stderr);
  assert.equal(result.stdout.trim(), "0.54.2");
  assert.deepEqual(contents(root), before);
});

test("preparation changes only the npm artifact version, including when versions already match", () => {
  for (const version of ["0.49.7", "0.54.2"]) {
    const root = fixture(version, version);
    const before = contents(root);
    const result = resolve(root, {}, true);
    assert.equal(result.status, 0, result.stderr);
    assert.equal(result.stdout.trim(), "0.54.2");
    const after = contents(root);
    assert.equal(after[0], before[0], "catalog must remain unchanged");
    assert.deepEqual(after.slice(2), before.slice(2), "bundled code and skills must remain unchanged");
    assert.deepEqual(JSON.parse(after[1]!), { ...JSON.parse(before[1]!), version: "0.54.2" });
  }
});

test("prerelease tags supply the full npm version", () => {
  const result = resolve(fixture(), { GITHUB_REF: "refs/tags/v0.55.0-rc.1" }, true);
  assert.equal(result.status, 0, result.stderr);
  assert.equal(result.stdout.trim(), "0.55.0-rc.1");
});

test("branch dispatch is permitted only for a dry run and uses the catalog version", () => {
  const root = fixture();
  const result = resolve(root, { GITHUB_REF: "refs/heads/main", GITHUB_REF_TYPE: "branch", DRY_RUN: "true" });
  assert.equal(result.status, 0, result.stderr);
  assert.equal(result.stdout.trim(), "0.49.7");
  const refused = resolve(root, { GITHUB_REF: "refs/heads/main", GITHUB_REF_TYPE: "branch" }, true);
  assert.notEqual(refused.status, 0);
  assert.match(refused.stderr, /Publishing requires a version tag/);
});

test("tag dispatch dry runs still use the tag version", () => {
  const result = resolve(fixture(), { DRY_RUN: "true" });
  assert.equal(result.status, 0, result.stderr);
  assert.equal(result.stdout.trim(), "0.54.2");
});

test("invalid release refs are refused before touching the package, even in dry runs", () => {
  for (const ref of ["refs/heads/main", "refs/tags/vfoo", "refs/tags/v1.2", "refs/tags/v01.2.3", "refs/tags/v1.2.3-01", "refs/tags/v1.2.3-", "refs/tags/v1.2.3\n", "refs/tags/archdev-old-v0.54.2"]) {
    const root = fixture();
    const before = contents(root);
    const result = resolve(root, { GITHUB_REF: ref, DRY_RUN: "true" }, true);
    assert.notEqual(result.status, 0, ref);
    assert.deepEqual(contents(root), before);
  }
});

test("missing GitHub refs cannot bypass tag validation", () => {
  for (const env of [{ GITHUB_REF: "" }, { GITHUB_REF_TYPE: "", DRY_RUN: "true", GITHUB_REF: "" }]) {
    const result = resolve(fixture(), env);
    assert.notEqual(result.status, 0, result.stdout);
  }
});

test("source package identity, catalog consistency, and valid catalog versions remain required", () => {
  for (const [pkgVersion, catalogVersion, name, error] of [
    ["0.49.6", "0.49.7", "@archastro/archdev-opencode", /out of date with the catalog/],
    ["0.49.7", "0.49.7", "another-package", /Unexpected OpenCode package name/],
    ["not-a-version", "not-a-version", "@archastro/archdev-opencode", /Invalid catalog version/],
  ] as const) {
    const root = fixture(pkgVersion, catalogVersion, name);
    const before = contents(root);
    const result = resolve(root, {}, true);
    assert.notEqual(result.status, 0);
    assert.match(result.stderr, error);
    assert.deepEqual(contents(root), before);
  }
});

test("the packed npm artifact carries the release version, not the catalog version", () => {
  const root = fixture();
  const prepared = resolve(root, {}, true);
  assert.equal(prepared.status, 0, prepared.stderr);
  const packed = spawnSync("npm", ["pack", "--json", "--ignore-scripts", "--cache", path.join(scratch, "npm-cache")], {
    cwd: path.join(root, "plugins/opencode"), encoding: "utf8",
  });
  assert.equal(packed.status, 0, packed.stderr);
  const result = JSON.parse(packed.stdout)[0];
  assert.equal(result.name, "@archastro/archdev-opencode");
  assert.equal(result.version, "0.54.2");
  assert.equal(result.filename, "archastro-archdev-opencode-0.54.2.tgz");
  assert.ok(result.files.some((file: { path: string }) => file.path === "skills/SKILL.md"));
});
