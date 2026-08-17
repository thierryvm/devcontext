# Installing DevContext on a fresh machine

This repository is the **single source** of the module. There is no second copy —
that is deliberate, and it is the most important sentence in this document.

Requires **Windows** and **PowerShell 7+**.

---

## Why a symlink and not a copy

The module once lived in **two places**: a reference folder, and the copy
PowerShell actually loaded from `Documents\PowerShell\Modules\`.

They were identical — until the day a fix was applied to the reference. It had
**no effect**, silently, because that was not the copy being executed. Finding
out required diffing the two files.

A symlink removes the entire class of problem: there is one real file, so there
is nothing to synchronise, so there is nothing to drift.

---

## Install from PowerShell Gallery

### 1. The module

```powershell
Install-PSResource DevContext        # or: Install-Module DevContext
```

The vault — `Microsoft.PowerShell.SecretManagement` and
`Microsoft.PowerShell.SecretStore` — comes along as a declared dependency. It is
a **hard** one: without it no token is loaded and the module cannot keep its
promise, so it refuses to import rather than half-work.

### 2. The production guard

Not optional, and not automatic. Installing a module cannot modify your `PATH`,
and it should not: that is a change to your machine, and it belongs to a command
you chose to run.

```powershell
pwsh -NoProfile -File (Join-Path (Get-Module DevContext -ListAvailable)[0].ModuleBase 'installer-shims.ps1')
```

This is what makes the guard reachable from git-bash, npm scripts, Node and an AI
agent's shell — not only from a PowerShell session that imported the module. It
backs up the previous `PATH` first and is fully reversible:

```powershell
pwsh -NoProfile -File .\installer-shims.ps1 -Verifier    # report, change nothing
pwsh -NoProfile -File .\installer-shims.ps1 -Restaurer   # remove it again
```

### 3. Run it again after every update

`PATH` receives `%LOCALAPPDATA%\DevContext\current\shims`, a path with no version
number in it. Behind `current` sits a **junction** to the installed module, and
that is what a new version has to repoint.

Why it works this way: installed from the Gallery, a module lives under
`...\Modules\DevContext\1.3.1\`. Putting *that* in `PATH` would pin a version —
the next release lands in a sibling folder, `PATH` keeps naming the old one, and
the guard runs stale logic until the old version is removed, at which point it
disappears without a word. That was the state of 1.3.0, for a few hours.

`ctx doctor` reports a junction pointing anywhere other than the loaded module,
so a forgotten step shows up as a finding rather than as silence.

---

## Install from a clone, to work on the module

```powershell
Install-Module Microsoft.PowerShell.SecretManagement, Microsoft.PowerShell.SecretStore -Scope CurrentUser

git clone https://github.com/thierryvm/devcontext.git
$depot = (Resolve-Path .\devcontext).Path

$modules = "$HOME\Documents\PowerShell\Modules\DevContext"
if (Test-Path $modules) { Rename-Item $modules 'DevContext.before-link' }
New-Item -ItemType SymbolicLink -Path $modules -Target $depot

