---
name: tasks-execute
description: Use when someone wants an agent to work through an ArchDev Tasks epic — pick ready tasks, lease each one, keep a lease heartbeat running the whole time, implement and verify, commit, close, and continue to the next task. Triggers include "work the epic", "execute these tasks", "pick up the next task", "run the plan", or /tasks-execute <epic>.
---

# Execute an epic

Work an ArchDev Tasks epic one task at a time. Each task follows the same
loop:

```
pick ready task → claim lease → start heartbeat → work → verify
      ↑                                                   ↓
 next ready task ← close ← stop heartbeat ← comment ← commit
```

Two rules matter more than anything else in this skill:

1. **Never work on a task you have not leased.** The claim is the only
   ownership gate. A `ready` listing is a snapshot, not ownership.
2. **Never hold a lease without a running heartbeat.** Leases expire (60s
   to 1h). Without renewal another session can claim the task while you are
   still editing it, and your commit then lands on work someone else owns.

Use the `archdev` CLI for every Tasks operation. Prefer `--json` for output
you parse. The CLI is the authority when it disagrees with this file:
read `"$archdev" tasks guide` once per session.

## Activity and risk ownership

Follow the `archdev` skill for activity reporting. Plan/task lifecycle events
retain their `risk.plan` / `risk.task` assessments. Server automation owns hosted
PR and code-region grading: report PR events without fetching, waiting for,
reusing, or attaching a server grade. No local assessment, annotation or stop
hold is required. Offline Evals remain supported. Absent capture stays off;
preserve explicit on/off and existing eligibility and session-link gates.

## 0. Connect

Resolve the absolute directory containing this `SKILL.md` and run its
bootstrap. It installs or updates ArchDev when the binary is missing or
lacks `tasks heartbeat`; get approval before installing or upgrading
software. Capture stdout, which is the executable's absolute path.

```sh
archdev="$(bash /absolute/path/to/tasks-execute/scripts/bootstrap.sh)"   # Bash/Zsh
set archdev (bash /absolute/path/to/tasks-execute/scripts/bootstrap.sh)  # Fish
$archdev = & powershell -NoProfile -File 'C:\path\to\tasks-execute\scripts\bootstrap.ps1'
```

Then:

1. `"$archdev" auth status`. If signed out, run `"$archdev" auth login` and
   let the human finish browser sign-in.
2. `"$archdev" tasks guide`. Read it in full.
3. If the `archdev` skill is installed, load it too. It covers lifecycle
   posts, presence and PR bookkeeping that this skill refers to.

## 1. Pin down the epic and the scope

The user names an epic (the Task `epic` label) or a plan. Resolve it before
claiming anything.

1. Find the owner scope: `--team <id>`, `--user <id>` (default: you), or
   `--org <id>`. If the user did not say and more than one fits, ask. Never
   guess an ID.
2. List the whole epic, including done work, so you know the shape:
   ```sh
   "$archdev" --json tasks list --epic "<epic>" [--team <id>] --limit 100
   "$archdev" --json tasks ready --explain --epic "<epic>" [--team <id>]
   ```
   Page with `--after-cursor` when a page is full.
3. Note which tasks are tagged `human` or `post_deploy`. Do not claim those:
   a person or a production observation closes them. Report them at the end.
4. Read the repository's agent instructions (`AGENTS.md`, `CLAUDE.md`)
   before editing. They decide branch, commit, push and test rules. Where
   they are stricter than this skill, they win.

Write a small state file outside the checkout, for example
`~/.archdev/task-execute/<epic-slug>.json` (`mkdir -p ~/.archdev/task-execute`
first), holding the epic, scope, and
for each claimed task its `task_id`, `lease_id`, `session_id`,
`session_name`, and heartbeat log path. Rewrite it on every claim, release
and close. It is how you resume after a crash or context reset (§8). It
contains no secrets; still keep it out of the repository.

## 2. Pick the next task

1. Re-read readiness every time. Never reuse an old listing:
   `"$archdev" --json tasks ready --epic "<epic>" [scope]`.
2. Choose the highest-priority ready task (lowest `priority` number), then
   the oldest. Work one task at a time unless the user asked for parallel
   workers.
3. Read it fully before claiming:
   ```sh
   "$archdev" --json tasks show <task-id>
   "$archdev" --json tasks comments <task-id> --all
   "$archdev" --json tasks deps list <task-id>
   ```
   Comments carry pause reasons, human answers and earlier attempts. The
   description carries the objective, acceptance, verification and the
   `## Implementation plan`.
4. If the task cannot be done as written (contradiction, missing access,
   a decision only a human can make), do not claim it. Comment the exact
   question on the task, tell the user, and pick another ready task.

## 3. Claim the lease

```sh
"$archdev" --json tasks claim <task-id> \
  --session-name "<harness>:<branch>:<task-id>:<random 6 chars>" \
  --harness <claude|codex|grok|...> \
  --lease-duration-seconds 300
```

