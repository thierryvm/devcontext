# Security Policy

DevContext exists to keep credentials apart. A flaw in it is a flaw in the thing
people trusted it to do, so this document is deliberately specific about what is
guarded, what is not, and how to tell us when we got it wrong.

## Reporting a vulnerability

**Do not open a public issue.** Use GitHub's private reporting:

> Repository → **Security** → **Report a vulnerability**

If that is unavailable to you, open an issue titled `security contact request`
containing no technical detail, and you will be given a private channel.

Please include the version (`Get-Module DevContext`), your PowerShell version,
the exact commands to reproduce, and what you observed versus what you expected.
**Never include a real token**, even a revoked one — redact it.

You can expect an acknowledgement within 7 days and an assessment within 30.
Fixes ship in a patch release, credited in `CHANGELOG.md` unless you prefer
otherwise.

## Supported versions

The latest minor release is supported. This is a single-maintainer project, so
older lines receive no backports.

## What DevContext protects

- **Credential separation.** Each context owns its own `gh` config directory,
  Vercel session, and vault entries. There is no shared "logged out" state to
  fall back into.
- **Secrets stay out of files.** Tokens live in the SecretManagement vault and
  reach tools through environment variables. Nothing is written to disk in
  clear text, and no generated file contains a credential.
- **Production is guarded.** `supabase db reset` is refused against a project
  tagged `prod`; `db push` is refused from a branch other than the repository's
  default. The guard sits in `PATH`, so it applies to every shell — not only
  the one that imported the module. Detection examines every adjacent pair of
  non-option arguments, so placing a global flag before the command does not
  shift it out of view.
- **A redirected target is refused rather than guessed.** `--db-url` points the
  CLI somewhere the folder does not. When the project ref can be read from the
  connection string it is judged on that; when it cannot, and the context holds
  any production project, the command is refused. This is the one place the
  guard fails closed.
- **Diagnostics never echo a *credential*.** `ctx doctor` reports the *name* of
  a key, never its value. Messages that can carry data from elsewhere — API
  errors, the output of a binary found on `PATH` — pass through
  `Protect-CtxMessage`, which redacts by issuer prefix and by shape: bearer
  headers, JWTs, connection-string passwords, and `password`/`secret` keywords.
  Redaction is a **last line, not a first**: no code path is meant to put a
  credential in a message. Static literals are not filtered, because they carry
  nothing to filter.

## What DevContext does not protect against — by design

These are stated plainly because a limitation you know about is manageable, and
one you have been allowed to assume away is not.

| Limit | Why it exists |
|---|---|
| **WSL is not covered** | A Linux distribution has its own `PATH` and its own filesystem view. The Windows shim is not on it, so a command run from WSL reaches the real CLI directly. `ctx doctor` reports this when a distribution is installed. |
| **An absolute path bypasses the guard** | Calling `C:\...\supabase.exe` directly skips `PATH` resolution entirely. The guard stops mistakes, not a determined operator. |
| **A local install bypasses the guard** | `npm run` and `npx` put `node_modules/.bin` *ahead* of `PATH`. A project carrying `supabase` as a dev dependency therefore reaches its own copy first, and the shim never sees the call. Check with `npm ls supabase`. |
| **The guard fails open** | If the module is missing, the index unreadable, or anything unexpected happens, the command is passed through unchanged. A guard that blocks whenever it hesitates gets uninstalled within the week, and an uninstalled guard protects nothing. |
| **`DEVCTX_ALLOW_PROD=1` disables it** | Intentional, for the one command that genuinely needs it. Setting it in `$PROFILE` removes the guard while leaving the impression of having it — `ctx doctor` reports it as a finding when set. |
| **Anyone who can write to `shims/` runs code everywhere** | The folder sits first in `PATH`. Its filesystem permissions are part of your threat model, not ours. |
| **`npx` fetches at run time** | A generated `.mcp.json` uses `npx -y @supabase/mcp-server-supabase@latest`, which downloads on every start. That is upstream's recommended form; pin the version yourself if your threat model requires it. |
| **The vault is as strong as its passphrase** | DevContext stores secrets in Microsoft's SecretStore. Its security properties are Microsoft's, not ours. |

## Verifying these claims yourself

The properties above are tested, not asserted:

```powershell
pwsh -NoProfile -File .\tests\RunTests.ps1
```

`tests/Securite.Tests.ps1` scans every git-tracked file for credential patterns,
and — when a context is loaded — runs the full diagnostic with your **real**
tokens, then asserts that not one character of them appears in the output.
