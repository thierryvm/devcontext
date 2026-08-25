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

## 1.10.0 — shipped, 22 August 2026

`ctx dashboard`: the whole estate as one generated page, opened in a browser. It
decides nothing — every verdict on it comes from `ctx doctor`, and a test asserts
the two sets are identical. It reaches no network, and the file it writes is
treated as what it is: a reconnaissance document.

---

## 1.11.0 — shipped, 25 August 2026

Written from a usage report by an agent working on another project against
1.10.0. Three defects, all reproduced here before a line was changed, and two of
the report's own claims measured false and corrected. See `CHANGELOG.md`.

The one worth carrying forward is the second: `ctx` returned GO on a folder where
`ctx doctor` returned PROBLEME, on the same fact, in the same process. That is the
**second** time this shape appeared — 19 August fixed it on the ownership axis.
Fixing the reported instance again would have bought a few weeks, so the family
was closed instead: every domain `doctor` judges, `ctx` either judges the same way
or does not display. Closing it surfaced two more instances nobody had reported.

---

## 1.12.0 — the machine-readable surface

**Decided 25 August 2026**, from two independent requests that arrived within a
day of each other and asked for the same thing: the usage report above, and an
orchestrator being built to run sessions across a machine's projects. Two callers
who had never spoken is the strongest argument this roadmap has seen for a
surface. It is also the reason to design both halves together rather than dribble
them out — they serve one audience and should read as one surface.

Nothing here is bent for one caller. Each item is defended on its own below, and
the third is deliberately **not** built the way it was asked for.

### `ctx -Json` — yes

**The first objection was wrong, and it is worth recording as wrong.** It ran: a
second JSON producer means two answers to one question, the exact family closed in
1.11.0. That does not hold. Since 1.11.0 both commands consume the *same* pure
decisions, so a second rendering cannot disagree unless someone writes it to.

The rule that must hold is therefore narrower and stricter than "don't": the JSON
is a **rendering** of the same problems and remarks the human output already
carries — never a second computation — and a test asserts the two cannot diverge.

It is needed because `ctx doctor -Json` answers a different question. `doctor`
reports what works here and on which account; it returns INFO and ATTENTION on
axes `ctx` deliberately stays silent about. A caller that wants *is this folder GO
or NO-GO* cannot get it from `doctor` without re-deciding — which is the defect
itself.

What it must carry: the verdict, the failing axes by **stable identifier** rather
than by translated sentence, and the remedy. The identifiers are the point: a
caller that greps a message is a caller that breaks the day the message is
reworded, or reads it in the other language.

### `ctx exec <command>` — yes, and it is a security feature

The report argues it well: the cost of `work <ctx> -NoCd;` is not the typing, it
is that **forgetting it is silent**. A command without the prefix produces no
signal. `ctx exec` replaces *did I remember?* — a question answered wrong once in
fifty — with an invariant that can be grepped in a transcript afterwards.

The sharper argument was found while answering the orchestrator, on 25 August
2026, and it is not in the report. A child process inherits `DEVCTX_ALLOW_PROD`,
which is this module's own documented bypass of the production guard. Also
`DEVCTX_ALLOW_GH` and `DEVCTX_ALLOW_VERCEL`. So today every tool that spawns a
child is reimplementing the sanitising, and getting it wrong in the single way
that matters: a human disarms the guard once, deliberately, in their session — and
everything launched from there carries the disarmed guard into a folder that never
consented to it. That is the incident this module exists to prevent, produced by
the tool meant to prevent it.

Constraints that must hold, or it should not ship:

- The child's environment is built by **allow-list from the target context**,
  never by copying the parent's and patching it. Copy-then-patch always leaks the
  variable nobody thought of, and there are twenty-eight touched by this module
  alone.
- The three `DEVCTX_ALLOW_*` bypasses are **cleared, always**, with no flag to
  keep them. A bypass is a deliberate gesture inside one session; inheriting it is
  not that gesture.
- The context is resolved from the **folder**, never from `$env:DEVCTX` — the
  doctrine of the whole module, and the only reading a child can trust.
- The child's exit code is returned unchanged. A wrapper that swallows an exit
  code is a wrapper that hides a failure.
- A folder no context owns is a **refusal**, not a guess, and the exit code says
  which.

Not proposed, and the report is right to rule it out: automatic loading from a
profile. A context that loads itself is a context nobody can name.

### Naming a remote MCP connector — yes, but not as asked

