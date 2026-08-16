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

Three zones, and which one a file belongs to is decided by **who invokes it**.

```
DevContext.psd1              Manifest. Version, dependencies, export list.
DevContext.psm1              Core: contexts, activation, verification.
DevContext.format.ps1xml     Table views for the objects commands return.
lang/
  fr.psd1  en.psd1           Every user-facing string, one key each.

src/                         DOT-SOURCED. Never invoked directly.
  Chemins.ps1                Path rules shared by the module and the installer
  Langue.ps1                 Key lookup, and the fallback that renders [the.key]
  Doctor.ps1                 ctx doctor — what works here, and on which account
  Jetons.ps1                 ctx doctor -Live — do the tokens work, on the right account
  Mcp.ps1                    ctx mcp — project-scoped MCP, any assistant
  Editors.ps1                ctx editors — find editors, measure what they support
  Shortcuts.ps1              ctx doctor / ctx shortcut — the launcher PATH cannot reach
  Gh.ps1                     gh — the identity correction, and the guard behind it
  Vercel.ps1                 vercel — production refusals, and session redirection

shims/                       INVOKED BY PATH, by any shell.
  supabase.ps1               The production guard. Decides, then delegates or refuses.
  gh.ps1                     Identity. Corrects when it can, refuses when it cannot.
  vercel.ps1                 Production refusals, plus --global-config injection
  <tool>.cmd                 Entry point for cmd.exe, PowerShell, npm  (CRLF)
  <tool>                     Entry point for POSIX shells               (LF)
  editor.ps1                 Editor isolation, shared by every editor
  <editor>.cmd / <editor>    GENERATED per machine, from the editors found there

<root>/*.ps1                 INVOKED BY ABSOLUTE PATH, from outside PowerShell.
  installer-shims.ps1        Puts shims/ in PATH, writes the entry points, poses the junction
  installer-uri-router.ps1   Registers the vscode:// handler in HKCU
  vscode-uri-router.ps1      What that registry key points AT
  lancer-editeur.ps1         Detached launch for shortcuts. Deduces the context.
  lancer-vscode.ps1          The 8 Aug 2026 launcher, named by shortcuts already on disk

tools/Build-Package.ps1      Assembles the published package from git ls-files
tests/                       See tests/README.md
```

Files under `src/` are **dot-sourced** into the module rather than declared as
`NestedModules`. They therefore share module scope — they see `$script:CtxRoot`
and the internal helpers — and a single `Export-ModuleMember` remains the one
place that decides what leaves.

### Why five scripts sit at the root

Because each is named, by absolute path, by something that is not PowerShell: a
human typing a command, `HKCU\Software\Classes\vscode\...`, or a `.lnk` file on
somebody's desktop. Nothing dot-sources them and nothing resolves them through
`PATH`, so they cannot live in `src/` or `shims/` — those two zones are defined
by the opposite property.

**Moving or renaming one is a breaking change with no deprecation path.** A
registry value and a desktop shortcut hold a literal string; they do not follow.
That is not theory: on 13 August 2026 the repository moved, the old folder was
deleted, and every shortcut opened a terminal that closed instantly while the
dangling `vscode://` handler brought back permanent GitHub re-authentication
across every project. `INSTALLATION.md` lists the four consumers to repair after
any move.

The `lancer-*` names are French in an otherwise English-facing package. That is
a wart, and it stays one: renaming them would break every shortcut already
written, which is a real cost paid to fix an aesthetic one.

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

## One rule, two callers

A guarded CLI is reached two ways, and this is the invariant that keeps them
honest: **the rule lives in the module, never in the shim.**

| Caller | Reaches | Covers |
|---|---|---|
| `shims/<tool>` in `PATH` | every shell | git-bash, cmd, npm, Node, an agent |
| the module's alias | PowerShell only | and it wins there — aliases outrank `PATH` |

That last cell is the whole point. `Get-Command supabase` in a session that
imported the module answers **`Alias`**, not the shim. Until 16 August 2026 the
gathering and the decision lived inside `shims/supabase.ps1`, and
`Invoke-DevSupabase` never called the guard — so the protection covered every
shell except the one it was used from every day. Measured against a decoy:
`db reset --linked` on a production project ran, exit code 42, no refusal.

So each tool has `Resolve-Ctx<Tool>Verdict` in the module, and both callers ask
it. A shim that holds a rule is a rule that only exists for the callers passing
through that shim.

