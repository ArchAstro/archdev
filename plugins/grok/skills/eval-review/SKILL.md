---
name: eval-review
description: Use when a person needs to judge a set of outputs one at a time in the browser — rating model or agent outputs against criteria, comparing two candidates blind, labelling examples, or spot-checking generated summaries, diagrams or code changes. You write one JSON file with the items and the questions, host it locally with the bundled script, and ArchDev shows a keyboard-driven review deck with each item's picture, description, pull request and code; ratings save to a file you read back. Triggers include "have a human rate these", "set up an eval review", "let me go through the examples", "which of these is better", "human eval", "label these", and "collect feedback on these outputs".
---

# Eval review

Turn "can you look through these and tell me which are good" into a review a
person finishes quickly. You prepare the items and the questions; the person
rates them in ArchDev, one card at a time, with number keys. Their answers,
flags and notes land in a JSON file beside yours.

Use it when a person's judgment is the measurement: rating outputs, choosing
between candidates, labelling a sample, or checking a claim against code. Do
not use it to review a diff for merge (`archdev inspect local`) or a task plan
(the `tasks` skill).

## Activity and risk ownership

Follow the `archdev` skill for activity reporting. Plan/task lifecycle events
retain their `risk.plan` / `risk.task` assessments. Server automation owns hosted
PR and code-region grading: report PR events without fetching, waiting for,
reusing, or attaching a server grade. No local assessment, annotation or stop
hold is required.

## What the reviewer gets

- One item per card, a progress strip, and the next few items listed.
- Your criteria as rows of options. `1`-`9` answers the highlighted row,
  `↑` `↓` moves between rows, `J`/`K` moves between items, `↵` goes on once
  every row is answered.
- An answer can ask for one line of explanation, and every item has a notes box.
- The item's picture, with `Z` to enlarge. Parts of it can be flagged.
- References: a pull request or a file opens in a side panel with the
  description and the diff; `D` opens all the item's code.
- A summary at the end with tallies and whatever is still unrated.

## 1. Write the eval file

One JSON file holds everything. The full field list, the three exhibit kinds
and a complete example are in `references/format.md`; read it before writing
your first file. The shape:

```json
{
  "title": "Release note drafts",
  "criteria": [
    {
      "key": "accurate",
      "title": "Does it match the change?",
      "options": [
        { "value": "yes", "label": "Yes" },
        { "value": "partly", "label": "Partly" },
        { "value": "no", "label": "No" }
      ],
      "follow": { "no": "What is wrong?" }
    }
  ],
  "items": [
    {
      "key": "pr-482",
      "title": "Checkout retries a declined card once",
      "exhibit": { "kind": "image", "mediaType": "image/svg+xml", "data": "<svg …>", "alt": "Draft note" },
      "description": "Markdown shown beside the card.",
      "files": [{ "filename": "src/charge.ts", "status": "modified", "additions": 12, "deletions": 3, "patch": "@@ -1,3 +1,4 @@\n …" }]
    }
  ]
}
```

Writing good criteria:

1. Ask what the person can judge from the card. "Would you understand this
   from the picture alone?" works; "Is this good?" does not.
2. Two to nine options each, in the order a reader expects. A 1-5 scale is
   five options; label the ends ("1 wrong", "5 exact").
3. Add a `follow` prompt on the answers that mean something is wrong. That one
   line is usually the most useful thing you get back.
4. Three or four criteria is comfortable. More than seven slows the reviewer
   enough that they stop.
5. Put per-item facts in `hints` (word counts, a classifier's label), not in
   the criterion title.

Choosing the exhibit:

| The person is judging | Use |
|---|---|
| One picture, card or screenshot | `image` (SVG text or base64 PNG) |
| Which of two to four candidates is better | `compare`; shuffle the order per item yourself and keep the key in a separate file |
| Something they need to click inside, or a layout only you can draw | `frame`: your own HTML and script in a sandbox, see `references/format.md` |
| Text only | `frame` with the text as HTML, or no exhibit and the text in `description` |

For anything about a code change, include the pull request as a reference and
the diff as `files`, so the reviewer can check a claim without leaving the
card. Split a unified diff per file: each file's `patch` starts at its first
`@@` line.

## 2. Check it, then host it

Resolve the absolute directory containing this loaded `SKILL.md`; the script
is beside it. It needs Node 18 or newer and nothing else.

```sh
node <skill-dir>/scripts/serve.mjs eval.json --check   # lists every problem in the file
node <skill-dir>/scripts/serve.mjs eval.json           # hosts it and opens the browser
```

Fix everything `--check` reports before hosting; the web app rejects a session
it cannot show. Run the server in the background and leave it running: it is
what the browser reads from and saves to. It listens on loopback only, and the
link it prints carries a one-time token for this session. Do not paste the
link into a pull request, an issue or a chat channel.

If the server warns that the site did not serve `/eval-frame`, that ArchDev
deployment does not have eval review yet. Tell the person; do not work around
it.

Tell the person what you are asking them to judge, how many items there are,
and that their answers save as they go. Then wait. Do not rate items yourself.

## 3. Read the ratings

Ratings are written to `eval.json.ratings.json` after every change:

```json
{
  "pr-482": {
    "answers": { "accurate": "no" },
    "why": { "accurate": "says it retries twice" },
    "flagged": ["retry-count"],
    "note": "",
    "at": "2026-11-12T15:44:09.194Z"
  }
}
```

```sh
node <skill-dir>/scripts/serve.mjs eval.json --summary   # tallies and what is still unrated
```

When the person says they are done, or partway:

1. Run `--summary` for the counts, then read the ratings file for the `why`
   text, flags and notes. The explanations matter more than the tallies.
2. Report what they found in their words, grouped by what it means for the
   work: which items failed and why, what was flagged most, what they asked for.
3. For a blind comparison, join the answers with your key file before
   reporting; never show the key to the reviewer first.
4. Say how many items are unrated. A partial pass is a result, with its size
   stated.

Restarting the server keeps the saved ratings and makes a new link; a tab
opened from the old link cannot save, so send the new one.