The gap is real, and the report states it more honestly than most: `ctx doctor`
sees MCP servers declared in a **file**, and cannot see connectors authenticated
at the assistant's **account** level. Those are nowhere on disk. Such a connector
slips past every net at once — `ctx` says GO, no PATH is involved so no shim is in
the call chain, and an application preflight cannot see it either.

The proposed check compares *this project declares no project-scoped MCP file*
against *the machine knows remote connectors of the same family*.

**The second half is refused.** "Of the same family" requires a maintained list of
MCP server families, and this repository's own doctrine is that a list a human
must remember to complete is a list that will be incomplete. It has already cost
this project a session twice — the analysed-files list, and the exported-aliases
list. A check that rots silently is worse than an absent one.

The version that cannot rot drops the families entirely — and a first attempt at
replacing them was **wrong, caught in review on 25 August 2026**. It proposed
firing when *this machine uses MCP at all, and this folder declares nothing of its
own*. The first half does not derive: a connector authenticated at the assistant's
account leaves nothing on disk, so on the machine where the whole risk lives —
account-level connector, no file anywhere — the condition reads false and the
check stays silent. A proxy that fails in exactly the configuration it exists for
is worse than no check, because it reports having looked.

What is left is the only half that cannot produce that false negative: **this
folder declares no project-scoped MCP configuration**. No machine-side condition,
no list, nothing to derive from evidence that is not there.

Its limit has to be written into the message, not just into this file: the check
sees **file-backed** MCP configuration only. Account-level connectors are not
observable from this machine and are not covered — which is also why the wording
says a remote connector **may** cover this project under another account. It
proves the absence of a local guard. It proves nothing about an account.

Kept from the proposal, because it is the best part of it: the wording says a
remote connector **may** cover this project under another account. The check
proves the absence of a local guard. It proves nothing about an account, and must
never sound as though it does.

**Counted on 25 August 2026, before writing a line — and the count changed the
answer twice.**

Unconditional, the check fires on **22 folders out of 22**. Not one project on
this machine declares a project-scoped MCP configuration. A remark that appears
everywhere discriminates nothing, and noise is how a guard gets uninstalled. On
that number alone the honest outcome was to ship nothing.

The same pass measured the other half, and the risk is not hypothetical: **eight
MCP servers are declared machine-wide**, across four configuration files, and
several are exactly the account-authenticated kind — Linear, Coda, Notion,
GitHub, Supabase. Every project here inherits whichever account was connected
last, and none of them carries a local declaration to pin it.

What rescues the check is a narrowing that **derives from evidence this module
already reads**, with no list to maintain: a project the module can prove is
linked to an account-scoped service — `supabase/.temp/project-ref`, which
`Resolve-CtxSupabaseRef` already resolves, or `.vercel/project.json`, which
`Get-CtxVerdictVercelSession` has read since 1.11.0.

    unconditional                     22 / 22   fires everywhere, says nothing
    linked to Supabase or Vercel       5 / 22   discriminates, but one is a lie
    linked to Supabase alone           4 / 22   discriminates, and the remedy works

**Four, not five — corrected on 25 August 2026, and the correction matters more
than the number.** `ctx mcp` knows how to declare exactly two servers: Supabase
and GitHub. There is no Vercel MCP server in this module. So flagging a project
linked to Vercel *alone* — `savoora` is the one here — would name a risk and point
at a remedy that writes nothing. `ctx mcp` there prints *nothing to declare*, and
rightly. The discriminator is the **Supabase link alone**: the only linked service
whose MCP server this module can actually pin. Linked is not declarable.

**And the remedy has a silent first run, which nearly shipped a guard pointing at
an inert command.** `ctx mcp` without `-Client` serves only assistants ALREADY
present in the folder — it declines to write a `.cursor/` into a repository whose
team does not use Cursor, which is right, and shared committed files make that
mess spread on the next pull. But the bootstrap case is exactly the one it
refuses: with no file anywhere, the first run does nothing on every project, and
reads as *nothing to do*. That is why `ctx mcp` shows zero adoption on twenty-two
projects. Whatever this check says, it must name `ctx mcp -Client <assistant>` —
never the bare command.

**Its scope has to be stated, in the message and in `SECURITY.md`.** The check
covers projects whose link the module can see. The other seventeen — fourteen of
them git repositories — may be just as exposed through a GitHub, Linear or Notion
connector, and the check will stay silent about them. That is a declared limit,
not a misreading: it does not fail *because* the risk is hidden, it simply does
not claim ground it cannot stand on. Rejecting the earlier condition was right
for the opposite reason — that one read *false* exactly where the danger lived.