- The random suffix makes the session name unique, so you can recognise your
  own lease in `tasks show` later.
- Keep `lease.lease_id`, `lease.session_id` and `lease.expires_at` from the
  response. Write them to the state file before doing anything else.
- A conflict error means another session holds the task. Do not retry in a
  loop and never try to take it over. Pick another ready task.
- Go straight to §4. Mark the task in progress and set presence only after
  the heartbeat is running.

## 4. Start the heartbeat (before any other work)

Start the heartbeat immediately after the claim succeeds. Do not read code,
plan, or edit anything first.

```sh
"$archdev" --json tasks heartbeat <task-id> \
  --lease-id <lease-id> --session-id <session-id> \
  --interval-seconds 60 --lease-duration-seconds 300
```

It renews the lease every 60s for 300s. It needs native ArchDev Tasks leases
and refuses other task backends. It writes one JSON line per event to stdout;
errors also go to stderr as plain text:

| `event` | Meaning | What you do |
|---|---|---|
| `renewed` | Lease extended to `expires_at` | Nothing |
| `renew_failed` | Transient failure (network, timeout, 5xx, rate limit); still retrying | Watch. Do not commit or close until a `renewed` follows |
| `lease_lost` | `reason: "lost"`: the backend refused the lease (expired, held by someone else, or the task is gone). `reason: "expired"`: no renewal succeeded for a full lease duration, so the lease is presumed lost. Exits with **code 3** | **Stop work on this task now** (see below) |
| `heartbeat_error` | A request the backend will never accept (signed out, invalid parameters). Exits with **code 1** | Stop work, fix the cause (for example `auth login`), then confirm with `tasks renew` |
| `stopped` | You stopped it | Expected before close or release |

Then, with the heartbeat running:

```sh
"$archdev" --json tasks update <task-id> --status in_progress \
  --lease-id <lease-id> --session-id <session-id>
```

Set presence only for an accessible **team-owned** task, and only if
`"$archdev" presence --help` lists `update`:
`"$archdev" presence update --task <task-id>`. Personal tasks stay private:
never publish their IDs through presence.

### Run it so the harness tells you when it dies

The heartbeat must keep running in the background for as long as you hold
the task, and you must find out when it exits.

- **Claude Code:** run it with the Bash tool, `run_in_background: true` and
  the maximum `timeout` (7200000 ms). Record the background task ID it
  returns in the state file. The harness re-invokes you when it exits.
  - Read its output from the output file path the tool returns (for example
    `tail -n 1 <output file>`). Do not read the whole file into context.
  - Stop it with the harness's stop tool for background tasks (for example
    `TaskStop` with the recorded ID).
  - Background runs have a time limit. When the notification says it stopped
    because of the limit and you still hold the task, restart it straight
    away with the **same** lease and session IDs.
  - If a Monitor tool is available, use it as well to watch the output for
    `lease_lost`, `heartbeat_error` and `renew_failed` lines.
- **Codex, Grok and other harnesses:** use the harness's persistent or
  background process facility if it has one. Otherwise start it detached,
  with stdout and stderr in separate files so the event log stays JSONL:
  ```sh
  mkdir -p "$HOME/.archdev/task-execute"
  nohup "$archdev" --json tasks heartbeat <task-id> --lease-id <lease-id> \
    --session-id <session-id> \
    >"$HOME/.archdev/task-execute/<task-id>.heartbeat.jsonl" \
    2>"$HOME/.archdev/task-execute/<task-id>.heartbeat.err" &
  echo $!   # record this PID in the state file
  ```
  Stop it with `kill <pid>` (SIGTERM). Check `kill -0 <pid>` to see whether
  it is still alive.

### Check the heartbeat at every gate

Before each of these steps, read the newest heartbeat line and confirm the
process is alive, the line is `renewed`, and its `at` is within about two
intervals (two minutes at the defaults):

1. before the first edit
2. before running long verification
3. before `git commit`
4. before `git push` or opening a PR
5. before `tasks close`

If the line is older, the process is gone, or the line is anything other
than `renewed`, run the lease-lost steps below.

### When the lease is lost or the heartbeat is dead

