# Working on DevContext as an AI agent

Read this before changing anything. It is short on purpose, and every rule here
exists because ignoring it already cost a session.

---

## What this repository is

A PowerShell module that keeps development identities apart. A defect here does
not produce a wrong pixel — it commits under a client's name, deploys to the
wrong project, or destroys a production database. Treat every change as
security-relevant, because most of them are.

Start with [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md). The one idea is:
**the folder decides, never the session.**

---

## Before you touch anything

```powershell
work perso -NoCd            # this repository belongs to the "perso" context
ctx                         # must say GO
pwsh -NoProfile -File .\tests\RunTests.ps1
```

A green suite before you start is what makes a red one afterwards mean
something.

**Every outgoing command goes through PowerShell, prefixed with `work`.** Each
tool invocation is a fresh process, so variables set by a previous call are
gone:

```powershell
work perso -NoCd; gh pr create ...
```

Never run `gh`, `vercel` or `supabase` from bash — they would use the machine's
global config, which is the last account anyone logged into. `git` is safe from
any shell: its `includeIf` and `insteadOf` rules live in config files the binary
reads regardless.

---

## Non-negotiable

**Never weaken a test to make it pass.** A red test is information. Do not
adjust an expected value to match observed output, do not add `-Skip`, do not
loosen an assertion, do not wrap the cause in a `try/catch`. Find the cause,
fix the cause. If the expectation was genuinely wrong, say so out loud and
explain why — never change it quietly.

**Prove a regression test actually bites.** Reintroduce the bug, watch the test
go red, restore. A test that stays green on broken code is worse than no test:
it advertises coverage that does not exist. This repository has two recorded
cases of exactly that, both documented in `tests/README.md`.

**Never test a destructive command against a real service.** Build a fake world
under `$TestDrive` and a decoy binary that announces itself. The assertion is
that the decoy was **not** called.

**Never print a secret.** Not in output, not in an error, not in a log, not in a
commit message, not in an example. Report the *name* of the key, never its
value. Every message that can carry an exception passes through
`Protect-CtxMessage`.

**Ask before installing a dependency or running a destructive command.**

---

## Traps that have already caught someone here

