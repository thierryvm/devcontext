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
