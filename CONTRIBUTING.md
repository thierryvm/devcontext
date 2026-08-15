# Contributing

Thanks for looking. This is a small, single-maintainer project with an unusually
strict test culture, for a reason: a defect here does not produce a wrong pixel,
it commits under someone else's name or drops a production database.

## Before you start

Open an issue first for anything beyond a typo. It saves you writing code
against an assumption the maintainer does not share — and this project has firm
opinions about where a decision belongs.

## Setup

Windows and PowerShell 7+ are required. The module manipulates the Windows
`PATH`, the `HKCU` registry and DPAPI-backed stores; there is no meaningful way
to develop it elsewhere.

```powershell
Install-Module Pester -MinimumVersion 5.0.0 -Scope CurrentUser
Install-Module PSScriptAnalyzer -Scope CurrentUser
Install-Module Microsoft.PowerShell.SecretManagement, Microsoft.PowerShell.SecretStore -Scope CurrentUser

git clone https://github.com/thierryvm/devcontext.git
cd devcontext
pwsh -NoProfile -File .\tests\RunTests.ps1     # green before you start
```

## The rules that are not negotiable

**Never weaken a test to make it pass.** A red test is information. Do not
adjust an expected value to match the observed output, do not add `-Skip`, do
not loosen an assertion. Find the cause and fix the cause. If the expectation
was genuinely wrong, say so in the pull request and explain why.

**Prove your regression test bites.** Reintroduce the bug, watch it go red,
restore. Say so in the pull request. A test that stays green on broken code
advertises coverage that does not exist — this repository has two recorded cases
of exactly that, both written up in `tests/README.md`.

**Never test a destructive command against a real service.** Build a fake world
under `$TestDrive` and a decoy binary that announces itself. Assert the decoy was
**not** called.

**Never put a secret anywhere.** Not in code, tests, fixtures, examples, commit
messages or output. Test fixtures use obviously synthetic values
(`sbp_0102030405…`). `tests/Securite.Tests.ps1` and CI both enforce this, over
the whole history.

## Where code goes

Decisions are **pure functions** that take facts and return a verdict —
`Test-CtxSupabaseGuard`, `Test-CtxDoctor*`, `Merge-CtxMcpConfig`. No filesystem,
no network, no registry. Gathering and side effects live in thin, mockable
functions around them.

If your test needs an elaborate fake world to reach a decision, the decision is
in the wrong place. Move it into a pure function.

`docs/ARCHITECTURE.md` has the full picture and a worked example of adding a new
service.

## Style

- **Comments explain why, never what.** If a comment describes what the line
  does, change the line.
- **Code in English**, including comments. Command output is currently French;
  making it bilingual is planned and tracked in `CHANGELOG.md`.
- Names carry meaning. `$r` is not a name.
- PSScriptAnalyzer must be clean — see `PSScriptAnalyzerSettings.psd1`, where
  the two disabled rules each carry their reason.

## Commits and pull requests

Conventional commits, in English:

```
type(scope): what changed

Why it changed, and what it prevents. Name the incident when there is one.
```

`feat` · `fix` · `refactor` · `test` · `docs` · `chore` · `security`

In the pull request, tell us: what breaks without this, how you verified it on a
real machine (not only in the harness), and — for a bugfix — that you watched
the new test fail on the old code.

Branch from `main` as `feature/…` or `hotfix/…`. CI must be green.

## Reporting a vulnerability

Not here. See [`SECURITY.md`](SECURITY.md) — use GitHub's private reporting.

## License

By contributing you agree your work is released under the MIT license.
