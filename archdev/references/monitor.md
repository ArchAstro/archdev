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
5. Was a PR created, updated, or closed? (pr `detection`: …)
6. Otherwise, is this worth a free-text note? → `agent.message`. When in
   doubt, log the note — ambiguous observations beat silent ones, but
   never invent a structured event.

## Report

- Free text: `"$archdev" log <text>` — posts to the org room as event
  `agent.message`.
- Structured: author the payload via `archdev extract context
  <extractor> <ref>` → write JSON → `archdev extract run <extractor>
  <ref> --runner file:<path>` → `archdev log --event <type>
  --payload-file <path> [--message <one-line summary>]`.
  Retries of the same logical event pass `--idempotency-key` (hook
  start derives `activity:<event>:<session>`); otherwise each call gets
  a fresh random key.
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
