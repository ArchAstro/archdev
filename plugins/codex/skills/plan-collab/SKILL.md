---
name: plan-collab
description: Use when an agent should co-edit a markdown plan live with a person in the browser through the local `archdev plan collab` seat — starting a plan, waiting for and answering the page's signals (tab-completion requests, "ask" questions about a selection, agent requests, run undo and review, file conflicts, plan approval), writing review suggestions as CriticMarkup, or reporting run status. Triggers include "collab on this plan", "plan collab", "co-edit the plan", "answer the plan page", "complete.request", "ask.request", "agent.request", and a `.collab.json` handle file.
---

# Plan collab

A plan is a markdown Artifact edited live by a person in the browser and by
your **local seat**: the `archdev plan collab start` process, which joins the
Artifact channel as an agent actor and relays signals to you. The plan lives
only in the Artifact; nothing is written to disk. You never touch the channel directly. You drive the
seat with short-lived commands that find it through a **handle file**.

```
browser  <--OT ops + signals-->  Artifact channel  <-->  seat (archdev plan collab start)
                                                              ^  loopback + handle file
                                              you: signals / read / suggest / complete / apply / run
```

`archdev plan collab --help` and each verb's `--help` list the commands; the
CLI is the authority when it disagrees with this file. Every verb prints one
JSON object per line. Everything needs a signed-in user session.

## Activity and risk ownership

Follow the `archdev` skill for activity reporting. Plan/task lifecycle events
retain their `risk.plan` / `risk.task` assessments. Server automation owns hosted
PR and code-region grading: report PR events without fetching, waiting for,
reusing, or attaching a server grade. No local assessment, annotation or stop
hold is required.

## 1. Start the seat

```sh
archdev plan collab start --file plan.md [--handle plan.collab.json] [--artifact <id>] [--agent <id>] [--model @alias]
```

- `start` creates a plan Artifact seeded once from `--file` (or reuses
  `--artifact`). The seat never reads or writes that file again; it is a
  starting draft, not a copy of the plan. Read the plan with `read`.
- `start` prints a `started` event with the page `url`, then **keeps running**. Run it
  in the background and read its stdout; stop it with Ctrl-C.
- The handle defaults to `<file>.collab.json`, beside the seed file. It holds a loopback port and a
  capability token. Never print, commit or share it. The seat deletes it on
  exit; `start` refuses to run if the handle already exists.
- With `--model @alias` (a configured model alias) the seat answers ghost
  completions itself and you only see the signals. Without it the seat tells
  the page it has no completer and ghost suggestions are off; any
  `complete.request` an older page still sends is yours to answer.
- Tell the person the `url` from the `started` event.

Seat stdout events: `started`, `signal` (every relayed signal),
`completion.required` (you must answer a completion) and `report.required`
(plan approved, see section 4).

## 2. The loop

```sh
archdev plan collab signals --handle plan.collab.json
```

With no `--input`, `signals` **waits** for the next signal, prints it and
acknowledges it, so a signal is not lost if you restart. Handle one, answer
it, call `signals` again. Envelope:

```json
{"kind":"ask.request","to":"…","from":"<actor id>","revision":12,"payload":{…}}
```

Rules that apply to every answer:

1. **Positions are Unicode code points**, not bytes, UTF-16 units or
   graphemes. `🌍` is one position.
2. **Revisions go stale.** `read` returns `content`, `revision` and the parsed
   `suggestions`. `apply`, `suggest` and `complete` fail with a stale-revision
   error if you pass any revision but the current one: run `read`, redo the
   position math against the new text, retry. Never reuse positions from an
   older `read`.
3. Any edit, from you or the person, cancels pending completions.
4. Reply to a requester with `"to":"actor:<from>"` using the request's `from`.

## 3. Signal kinds

Received signals and what to do:

| Signal (payload) | Do |
|---|---|
| `complete.request {request, position, revision}` | Ghost text for the cursor. Compose a short continuation, then `complete`. |
| `complete.cancel {request}` | Drop that request. The seat already cancelled it. |
| `ask.request {id, intent, range:[from,to], quote, text}` | Person asked about a selection (`intent:"edit"`) or asked a question (`intent:"chat"`). Edit: write a suggestion over `range` with `suggest`. Both: then `agent.reply`. |
| `agent.request {id, text, section?}` | A task for you. Do it (run status, then `suggest` or `apply`), then `agent.reply`. |
| `run.stop {run}` | The person pressed Stop. Stop writing for that run and send its `run.status` with `state:"stopped"`. |
| `plan.tasks.request {request, revision}` | The person asked to break the approved plan into tasks. Reply with `plan.tasks.result` (section 4). |
| `run.undo {run}` | Revert that run: apply the inverse of what it wrote (section 5). |
| `run.reviewed {run}` | The person reviewed the run. Nothing to send. |
| `plan.approved {revision}` | Plan frozen. Report it (section 4). Stop editing. |
| `plan.reopened {revision}` | Editing is allowed again. |

Sent by you:

| Signal | Command |
|---|---|
| `complete.suggestion {request, position, text, alternatives[]}` | `complete` |
| `run.status {run, state, steps[], ranges[]}` | `run` |
| `agent.reply {request, text}` | `signals --input` |
| `plan.tasks.result {request, revision, tasks[]}` | `signals --input` |

**Every `ask.request` and `agent.request` ends with an `agent.reply`** whose
`request` is the payload's `id`. The page shows the prompt as "Queued" and
keeps the plan from being approved until that reply arrives; a suggestion
alone does not clear it.

### Ghost completion (`complete.request`)

