# Configure automation from repository evidence

Read this before writing pipelines, aliases, publication settings, or worktree
configuration. Mirror `archdev setup`'s audit → proposal → validation sequence.
Inside an ArchDev agent session, use its bundled `docs` tool first for the
relevant topics. That is an agent tool, not an `archdev docs` shell command.
External harnesses can use this reference and the installed commands' help;
`archdev check` is the executable contract for their final configuration.

## 1. Audit before proposing

1. Read tracked manifests recursively, not only the root package. Inspect
   contributor instructions, CI workflow steps, existing test/build scripts,
   primary remote/branch, and existing `.archdev` definitions.
2. For each proposed verification step, retain a repository-relative evidence
   path and the exact command, working directory, and required environment.
   Use the commands this repository actually runs, including nested packages.
3. Preserve working defaults when evidence does not justify an override. Setup
   generates `archdev-setup-validation` from validated repository commands,
   starting with a call to built-in `branch-validation`; it does not ask the
   model to invent executable policy. An empty proposal can be correct.
4. Keep deployments and live infrastructure operations out of a routine branch
   verification pipeline. A command's innocent name is not a sandbox: scripts
   execute repository code with full process authority.

For first-run setup, let the CLI query the authenticated provider catalog and
show the proposal. For manual model changes, inspect
`archdev settings provider status` and
`archdev --json settings provider models <platform|openai|xai>`.
Provider login lives under `settings provider login`; use its help for account
selection. Older builds expose `provider` at top level. If canonical help is
missing, update the CLI rather than inventing a settings key.

## 2. Put configuration at its owning layer

| Artifact | Purpose |
| --- | --- |
| `<repo>/archdev.json` | Checked-in pipelines, bindings, publish/review policy, worktree lifecycle, generated project identity |
| `~/.archdev/archdev.json` | User model preferences and provider accounts |
| `<repo>/archdev.local.json` | Gitignored personal model overrides for this checkout |
| `<repo>/.archdev/workflows` | Project model-driven workflows |
| `<repo>/.archdev/reviews` | Project review workflow definitions |

Checked-in project policy takes precedence over personal configuration.
Model aliases and preferred model selections use the opposite precedence:
repo-local → user → project. Project workflow/review definitions override
same-named user definitions under `~/.archdev/`. Do not confuse command
`pipelines` with model-driven workflows or a review's internal workflow.

Exact-commit daemon execution deliberately omits the checkout's mutable local
overlay. A local alias override that works interactively is not proof it will
apply to a queued job. Keep required aliases available in the configuration
sources that job actually loads. Do not move credentials into the project to
make a daemon see them, or replace CLI-generated local identity fields.

## 3. Compose a pipeline

This illustrative configuration adds a repository-owned test command after
the built-in review/fix pipeline. Replace the test command with audited argv;
merge these sections into existing configuration rather than overwriting it.

```json
{
  "publish": {"auto": false},
  "pipelines": {
    "repository-validation": {
      "steps": [
        {"id": "review-and-fix", "uses": "branch-validation"},
        {"id": "test", "run": ["npm", "test"], "cwd": "."}
      ]
    }
  },
  "pipeline_bindings": {"branch_update": "repository-validation"}
}
```

1. `branch-validation` runs adversarial review followed by fixes of supported
   findings and focused tests. Its fix phase can commit. Reuse it with `uses`
   instead of copying its prompts or creating a second review loop.
2. Steps run in order. Each needs a stable unique `id`. Use either `uses` for
   another pipeline or `run` for a nonempty argv array, never both. A pipeline
   call cannot also set command options. Shell expressions are not implicitly
   expanded; use repository scripts for cohesive multi-command logic.
3. Command steps can set repository-relative `cwd`, string-valued `env`, and
   `timeout_seconds` (1–86400). Do not override reserved `ARCHDEV_` variables.
   Choose timeouts from actual execution needs, not arbitrary short limits.
4. Failed verification must block success. Do not use `continue_on_error` to
   hide required checks or remove failing steps to make a job green.
5. `pipeline_bindings` routes events: `branch_update`,
   `pull_request_feedback`, `pull_request_rebase_conflict`, and
   `branch_rebase_conflict`. Prefer built-in PR/conflict pipelines unless a
   concrete requirement warrants changing them. Keep their host-owned
   publication/finalization boundaries intact.
