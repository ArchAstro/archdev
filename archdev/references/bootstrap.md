# Bootstrap

Goal: `archdev` installed and current, user logged in, model access
configured, repo wiring valid. `SKILL.md` step 0 runs `repo status`,
which checks all of this — the steps below are what each check means
and how to clear it.

## 1. Version and login

1. `"$archdev" --version` (need 0.46.5+), then `"$archdev" auth status`.
2. If unauthenticated: `"$archdev" auth login` (browser,
   copy/paste, or personal access token). Keep a persistent interactive
   process running while the human signs in; do not proceed headless.
3. `auth logout` removes credentials — never run it as a fix for anything.

## 2. Model access (separate from login)

ArchDev identity and BYO model credentials are different
authentications. Check both:

1. `"$archdev" settings provider status` — independent of `auth status`.
2. If no model access: from the target repo, run `"$archdev" agents
   setup` (agent-only onboarding: no Jobs, daemon, or private remotes).
   Choose interactively, or `--provider openai --provider-email <email>`
   for ChatGPT OAuth, `xai` for Grok, `archdev` for the model router.
   (`archdev` here is the setup selector; the provider id is `platform`.)
3. A provider login alone proves nothing about the next request — verify
   the actual selected model and one small authorized request when setup
   requires it. For existing model access, skip to the operation.

Full onboarding (`"$archdev" setup`) is for first-run only: auth +
provider + daemon + repo registration + model-guided config audit.
`--skills` installs skills for detected tools without other setup.

## 3. Validate the repo

`"$archdev" check` validates configuration without executing it. Success
criteria for this phase: `auth status` ok, provider status ok, `check`
clean. On failure, fix the reported keys and re-run — do not work around
them with other commands.