The suite missed it for the same reason it was written: every end-to-end test
invoked the shim **by path**. It exercised the file, never the command a user
types. Tests for a guard must name the *command*, not the *script*.

---

## Correct, or refuse

The three guarded CLIs do not behave the same way, and the difference is not
stylistic.

| Tool | On an unwanted state | Because |
|---|---|---|
| `supabase` | **refuses** | Nobody can guess which database was meant. |
| `gh` | **corrects**, refuses only when it cannot | The folder holds the right answer: which context owns it. |
| `vercel` | both | Session directory: corrects. Production deploy from a side branch: refuses. |

The rule for the next one: **correct when the answer is knowable, refuse only
when it is not.** A refusal is a cost paid by the user, and it is only worth
paying when the alternative is guessing.

Two properties survive in both directions. A correction applies to the **child
process only** — `gh.ps1` sets `GH_CONFIG_DIR` on itself, which exists solely to
launch `gh`. And a value the caller set **deliberately** is never overwritten;
it is judged and reported instead. An outsourced choice that silently reverses
an explicit one is worse than no help at all.

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

## Two shims, opposite timing

The supabase guard and the editor shim sit side by side and behave in opposite
ways, on purpose.

The guard **refuses or delegates**, and every uncertain path delegates: no
context, no linked project, an unreadable index, an unexpected error. A guard
that breaks when it hesitates is uninstalled within the week.

The editor shim **adds flags and never removes any**, and it is likewise silent
when unsure. Its failure mode is therefore "isolation you did not get", not
"editor that will not start" — the right way round for something standing
between a developer and their editor.

They also differ on blocking. The editor shim runs the editor **synchronously**:
code --wait COMMIT_EDITMSG is git's editor, and returning early there commits
an empty message. A shortcut needs the reverse — lancer-editeur.ps1 detaches
through start, or the launching process survives the whole working session.
Two needs, two paths, the same context decision behind both.

The editor's name reaches ditor.ps1 through DEVCTX_SHIM_EDITOR, set by the
entry point, never as a parameter: the argument stream belongs to the caller and
must arrive untouched.

---

## Discovered, not declared

Editors.ps1 ships names as **search hints** and derives everything else by
looking. The rule it enforces: a flag counts as supported only when the
directory it names actually appeared on disk. Exit code alone proves nothing —
every editor in this family accepts an unknown flag and exits 0.

Where no command-line entry point exists, the application's argument surface is
read from its bundle instead, and the capability is labelled declared rather
than measured. Weaker evidence, reported as weaker. **A GUI is never launched
to answer the question**; doing so once left an editor crashing in a loop on the
user's screen.

Results are cached under the context root, keyed on the executable's path *and*
its last-write time, so an editor that gains a flag by updating is re-probed and
one that has not changed costs nothing.

---

## Identity resolution

`Resolve-DevContextForPath` compares normalised roots, **longest root wins**, so
a context nested under another resolves to the more specific of the two.

`Get-NormalizedRoot` appends a trailing separator, and that separator is the
whole point: without it, `C:\Work\Apps` also matches
`C:\Work\Apps-Autre`, and the guard confidently states the opposite of the
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

Adding a guarded CLI is the same shape, with one extra step that is not
optional:

1. **`src/<Tool>.ps1`** — a pure `Test-Ctx<Tool>Guard` taking facts as
   parameters, plus `Resolve-Ctx<Tool>Verdict` doing the gathering. Both live in
   the module. See *One rule, two callers* above for why the shim must not hold
   them.
2. **`shims/<tool>.ps1`, `.cmd`, and the extensionless sibling** — CRLF for the
   first, LF for the last, pinned in `.gitattributes`.
3. **Both lists in `installer-shims.ps1`** — `$script:ShimFichiers` so a partial
   install is caught, `$script:ShimOutils` so `-Verifier` shows the resolution.
4. **`shims/.gitignore`** — it is an allowlist; an unlisted file is treated as
   generated.
5. **If the module also exposes an alias for that tool**, point it at the same
   `Resolve-Ctx<Tool>Verdict`. Otherwise the alias and the shim are two
   implementations of one rule, and the one people hit is whichever they
   happened to type.
6. **Tests at both ends**: the pure decision exhaustively, and end-to-end
   against a **decoy** binary — from PowerShell *and* from git-bash.

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
