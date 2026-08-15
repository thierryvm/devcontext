# Architecture

How DevContext is put together, and why each piece sits where it does. Written
for whoever maintains it next — human or agent.

---

## The one idea

> **The folder decides. Never the session.**

Everything else follows. A session variable can be forgotten, inherited, lost
across a process boundary, or simply absent — as it always is in git-bash, in an
npm script, and in an AI agent's shell. A folder is a fact you cannot forget to
set, because you are standing in it.

This was learned the expensive way. The production guard originally opened with
`if (-not $env:DEVCTX) { Invoke-Real }`, which made it step aside in exactly the
shells it was built for. On 15 August 2026 a `supabase db reset --linked`
against a production project went straight through from git-bash; it failed on a
network timeout, not on anything the guard did.

When you extend this module, ask of every new decision: *would this still be
right in a shell that has never heard of DevContext?* If not, it belongs in
`Resolve-DevContextForPath`, not in a variable.

---

## Layout

```
DevContext.psd1              Manifest. Version, dependencies, export list.
DevContext.psm1              Core: contexts, activation, verification.
DevContext.format.ps1xml     Table views for the objects commands return.
src/
  Doctor.ps1                 ctx doctor — what works here, and on which account
  Jetons.ps1                 ctx doctor -Live — do the tokens work, on the right account
  Mcp.ps1                    ctx mcp — project-scoped MCP, any assistant
shims/
  supabase.ps1               The guard. Decides, then delegates or refuses.
  supabase.cmd               Entry point for cmd.exe, PowerShell, npm  (CRLF)
  supabase                   Entry point for POSIX shells               (LF)
installer-shims.ps1          Puts shims/ first in PATH. Reversible.
tests/                       See tests/README.md
```

Files under `src/` are **dot-sourced** into the module rather than declared as
`NestedModules`. They therefore share module scope — they see `$script:CtxRoot`
and the internal helpers — and a single `Export-ModuleMember` remains the one
place that decides what leaves.

---

## The export trap

The real export is the **intersection** of two lists:

| Where | What |
|---|---|
| `DevContext.psm1` | `$exportedFunctions`, `$exportedAliases` |
| `DevContext.psd1` | `FunctionsToExport`, `AliasesToExport` |

Adding a command to only one makes it **silently invisible**: no error, no
warning, just a command that cannot be found. `tests/Manifest.Tests.ps1` checks
the two lists agree, and does so **without importing the module** — a test that
imports what it verifies proves nothing when the import is the broken part.

---

## Decision, then action

Every non-trivial feature is split in two, and the split is not stylistic.

**Pure decisions** — `Test-CtxSupabaseGuard`, `Test-CtxDoctor*`,
`Add-CtxPathEntry`, `Merge-CtxMcpConfig`. They take facts as parameters and
return a verdict. No filesystem, no network, no registry. They are where the
interesting logic lives, and they can be tested exhaustively without a machine
that happens to be misconfigured.

**Gathering and effects** — `Get-Ctx*Facts`, `Invoke-CtxApi`, the writers. Thin,
boring, and mockable.

When you add behaviour, put the judgement in a pure function. If a test needs an
elaborate fake world to reach a decision, the decision is in the wrong place.

---

## How the guard works

```
  supabase db reset
        │
        ├─ PATH resolves to shims/supabase(.cmd)
        │
        ├─ Which context owns this FOLDER?          Resolve-DevContextForPath
        ├─ Which project is this folder linked to?  Resolve-CtxSupabaseRef
        ├─ Is that project tagged prod?             Get-CtxSupabaseEnv
        ├─ Which branch, and which is default?      git
        │
        ├─ Test-CtxSupabaseGuard   ── allowed ──▶ exec the real CLI, propagate exit code
        │                          └─ refused ──▶ print, exit 1
        │
        └─ anything unexpected ─────────────────▶ exec the real CLI
```

Three properties are deliberate:

**It fails open.** Missing module, unreadable index, unknown environment,
unexpected error — the command passes through unchanged. This is a trade, stated
plainly in `SECURITY.md`: a guard that blocks whenever it hesitates gets
uninstalled, and an uninstalled guard protects nothing.

**It duplicates `Resolve-RealExe` from the module on purpose.** Delegation has to
keep working when the module is missing or broken, which is exactly when it
matters most.

