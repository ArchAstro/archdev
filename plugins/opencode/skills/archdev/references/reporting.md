# Structured plan and task reporting

## Report

- Free text: `"$archdev" log post --project <id> "<text>"` — posts to the organization stream as event
  `agent.message`.
- Structured: `plan.*` and `task.*` events carry a sealed risk
  assessment under the CLI's pinned risk definitions; `pr.*`, `commit.*`, and
  `agent.*` events carry none, and the CLI rejects either mistake. The
  risk definition is the resource type, never the event name:
  `task.started` seals under `risk.task`, not `risk.task.started`.

  | Family | Risk definition | Extractor and ref | Subject source | Events |
  |---|---|---|---|---|
  | task | `risk.task` | `task.lifecycle <task id>` | `archdev:task:<task id>` | `task.created`, `task.started`, `task.updated`, `task.closed` |
  | plan | `risk.plan` | `plan.created <plan path>` | `archdev:plan:<plan path>` | `plan.created`, `plan.started`, `plan.updated` |

  In order, for a task (swap in the plan row; `<dir>` is any
  scratch directory outside the checkout), each step spelled out under
  Risk assessments below:
  1. `"$archdev" extract brief risk.task --out <dir>/brief/` — the
     rubric (DEFINITION.md, INPUT_SCHEMA.json, OUTPUT_SCHEMA.json,
     example.json, `brief.json`). Fetch once per definition per session;
     reuse it while `brief.json`'s digest is unchanged.
  2. Judgment: author `<dir>/judgment.json` as `{input, assessment}`.
     `input.subject.source.source` is the subject source from the table;
     `input.producer.role` is one of `author`, `assessor`, or `human`
     (`author` when you wrote the work).
  3. `"$archdev" extract finalize risk.task <dir>/judgment.json
     --out <dir>/sealed/` — validates, derives the combined grade, and
     writes `<dir>/sealed/result.json`. Fix what the named stage reports.
  4. Mitigate, then recompute. For each medium or high risk driver the
     assessment names, reduce the risk in the subject itself: fix the
     code, add the missing test or guard, split the unverifiable step,
     tighten the plan. Then re-author the judgment from the changed
     subject and finalize again. Never lower a grade by editing the
     assessment alone. At most two rounds, and only within the work's
     existing scope; a fix that would expand scope stays a residual
     risk. Name what you mitigated and what remains in `--message`.
  5. `"$archdev" extract context task.lifecycle <task id> --json` prints
     the event value's `jsonSchema` and, on current CLIs, these steps
     filled in for the subject under `authoring`. Author
     `<dir>/event.json` from the schema with its `"risk"` field set to
     the whole JSON object in `<dir>/sealed/result.json`, and its
     lifecycle matching the event name.
  6. Optional check: `"$archdev" extract run task.lifecycle <task id>
     --runner file:<dir>/event.json --sink stdout`.
  7. `"$archdev" log post --project <id> --event task.started
     --payload-file <dir>/event.json --assessment <dir>/sealed/result.json
     --message "<one-line summary>"`.
  Every structured post must read well to a human in the stream, whatever
  its schema. The CLI renders the payload as text (`▶ Task tsk_1
  started: …`, then `- Risk: medium`), and `--message` becomes the
  headline above it. Always pass `--message`: a full sentence saying what
  happened and why it matters, not the event name or a JSON fragment.
  Retries of the same logical event pass `--idempotency-key` (hook
  start derives `activity:<event>:<session>`); otherwise each call gets
  a fresh random key. If the stream is unreachable after the post is
  built, the CLI saves it to the outbox and reports `queued`; a
  background worker delivers it with the same key — do not re-send.
  Attachments cap at 64 KB encoded: cite less, or move bodies to
  `missingInputs`, when finalize succeeds but log reports oversize.
- Events without an assessment (`pr.*`, `commit.*`, `agent.*`):
  `"$archdev" extract context <extractor> <ref> --json` prints the value
  schema; author the value into `<dir>/event.json` and post it with
  `"$archdev" log post --project <id> --event <event> --payload-file <dir>/event.json --message "<one-line summary>"`.
  `--payload-file` takes the value object, never an extraction
  envelope. When the value comes from
  `"$archdev" extract run <extractor> <ref> --sink file:<dir>/out/`,
  the sink writes a nested envelope `{key, provenance, schema, value}`
  several directories down (find it with
  `find <dir>/out -name '*.json'`), and passing that file fails with
  `Unrecognized keys: "schema", "key", "provenance", "value"`. Extract
  the envelope value file first:
  `jq .value <envelope.json> > <dir>/event.json`.

## Plan and task risk assessments

Every `plan.*` and `task.*` event retains its required assessment under
`risk.plan` or `risk.task`. Follow the sequence under Report: read the pinned
brief, author `{input, assessment}`, finalize, embed the complete result in
`risk`, and post with `--assessment`. The resource type determines the rubric,
never the event name. Read `DEFINITION.md`; do not grade from memory.

Keep versioned subject evidence, producer identity, prior-answer exposure,
coverage and limitations. Distinguish inspected source, test source, observed
execution and attributed claims. Assess uncertainty and consequence separately;
the CLI derives combined risk. Missing evidence is unassessed, never low.
Mitigate within scope and recompute at most twice; do not lower a grade by
editing the assessment alone.