| Trap | What happens |
|---|---|
| `param($Args)` | `$Args` is an automatic variable, silently overwritten. The shim received garbage and let everything through. Same for `$Input`, `$Host`, `$Matches`, `$profile`. |
| Export in one list only | The real export is the **intersection** of psd1 and psm1. The command becomes invisible with no error. |
| Deriving one list but hand-copying its twin | The `ctx-*` aliases were **created** from the subcommand table and **exported** from a hand list. The first subcommand added existed inside the module and was absent for the caller, while the space-separated form worked — two spellings, one dead. Derive both from the same table, or neither. |
| Static analysis of a derived list | The manifest test read `$exportedAliases = @(…)` **as text** and saw nothing once half the list was computed. It answered "what the psm1 says it exports", never "what it exports". Read the loaded module's `ExportedAliases`. |
| Indexing `[0]` without checking | `@(...)[0]` on an empty array throws *Index was outside the bounds*. `ctx init` did it on the gh account list — so the welcome command crashed on exactly the virgin machine it exists to welcome. |
| `try`/`catch` inside a hashtable literal | It is a **statement**, not an expression: `@{ X = try {…} catch {…} }` is a parse error, while `$x = try {…} catch {…}` is fine. Compute into a variable first. |
| Writing a rule you have not confirmed the target honours | `ctx guard` was designed to emit `deny` rules against other contexts' roots. Checking the upstream tracker **before writing a line** found that path-scoped `Write`/`Edit` rules never match on Windows — the tool absolutizes the path before the check, and absolute Windows paths match no documented pattern form ([#67849](https://github.com/anthropics/claude-code/issues/67849), [#34741](https://github.com/anthropics/claude-code/issues/34741), [#22907](https://github.com/anthropics/claude-code/issues/22907), [#36884](https://github.com/anthropics/claude-code/issues/36884)). A file of inert rules is worse than no file: it looks like protection. The command now only *removes* approvals, and never adds one that would be inert. |
| A test that needs an external tool, and does not say so | Three shim tests invoked the real Supabase CLI with no precondition declared, while their twins in `Executable.Tests.ps1` had declared it since day one. On a runner without the CLI one went red — and **the other two went green for the wrong reason**: a missing binary also returns non-zero, and its error text also lacks the word `REFUSE`. Declaring the precondition is not weakening the test; leaving it implicit is what let two of them stop measuring anything. |
| A function cannot **return** an empty array | `@($faits)` on the last line does not save you: an empty array unrolls crossing the output stream, so the caller receives `$null` — and `$null.Count` throws under StrictMode. Third occurrence here (`Get-CtxVercelMots` in 1.4.0, `$reste` in `Invoke-DevCtx`, `Get-CtxAgentConfianceFacts` on 18 Aug 2026). Wrap at the **call site**, `@(Get-Something)`, and let pure functions take `[AllowNull()]`. |
| Only ever building the populated case | The empty case is the most ordinary input there is, and it was the one no test constructed. `ctx doctor` was green here for a week and red on the first CI agent, because a developer machine always has *some* agent settings file and a fresh runner has none. If a test's result depends on the machine running it, it proves nothing anywhere else — neutralize the machine (`CLAUDE_CONFIG_DIR` to an empty folder) rather than trusting the one you have. |
| A rehearsal mode nobody rehearsed | `workflow_dispatch` with `dry_run` exists so `release.yml` can be tried without spending a version number. It worked — until the first version actually shipped. From then on the manifest names a version the Gallery already serves, and the check whose only purpose is *do not publish a duplicate* went fatal in a run that publishes nothing. Latent from the day it was written, and visible only after the success it was built to protect. An assertion belongs to the runs where its consequence exists: ask `steps.mode.outputs.publier` before throwing. |
| Trusting a native command's output without its exit code | `gh api user --jq .login` writes the API's **error body to stdout** on failure. `ctx` never read `$LASTEXITCODE`, so during GitHub's outage of 17 Aug 2026 it compared `{"message": "No server is currently available…"}` to the expected account and declared NO-GO on a healthy folder. Read the exit code, *and* check the value's shape — the guarantee must not rest on a third-party binary's exit discipline. |
| The same question answered in two places | `ctx doctor -Live` tested that exit code from day one; `ctx`, twenty lines away, did not. The correct version existed the whole time — in the command nobody runs daily, while the flawed one shipped in the command everyone types. When two call sites ask one question, they share a function or one of them is already wrong. Sibling of the hand-copied-list row above: same defect, logic instead of data. |
| `Write-Host` across `pwsh -File` | It is not "quiet output". The child's information stream lands on the **parent's stdout**, so `$d = pwsh -File build.ps1` captured three progress lines wearing the shape of a path. Inside one process the separation is real; across a process boundary only **stderr** keeps it. |
| A bare version in `Find-PSResource -Version` | It reads like a NuGet range, where a bare number means "this or higher". PSResourceGet is the documented exception and treats it as **exact** — which is what this repository wants, so the surprise is that it is right. Verified rather than assumed, because the caller was a publish gate. |
| `Get-CtxProp` on a Hashtable | It navigates `PSObject.Properties`, which sees nothing inside a Hashtable — and `ConvertFrom-Json -AsHashtable` returns one. Use `Get-CtxPaires`. |
| StrictMode | Reading an absent property **throws**. Any field that may be missing goes through `Get-CtxProp`. |
| `Update-TypeData` vs format file | `-DefaultDisplayPropertySet` wins over a `format.ps1xml` view. Two mechanisms, the weaker one wins in silence. |
| `--` in an XML comment | The manifest then refuses to load the **entire module**. `work` and `ctx` stop existing. |
| `if` as an argument | `Cmd -X (if (…) {…})` does not parse. Use `$(…)` or a variable. |
| `pwsh -Command` inherits the parent environment | Declining to *set* a variable does not *clear* it. A test meant to run without a context inherited one and never built the case it claimed to. |
| Clearing a real env var in a test | Removing `SUPABASE_ACCESS_TOKEN` in a `finally` disarmed the leak test that ran later. **Restore, never remove.** |
| `Join-Path` in a pure function | It is a **provider** cmdlet: it resolves the drive and fails with "Cannot find drive" when one is not mounted. Without `-ErrorAction Stop` it does not throw — it returns an **empty string**, and `--user-data-dir --extensions-dir .` ships, where the next flag is read as the previous one's value. Invisible on the machine that has the drive; red on a CI agent that does not. Use `[System.IO.Path]::Combine` wherever the path is data rather than a location. |
| A local composite action inside a job that downloads instead of checking out | `uses: ./…` is read from the **workspace**, so the job has to check the repository out first — and `actions/checkout` **cleans its destination**, so a checkout placed after `download-artifact` takes the downloaded package with it. The publishing job therefore checks out sparsely, first, and then asserts that the package it downloaded carries the version the audit reported. Order is the whole fix, and nothing about it is visible in a diff. |
| A hardcoded absolute path | `C:\Users\<name>\...` and `C:\Program Files\PowerShell\7\` sat in two shipped scripts. They worked on one machine and published a Windows username. Resolve, never assume. |
| Running a GUI application to ask it a question | Probing Antigravity with CLI flags opened the editor, which self-updated, relaunched and crashed on `EPIPE` in a loop on the user's screen. Run a binary only when the install layout proves a command-line entry point exists; otherwise read its argument surface from disk. |
| `[Parameter(Mandatory)]` on an array | Rejects `@()`. `installer-shims.ps1 -Restaurer` passes an empty list to mean "remove everything", and threw on parameter binding — removing the `PATH` entry but leaving the files. Add `[AllowEmptyCollection()]`. |
| `continue` inside a `switch` | It continues the **enclosing loop**, not the switch. Right by accident here, wrong the day the block moves. Use `if`/`elseif` where a reader would have to stop and think. |
| Injecting half a dependency | A function took an `-Exists` callback but still called `Test-Path -PathType Leaf` itself, so a test could describe a path and the function would still ask the real disk. Injected or not injected — never half. |
| Assuming a fixed directory depth | VS Code puts `bin/code.cmd` two levels under `Code.exe`; Cursor puts it four. Walk up and look, do not count. |
| A count as a discriminator | `--list-extensions` returned 160 for two different profiles holding 160 and 165 directories, which read as "the flag was ignored". Compare the values, not their number. |

---

## Conventions

- **Commits** in English, `type(scope): description`. Explain *why*, and name the
  incident when there is one. End with
  `Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>`.
- **Documentation** in English. Command output is currently French; making it
  bilingual through `DEVCTX_LANG` is planned.
- **Comments explain why, never what.** If a comment describes what the line
  does, change the line instead.
- **Branches**: `feature/…`, `hotfix/…`. `main` is protected, and the protection
  was **tested rather than assumed** on 18 August 2026: a direct push is refused
  with `GH006 — Changes must be made through a pull request`. Two consequences
  worth knowing before they surprise you. Four checks are required **by name**
  (`Pester suite / fr`, `Pester suite / en`, `Manifest and module load`, `No
  credential in the repository`), so **renaming a CI job blocks every merge**
  until the rule is updated with it. And administrators are included on
  purpose — the incident this exists for was a direct push to `main` by someone
  who had every right to make it. Lifting it in a real emergency means
  disabling the rule explicitly, which is the point: visible, never silent.
- **Never push without a green suite.** `push done ≠ task done`: check CI too.
- **CI: one suite, one setup.** The Pester matrix lives in
  `.github/workflows/suite.yml` and is *called* by both `ci.yml` and
  `release.yml`, with `fail-fast` and the timeout as its only inputs — the only
  two differences that were ever deliberate. Preparing an environment lives in
  `.github/actions/prepare-powershell`, which reads the required modules **from
  the manifest** rather than from a list beside it. If you find yourself copying
  a job or an install step from one workflow into the other, stop: that is the
  defect that cost three release attempts on 18 August 2026, and it has been
  fixed. `actionlint` checks these files and is worth running before a push.

---

## Specialised agents

Under `.claude/agents/`. Each pins its model by **alias** (`model: opus`), never
a frozen version id — a pinned id blocks upgrades as effectively as downgrades,
and expires in silence.

| Agent | Model | When |
|---|---|---|
| `security-auditor` | opus | Before any release, and after any change to shims, `PATH`, the registry, tokens, or generated config files |
| `test-strategist` | sonnet | After adding a feature — finds what the suite does *not* guarantee |
| `powershell-reviewer` | sonnet | On any change to the module, the shims or the installer |

Security work stays on Opus. When a false negative can publish a credential or
destroy real data, model cost stops being an argument.

---

## Definition of done

1. Tests green, including the one you added
2. Your new test proven to fail on the bug it catches
3. No secret anywhere in the diff — `tests/Securite.Tests.ps1` enforces this
4. Verified on the **real machine**, not only in the test harness
5. Documentation updated when behaviour changed
6. `CHANGELOG.md` updated for anything user-visible
7. Commit message says why