**It never prints a token, an environment variable, or the command's own
arguments.** A refusal is pasted into chats and written to logs; arguments can
carry `--db-url`, and a `--db-url` carries a password.

---

## Three entry points, one script

`supabase.cmd`, `supabase` and `supabase.ps1` are not redundancy. PowerShell and
cmd resolve the `.cmd`; POSIX shells resolve only the extensionless sibling.
Losing either uncovers a whole class of caller. This mirrors the npm convention.

Line endings are load-bearing and pinned in `.gitattributes`: the POSIX file
**must** be LF, because `#!/bin/sh` followed by CRLF fails on Unix with
`bad interpreter: /bin/sh^M`. `tests/Shell.Tests.ps1` checks both.

`supabase.ps1` deliberately has **no `param()` block**. `[CmdletBinding()]` would
capture `-debug` and `-verbose` as its own parameters instead of forwarding them;
`$args` forwards everything verbatim.

---

## Identity resolution

`Resolve-DevContextForPath` compares normalised roots, **longest root wins**, so
a context nested under another resolves to the more specific of the two.

`Get-NormalizedRoot` appends a trailing separator, and that separator is the
whole point: without it, `F:\PROJECTS\Apps` also matches
`F:\PROJECTS\Apps-Autre`, and the guard confidently states the opposite of the
truth. `tests/ContextResolution.Tests.ps1` pins this case by name.

---

## Where credentials live

| Layer | Mechanism |
|---|---|
| At rest | SecretManagement vault `DevContext`, key `devctx/<context>/<name>` |
| In transit | Environment variables set by `work`, inherited by child processes |
| In files | **Never.** Generated configs reference `${VAR}`, or nothing at all |

`.mcp.json` deliberately declares **no `env` block** for Supabase. A
`"${SUPABASE_ACCESS_TOKEN}"` reference expands to an **empty string** when the
variable is unset, and the CLI reads an empty string as *a token was supplied and
it is invalid*. Plain process inheritance leaves an absent token absent, and the
resulting error names the real problem. The same reasoning is why
`Set-CtxSupabaseToken` removes the variable rather than setting it to `''`.

---

## Adding a service

Say you want `ctx doctor` to cover Netlify.

1. **Secret** — add `'netlify-token' = 'NETLIFY_AUTH_TOKEN'` to `$script:SecretMap`.
2. **Decision** — write `Test-CtxDoctorJetonNetlify` in `src/Jetons.ps1`: pure,
   taking the expected account and the observed one, returning a check.
3. **Gathering** — call the API in `Get-CtxJetonChecks`, through `Invoke-CtxApi`
   so the timeout and the redaction come for free.
4. **Tests** — cover every return path of the decision, including *valid token,
   wrong account*, which is the failure that matters.
5. **Export** — only if it is user-facing, and then in **both** lists.

Adding a guarded CLI is the same shape: a new folder in `shims/` with its three
entry points, a pure `Test-Ctx<Tool>Guard`, and a line in `installer-shims.ps1`.

---

## Deliberate limits

Documented so nobody rediscovers them as surprises. The full list, with
reasoning, is in `SECURITY.md`.

- **WSL is not covered.** Its own `PATH`, its own filesystem view. `ctx doctor`
  reports this rather than pretending otherwise.
- **An absolute path bypasses the guard.** It stops mistakes, not operators.
- **PATH placement is trust.** Whoever can write to `shims/` runs code in every
  shell.
- **`npx` fetches at run time.** Upstream's recommended form; pin it yourself if
  your threat model requires it.

---

## Machine-level footprint

Everything DevContext writes outside its own folder, and how to undo it.

| What | Where | Undo |
|---|---|---|
| Shims in `PATH` | `HKCU\Environment\Path` | `installer-shims.ps1 -Restaurer` |
| VS Code URI router | `HKCU\Software\Classes\vscode\...` | `installer-uri-router.ps1 -Restaurer` |
| Module link | `Documents\PowerShell\Modules\DevContext` | delete the symlink |
| Secrets | SecretStore vault `DevContext` | `Remove-Secret` |

The PATH is written **through the registry**, preserving the value kind.
`[Environment]::SetEnvironmentVariable` returns the *expanded* value; writing it
back bakes `%USERPROFILE%` in as a literal path and downgrades `REG_EXPAND_SZ` to
`REG_SZ` — permanently, and silently.
