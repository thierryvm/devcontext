# Tests

```powershell
pwsh -NoProfile -File .\tests\RunTests.ps1
```

`RunTests.ps1` imports Pester explicitly with `-MinimumVersion 5.0.0`. Windows
ships a non-removable Pester 3.4.0 in `System32` whose syntax is incompatible;
without the explicit import, that is what runs.

---

## What the suite actually guarantees

Stated honestly, because a coverage claim nobody can check is worth nothing.

| Level | File | Guarantees |
|---|---|---|
| Decision | `Guard`, `Doctor`, `Jetons`, `Mcp`, `Installer`, `Editors`, `Shortcuts`, `Fix`, `Init`, `ProfilComptes` | Every return path of every pure decision, exhaustively, without touching a machine |
| Contract | `Manifest`, `Ctx` | psd1 ↔ module export parity — read from the LOADED module, since a derived list is invisible to text analysis — plus format file validity, and that `ctx-<name>` and `ctx <name>` cannot diverge |
| Resolution | `ContextResolution` | Which context owns a folder, including the prefix trap and nesting |
| Integration | `Shim`, `SupabaseIndex`, `SupabaseMap` | A whole fake world under `$TestDrive`: context, index, git repository, decoy binary |
| Cross-shell | `Shell`, `Alias` | The guard exercised from cmd.exe **and git-bash**, not only PowerShell; and the four wrappers passing short options and comma lists through verbatim |
| Repository security | `Securite` | No credential in any tracked file; the full diagnostic run with the machine's **real** tokens, asserting none appear |
| Static analysis | `Analyse` | PSScriptAnalyzer, comment-based help on every exported command, verb-noun conformance |

**What it does not guarantee.** No test drives a real Supabase, Vercel or GitHub
mutation. `-Live` token checks are read-only identity probes and are skipped
when no token is loaded. WSL is not exercised — it is an acknowledged gap, and
`ctx doctor` reports it rather than pretending otherwise.

**No test launches an editor**, and that is a deliberate limit rather than an
oversight. `Editors` and `Shortcuts` prove the RULES — which flag may be
injected, what counts as evidence that one is supported, which folder a command
line points at — against fake filesystems and fabricated capabilities. Whether
a given editor on a given machine honours `--user-data-dir` is a question about
that machine, and it is answered at runtime by the probe, whose own rule
(*a flag counts only when the directory it names appeared*) is what the suite
pins down.

The same reasoning bars a test from opening a window. A suite that launches GUI
applications is a suite people stop running, and on 15 Aug 2026 launching one to
interrogate it left it crashing in a loop on the user's screen.

---

## The rule that outranks the others

> **A test that stays green on broken code is worse than no test.** It
> advertises coverage that does not exist.

Two recorded cases, both found here:

**13 August 2026 — the test that never built its own condition.** Shim tests
were meant to run with no context active. They simply declined to *set*
`DEVCTX`. But `pwsh -Command` inherits the parent environment, and the suite runs
in a shell where a context is loaded — so the child inherited one. The tests
would have stayed green against a completely broken guard. They now clear the
variable explicitly.

**15 August 2026 — the test that disarmed another test.** A token test cleared
`SUPABASE_ACCESS_TOKEN` in its `finally` instead of restoring it. Everything
after it saw no token, so the end-to-end leak check quietly skipped. Green
suite, vanished coverage. **Restore, never remove.**

So: whenever a test matters, prove it bites. Break the code, watch it go red,
restore.

```powershell
# The discipline, applied by hand
Copy-Item .\shims\supabase.ps1 .\shims\supabase.ps1.bak
#   … reintroduce the bug …
pwsh -NoProfile -Command "Import-Module Pester -MinimumVersion 5; Invoke-Pester .\tests\Shim.Tests.ps1"
#   expect RED, then:
Move-Item .\shims\supabase.ps1.bak .\shims\supabase.ps1 -Force
```

---

## Never test destruction for real

Destructive commands are exercised against a **decoy** that announces itself:

```powershell
"@echo off`r`necho LEURRE-APPELE`r`nexit /b 42" | Set-Content "$decoy\supabase.cmd"
```

The assertion is that `LEURRE-APPELE` **did not** appear. Testing `db reset`
against the real CLI would mean betting a database on the guard working — which
is precisely the thing under test.

---

## Writing a new test

- Name it after the behaviour, not the function: *«refuses db reset without an
  active context»*, not *«Test-CtxSupabaseGuard returns false»*.
- Comment the **why**, and name the incident when there is one. A test carrying
  its date and its story survives the refactor that would otherwise delete it as
  redundant.
- Never remove an environment variable you did not create — restore it.
- Cover the *interesting* failure. For a token, that is not «is it valid» but
  «is it valid **on the wrong account**» — the case a naive check blesses.
- Prefer `InModuleScope` + `Mock` over building a filesystem. If a decision
  needs an elaborate fake world to be reached, the decision is in the wrong
  place — move it into a pure function.

---

## Cross-shell testing on Windows

`bash` on `PATH` resolves to `C:\WINDOWS\system32\bash.exe`, which is the **WSL
launcher**, not git-bash. WSL sees a different filesystem (`/mnt/c`, not `/c`)
and a different `PATH`. `Shell.Tests.ps1` therefore locates git-bash by absolute
path and skips when it is absent — measuring the wrong shell would be worse than
not measuring at all.

---

## Continuous integration

`.github/workflows/ci.yml`, Windows only — this module manipulates the Windows
`PATH`, the `HKCU` registry, DPAPI-backed VS Code stores and git-bash. Three
jobs, so a red build names the property that broke: **Pester suite**, **manifest
and module load**, **no credential in the repository**. The last one clones with
full history: a secret removed in a later commit is still published.

PSScriptAnalyzer is not a runtime dependency, so its tests **skip** locally when
absent rather than passing. CI installs it, so the net is always up there.