pwsh -NoProfile -File "$depot\installer-shims.ps1"
```

> Elevation is only needed if Windows **Developer Mode** is off. With it on, the
> command works without administrator rights. (The junction the installer creates
> needs neither — that is why it is a junction and not a symlink.)

The symlink means the module PowerShell loads and the repository you edit are the
same files. There is nothing to synchronise, so there is nothing to drift — and
no chance of fixing the copy that is not the one being executed, which is exactly
what happened on 12 Aug 2026.

The test suite ships with the clone, not with the Gallery package:

```powershell
pwsh -NoProfile -File .\tests\RunTests.ps1
```

User scope only. No administrator rights, no machine-wide change.

---

## Verify — in a NEW terminal

`PATH` changes land in the next terminal, never in the one that made them.

```powershell
ctx init          # what is in place, what is missing, and the command for each
work perso -NoCd
ctx
ctx doctor
```

**`ctx init` is the one command to remember.** It installs nothing on your
behalf and creates no context for you — both are decisions rather than chores —
but it prints the exact command for every remaining step, in the order they have
to be done.

It asks no question when input is redirected: an agent or a CI job gets the same
list in a form it can act on, rather than a terminal that never comes back.

It is idempotent. On a machine that is already set up it changes nothing and
says so, which also makes it the right command for *something is off and I do
not remember what I did*.

`ctx` must answer **GO**. Until it has, **delete nothing** — in particular not
the `DevContext.before-link` folder, if the clone install renamed one:

```powershell
Remove-Item "$HOME\Documents\PowerShell\Modules\DevContext.before-link" -Recurse -Force
```

## Rolling back

```powershell
pwsh -NoProfile -File .\installer-shims.ps1 -Restaurer
Remove-Item "$HOME\Documents\PowerShell\Modules\DevContext" -Force    # removes the link
Rename-Item "$HOME\Documents\PowerShell\Modules\DevContext.before-link" 'DevContext'
```

Terminals already open keep the old `PATH`; the change lands in the next one.

---

## What points at this folder from outside

The symlink only covers PowerShell. **Four other things reference this folder by
absolute path**, and none of them follow a move:

| Consumer | What it targets | How to repair |
|---|---|---|
| The user `PATH` (`HKCU\Environment`) | `shims\` | re-run `installer-shims.ps1` **from the repository** |
| `vscode://` handler (`HKCU\Software\Classes\vscode\...`) | `vscode-uri-router.ps1` | re-run `installer-uri-router.ps1` **from the repository** |
| Desktop shortcuts that open VS Code per context | `lancer-vscode.ps1` | rewrite each shortcut's `-File` argument |
| Agent documentation referencing the path | the path itself | edit by hand |

**Moving this repository without doing all four breaks everything, silently.**
That happened on 13 August 2026: the old folder was deleted after a migration,
the shortcuts opened a terminal that closed instantly (script not found), and
the dangling `vscode://` handler brought back permanent GitHub re-authentication
across every project.

Check after any move:

```powershell
pwsh -NoProfile -File .\installer-shims.ps1 -Verifier
pwsh -NoProfile -File .\installer-uri-router.ps1 -Verifier

# do the shortcuts point at a script that exists?
$sh = New-Object -ComObject WScript.Shell
Get-ChildItem "$HOME\Desktop\Raccourcis-outils" -Filter 'VS Code*.lnk' -ErrorAction SilentlyContinue |
  ForEach-Object {
    $a = $sh.CreateShortcut($_.FullName).Arguments
    $f = [regex]::Match($a, '-File "([^"]+)"').Groups[1].Value
    '{0,-34} {1}' -f $_.BaseName, (Test-Path -LiteralPath $f)
  }
```

---

## What this repository does not contain, and never will

| What | Where it actually lives |
|---|---|
| Tokens (GitHub, Vercel, Supabase, Sentry) | **SecretStore** vault `DevContext` |
| Context identities (`context.json`) | the context root, e.g. `F:\CTX\<context>\` |
| SSH keys | `~\.ssh\` |
| Per-context `gh` and `vercel` configuration | the context root |

**Cloning this repository on a fresh machine therefore does not restore your
contexts.** It restores the tool. Contexts are recreated with `ctx-new`, and
tokens are re-entered by hand — deliberately. A secret you can restore from a
backup is a secret that has already been copied somewhere it did not belong.

## Recreating a context

```powershell
ctx-new perso -Label 'Perso' -Email '...' -Root 'C:\Work\Apps' -GithubLogin '...'
```

`ctx-new` asks for each token in turn, with masked input. Press Enter to skip
the ones you do not want to set yet.

Then check the result:

```powershell
work perso -NoCd
ctx-doctor -Live
```

`-Live` confirms each token is not merely present but **valid, on the account
this folder expects**.

---

Daily usage: `README.md` · Internals: `docs/ARCHITECTURE.md` ·
Reasoning: `POURQUOI.md` (French) · Guarantees and limits: `SECURITY.md`
