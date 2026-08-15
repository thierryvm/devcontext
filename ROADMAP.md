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

## 1.3.0 — speak the user's language

**Bilingual output through `DEVCTX_LANG`.** Command output is French today;
documentation is English. A developer in Berlin installing this gets refusals
and diagnostics in a language they may not read — the most visible inconsistency
there is, and the one that gets a tool uninstalled on first run.

Default to the system locale, `DEVCTX_LANG=en|fr` to override. English is the
fallback for any string not yet translated, so a missing translation degrades
into a readable message rather than a blank.

Also in scope: translating `INSTALLATION.md` and `POURQUOI.md`.

---

## 1.4.0 — guard more than Supabase

The shim pattern generalises. Each new tool is a folder in `shims/`, three entry
points, and one pure `Test-Ctx<Tool>Guard`.

- **`vercel`** — refuse `--prod` deploys from a branch that is not the default,
  and refuse `env rm` against production.
- **`gh`** — refuse a push or a PR when `GH_CONFIG_DIR` does not match the
  folder's context. This is the failure that started the whole project.

`code` was on this list and shipped early, in 1.2.0 — it turned out to be the
most-felt problem, not the least.

---

## 1.5.0 — make it easy to start

Adoption dies at the first step. Today a new user must clone, symlink, run an
installer, then create contexts by hand.

- **`ctx init`** — one interactive command that detects existing accounts,
  proposes contexts, and creates them.
- **PowerShell Gallery** — `Install-Module DevContext`. The manifest is already
  publishable; this is the single biggest change to how far the tool travels.
- **`ctx doctor --fix`** — apply the correction a finding already spells out,
  after confirmation. The diagnostic already knows the answer; making the human
  retype it is friction for nothing.

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
