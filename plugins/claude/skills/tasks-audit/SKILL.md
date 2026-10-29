---
name: tasks-audit
description: Use when someone wants to go through their own paused, blocked, failed or stuck ArchDev Tasks — find every Task assigned to them that is not moving, work out why from its comments, dependencies and inbox question, explain each reason in plain language, and walk them through answering, unblocking, splitting or cancelling it. Fans the investigation out to subagents, one per epic. Triggers include "audit my tasks", "what's paused", "what's blocked on me", "why is this stuck", "go through my paused tasks", "triage my inbox", or /tasks-audit.
---

# Audit your paused, blocked and failed Tasks

Find every Task assigned to the user that is not moving, explain why in
words they can act on, and help them clear it. The run is a workflow:

```
connect → who am I → inventory ──→ investigate (subagents, one per epic)
                                         ↓
            finish ← act (approved only) ← walk through ← plain-language report
```

Rules that hold through every phase:

1. **Read-only until the user approves a specific change.** Inventory,
   investigation and the report change nothing. "Audit my tasks" is not
   approval to answer, reopen, cancel or retag anything.
2. **Explain first, then propose.** Every Task in the report says what it
   is waiting for, in plain language, before any action is offered.
3. **Don't fight a running Factory.** A native status change does not clear
   a Factory's local state; its overseer re-pauses the Task within minutes.
   Factory-owned work is unblocked by answering it (`tasks answer`) or by
   asking the overseer to resume it, never by `tasks update --status open`.
4. **Don't invent reasons.** If the Task's `metadata.pause`, inbox row,
   comments and dependencies don't say why it stopped, report "no recorded reason" and
   what would find out. Mark guesses as guesses.

Use the `archdev` CLI for every Tasks operation, with `--json` for output
you parse. The CLI is the authority when it disagrees with this file: read
`"$archdev" tasks guide` once per session.

## Activity and risk ownership

Follow the `archdev` skill for activity reporting. Plan/task lifecycle events
retain their `risk.plan` / `risk.task` assessments. Server automation owns hosted
PR and code-region grading: report PR events without fetching, waiting for,
reusing, or attaching a server grade. No local assessment, annotation or stop
hold is required.

## 0. Connect

Resolve the absolute directory containing this `SKILL.md` and run its
bootstrap. It installs or updates ArchDev when the binary is missing or
lacks `tasks inbox` / `tasks answer`; get approval before installing or
upgrading software. Capture stdout, which is the executable's absolute path.

```sh
archdev="$(bash /absolute/path/to/tasks-audit/scripts/bootstrap.sh)"   # Bash/Zsh
set archdev (bash /absolute/path/to/tasks-audit/scripts/bootstrap.sh)  # Fish
$archdev = & powershell -NoProfile -File 'C:\path\to\tasks-audit\scripts\bootstrap.ps1'
```

Then `"$archdev" auth status` (sign in with `"$archdev" auth login` if
needed; the human finishes the browser step) and read `"$archdev" tasks guide`.

## 1. Work out who "me" is

Org Tasks are filtered by assignee with `--owner-user <usr_…>`, and the CLI
has no "me" alias for that flag. Resolve the user's ID once:

1. If the user gave an ID or a name, use it.
2. Otherwise read the signed-in email from `"$archdev" auth status` and
   match its name part against the assignees on recent Tasks:
   ```sh
   "$archdev" --json tasks list --sort created --order desc --limit 100 \
     | jq -c '[.data[].owner_actor | {id, name, alias}] | unique | .[]'
   ```
   `owner_actor.id` is `user-usr_…`; the flag takes the `usr_…` part.
3. If exactly one assignee plausibly matches, use it and say so on the
   report's first line ("Auditing Tasks assigned to Calvin Grunewald") so
   the user can correct it. If none or several match, ask. Never guess.

Personal Tasks (`--user me`) are a separate collection. Include them only
if the user asks, or if the org audit comes back empty. Add `--team <id>`
when the user names a team.

Keep run state outside the checkout, for example
`~/.archdev/tasks-audit/<YYYY-MM-DD>/` (`mkdir -p` first): `me.json`,
`inventory.json`, one `findings-<epic-slug>.json` per subagent, and
`actions.jsonl` (one line per change made). It holds no secrets. It is how
you resume after a context reset without re-investigating.

## 2. Inventory

Collect everything assigned to the user that is not moving. Do this in the
main session; it is a handful of list calls. Page any full page with
`--after-cursor` (100 is the page maximum).

