# Roadmap

What this tool is trying to become, and in which order. Dates are intentions,
not commitments.

The line that decides everything below: **the folder decides, and it decides for
any assistant.** A feature that would tie DevContext to one vendor, one AI
provider, or one shell does not belong here — that lock-in is the problem this
tool exists to remove.

---

## 1.1.0 — shipped, 15 August 2026

The production guard reaching every shell, and the module answering *what can I
do here* rather than only *who am I*. See `CHANGELOG.md`.

---

## 1.2.0 — shipped, 15 August 2026

Editor isolation reaching every launcher, not only the one we wrote. Editors are
discovered and probed rather than listed; shortcuts are audited because they are
the one launcher `PATH` cannot reach. See `CHANGELOG.md`.

---

## 1.3.0 — shipped, 15 August 2026

Every user-facing string now goes through a key. 268 of them, in two languages,
with five tests holding the line translation projects usually lose: matching key
sets, no empty string, matching `{n}` placeholders, ASCII only, and every key
called in code present in both tables.

The migration found a class of bug worth naming — code deciding on **displayed
text**. Three occurrences, each invisible in the language that wrote them. The
rule that came out of it: a displayed value is never a decision value, and a
test now scans every source file for comparisons against any string in the
tables.

Still to translate: `INSTALLATION.md` and `POURQUOI.md`, which are prose
rather than program output.

---

## 1.4.0 — shipped, 16 August 2026

`gh` and `vercel` join the guarded set. `code` was on this list and shipped
early, in 1.2.0 — it turned out to be the most-felt problem, not the least.

The item was written as *refuse a PR when `GH_CONFIG_DIR` does not match*. Half
of that turned out to be the wrong instinct. Refusing is what the Supabase guard
must do, because nobody can guess which database was meant; for `gh` **the right
answer is known — the folder holds it**, so the entry point supplies the
directory instead of refusing. It refuses only when it has nothing to supply.
The rule that came out of it, and which the next guarded tool inherits:
**correct when the answer is knowable, refuse only when it is not.**

`vercel` kept the two refusals as written, and gained the same session
redirection.

See `CHANGELOG.md`, and `SECURITY.md` for what each guard deliberately does not
cover.

---

## 1.5.0 — shipped, 17 August 2026

Commands you can guess. `ctx doctor` used to fail on parameter binding and name
an internal function in the error; both spellings now work, derived from one
table so they cannot diverge. A typo gets the list instead of a stack trace.

The report also stopped implying that an isolated editor profile was the end of
the story: it **is** a separate secret store, so the GitHub sign-in has to be
done once per context, and that is now said rather than discovered.

The shadowed-shim advice learned to distinguish the cheap repair from the
expensive one, instead of prescribing a reinstall to everyone.

---

## 1.6.0 — shipped, 17 August 2026

An identity from one context living in another context's editor profile is now
reported. Isolation stops sessions from overwriting each other; it never stopped
anyone signing into the wrong account inside the right profile — and that is the
same class of error the whole module exists to prevent.

Found on the author's machine the day the check was written, in both directions
at once.

---

## 1.6.1 — finish the fixer

- **`ctx doctor -Fix`** — apply the correction a finding already spells out,
  after confirmation. The diagnostic already knows the answer; making the human
  retype it is friction for nothing.

  Written, then held back: it repairs only what it can **prove and undo** —
  empty `PATH` entries, shims missing from `PATH`, a stale junction — and names
  everything else with the reason. Four families stay manual, and the first one
  is not a limitation but an OS property: the fix for `gh/compte` is `work`,
  which writes into the **calling** shell, and a child process cannot write to
  its parent's environment.

## 1.7.0 — make it easy to start

Adoption dies at the first step. Today a new user must clone, symlink, run an
installer, then create contexts by hand.

- **`ctx init`** — one interactive command that detects existing accounts,
  proposes contexts, and creates them.
- **Publishing from a tag** — a GitHub Actions workflow on `v*`, gated by a
  manual-approval environment so the API key never travels alone.

~~**PowerShell Gallery**~~ — shipped in 1.3.0. `Install-Module DevContext`.

---

## 1.8.0 — macOS and Linux

The decision layer is already portable and has been from the start; what is
nailed to Windows is the **machine integration**, not the logic.

Already portable, and shipped as such:

- `includeIf` and `insteadOf` — plain git config, read by the binary anywhere.
- `GH_CONFIG_DIR`, `SUPABASE_ACCESS_TOKEN`, `vercel --global-config` —
  environment variables.
- The POSIX shims (`shims/gh`, `shims/supabase`, `shims/vercel`) already ship,
  LF-pinned with a shebang, and already carry the guard.
- Context resolution by path, and every pure decision function.
- PowerShell 7 and SecretStore both run on macOS and Linux.

