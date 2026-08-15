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

## Install

### 1. Dependencies

```powershell
Install-Module Microsoft.PowerShell.SecretManagement, Microsoft.PowerShell.SecretStore -Scope CurrentUser
```

The vault is a **hard** dependency. Without it no token is loaded and the module
cannot keep its promise, so it refuses to import rather than half-work.

### 2. Clone

```powershell
git clone https://github.com/thierryvm/devcontext.git F:\PROJECTS\Apps\devcontext
```

The path barely matters, but placing the repository under a context root means
DevContext manages itself.

### 3. Link the module folder

```powershell
$modules = "$HOME\Documents\PowerShell\Modules\DevContext"
if (Test-Path $modules) { Rename-Item $modules 'DevContext.before-link' }
New-Item -ItemType SymbolicLink -Path $modules -Target 'F:\PROJECTS\Apps\devcontext'
```

> Elevation is only needed if Windows **Developer Mode** is off. With it on, the
> command works without administrator rights.

### 4. Install the production guard

```powershell
pwsh -NoProfile -File F:\PROJECTS\Apps\devcontext\installer-shims.ps1
```

This puts `shims\` at the **front** of the user `PATH`, which is what makes the
guard reachable from git-bash, npm scripts, Node and an AI agent's shell — not
only from PowerShell. It backs up the previous `PATH` first and is fully
reversible:

```powershell
pwsh -NoProfile -File .\installer-shims.ps1 -Verifier    # report, change nothing
pwsh -NoProfile -File .\installer-shims.ps1 -Restaurer   # remove it again
```

User scope only. No administrator rights, no machine-wide change.

### 5. Verify — in a NEW terminal

```powershell
work perso -NoCd
ctx
ctx-doctor
```

`ctx` must answer **GO**. Until it has, **delete nothing.**

### 6. Once proven

```powershell
Remove-Item "$HOME\Documents\PowerShell\Modules\DevContext.before-link" -Recurse -Force
```

### Rolling back

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
ctx-new perso -Label 'Perso' -Email '...' -Root 'F:\PROJECTS\Apps' -GithubLogin '...'
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
