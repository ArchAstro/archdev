# Bootstrap

Goal: an available ArchDev executable and the authentication required by the
requested operation. These commands are for the agent, not the user.

## Installation and consent

For first-time installation or a change in configuration scope, follow
[the agent installation guide](https://archdev.ai/install.md). Ask and wait for
**For me on this machine** or **For this repository**, and explain that setup
always reports session activity to the organization stream. Placement is the
only question; do not ask about reporting.

The guide covers prerequisites, verified binary installation, scoped core
skills, personal sign-in, and scoped hooks. Get approval before installing or
upgrading software. Binary installation and credentials are per-user in either
scope. Do not edit agent instruction files or commit changes without permission.

The Bash and PowerShell bootstrap scripts resolve or install the executable
and check its capabilities. They do not install or refresh hooks, install
skills, authenticate, or create repository configuration. Do not run them to
bypass the guide's consent steps.

## Version and login

1. `"$archdev" --version` (need 0.47.0+) and
   `"$archdev" repo hook setup --help` (must include `--local`). If the
   published release lacks repository setup, stop; never fall back globally.
2. `"$archdev" auth status`. For approved stream reporting, if unauthenticated,
   run `"$archdev" auth login` and keep the interactive process available while
   the user signs in. Do not request tokens in chat or copy another user's
   credentials. Local code inspection does not require an ArchDev account.
3. `auth logout` removes credentials. Never run it as a repair step.

## Model access only when requested

Session reporting does not require provider setup. A missing model-access
check is not a reason to configure a provider or block hook installation.
If the user requests an operation needing ArchDev model access:

1. Check `"$archdev" settings provider status`, independently of login.
2. If necessary and approved, run `"$archdev" agents setup` and let the user
   choose a provider interactively. `--provider openai --provider-email <email>`
   selects ChatGPT OAuth; `xai` selects Grok; `archdev` selects the model router
   (whose provider id is `platform`).
3. Verify the selected model and one small authorized request. Do not make
   paid model requests merely to verify session-hook installation.

Do not use full `"$archdev" setup` for guided installation or readiness repair.
Use the scoped primitives from the installation guide instead.

## Repository validation only in the approved scope

For repository placement or separately approved repository mapping,
`"$archdev" check` validates configuration without executing it. Keep existing
configuration and fix only relevant reported keys, then re-run. For user-wide
installation, do not initialize a repository to satisfy a readiness check.