Verdict level: **ATTENTION**, and it clears when `ctx mcp` is run. A warning with
a remedy that visibly removes it is the kind people act on.

**One finding from the count is worth more than the check itself.** `ctx mcp`
ships in this module and has been used on **zero** of the twenty-two projects on
the machine that wrote it. That is this repository's recurring pattern — what
breaks is what the author is not in a position to see — arriving from the inside
this time.

---

## Deferred — Linux and macOS

**Not scheduled, and that is a decision rather than a backlog accident.**
Reviewed again on 22 August 2026 when the dashboard's reach was chosen, and left
where it was: the interface goes first, on Windows, and this waits for a machine
to verify it on. Originally reviewed on 18 August 2026 and deliberately left
without a version number:
nobody has asked for it, the module has been public for three days, and nobody
working on it has a Mac.

A port nobody can verify is not a feature, it is a promise. This project's whole
argument is that an unverified guarantee is worse than an absent one — a `deny`
rule that never matches, a test green for the wrong reason — and *supports
macOS* written on the strength of a CI job would be the same mistake in the
README instead of the code. It gets a number the day someone asks for it, or the
day there is a Mac to try it on.

The decision layer has been portable from the start; what is nailed to Windows
is the **machine integration**, not the logic. That groundwork is real, it
already ships, and it stays true while this waits.

**WSL was the one argument for doing it now, and it turns out to be
separable.** The gap is on the development machine, `ctx doctor` already reports
it, and what closes it is putting the POSIX shims on a distribution's own
`PATH` — which needs no release for either platform. It is tracked on its own,
under *Known gaps*.

If this is ever picked up: Linux first, and macOS only when someone can verify
it. Most of the work is shared — POSIX shims, `PATH` through a shell rc file,
XDG paths — so Linux de-risks the majority of macOS, leaving LaunchServices and
the `.app` bundle, which would ship described as untried until they are tried.

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

CI would have to grow a macOS and a Linux job on the same day: a port with no matrix is
a port that works only on the machine that wrote it, and this repository has
already paid that lesson five times.

---

## 2.0 — the dashboard

A visual surface over what the commands already expose: every context, every
account, every project, which folder points where, which tokens are about to
expire, which MCP servers a project can reach.

**Split in two on 22 August 2026, and that split is the decision that shapes
everything below.** What was written as one product is two, because they answer
questions of different scope:

| | the dashboard (2.0) | the watchman (2.1) |
|---|---|---|
| answers | *what is true of this folder* | *something is wrong somewhere on this machine* |
| opened | on demand | never — it is simply there |
| scope | the folder | the machine |
| ships | inside the module | as a separate, optional binary |

Conflating them produced a requirement that contradicts the product: a tray icon
naming a *current context*. **There is no current context at machine level.** The
folder decides, never the session — so a tray answering *who am I right now*
would reinstall, in the interface, the exact mental model this tool exists to
remove, and it would be wrong the moment a second window sits in a client folder.
Rejected for the same reason as the embedded terminal below.

What is genuinely machine-wide is not identity, it is **breakage**: a token about
to expire, a broken shortcut, a foreign account in a global config. That is 2.1,
and it is small.

Two constraints decided in advance, because they are the ones that get lost:

**The CLI stays the source of truth.** The dashboard reads what `ctx doctor
-Json` and `ctx-sb` already produce. It adds no logic of its own — otherwise
the two drift, and the one people trust is whichever they happened to open.

The seams were built as seams on purpose. On 22 August 2026 they were
**measured** rather than trusted, because *the seams are already in place* is
exactly the shape of claim this project refuses to accept elsewhere. Every
function named below exists and is tested. Two of them cannot be called from
outside the module:

| Screen | Reads | Reachable | Acts through | Reachable |
|---|---|---|---|---|
| Contexts and accounts | `ctx-list`, `ctx doctor -Json` | yes | `Use-DevContext` | yes |
| Editors, and which are isolable | `Get-DevEditorList` | yes | — | — |
| Shortcuts, and which are broken | `Get-CtxRaccourciChecks` | **no** | `New-DevShortcut -Force` | yes |
| Projects per Supabase account | `Get-DevSupabaseMap` | yes | `Update-DevSupabaseIndex` | yes |
| MCP servers per project | `Get-CtxMcpFacts` | **no** | `New-DevProjectMcp` | yes |

