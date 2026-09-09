# Providers and your own subscriptions

Use this reference for model access, `settings provider`, account rotation,
and aliases. It describes ArchDev's implemented integrations; do not promise
subscription eligibility, unlimited usage, particular plan entitlements, or
prices from this document. Verify actual login and model execution.

## 1. Choose the intended credential path

| Path | Login | Model selector |
| --- | --- | --- |
| ArchDev model router | `archdev auth login` | `platform/<catalog-id>` |
| Your ChatGPT subscription via OpenAI OAuth | `archdev settings provider login openai` | `openai/<catalog-id>` |
| Your Grok subscription via xAI OAuth | `archdev settings provider login xai` | `xai/<catalog-id>` |
| Your OpenAI/xAI API account | Provider API-key login or supported environment variable | Same direct provider prefix; verify resolved auth method |

ArchDev account authentication and provider credentials are independent. Agent
execution still needs `archdev auth login` even when model requests use a BYO
account. Subscription OAuth and API keys are distinct paths; adding an API key
does not mean the CLI is using a subscription. Do not silently switch to a
platform/API route when the user requested their subscription.

The canonical namespace is `settings provider`. Older top-level `provider`
commands remain compatibility aliases sharing the same credential store.

## 2. Drive subscription login

```sh
archdev auth status
archdev settings provider login openai --account <email>
archdev settings provider login xai --account <email>
archdev settings provider status
```

1. Run only the login for the selected provider/account. Omit `--account` to
   use the saved account list or the provider's normal sign-in flow. Keep the
   process alive until it reports completion; an opened URL is not success.
2. OpenAI defaults to browser OAuth. Let the human complete sign-in in their
   browser; never ask them to paste passwords, OAuth callback codes, or tokens
   into the conversation. A printed login URL is available if opening fails.
3. For SSH/headless machines use `settings provider login openai --device-code`.
   Present the returned verification URL and short code to the human and wait
   for the CLI to complete. The xAI/SuperGrok integration uses device-code OAuth
   by default. Do not guess verification URLs or approve on the user's behalf.
4. Inspect `settings provider status` for provider, method, profile, expiry,
   and stored count. The text view also reports known OAuth exhaustion times.
   Inspect the account actually selected, not merely the email requested.
5. Select that provider's model explicitly and run a small authorized request:

```sh
archdev settings provider models openai
archdev agents run "Reply with one short sentence confirming you can answer." --model openai/<listed-id> --output-format json
```

Replace the placeholder with a real ID. Report the actual model and outcome,
not a claim that subscription access works based on credential storage alone.

## 3. Inspect models and select one

```sh
archdev settings provider list
archdev --json settings provider status
archdev --json settings provider models platform
archdev --json settings provider models openai
archdev --json settings provider models xai
```

`models platform` fetches the authenticated live platform catalog. OpenAI/xAI
catalogs are bundled with the installed CLI and can be listed without signing
in; they are discovery, not proof of usable credentials or account capacity.
`provider list`'s platform row is also not an authentication probe: use
`auth status` and an authenticated operation to verify ArchDev access.

Human-readable model tables print full selectors. JSON returns
`{provider, data: [{id, ...}]}` where `id` is provider-local: prepend the returned
provider once. For example, provider `platform` plus ID `openai/<model>` becomes
`platform/openai/<model>`; provider `openai` plus ID `<model>` becomes
`openai/<model>`. Preserve nested provider-local paths.

Use `--model <selector>` for a run or `/model` within `agents start`/Factory.
Workflow execution uses models configured on workflow nodes rather than a
`--model` option on `agents workflows run`. Do not assume choosing a model for
one session rewrote every workflow or worker setting.

## 4. Multiple subscription accounts

```sh
archdev settings provider accounts openai list
archdev settings provider accounts openai add <email>
archdev settings provider accounts openai remove <email>
archdev settings provider login openai
```

The same commands work for `xai`. The saved email list lives in user
`~/.archdev/archdev.json`; adding an email does not authenticate it. Login walks
the saved list, skips stored OAuth accounts, and records account order and the
first active profile. `login --account <email>` limits that login walk to one
account; it is not a command for deleting the other stored credentials.
The login walk skips an existing OAuth credential for that email even if it is
expired: “Already stored OAuth” is not fresh authentication. Do not loop on
`login --account` expecting it to force refresh. If the credential cannot be
refreshed and a fresh login is needed, the public logout operation is
provider-wide: explain that scope and obtain appropriate authorization before
logging out and reconnecting the intended accounts.

