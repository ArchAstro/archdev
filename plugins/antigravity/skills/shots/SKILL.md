---
name: shots
description: Use when an agent should capture, publish or read screenshots and movies with `archdev shots` — checking whether Shots is on, publishing stills of UI work into `.astroshot/<feature>/`, rendering React, Ink or PTY fixtures to PNG, recording browser, terminal, macOS window or frame-sequence movies, reading a person's Astroshots review comments (`review.json`), uploading a run for web review (which also posts the stills to the Company Room), or authoring and reading user stories. Triggers include "take a screenshot", "capture shots", "record a movie of this flow", "what did the reviewer say", ".astroshot", "user story", "upload the shots", and the "ArchDev shots" hook reminder.
---

# Shots

`archdev shots` turns UI work into reviewable evidence. A capture writes a PNG
(or a poster PNG plus a video) into `.astroshot/<feature>/` at the worktree
root and records it in that directory's `manifest.json`. A person reviews the
frames in the Astroshots app or in `archdev shots review`, and their decisions
and comments land in `review.json` next to the images. You read that feedback
back with `archdev shots status`.

Everything here needs ArchDev 0.53.0 or newer; check `archdev --version` and,
if it is older, ask the person to run `archdev upgrade`. `archdev shots --help` lists
the commands; every subcommand has its own `--help`, and the CLI is the
authority when it disagrees with this file.

## Activity and risk ownership

Follow the `archdev` skill for activity reporting. Plan/task lifecycle events
retain their `risk.plan` / `risk.task` assessments. Server automation owns hosted
PR and code-region grading: report PR events without fetching, waiting for,
reusing, or attaching a server grade. No local assessment, annotation or stop
hold is required.

## 1. Check that Shots is on before anything else

Shots is off by default, and the setting belongs to the person, not to you.
Every `archdev shots` command except `doctor` and `--help` refuses while it is
off, exits 1 and prints:

```text
archdev shots is off. Enable it with: archdev settings set shots on
```

Check first:

```sh
archdev shots doctor
```

`doctor` is read-only: it starts no browser and writes nothing. Its first line
is `archdev shots is on` or the off message above, and it exits 0 only when
Shots is on. The other lines say where it found the tools each mode needs:

| Tool | Needed for |
|---|---|
| Chrome | React stills and browser movies; also PTY and frames movies when ffmpeg is missing |
| Node (22 or newer) and the Node helper | React and Ink stills, and browser movie scripts |
| ffmpeg | encoding movies (optional: without it Chrome encodes them, always as WebM) |
| ffprobe | movie metadata |

A missing tool only blocks the modes that need it. `archdev shots doctor --json`
gives the same report as JSON (`setting`, then one object per tool with
`path` and `needed_for`).

`doctor` does not check the Node helper's npm packages, and the helper the
CLI ships has none installed. React and Ink stills and `movie run --script`
fail with `astroshot node helper could not load "tsx/esm/api"` (or `"vite"`,
`"playwright-core"`) until those packages sit next to a helper copy. See
"Node helper packages" under Troubleshooting. PTY stills, captures and
movies without `--script` do not use them.

`archdev settings get` shows `Shots: on (config)` and `Shots upload: auto
(config)` rows once the person has set them; before that it shows no Shots
rows, which means both defaults (off, manual).

### When Shots is off

Ask the person to turn it on. Tell them to run this in their own terminal,
outside the agent session:

```sh
archdev settings set shots on
```