1. Stop editing. Do not commit, push or close.
2. Probe ownership with your stored IDs:
   ```sh
   "$archdev" --json tasks renew <task-id> --lease-id <lease-id> --session-id <session-id>
   ```
   - **It succeeds:** you still hold the task. Restart the heartbeat with the
     same IDs and continue.
   - **It fails with a conflict** ("Task lease has expired" or "Task lease
     does not match the current holder"): your lease is gone. The second
     message also appears when nobody holds the task, so check:
     `"$archdev" --json tasks show <task-id>` and look at `current_lease`.
     - **Empty:** claim again with **new** IDs (§3), start a new heartbeat,
       and check the working tree still matches what you expect before
       going on.
     - **Another `session_name`:** someone else owns the task now, and your
       work on it is no longer authoritative. Comment where your partial work
       is (branch name, stash tag, or WIP commit SHA), tell the user, and move
       to another ready task. Never push over the other session's work.
   - **It fails with an authentication or other error:** fix that first (for
     example `auth login`), then probe again.

### Rules

- One heartbeat per held lease, never zero.
- Do not request a long lease (up to 3600s) to avoid running a heartbeat.
  Use 300s with a 60s interval unless the user says otherwise. Allowed
  durations are 60 to 3600 seconds.
- `--interval-seconds` must be shorter than `--lease-duration-seconds`. Keep
  it at a third of the duration or less.
- Stop the heartbeat only as part of closing (§6) or giving the task back
  (§7), right before that command, never earlier.

## 5. Do the work

1. Report the start if the `archdev` skill's lifecycle posts are in use:
   `"$archdev" log post --project <id> --kind start "<what this task delivers>"`.
2. Follow the task's implementation plan, acceptance and verification. They
   are the contract. If they turn out to be wrong, comment what you found
   and why, and adjust within the objective. Ask the user before changing
   scope.
3. Record durable progress on the task at real milestones, not every step:
   `"$archdev" tasks comment <task-id> "<decision, finding, or blocker>"`.
4. Run the verification the task names: its canonical end-to-end test,
   focused tests, and the repository's pre-commit gates. A task is not done
   until they pass, or until the gap is written down on the task with the
   reason.
5. Two failed attempts on the same failure means change approach, not try
   a third time. If you are still stuck, use §7.

## 6. Commit, then close

This skill carries each task through to a commit. Invoking it on an epic is
the user's explicit request to **commit** each finished task. It is **not** a
request to push or open PRs; do those only when the user said so for this
run. Repository instructions still decide the branch and commit format. If
they forbid agent commits outright, stop at verified, uncommitted work and
ask.

1. Gate check: the heartbeat's newest line is `renewed` (§4).
2. Commit only that task's files, on the branch the repository rules
   require, using the task title and ID in the message:
   ```
   <type>(<area>): <task title>

   Task: <task-id>
   ```
   Never bypass hooks (`--no-verify`). If a hook fails, fix the cause.
3. If pushing was requested: push, then run the PR bookkeeping the `archdev`
   skill requires for any PR head you moved.
4. Record the result on the task:
   `"$archdev" tasks comment <task-id> "Done in <sha> on <branch>. Verified by <test names>."`
5. Gate check again, then stop the heartbeat and close, fenced with your
   lease. The last renewal leaves minutes on the lease, which is plenty for
   the close. Stopping first means the heartbeat never reports your own close
   as a lost lease.
   ```sh
   "$archdev" --json tasks close <task-id> --lease-id <lease-id> --session-id <session-id>
   ```
   If the close fails, restart the heartbeat with the same IDs before you
   retry or investigate.
6. Run `"$archdev" presence clear` if you set presence. Update the state file.
7. Go back to §2. Closing a task can make its dependents ready.

## 7. Give a task back

When you cannot finish (blocked, needs a human, out of scope, or the user
redirects you):

1. Comment the state: what is done, where it lives (branch or SHA), what
   remains, and the exact question if one exists.
2. Reopen it while still fenced:
   ```sh
   "$archdev" --json tasks update <task-id> --status open --lease-id <lease-id> --session-id <session-id>
   ```
3. Stop the heartbeat, then release:
   ```sh
   "$archdev" --json tasks release <task-id> --lease-id <lease-id> --session-id <session-id>
   ```
4. Run `presence clear` if you set presence, and update the state file.

## 8. Resume after a crash or context reset

1. Read the state file.
2. For each task it lists as held, probe with the stored IDs:
   `"$archdev" --json tasks renew <task-id> --lease-id <lease-id> --session-id <session-id>`.
   - **Success:** the lease is still yours. Start a heartbeat with the same
     IDs straight away (§4), then continue.
   - **Failure:** follow the lease-lost steps in §4. They cover an expired
     lease, a new owner, and auth errors.
3. Clean up anything the crash left running: a heartbeat PID or background
   task for a task you no longer hold.
4. Read the task's newest comments before editing, in case someone changed
   the plan while you were away.

## 9. Finish

Stop when the epic has no ready tasks left, when the user stops you, or
when a blocker needs them. Before you report, check that no heartbeat is
still running for a task you closed or released.

Report back in this form:

1. **Done:** task, commit SHA, and the verification that proved it.
2. **Given back:** task, why, and the question it needs answered.
3. **Blocked or not started:** task and its blockers, from
   `tasks ready --explain --epic "<epic>"`.
4. **For a human:** tasks tagged `human` or `post_deploy`.
5. **Pushed or PRs opened:** only if pushing was requested.