```sh
"$archdev" --json tasks list --owner-user "$me" --status paused --limit 100
"$archdev" --json tasks list --owner-user "$me" --status failed --limit 100
"$archdev" --json tasks blocked            # org-wide, no owner flag: see below
"$archdev" --json tasks list --owner-user "$me" --status in_progress --limit 100   # keep is_stalled == true
"$archdev" --json tasks list --owner-user "$me" --status in_review --limit 100     # keep is_stalled == true
"$archdev" --json tasks inbox              # org-wide, unpaged; join on taskId
```

`tasks blocked` covers the whole org and includes `open`, `paused` and
`cancelled` rows. Keep `.owner_user == $me` and drop `cancelled`; its
paused and in-progress rows overlap the lists above, so dedupe by `id`.
Only `is_blocked == true` means a Task is waiting on unfinished work.
`blocked_by_count` counts every blocker, including done ones, so it is not
a blocked signal on its own.

Every paused Task's reason, when one was recorded, is on the Task itself:
`metadata.pause` (`kind`, `category`, `blocker`, `question`, `recommended`,
`rationale`, `paused_at`, `paused_by`) and `metadata.factory_attention`
(`kind`, `summary`, `at`). Read it straight from the list rows. Many paused
Tasks have no inbox row (for example `kind: dependency_not_promoted`, a
pause until a prerequisite ships or a date passes), so the inbox alone
undercounts the reasons.

`tasks inbox` lists paused Tasks waiting on a human, across the org. Join
its rows onto the user's Tasks by `taskId`; its `kind`, `category`,
`question`, `blocker`, `recommended`, `rationale`, `pausedAt` and `version`
match `metadata.pause` and add the `version` (the Task's
`aggregate_version`). Keep it: answers pass it as `--expected-version`.

Sort each Task into one first-pass bucket. Investigation may move it.

| Bucket | Signal |
|---|---|
| Needs your answer | pause `kind` is `needs_decision` |
| Needs access you hold | pause `kind` is `needs_access` |
| Waiting for something to ship or a date | pause `kind` is `dependency_not_promoted` |
| Human-only step | tag `human`, or inbox `kind` is `legacy_human_task` |
| Waits for a deploy | tag `post_deploy` |
| Waiting on other Tasks | `is_blocked` and none of the above |
| Failed | status `failed` |
| Stuck mid-work | `is_stalled` (in progress, no activity since `stalled_since`; often no lease at all) |
| Paused, no recorded reason | paused, no `metadata.pause`, no inbox row, no tag above |

A human-only or post-deploy Task that is also blocked belongs to the
blocked bucket until its blockers are done: it is not actionable yet. Say
so rather than asking the user to do it early.

Write `inventory.json` and tell the user the counts per bucket in one line
before investigating, so they can narrow the audit ("only the Gemini epic",
"skip post-deploy").

## 3. Investigate with subagents

Group the inventory by `epic` (Tasks without one form their own group).
Give each group to one read-only subagent; split a group above about 10
Tasks. Run them in parallel. Each subagent gets a self-contained brief: it
has not seen this conversation.

### Subagent brief

Pass the `archdev` path, the user's ID, the group's Task rows from
`inventory.json` (including any inbox row), and this text:

> You are auditing paused, blocked and failed ArchDev Tasks for one epic.
> **Read only:** do not run `tasks update`, `answer`, `comment`, `claim`,
> `close`, `reopen`, `deps add/remove`, or anything that writes. For each
> Task:
>
> 1. `"$archdev" --json tasks show <id>` — description, acceptance,
>    `current_lease`, tags, links.
> 2. `"$archdev" --json tasks comments <id> --all` — pause and block
>    reasons live here. Factory comments are prefixed: `[factory:pause
>    kind=…]`, `[factory:needs-operator kind=…]`, `[factory:decision]`,
>    `[factory:implementation_plan]`, `[human:answer]`. The newest pause
>    comment and anything after it matter most.
> 3. `"$archdev" --json tasks deps list <id>` — each blocker with its
>    status. Follow blockers that are themselves blocked until you reach
>    the root blocker(s) that are actually stuck, and name them.
> 4. For each linked pull request, its state (`gh pr view <url> --json
>    state,mergedAt,statusCheckRollup` if `gh` is available).
> 5. If a blocker is `done`, check it shipped: its PR merged, or its
>    commit is on the default branch. A done-but-never-shipped blocker is
>    a finding.
> 6. Factory ownership: recent `[factory:…]` comments, a
>    `metadata.factory_attention` entry, or a `current_lease.session_name`
>    starting with `factory:` mean a Factory is driving it. A stalled Task
>    often has no lease, so don't rely on the lease alone.
>
> Return JSON only, one object per Task, matching the schema below. Quote
> evidence (comment timestamp and first line, blocker title and status);
> do not paraphrase it into certainty. If nothing records why the Task
> stopped, say `"reason_known": false`.

