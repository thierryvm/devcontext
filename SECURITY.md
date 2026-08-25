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
  tagged `prod` unless the command explicitly targets the local database;
  `db push` is refused from a branch other than the repository's default.
  A command whose target cannot be read with certainty is treated as aimed at
  production, never as harmless. The guard sits in `PATH`, so it applies to every shell — not only
  the one that imported the module. Detection examines every adjacent pair of
  non-option arguments, so placing a global flag before the command does not
  shift it out of view.
- **GitHub writes are tied to the folder's identity.** `gh` reads its account
  from `GH_CONFIG_DIR`, and without it falls back to the machine-wide config —
  whichever account was logged in last. `work` sets it, but `work` is a
  PowerShell command, so from git-bash, an npm script or an agent's shell it was
  never set. The entry point in `PATH` now resolves the context **from the
  folder** and supplies the directory itself, on the child process only. When
  there is nothing to supply — the context has no `gh` account yet — a *write*
  is refused and names the two commands that fix it, while *reads* pass. When
  `GH_CONFIG_DIR` is set to a different context it is never overwritten, because
  a deliberate choice is not ours to undo; writes are refused and reads are
  flagged on stderr. Writing commands are recognised by **verb** (`create`,
  `delete`, `merge`, `edit`, …, split on hyphens so `project item-add` counts),
  which is what makes a noun GitHub adds tomorrow covered without a change here.
- **Vercel production deployments are guarded, and sessions are separated.** A
  `--prod` deployment from a branch other than the default is refused, as is
  `env rm` naming `production`. The Vercel CLI has no `GH_CONFIG_DIR`
  equivalent — its config directory is chosen only by `--global-config` — so the
  entry point writes it into the command line, from the folder, and never when
  the caller already passed one.
- **A redirected target is refused rather than guessed.** `--db-url` points the
  CLI somewhere the folder does not. When the project ref can be read from the
  connection string it is judged on that; when it cannot, and the context holds
  any production project, the command is refused. This is the one place the
  guard fails closed.
- **Editor sessions are separated per context.** Each context owns a profile
  directory, and the editor keeps its GitHub, Copilot and marketplace sessions
  inside it, encrypted by the OS. An entry point in `PATH` supplies the flag, so
  a terminal, an npm script, "Open with" and an agent all land on the right one
  — not only the launcher we wrote. What each editor actually supports is
  probed, never assumed, and probing a GUI-only editor is refused rather than
  attempted (see the limits below).