Ghost text is **never written into the document**; it only travels as a
signal. Read the document, choose text to insert at `position`, then:

```sh
archdev plan collab complete --handle plan.collab.json --input \
  '{"to":"<from>","request":<payload.request>,"revision":<payload.revision>,"position":<payload.position>,"text":"…","alternatives":[]}'
```

Pass `request`, `revision` and `position` back unchanged. It fails with
"canceled, replaced or unknown" when the request was cancelled or the document
moved on; drop it, do not retry. Keep text short and do not repeat what is
already after the cursor.

The next keystroke cancels a request, usually within a second. An agent that
handles one command at a time rarely answers in time, so for working ghost
text start the seat with `--model @alias` and let the seat answer them.

### Ask about a selection (`ask.request`)

`intent:"chat"` is a question from the agent panel with no selection: answer
it in the `agent.reply` text and do not edit. `intent:"edit"` asks for a
change. Answer by editing, not chatting. Rewrite `range` as a CriticMarkup
suggestion the person accepts or rejects:

```sh
archdev plan collab suggest --handle plan.collab.json --input \
  '{"revision":<current>,"range":[<from>,<to>],"text":"<replacement>","id":"s_<8 chars a-z0-9>","author":"<your name>"}'
```

- Empty `range` inserts, empty `text` deletes, both non-empty replaces.
- `id` is `s_` plus eight lowercase base-36 characters, fresh each time.
- `author` is a one-line label for the suggestion.
- It fails if the range overlaps pending markup, sits in a fenced code block,
  or `text` contains `{++ {-- {~~ {>> ++} --} ~~} <<}` or `~>`. Split the edit
  or shorten the range; there is no escape syntax.
- `quote` is the selected text at ask time; if `read` shows it moved, find it
  again before using positions.
- An empty `range` with an empty `quote` (Ask with no selection) inserts at
  that position.

Then clear the prompt with a one-line reply, edit or chat:

```sh
archdev plan collab signals --handle plan.collab.json --input \
  '{"kind":"agent.reply","to":"actor:<from>","payload":{"request":"<payload.id>","text":"…"}}'
```

### Agent task (`agent.request`)

1. Send `run.status` with `state:"working"` (section 5).
2. Read, then change the plan. Prefer `suggest` when the person should
   review each change; use `apply` for whole-section rewrites they asked for.
   `apply` takes the complete new document and sends the smallest diff:

   ```sh
   archdev plan collab apply --handle plan.collab.json --input '{"revision":<current>,"text":"<full document>"}'
   ```
3. Send `run.status` with `state:"done"` and the ranges you wrote.
4. Reply with a one-line summary:

   ```sh
   archdev plan collab signals --handle plan.collab.json --input \
     '{"kind":"agent.reply","to":"actor:<from>","payload":{"request":"<id>","text":"…"}}'
   ```

Review suggestions are plain text in the markdown, not channel messages:
`{~~old~>new~~}`, `{++add++}` or `{--del--}`, immediately followed by
`{>>id:s_xxxxxxxx by:Name<<}`. OT anchors them and checkpoints persist them.
`read` lists the pending ones. Do not hand-write markup with `apply`; use
`suggest`, which validates it.

## 4. Approval

On `plan.approved` the seat prints a `report.required` event naming
`risk.plan` and `log post plan.updated`. Follow the `archdev` skill's plan
reporting rules for that post. After approval do not edit until
`plan.reopened`.

### Break into tasks (`plan.tasks.request`)

After approval the person can ask for a draft task graph. Read the plan, draft
tasks from its steps, and reply to the requester with the same `request` and
`revision`:

```sh
archdev plan collab signals --handle plan.collab.json --input \
  '{"kind":"plan.tasks.result","to":"actor:<from>","payload":{"request":"<payload.request>","revision":<payload.revision>,"tasks":[{"key":"t1","title":"…","risk":"low","area":"…","dependsOn":[]}]}}'
```

`risk` is `low`, `medium` or `high`; `dependsOn` lists other task `key`s. The
page shows the draft and offers `archdev tasks review start`; follow the
`tasks` skill from there.

## 5. Runs and undo

A run is one unit of agent work the person can review and undo.

```sh
archdev plan collab run --handle plan.collab.json --input \
  '{"to":"all","payload":{"run":"r1","state":"working","steps":[{"text":"Reading plan","done":true}],"ranges":[[120,180]]}}'
```

- `state` is `working`, `done` or `stopped`. Update the same `run` id as you
  go; `steps` are `{text, done}`, `ranges` are the `[from,to]` code-point
  spans you wrote, in the document at send time.
- Use `stopped` if you abandon the work.
- On `run.undo`, `read`, locate the text that run wrote (its last reported
  ranges, shifted by later edits), and `apply` the document with exactly that
  text removed. Do not undo more than that run. Then send `run.status` for it
  with `"undone":true` and `"reviewed":true`, keeping its `run` id; the page
  keeps the run open and approval blocked until it sees them:

  ```sh
  archdev plan collab run --handle plan.collab.json --input \
    '{"to":"all","payload":{"run":"r1","state":"done","steps":[{"text":"Undone","done":true}],"ranges":[],"undone":true,"reviewed":true}}'
  ```

## Gotchas

1. The seat is one process per plan. Keep it running while you work; if
   `signals` says the handle is invalid, the seat has exited, so start again.
2. Handle one signal at a time and answer each; unanswered requests make the
   page look stuck.
3. Never fabricate a signal the person did not trigger.
4. Editing the seed file changes nothing in the plan. Change the plan with
   `suggest` or `apply`.
