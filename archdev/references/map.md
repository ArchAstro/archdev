# Map

Goal: opt the repo into ArchDev and record how it works in `archdev.json`
under the `activity` key, then install the monitor hooks.

## 1. Init

1. If `archdev.json` exists in the repo root, keep it.
2. If absent: `"$archdev" repo init [--name <unique-private-repo-name>]`
   (same as `init` / `jobs repo enable`). This creates `archdev.json`
   with `local.project_id` / `local.repo_name`.
3. Personal/model overrides (`modelAliases`, `factory.model`, provider
   accounts) belong in gitignored `archdev.local.json`, never in the
   checked-in file. Re-run `"$archdev" check` after editing.

## 2. Scaffold and interview

1. Run `"$archdev" repo map init` to scaffold the `activity` skeleton —
   prefilled from the resolved `tasks.backend`, existing plan dirs,
   origin remote, and VCS topology. It merges missing keys and refuses
   to overwrite a filled taxonomy without `--force`.
2. Interview to fill the blanks. Sources: repo layout, docs,
   `archdev.json`, past trajectories, tracker IDs/links.
   - **Plan:** where do plans/docs live (`docs/plans/`, `plans/`,
     `specs/`)? What skill produces them? What style/format?
   - **Code:** what harness, what cloud agents, what orchestrator
     (Factory vs one-off `agents run`)? Tasks are optional for ordinary
     sessions — do not create Tasks/DAGs just to start an agent.
   - **Review:** GitHub PRs (`inspect`/`reviews` + `publish`), direct
     push, or local-only?
   - **Instruction style:** tasks, chat prompts, or session pulls?
     Record every tracker, not just `tasks.backend`. Confirm live
     backends with `"$archdev" tasks list|show`; confirm remote
     trackers (Linear, Jira, …) from links or integrations in
     trajectories.
   - **Record what is really there.** A tracker counts only where its
     records live. An ID prefix or title tag (`linear: LIN-12`,
     `tickets/ENT-7.md`) with no workspace link, API, or integration is
     not that tracker: record the real store (`github` issues,
     `markdown` files) and note the naming in `style`.

## 3. The taxonomy

Persist findings under top-level `activity` (additive; old CLIs ignore
it). Arrays everywhere — repos use several of everything. `detection` is
required per resource: it is what the monitor phase consumes.

```jsonc
{ "activity": { "version": 1, "resources": {
  "plan":   { "origins": ["skill", "manual"],
              "environments": ["local"],
              "style": "...", "locations": ["docs/plans/"],
              "detection": "how to recognize plan work live" },
  "task":   { "origins": ["manual"],
              "systems": ["beads", "linear"],
              "environments": ["local", "remote"],
              "style": "per-system notes, e.g. micro-tasks in beads, planning in Linear",
              "detection": "how to recognize task events live" },
  "agent":  { "harnesses": ["claude"],
              "environments": ["local"],
              "detection": "how to recognize session start/stop/steer" },
  "commit": { "detection": "how to recognize commits/pushes" },
  "pr":     { "providers": ["github"],
              "detection": "how to recognize PR open/update/close" },
  "repo":   { "vcs": "git", "worktrees": ["..."],
              "detection": "how to recognize repo/worktree instances" }
}}}
```

Task-system vocabulary (open list): `archdev` (local,
`tasks.backend`), `beads` (local, `.beads/`), `github` (remote,
issues/projects), `linear`, `jira`, `asana`, `trello`, `notion`,
`clickup`, `azure-boards`, `youtrack`, `todoist`, `markdown`
(`TODO.md`, `tasks/`), `manual` (chat-assigned, no tracker).
Harnesses: `claude|codex|cursor|gemini|copilot|opencode|grok|archdev`
+ free text. PR providers: `github|gitlab|bitbucket|forgejo|azure` + …
VCS: `git|jj|sapling|hg|svn|…`. `check` enforces the schema; re-run it
after editing.

## 4. Install hooks (final map step)

Install now — session coverage starts immediately:

```sh
"$archdev" repo hook setup [--harness claude|codex|grok|archdev] [--force]
```

Installs SessionStart, UserPromptSubmit, PostToolUse and Stop (Grok: no
UserPromptSubmit). Without `--harness`, covers every installed harness
(config-dir presence = installed); warns when none is found — pass
`--harness <name>` to install anyway. `--uninstall` removes them.
Harnesses outside that list: hand-author entries invoking `repo hook
start|prompt|post-tool|stop --spec <N>` (copy `N` from `repo hook setup
--help`). Verify with `repo status`: it reports missing hooks and hooks
from an older `--spec` as stale.

Each installed command carries `--spec N`, the hook wiring version of the
CLI that wrote it. This skill's bootstrap runs `repo hook setup --refresh`
after checking the CLI, which updates only harnesses that already have
archdev hooks. Setup refuses when the `archdev` on PATH (what hooks run)
is older than the CLI running setup; upgrade or fix PATH rather than
passing `--force`.
