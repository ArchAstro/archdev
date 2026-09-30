# Map

Goal: record the approved repository workflow in `archdev.json` under
`activity`, then install hooks in the approved scope. This is an agent
implementation reference, not a list of commands for the user.

Follow [the installation guide](https://archdev.ai/install.md) first. User-wide
installation does not authorize repository mapping: skip this phase unless
repository placement or separate mapping was explicitly approved.

## 1. Init

1. If `archdev.json` exists in the repo root, keep it. It opts the repo
   in; the local daemon is not involved.
2. If absent: `"$archdev" repo map init` (§2) creates `archdev.json`
   along with the activity skeleton. A CLI that refuses here predates
   this; request an approved software upgrade, then check `--local` support.
3. Do not run `repo init` (`jobs repo enable`) for onboarding. It
   clones a private repository and registers it with the local daemon,
   which only jobs, Factory, and PR watching need. `repo status` does
   not check it.
4. Personal/model overrides (`modelAliases`, `factory.model`, provider
   accounts) belong in gitignored `archdev.local.json`, never in the
   checked-in file. Re-run `"$archdev" check` after editing.

## 2. Scaffold and interview

1. If the mapping is already complete, leave it unchanged. Otherwise run
   `"$archdev" repo map init` to scaffold the `activity` skeleton —
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
Harnesses: `claude|codex|cursor|gemini|copilot|opencode|grok|pi|archdev`
+ free text. PR providers: `github|gitlab|bitbucket|forgejo|azure` + …
VCS: `git|jj|sapling|hg|svn|…`. `check` enforces the schema; re-run it
after editing.

## 4. Install hooks in the approved scope

Explain that session activity goes to the organization's stream, where other
members can read it. Require explicit reporting consent before installation.

**For this repository**, from its Git root:

```sh
"$archdev" repo hook setup --local
```

This prepares Claude Code, Codex, Grok, Pi, and ArchDev, even if those tools are
not installed yet. It preserves other tools' settings and user-wide hooks.
Claude uses shareable `.claude/settings.json`; the other paths are
`.codex/hooks.json`, `.grok/hooks/archdev.json`, `.pi/extensions/archdev.js`,
and `.archdev/hooks.json`. Missing-binary callbacks provide installation
guidance without downloads. Node.js is required for shared JSON callbacks.
Codex and Grok require project trust; never approve it automatically. Reload
Pi after installing its extension. Share files only through approved code
review, never automatic commits.

**For me on this machine**, only after that explicit choice:

```sh
"$archdev" repo hook setup
```

This configures detected user-wide harnesses, not repository files. It does
not authorize initializing shared repository configuration. `--harness
claude codex` selects particular harnesses in either scope. Preserve the
scope when repairing or removing hooks: refresh existing hooks with
`repo hook setup --refresh --local` for repository placement, or
`repo hook setup --refresh` for user-wide placement. Bare setup is a first
installation action, not a repair: it can clear opt-outs. Reinstall an opted-out
tool only after separate approval: verify that the resolved executable matches
the harness PATH, then use `repo hook setup --harness <name> --force`, retaining
the selected scope. This may clear only the approved harness's opt-out; never
use `--force` to bypass a PATH mismatch.
Repository removals use `--local`; user-wide removals omit it. `--uninstall --local` removes
only ArchDev's repository hooks. User-wide uninstall records an opt-out;
leave opted-out harnesses alone unless the user explicitly requests reinstall.
Never use `--force` just to silence a readiness check.

The binary bootstrap never installs or refreshes hooks. `repo status --json`
can identify missing/stale wiring, but a remediation is not permission to
change scope. Check the actual files and test activation in a new trusted
session when possible; file creation alone does not prove activation.
If a different `archdev` on PATH prevents setup, repair PATH with permission
rather than forcing setup or falling back to global hooks.
