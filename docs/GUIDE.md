# DevContext — user guide

The README says what this is and why. This walks you through using it, from an
empty machine to a working day, and tells you what to do when something is wrong.

Nothing here assumes a particular drive, folder layout, or set of installed
tools. Where a choice exists, the default is named and so is how to change it.

**Contents**

1. [Before you start](#1-before-you-start)
2. [Install](#2-install)
3. [Your first context](#3-your-first-context)
4. [A working day](#4-a-working-day)
5. [Editors](#5-editors)
6. [AI assistants and MCP](#6-ai-assistants-and-mcp)
7. [The production guard](#7-the-production-guard)
8. [When something is wrong](#8-when-something-is-wrong)
9. [Uninstalling](#9-uninstalling)

---

## 1. Before you start

### What a context is

A context is **one complete working identity**, not one project:

| Piece | What it isolates |
|---|---|
| git email and name | who your commits say you are |
| SSH key | which account can push |
| `gh` config directory | which GitHub account the CLI acts as |
| Vercel session | which team you deploy to |
| Supabase tokens | which projects you can reach |
| Editor profile | which GitHub and Copilot accounts your editor is signed into |
| MCP servers | which account your AI assistant reaches |

Most people need two or three: your own work, and one per client or employer.
**Not one per project** — ten projects for the same client share one context.

### What you need

- **Windows** and **PowerShell 7+** (`pwsh`, not the Windows PowerShell 5.1 that
  ships with the OS). `pwsh --version` should print 7 or higher.
- **git**.
- The secret vault modules:

  ```powershell
  Install-Module Microsoft.PowerShell.SecretManagement, Microsoft.PowerShell.SecretStore -Scope CurrentUser
  ```

Linux and macOS are not supported yet. The core idea is portable; this
implementation is not — see `ROADMAP.md` for why that is a rewrite rather than a
flag.

---

## 2. Install

```powershell
git clone https://github.com/thierryvm/devcontext.git C:\tools\devcontext

New-Item -ItemType SymbolicLink `
    -Path   "$HOME\Documents\PowerShell\Modules\DevContext" `
    -Target 'C:\tools\devcontext'
```

Clone it wherever you like — that path is an example, not a requirement.

**A symbolic link, not a copy.** The module is used *from* the repository. Two
copies is how a fix ends up applied to the file nobody is running.

Then put the guards in `PATH`:

```powershell
pwsh -NoProfile -File C:\tools\devcontext\installer-shims.ps1
```

This does two things: it puts the production guard where every shell can reach
it, and it writes an entry point for each editor found on your machine. It backs
your `PATH` up first and `-Restaurer` undoes all of it.

**Open a new terminal** — the ones already running still have the old `PATH`.

Check it landed:

```powershell
Import-Module DevContext
ctx init
```

`ctx init` is the shortest route through all of the above. It reports what is
already in place and what is missing, and prints the exact command for each
remaining step:

```
  Setting up DevContext on this machine

    + Secret vault (SecretManagement + SecretStore)
    - Guards reachable from every shell
    - At least one working context

  Contexts live in: C:\dev\contexts
  To keep them elsewhere: ctx root <folder>
```

It installs nothing for you and creates no context on your behalf — both are
decisions, not chores. And it does not prompt when input is redirected, so an
agent or a CI job gets the same ordered list rather than a hung terminal.

Run it again any time. It changes nothing on a machine that is already set up
and says so, which makes it the right command for *something is off and I do not
remember what I did*.

---

## 3. Your first context

`ctx init` prints this command pre-filled from `git config --global` and
`gh auth status`. You run it — creating a context lays an SSH key and a folder,
and that is not done on a guess:

```powershell
ctx-new -Name perso -Email you@example.com -Root C:\dev\perso
```

- **`-Name`** — lowercase, digits and hyphens. Used in paths and SSH aliases.
- **`-Root`** — the folder this context owns. **Everything under it belongs to
  this context**, and that is what the guard reads. Two contexts must never
  overlap.
- **`-NoKey`** — skip SSH key generation. Needed in a script, a CI job, or an AI
  agent's shell: `ssh-keygen` asks for a passphrase, and nothing there can answer.

You will be asked for a passphrase and then for tokens. Every token is optional —
press Enter to skip and add it later.

### Where contexts are stored

By default `%LOCALAPPDATA%\DevContext\contexts`. To put them elsewhere:

```powershell
ctx-root D:\DevContext   # remembered for every future session
ctx-root                 # shows the current root and where that setting came from
```

`DEVCTX_ROOT` overrides it for one shell — useful in a test or a CI job.

### Language

Commands speak your system language when it is one of the two translated
(English, French), and English otherwise. To force it for a shell:

```powershell
$env:DEVCTX_LANG = 'en'
```

Useful for a screenshot, a bug report you want others to read, or a CI log.

If you ever see a message like `[ctx.noGo]`, that is a missing translation
showing its key rather than printing nothing — please report it. The key is
enough for us to find the string.

Contexts hold **SSH private keys**. Putting them on a removable drive or a
network share is a real choice with real consequences; `ctx-root` lets you make
it and deliberately moves nothing on your behalf.

### Finishing the setup

`ctx-new` prints what remains. The two that matter:

```powershell
work perso
gh auth login          # this account is stored in the context, not machine-wide
```

Then add `github.login` to `context.json` in the context folder. Without it `ctx`
can only *report* which account is active — never *check* that it is the right
one, which is the whole point.

---

## 4. A working day

```powershell
work perso              # load an identity into this terminal
cd C:\dev\perso\my-app
ctx                     # GO / NO-GO
```

`work` sets the environment variables; `ctx` checks that folder, identity and
account agree. **Run `ctx` before anything that leaves your machine** — a push, a
deploy, a migration.

### GO and NO-GO

**GO** means the folder you are in, the identity loaded in this terminal, and the
account actually authenticated all agree.

**NO-GO** means they do not, and it prints the command that fixes it — almost
always `work <context> -NoCd`. `-NoCd` keeps you where you are instead of jumping
to the context root.

**Never work around a NO-GO.** The state it catches — standing in one context's
folder with another's identity — is exactly the one that sends a client commit
under your personal name, or the reverse.

### The environment does not survive between processes

Each new process starts fresh. In a script, a hook, or an AI agent's tool call,
prefix outgoing commands:

```powershell
work perso -NoCd; gh pr create ...
work perso -NoCd; vercel deploy
```

A lone `ctx` right after a successful `work` in a *different* process will say
NO-GO. That is correct — they are two processes. To check, chain them in one:
`work perso -NoCd; ctx`.

### What is protected from which shell

| Tool | Isolated by | Works from bash? |
|---|---|---|
| git identity | `includeIf` per path in `~/.gitconfig` | **yes** |
| git push | `insteadOf` → per-context SSH key | **yes** |
| `gh` | the entry point supplies `GH_CONFIG_DIR` from the folder | **yes**, since 1.4.0 |
| `vercel` | the entry point injects `--global-config` from the folder | **yes**, since 1.4.0 |
| `supabase` | the guard in `PATH`, plus the token `work` loads | **yes** |

git is safe from any shell because its rules live in config files the binary
reads regardless. The other three used to depend on `work` having run, which
made them PowerShell-only — the reason this guide once said *"run them from
PowerShell"*. Since 1.4.0 the entry point in `PATH` resolves the context from
the **folder** and supplies the configuration itself, so `gh pr create` typed in
git-bash goes out under the right account.

Two things `work` still does that no entry point can: loading the tokens into
your session, and changing directory. Prefixing outgoing commands with
`work <ctx> -NoCd` remains the habit — it is simply no longer the only thing
standing between you and a commit under the wrong name.

When a context has no `gh` account yet, a *write* is refused rather than sent
under the machine-wide account, and the refusal names the fix:

```powershell
work perso -NoCd
gh auth login          # lands in this context, from anywhere inside it
```

---

## 5. Editors

Editors keep account sessions inside their profile directory. One directory per
context means independent GitHub, Copilot and marketplace sessions, live at the
same time.

```powershell
ctx-editors     # which editors are installed, and can each be isolated?
```

```
Editeur             Commande      Profil  Extensions   Methode
Visual Studio Code  code          isole   isolees      measured
Cursor              cursor        isole   isolees      measured
```

`measured` means the flag was tried and the directory it names appeared.
`declared` means the editor exposes no command line to try, so its capability was
read from its own files — weaker evidence, reported as such.

Once installed, just use your editor normally:

```powershell
cd C:\dev\clients\acme\site
code .          # opens on acme's profile, with acme's gh and tokens
```

If it opened on the wrong account, ask it why:

```powershell
$env:DEVCTX_SHIM_TRACE = 1
code .          # prints, on stderr, which context it chose and why
```

### Shortcuts

A shortcut whose target is `C:\...\Code.exe` consults no `PATH`, so nothing can
correct it. `ctx-doctor` reads your shortcuts and reports which ones will open a
context project on the shared profile. To write a correct one:

```powershell
ctx-shortcut -Path C:\dev\clients\acme\site
```

It targets the launcher rather than an absolute path to an executable, so it
keeps working when the editor updates.

---

## 6. AI assistants and MCP

MCP servers are usually declared machine-wide, so every project inherits whichever
account was connected last. `ctx-mcp` writes a **project-scoped** declaration
instead:

```powershell
cd C:\dev\clients\acme\site
ctx-mcp
```

It writes for the assistants actually present — Claude Code, VS Code, Cursor —
each in its own format. The files contain **no secret**: the token comes from the
environment, which `work` fills from the folder. That is what makes them safe to
commit, and what makes this work with any assistant and any provider, including
your own key.

Read-only by default, and read-only without appeal on a project marked
production.

---

## 7. The production guard

`supabase db reset` is refused against a project tagged `prod`. `db push`,
`migration repair` and `migration up` are refused from any branch other than the
repository's default. Everything else passes through untouched.

For it to know which projects are production:

```powershell
work perso
sb-index        # builds the index from your Supabase account
ctx-sb          # shows which project lives on which account, and which folders point at it
```

Projects whose name suggests production are tagged automatically; anything you
set by hand survives the next rebuild.

The guard sits in `PATH`, so it applies from PowerShell, cmd.exe, git-bash, npm
scripts and an AI agent's shell alike.

**When you genuinely need the command**, for that one command only:

```powershell
$env:DEVCTX_ALLOW_PROD = 1
```

Never put that in your profile. It removes the guard while leaving the impression
of having it — `ctx-doctor` reports it as a finding when it is set.

### What it does not cover

Stated plainly, because a limitation you know about is manageable:

- **WSL** — a distribution has its own `PATH`. `ctx-doctor` tells you when one is
  installed.
- **An absolute path** — `C:\...\supabase.exe` skips `PATH` entirely.
- **A local install** — `npm run` and `npx` put `node_modules/.bin` *ahead* of
  `PATH`. Check with `npm ls supabase`.
- **It fails open** — if anything is unreadable or unexpected, the command passes
  through. A guard that blocks whenever it hesitates gets uninstalled.

Full list with reasoning: [`SECURITY.md`](../SECURITY.md).

---

## 8. When something is wrong

**Start here, always:**

```powershell
ctx doctor          # what works in this folder, and on which account
ctx doctor -Live    # also checks the tokens still work, on the right account
```

`ctx-doctor` with the hyphen does exactly the same thing — both spellings are the
same command. `ctx help` lists everything available.

`-Live` is opt-in because a diagnostic that reaches the network without being
asked is one people stop running. It never prints a token — only the name of the
key holding it.

| Symptom | Likely cause |
|---|---|
| `ctx` says NO-GO after `work` succeeded | Two different processes. Chain them: `work x -NoCd; ctx` |
| `gh` acts as the wrong account | `gh` run from bash, or without `work`. Use PowerShell. |
| Commits carry the wrong email | A `user.email` hardcoded in that repo's `.git/config` beats `includeIf`. Check `git config --show-origin user.email`. |
| Push goes to the wrong account | The remote URL carries `login@`, which the `insteadOf` rule cannot match. `git remote set-url origin https://github.com/<org>/<repo>.git` |
| `Access token not provided` from Supabase | Normal outside a context. Run `work <context>`. |
| The editor opened on the wrong account | `$env:DEVCTX_SHIM_TRACE = 1` then reopen — it will say why. |
| The editor asks me to sign in to GitHub again | Expected, once per context: a separate profile is a separate secret store. That is what stops a client sign-in from signing you out of your own account. |
| A shortcut opens the shared profile | It targets the executable directly. `ctx-shortcut -Path <project> -Force` |
| `ctx-new` seems to hang | It is waiting for a passphrase it cannot receive. Use `-NoKey`, or run it in a real terminal. |

---

## 9. Uninstalling

Every machine-level change is reversible, and each has its own undo:

```powershell
pwsh -NoProfile -File C:\tools\devcontext\installer-shims.ps1 -Restaurer
Remove-Item "$HOME\Documents\PowerShell\Modules\DevContext"   # the symlink only
```

Your contexts are **not** touched by either. They are folders — delete them
yourself when you mean to, and remember that they hold SSH private keys.

Tokens live in the SecretStore vault. Removing a context does **not** revoke
them: revoke at the provider, or they remain valid.

---

## Where to go next

- [`README.md`](../README.md) — what this is, and why it works this way
- [`SECURITY.md`](../SECURITY.md) — what is guarded, and at equal length what is not
- [`docs/ARCHITECTURE.md`](ARCHITECTURE.md) — how it is built, and why each decision
- [`ROADMAP.md`](../ROADMAP.md) — what is coming
- [`CONTRIBUTING.md`](../CONTRIBUTING.md) — how to change it
