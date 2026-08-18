## [Unreleased]

### Fixed

- **`ctx doctor` kept accusing an editor profile that had already been cleaned,
  and nothing the user did could clear it.** The check looks for a foreign
  context's GitHub login in that profile's `state.vscdb`. It read the whole
  file — and SQLite does not rewrite what it frees: `secure_delete` is off by
  default, so a deleted key stays written byte for byte until its space is
  reused. The check was reading the present and the past at once, with no way
  to tell them apart.

  Measured on 18 August 2026: a profile whose Accounts menu listed only its own
  account was still reported as carrying a foreign identity. A verdict no action
  can clear is the cry-wolf failure this project names elsewhere — worse here,
  because it invites reconnecting and disconnecting again to "retry".

  The reader now keeps only the **live** regions: freelist pages are skipped,
  so is the unallocated gap before each page's cell content area, and so is the
  freeblock chain inside it. On an unrecognised format it degrades to reading
  the file whole — *too talkative*, never blind, because a false positive is
  visible and a false negative is not.

  Verified on the machine that produced the defect: the cleaned profile stopped
  being reported, and the profile that genuinely still carries the other
  account is still reported. A fix that silenced both would not be a fix, it
  would be an off switch.

---

## [1.9.1] - 18 August 2026

### Changed

- **The test suite and the environment setup now exist once each, and are
  called.** `ci.yml` and `release.yml` carried hand-written copies of both, and
  on 18 August 2026 that cost three release attempts: the release copy of the
  test job was missing the step installing the Supabase CLI — so one delegation
  test went red and two went green for the wrong reason — and the publishing job
  was missing the two vault modules the manifest requires, which only surfaced
  *after* a human had approved the release.

  The matrix lives in `.github/workflows/suite.yml`, called by both workflows,
  with `fail-fast` and the timeout as its only inputs: the two differences that
  were deliberate. Preparation lives in `.github/actions/prepare-powershell`,
  which reads the required modules **from the manifest** instead of from a list
  kept beside it, so adding an entry to `RequiredModules` installs it everywhere
  with nothing left to remember. The action ends on `Test-ModuleManifest`, so
  each environment *proves* it can resolve the manifest rather than assuming it.

  Nothing changes for anyone installing the module. It is recorded because the
  failure it removes was invisible: a copy never announces that it has drifted.

- `actions/upload-artifact` to v7 and `actions/download-artifact` to v8, off the
  deprecated Node 20. The majors are offset on purpose, which reads like a typo
  and was therefore checked in the actions' own documentation rather than
  inferred from v4 having paired with v4.

### Fixed

- **Every single-argument call through the `gh`, `supabase` and `vercel`
  aliases was broken, in shipped 1.9.0.** `vercel whoami` reached the CLI as
  `w h o a m i`; `gh --version` as `- - v e r s i o n`. Anything with two or
  more arguments worked, which is why it went unnoticed — and why every test in
  `Alias.Tests.ps1` passed: not one of them built the one-argument case, the
  most ordinary form there is.

  `Get-CtxArgumentsBruts` ends on `@(...)`, but a PowerShell function **unrolls
  its output**: a one-element array reaches the caller as a bare string, and
  `& $exe @arguments` then splats a string, which enumerates its characters.
  The same mechanism as the empty-array trap this repository already records,
  one notch along — and worse, because the empty case at least throws.

  Fixed by wrapping at the three **call sites**, which is the rule `AGENTS.md`
  already stated. A test now reads the source and fails on a bare assignment,
  so the symptom and its cause are both held.

  **The shims were never affected.** They are reached as external programs, so
  a shell that had not imported the module always behaved correctly.

- **The release rehearsal was unusable, and had been since the first real
  publication.** `workflow_dispatch` with `dry_run` exists so `release.yml` can
  be tried without spending a version number. The check *this version is not on
  the Gallery yet* threw on every run — including runs that cannot publish
  anything — so from the moment 1.9.0 shipped, the manifest named a version the
  Gallery already served and every rehearsal died there. The facility built to
  make a release safe to try was the one thing never tried after a release
  succeeded.

  The assertion is now scoped to the runs where its consequence exists: on a tag
  that will publish it still refuses, exactly as before. Nothing is loosened
  where it matters — what changes is that a run which publishes nothing can no
  longer fail on a duplicate it could never have created.


---

## [1.9.0] - 18 August 2026

### Added