What needs writing:

| Windows today | Unix equivalent |
|---|---|
| `PATH` through the `HKCU` registry | `~/.zshrc` / `~/.profile`, or `~/.local/bin` |
| `vscode://` router through `HKCU` | LaunchServices (macOS), `.desktop` (Linux) |
| Desktop `.lnk` shortcuts | `.app` bundle / `.desktop` entry |
| `.cmd` entry points | unused there, and harmless |

A Linux port also closes the **WSL gap** that `ctx doctor` currently reports as
uncovered — the shim is absent from a distribution's own `PATH`, and a native
Linux install is what puts it there. Two problems, one piece of work.

CI has to grow a macOS and a Linux job on the same day: a port with no matrix is
a port that works only on the machine that wrote it, and this repository has
already paid that lesson five times.

---

## 2.0 — the dashboard

A visual surface over what the commands already expose: every context, every
account, every project, which folder points where, which tokens are about to
expire, which MCP servers a project can reach.

Two constraints decided in advance, because they are the ones that get lost:

**The CLI stays the source of truth.** The dashboard reads what `ctx doctor
-Json` and `ctx-sb` already produce. It adds no logic of its own — otherwise
the two drift, and the one people trust is whichever they happened to open.

The seams are already in place, and they were built as seams on purpose. Every
screen the dashboard needs corresponds to a function that exists and is tested:

| Screen | Reads | Acts through |
|---|---|---|
| Contexts and accounts | `ctx-list`, `ctx doctor -Json` | `Use-DevContext` |
| Editors, and which are isolable | `Get-DevEditorList` | — |
| Shortcuts, and which are broken | `Get-CtxRaccourciChecks` | `New-DevShortcut -Force` |
| Projects per Supabase account | `Get-DevSupabaseMap` | `Update-DevSupabaseIndex` |
| MCP servers per project | `Get-CtxMcpFacts` | `New-DevProjectMcp` |

A "repair this shortcut" button is therefore one call to a function the test
suite already covers, never a second implementation of the same rules living in
a UI. That is the whole reason the decisions were kept pure and separate from
the gathering.

**It stays local.** No account, no cloud, no telemetry. A tool whose whole
purpose is to keep credentials apart cannot ask you to send your credential
topology anywhere.

**Every empty state names the next command.** This is not a polish item, it is
the first screen. On 15 August 2026 a virgin machine was simulated and the CLI
walked into five dead ends in a row: `ctx` answered a red NO-GO to someone who
had done nothing wrong, `ctx-list` said "none" and stopped there, the onboarding
message proposed a command that failed on a missing mandatory parameter, and two
prompts blocked forever on redirected input. None of it was visible on the
author's machine, which is exactly why it survived.

The rule that came out of it, and which the dashboard inherits: **a screen with
nothing on it is the most important screen in the product.** It must say what
this thing is for, what is missing, and the one action that comes next. A UI that
renders an empty table has failed in the same way a CLI that prints "none" has.

**A documentation section, including personal notes.** The dashboard carries the
project's own documentation, and alongside it a place for the operator's own —
their accounts, their conventions, the procedures that belong to their machine
and nobody else's.

That material is deliberately *not* in this repository. A guide describing one
person's accounts and folder layout has no business in a public repository: it is
noise for every reader except its author, and free reconnaissance for anyone
else. It was removed from the tree and from the history on 15 August 2026, and it
returns as data the dashboard displays — never as a file the project ships.

The distinction to keep: [`docs/GUIDE.md`](docs/GUIDE.md) teaches **anyone** to
use the tool and belongs to the project. A personal guide teaches **one person**
to run their own estate and belongs to them.

Likely shape: a local web UI served by a `ctx dashboard` command, or Tauri if it
needs to live in the tray. The decision waits until the CLI surface has settled
— building a UI over an API that is still moving is how both end up bad.

---

## Explicitly out of scope

- **Anything requiring an account with us.** There is no us.
- **Storing secrets anywhere but the OS vault.**
- **Being a Claude tool, a Cursor tool, or any vendor's tool.** MCP is an open
  standard and this module treats it as one.
- **Linux and macOS as first-class targets** — for now. The core idea is
  portable, but the current implementation is deeply Windows: registry, DPAPI,
  `HKCU\Environment`, git-bash. A port is a rewrite of the plumbing, not a
  flag. Worth doing, not worth pretending is close.

---

## Known gaps, carried

- **WSL is not covered.** Its own `PATH`, its own filesystem. `ctx doctor`
  reports it. Closing it means a Linux-side install, which lands with the port.
- **An absolute path bypasses the guard.** Inherent to a `PATH` shim.
- Full list with reasoning: `SECURITY.md`.
