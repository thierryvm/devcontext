# Journal des versions

Format inspiré de [Keep a Changelog](https://keepachangelog.com/fr/1.1.0/).
Ce module suit le [versionnement sémantique](https://semver.org/lang/fr/).

`ModuleVersion` dans `DevContext.psd1` se met à jour **à la main**, et doit
toujours correspondre au dernier tag git.

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
  Les projets **personnels** cités en exemple (`demo-app`, `savoora`, …) sont
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