### Findings schema

```json
{
  "task_id": "tsk_…",
  "title": "…",
  "epic": "…",
  "bucket": "needs_answer | needs_access | human_step | waits_for_deploy | blocked | failed | stuck | no_reason | stale",
  "reason_known": true,
  "waiting_for": "one plain sentence: what has to happen next, and by whom",
  "why": "one or two plain sentences on how it got here",
  "evidence": ["2026-10-29 19:25 [factory:pause kind=needs_access] The retained checkout predates …"],
  "root_blockers": [{"task_id": "tsk_…", "title": "…", "status": "paused", "why_stuck": "…"}],
  "factory_owned": false,
  "inbox_version": 24,
  "recommended": "the inbox recommendation, or the subagent's proposed next step marked as a proposal",
  "proposed_actions": ["accept_recommended | answer | access_granted | evidence | rescope_local | add_dep | split_human | cancel | reopen_blocker | ask_overseer | none"],
  "question_for_user": "the one question that unblocks it, or null"
}
```

`stale` means duplicate, superseded, or already delivered (the acceptance
is met on the default branch): it should probably be cancelled or closed.

### Running it

- **Claude Code with the Workflow tool:** invoking this skill is the
  user's request to run the investigation as a workflow. Load the
  `workflow-authoring` skill first, then run one `agent()` per epic group
  inside `parallel()`, each with the brief above and the findings schema,
  and return the merged findings. Keep it to one phase; the main session
  writes the report. Without the Workflow tool, launch one `Agent` per
  group in a single message so they run concurrently.
- **Other harnesses:** use their subagent or parallel-task facility with
  the same brief. With no subagents, investigate the groups yourself one
  at a time and write each group's findings file before the next.
- A cheaper or faster model is fine for subagents: the work is reading
  and summarising, not judgement calls.
- Check what comes back. Spot-check one finding per group against the
  Task's comments yourself; send a group back if its evidence does not
  support its `waiting_for`.

Save each group's result as `findings-<epic-slug>.json`.

## 4. Say it in plain language

The user should understand every line without knowing Factory or Tasks
internals. For each Task:

- **Lead with what it is waiting for and who acts.** "Waiting on you to
  approve four live Slack steps", not "paused (needs_decision /
  live_infrastructure)".
- **Name things by title, not ID.** IDs go in a trailing link or column.
- **Relative times.** "paused 10 days ago", "stuck since yesterday".
- **Translate internal terms** (table below). Keep the raw kind only in
  the detail view.
- **One sentence of why**, then the recommended next step if there is
  one. Long evidence stays in the detail view.
- **Say when nothing is known.** "No reason recorded. The last comment is
  from the worker on Oct 12 and says tests passed." is better than a
  guess.

| Internal | Say |
|---|---|
| `needs_decision` | Waiting on your decision |
| `needs_access` / `credentials` | Needs a credential or secret only a person can provide |
| `needs_access` / `host_environment` | The worker's machine or checkout needs fixing before it can continue (stale branch, missing tool, workspace setup failed) |
| `needs_access` / `live_infrastructure` | Needs your OK to change a live system |
| `legacy_human_task`, tag `human` | A step only a person can do; once done, mark it done |
| tag `post_deploy` | Can only be checked after a deploy, by watching production |
| `dependency_not_promoted` | Paused until a prerequisite ships or a date passes (say which, from `blocker`) |
| `is_blocked` | Waiting on N unfinished Tasks (name the root one) |
| `failed` | The worker gave up: <last error, in a sentence> |
| `is_stalled` | Marked in progress, but nothing has happened since <time> |
| `rescope_local` | Drop the part that needs production and close on local proof |
| `access_granted` | You've granted the access; let the worker retry |
| lease | "who's working on it" |

## 5. The report

Order groups by what the user can do right now, quickest first:

1. **Answer and go** — has a question and a recommended answer.
2. **Needs you outside ArchDev** — access, credentials, live-system
   approval, human-only steps whose blockers are done.
3. **Broken or stuck** — failed, stalled, churn, no recorded reason.
4. **Probably stale** — duplicates, superseded, already delivered.
5. **Waiting on other Tasks** — grouped by root blocker, so clearing one
   root shows how much it frees.
6. **Waiting for a deploy** — nothing to do until it ships.

