---
title: "I committed under the wrong identity one time too many"
published: false
tags: powershell, windows, devtools, security
canonical_url:
---

# I committed under the wrong identity one time too many

Every tool a developer uses assumes one account per machine.

`gh auth login` replaces the previous account. `vercel login` replaces the
previous session. `npm login` writes one token to one file. Your AI assistant's
integrations are attached to whichever account you last authorised — for the
whole machine, not for the project you happen to have open.

That assumption is fine if you have one life. It stops being fine the moment you
have personal projects on one side and client work on the other.

## The three failures that actually happen

They are not dramatic. That is the problem — none of them announce themselves.

**You commit under the wrong email.** Your `user.email` was set globally, months
ago, and you have not thought about it since. It is correct for four of your five
repositories.

**Your pull request opens from the wrong account.** `gh` keeps one global
configuration and remembers the last login. `gh pr create` is not going to ask
whether that is the account this repository expects.

**Your migration lands on the wrong database.** This one cost me an afternoon.
I had three git worktrees of the same project — `main`, a landing page, a
redesign branch — and all three were linked to the same Supabase project. The
production one. The redesign branch was three migrations behind.

`supabase db push` from that folder would have rolled production backwards. The
folder gave no sign. My own tooling said everything was fine, because it was
answering a different question: *who are you?* It had never been built to answer
*what are you about to touch?*

## Being careful is not a mechanism

The usual advice is to pay attention. Check the remote before pushing. Verify
the account before deploying.

I did pay attention. I still nearly did it, because attention is a resource that
runs out at 6pm on a Friday, and because the failure mode is invisible until
after it has happened.

What I wanted instead was a property: **the folder decides.**

Stand in a folder, and the identity, the credentials and the tools that apply
there are the ones you get. Stand in the wrong one and something tells you
*before* anything leaves your machine.

## Where the guard has to live

My first attempt was a PowerShell function that wrapped `supabase`. It worked.
It also protected almost nothing, and it took me a while to see why.

A PowerShell alias exists inside a PowerShell session that imported your module.
It does nothing for:

- git-bash, which is where half my muscle memory lives
- an `npm run` script
- `execFileSync` from a Node build step
- an AI agent's shell — and agents run a *lot* of commands

Which is to say: it covered the callers least likely to make the mistake, and
none of the ones most likely to.

The only handover point every caller passes through is `PATH`. So the guard
moved there: a folder of shims, first in the user `PATH`, with three entry
points — a `.cmd` for cmd and PowerShell, an extensionless sibling for POSIX
shells, and the shared logic they both call. That is the npm convention, and it
exists because no single file satisfies every shell.

## The bug that taught me the actual lesson

The guard shipped. The tests were green. Then I tried it from git-bash for real:

```bash
$ cd ~/projects/my-app
$ supabase db reset --linked
```

It went straight through.

It failed — on a network timeout. Not on anything I had built. If the network
had been healthy, I would have rebuilt production from a stale branch while
holding a tool I had written specifically to prevent that.

The cause was one line, at the top of the guard:

```powershell
if (-not $env:DEVCTX) { Invoke-Real }
```

The guard stepped aside whenever the session variable was missing. And the
session variable is *always* missing in git-bash, in an npm script, in an
agent's shell. I had rebuilt the exact limitation I moved to `PATH` to escape,
one layer down.

The fix was small and the lesson was not:

> **Decide from the folder, never from the session.**

A session variable can be forgotten, lost across a process boundary, or simply
absent. A folder is a fact you cannot forget to set, because you are standing in
it.

## What a guard must not do

Two decisions I would defend to anyone.

**It fails open.** Missing module, unreadable index, unexpected error — the
command passes through unchanged. That sounds like a weak guard. It is the only
kind that survives: a tool that blocks whenever it hesitates gets uninstalled
within the week, and an uninstalled guard protects nothing at all. It refuses
only the cases it is certain about.

**It never tests destruction for real.** The test suite runs `db reset` against
a *decoy binary* that announces itself, and asserts the decoy was never called.
Testing a guard against the real CLI means betting a database on the guard
working — which is the thing under test.

## Then a second question appeared

Once the folder decided *who I was*, the obvious next question was what else it
should decide.

`supabase` resolved to version 2.84.2 under PowerShell and 2.109.1 under bash.
Two installations, same command name, different behaviour depending on which
shell I happened to open. I had never noticed.

My AI assistant's integrations were configured machine-wide, so every project
inherited whichever account I had connected last — which meant reconnecting them
by hand every time I switched between personal and client work.

And I had four editor profiles, so signing into GitHub in one meant nothing in
the next.

Three symptoms. One cause: nothing told me, in a given folder, which tools were
usable and where they would actually land. I found out by failing.

So the tool grew a diagnostic — one command that answers, for the folder you are
in: which binaries are installed and whether there are several, which account
each one will actually reach, whether the tokens are still valid, and whether
any of them is sitting in clear text in a config file.

The most useful check turned out to be the one I nearly did not write. Asking
*is this token valid* is easy and almost worthless. The failure that costs you
an afternoon is **a perfectly valid token on the wrong account** — and a naive
check blesses it.

## The part that generalises

Two things I would take to any tool of this shape.

**Put the judgement in a pure function.** Every non-trivial decision here takes
facts as parameters and returns a verdict — no filesystem, no network, no
registry. The plumbing that gathers those facts is thin and boring. That split
is what let me test 250-odd cases exhaustively without needing a machine that
happens to be misconfigured. And when a test needed an elaborate fake world just
to reach a decision, that was the signal the decision was in the wrong place.

**A test that stays green on broken code is worse than no test.** I have two
recorded cases. One test declined to *set* an environment variable to simulate
its absence — but the child process inherited it from the parent, so the test
never built the condition it claimed to. Another cleared a real variable in its
`finally` instead of restoring it, silently disarming a security check that ran
later. Green suite, vanished coverage, both times.

Now, whenever a test matters, I break the code on purpose and watch it go red
before I keep it.

## Try it

It is a PowerShell module for Windows, MIT licensed:
**[github.com/thierryvm/devcontext](https://github.com/thierryvm/devcontext)**

It is deliberately not tied to any AI vendor. MCP is an open standard, and being
locked to one vendor's account is the problem the tool removes — so being locked
to one vendor's *tool* would be the same mistake wearing a different hat.

What it does *not* protect is written down at the same length as what it does.
A limitation you know about is manageable. One you have been allowed to assume
away is not.