- **`ctx guard` — the trusted-folder list, shown before it is changed.**
  `ctx doctor` reports the problem; this corrects it.

  **It was designed to do something else, and checking saved it.** The first
  design wrote `deny` rules against other contexts' roots. Before a line was
  written, the upstream tracker said those rules **never match on Windows**: the
  write tool absolutizes the path before the check, and an absolute Windows path
  matches no documented pattern form —
  [#67849](https://github.com/anthropics/claude-code/issues/67849),
  [#34741](https://github.com/anthropics/claude-code/issues/34741),
  [#22907](https://github.com/anthropics/claude-code/issues/22907), and
  [#36884](https://github.com/anthropics/claude-code/issues/36884) for the VS
  Code extension.

  A file of inert rules is worse than no file: it has the appearance of
  protection. The same defect this repository already names for a silently
  dropped flag — *isolation you do not have*.

  So the command adds nothing. The mechanism that **works** is the positive one
  — the working-directory boundary — and what breaks it is the trusted list
  growing at user scope. `ctx guard` therefore removes from user scope every
  folder that belongs to a context, and **only** those: a folder belonging to no
  context is a judgement call, so it is listed for the operator rather than
  decided for them.

  **Preview by default.** This file decides what every agent may do; a command
  that edits it without showing first asks for trust it has not yet earned.
  `-Apply` writes, after a backup — *no backup, no write*, the rule already in
  `Fix.ps1` — and the write is refused outright if the transformation touched a
  single key beyond the folders it named. `-WhatIf` works, and `Ecrit` reports
  what happened rather than what was asked.

- **`ctx doctor` now reads where an agent is allowed to write.** Everything else
  in this module partitions *who you are* — git identity, tokens, sessions.
  Nothing looked at *where it writes*, and an agent running in a client folder
  has the same filesystem rights as any process.

  Agents already carry a boundary: the working directory, widened by a list of
  trusted folders. The defect is not a missing mechanism — it is that the list
  is written at **user scope**, one one-off approval at a time, and nobody ever
  rereads it.

  Measured on the author's machine on 17 Aug 2026: **14 folders trusted
  globally**, including another context's root, the desktop, a notes vault, and
  a session folder created for one day's need. All of them active in *every*
  session, including one opened in a client folder. Zero deny rules.

  That is precisely the failure this module exists to catch — *the folder
  decides, never the session* — except here a session's decisions had become
  permanent global state.

  A trusted folder belonging to **another context** is a `PROBLEME`, the same
  verdict and the same family as the foreign-identity check from 1.6.0: a client
  folder whose session can write into another client's tree is a confidentiality
  question, not untidiness. Folders outside every context, trusted globally, are
  an `ATTENTION`. A folder trusted at **project** scope is never reported —
  that is the practice being recommended, and flagging it would teach the
  opposite of what the fix says.

  Both messages state the consequence rather than only the fact, and both fixes
  state the rule rather than only the gesture. A finding that says *this is
  wrong* without saying what it costs teaches nothing, and gets skimmed.

  The owner of each folder is resolved through `Resolve-DevContextForPath` — the
  same function that arms `ctx`. Reusing it is not a saving of lines: it carries
  the prefix trap (`Apps` must not match `Apps-Autre`) this repository has
  already paid for three times.

  **It reports; it does not confine.** A permission rule is honoured by the
  agent, never enforced by the kernel. Real write confinement needs a filesystem
  filter driver or a container. `SECURITY.md` says so in the table of what is
  deliberately not protected, at the same length as the rest.

- **Publishing from a tag, behind a manual approval.** Pushing `vX.Y.Z` now runs
  a release workflow, and the shape of that workflow is the point.

  It is split in two. The first half has **no access to the API key** and does
  everything a machine can prove: the suite in both languages, the tag against
  the manifest, the version against what the Gallery already serves, and the
  assembled package against what a package may contain. The second half is gated
  behind an approval environment and does one thing.

  Asking a human to approve *before* anything has been checked is asking them to
  rubber-stamp. By the time the request arrives, the only question left is the
  one a person should answer: whether this version should exist. The key is an
  environment secret, so before that approval it is not merely unused — a job
  that does not name the environment cannot read it.

  The publish job takes the **artifact the first half audited**, not one it
  assembles itself. Publishing bytes nobody looked at, because bytes that looked
  the same were approved, is how an audit becomes decorative.

  `workflow_dispatch` rehearses the whole file without spending a version
  number, and a run that is not on a tag **cannot** publish whatever its input
  says — there is no version to compare the manifest against, so there is
  nothing to publish.

- **`tools/Assert-Release.ps1`.** The checks live in a script rather than in the
  workflow, and that is the whole reason the file exists. A rule written in YAML
  can only be tried by running the workflow — which, for a publishing workflow,
  means trying it by publishing. Written here, the deciding half is pure and the
  suite exercises it on cases that must never reach a real release. 41 tests.

  The check that matters is the tag against the manifest. The version is bumped
  **by hand**, in a dedicated commit; tagging without bumping is silent
  otherwise, because the Gallery would answer *this version already exists* — an
  error naming the conflict and never the forgotten edit.

### Fixed

- **The publishing job could not read its own manifest.** `Publish-PSResource`
  calls `Test-ModuleManifest`, which *resolves* every `RequiredModules` entry
  against the modules available. The manifest declares two — SecretManagement and
  SecretStore, the vault the tokens live in — and the publish job installed only
  PSResourceGet:

  ```
  The specified RequiredModules entry 'Microsoft.PowerShell.SecretManagement'
  in the module manifest '...\DevContext.psd1' is invalid.
  ```

  So the audit declared the package publishable in an environment that carried
  them, and the publisher failed in one that did not. Reproduced away from CI by
  removing those modules from `PSModulePath` — the same message, word for word.

  The modules are installed there now, and a step ahead of the publish asserts
  that **this** environment resolves the manifest. The audit job proves the
  package; it runs somewhere else, so it can prove nothing about the machine that
  publishes. Asking the question before touching the key turns a failed
  publication into a failed check.

  Third occurrence in one day of the same defect: a job written by hand with one
  precondition fewer than its neighbours. `ROADMAP.md` carries the cure; this is
  the dressing.

- **The release suite was not the CI suite.** The first real run of the publish
  workflow went red on a test that had been green in CI minutes earlier, on the
  same commit. `release.yml`'s test job was written by copying `ci.yml`'s, and
  the copy had lost one step: the one installing the Supabase CLI. So the job
  standing between a tag and an irreversible publish was running a suite nobody
  had ever run.

  Worse than the red: **two neighbouring tests were green for the wrong reason.**
  All three invoke the real CLI, and none declared it as a precondition — unlike
  their twins in `Executable.Tests.ps1`, which have declared it since day one. A
  missing binary also returns non-zero, and its error text also lacks the word
  `REFUSE`, so two assertions kept passing while measuring nothing at all.

  The step is restored, and the three tests now state what they need: they skip
  and say why on a machine without the CLI, and still bite on CI, which installs
  it. Verified both ways — 24 passed with the CLI on `PATH`, 3 skipped and 0
  failed with it removed.

  The copy itself is the real defect and it is **not** fixed here: two hand-kept
  twins will drift again. `ROADMAP.md` carries it as a known gap, to be closed by
  a `workflow_call` both jobs invoke rather than smuggled into a release.

- **`ctx doctor` threw on a machine with no agent settings at all.** The most
  ordinary input there is, and the one case no test built. `Get-CtxAgentConfianceFacts`
  ends with `@($faits)`, which does **not** make it return an empty array: an
  empty array unrolls crossing a function's output stream, so the caller gets
  `$null`, and the `$Faits.Count` on the other side throws under StrictMode.

  Green on every developer machine — they always carry a settings file
  somewhere — and red on the first CI runner, which carries none. Eight tests
  failed there and none here, which is the whole lesson: a test whose result
  depends on the machine running it proves nothing anywhere else.

  Fixed at the call site (`@(Get-CtxAgentConfianceFacts …)`), and the two pure
  functions now accept `[AllowNull()]` rather than dying on the emptiest input
  they will ever see. The `Get-DevContextDoctor` tests point `CLAUDE_CONFIG_DIR`
  at an empty folder, so the virgin case is now built on every machine. Removing
  the fix turns exactly those eight red again.

- **`ctx` read a GitHub outage as a stolen identity.** On 17 Aug 2026, with
  GitHub's API in Major Outage, `ctx` returned **NO-GO** on a healthy client
  folder:

  ```
  NO-GO
    - Compte GitHub actif '{"message": "No server is currently available
      to service your request..."}' - le contexte attend 'ovb-willemot'.
  ```

  `gh api user --jq .login` wrote the API's error body to its **standard
  output**, the exit code was never read, and that sentence was compared to the
  expected account as though it were an identity.

  The same question was already asked correctly twenty lines away. `ctx doctor
  -Live` has tested `$LASTEXITCODE` since the day it was written, under a stated
  doctrine: *an unreachable network is INFO and says nothing about the token; a
  401 is a PROBLEM; conflating them makes the tool cry wolf, and a tool that
  cries wolf gets uninstalled.* Two implementations of one question, and the
  wrong one was in the command people type twenty times a day.

  `Resolve-CtxGhLoginObserve` now answers what was **observed**, in three states
  rather than two: the account is known, there is provably no credential where
  `gh` looks, or it could not be read. Only the first is compared, so an outage
  can no longer produce a false NO-GO — and only the second says "not
  authenticated", because that one is a **local** fact, still true while the
  network is down. The doubt leans to *not verified*: telling someone perfectly
  authenticated to run `gh auth login` sends them to repair what is not broken,
  with a command the outage would fail anyway.

  The account's **shape** is checked even on exit code zero. The guarantee must
  not rest on a third-party binary's exit-code discipline, and a GitHub login
  contains no brace, quote, space or newline.

  A `GO` whose account was never measured no longer claims that "identity,
  folder and account agree" — it says which axis went unverified, two lines
  under the `gh :` line that already says so. Nine tests, replaying the outage
  string verbatim; reintroducing the bug turns three of them red — verified,
  not assumed.

- **`Write-Host` does not keep stdout clean across `pwsh -File`.** Measured on
  17 Aug 2026: `$d = pwsh -NoProfile -File .\tools\Build-Package.ps1` returned
  **three lines**, not a path. The separation Write-Host provides is real inside
  one process and absent across a process boundary, where the child's
  information stream lands on the parent's stdout. The example in that script's
  own documentation had been wrong since it was written.

  Progress now goes to **stderr**, which stays separate across the boundary, and
  a test asserts stdout carries exactly one line. Reintroducing the bug turns it
  red — verified, not assumed. It matters twice over in `Assert-Release.ps1`,
  where the returned value is a version, and a version contaminated by progress
  lines is what would then be published.

- **The secret patterns had become two lists.** The CI history scan kept its own
  copy. Both now read `Get-CtxMotifsSecrets`, and a test asserts the workflow
  sources it. Two scanners with different inputs and different allowlists is
  fine; two copies of the patterns is the *derive one list, hand-copy its twin*
  trap this repository already paid for on the `ctx-*` aliases.

- `INSTALLATION.md` had a French section in an otherwise English document, added
  with `ctx init` in 1.8.0. A document bilingual by accident is harder to read
  than two documents.

## [1.8.0] - 17 August 2026

### Added

- **`ctx init` — the first command, and where adoption is won or lost.** Until
  now a new user had to clone the repository, create a symlink, run an
  installer, then create a context by hand from a command line with five
  parameters. Every one of those steps is a place to stop.

  It reports what is already in place — including what is fine, because the
  second most likely moment to run it is *something is off and I do not
  remember what I did* — then walks the missing pieces in order.

  **It is a guide, not a wizard that takes over.** Every step it does not
  perform is printed as the exact command that performs it, so someone who
  prefers to drive by hand loses nothing by running it first. Installing the
  vault modules is never done for you: a new dependency is not a decision to
  take in someone else's name.

  It does not create the context either. The command is printed **pre-filled**
  from `git config --global` and `gh auth status`, and you run it. Creating a
  context lays an SSH key and a folder; doing that on a guess is the kind of
  help one does without.

  **And it refuses to ask a question it cannot hear the answer to.** With
  redirected input — an agent, a CI job, a pipe — a prompt does not pause: it
  reads EOF and takes a default nobody chose. This module already paid that
  lesson when `ctx-new` hung on a passphrase prompt, which is why `-NoKey`
  exists. So interactivity is **detected**, and the non-interactive path is a
  full citizen rather than a degraded mode: the same ordered list of commands,
  in a form a script can act on.

  The proposed context name is sanitised to what `New-DevContext` actually
  accepts — proposing a name it will then reject is the worst kind of help,
  because the user believes they followed the instruction.

### Fixed

- **Half the `ctx-*` aliases were created but never exported.** They were built
  from the subcommand table since 1.5.0, but *exported* from a hand-copied list
  — and the defect landed on the very first subcommand added: `ctx-init`
  existed inside the module, was absent for the caller, while `ctx init`
  worked. Two spellings, one of them dead: exactly what the shared table was
  meant to make impossible. The export list is now derived from the same table,
  and a test asserts every subcommand alias actually leaves the module.

  The manifest test that should have caught it was reading `$exportedAliases`
  out of the psm1 **as text**. It now reads the loaded module's real
  `ExportedAliases` — which is the only thing that answers the question it was
  asking.

## [1.7.0] - 17 August 2026

### Added

- **`ctx doctor -Fix` applies the correction each finding already spells out.**
  The diagnostic knew the answer all along; making the human retype it was
  friction at the moment they are least willing to read carefully.

  It repairs only what it can **prove and undo** — empty `PATH` entries and
  exact duplicates, shims missing from `PATH`, a stale junction. The list is
  short on purpose: **a fixer that overreaches is uninstalled the first time it
  does something its owner did not expect, and it takes the useful two thirds
  with it.**

  Everything else is **named, with the reason**, and that half matters as much
  as the repairs — an unexplained silence reads as *nothing more to do*, which
  is precisely the false reassurance this module exists to remove. Four
  families stay manual, for four different reasons:

  | Finding | Why it stays manual |
  |---|---|
  | `gh/compte`, `supabase/compte`, `vercel/session` | the fix is `work <ctx>`, which sets variables in the **calling** shell — and a child process cannot write into its parent's environment. An OS property, not a missing feature. |
  | `garde-fou/priorite` | writes to `HKLM`, so it needs elevation. A tool that silently asks for administrator rights is a tool people stop trusting. |
  | a duplicated CLI | installing or uninstalling a binary is never a diagnostic's job. |
  | `garde-fou/WSL` | nothing on the Windows side can close it. |

  `-WhatIf` and `-Confirm` work, and land on the **precise gesture** — *remove 2
  entries from the user PATH*, not *repair things*. The `PATH` repair writes a
  backup before touching the registry, preserves the registry **value kind**
  (writing `REG_SZ` over a `REG_EXPAND_SZ` disables every variable in the PATH,
  silently and for good), and is idempotent. It is proved against a **scratch
  registry key**, never the real PATH: a suite that modifies the machine running
  it is a suite nobody dares run.

  `-Fix` with `-Json` is **refused** rather than one of them silently ignored:
  `-Json` is for a program, `-Fix` talks to a human, and silence would let the
  caller believe it worked.

  Dispatch keys on `Domaine/Sujet`, which are **literals** throughout — never a
  translated lookup — so the table behaves identically under `fr` and `en`.

## [1.6.0] - 17 August 2026

### Added

- **`ctx doctor` now catches an identity from one context living in another
  context's editor profile.** Measured on the author's machine the day it was
  written: the **client** profile carried the personal GitHub account, and the
  personal profile carried the client's.

  Both profiles were perfectly isolated. That is the point — **isolation stops
  sessions from overwriting each other; it does not stop anyone from signing
  into the wrong account inside the right profile.** A window opened on a client
  project where Copilot, the Pull Request extension and GitLens act as a
  personal identity is an incident that only shows up afterwards, and this is
  precisely the class of error the module exists to prevent.

  Nothing reported it. Now one finding per affected context names the foreign
  account and the context it belongs to.

  The fix text names the *alternative*, not just the problem: signing out breaks
  Settings Sync, and nobody applies a repair that takes something away. VS Code
  accepts a **Microsoft** account for Sync, which frees the GitHub account to be
  one per context again.

  **How it reads the profile, and why not otherwise.** VS Code keeps sessions in
  `state.vscdb`, a SQLite database. PowerShell has no SQLite driver and this
  module has no dependencies, so key names are matched as text — by **exact
  search over a closed set**: the logins the manifests already declare. That is
  deliberately the opposite of extraction. Extraction was tried the same day and
  thrown away on measurement: SQLite pages glue binary bytes onto strings, and
  it returned `thierryvmn4`, `authenticationL`, `thie`. Values are never read;
  they are encrypted, and a diagnostic has no business there.

  The match is bounded on the right, because a substring search answers *yes* to
  `github-thier` when the text holds `github-thierryvm` — the third time this
  repository has met the prefix trap, after `Apps` matching `Apps-Autre`. **A
  guard that cries wolf is a guard people switch off.**

### Fixed

- **The report's order was not stable.** `Hashtable.Keys` enumerates in no
  guaranteed order, so two runs could emit the same findings in a different
  sequence. Caught on the first run by the test that compares `fr` output to
  `en` output — it was not looking for this, but any difference between the two
  passes turns it red, and an unstable order is one.

## [1.5.0] - 17 August 2026

### Added

- **`ctx doctor` works, and so does every other subcommand written with a
  space.** The module shipped twelve commands spelled `ctx-doctor`, `ctx-list`,
  `ctx-new`. That hyphen is a PowerShell habit; git, docker, gh, npm and cargo
  all use a space, so a space is what fingers type. Until now that answered:

  ```
  Test-DevContext: A positional parameter cannot be found that accepts argument 'doctor'.
  ```

  The sentence names `Test-DevContext` — an internal function the reader has
  never typed and will not find in any document. **A first contact that names
  your internals teaches the reader the tool is not for them.**

  Both spellings now exist and, more importantly, cannot diverge: the twelve
  hyphenated aliases are *derived* from the same table the dispatcher reads, so
  adding a subcommand means touching one place. A test asserts the two forms
  resolve to the same function, and that the help screen lists every entry
  rather than a hand-copied list that would go stale on the first addition.

  `ctx` alone is still the verdict, and `ctx -Quiet` still returns a boolean —
  the dash is tested *before* the table, or the module's most-used command would
  have printed a help screen instead of answering.

- **`ctx help`, and a useful answer to a typo.** `ctx doctr` names the word it
  did not recognise and lists what it accepts, instead of failing on parameter
  binding.

- **The report now states what an isolated profile means for sign-ins.** It said
  `profile and extensions per context — OK`, which reads as *everything is set*,
  while VS Code kept asking to sign in to GitHub in that window. Both were true:
  a profile per context **is** a secret store per context, so the sign-in has to
  be done once in each. The half that was missing is now printed.

  The real state is deliberately not measured. VS Code encrypts sessions into a
  SQLite `state.vscdb`, where the string `github-authentication` appears in both
  a signed-in profile and one that never was — 10 occurrences against 11, so the
  marker distinguishes nothing. Reading it properly would mean a SQLite
  dependency, in a module that has none, loaded on every `ctx doctor` for one
  informational line. **A diagnostic that is wrong half the time is worse than
  an absent one: it teaches people to stop reading it.**

### Changed

- **The shadowed-shim fix now names the cheap repair when it applies.** The
  advice was *reinstall that tool at user scope (winget install --scope user)*.
  Measured on 17 August 2026, `gh` did not need reinstalling at all: its
  directory was **already** in the user PATH behind the shims, and appeared a
  second time in the system PATH. Removing that redundant system entry is
  enough — nothing reinstalled, nothing uninstalled, undone by pasting a line
  back.

  The diagnostic now distinguishes the two cases instead of prescribing the
  expensive one to everyone, and the general message no longer assumes winget:
  scoop, npm and .msi installers all offer a user scope. **A fix that costs more
  than it needs to is a fix people do not apply.**

## [1.4.0] - 16 August 2026

### Added

- **`gh` runs under the folder's account, from any shell.** `gh` reads its
  identity from `GH_CONFIG_DIR`; without it, it falls back to the machine-wide
  config — whichever account was logged in last. `work` sets the variable, but
  `work` is a PowerShell command, so from git-bash, an npm script or an agent's
  shell it never was. **This is the failure the whole tool was built around**,
  and until now it was handled by a rule people had to remember: *never run `gh`
  from bash*.

  The roadmap said *refuse a PR when `GH_CONFIG_DIR` does not match*. Half of
  that was the wrong instinct. Refusing is right for Supabase because nobody can
  guess which database was meant; here **the folder holds the right answer**, so
  the entry point supplies the directory itself — on the child process only,
  never on the caller's session. Refusing is what is left when there is nothing
  to supply.

  | State | What happens |
  |---|---|
  | unset, context has a `gh` account | supplied, silently |
  | unset, command is `gh auth ...` | supplied, and said out loud |
  | unset, no account yet, a **write** | refused, naming the two lines that fix it |
  | set and matching | nothing |
  | set on another context | writes refused, reads flagged on stderr |

  A deliberately set `GH_CONFIG_DIR` is never overwritten — a tool that silently
  reverses an explicit choice is worse than no help. Reads are never refused
  either: a blocked user reaches for the raw binary, which has no guard at all.

  Writing commands are recognised by **verb** — `create`, `delete`, `merge`,
  `edit`, split on hyphens so `project item-add` counts — which is what makes a
  noun GitHub adds tomorrow covered without a change here. `gh api` is judged on
  its method, and on whether a field is present, because the CLI itself switches
  to POST when one is.

- **`vercel` joins the guarded set.** A `--prod` deployment from a branch other
  than the default is refused, as is `env rm` naming `production`. `rollback`,
  `promote` and `rm` are deliberately left alone — refusing a repair gesture
  always lands during an incident, from a hotfix branch. `vercel build --prod`
  builds locally and is not a deployment.

  Session isolation moved to the same footing: the config directory is resolved
  from the **folder** rather than from `$env:DEVCTX_VERCEL_CONFIG`, and injected
  only towards a directory that actually holds a session — or when the command
  is `login`/`logout`/`switch`, whose subject *is* that directory. Pointing at
  an empty config would answer "not logged in" where `vercel` worked, which is a
  regression, not a protection.

- **`gh` is also a module alias, and that is not symmetry.** Measured on the
  author's machine while verifying this release:

  ```
  gh     -> C:\Program Files\GitHub CLI\gh.exe   (system PATH, index 10)
  shims  -> ...\DevContext\current\shims         (user PATH,   index 19)
  ```

  Windows composes `PATH` as **system first, user second**, and the installer
  writes to the user half on purpose — that is what lets it require no
  administrator rights. A binary installed machine-wide is therefore resolved
  **before** our shims, and `gh` from winget or the MSI is exactly that. The
  guard was installed, announced active, and never reached.

  `supabase` escaped this by accident: it comes from npm, so from the user PATH.
  An accident is not an architecture. The alias makes the guard effective under
  PowerShell whatever the PATH order; from bash it cannot, and that limit is
  written down rather than papered over. `ctx doctor` now names the directory
  that wins and the two ways out.

### Changed

- **The three CLI wrappers no longer swallow short options.** `[CmdletBinding()]`
  turns a function into an advanced one, and an advanced function claims
  PowerShell's common parameters — so any short option that prefixes one became
  ambiguous before reaching the CLI:

  ```
  gh api -i user
  -> parameter name 'i' is ambiguous: -InformationAction, -InformationVariable
  ```

  `shims/supabase.ps1` has documented this trap since day one — *"no `param()`
  block on purpose"* — but the lesson had only been drawn for **scripts**. The
  module's own functions carried it, and it surfaced when the `gh` alias made
  the module's own diagnostic go through its own wrapper. Fixed on all three at
  once, with a test on the AST: repairing a class of defect only where you met
  it leaves it alive in its twin. `-c -d -e -i -o -p -v -w` were all affected.

- **The module's internal `gh` calls bypass the wrapper.** `ctx` and
  `ctx doctor -Live` ask `gh` which account is active. Routed through the alias,
  that question would be answered *after* the wrapper corrected
  `GH_CONFIG_DIR` — reporting the right account on a machine where git-bash
  still goes out with the wrong one. A diagnostic observes the state; it must
  never repair it on the way.

- **`ctx doctor` reports every disarmed guard, not the first one.** There is now
  one waiver variable per tool — deliberately, so that waiving one never waives
  the others — and the check knew only `DEVCTX_ALLOW_PROD`. Someone with
  `DEVCTX_ALLOW_GH=1` in their `$PROFILE` would have been told the guard was
  "active in every shell", which is precisely the lie that file exists to
  prevent.

- **`installer-shims.ps1 -Verifier` shows the resolution of all three CLIs.** A
  shim can sit in front for one tool and behind for another — npm reinstalling
  `vercel` elsewhere in `PATH`, for instance — and a report showing only
  `supabase` read as an answer for all of them.

- **The line-ending tests cover all three POSIX entry points.** Wrong endings
  break nothing under Windows; they break only under bash, which is exactly the
  population the entry points exist for. A regression there would have stayed
  invisible until the day it mattered.

## [1.3.5] - 16 August 2026

### Fixed

- **The production guard did not cover PowerShell — the one shell it was used
  from every day.** `supabase` resolves to the module's **alias** before it
  resolves the `PATH` shim:

  ```
  Get-Command supabase -All
  Alias        supabase       DevContext      <-- wins
  Application  supabase.cmd   ...\shims\
  ```

  The alias leads to `Invoke-DevSupabase`, which never called
  `Test-CtxSupabaseGuard`. Measured against a decoy binary on 16 August 2026:
  `supabase db reset --linked`, on a project marked `prod`, from a linked folder,
  on a side branch — the binary ran, exit code 42, no refusal. And `work` imports
  the module, so this was the state of **every** terminal.

  The suite did not catch it because every end-to-end test invoked the shim *by
  path*. It exercised the file, never the command the user actually types. Both
  callers are now tested on the same fake world, and a test pins the alias
  precedence that caused it — so the day the alias goes away, that test explains
  why it mattered.

  Gathering and decision moved into the module (`Resolve-CtxSupabaseVerdict`,
  `Write-CtxGardeRefus`); the shim applies the rule instead of holding it. Same
  shape as the format-file incident of 13 August 2026: two mechanisms for one
  job, the weaker winning in silence.

- **`--workdir` judged the branch of the wrong repository.** The guard resolved
  the target *database* from `--workdir` — the 15 August 2026 fix — but kept
  reading the *branch* from the folder the command was typed in. Standing in a
  repository on its default branch, `supabase --workdir <prod-project> db push`
  passed while that project sat on a side branch. `Get-CtxBranchesPour` now reads
  both branches in the targeted folder. Same class again: deciding on the wrong
  subject.

## [1.3.4] - 16 August 2026

### Fixed

- **`ctx doctor` accused its own guard of being stale.** On a development
  machine the junction points at the repository while the module loads through
  the modules symlink — two strings, one folder — and the check reported
  `PROBLEME: the guard runs stale logic` on a guard running exactly the right
  code. That is the worst possible false alarm: a diagnostic that accuses the
  mechanism it watches teaches its reader to ignore it, and that reader will
  miss the real failure. `Test-CtxJonctionSaine` now compares the **physical**
  folders through `Resolve-CtxCheminReel`, injected as a resolver so the
  decision stays verifiable without links on disk.

- **`ctx doctor` could report a correctly isolated shortcut as `PROBLEME`.**
  `Test-CtxShortcutIsolated` and `Test-CtxShortcutLaunchesEditor` recognised our
  shims directory by a single name. Since `PATH` names the junction, a shortcut
  may spell that folder differently. Both now take the full list.

  Third and fourth sites of the same defect, after `Get-CtxSupabaseExe` (1.3.1)
  and `Find-CtxEditorCli` (1.3.2). The lesson is written into the repository
  rather than only fixed: repairing a class of defect is not repairing the
  occurrence you met.

### Changed

- **Help examples no longer name the author's drive.** `lancer-vscode.ps1`,
  `lancer-editeur.ps1` and `ctx-shortcut` showed `F:\PROJECTS\...` in the text
  `Get-Help` prints to a stranger. Comments citing a real incident keep the real
  path — naming the machine where a bug happened is what makes the comment
  checkable — but user-facing help does not.

- **The README contradicted itself about languages.** One section documented
  `DEVCTX_LANG` as working; another announced bilingual output as *planned*. It
  has shipped since 1.3.0. The test count was also two years behind reality —
  250+ claimed, 479 actual.

- **`docs/ARCHITECTURE.md` listed half the layout.** Two of the five root scripts
  and none of `lang/`, `tools/` or the newer `src/` files. It now describes the
  three zones and, more usefully, the rule that decides which one a file belongs
  to: **who invokes it.** `src/` is dot-sourced, `shims/` is reached through
  `PATH`, and the root holds what is named by absolute path from outside
  PowerShell — a registry value, a `.lnk`, a human. That last zone is why moving
  or renaming those five is a breaking change with no deprecation path.

## [1.3.3] - 16 August 2026

### Changed

- **`supabase` resolution says what it excluded, instead of claiming an
  absence.** Recognising a shims folder by its contents fails *closed* — it
  raises, it never runs the wrong thing, which is the only acceptable direction
  for a module guarding a production database. The message, however, lied about
  its cause: a directory that happens to carry `editor.ps1` and `supabase.ps1`
  produced "supabase not found" while the binary sat right there.

  A user blocked by a false message does not file a report; they call the raw
  binary to get moving — **without the guard**. So the error now names the
  excluded directory, states the rule that excluded it, and says explicitly not
  to bypass the wrapper. The "nothing in `PATH` at all" case keeps its original
  message: two different failures, two different answers.

## [1.3.2] - 16 August 2026

The same defect as yesterday, in the one place it had not been repaired.

### Fixed

- **Every desktop shortcut left a terminal window open for the whole editing
  session.** `Find-CtxEditorCli` skipped our own shims by comparing against ONE
  path — the module's. Since `PATH` names the junction, that folder answers to
  another name, the two strings differ, and the shim was no longer recognised as
  ours. It became "the VS Code CLI": `Find-CtxEditorExecutable` walked up from
  `...\current\shims` finding no `Code.exe`, and `Open-DevCode` fell through to
  its **synchronous** fallback. The editor still opened, correctly isolated, so
  the only visible symptom was a window that would not close.

  This is exactly the defect fixed in `Get-CtxSupabaseExe` the day before, and
  never carried over here — because this function, whose entire purpose is not
  to mistake itself for the editor, **had no test at all**. It has three now.

- **Shim identity no longer rests on a name.** `Test-CtxDossierEstShimDevContext`
  recognises a shims folder by its **contents** when its name says nothing: a
  directory carrying `editor.ps1` and `supabase.ps1` is ours, whatever path led
  there. A development machine gives that one folder three names — the
  repository, the modules symlink, the `PATH` junction — and a hand-written
  `PATH` entry, a `subst` drive or a UNC path would give a fourth that no list
  can anticipate. The markers are load-bearing on purpose: they are what the
  shims execute, so they cannot be removed without removing the feature, and a
  test asserts they exist in `shims/`. `Get-CtxSupabaseExe` uses the same
  identity, so both callers now agree on what "ours" means.

- **The synchronous fallback says so.** It was silent, and it fired wrongly on
  every machine: a shortcut window stayed open for an entire session with
  nothing explaining why, while the cause sat two levels up. It now warns, names
  the launcher it could not resolve, and states the consequence.

## [1.3.1] - 15 August 2026

The release that repairs what publishing revealed. Nothing here was visible
before 1.3.0 reached the Gallery, and that is the whole point of it.

### Fixed

- **The guard would have silently stopped guarding on the first update.** The
  installer put the module's own `shims` folder in `PATH`. On the author's
  machine the module is a symlink to a repository, so that path never moves.
  Installed from the Gallery, the module lives under
  `...\Modules\DevContext\1.3.0\` — **the version number is in the path**.
  Installing 1.4.0 creates a sibling folder; `PATH` keeps pointing at 1.3.0, so
  the guard runs stale logic, and then disappears entirely the day the old
  version is removed. Without a message.

  That is precisely the failure this tool exists to prevent, and no machine
  could have shown it before publication — the same shape as the five dead ends
  a virgin machine walked into, and as code deciding on translated text: what
  breaks is what the author is not positioned to see.

  `PATH` now receives `%LOCALAPPDATA%\DevContext\current\shims`, where `current`
  is a **junction** to the installed module. A junction and not a copy: the shims
  resolve the module by relative path (`..\DevContext.psd1`), and that path stays
  valid THROUGH a junction. Copying would break the resolution, the shim would
  fall into its `catch`, and it would delegate — silently, always. A junction and
  not a symlink: symlinks need administrator rights or developer mode on Windows,
  and an installer that demands elevation for a per-user tool does not get
  installed. Existing installs are migrated: the old entry is removed as the new
  one is added.

- **A shim could have called itself forever.** `Get-CtxSupabaseExe` skipped our
  own directory by comparing against ONE path. Once `PATH` names a junction the
  same folder answers to two names, the comparison failed, and the shim resolved
  to itself. Fixed by excluding the whole set — and, in the shims themselves, by
  a depth counter rather than a path comparison, because paths lie readily:
  junctions, casing, 8.3 names, `subst` drives, UNC.

  The counter **breaks the loop, it never skips the check**. A first version
  delegated to the real binary on the second entry, which handed a complete
  bypass to anyone setting `DEVCTX_SHIM_DEPTH=1` before their command. An
  environment variable that disarms a protection must be deliberate and
  documented (`DEVCTX_ALLOW_PROD`), never a side effect of an internal mechanism.

### Added

- **`ctx doctor` reports a stale junction** — one pointing at a version other
  than the loaded module, or missing while `PATH` still names it. Nothing can
  repair itself here; the installer has to be run again after a module update.
  What the diagnostic can do is stop the failure from being silent, which is the
  doctrine of that whole file.
- **`src/Chemins.ps1`**, sourced by both the module and the installer. The path
  rules exist once: two copies of one rule is the 12 Aug 2026 incident, where a
  fix landed on the copy that was not the one being executed.

---

## [1.3.0] - 15 August 2026

The release where the tool stopped speaking only its author's language.

The documentation was English and the output French. A developer in Berlin read
a README they understood, then received refusals and diagnostics in a language
they may not speak. That is the most visible inconsistency a tool can have, and
the one that gets it uninstalled on first run.

### Added

- **`DEVCTX_LANG`**, then the system culture, then English. Nothing to
  configure to be understood; one variable to override for a shell, a test, or a
  screenshot. `fr-BE` resolves as `fr`, because a system culture almost
  always carries a region and demanding the short code would recognise nobody.
- **268 keys, two tables**, in `lang/fr.psd1` and `lang/en.psd1`, loaded
  through `Import-PowerShellDataFile` -- a data file must not be able to
  execute code, even one we ship.
- **`ctx-root`**, `ctx-new`, `ctx-end`, `ctx-mcp`, `ctx-shortcut`,
  `ctx-editors`, `ctx doctor`, `work`, the production guard refusal, the
  installers and the launchers all speak both.
- **`tools/Build-Package.ps1`**, which assembles the exact folder that gets
  published, from `git ls-files` rather than from a directory walk. The source is
  what git TRACKS, not what the folder CONTAINS, so build artifacts and ignored
  files are excluded by construction rather than by a list somebody has to
  remember. It refuses to run on a modified tree: a package must correspond to a
  commit, or the published version is reproducible nowhere.

### Changed

- **A missing key renders as `[ctx.noGo]`**, never as an empty string. An
  empty message reads as a command that said nothing; a visible key reads as a
  defect, and a test finds it.
- **Substitution goes through `{0}`, `{1}` and `-f`**, never through
  concatenation, so a translation can REORDER what it inserts. German puts its
  verb last; a sentence assembled from fragments survives neither that nor the
  next language.
- **Log entries are deliberately NOT translated.** A trace that changes language
  with the machine is a trace nobody can search: two users reporting the same
  incident would produce two different texts.
- **`Sujet` in `ctx doctor` stays an untranslated identifier.** It is the
  column an agent or a CI filters `-Json` on, and a key that changes with the
  operator's locale is no longer a key. `Detail` and `Correctif` address a
  human and are translated.

### Fixed

- **The package would have shipped `.git` in full**, caught by building a test
  package and reading it before publishing anything. 825 KB out of 1060 -- 78% of
  the package -- including `.git/config` with the author's push URL and SSH host
  alias, and `.git/filter-repo/commit-map`, the old-to-new commit table of a
  history rewrite. `Publish-PSResource` packs everything in the folder it is
  given and excludes nothing of its own.

  This is the one defect in the project that no later version could have
  repaired: a published version cannot be deleted, only unlisted, and an unlisted
  version stays downloadable by exact version number. `tests/Paquet.Tests.ps1`
  now asserts on the assembled folder itself, and covers the symmetric danger --
  EXCLUDING something the module needs, which would only ever show up on a
  machine that installed from the Gallery.

- **Code deciding on displayed text.** Three occurrences, each invisible in the
  language that wrote it.

  `ctx doctor` compared `\.Profil -eq 'isole'` against a field that had just
  become translated: in English EVERY editor was reported as not isolated. The
  shortcut audit filtered on `-eq 'ne lance pas un editeur'`, which in English
  would have flooded the report with hundreds of unrelated shortcuts.

  The fix is structural. `Get-DevEditorList` carries `Isole` and
  `ExtensionsIsolees` for the code, beside `Profil` and `Extensions` for
  the human. `Test-CtxDoctorRaccourci` returns nothing rather than a check
  recognisable by its wording -- absence does not translate.

### Tests

Five guards against the drift translation projects die of: both tables carry the
same keys, no string is empty, the `{n}` placeholders match across languages
(a `{1}` in one and not the other throws at runtime, for some users only),
everything stays ASCII, and every key called in code exists in both tables.

Three more against deciding on display text: the full diagnostic must return
identical verdicts in both languages, the boolean fields must exist, and no
source file may compare against any string present in the tables. That last one
found the occurrence a human review had missed -- and produced a false positive
first, reading the comment describing the bug as if it were the bug. It works on
tokens now, which cannot mistake an explanation for a comparison.

403 tests, zero analyser findings.

---
## [1.2.0] — 15 August 2026

The release where isolation stopped depending on launching things our way.

`Open-DevCode` had passed `--user-data-dir` since August 2026, so an editor
opened through it had its own sign-ins. Everything else did not: a shortcut made
by hand, `code .` in a terminal, "Open with" from the file explorer, an npm
script, an agent. All of them landed on the shared profile, where signing into
GitHub for a client project signs you out of your own — the reconnect-everything
ritual after every reboot.

### Added

- **Editor isolation in `PATH`.** An entry point per editor, ahead of the real
  one, injecting the context's profile directory. Covers every caller that
  resolves a command by name. Same position, and the same reasoning, as the
  production guard next door.
- **`ctx-editors`** — which editors are installed, and whether each can be
  isolated. Nothing is hardcoded: editors are found on the machine and their
  capabilities probed.
- **`ctx-shortcut`** — writes a shortcut that opens a project in its own
  context, through the launcher rather than through an absolute path to an
  executable.
- **Shortcut audit in `ctx doctor`.** A shortcut targeting `Code.exe` directly
  consults no `PATH`, so nothing can fix it from the outside. It is now read and
  reported instead: which ones open a context project on the shared profile, and
  which are already correct.
- **`DEVCTX_SHIM_TRACE=1`** — the shim says on stderr which context it picked
  and why. "My editor opened on the wrong account" had no answer otherwise, and
  two contexts can be indistinguishable from the outside.
- **`lancer-editeur.ps1`**, generalising `lancer-vscode.ps1` to every editor and
  deducing the context from the folder instead of carrying it as a parameter. A
  context written into a shortcut becomes wrong the day the project moves, and
  nobody rereads a shortcut.
- **`editors.json`** next to the contexts, to declare an editor DevContext does
  not know.

### Changed

- **`Open-DevCode` takes `-Editor`** and no longer writes its flags by hand:
  they come from a measured capability. Passing `--extensions-dir` to an editor
  that ignores it reads as isolation in a shortcut while the extensions stay
  shared.
- **The executable behind a launcher is found by walking up**, not by assuming a
  depth. VS Code puts `bin/code.cmd` two levels under `Code.exe`; Cursor puts
  `resources/app/bin/cursor.cmd` four levels under `Cursor.exe`. "Two levels up"
  is right for exactly one editor.
- **Real project names removed from the repository and its history.** They were
  never secrets, but a public repository naming somebody's production database
  hands out infrastructure intelligence for free. The lessons in those comments
  survive without the names.

### Fixed

- **`installer-shims.ps1 -Restaurer` threw on parameter binding** and left the
  generated entry points behind while removing the `PATH` entry. Found by a test
  written for the uninstall path, which is the path nobody exercises by hand.

### Removed

- **`GUIDE.html`**, the author's personal working guide, from the tree **and
  from the history**. A document describing one person's accounts, folder layout
  and procedures is noise for every reader except its author, and free
  reconnaissance for anyone else. It returns later as a documentation section of
  the dashboard -- as data that tool displays, never as a file this project
  ships. `docs/GUIDE.md` is the guide for people who USE DevContext, and that
  one belongs here.
- **A personal email address and user-profile paths** from the history. They had
  been cleared from the tree in this release; the history still carried them,
  which is the half people forget.

### Why discovery rather than a list

The first draft was a table: name, executable, flags. It was wrong within the
hour, on the machine that wrote it.

- Cursor ships `resources/app/codeBin/code.cmd`. A table keyed on the name
  `code` would have isolated Cursor's profile and called it VS Code.
- Antigravity accepts `--user-data-dir`, has no `--extensions-dir` and no
  `--list-extensions` at all. "It is a VS Code fork, therefore it takes the VS
  Code flags" produces a command line the editor silently ignores.

And a table is keyed on one machine. So the names shipped here are search
**hints**; what an editor supports is measured, and what cannot be measured is
reported as `declared` rather than rounded up to `measured`.

### Why the probe never launches a GUI

Established on 15 August 2026, at the user's expense. Probing Antigravity by
running its executable with CLI flags did not print a version — it opened the
editor, which relaunched itself after an update and threw `EPIPE: broken pipe`
in a loop, because the console that started it had gone.

A binary is now run only when the install layout proves a command-line entry
point exists. Otherwise the application's argument surface is read from disk and
labelled as such. A diagnostic that opens windows on someone's machine, or
leaves an application crashing behind it, is not a diagnostic.

---

## [1.1.0] — 15 August 2026

The release where the guard started covering the shells it was built for, and
where the module started answering *what can I do here* rather than only *who
am I*.

### Added

- **Production guard.** `supabase db reset` is refused against a project tagged
  `prod`; `db push`, `migration repair` and `migration up` are refused from any
  branch other than the repository's default. Everything else passes through.
- **`shims/` in `PATH`**, via a reversible `installer-shims.ps1`. A PowerShell
  alias covers PowerShell; only a `PATH` entry covers git-bash, npm scripts,
  `execFileSync` from Node, and an AI agent's shell.
- **`ctx doctor`** — for the current folder: which tools are installed, which
  account each will actually reach, which project it is aimed at, and where a
  credential sits in clear text. `-Json` for agents and CI.
- **`ctx doctor -Live`** — probes each loaded token against its service. The
  interesting verdict is not *is it valid* but *is it valid on the wrong
  account*, which a naive check would bless.
- **`ctx mcp`** — writes project-scoped MCP configuration for Claude Code,
  VS Code and Cursor, taking credentials from the environment. No secret in the
  file, so it can be committed. Read-only by default, and read-only without
  appeal on a production project.
- **`ctx-sb`** — which Supabase project lives on which account, and which
  folders point at each.
- **Environment tagging** in the Supabase index, inferred from project names and
  never overwriting a manual choice.
- **WSL is reported.** A distribution has its own `PATH` and filesystem view, so
  the Windows shim is not on it. The gap cannot be closed here; it can be made
  visible.
- `LICENSE` (MIT), `SECURITY.md`, `docs/ARCHITECTURE.md`, `AGENTS.md`,
  `tests/README.md`, CI on Windows, and agent definitions under `.claude/agents/`
  with their model pinned by alias.

### Fixed

- **The guard only protected the shells that were already protected.** It opened
  with `if (-not $env:DEVCTX) { Invoke-Real }`, so it stepped aside whenever the
  session variable was missing — which is always the case in git-bash, npm
  scripts and agent shells. Measured on 15 August 2026: `supabase db reset
  --linked` against a production project went through from git-bash, stopped
  only by a network timeout. `Resolve-DevContextForPath` now arms the guard from
  the **folder**.
- `Get-CtxProp` accepts a null object. It is documented as a defensive read, and
  refusing null contradicted that: a folder outside any context has no manifest,
  so `-Live` died on parameter binding rather than on the lookup it attempted.
- The Supabase index no longer crashes on entries written before the `env`
  fields existed.
- `shims/supabase.cmd` is CRLF, as `.gitattributes` has always declared. The
  file predated the declaration and had never been re-checked-out.

### Security

- **No credential is ever printed.** Diagnostics report the *name* of a key,
  never its value, and every surfaced message passes through
  `Protect-CtxMessage`, which redacts by issuer prefix and by the shape of a
  bearer header.
- **The user `PATH` is written through the registry**, preserving the value
  kind. `[Environment]::SetEnvironmentVariable` returns the *expanded* value;
  writing it back bakes `%USERPROFILE%` in as a literal path and downgrades
  `REG_EXPAND_SZ` to `REG_SZ`, permanently and silently.
- **`tests/Securite.Tests.ps1`** scans every tracked file for credential
  patterns and, when a context is loaded, runs the full diagnostic with the
  machine's real tokens then asserts that none appear in the output. CI scans
  the entire git history, since a secret removed later is still published.
- What is **not** guarded — WSL, absolute-path invocation, fail-open by design,
  `npx` fetching at run time — is set out in `SECURITY.md`.

### Known limitations

- Command output is French; documentation is English. A bilingual `DEVCTX_LANG`
  is planned for 1.2.0.
- `POURQUOI.md` and `INSTALLATION.md` are not yet translated.

---

## [1.0.0] — 13 août 2026

Première version nommée. Le module fonctionnait depuis le 5 août ; cette version
marque le jour où il a cessé d'exister en plusieurs exemplaires et où il est
devenu un dépôt.

### Ajouté

- Manifeste `DevContext.psd1`. `Get-Module DevContext` annonçait « 0.0 » — un
  module sans version est un module qu'on ne peut pas situer dans le temps.
- `INSTALLATION.md` : procédure d'installation par lien symbolique, et liste des
  **consommateurs externes** qui référencent ce dépôt par chemin absolu.

### Modifié

- `README.md` enseignait la copie du module ; il enseigne désormais le lien
  symbolique. La copie était la cause racine du bug du 12 août.

### Corrigé

- Le module vivait en deux exemplaires. Voir « 12 août » ci-dessous.

### Sécurité

- `GUIDE.html` documentait la mise en place d'un contexte à partir du **cas
  client réel** : nom du client, chemins, login GitHub du compte client et
  adresse du Gmail dédié à la mission. Un module d'isolation d'identités qui
  embarque les identités qu'il isole contredit sa propre raison d'être.
  Ces valeurs sont remplacées par des exemples génériques (`client-a`,
  `contact@exemple.com`, `login-client`), et l'historique git a été réécrit —
  le fichier était présent dès le premier commit.
  Les projets **personnels** cités en exemple (`demo-app`, `demo-api`, …) sont
  conservés : ce sont des dépôts publics, et un exemple concret se relit mieux
  qu'un `foo`.

---

## Avant le dépôt

Le dépôt GitHub a été créé le **12 août 2026 à 22:28**. Tout ce qui précède
n'existe que dans les horodatages de fichiers — d'où cette section, écrite pour
que le raisonnement survive à l'oubli.

### 5 août 2026 — origine

Rédaction de `POURQUOI.md`. Le module naît d'un constat simple : il n'existe pas
d'état neutre. Un état neutre, c'est l'identité du dernier qui a parlé.

### 8 août 2026 — premiers contextes

- Les deux premiers contextes créés — un perso, un client (~35 min, corrections
  comprises).
- `lancer-vscode.ps1` : un raccourci qui lance VS Code directement l'isole
  (`--user-data-dir`) mais ne pose **aucune** variable d'environnement — le
  terminal intégré repartirait alors sur le dernier compte `gh` de la machine.
  Le script rétablit l'ordre : `work` → `Set-Location` → `ctx` → VS Code, et
  n'ouvre rien si `ctx` rend NO-GO.
- `GUIDE.html` : guide complet destiné à Thierry. Rédigé à partir du cas client
  réel — anonymisé depuis, voir la section « Sécurité » de la version 1.0.0.

### 9 août 2026 — routeur d'URI `vscode://`

Windows n'accepte **qu'un seul** gestionnaire par protocole, et celui livré par
VS Code ne porte pas de `--user-data-dir`. Or une instance ne dialogue qu'avec
celles qui partagent son `user-data-dir` : au retour de GitHub, le callback
démarrait un VS Code sur le profil par défaut. Une fenêtre parasite s'ouvrait,
et la fenêtre qui attendait son jeton ne le recevait jamais.

`vscode-uri-router.ps1` choisit l'instance destinataire : 0 instance isolée →
profil par défaut, 1 → celle-là, 2 et plus → la fenêtre au premier plan (ordre
Z). Toute erreur retombe sur le comportement d'origine.

### 10 août 2026 — le verrou ACL

Le correctif de la veille n'a pas passé la nuit. Mesure décisive : la clé de
registre réécrite entre 11:50:06 et 11:50:36 au simple lancement d'une instance
jetable. **VS Code réenregistre le protocole à chaque démarrage d'instance**,
pas seulement à l'installation.

Poser une valeur ne pouvait donc pas tenir. `installer-uri-router.ps1` refuse
désormais à l'utilisateur courant les droits `SetValue` et `Delete` sur la clé :
VS Code tente, échoue en silence, le routeur reste. L'utilisateur restant
propriétaire, il conserve `ChangePermissions` — réversible, sans droits
administrateur.

### 12 août 2026 — le module vivait en deux exemplaires

Un dossier de référence sur le Bureau, et la copie réellement chargée depuis
`Documents\PowerShell\Modules\`. Une correction apportée à la référence n'a eu
**aucun effet, en silence** : ce n'était pas la copie exécutée. Il a fallu
comparer les deux fichiers pour le comprendre.

Corrigé en supprimant la classe entière du problème : un lien symbolique, donc
un seul fichier réel, donc plus rien à synchroniser.

### 13 août 2026 — le déménagement, et sa facture

Le module rejoint `F:\PROJECTS\Apps\devcontext` et `Desktop\02-OUTILS\DevContext`
disparaît. Le lien symbolique suit — **rien d'autre ne suit**. Les 10 raccourcis
VS Code et la clé de registre pointaient toujours sur le dossier supprimé :

- les raccourcis ouvraient un terminal qui se refermait en une seconde
  (`pwsh -File` sur un script inexistant ne laisse pas le temps de lire l'erreur) ;
- le routeur d'URI pointant dans le vide, la réauthentification GitHub
  permanente est revenue sur tous les projets.

`ctx` et `work` fonctionnaient pendant tout ce temps, ce qui rendait la panne
trompeuse. Le verrou ACL, lui, a parfaitement tenu — il protégeait fidèlement
une valeur devenue morte.

> **Un verrou garantit qu'une valeur ne change pas, pas qu'elle est juste.**

D'où la section « Ce qui pointe vers ce dépôt depuis l'extérieur » ajoutée à
`INSTALLATION.md`, à relire avant tout déplacement futur.

---

[1.0.0]: https://github.com/thierryvm/devcontext/releases/tag/v1.0.0