Do not try to enable it yourself. `archdev settings set shots …` and
`archdev settings set shots-upload …` refuse inside an agent session or
without an interactive terminal ("Shots settings require a human terminal
outside an agent session"), and that includes commands a harness runs for
the person from the chat (such as Claude Code's `!` prefix). Do not edit the
ArchDev config file, set a different `ARCHDEV_PROFILE` or `--profile`, or
otherwise route around the refusal: the setting is the person's consent to
have screenshots taken. If they decline, carry on without captures and say
which evidence is missing.

The setting is stored per ArchDev profile. If the session runs with
`ARCHDEV_PROFILE=<name>` or `--profile <name>`, the person must enable that
profile: `archdev --profile <name> settings set shots on`. The off message
does not include the profile name.

### Upload preference

`archdev settings set shots-upload auto|manual` (default `manual`) is the
person's preference for sending a session's captures to ArchDev for web
review. It has the same human-terminal rule. With `manual`, upload only when
the person asks (section 6).

### Unattended harnesses

A test harness that runs without a person at the keyboard can keep its own
profile with Shots on, for example a profile named `astroshot-harness` whose
`config.json` the harness writes with `{"shots":{"enabled":"on"}}`, and run
`ARCHDEV_PROFILE=astroshot-harness archdev shots capture …`. That pattern is
for harness code a team has reviewed and committed. It is not a way to
capture in an interactive session where the person has not turned Shots on.

## 2. Publish stills

`archdev shots capture` publishes an existing image (PNG, JPEG, WebP or GIF),
or takes a PNG from an `agent-browser` session, into `.astroshot/<feature>/`.
It prints the path it wrote.

```sh
archdev shots capture --feature account-settings --slug dialog \
  --title "Account dialog" \
  --description "Name and email fields are editable." \
  --source ./account-dialog.png

archdev shots capture --feature account-settings --slug saved \
  --title "Saved" \
  --description "The success toast is visible after saving." \
  --url /account --viewport 1280x800 \
  --from-agent-browser "$SESSION"
```

- `--feature` is kebab-case (`[a-z0-9-]+`). `stories` and `friction-logs` are
  reserved for user stories and are refused.
- `--slug` is `[a-z0-9][a-z0-9_-]*`. Files are numbered: `0001-dialog.png`,
  `0002-saved.png`. Numbering continues from the highest file already in the
  directory.
- `--source PATH` and `--from-agent-browser SESSION` are mutually exclusive.
  The browser form runs `agent-browser --session SESSION screenshot`; it takes
  a full-page screenshot unless you pass `--no-full` (viewport only) or
  `--selector SEL` (one element). `agent-browser` must be on `PATH`, and a
  session name that does not exist yet starts a new, blank session, so pass
  the name of the session you have been driving.
- The image is validated before anything is written: bytes that do not match
  the file extension fail with `not a valid .<ext> image: …` and leave the
  directory unchanged. The published file keeps the source's extension.
- `--title` defaults to the slug in title case (`saved` becomes "Saved");
  `--description` should say what the frame
  proves. `--url` and `--viewport` are free-form context shown to the
  reviewer.
- `--root DIR` overrides the worktree root. By default the root is the Git
  top level of the current directory (or the current directory outside Git).

### Runs

`manifest.json` holds one run at a time: a `run_id`, a `status` and the
`shots` captured in that run.

- A capture with the default `--status running` appends to the current run
  while that run's status is `running`.
- `--status pass`, `fail` or `idle` on a capture appends that shot and closes
  the run. To close a run without a new shot:

  ```sh
  archdev shots capture --feature account-settings --status pass --finalize
  ```

  The `--status` is what closes the run: `--finalize` without it sets the
  status to `running`, exits 0 and leaves the run open. `--finalize` refuses
  `--source` and `--from-agent-browser`.
- The next capture after a closed run starts a new run with a fresh run id.
  Earlier images stay on disk.
- `--run-id ID` pins the run: captures with the same id append to it (and
  reopen it if it was closed). `--finalize --run-id ID` refuses when the
  manifest's run is a different one (`manifest run_id "…" does not match
  "…"`). A multi-step harness should pass one `--run-id` to every capture
  and to the final `--finalize`.
- A capture with a different `--run-id` replaces the current run, even one
  still `running`, without a warning. Two harnesses must not share a
  feature name.

Read review comments (section 5) before you close a run or start a new one.
Comments are scoped to the run they were written in, so once a new run
starts, `archdev shots status` no longer shows them.

`pass` and `fail` describe whether your journey ran, never whether a person
looked at it. Review state lives only in `review.json` (section 5).

Captures in one feature directory are serialized by a lock directory,
`.capture.lock`. See Troubleshooting for lock errors.

## 3. Render fixtures to PNG

Use a fixture when a component or terminal state can be reproduced without
running the whole application. Pick the smallest boundary that shows the
state:

| State to show | Command |
|---|---|
| A React component with fixed props | `archdev shots react` |
| An Ink component tree in a fixed state | `archdev shots ink` |
| A real terminal program and its keyboard flow | `archdev shots pty` |
| Routing, sign-in, live data, the whole app shell | drive the app with `agent-browser`, then `archdev shots capture --from-agent-browser` |

Each takes the fixture path and either `-o, --out PATH` (write a PNG and
print `wrote PATH`) or `--feature F --slug S` (render and publish into
`.astroshot/F/` in one step, with optional `--title` and `--description`).
Fixture rendering always uses the Git top level as the root and appends to
the feature's current run; use `-o` plus `archdev shots capture` when you
need `--run-id`, `--status` or `--root`.

Fixtures, their imports and PTY commands run with your permissions. A
temporary browser or pseudoterminal is not a sandbox, so review fixtures you
did not write before rendering them.

### React

Needs Chrome, Node and the helper packages (see section 1), plus `react` and
`react-dom` in the fixture's project. The fixture default-exports the
component and its capture settings:

```tsx
import { AccountDialog } from "../src/AccountDialog";

export default {
  width: 960,
  height: 900,
  background: "transparent",
  selector: "[role=dialog]",
  waitFor: "text=Save",
  settleMs: 200,
  component: <AccountDialog accountName="Acme" onClose={() => {}} />,
};
```

Settings: `width` and `height` (viewport, default 1280×800), `background`,
`selector` (element to capture), `waitFor` (selector or `text=…` that must be
visible), `settleMs`, `fullPage`, `stripOverlay`, `omitBackground`.

```sh
archdev shots react fixtures/account-dialog.tsx -o account-dialog.png
archdev shots react fixtures/account-dialog.tsx --feature account-settings --slug dialog --title "Account dialog"
```

Import the production component, give it synthetic props, and mock network
and server-only modules. For aliases, global styles, deduplicated packages
and stubbed modules, put a `react-shot.config.ts` (or `.mts`, `.js`, `.mjs`)
next to the app package exporting `root`, `alias`, `styles`,
`postcssConfig`, `dedupe` and `stubModules`. `--root` picks the package root
when discovery is ambiguous, `--config` names the config file, `--width` and
`--height` override the fixture, and `--headed` shows the browser.

Several fixtures at once, from a YAML manifest:

```yaml
shots:
  - fixture: fixtures/account-dialog.tsx
    out: screenshots/account-dialog.png
  - fixture: fixtures/empty-state.tsx
    out: screenshots/empty-state.png
    width: 640
```

```sh
archdev shots react batch shots.yaml
```

`fixture` and `out` are relative to the manifest's directory. Batch output
goes to the `out` paths only; publish the results with `archdev shots
capture --source` if they belong in the review stream.

### Ink

Needs Node and the helper packages (see section 1), and `ink` 7 and `react`
19 installed in the fixture's project. That project's `package.json` needs
`"type": "module"`; otherwise rendering fails with `Top-level await is
currently not supported with the "cjs" output format`.

```tsx
import React from "react";
import { Box, Text } from "ink";

export default {
  cols: 72,
  rows: 18,
  expectText: ["Install agent", "Continue"],
  component: (
    <Box flexDirection="column">
      <Text bold>Install agent</Text>
      <Text color="cyan">Continue</Text>
    </Box>
  ),
};
```

```sh
archdev shots ink fixtures/install-wizard.tsx -o install-wizard.png
archdev shots ink batch terminal-shots.yaml --out-dir screenshots
```

`--cols`, `--rows` and `--scale` (up to 4) override the fixture. The batch
manifest has the same `shots: [{fixture, out}]` shape as React's.

### PTY

Runs a real program in a pseudoterminal. Build the program first. The
fixture is YAML (or JSON with a `.json` extension):

```yaml
version: 1
command: ./target/debug/install-wizard
args: []
cwd: ..
cols: 100
rows: 30
timeoutMs: 15000
actions:
  - waitFor: Choose an option
  - key: down
  - key: enter
  - waitFor: Ready
expectText:
  - Ready
```

```sh
archdev shots pty fixtures/install-wizard.yaml -o install-wizard.png
archdev shots pty fixtures/install-wizard.yaml --feature install-wizard --slug ready --title "Ready"
```

- `command` runs directly, without a shell; `cwd` is relative to the fixture.
  On Windows, point at the `.exe`: `.cmd` and `.bat` need a shell.
- Actions: `waitFor` (optional `timeoutMs`), `waitForExit: true`, `key`
  (`enter`, `up`, `down`, `left`, `right`, `tab`, `escape`, `backspace`,
  `space`, `ctrl-c`, `ctrl-d`), `text` (typed literally) and `pauseMs`.
  Prefer `waitFor` over pauses, and end with distinctive `expectText`.
- A nonzero exit fails the capture unless the fixture sets
  `allowNonZeroExit: true`. `env` adds environment variables.
- Mouse input, resizing mid-run and Sixel graphics are not modelled.

Open every PNG you produce and check it before you publish or report it:
clipping, wrapping, loading states, colors, and private data.

## 4. Record movies

Movies show a journey; stills remain the evidence for individual states.
Every movie writes a poster PNG and a video into `.astroshot/<feature>/` and
adds them to the manifest as one shot. Review state attaches to the poster
file. The video is WebM unless you pass `--format mp4`, and `mp4` takes
effect only for PTY and frames movies with ffmpeg on `PATH`: browser movies
and every movie encoded without ffmpeg are WebM. Read the extension of
`videoPath` in the JSON the command prints.

Choose the source from what you are recording:

| Recording | Source |
|---|---|
| A web page or single-page app | `--source browser` |
| A terminal program | `--source pty` |
| A native macOS app window | `--source desktop.window` |
| PNG frames your own code produces | `movie start` / `push-frame` / `stop` |

Do not record a browser or a terminal by grabbing its desktop window.

```sh
archdev shots movie run --source browser --feature checkout --slug purchase \
  --url http://localhost:3000/checkout --script fixtures/purchase.mjs \
  --size 1280x800 --run-id checkout-r1

archdev shots movie run --source pty --feature install-wizard --slug walkthrough \
  --fixture fixtures/install-wizard.yaml

archdev shots movie run --source desktop.window --feature onboarding --slug first-run \
  --bundle-id com.example.App --duration-ms 4000
```

- Shared options: `--feature`, `--slug` (kebab-case), `--title`,
  `--description`, `--run-id`, `--root`, `--size WxH`, `--fps` (up to 60),
  `--format`, `--status`.
- `browser`: `--url`, `--settle-ms`, `--headed`, and `--script PATH`, an ES
  module whose default export is `async (page) => { … }` and receives the
  Playwright page after `--url` loads (scripts need the helper packages,
  section 1). Without `--url` or `--script` it
  records a placeholder page.
- `pty`: `--fixture`, the same YAML as a PTY still.
- `desktop.window` (macOS only): select the window with `--bundle-id`,
  `--window-id`, `--title-regex`, `--owner`, `--pid` or `--pick`; record for
  `--duration-ms` (default 3000) with `--cursor` to show the pointer. It
  refuses nearly blank frames unless you pass `--allow-blank`.
  `archdev shots movie list-windows` lists candidate windows, and
  `archdev shots movie check-screen-access` reports the Screen Recording
  permission (exit 2 when denied; `--request` asks for it, `--open-settings`
  opens System Settings).
- An option that belongs to another source is refused, for example
  `--url cannot be used with --source pty`.

Frames you produce yourself:

```sh
archdev shots movie start --feature report --slug build-up --size 1280x720 --fps 4
archdev shots movie push-frame --feature report --file frames/0001.png
archdev shots movie mark --feature report --slug totals --note "Totals appear"
archdev shots movie push-frame --feature report --file frames/0002.png
archdev shots movie stop --feature report --status pass
```

`mark` adds a chapter at the current time. `start` prints the session as
JSON, including its `id`. When a feature has more than one open session,
pass `--session ID` to `push-frame`, `mark` and `stop`: without it the
command picks one of them, not necessarily the one you started.

Close a movie run the same way as stills, with the same run id:

```sh
archdev shots movie finalize --feature checkout --run-id checkout-r1 --status pass
```

## 5. Read review feedback

```sh
archdev shots status
archdev shots status --feature account-settings --json
```

The table lists every image in each feature directory with its kind, state
and comment count, then totals. `--json` prints `{root, features: [{feature,
run_id, status, shots: [{file, slug, title, description, kind, video,
duration_ms, chapters, captured_at, viewport, url, state, comments: [{id,
body, created_at}]}]}], totals: {seen, stale, unseen}}`.

| State | Meaning |
|---|---|
| `seen` | A person marked this exact image (same SHA-256) seen in the current run |
| `stale` | A person reviewed an earlier version of this file; the bytes changed since. Comments still apply |
| `unseen` | No review for this file in the current run |

`status` lists every image in the directory, including earlier runs, and
those report `unseen` because review is scoped to the manifest's current
run. The current run's files are the ones listed under `shots` in
`.astroshot/<feature>/manifest.json`; check there before reporting a frame
as unreviewed.

Read status while the run you are asking about is still the current one,
then report every comment to the person, address it, and capture new
images.
Never write `review.json` yourself or mark your own work seen: the person
reviews the new bytes.

`archdev shots review` opens the review tray in a terminal (macOS and Linux;
it needs an interactive terminal, so it is for the person, not for you).
Arguments are roots to watch; `--no-graphics`, `--no-watch` and `--no-index`
turn off images, live reload and the index cache.

## 6. Upload for web review

```sh
archdev shots upload --feature account-settings --project <prj_id> \
  --root "$(git rev-parse --show-toplevel)"
```

Uploads the feature's current run (the shots in `manifest.json`, with movie
videos) to ArchDev so it can be reviewed on the web, then posts the run's
stills once to the organization's Company Room so teammates see the images in
the stream. It needs `archdev auth login` with a user session (agent-only
sessions cannot upload), a Git `origin` remote, and a manifest with
`"version": 1`. It prints one `<file> <media-id>` line per uploaded file, then
the group key and the review URL, then `stream <status> [<message-id>]`;
`--json` prints `{group_key, url, uploads, stream_post}`. Unchanged files are
skipped, and `uploads.json` in the feature directory remembers what was sent.
Exit 1 means at least one file failed; the errors are on stderr.

`--root` defaults to the current directory, not the Git top level, so pass it
when you are not at the worktree root.

### The Company Room post

Pass `--project <prj_id>` so the post is filed under the project the work
belongs to, the same ID you use on `archdev log post`. Find it with
`archdev projects list --query "<subject>"`; the `archdev` skill explains how
to choose one. Without `--project` the stills are still posted, and the CLI
prints the usual untagged warning.

The post is an ordinary stream note that links the Shots page and attaches up
to ten stills by their uploaded Media id (movie video rows are not attached;
their poster still is). Its `stream_post.status` tells you what happened:

- `posted`: a new message was made.
- `unchanged`: these exact stills were already posted; nothing was sent.
- `retagged`: an earlier post for these stills now carries the given
  `--project`. This is how to fix an upload you ran without one: rerun the
  same command with `--project`.
- `no_room`: the organization has no Company Room yet; the upload still
  succeeded.

A post that fails leaves the upload complete, is reported on stderr with exit
1, and is retried by rerunning the same command; the retry lands on one
message, never two. A recapture (new bytes) posts again. Do not also attach
the PNGs to a `done` or `start` post with `-a`; the upload post is the
stream's copy.

Upload only when the person asked for it, or when their `shots-upload`
setting is `auto`.

## 7. User stories

A user story is a scripted walk through the product from a user's point of
view, run by an agent, with a screenshot and notes per step. Stories live
under `.astroshot/stories/<slug>/` (the older `.astroshot/friction-logs/`
tree is still read) and appear in the review tray's User stories tab, not in
the Shots stream. Do not publish story screenshots with `archdev shots
capture`.

```sh
archdev shots stories new invite-teammate --title "Invite a teammate" \
  --description "An admin invites a new member and the member accepts."
archdev shots stories list
archdev shots stories show invite-teammate
RUN_DIR="$(archdev shots stories run-dir invite-teammate)"
```

- `new` creates `prompt.md` (headings: Goal, Persona, Environment,
  Preconditions, Steps, Out of scope, Output contract) and `meta.json` with
  status `draft`. `--title` is required and the slug is kebab-case. An
  existing slug fails with `File exists (os error 17)`.
- `list` prints `slug, title, status, run count, latest run id` per story;
  `--json` adds whether the latest run was acknowledged.
- `show <slug>` prints the prompt and the steps of the latest run;
  `--run ID` picks another run, `--json` returns `{prompt_md, steps}`.
- `run-dir <slug>` creates an empty `runs/<timestamp>/` directory and prints
  its path. Use a new one for every attempt.
- The stories commands always use the Git top level as the root.

Fill in `prompt.md` with 5 to 12 user actions, each with what "done" looks
like. Keep secrets out of it; name environment variables instead. Use a
clean session or a throwaway account, not the person's own login, unless the
prompt says otherwise.

To run a story, for each step: do the action, wait for the done signal, save
a numbered PNG into `$RUN_DIR` (`0001-open-settings.png`), and append one
JSON line to `$RUN_DIR/log.jsonl`:

```json
{"step": 1, "id": "open-settings", "title": "Open settings", "description": "Opened /settings from the avatar menu.", "transcript": "I open settings from the avatar menu. The entry is easy to find, but the page loads without a heading, so I check the URL before moving on to Members.", "screenshots": ["0001-open-settings.png"], "good": ["Settings is one click from the avatar"], "improve": ["The settings page has no visible heading"], "url": "/settings"}
```

`step`, `id`, `title`, `description`, `transcript`, `screenshots`, `good`
and `improve` are required (`good` and `improve` may be empty arrays);
`url` and `captured_at` are optional. `transcript` is spoken narration, two
to five sentences in plain prose, that says what you did, what worked and
what did not, and leads into the next step. Set `meta.json` `status` to
`running` while you work and `complete` or `failed` at the end. If you stop
before writing any step, delete the empty run directory. Report the run
directory, the step count, and the most important `improve` items.

## Hook reminders

When Shots is on and the ArchDev hooks are installed, editing UI files
(`.tsx`, `.jsx`, `.css`, `.scss`, `.html`, `.heex`, and similar; a
repository can set its own list in `archdev.json` under `shots.ui_globs`)
makes the hook print a reminder that starts with `ArchDev shots: Capture
shots for the flows touched by these UI edits`. A still published from the
same agent session into the same worktree clears it (`archdev shots capture`,
or `react`, `ink` or `pty` with `--feature`); movies and captures run from
another session (a subagent, the person's terminal) do not. When the edits
need no screenshot (a refactor with no
visible change), dismiss it with the session id from the reminder:

```sh
archdev repo hook dismiss --harness <harness> --session <session-id> \
  --evidence shots --reason "No visible UI change"
```

## Troubleshooting

| Message | Cause and fix |
|---|---|
| `archdev shots is off. Enable it with: archdev settings set shots on` | Shots is off for this profile. Ask the person to run the command in their own terminal (section 1). |
| `Shots settings require a human terminal outside an agent session` | You tried to change the setting. Ask the person instead. |
| `not a valid .<ext> image: PATH` | The bytes do not match the extension (a JPEG saved as `.png`, an HTML error page, a truncated file). Recapture it or fix the extension. |
| `unsupported image extension …` | Stills must be `.png`, `.jpg`, `.jpeg`, `.webp` or `.gif`. |
| `astroshot node helper could not load "tsx/esm/api"` (or `vite`, `@vitejs/plugin-react`, `playwright-core`) | The helper's npm packages are missing. See "Node helper packages" below. |
| `timed out after Ns waiting for capture lock: …/.capture.lock` | Another capture into the same feature is running. The wait defaults to 120 seconds; `ASTROSHOT_LOCK_TIMEOUT_SECONDS=N` changes it. |
| `stale capture lock from dead pid N: …; remove it and retry` | A capture process died holding the lock. Confirm no capture is running, then remove that `.capture.lock` directory. |
| `feature must be kebab-case …`, `slug must be …`, `reserved feature: …` | Rename the feature or slug (section 2). |
| `manifest run_id "…" does not match "…"` | `--finalize --run-id` names a run that is not the current one. |
| `--X cannot be used with --source Y` | The movie option belongs to another source. |
| `… Install Chrome or set ASTROSHOT_CHROME` | No Chrome found for React stills or browser movies. Install Chrome, or set `ASTROSHOT_CHROME` to its executable. |
| `Not authenticated. Run archdev auth login first.` | `upload` needs a signed-in user. |
| `Media upload needs a user session with media:write` | The session is agent-only. The person signs in with `archdev auth login`. |
| `archdev shots review needs an interactive terminal.` | The review tray is for the person; read feedback with `archdev shots status`. |
| `Screen Recording denied …` | macOS permission for `desktop.window`. The person grants it in System Settings and restarts the app that launched the command. |

### Node helper packages

React and Ink stills and browser movie scripts run in a Node helper script
(`helper.mjs`) that loads `tsx`, `vite`, `@vitejs/plugin-react` and
`playwright-core` from its own directory, not from your project. The copy the
CLI writes to its cache has no packages next to it, so these modes fail until
someone installs them. Installing npm packages changes the person's machine:
ask first. With their agreement, keep a helper copy in a directory that has
the packages, and point the CLI at it with `ASTROSHOT_NODE_HELPER`:

```sh
helper_dir="$HOME/.local/share/archdev-shots-helper"
mkdir -p "$helper_dir"
cp "$(ls -t "$HOME"/.cache/astroshot/node-helper/*/helper.mjs "$HOME"/Library/Caches/astroshot/node-helper/*/helper.mjs 2>/dev/null | head -n 1)" "$helper_dir/"
npm install --prefix "$helper_dir" tsx vite @vitejs/plugin-react playwright-core
export ASTROSHOT_NODE_HELPER="$helper_dir/helper.mjs"
```

The cached `helper.mjs` exists after the first React or Ink attempt, even a
failed one. Copy it again after upgrading ArchDev: the helper and the CLI
speak a versioned protocol.