- **A foreign identity inside a context profile is reported.** Isolation stops
  sessions from overwriting each other; it never stopped anyone signing into the
  *wrong account* inside the *right profile*. `ctx doctor` now names it when one
  context's editor profile carries another context's GitHub account — the case
  where Copilot, the Pull Request extension and GitLens act under a personal
  identity in a client window. Detection matches key names by **exact search
  over the closed set of logins the manifests declare**, bounded so that
  `github-thier` cannot match `github-thierryvm`. Encrypted values are never
  read.
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
| **`npx pkg@latest`, `pnpm dlx` and `bunx` bypass the guard** | Different from the row above, and worse: these fetch the package at run time and run it **without consulting `PATH` at all**, so no shim can sit in the way. Found on 18 August 2026 — `npx --yes vercel@latest`, run from a client folder, had left a **personal** account's token in `%APPDATA%\com.vercel.cli\Data\auth.json`, outside every context and reachable from any directory, while that folder's own compartmentalised session existed and was valid. The form reads as *safer* than an install precisely because nothing is installed. Run a guarded tool from `PATH`, never through a package runner. |
| **The guard fails open** | If the module is missing, the index unreadable, or anything unexpected happens, the command is passed through unchanged. A guard that blocks whenever it hesitates gets uninstalled within the week, and an uninstalled guard protects nothing. |
| **`DEVCTX_ALLOW_PROD=1` disables it** | Intentional, for the one command that genuinely needs it. There is one variable per tool — `DEVCTX_ALLOW_GH`, `DEVCTX_ALLOW_VERCEL` — deliberately, so that waiving one guard never waives the others. Setting any in `$PROFILE` removes a guard while leaving the impression of having it; `ctx doctor` names every one that is set. |
| **An unknown `gh` verb is treated as a read** | Verb classification covers new *nouns* for free but not a new *writing verb*. The choice is deliberate: on an identity mismatch nothing passes **silently** — what is not refused is flagged — and `ctx` already answers `NO-GO` on the same condition. This guard is a second line, not the only one. |
| **The GitHub account check needs the network** | Confirming *which account `gh` actually opens* costs an API call. When GitHub cannot answer, `ctx` says the account was **not verified** and does not turn that into `NO-GO`. Deliberate: on 17 Aug 2026 the opposite behaviour declared a healthy client folder compromised during a GitHub outage, which sends people to re-authenticate against a service that is down. The offline axes — folder ownership, `GH_CONFIG_DIR`, SSH routing, the Supabase key — are unaffected and still decide. |
| **`vercel rollback`, `promote` and `rm` are not guarded** | `rollback` is a repair gesture, and refusing it always lands during an incident, from a hotfix branch. `promote` acts on an already-built deployment. What `rm` deletes is not identifiable as production from the command line alone, and refusing on a doubt is refusing at random. |
| **`vercel env rm` without a named environment is not guarded** | Given no target the CLI opens a prompt, and the human sees what they pick. Refusing there would remove the command for development environments too, where it is routine. |
| **Anyone who can write to `shims/` runs code everywhere** | The folder sits first in `PATH`. Its filesystem permissions are part of your threat model, not ours. |
| **`npx` fetches at run time** | A generated `.mcp.json` uses `npx -y @supabase/mcp-server-supabase@latest`, which downloads on every start. That is upstream's recommended form; pin the version yourself if your threat model requires it. |
| **A shortcut pointing at the executable bypasses everything** | `C:\...\Code.exe` consults no `PATH`, so no entry point can reach it. Nothing here can change that; `ctx doctor` reads your shortcuts and reports which ones open a context project on the shared profile, and `ctx-shortcut` writes correct ones. Detection, not prevention. |
| **Some editors cannot be isolated at all** | Isolation needs a command-line entry point exposing `--user-data-dir`. An editor shipping only a GUI executable has none, and DevContext will **not** launch a GUI to find out — doing so on 15 Aug 2026 opened a window, triggered a self-update relaunch, and left the application crashing on a broken pipe. Such an editor is listed by `ctx-editors` with its capability read from disk and labelled `declared`, and `ctx doctor` says plainly that its sessions stay shared. |
| **`--extensions-dir` is not universal** | Antigravity accepts `--user-data-dir` and has no `--extensions-dir`. Profile isolation — which is where the sign-ins live — still applies; extensions remain common. The flag is never passed to an editor that ignores it, because a flag silently dropped reads as isolation you do not have. |
| **`--user-data-dir` alone stopped being enough on 19 August 2026** | VS Code 1.133 moved *application* storage — extension **secrets**, the recently-opened list, the trusted-folders list — out of the profile and into `~/.vscode-shared`, one store for the whole machine. Encryption stayed **per profile**, so two contexts write the same entry with two different keys and each makes the other's unreadable: the editor discards it and asks you to sign in again. Six launches measured that day — the six carrying `Error while decrypting the ciphertext` are exactly the six that read back zero sessions. The visible cost is the sign-in loop; the real one is that a **client** project path sat in the recently-opened list of a **personal** window. `Open-DevCode` now passes `--shared-data-dir` per context. |
| **That flag is *declared*, not measured** | The command-line probe never initialises the shared store — measured: `code --user-data-dir X --extensions-dir Y --shared-data-dir Z --list-extensions` exits 0, creates X and Y, and does **not** create Z. So the absence of a side effect proves nothing here, and answering "unsupported" would assert more than is known, with the authority of a measurement. The capability is read from the editor's own argument surface, and the **outcome** is then measured where it can be: `ctx doctor` reports whether this context's shared store exists on disk. |
| **What the machine-wide store already holds is not removed** | The fix separates what happens from now on. Entries written before it — including recently-opened paths that mix contexts — stay in `~/.vscode-shared` until you delete that folder yourself. Deleting it signs out the editor's **default** profile, which is why nothing here does it for you. |
| **The vault is as strong as its passphrase** | DevContext stores secrets in Microsoft's SecretStore. Its security properties are Microsoft's, not ours. |
| **Nothing here confines where an AI agent writes** | DevContext partitions *identity*, never *writes*. An agent running in a client folder has the same filesystem rights as any process. `ctx doctor` reports every directory an agent has been trusted with that belongs to another context or to none — a **report, not a barrier**. Real write confinement needs a filesystem filter driver or a container, which is a different class of software. |
| **An agent permission rule is honoured, not enforced** | Those rules live in the agent's own settings and the agent obeys them; the kernel knows nothing about them. They stop the frequent case — a tool writing next to where it meant to — and stop nothing determined. |
| **The credential sweep reads files, not the OS keyring** | `ctx doctor` reports a credential sitting at a tool's **default** location, outside every context. It reads files. On Windows, `gh` keeps the token itself in Credential Manager, so the file holds only **logins** — which is why the check reports the *identities a global config declares* rather than the presence of a secret. Measured on 19 August 2026: `cmdkey /list` showed `gh:github.com:<login>` while `hosts.yml` carried no `oauth_token` at all. A check that had looked for a token in the file would have answered "nothing to report" on a machine whose global config knew two accounts, one of them a client's. Keyring entries for other tools are not enumerated. |
| **That sweep works from a closed list** | The locations are enumerated, never discovered: `gh`, `vercel` and `supabase`, at their documented defaults. A credential somewhere the list does not know is invisible to it. This is deliberate — a heuristic looking for "files that resemble a token" produces false positives nobody believes, and a check nobody believes is a check that gets skipped. The list is short enough to read, which is the point. |
| **It says nothing outside a context** | A credential at a default location is only a fault where a boundary exists to be crossed. On a machine that compartmentalises nothing, a globally signed-in `gh` is simply how `gh` works. Reporting it there would be a red nothing can clear — the failure mode this project refuses everywhere else. |
| **Offline, it cannot say whose token it is** | When a global credential belongs to an account another context declares, the verdict is affirmative and says so. Otherwise it reports the credential and stops: naming the owner takes a network call, and this pass does not make one. |
| **The context root is watched, never tidied** | `ctx doctor` names what sits in the root without being a context — and an undone context folder still holds `ssh/` keys and `gh/` sessions. It deletes nothing. Deciding whether that material should be revoked, kept, or destroyed is a judgement about someone's credentials, and a diagnostic that made it for you would eventually make it wrong. It also looks only at the root's **immediate** entries: a folder buried three levels down inside a context is that context's business. |

## Verifying these claims yourself

The properties above are tested, not asserted:

```powershell
pwsh -NoProfile -File .\tests\RunTests.ps1
```

`tests/Securite.Tests.ps1` scans every git-tracked file for credential patterns,
and — when a context is loaded — runs the full diagnostic with your **real**
tokens, then asserts that not one character of them appears in the output.
