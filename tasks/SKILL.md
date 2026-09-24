---
name: tasks
description: Use when someone wants to turn a conversation or coding-harness plan into ArchDev Tasks, build a dependency graph, review a task plan in the browser, collect feedback and revise it until approved, or resume work on saved Tasks.
---

# Tasks

Use ArchDev Tasks as the shared plan and work record. You drive drafting,
browser handoff, feedback collection, revisions, and save verification; the
human reviews the plan in the web UI. This works from any coding harness and
does not require Factory, a daemon, a resident agent, or `archdev setup`.

## 1. Connect this machine

Resolve the absolute directory containing this loaded `SKILL.md`, independently
of the current repository. Its bootstrap installs ArchDev when missing and
updates an older CLI that lacks the review commands. Capture its stdout, which
is the executable's absolute path; diagnostics go to stderr.

Bash/Zsh:

```sh
archdev="$(bash /absolute/path/to/tasks/scripts/bootstrap.sh)"
```

Fish:

```fish
set archdev (bash /absolute/path/to/tasks/scripts/bootstrap.sh)
```

Windows PowerShell:

```powershell
$archdev = & powershell -NoProfile -File 'C:\absolute\path\to\tasks\scripts\bootstrap.ps1'
```

Commands below use `"$archdev"`; PowerShell uses `& $archdev` with the same
arguments. If bootstrap fails, report its error and point to the
[official installer](https://github.com/ArchAstro/archdev#install).

1. Run `"$archdev" auth status`. If signed out, run `"$archdev" auth login`,
   let the human finish browser sign-in, then check status again.
2. Read `"$archdev" tasks guide` and `"$archdev" tasks graph schema` for the
   installed CLI's contract. Prefer `--json` for output you need to parse.
3. Choose the destination from the user's request and existing context.
   Review defaults to the signed-in user's personal Tasks. For team work,
   supply a known `--team <id>`; use `--repository <owner/repo>` when applicable.
   If the team is ambiguous, ask which team before saving. Never guess an ID.
4. When resuming work, inspect the existing Tasks and local plan/receipt before
   creating another plan. `tasks list --team <id>` and `tasks show <task-id>`
   expose existing work; consult their help for other scopes.

## 2. Turn the source into a draft DAG

A DAG is a task graph with prerequisite edges and no cycles. Draft locally
first; opening review does not create Tasks. Do not pre-create every node with
`tasks create`, or import it separately, before sending the same graph through
review: approval owns saving this plan.

1. **From conversation:** extract the requested outcome, agreed decisions,
   constraints, exclusions, and unresolved choices. Inspect relevant code when
   needed to make the tasks actionable. Do not invent requirements.
2. **From a harness plan:** read the actual plan artifact or harness-provided
   plan state. Translate its steps into graph nodes while preserving intent,
   acceptance criteria, references, and dependencies. A harness checklist is
   input, not a second task authority after saving. Use stable source IDs as
   node keys where possible; do not invent harness/session metadata.
3. Name tasks by observable outcome. Give each a concrete objective, acceptance
   criteria, and verification. For implementation work, name the planned
   end-to-end test file/scenario and the boundary and observable outcome it
   proves; identify any missing prerequisites honestly.
4. Add `depends_on` only where a task needs another task's result. Explain each
   edge with `dependency_reasons`. Leave independent tasks parallel. Every
   dependency must reference a node key in this graph; no self-edges or cycles.
5. Keep unresolved design choices in `major_decisions` for the human to review.
   Do not silently choose on their behalf when the choice changes scope.

Write a UTF-8 JSON file at a stable path, such as `plans/task-review.json`.
Use the graph schema's `action: "preview"` format. Required node fields are
`key`, `title`, `objective`, `acceptance`, and `verification`. The review command
also accepts optional `major_decisions` (not part of `tasks graph schema`).

```json
{
  "action": "preview",
  "epic": "Users can export their filtered results",
  "nodes": [
    {
      "key": "export-api",
      "title": "Export respects the user's filters",
      "objective": "Add the export endpoint using the existing filtered query.",
      "acceptance": ["Export includes exactly the authorized filtered results."],
      "verification": ["Planned tests/export-api.e2e.test.ts: filtered export crosses HTTP and database boundaries and asserts returned rows."],
      "scope": ["Export API"],
      "exclusions": ["Scheduled exports"]
    },
    {
      "key": "export-ui",
      "title": "Users can download filtered results",
      "objective": "Connect the results page's download action to the export endpoint.",
      "acceptance": ["The downloaded file matches the active filters."],
      "verification": ["Planned tests/export-ui.e2e.test.ts: download filtered results through the browser and inspect file contents."],
      "depends_on": ["export-api"],
      "dependency_reasons": {"export-api": "The download action needs the export endpoint."}
    }
  ],
  "major_decisions": [
    {
      "id": "export-format",
      "name": "Choose the export format",
      "description": "Which format should the first version support?",
      "options": ["CSV", "JSON"]
    }
  ]
}
```

Replace illustrative paths with this project's real planned proof. Optional
node fields also include `context`, `scope`, `exclusions`, `deliverables`,
`depends_on`, `dependency_reasons`, and `priority` (0–4).
Keep context concise and omit secrets and customer data. The CLI validates the
preview and computes its hash; do not manufacture `plan_hash`.

## 3. Check each task in isolation before review

The drafter has the whole conversation, so its tasks read as complete to it
even when they lean on context a worker will never see. Before opening review,
test each node with a reader that has only that node. Run exactly one round.

1. For every node, start a fresh subagent with no conversation history. Use
   a smaller, cheaper model than the one drafting the plan: the check needs
   careful reading, not deep reasoning. The harness knows its own model
   lineup, so pick its cheaper tier yourself rather than naming a fixed
   model. For example, Claude Code's Agent tool takes `model: "haiku"` or
   `"sonnet"`; other harnesses expose a mini or flash tier, or a per-agent
   model setting. If the harness cannot choose a subagent model, use its
   default. Prefer a read-only agent type or tool set (for example, Claude
   Code's `Explore`). Run the checks in parallel, batching if the harness
   limits concurrency. If the harness has no subagent facility, say so and
   skip this step; do not self-review in the main context as a substitute.
2. Give each subagent only that node's JSON object, copied verbatim from the
   draft, and the prompt below. Do not pass the plan file path, the epic, other
   nodes, the conversation, or your own summary.

   ```text
   Read-only review. Do not implement anything, edit files, or run commands.
   You may read the repository to confirm that referenced paths and symbols
   exist and that referenced commands are defined (package scripts, Makefile,
   CLI help).

   Judge whether you could implement the task below if it were all you
   received: you will not see the conversation that produced it or any other
   task. Treat depends_on keys as work that will already be done, and nothing
   more.

   Return only JSON, with no prose or code fence:
   {"ready": true|false,
    "gaps": [{"kind": "field" | "prerequisite",
              "field": "<node field this gap is about, or null>",
              "blocking": true|false,
              "question": "<what you would have to ask>",
              "why": "<what you would otherwise have to guess, or what you checked>"}]}

   kind "prerequisite" means the task needs work that neither it nor its
   depends_on provides. blocking is true when you could not start
   implementing without an answer; false when you could start but would have
   to guess partway through.

   Report a gap when you would have to guess: which files or components to
   change, the expected behavior or interface, an acceptance criterion you
   could not verify, a planned test that does not name its file, boundary, or
   assertion, a referenced path or symbol that does not exist, what a
   dependency provides, or a scope boundary. Do not report style preferences
   or propose redesigns. An empty gaps list is a valid answer.

   Task:
   <node JSON>
   ```

   If a reply is not valid JSON, use a JSON block inside it when present;
   otherwise list that node as unchecked in the summary. Do not guess its gaps.
3. Triage every returned gap in the main context, which has the full history:
   - **Answerable from the conversation or code:** add the answer to the node
     (`objective`, `context`, `acceptance`, `verification`, `scope`,
     `exclusions`, or `deliverables`). Write it so a reader without your
     history could act on it; name real paths and symbols.
   - **A choice only the human can make:** add or extend a `major_decisions`
     entry. Do not pick an answer to close the gap.
   - **Not a real gap** (already stated, or out of scope): leave the node as
     is and note why in the triage summary.

   Subagent questions are prompts for missing context, not requirements. Do
   not add scope, acceptance criteria, or decisions the source did not
   support. A confirmed `prerequisite` gap becomes a new node or a
   `depends_on` edge with its reason.
4. Do not re-run the check on revised nodes or on nodes added during triage.
   Give the human a short summary in the progress update before review: per
   task, gaps found, how each was resolved, any moved to `major_decisions`,
   and any node left unchecked.

## 4. Open the review and keep it running

```sh
"$archdev" tasks review start --file plans/task-review.json --no-open
```

Add the chosen `--team` and `--repository` flags to that command when needed.
Run it in the harness's persistent process/PTY facility: it stays running and
streams JSONL. Do not wrap it in a short timeout, wait for it to exit before
opening the page, or kill it when the command tool yields.

1. Read the `event: "ready"` record. Retain its `url`, `sessionFile`,
   `stateFile`, `revision`, and `planHash` along with the process handle.
2. Open that exact URL once in the human's main browser profile using the
   available browser/open tool. The page updates in place on revisions.
   If browser control is unavailable, hand the URL to the human. Without
   `--no-open`, the CLI attempts to open the default browser itself.
3. Tell the human where to review and that **Approve & save** writes Tasks to
   the selected destination in a progress update, then enter the feedback loop
   in the same turn. Opening the page and leaving its server running do not
   monitor feedback; do not end the turn with an invitation to review.

The URL and session handle contain a local bearer capability. Do not commit
or publish them, dump the handle contents, or put them in shared logs. The
browser must run on a machine that can reach this CLI's loopback server;
a remote sandbox's localhost is not the human's localhost. If that boundary
prevents review, arrange execution on the human's machine instead of claiming
the page is reachable or exposing the server publicly.

## 5. Listen, revise, and verify saving

Start the feedback cursor at `0` for this session.

```sh
"$archdev" tasks review feedback <sessionFile> --after <cursor>
"$archdev" tasks review status <sessionFile>
"$archdev" tasks review update <sessionFile> --file plans/task-review.json --revision <currentRevision>
```

Keep the turn active and drive this loop until the current revision is saved
and verified, the user explicitly pauses/cancels, or a concrete blocker needs
their input. Answer status questions in progress updates and continue polling;
an incidental interruption does not complete the review. After a blocker is
resolved or an interrupted turn resumes, read feedback from the retained cursor
and status before continuing; do not wait for the user to announce new feedback.

1. Read feedback and status. Feedback returns `{events, cursor}` without
   consuming events. Process new events, then retain the returned cursor.
   The start process also streams events; avoid processing the same sequence
   twice. Poll with a modest wait (for example 5–10 seconds), staying responsive
   to user messages; empty feedback is not approval or a reason to stop.
2. Match feedback to its `revision` and `planHash`. Read plan-wide,
   task-specific, and decision-specific notes. Map task IDs through the
   current status request to the stable node keys. Old-revision notes are
   historical context, not instructions to apply automatically to a new plan.
3. For requested changes, edit the same JSON file. Preserve keys for unchanged
   work; add keys for new work, remove obsolete nodes, and repair dependency
   edges. Resolve reviewed decisions in the plan and remove resolved entries
   from `major_decisions`. Explain briefly what changed and why.
4. Publish with the current revision from status. On a revision conflict,
   re-read status and feedback and reconcile; do not blindly retry with an
   incremented number. Retain the returned revision/hash. Continue on the
   existing browser page rather than starting another review session.
5. For approval, wait for status `saved` for the current revision/hash and
   inspect its `saved` receipt. `saving` is still in progress. `save_failed`
   may mean some Tasks were already written. For a transient failure, report
   the error, address it, and use the browser's save retry. If the error says
   a Task changed outside this review, inspect that Task, reconcile the draft,
   publish a new revision, and obtain fresh human approval; retrying the old
   revision cannot resolve that conflict. Keep the same receipt and session;
   do not recreate the plan to retry. Never submit approval through a private
   HTTP endpoint or click **Approve & save** on the human's behalf.
6. Verify returned task IDs with `tasks show <task-id>` and check prerequisite
   edges with `tasks deps list <task-id>` (follow pagination when present).
   Report the saved outcome and task IDs. If the user
   requests another revision, continue with the same plan and receipt.

The durable `stateFile` maps node keys to task IDs. Later approved revisions
update those IDs; removing a previously saved node closes its Task and retains
history. Preserve the receipt even after review ends. Restarting with the same
absolute plan path reuses the default receipt; if moving the plan, pass the
original `--state-file <path>`. A restarted server has a new session handle and
URL, so open its new ready URL and reset the feedback cursor. Do not delete a
receipt or change its destination to bypass an error.

When finished or cancelled, run `"$archdev" tasks review stop <sessionFile>`.
This stops the local server and removes its private session handle; it does
not delete saved Tasks. If explicitly pausing for later, retain the draft and
receipt and explain how to restart. Do not report a paused review as saved.

## 6. Work from the saved Tasks when asked

Approval of a plan saves Tasks; it does not itself request implementation.
When implementation is authorized, use the installed `tasks guide` lifecycle:

1. Read `tasks ready --explain --team <id>` (or the intended user scope).
2. Claim with `tasks claim <task-id> --session-name "<short name>"` before
   working. Retain the returned `lease_id` and `session_id`; readiness alone
   is not ownership.
3. Record progress with `tasks comment`. Use both `--lease-id` and
   `--session-id` on fenced updates, close, and release. Close only after
   verification; re-read ready Tasks when a prerequisite finishes.

When beginning an accessible team-owned task, set current attention with
`"$archdev" presence update --task <task-id>`. Check `presence --help` lists
`update` and `clear` first; if unavailable after the normal CLI upgrade,
report the limitation and continue the task lifecycle. Personal tasks remain
private: do not publish their IDs or change their ownership for presence.

When attention shifts to its PR or job, use
`"$archdev" presence update --pr 'owner/repo#123' --job <job-id>` with only the
references currently relevant. Each update replaces all previous references;
include `--task <task-id>` again only while it still describes your attention.
On finishing or handing off, use `"$archdev" presence clear` to remain idle.
This neither closes the task nor releases its lease. Run these commands in
the existing harness session; never substitute the task lease's `session_id`
for `CLAUDE_CODE_SESSION_ID` or `CODEX_THREAD_ID`. The CLI owns authentication,
expiry, and concurrency; do not build snapshots or emit room presence posts.
If an update is rejected, earlier attention remains: clear it if it no longer
applies, and report any failure. `--json` is supported; `superseded` means a
newer observation won and should not be overwritten by retrying older work.

Keep shared progress on these saved Tasks rather than creating duplicate
harness tasks. Use `tasks deps add <blocked-task> --blocked-by <prerequisite>`
for explicit changes to existing dependencies, and consult command help for
other lifecycle operations.

## 7. Audit and unblock paused or failed work

Run this only when the user asks for an audit of paused, failed, or stalled
Tasks. Do not start one on your own because you noticed paused work; mention
it and let the user decide. The goal is unblocking the graph safely, not
rubber-stamping status changes, and every change below still follows the
user's direction on decisions and scope.

1. **Inventory.** Page through work needing attention:
   ```sh
   "$archdev" tasks list --status paused --limit 100 --after-cursor <cursor>
   ```
   Repeat for `failed`, `open`, `in_review` (100 is the max page size).
   Group results by `epic`. `tasks list --epic "<epic>"` filters to one
   epic; `tasks list --status done` shows what already shipped there.

2. **Find why before changing anything.** The pause reason is rarely in
   the description. Read, in order: the Task's activity feed (status
   changes, lease claims/releases, who and when), then comments, then
   description progress notes. If the installed CLI lacks `tasks
   comments`/`tasks activity`, get the same data from `GET
   /api/v1/tasks/{id}/comments` and `GET /api/v1/tasks/{id}/activity`
   (cursor-paginated) via the ArchDev web app at `archdev.ai/tasks/<id>` —
   never by reading credential files to call the API directly. Prefer the
   CLI, then the web UI, then a human. A pause with no comment usually
   means a Factory overseer paused it via `factory_tasks`; ask the
   overseer or its human rather than guessing.

3. **Check for a live Factory before touching status.** `tasks update
   --status open` changes only the native status — it does not clear a
   Factory's local state, and the overseer re-pauses the Task within
   minutes. Look for recent lease claims by `factory:worker-N` in the
   activity feed. If a Factory owns the work: fix the spec or
   dependencies, then ask the overseer (or its human) to `resume` through
   `factory_tasks`. Do not fight an active overseer with native status
   flips.

4. **Classify each paused/failed Task, then act:**
   - **Spec underspecified or self-contradictory** (acceptance vs.
     deliverables disagree, objective vs. plan drifted, a recorded
     decision contradicted by later plan steps) → rewrite the
     description, record the decision with date and decider, comment
     what changed and why.
   - **Needs a human decision** → ask; record the decision in the
     description once made. Don't decide scope silently. Check for
     prior direction first — a decision made without knowing an earlier
     direction was reverted just repeats the mistake.
   - **Blocked on another Task** → `tasks deps add <task> --blocked-by
     <prereq>` instead of leaving it hand-parked with no edge.
   - **Factory/tooling bug surfaced by a worker** → file it as its own
     Task and add the dependency edge back to the blocked work.
   - **Acceptance a worker can't meet before merge** (production
     observation, human visual review, numeric approvals, real
     credentials) → split off a separate Task tagged `human` (add
     `needs-access` if applicable), blocked-by the implementation Task.
     The implementation Task closes on local proof only.
   - **Needs access/credentials** → leave paused, tag `needs-access`,
     comment the exact human action required.
   - **Duplicate or superseded** → cancel with a comment pointing at the
     replacement Task.
   - **A "done" prerequisite never actually shipped** (no commit/PR/
     result on the default branch) → reopen it; dependents re-block
     automatically. Verify against git on the default branch, not the
     Task's status field.
   - **Churn** (hundreds of versions, the same failure repeating,
     "workspace preparation failed" on retry) → stop retrying. Reset the
     spec, or ask for `restart_clean`. Destructive cleanup of retained
     work needs human authorization first.

5. **Batch per epic.** `tasks review` only safely edits an existing graph
   when you hold that plan's receipt/state file — a Factory-created plan
   keeps its receipt locally, so a new `tasks review` on it creates
   duplicates instead of updating it. Otherwise batch manually: write
   each task's new description to a file and run `tasks update` per task,
   keeping the same task IDs.

6. **Mechanics gotchas:**
   - `--tag` replaces the full tag set — re-pass existing tags (including
     `archdev-plan`, `plan:<id>`, `plan-key:<key>`) whenever adding one.
   - Build multi-flag commands as an argument array; zsh does not
     word-split a flags string.
   - Pass long descriptions from a file (`--description "$(cat
     file.md)"`) to avoid shell-quoting bugs.
   - Create new human-only Tasks paused and tagged `human` so Factory
     workers don't claim them.

7. **Comment every status change** with why and what it unblocks. A
   status change with no comment is as opaque to the next person as the
   pause it resolved.
