import assert from "node:assert/strict";
import { execFileSync } from "node:child_process";
import { readFileSync } from "node:fs";
import path from "node:path";
import { describe, test } from "node:test";
import { parse } from "yaml";

const MAX_DESCRIPTION_LENGTH = 1024;

function checkDescription(markdown: string, file: string): void {
  const frontmatter = /^---\r?\n([\s\S]*?)\r?\n---(?:\r?\n|$)/.exec(markdown);
  assert.ok(frontmatter, `${file}: missing YAML frontmatter`);
  const description = parse(frontmatter[1]!)?.description;
  assert.equal(typeof description, "string", `${file}: description must be a string`);
  const length = [...description].length;
  assert.ok(
    length <= MAX_DESCRIPTION_LENGTH,
    `${file}: description is ${length} characters (maximum ${MAX_DESCRIPTION_LENGTH})`,
  );
}

function skill(yaml: string): string {
  return `---\n${yaml}\n---\n# Skill\n`;
}

describe("skill description validation", () => {
  test("accepts exactly 1,024 characters and rejects 1,025", () => {
    checkDescription(skill(`description: ${"a".repeat(1024)}`), "boundary/SKILL.md");
    assert.throws(
      () => checkDescription(skill(`description: ${"a".repeat(1025)}`), "oversized/SKILL.md"),
      /oversized\/SKILL\.md: description is 1025 characters \(maximum 1024\)/,
    );
  });

  test("counts Unicode characters, not UTF-8 bytes or UTF-16 code units", () => {
    checkDescription(skill(`description: ${"🚀".repeat(1024)}`), "unicode/SKILL.md");
    assert.throws(
      () => checkDescription(skill(`description: ${"🚀".repeat(1025)}`), "unicode/SKILL.md"),
      /description is 1025 characters/,
    );
  });

  test("measures parsed quoted and multiline YAML values", () => {
    checkDescription(skill(`description: "${"a".repeat(1024)}"`), "quoted/SKILL.md");
    checkDescription(skill(`description: >-\n  ${"a".repeat(512)}\n  ${"b".repeat(511)}`), "folded/SKILL.md");
    for (const style of [">-", "|-"]) {
      assert.throws(
        () => checkDescription(skill(`description: ${style}\n  ${"a".repeat(512)}\n  ${"b".repeat(512)}`), "multiline/SKILL.md"),
        /description is 1025 characters/,
      );
    }
  });

  test("rejects missing frontmatter and missing or non-string descriptions", () => {
    assert.throws(() => checkDescription("# Skill", "missing/SKILL.md"), /missing YAML frontmatter/);
    for (const yaml of ["name: example", "description: null", "description: 123", "description: [example]"]) {
      assert.throws(() => checkDescription(skill(yaml), "invalid/SKILL.md"), /description must be a string/);
    }
  });
});

describe("repository skill descriptions", () => {
  const repoRoot = execFileSync("git", ["rev-parse", "--show-toplevel"], { encoding: "utf8" }).trim();
  // Discover all skills, not just the catalog: include generated copies and new local skills.
  const skills = [...new Set(execFileSync(
    "git",
    ["ls-files", "-z", "--cached", "--others", "--exclude-standard", "--", "SKILL.md", "**/SKILL.md"],
    { cwd: repoRoot, encoding: "utf8" },
  ).split("\0").filter(Boolean))].sort();
  assert.ok(skills.length > 0, "the repository must contain skills to validate");

  for (const file of skills) {
    test(`${file} has a description of at most 1,024 characters`, () => {
      checkDescription(readFileSync(path.join(repoRoot, file), "utf8"), file);
    });
  }
});
