# Changelog

Format based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).
This module follows [semantic versioning](https://semver.org/).

`ModuleVersion` in `DevContext.psd1` is updated **by hand**, and must always
match the latest git tag.

> Entries from 1.1.0 onward are written in English, as is the rest of the
> documentation. Earlier entries are left in French rather than retranslated:
> rewriting history to look tidier makes it less trustworthy.

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