`Get-CtxRaccourciChecks` and `Get-CtxMcpFacts` are internal, and named in
neither export list. The real export is the intersection of the two, so a caller
outside the module sees nothing and gets no error — the trap `AGENTS.md` records
under *Export in one list only*, found this time in a plan rather than in code.
Both subjects are reachable today only through `ctx doctor`, which reports them
as **checks**, with a verdict and a remedy: the right shape for a diagnostic,
and not the list a screen would render.

**And `-Json` exists on `ctx doctor` alone.** Every other read returns
PowerShell objects — machine-readable inside PowerShell, and nowhere else.

That couples the two decisions below, which were written as though they were
independent:

| If the dashboard is… | it reads by | so it needs |
|---|---|---|
| a local web UI hosted **by** PowerShell (`ctx dashboard`) | calling the functions in-process | the two missing exports, and no `-Json` at all |
| Tauri, or anything not PowerShell | running `pwsh` and parsing stdout | `-Json` on every read above, and the two exports |

The shape is therefore not a packaging preference: it decides how much public
API this module owes, and a published module owes every exported name
indefinitely. Choosing the shape before adding `-Json` to four commands is the
difference between an API with a caller and an API with a hope — which is the
same argument this file already makes for not porting to a platform nobody can
try.

What does hold, and is the reason the rest is small: a "repair this shortcut"
button is one call to a function the test suite already covers, never a second
implementation of the same rules living in a UI. That is why the decisions were
kept pure and separate from the gathering.

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

**Shape, decided 22 August 2026: it ships inside the module.** Not Tauri — and
not because Tauri is bad, but because a binary is what 2.1 needs and 2.0 does
not. `Install-Module DevContext` has to be the whole installation for every
read-only screen. This file already records that adoption died at the first extra
step, which is why `ctx init` exists; a second artefact to download, per platform
and signed, is a taller cliff than the one that was just removed.

The second reason is a security property rather than a convenience. This module
ships as **readable PowerShell**: anyone can read what the tool holding their
credentials actually does, before running it — which is what `SECURITY.md` is
for. A compiled binary replaces *read the source* with *trust the signature*. For
2.1 that trade is worth making, because a tray icon cannot ship any other way.
For 2.0 it buys nothing.

**First slice shipped, 22 August 2026 — `ctx dashboard`.** A generated report,
opened in the browser: no listening socket, no per-platform binary, and not one
new exported name beyond the command itself. Every read-only screen is there, and
a test asserts its verdicts are identical to the diagnostic's, so a second
implementation cannot appear quietly.

What it deliberately does **not** do, said before what it does: no second click
that runs a command, no refresh, no tray. A first step announced as a destination
is how a roadmap starts lying.

A local web UI served by the same command stays the next step if the second click
proves to be wanted; what that costs — down to the `Host` header validation a
loopback socket needs against DNS rebinding — is laid out in
[`docs/plans/2026-08-22-forme-du-tableau-de-bord.md`](docs/plans/2026-08-22-forme-du-tableau-de-bord.md).

**Reach: Windows, decided 22 August 2026 — and it was a real choice, not an
omission.** *Usable by everyone* was the requirement; measuring what stands in
its way settled where the work goes. The module is nailed to Windows: 36 registry
accesses, 81 `.cmd` entry points, `.lnk` shortcuts and 30 Windows environment
paths, against **six** platform guards in total. So reach is limited by the
**port**, not by the interface — a window on macOS would sit over a module that
cannot run there, which is the promise-without-verification this file refuses
under *Deferred*.

Windows first therefore costs nothing in reach that a cross-platform shell would
have bought, and it keeps the port a decision rather than a side effect. It is
revisited the day there is a machine to verify the port on — the same condition
*Deferred* already names, unchanged.

---

## 2.1 — the watchman

One job: say that something is wrong, when nobody is looking.

It exists because the failures this module catches are precisely the ones nobody
was watching for. A foreign account slept in the global `gh` config until a check
was written for it on 19 August 2026. A secret-scanning alert — a false positive,
though nobody knew that until someone looked — stayed open for seven days. A
`PATH` entry pinned to a version number would have disarmed the production guard
without a single message.

What it may report, and the list is closed on purpose:

| | why it is machine-wide |
|---|---|
| a token approaching expiry | the machine has one answer, whatever folder is open |
| a broken shortcut | `Get-CtxRaccourciChecks` already decides this |
| a credential outside the partition | `ctx doctor` already decides this |
| an alert on a watched repository | the forge answers; the module does not decide |

