# DevContext

**Your identity, your credentials and your AI tooling follow the folder you are
standing in — not the account you last logged into.**

One context = one folder + one complete identity: git email, SSH key, GitHub
account, Vercel session, Supabase tokens, VS Code profile, MCP servers. Several
coexist at once. You never log out of anything.

```powershell
work perso                  # this terminal is now "perso"
cd F:\PROJECTS\Clients\acme # …and this folder belongs to a client
ctx                         # NO-GO — and it tells you why
```

---

## The problem

Every tool a developer uses assumes **one account per machine**.

`gh auth login` replaces the previous account. `vercel login` replaces the
previous session. Your AI assistant's MCP connections are attached to whichever
account you authorised last, machine-wide. So a developer working on personal
projects and client projects spends their day switching — and every switch is a
chance to commit under the wrong name, deploy to the wrong project, or point a
migration at the wrong database.

The usual advice is to be careful. That is not a mechanism.

DevContext replaces care with a property: **the folder decides**. Stand in a
folder, and the identity, the credentials and the tools that apply there are the
ones you get. Stand in the wrong one, and you are told before anything leaves
your machine.

## Why not just switch accounts?

Because switching is state, and state drifts. The three failures below are the
ones that actually happen, and none of them announce themselves:

- You commit under your personal email in a client repository, because
  `user.email` was set globally three months ago.
- `gh pr create` opens a pull request from the wrong account, because `gh`
  keeps one global config and remembers the last login.
- `supabase db push` applies migrations to production from a feature branch,
  because three git worktrees point at the same linked project and nothing
  distinguishes them.

DevContext turns each of those into a refusal instead of an incident.

---

## What makes it different

**It is not tied to any AI vendor.** MCP is an open standard. `ctx mcp` writes
project-scoped configuration for Claude Code, VS Code and Cursor alike, taking
credentials from the environment rather than from a vendor account. Change
assistant, change provider, bring your own key — the folder still decides. Being
locked to one vendor's account is the problem this tool removes; being locked to
one vendor's *tool* would be the same mistake wearing a different hat.

**The guard lives in `PATH`, not in a shell.** A PowerShell alias protects only
PowerShell. It does nothing for git-bash, an npm script, `execFileSync` from
Node, or an AI agent's shell — which are precisely the callers most likely to
make the mistake. DevContext's guard sits in `PATH`, so every caller passes
through it.

**It decides from the folder, never from the session.** No variable to remember
to set, no state to keep in your head. A fresh terminal with no context active
is still protected, because the answer is derived from where you are standing.

**It tells you what is wrong before you find out the hard way.** `ctx doctor`
answers, for the current folder: which tools are installed, which account each
one will actually reach, whether the tokens are still valid, and where a
credential is sitting in clear text in a config file.

---

## Install

Requires **Windows** and **PowerShell 7+**.

```powershell
Install-Module Microsoft.PowerShell.SecretManagement, Microsoft.PowerShell.SecretStore -Scope CurrentUser

git clone https://github.com/thierryvm/devcontext.git F:\PROJECTS\Apps\devcontext
New-Item -ItemType SymbolicLink `
    -Path   "$HOME\Documents\PowerShell\Modules\DevContext" `
    -Target 'F:\PROJECTS\Apps\devcontext'

# Puts the production guard in PATH, so it covers every shell.
pwsh -NoProfile -File F:\PROJECTS\Apps\devcontext\installer-shims.ps1
```

The module is **used from the repository, never copied**. A second copy is how a
fix ends up applied to the file nobody is running — see `INSTALLATION.md`, which
also documents the rollback for every machine-level change.

Full walkthrough: [`INSTALLATION.md`](INSTALLATION.md) ·
Reasoning: [`POURQUOI.md`](POURQUOI.md) ·
Internals: [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md)

---

## Commands

| Command | What it answers |
|---|---|
| `work <ctx>` | Load an identity into this terminal |
| `ctx` | Do the folder, the identity and the account agree? **GO / NO-GO** |
| `ctx-doctor` | What works in this folder, and on which account? |
| `ctx-doctor -Live` | Are the tokens still valid, and do they open the right account? |
| `ctx-sb` | Which Supabase project lives on which account, and which folders point at it |
| `ctx-mcp` | Write MCP configuration for this project, bound to its own credentials |
| `ctx-list` | Every context on this machine |
| `ctx-who` | Which context owns this folder |
| `code-ctx` | Open VS Code with this context's profile and environment |

`ctx-doctor -Json` emits machine-readable output, for CI or for an AI agent.

---

## Example — what a diagnosis looks like

```
Verdict   Domaine    Sujet          Constat
-------   -------    -----          -------
OK        contexte   proprietaire   perso
OK        git        identite       moi@exemple.be
ATTENTION supabase   binaire        2 installations de versions differentes : 2.84.2 | 2.109.1
                                      -> n'en garder qu'une — la version depend sinon du shell appelant
ATTENTION supabase   projet         ce dossier vise un projet de PRODUCTION
                                      -> db reset y est refuse, db push hors branche par defaut aussi
OK        garde-fou  portee         actif dans tous les shells
OK        gh         jeton          valide — moncompte (portees : gist, read:org, repo, workflow)
OK        supabase   jeton          valide — acces confirme a mon-projet-prod
```

> **Language.** Command output currently ships in French; documentation is in
> English. Making the output bilingual through `DEVCTX_LANG` is planned — see
> `CHANGELOG.md`.

---

## The production guard

Against a Supabase project tagged `prod`:

- `supabase db reset` — **refused**, unconditionally. There is no legitimate use
  for it against production, so the guard costs nothing and prevents everything.
- `supabase db push`, `migration repair`, `migration up` — **refused** from any
  branch other than the repository's default. This is the worktree case: three
  folders, one linked project, one of them holding fewer migrations than the
  others.
- Everything else passes through untouched.

Any uncertainty passes through. A guard that blocks whenever it hesitates gets
uninstalled within the week, and an uninstalled guard protects nothing.

To override for a single command — never in `$PROFILE`:

```powershell
$env:DEVCTX_ALLOW_PROD = 1
```

`ctx doctor` reports it as a finding whenever it is set.

---

## Security

Tokens live in a SecretManagement vault and reach tools through environment
variables. Nothing is written to disk in clear text, and no generated file
contains a credential — that is what makes `.mcp.json` safe to commit.

What is guarded, and equally importantly what is **not** — WSL, absolute-path
invocation, fail-open by design — is set out in
[`SECURITY.md`](SECURITY.md). Report a vulnerability privately through GitHub's
Security tab.

---

## Tests

```powershell
pwsh -NoProfile -File .\tests\RunTests.ps1
```

250+ tests across unit, contract, integration, cross-shell (PowerShell, cmd,
git-bash) and repository-security levels. Destructive commands are exercised
against a **decoy binary** that announces itself: a guard tested against the real
CLI would mean betting a database on the guard working.

What the suite does and does not guarantee: [`tests/README.md`](tests/README.md).

---

## License

MIT — see [`LICENSE`](LICENSE).
