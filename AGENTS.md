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
| `Get-CtxProp` on a Hashtable | It navigates `PSObject.Properties`, which sees nothing inside a Hashtable — and `ConvertFrom-Json -AsHashtable` returns one. Use `Get-CtxPaires`. |
| StrictMode | Reading an absent property **throws**. Any field that may be missing goes through `Get-CtxProp`. |
| `Update-TypeData` vs format file | `-DefaultDisplayPropertySet` wins over a `format.ps1xml` view. Two mechanisms, the weaker one wins in silence. |
| `--` in an XML comment | The manifest then refuses to load the **entire module**. `work` and `ctx` stop existing. |
| `if` as an argument | `Cmd -X (if (…) {…})` does not parse. Use `$(…)` or a variable. |
| `pwsh -Command` inherits the parent environment | Declining to *set* a variable does not *clear* it. A test meant to run without a context inherited one and never built the case it claimed to. |
| Clearing a real env var in a test | Removing `SUPABASE_ACCESS_TOKEN` in a `finally` disarmed the leak test that ran later. **Restore, never remove.** |
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
- **Branches**: `feature/…`, `hotfix/…`. `main` is protected.
- **Never push without a green suite.** `push done ≠ task done`: check CI too.

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