At runtime, eligible OAuth profiles follow configured ordering/active selection;
accounts in a recorded usage cooldown are skipped. Different model aliases
select providers/models, not specific account-email identities.

`accounts remove` edits the login-email list; it does **not** remove the stored
credential, so that account can remain eligible. `settings provider logout
<provider>` removes all stored credentials for that provider. It does not clear
API-key environment variables. There is no documented per-email logout command;
do not promise one or delete credential-file entries manually.

```sh
archdev settings provider accounts openai reset
```

`reset` clears local OAuth usage-cooldown markers. It does not reset the
provider's quota or erase the account list. Use it when a stale local cooldown
is the demonstrated problem, not as a loop for bypassing exhausted capacity.

## 5. API keys when explicitly chosen

The supported CLI shape is `settings provider login <openai|xai> --api-key
<key>`. The providers also accept `OPENAI_API_KEY` and `XAI_API_KEY` from the
process environment. Have the user supply secrets through their terminal or
an existing secret mechanism; do not collect raw keys in chat, place them in
project configuration, or emit them in tool logs. Passing a key as a literal
shell argument can expose it in shell history/process inspection.

Default automatic resolution prefers stored OAuth profiles when present.
Exhausted OAuth profiles do not silently fall through to API keys. Without
that OAuth preference taking effect, environment keys precede stored API keys.
An explicit API-key runtime path has its own resolution. Check `status` and
the actual request/error before concluding which method a model used.

Credentials are stored under the user's `.archdev` directory; `status` reports
the file path without requiring you to open it. Do not copy credential files
into a repository, import another coding harness's token store, or invent a
second provider store. Changes affect future resolution; already-running
sessions may need an intentional restart to pick up changed configuration.

## 6. Reusable model configuration

Use IDs verified above; this example is structural, not a catalog recommendation:

```json
{
  "modelAliases": {
    "coding": [
      {"provider": "openai", "model": "available-model-id"},
      {"provider": "xai", "model": "available-model-id"}
    ]
  },
  "factory": {"model": "@coding", "worker_model": "@coding"}
}
```

Use only accounts/providers the user intends to consume. An alias can hold one
provider/model object or an ordered nonempty array. Select it with `@coding`.
For ordinary invocation, prefer explicit `--model` with a listed selector;
for persistent Factory defaults use `factory.model` and optional
`factory.worker_model`. Unset worker model inherits the active overseer model.

Personal model precedence is gitignored `<repo>/archdev.local.json` →
`~/.archdev/archdev.json` → checked-in `<repo>/archdev.json`. Repository policy
has project-first precedence; provider accounts are user-owned. Keep model
preferences separate from credentials. Run `archdev --json check` after edits
and inspect the model in a new invocation.

Fallback starts at the first candidate each turn. It can advance on auth,
usage, rate-limit, lookup, and transport/backend failures before output starts.
Once streaming output begins, failure stops the turn rather than replaying it
on another model. Invalid prompts and cancellation also stop. A fallback list
is not evidence every candidate works; setup requires at least one available
candidate in each configured agent role.

## 7. Troubleshoot the owning boundary

1. **ArchDev says unauthenticated:** check `auth status/login`, not provider
   OAuth alone.
2. **Wrong provider/model:** inspect the exact selector, effective aliases,
   Factory role override, and workflow node model. Do not change all defaults
   to repair one invocation.
3. **OAuth appears stored but calls fail:** inspect expiry, exhaustion and the
   actual provider error. Follow the fresh-login caveat above when reauthentication is required;
   use device code when browser callbacks cannot reach the login process.
4. **Catalog lists a BYO model but request fails:** bundled availability does
   not establish account access; check credentials/capacity and current CLI
   version. Do not repeatedly switch endpoints without user intent.
5. **All subscriptions exhausted:** report the cooldown/capacity limitation.
   Use an already-authorized fallback or wait; do not silently bill an API key
   or the platform router as a recovery shortcut.