What it may **not** report: which context is *active*. That is the requirement
rejected under 2.0, and it stays rejected here.

It reads the CLI like everything else, stores nothing, and never acts on its own
— clicking a notification opens the dashboard or copies a command. Windows first,
because that is where the module runs. Signed, because an unsigned binary asking
about credentials is the shape of the thing it exists to warn about.

Not scheduled, and after 2.0: a watchman for a dashboard nobody opened is a
notification nobody asked for.

---

## Explicitly out of scope

- **Anything requiring an account with us.** There is no us.
- **Storing secrets anywhere but the OS vault.**
- **Being a Claude tool, a Cursor tool, or any vendor's tool.** MCP is an open
  standard and this module treats it as one.
- **An embedded shell in the dashboard.** Reasoning under 2.0.
- **A tray icon naming a "current context".** There is none at machine level, and
  displaying one would teach the opposite of what the tool does. Reasoning under
  2.0.

---

## Known gaps, carried

- **An upstream release can move a guarantee out from under a flag.** Found on
  19 August 2026, and the reason this line is at the top of the list. VS Code
  1.133 moved application storage — extension secrets, recently-opened folders,
  trusted folders — out of `--user-data-dir` and into a machine-wide
  `~/.vscode-shared`. Nothing was renamed, nothing was announced in a place this
  project reads, and the only visible symptom was a sign-in prompt on every
  launch. `--shared-data-dir` closes it, and `ctx doctor` now measures the
  outcome on disk.

  What stays open is the class, not the case: **this project has no way to learn
  that an editor changed what a flag covers.** It found out because the author
  was annoyed enough to ask. A capability read once and cached will keep
  answering with the layout of the version it was read from. Candidates, none
  chosen yet: re-read the surface when the editor's build id changes rather than
  only its timestamp; assert on a known-good machine that each isolated folder
  actually receives writes; or accept the limit and say so here, which is what
  this entry does today.

- **The shared store written before that fix is not cleaned up.** Separating what
  happens from now on was the safe half. `~/.vscode-shared` still holds the
  entries written when it was the only store — including recently-opened paths
  that mix a client context with personal ones. Deleting it signs the editor's
  **default** profile out, so nothing here does it automatically; there is no
  command for it either, and adding one means deciding what to do about a
  default profile the module does not own.

- ~~**The two test jobs are hand-copied, not shared.**~~ **Closed, 18 August
  2026.** The matrix lives once, in `.github/workflows/suite.yml`, called by both
  workflows. Only the two differences that were *deliberate* survive as inputs:
  `fail-fast` and the timeout. Everything else that differed was an accident of
  copying, and an accident does not deserve a parameter. The setup moved the same
  day into `.github/actions/prepare-powershell`, which reads the required modules
  **from the manifest** — so the publishing job can no longer be one short of
  what `Test-ModuleManifest` will resolve.
- ~~**The artifact actions are two majors behind.**~~ **Closed, 18 August 2026.**
  `upload-artifact@v7` and `download-artifact@v8`. The majors are offset on
  purpose and it reads like a typo, so it was checked rather than inferred:
  download-artifact's own README pairs `@v8` with `upload-artifact@v7` in its
  examples.
- ~~**The publishing job's first steps are never rehearsed.**~~ **Closed, 19
  August 2026**, shipped in 1.9.5. A `repetition` job does everything `publier`
  does except publish, and runs where `publier` cannot: off a tag, with no
  approval, with no key. Both go through
  `.github/actions/take-audited-package`, so the rehearsal cannot drift from
  what it rehearses — a test fails if a copy of those steps reappears in the
  workflow, and it was watched failing with the copy put back. It runs on any
  pull request touching the release machinery, so nobody has to remember to
  launch it. It proves two things nothing proved before: `Publish-PSResource` is
  present in that environment, and the Gallery key is **unreachable** from a job
  that names no environment — the claim this workflow's own header makes, and
  which nothing had ever checked.
- **WSL is not covered.** Its own `PATH`, its own filesystem view. `ctx doctor`
  reports it rather than closing it. This is the one gap that sits on the
  *author's own* machine — a distribution is used daily for Docker — and it is
  **separable from the port below**: what closes it is putting the POSIX shims on
  a distribution's `PATH`, which needs neither a Linux release nor a macOS one.
- **An absolute path bypasses the guard.** Inherent to a `PATH` shim.
- Full list with reasoning: `SECURITY.md`.