6. Prior output arrives through stdin and `ARCHDEV_PREVIOUS_OUTPUT`;
   `ARCHDEV_PIPELINE_EVIDENCE` provides the ordered step record. Use those
   existing handoffs rather than inventing shared scratch-file protocols.

`publish.auto` controls the host's automatic GitHub publication after branch
validation. New setup defaults enable it; the example opts out for private
validation of submitted branches; it does not disable authored-PR discovery
or remediation in a registered repo. Check watcher authorization before setup.
Automatic publication requires `origin` and a real `main` branch.
If the verified primary branch differs and there is no supporting custom
pipeline, follow setup: disable automatic publication and omit `publish.base`.
Do not change the user's branch convention to accommodate the example.

## 4. Use model aliases deliberately

Replace the illustrative IDs with IDs returned by the authenticated live
catalog; do not paste guessed model names into working configuration.

```json
{
  "modelAliases": {
    "review": [
      {"provider": "openai", "model": "available-model-id"},
      {"provider": "platform", "model": "openai/available-model-id"}
    ]
  },
  "publish": {"model": ["@review"]}
}
```

1. An alias holds one `{provider, model}` object or an ordered nonempty array.
   Consumers select `@review`, a `provider/model` selector, or an ordered list.
   Include only providers/accounts the user intends to use and can authenticate.
2. Follow setup's restraint: define aliases used by an actual consumer, not a
   speculative catalog. Preserve the selected provider preference and existing
   overrides unless evidence warrants a change.
3. Fallback order is best-first. Each turn starts again at the first candidate.
   Authentication, quota, rate-limit, lookup, or transport errors can advance
   to the next candidate before output. A failure after streaming output does
   not replay the turn on another model; cancellation and invalid prompts stop.
4. `check` validates selector structure and references, not live capacity or
   account health. Verify catalog availability and a suitable focused model
   operation when the task warrants it; do not claim that JSON validation
   proved model execution.

## 5. Prepare worktrees and their runtime

A native daemon does not inherit every interactive shell/tool-manager setting.
Configure repository-owned worktree preparation when dependencies, generated
files, or toolchains are needed; do not assume an interactive Fish/Zsh startup
file will execute in a worker.

```json
{
  "worktree": {
    "hooks": {
      "after_worktree_create": {"run": ["tools/worktree/prepare-worktree"]},
      "after_worktree_delete": {"run": ["tools/worktree/cleanup-worktree"]}
    },
    "runtime_environment": {"run": ["tools/worktree/runtime-environment"]}
  }
}
```

These are example paths, not bundled scripts. Reuse actual repository helpers.
Creation hook owns installation/preparation. The runtime command reports one
JSON object of environment variable names to string values on stdout; send
its diagnostics to stderr. Cleanup runs after Git removes the checkout and
should be idempotent. A failed hook or malformed runtime environment prevents
work from proceeding; do not bypass it with a manually created worktree.

Daemon lifecycle hooks come from the resolved upstream base: main/master for
branch work, the PR base for PR automation, or the private default branch when
no upstream base is available. The registered checkout is not consulted for
that control revision. The rebased job checkout owns its runtime environment,
pipeline, and publication settings. Personal overlays do not supply project worktree hooks. A feature
branch's new lifecycle hook is therefore not guaranteed to bootstrap that
same branch's job. Inspect which revision owns the failing stage.

## 6. Validate and prove the change

1. Run `archdev --json check` from the repository. Inspect reported sources,
   resolved pipelines/bindings, review workflow, and worktree settings.
2. Review the diff and ensure executable commands are evidence-backed and
   secrets/identity were not copied into it. Commit only when authorized.
3. Run one focused, authorized job through the intended path: a committed
   snapshot with `jobs run <pipeline>`, or branch submission with
   `jobs repo submit`. `--here` is appropriate only when current-checkout
   mutation is intended; it does not prove isolated daemon execution.
4. Inspect the durable job's exact input, step outcomes, result, and expected
   publication. Report separately what passed static validation and what ran
   through Git, native runner, model provider, or GitHub boundaries.
