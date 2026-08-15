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

## 1.2.0 — speak the user's language

**Bilingual output through `DEVCTX_LANG`.** Command output is French today;
documentation is English. A developer in Berlin installing this gets refusals
and diagnostics in a language they may not read — the most visible inconsistency
there is, and the one that gets a tool uninstalled on first run.

Default to the system locale, `DEVCTX_LANG=en|fr` to override. English is the
fallback for any string not yet translated, so a missing translation degrades
into a readable message rather than a blank.

Also in scope: translating `INSTALLATION.md` and `POURQUOI.md`.

---

## 1.3.0 — guard more than Supabase

The shim pattern generalises. Each new tool is a folder in `shims/`, three entry
points, and one pure `Test-Ctx<Tool>Guard`.

- **`vercel`** — refuse `--prod` deploys from a branch that is not the default,
  and refuse `env rm` against production.
- **`gh`** — refuse a push or a PR when `GH_CONFIG_DIR` does not match the
  folder's context. This is the failure that started the whole project.
- **`code`** — a bare `code .` inside a context folder should open the context's
  VS Code profile, not the default one. Four profiles means four GitHub
  sign-ins, and after a reboot Windows relaunches VS Code without its original
  arguments, landing you in the one where you are signed into nothing.

---

## 1.4.0 — make it easy to start

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

**It stays local.** No account, no cloud, no telemetry. A tool whose whole
purpose is to keep credentials apart cannot ask you to send your credential
topology anywhere.

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