Open with one line of totals per group, then the groups as numbered lists:

```
Auditing 36 Tasks assigned to Calvin Grunewald — 6 need you now.

1. Answer and go (2)
   1.1 Clients receive org task changes over SSE instead of polling
       Waiting on: your OK to move the worker's old checkout onto main.
       Why: the checkout predates code it depends on; its retry work is saved.
       Suggested: approve the supported recovery. · paused today · tsk_0zCP…
```

For blocked work, draw the chain to the root blocker:

```
Cloud factory enabled for first org   (waits for deploy)
  └─ Live staging proof: nodes claim a task and open a PR   (needs you: staging creds)
       └─ 12 more Tasks wait on this one
```

When the audit has more than about 15 Tasks, also offer the report as a
page (an HTML artifact, if the harness can publish one): one card per Task
with the plain-language lines up front, evidence and IDs folded away, and
the groups as sections. The terminal report stays the source of what to
act on.

## 6. Walk through it with the user

Go group by group, in report order. For each Task (or a batch of
same-shaped Tasks) offer concrete choices and wait. Use the harness's
question tool if it has one; otherwise a numbered list.

- Accept the recommended answer
- Answer differently (type it)
- I've granted the access / here's the evidence
- Drop the production part and close on local proof (`rescope_local`)
- Split the human step into its own Task
- Cancel it (duplicate / no longer needed)
- Skip for now

One "yes" covers only the Task it was asked about, unless the user says it
covers a batch ("accept all the recommended ones in group 1"). Before an
answer, check for earlier direction in the comments: answering without
knowing a prior answer was reverted repeats the mistake.

## 7. Act (approved changes only)

Run each change, then append it to `actions.jsonl` with the Task, the
command, and the result.

| Decision | Command |
|---|---|
| Accept recommended | `tasks answer <id> --accept-recommended --expected-version <v>` |
| Custom answer | `tasks answer <id> "<answer>" --expected-version <v>` |
| Access granted | `tasks answer <id> "<what was granted>" --outcome access_granted --expected-version <v>` |
| Evidence supplied | `tasks answer <id> "<note>" --outcome evidence --evidence <link> --expected-version <v>` |
| Close on local proof | `tasks answer <id> "<why>" --outcome rescope_local --drop-acceptance "<exact item>" --expected-version <v>` |
| Human step done | Confirm its blockers are done (`deps list`), then `tasks answer <id> "<what was done>"`. This marks it done at once, so only after the user says the step really happened |
| Missing dependency | `tasks deps add <id> --blocked-by <prereq>` |
| Split a human step | `tasks create "<step>" --tag human --epic "<epic>" --project <prj>`, then straight away `tasks update <new> --status paused` (`create` has no status flag; until the update lands the Task is open, and the `human` tag is the only thing keeping workers off it), `tasks deps add <new> --blocked-by <implementation>` and `tasks deps add <rollout-or-epic-close> --blocked-by <new>` |
| Done blocker never shipped | `tasks reopen <blocker>` (dependents re-block) |
| Cancel | `tasks comment <id> "<why, and the replacement Task>"`, then `tasks update <id> --status cancelled` (check `tasks update --help` lists the status first; if the update is refused, report it rather than trying another route) |
| Factory-owned, not answerable | comment the fix, then ask the overseer or its human to resume; do not flip status |

- `tasks answer` records the answer, comments `[human:answer]` and
  reopens the Task for the next worker. `--expected-version` refuses if
  the Task changed since the inbox read; re-read the inbox row and re-ask
  the user instead of retrying with a newer version.
- `--standing` applies the answer to matching future pauses. Use it only
  when the user asks for a standing rule.
- `--tag` replaces the whole tag set: re-pass the existing tags
  (including `archdev-plan`, `plan:<id>`, `plan-key:<key>`) when adding one.
- Pass long text from a file (`--description "$(cat file.md)"`).
- Every status change gets a comment saying why and what it unblocks.
- Approval to answer a Task is not approval to touch live
  infrastructure. If an answer approves live-system steps, the user's
  answer is the approval for those steps only as worded.

## 8. Finish

Re-run the inventory list calls and report:

1. **Changed:** each Task, the action, and what it unblocked (newly ready
   dependents from `tasks ready --epic "<epic>"`).
2. **Still needs you:** the open questions, by Task title.
3. **Skipped:** Tasks the user passed on.
4. **Not actionable yet:** blocked or post-deploy work, with its root
   blocker.
5. **Couldn't explain:** Tasks with no recorded reason, and who to ask.
