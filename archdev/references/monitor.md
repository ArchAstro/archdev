# Monitor

Goal: validate the mapped taxonomy against real sessions. The model is
the sensor — no daemon, no log tailing. Self-check at stopping points,
report hits with `archdev log`.

Run `"$archdev" repo monitor bootstrap` at session start. It prints the
self-check block generated from the repo's own `activity` taxonomy:
resource `detection` prompts, the closed event list, per-event
extraction schemas, and the report commands. The static block below is
the same shape for reference.

## Self-check block

At every stopping point, ask:

1. Did I start a session, get steered, or stop? → `agent.session_*`
2. Was a plan created, started, or updated? (plan `detection`: …)
3. Was a task created, started, updated, or closed? (task `detection`: …)
4. Was a commit created or pushed? (commit `detection`: …)
5. Was a PR created, updated, or closed? (pr `detection`: …) → on
   created, or updated with a new head, store its hunk metadata first
   (see Report).
6. Otherwise, is this worth a free-text note? → `agent.message`. When in
   doubt, log the note — ambiguous observations beat silent ones, but
   never invent a structured event.

## Report

- Free text: `"$archdev" log <text>` — posts to the org room as event
  `agent.message`.
- Structured: plan/task/pr events carry a sealed risk assessment;
  commit/agent events do not. Four steps:
  1. `"$archdev" extract brief risk.<type> --out ./brief/` — rubric for
     this session (instructions, input/output schemas, worked example).
     Fetch once per definition; reuse via the digest in `brief.json`.
  2. Author `{input, assessment}` JSON. The subject source must name the
     event subject exactly: `archdev:task:<id>`, `archdev:plan:<path>`,
     `archdev:pr:<owner/repo>#<num>` (`archdev:pr:local#<num>` with no
     repository). Every evidence item carries its body and an honest
     kind — `source` means you inspected it; second-hand material is
     `attributed-claim`; guesses are `inference`. Record
     producer/exposure including "unfrozen, agent-supplied input" in
     ambientContext. Name gaps in `missingInputs` and
     `coverage.unassessed` — unassessed is not low.
  3. `"$archdev" extract finalize risk.<type> ./judgment.json --out
     ./sealed/` — validates the schemas, derives the combined grade,
     prints the digest. Fix what the named stage reports.
  4. `"$archdev" log --event <type> --payload-file <fact> --assessment
     ./sealed/result.json --message "<one-line summary>"`.
  Every structured post must read well to a human in the room, whatever
  its schema. The CLI renders the payload as text (`▶ Task tsk_1
  started: …`, then `- Risk: medium`), and `--message` becomes the
  headline above it. Always pass `--message`: a full sentence saying what
  happened and why it matters, not the event name or a JSON fragment.
  Retries of the same logical event pass `--idempotency-key` (hook
  start derives `activity:<event>:<session>`); otherwise each call gets
  a fresh random key. Attachments cap at 64 KB encoded: cite less, or
  move bodies to `missingInputs`, when finalize succeeds but log
  reports oversize.
- PR hunk metadata: on `pr.created`, and on `pr.updated` when the head
  moved, store review annotations for the PR's current head *before*
  logging the event, so ArchDev opens the PR with its risk, theme, and
  note labels per hunk. `archdev publish` already does this; a PR opened
  any other way (`gh pr create`, the web UI) has none until you do:
  1. `"$archdev" extract context pr.review-annotations <num> --json` —
     copy identity from `key`; read `authoring` for the `auto_reviewed`
     paths a focus entry may not name.
  2. Author the value from the patches: sparse `risk` / `semantic_group`
     / `note` ranges covering every changed path, plus an optional
     `summary` (`intent`, `overall_risk`, up to five `focus` ranges).
  3. `"$archdev" extract run pr.review-annotations <num> --runner
     file:<answer.json> --json` — the default sink writes the
     `github_pr_review_annotations` object for that head. `cached` means
     that head already has annotations; do not `--force` over rows you did
     not write.
  4. Confirm with `"$archdev" extract show pr.review-annotations <num>
     --json`, then log the `pr.*` event.
  If step 3 fails (signed out, no GitHub origin, validation error), fix
  what it names or say so in the event's `--message`; never skip
  silently.
- Closed vocabulary: `agent.message`, `plan.created|started|updated`,
  `task.created|started|updated|closed`, `agent.session_started|
  session_stopped|steered`, `commit.created|pushed`,
  `pr.created|updated|closed`. Emit nothing else.

## Promotion

When an event fires reliably across sessions, say so in your report:
high-signal events (`commit.*`, `pr.*`) graduate from model attention
into the stop hook, and leave the self-check block. The block shrinks as
the taxonomy proves itself.

## Coexistence (invariants)

- Presence belongs to minimap (`minimap ping` and its publisher). Never
  fabricate presence, never set minimap fields or its `exhaust` type on
  activity posts, and never skip the real presence path.
- `rooms start|lesson|done|…` are team exhaust for substantial work —
  keep publishing them. Activity events are machine signals alongside,
  not instead. `agent.session_started` is not `rooms start`.
- Verify every post (check the returned message id). A failure before
  queueing means the event was NOT recorded — report it and retry after
  login/connectivity is restored. Never re-send a successfully queued
  event. Only the top-level session posts; subagents never post.
- Never post secrets, tokens, customer data, or unreviewed private
  content.
