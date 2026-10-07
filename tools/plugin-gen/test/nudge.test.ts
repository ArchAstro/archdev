import assert from "node:assert/strict";
import { execFileSync, spawnSync } from "node:child_process";
import { existsSync, mkdirSync, mkdtempSync, readFileSync, rmSync, statSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import path from "node:path";
import { after, before, describe, test } from "node:test";

const repoRoot = execFileSync("git", ["rev-parse", "--show-toplevel"], { encoding: "utf8" }).trim();
// Each harness plugin that ships the nudge, with the env var its runtime sets
// for the plugin's data directory (Claude Code: CLAUDE_PLUGIN_DATA; Codex:
// PLUGIN_DATA, with the Claude names kept as aliases).
const HARNESSES = [
  { name: "claude", dataVar: "CLAUDE_PLUGIN_DATA" },
  { name: "codex", dataVar: "PLUGIN_DATA" },
] as const;
let script = "";
let dataVar: string = "CLAUDE_PLUGIN_DATA";

// A PATH without an archdev CLI, so the script takes its no-CLI branch even on
// a machine that has ArchDev installed.
const noCliPath = (process.env.PATH ?? "")
  .split(path.delimiter)
  .filter((dir) => dir && !existsSync(path.join(dir, "archdev")))
  .join(path.delimiter);

let tmp: string;
let repo: string;
let data: string;
let n = 0;

const git = (...args: string[]) =>
  execFileSync("git", args, { cwd: repo, encoding: "utf8" }).trim();

before(() => {
  tmp = mkdtempSync(path.join(tmpdir(), "nudge-"));
  repo = path.join(tmp, "repo");
  data = path.join(tmp, "data");
  mkdirSync(repo);
  git("init", "-q");
  git("config", "user.email", "t@example.com");
  git("config", "user.name", "t");
  writeFileSync(path.join(repo, "a.txt"), "a");
  git("add", "a.txt");
  git("commit", "-qm", "init");
});
after(() => rmSync(tmp, { recursive: true, force: true }));

interface Run {
  status: number | null;
  stdout: string;
  context?: string;
  event?: string;
  block?: string;
}

/** Runs the script like Claude Code does: hook JSON on stdin. */
function hook(mode: string, session: string, payload: Record<string, unknown>, env: Record<string, string> = {}): Run {
  const result = spawnSync("sh", [script, mode], {
    input: JSON.stringify({ session_id: session, cwd: repo, ...payload }),
    encoding: "utf8",
    env: { ...process.env, PATH: noCliPath, [dataVar]: data, ...env },
  });
  const run: Run = { status: result.status, stdout: result.stdout };
  if (result.stdout.trim()) {
    const out = JSON.parse(result.stdout);
    run.context = out.hookSpecificOutput?.additionalContext;
    run.event = out.hookSpecificOutput?.hookEventName;
    run.block = out.decision === "block" ? out.reason : undefined;
  }
  return run;
}

const bash = (session: string, command: string, response: Record<string, unknown> = {}) =>
  hook("post-tool", session, { tool_name: "Bash", tool_input: { command }, tool_response: { stdout: "", stderr: "", ...response } });
const fresh = () => `sess${++n}`;

for (const harness of HARNESSES) describe(`${harness.name}: archdev-nudge.sh without the CLI`, () => {
  before(() => {
    script = path.join(repoRoot, `plugins/${harness.name}/hooks/archdev-nudge.sh`);
    dataVar = harness.dataVar;
  });

  test("is executable POSIX sh and exits 0 on garbage, empty and unknown input", () => {
    assert.ok(statSync(script).mode & 0o100);
    assert.equal(readFileSync(script, "utf8").split("\n")[0], "#!/bin/sh");
    for (const mode of ["start", "prompt", "post-tool", "stop", "bogus", ""]) {
      for (const input of ["", "not json", "{}", '{"tool_name":'] ) {
        const r = spawnSync("sh", [script, mode], { input, env: { ...process.env, PATH: noCliPath, [dataVar]: data } });
        assert.equal(r.status, 0, `${mode} ${input}`);
      }
    }
  });

  test("does nothing when the CLI is on PATH, so the CLI never double reports", () => {
    const bin = path.join(tmp, "bin");
    mkdirSync(bin, { recursive: true });
    writeFileSync(path.join(bin, "archdev"), "#!/bin/sh\n", { mode: 0o755 });
    const r = spawnSync("sh", [script, "start"], {
      input: JSON.stringify({ session_id: fresh(), cwd: repo }),
      encoding: "utf8",
      env: { ...process.env, PATH: `${bin}${path.delimiter}${noCliPath}`, [dataVar]: data },
    });
    assert.equal(r.status, 0);
    assert.equal(r.stdout, "");
  });

  test("session start names the first calls, the session id and the consent", () => {
    const s = fresh();
    const r = hook("start", s, { hook_event_name: "SessionStart" });
    assert.equal(r.event, "SessionStart");
    for (const part of ["archdev_get_context", "archdev_list_projects", "archdev_create_project", "agent.session_started", `"session_id":"${s}"`, "archdev:write consent", "do not ask again"])
      assert.ok(r.context?.includes(part), part);
  });

  test("the first prompt is quiet once ArchDev was used; every later prompt owes agent.steered", () => {
    const s = fresh();
    hook("start", s, {});
    assert.match(hook("prompt", s, { prompt: "one" }).context ?? "", /archdev_get_context/);
    const second = hook("prompt", s, { prompt: "two" });
    assert.match(second.context ?? "", /agent\.steered/);
    assert.match(second.context ?? "", new RegExp(`"lifecycle":"steered"`));
    assert.match(second.context ?? "", new RegExp(`${s}-steered-1`));
    assert.match(hook("prompt", s, { prompt: "three" }).context ?? "", new RegExp(`${s}-steered-2`));

    const used = fresh();
    hook("post-tool", used, { tool_name: "mcp__plugin_archdev_archdev__archdev_get_context", tool_input: {}, tool_response: "ok" });
    assert.equal(hook("prompt", used, { prompt: "one" }).stdout, "");
  });

  test("a successful git commit nudges commit.created with the new HEAD; a no-op commit does not", () => {
    const s = fresh();
    hook("start", s, {});
    assert.equal(bash(s, "git commit -m nothing").stdout, "", "HEAD did not move");
    writeFileSync(path.join(repo, `b${++n}.txt`), "b");
    git("add", ".");
    git("commit", "-qm", 'add "b" feature');
    const head = git("rev-parse", "HEAD");
    const r = bash(s, 'cd repo && git add -A && git commit -m "add b"');
    assert.equal(r.event, "PostToolUse");
    assert.match(r.context ?? "", /commit\.created/);
    assert.ok(r.context?.includes(`"sha":"${head}"`));
    assert.ok(r.context?.includes('"summary":"add b feature"'), "subject is sanitized for JSON");
    assert.equal(bash(s, "git commit -m again").stdout, "", "one nudge per new HEAD");
  });

  test("git push nudges commit.pushed once per HEAD, not after a rejected push", () => {
    const s = fresh();
    hook("start", s, {});
    assert.equal(bash(s, "git push origin main", { stderr: "! [rejected] main -> main\nerror: failed to push" }).stdout, "");
    const r = bash(s, "git push -u origin main", { stderr: "main -> main" });
    assert.match(r.context ?? "", /commit\.pushed/);
    assert.ok(r.context?.includes(`"sha":"${git("rev-parse", "HEAD")}"`));
    assert.equal(bash(s, "git push", { stderr: "Everything up-to-date" }).stdout, "");
  });

  test("gh pr create, edit and merge nudge pr.created, pr.updated and pr.closed with the PR number", () => {
    const s = fresh();
    hook("start", s, {});
    const created = bash(s, "gh pr create --title t --body b", { stdout: "https://github.com/acme/app/pull/7\n" });
    assert.match(created.context ?? "", /pr\.created/);
    assert.ok(created.context?.includes('"repository":"acme/app","number":7'));
    assert.ok(created.context?.includes("archdev_finalize_risk"));
    assert.equal(bash(s, "gh pr create --title t", { stdout: "https://github.com/acme/app/pull/7\n" }).stdout, "");
    const edited = bash(s, "gh pr edit 7 --body more");
    assert.ok(edited.context?.includes('"event \\"pr.updated\\"') === false);
    assert.match(edited.context ?? "", /pr\.updated/);
    assert.match(edited.context ?? "", /#7/);
    const merged = bash(s, "gh pr merge 7 --squash");
    assert.match(merged.context ?? "", /archdev_post_pr_closed/);
    assert.ok(merged.context?.includes("pull_number 7"));
    assert.equal(bash(s, "gh pr merge 7").stdout, "");
  });

  test("a push to an open PR's branch also owes pr.updated", () => {
    const s = fresh();
    hook("start", s, {});
    bash(s, "gh pr create", { stdout: "https://github.com/acme/app/pull/9\n" });
    writeFileSync(path.join(repo, `c${n}.txt`), "c");
    git("add", ".");
    git("commit", "-qm", "more");
    const r = bash(s, "git push", { stderr: "main -> main" });
    assert.match(r.context ?? "", /commit\.pushed/);
    assert.match(r.context ?? "", /pr\.updated/);
  });

  test("a failed Bash tool call (is_error) nudges nothing", () => {
    const s = fresh();
    hook("start", s, {});
    writeFileSync(path.join(repo, `d${n}.txt`), "d");
    git("add", ".");
    git("commit", "-qm", "d");
    assert.equal(bash(s, "git commit -m d", { is_error: true }).stdout, "");
  });

  test("plan files nudge plan.created then plan.updated, once per user turn, and other files nothing", () => {
    const s = fresh();
    hook("start", s, {});
    hook("prompt", s, { prompt: "one" });
    const write = (file: string, type?: string) =>
      hook("post-tool", s, { tool_name: type ? "Write" : "Edit", tool_input: { file_path: path.join(repo, file) }, tool_response: type ? { type } : {} });
    const created = write("docs/plans/todo.md", "create");
    assert.match(created.context ?? "", /plan\.created/);
    assert.ok(created.context?.includes('"location":"docs/plans/todo.md"'));
    assert.equal(write("docs/plans/todo.md").stdout, "", "second edit in the same turn");
    hook("prompt", s, { prompt: "two" });
    assert.match(write("docs/plans/todo.md").context ?? "", /plan\.updated/);
    assert.equal(write("src/app.py", "create").stdout, "");
    assert.equal(write("README.md", "create").stdout, "");
    assert.match(write("PLAN.md", "create").context ?? "", /plan\.created/);
  });

  test("an ArchDev MCP call clears what was owed, and Stop blocks once for what was not", () => {
    const s = fresh();
    hook("start", s, {});
    hook("prompt", s, { prompt: "one" });
    hook("prompt", s, { prompt: "two" });
    const call = (tool: string, input: unknown) =>
      hook("post-tool", s, { tool_name: `mcp__plugin_archdev_archdev__${tool}`, tool_input: input, tool_response: "ok" });
    call("archdev_post_activity_event", { event: "agent.steered", value: {} });
    assert.equal(hook("stop", s, { stop_hook_active: false }).stdout, "", "nothing owed");

    hook("prompt", s, { prompt: "three" });
    assert.equal(hook("stop", s, { stop_hook_active: true }).stdout, "", "no loop while already continuing");
    const stop = hook("stop", s, { stop_hook_active: false });
    assert.match(stop.block ?? "", /agent\.steered/);
    assert.equal(hook("stop", s, { stop_hook_active: false }).stdout, "", "the owed list is cleared after one block");
  });

  test("accepts the documented Codex and Claude hook envelopes, including extra fields and a string tool_response", () => {
    const s = fresh();
    hook("start", s, { hook_event_name: "SessionStart", source: "startup", model: "m", permission_mode: "default" });
    writeFileSync(path.join(repo, `e${++n}.txt`), "e");
    git("add", ".");
    git("commit", "-qm", "envelope");
    const r = hook("post-tool", s, {
      hook_event_name: "PostToolUse",
      turn_id: "t1",
      transcript_path: "/x",
      permission_mode: "default",
      tool_name: "Bash",
      tool_use_id: "call_1",
      tool_input: { command: "git commit -am envelope" },
      tool_response: "[main 123abc] envelope",
    });
    assert.match(r.context ?? "", /commit\.created/);
    assert.equal(r.event, "PostToolUse");
  });

  test("runs in well under 100 ms", () => {
    const s = fresh();
    hook("start", s, {});
    const started = process.hrtime.bigint();
    for (let i = 0; i < 5; i++) bash(s, "ls -la");
    const each = Number(process.hrtime.bigint() - started) / 5 / 1e6;
    assert.ok(each < 100, `${each} ms per hook`);
  });
});
