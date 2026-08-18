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

## 1.7.0 — shipped, 17 August 2026

`ctx doctor -Fix`. The diagnostic already knew the answer; it now applies it —
for the repairs it can prove and undo, and only those. Everything else is named
with the reason, because an unexplained silence reads as *nothing more to do*.

---

## 1.8.0 — shipped, 17 August 2026

`ctx init`. Adoption used to die at the first step — clone, symlink, installer,
then a five-parameter command to type by hand.

It guides rather than takes over: it reports what is in place, walks what is
missing in order, and prints every step it does not perform as the exact command
that performs it. It installs no module and creates no context on your behalf —
both are decisions, not chores. And it refuses to prompt when input is
redirected, because a question nobody can answer is worse than no question.

~~**PowerShell Gallery**~~ — shipped in 1.3.0. `Install-Module DevContext`.

---

## 1.9.0 — shipped, 18 August 2026

Published from a tag, by the workflow, behind a human approval — the first
release this project did not push by hand. Also `ctx guard`, and `ctx doctor`
reporting where an agent is allowed to write.

**It took three attempts, and that is the honest headline.** Each failure was the
same defect wearing a different hat: a job written by copying a neighbour and
losing one of its setup steps. The Supabase CLI missing from the test job, then
the vault modules missing from the publishing job. Nothing reached the Gallery
until it was right, which is exactly what the gate is for — but a gate that fires
three times is telling you about the thing behind it, not about luck. The cure is
under *Known gaps*: one `workflow_call`, not three hand-kept copies.

- ~~**A GitHub Actions workflow on `v*`**~~ — written. Split so that everything
  provable happens *before* a human is asked to approve, and so the API key is
  unreachable until they do. `tools/Assert-Release.ps1` holds the decisions,
  because a rule living in YAML can only be tried by publishing.
- ~~`INSTALLATION.md`~~ — the French section added with `ctx init` is translated.
- **`POURQUOI.md`** stays in French for now. It is the only document written to
  be *argued with* rather than followed, and translating it badly would be worse
  than leaving it: the reader who needs it can read the language it is in, and
  the reader who cannot is not missing an instruction.

**One thing this workflow does not do: write the GitHub release notes.** They
are composed by hand, and generating them from commit subjects would replace
something considered with something merely produced. The intended order is
therefore to write the release on GitHub — which creates the tag — and let the
tag start the publish.

---

## 1.10.0 — Linux (and macOS when it can be verified)

The decision layer is already portable and has been from the start; what is
nailed to Windows is the **machine integration**, not the logic.

**Linux first, and macOS only when someone can verify it.** Not a preference —
an admission. Nobody working on this repository has a Mac, and this project's
own recorded lesson is that what breaks is what the author is not in a position
to see. Shipping a macOS port verified only by CI would be claiming support for
a platform nobody has run it on.

Linux does not have that problem, because **WSL is already here**. It is on the
development machine, `ctx doctor` already reports it as uncovered, and the port
is what puts the shims on its own `PATH`. The gap and the feature close with the
same work — and the test bench costs nothing.

Most of the work is shared anyway: POSIX shims, `PATH` through a shell rc file,
XDG paths. Verifying that on Linux de-risks the majority of macOS, leaving
LaunchServices and the `.app` bundle — which will ship when they can be tried,
and be described as untried until then.

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

**It runs commands, never a shell.** An embedded terminal was considered and
deliberately rejected. Not for effort — for what it would undo.

A shell inherits the environment of the window hosting it. Launch the dashboard
without a context and that terminal has none, so `supabase db push` typed inside
our own window runs unguarded — the tool failing its promise in its own
interface. `work` also exports tokens as environment variables: today, seeing
them means having deliberately opened a terminal; embedded, one `env` during a
screen share does it by accident. And the day a repository name, a branch or a
project label read from an API can reach that input, there is command injection
in the tool that holds the keys.

What ships instead is a **command console**, which is the same value without the
shell:

| | |
|---|---|
| Shows | the exact command behind every action — the CLI already prints them (`Correctif`, `ctx init` steps, `-Fix`) |
| One click | copies it |
| A second, explicit click | runs it — from the **module's own commands only**, never free text |
| Output | read-only |
| Every run | stamped with the context it ran under, and refused when none is active — the same `ctx` verdict the CLI applies |

Verification, tests, discoverability and the teaching effect — *so that is the
command* — without an arbitrary shell inside the credential tool. It also stays
inside the rule above: a console that can only run the module's commands is a
reading of the CLI, not a second implementation of it.

If a real terminal is ever added, it is opt-in, launched **with** an explicit
context, the context name in the tab title, and never the default view.

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
- **An embedded shell in the dashboard.** Reasoning under 2.0.

---

## Known gaps, carried

- **The two test jobs are hand-copied, not shared.** `ci.yml` and `release.yml`
  each declare their own matrix, and on 18 August 2026 the release copy was found
  missing the Supabase CLI step the CI copy had — so the first real release ran a
  suite the CI never ran. Both were patched, and that is a treatment, not a cure:
  the next divergence will be as silent as this one. The fix is a `workflow_call`
  the two invoke, with `fail-fast` and the timeout as inputs, since those are the
  only differences that are *deliberate*. Left as its own change rather than
  smuggled into a release. It is the same defect this repository already names
  for the `ctx-*` aliases: **derive both from the same source, or neither**.
- **The artifact actions are two majors behind.** `upload-artifact@v4` and
  `download-artifact@v4` still run on Node 20, which GitHub has announced as
  deprecated; the current majors are v7 and v8. Nothing is broken — it is a
  warning — and the bump is deliberately **not** taken inside a release, because
  the pairing between the two majors is exactly the kind of assumption that has
  cost this project three round trips in a single day. It lands in its own change,
  rehearsed through `workflow_dispatch` with `dry_run` before any tag depends on
  it.
- **WSL is not covered.** Its own `PATH`, its own filesystem. `ctx doctor`
  reports it. Closing it means a Linux-side install, which lands with the port.
- **An absolute path bypasses the guard.** Inherent to a `PATH` shim.
- Full list with reasoning: `SECURITY.md`.
