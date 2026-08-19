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
| A function cannot **return** an array at all | `@($faits)` on the last line does not save you: PowerShell unrolls it crossing the output stream. **Empty** arrives as `$null`, and `$null.Count` throws under StrictMode — loud, at least. **One element** arrives as a bare scalar, and that one is silent: `& $exe @arguments` then splats a STRING, which enumerates its CHARACTERS. On 18 Aug 2026 the three CLI aliases were doing exactly that in shipped 1.9.0 — `vercel whoami` reached the CLI as `w h o a m i`, `gh --version` as `- - v e r s i o n`. The shims were fine; only the aliases were affected, so a shell without the module imported behaved correctly. Occurrences: `Get-CtxVercelMots` (1.4.0), `$reste` in `Invoke-DevCtx`, `Get-CtxAgentConfianceFacts`, and the three `Get-CtxArgumentsBruts` call sites. Wrap at the **call site**, `@(Get-Something)`, and let pure functions take `[AllowNull()]`. |
| Only ever building the populated case | The empty case is the most ordinary input there is, and it was the one no test constructed. `ctx doctor` was green here for a week and red on the first CI agent, because a developer machine always has *some* agent settings file and a fresh runner has none. If a test's result depends on the machine running it, it proves nothing anywhere else — neutralize the machine (`CLAUDE_CONFIG_DIR` to an empty folder) rather than trusting the one you have. |
| Searching a database file as raw bytes | SQLite does not rewrite what it frees — `secure_delete` is off by default — so a deleted key stays written, byte for byte, until its space is reused. The editor-account check read `state.vscdb` whole, and on 18 Aug 2026 kept accusing a profile the user had just cleaned; the Accounts menu of the window was the proof, and **no action could clear the verdict**. That is the cry-wolf failure this repository names elsewhere, turned inward — it even pushes the user to reconnect and disconnect again to "retry". Read the LIVE regions only: skip freelist pages, skip the unallocated gap before the cell content area, skip the freeblock chain inside it. And when the format is not recognised, degrade to *too talkative*, never to blind: a false positive is visible, a false negative is not. |
| Checking the value instead of its source | `ctx` compared the git email to the one the context expects and answered `GO` whenever they matched. But a `user.email` written in a repository's own `.git/config` **overrides the `includeIf`**, so a matching value proves the line was typed correctly — not that the mechanism is alive. Measured 18 Aug 2026: six repositories on one machine were in that state, five with the right value and one with another account's; `ctx` said `GO` on all six. The folder rule was dead in a quarter of the repositories, silently. `git config --show-origin` already answered the question and the diagnostic already passed the origin around — it simply threw it away on the happy path. A guarantee has to be checked at its source, or it is a coincidence you have not measured yet. |
| A rehearsal mode nobody rehearsed | `workflow_dispatch` with `dry_run` exists so `release.yml` can be tried without spending a version number. It worked — until the first version actually shipped. From then on the manifest names a version the Gallery already serves, and the check whose only purpose is *do not publish a duplicate* went fatal in a run that publishes nothing. Latent from the day it was written, and visible only after the success it was built to protect. An assertion belongs to the runs where its consequence exists: ask `steps.mode.outputs.publier` before throwing. |
| An absolute threshold in a test is an expectation that ages | `Should -BeLessThan 700kb` guarded the package against carrying the repo plumbing. On 19 August 2026 it went red on the module's OWN growth -- `DevContext.psm1`, `src/Doctor.ps1` and `CHANGELOG.md` pass 250 kB between them -- while the package carried nothing it should not. Raising the number would have been an expectation recalibrated on the result, which this project forbids. The fix is to assert what the test's own title claims: the package is by construction a SUBSET of the tracked files, so compare the two. Both sides grow together, and the reference defect still fails it by 3.6x. Read the composition before touching the line -- the number may be right and the package wrong. |
| A function defined in `BeforeAll` does not exist inside `InModuleScope` | `InModuleScope` runs its block in the **module's** scope; helpers written in `BeforeAll` live in the test's. Calling one from inside fails with `CommandNotFoundException`, which reads like a missing module function and sends you looking in `src/`. Arrange in the test scope, then pass what the block needs through `-Parameters @{ x = $x }` — the pattern the rest of this suite already uses. Cost: five tests red at once on 19 August 2026, none of them for the reason they were testing. |
| Resolving a tool's config location through its environment variable | `GH_CONFIG_DIR` points at the **context's** config inside any shell where `work` has run. A check that resolves the path that way measures the compartmentalised config — the one that is fine — and answers "nothing to report" on a machine whose **global** config knows two accounts. When the question is *what lives outside the partition*, the system default must be targeted and the variable ignored. Written on 19 August 2026, with the test that fails when the variable creeps back in. |
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
| Assuming the isolation flags you know are the whole list | `--user-data-dir` isolated everything until VS Code 1.133 moved application storage — extension secrets, recent folders, trusted folders — into a machine-wide `~/.vscode-shared`. Nothing announced it; the symptom was a sign-in prompt on every launch, and the evidence was one line in the editor's own `main.log`. An upstream release can move a guarantee out from under a flag without renaming the flag. When a symptom says isolation broke, read the application's log before the module's code. |
| The absence of a side effect is not the absence of support | The probe's rule — only a directory that appeared counts as proof — is right for what it covers, and blind outside it. `--shared-data-dir` is honoured by the GUI and ignored by the `--list-extensions` code path, so probing it measures nothing: exit 0, no directory. Answering `$false` there would state more than is known, wearing the authority of a measurement. Read the declared surface, label it `declared`, and measure the **outcome** somewhere it exists — here, whether the folder is on disk after real use. |
| An install layout that grew a directory | `Read-CtxEditorArgvSurface` looked for `resources/app.asar` and two siblings directly under the editor's root. VS Code now inserts a build id — `...\Microsoft VS Code\a5b5009513\resources\app` — so all three paths matched nothing and the function returned `$null` **in silence**, which the caller read as "this editor declares no flags". The declared fallback had been dead for as long as that layout existed, and only an editor without a CLI would ever have shown it. Probe one level of subdirectories too, and prefer the most informative file: `package.json` exists in nearly every layout and contains no flag, so meeting it first returns an answer that is valid and empty. |
| Adding a field to a cached record | The cache is JSON reread as a hashtable. Reading an absent key does **not** throw — it yields `$null`, which `[bool]` turns into `$false`. An entry written before a new field therefore answers "not supported" with a measurement's authority, and forever, since neither the executable's path nor its timestamp changed. The key carries a schema number; bump it whenever the record gains a field. One extra probe, once, per editor. |
| Running the suite from a shell where `work` has run | `work` imports DevContext from `Documents\PowerShell\Modules\DevContext` (a symlink to this repository), and the suite's `Import-Module <repo>\DevContext.psd1 -Force` then loads a **second** module of the same name from a different path. `InModuleScope DevContext` can no longer choose, and 45 tests go red that have nothing wrong with them. Measured 19 Aug 2026 — same command, 45 failures with the profile, 7 without. Run the suite with `pwsh -NoProfile`. |
| A backslash swallowed as an escape | `\e`, `\v`, `\a`, `\t`, `\n` and friends become CONTROL CHARACTERS in a shell heredoc, a `printf`, or a non-raw Python string. The result is invisible in a diff and in most editors: `shims\editor.ps1` shipped in `docs/ARCHITECTURE.md` as ESC + `ditor.ps1`, and lived there through a public release. Two more were produced on 19 Aug 2026 while writing the very sentences warning about it. Write Windows paths with forward slashes in prose, use raw strings in tooling, and check afterwards — `grep -P '[\x00-\x08\x0b\x0c\x0e-\x1f]'` over the files you touched costs one command and is the only thing that sees it. |
| PowerShell's `-replace` on a replacement string containing `$` | The second operand is a **substitution pattern**, not a literal: `` $` `` means "everything before the match" and will paste the file's own opening into the middle of a line. Used on 19 Aug 2026 to put a bug back and prove a regression test bites, it corrupted `src/Doctor.ps1` instead — the file was restored from git and the patch reapplied from its script. Round-trip edits belong in a tool with no substitution semantics. |

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
