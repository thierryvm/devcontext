# Garde-fou production — conception

> **Noms de projets remplacés par des marque-places.** Ce document décrit une
> investigation réelle ; les noms de projets, de dépôts et de bases y ont été
> remplacés par demo-app, other-app, 	hird-app. La méthode et les
> conclusions sont inchangées — seule la topologie réelle a été retirée, parce
> qu'un document qui explique où se trouve une base de production et comment son
> garde-fou fonctionne est un document de reconnaissance.

*13 août 2026*

Ce document décrit l'ajout d'un second garde-fou à DevContext. Il ne remplace
rien : le dispositif d'isolation d'identités reste inchangé.

---

## Le problème

DevContext juge **qui tu es** : le dossier courant appartient-il au contexte
actif, le compte GitHub authentifié est-il celui que le manifeste attend.

Il ne juge jamais **ce que tu vas toucher**.

Relevé le 13 août 2026 sur la machine de référence :

| Dossier | Nature | Branche | Migrations | Base visée |
|---|---|---|---|---|
| `demo-app` | dépôt principal | `docs/handoff-2026-08-11-2215` | 22 | `demo-app-prod` |
| `demo-app-landing` | worktree | `main` | 22 | `demo-app-prod` |
| `demo-app-redesign` | worktree | `feat/pwa-start-url-cockpit` | **19** | `demo-app-prod` |

Les trois sont le **même dépôt git** sur trois branches. Partager la même base
est donc cohérent — ce n'est pas l'anomalie.

L'anomalie est ailleurs : depuis `demo-app-redesign`, un `supabase db reset`
reconstruirait la production à partir de **19 migrations au lieu de 22**.
Données perdues, schéma ramené trois crans en arrière. `ctx` répondrait **GO**,
en toute bonne foi : le dossier est bien dans le contexte `perso`, l'identité
GitHub est la bonne. Rien de ce que le module surveille n'est en défaut.

Deux constats aggravants :

1. **Le signal existe déjà et n'est pas utilisé.** Le projet Supabase s'appelle
   `demo-app-prod`. Le mot est dans `supabase-index.json`, relu à chaque commande.
2. **L'information n'est lisible nulle part.** Aucune commande n'affiche quel
   projet vit sur quel compte. `sb-index` construit l'index ; rien ne le montre.

## Où le garde-fou doit vivre

`supabase` est un **alias PowerShell** (`DevContext.psm1`, ligne 1002). Un alias
n'existe que dans une session PowerShell ayant importé le module.

| Vecteur | Le wrapper actuel s'applique ? |
|---|---|
| `supabase` tapé dans pwsh | oui |
| outil Bash d'un agent (git-bash) | **non** |
| script npm (`npm run db:reset`) | **non** |
| `execFileSync('supabase', …)` depuis Node | **non** |
| terminal VS Code non-PowerShell | **non** |

Un contrôle placé dans l'alias protégerait l'humain qui tape à la main et
laisserait passer l'agent. C'est l'inverse de l'objectif.

`CLAUDE.md` couvre déjà ce trou par une règle — *« toute commande sortante passe
par PowerShell »*. Mais une règle de discipline n'est pas un garde-fou. C'est
exactement le raisonnement tenu le 5 août contre l'affichage qui ne juge pas.

---

## Architecture

Deux couches, deux questions, testables séparément.

```
  n'importe quel shell
        │
        ▼
  ┌───────────────────────────────┐
  │  COUCHE 1 — shim dans le PATH │   « ai-je le droit ? »
  │  supabase.cmd / supabase.ps1  │
  └───────────────┬───────────────┘
                  │ (autorisé)
                  ▼
  ┌───────────────────────────────┐
  │  COUCHE 2 — wrapper PS        │   « sous quelle identité ? »
  │  Invoke-DevSupabase (existant)│
  └───────────────┬───────────────┘
                  ▼
            binaire supabase réel
```

La couche 2 existe et **ne change pas de rôle**.

### Couche 1 — le shim

Un dossier de shims placé **avant** le binaire réel dans le PATH. Tout process
qui résout `supabase` par le PATH y passe : bash, npm, Node, agent, n'importe
quel shell.

Le shim ne fait qu'une chose : appliquer la décision. Dans tous les autres cas
il transmet au binaire réel — arguments inchangés, code de sortie propagé,
sortie standard et erreur non altérées.

**Repli par le passage, jamais par le blocage.** Shim en erreur, index illisible,
projet inconnu, hors contexte, dossier non lié : il transmet. Un garde-fou qui
casse quand il doute est un garde-fou qu'on retire au bout d'une semaine.

---

## La décision

Une fonction **pure** : entrées → verdict. Aucun accès réseau, aucun secret,
aucun appel à Supabase. C'est ce qui la rend testable.

```
Test-CtxSupabaseGuard
    -SousCommande   'db reset'
    -Environnement  'prod' | 'dev' | $null
    -BrancheCourante 'feat/pwa-start-url-cockpit'
    -BrancheDefaut   'main'
  →  @{ Autorise = $false; Raison = '…' }
```

### Règles

| Sous-commande | Projet `prod` | Projet autre / inconnu |
|---|---|---|
| `db reset` | **refus inconditionnel** | passage |
| `db push`, `migration repair`, `migration up` | refus **si** la branche courante n'est pas la branche par défaut du dépôt | passage |
| tout le reste (`db pull`, `db dump`, `gen types`, `functions serve`, `status`, `login`, …) | passage | passage |

**Pourquoi `db reset` est un refus inconditionnel :** cette commande détruit et
recrée la base. Elle n'a **aucun usage légitime en production**, dans aucun
scénario. La refuser ne coûte donc aucune friction — cas rare, et c'est ce qui
rend la règle tenable dans le temps.

« Inconditionnel » qualifie l'absence de condition de branche, par opposition à
`db push`. Le contournement explicite décrit plus bas reste possible.

**Pourquoi la branche pour `db push` :** `db push` *a* un usage légitime en
production. Le distinguer par le dossier serait arbitraire ici, puisque les trois
dossiers sont le même dépôt. Le critère juste est l'**état** : on ne pousse des
migrations en production que depuis la branche principale du dépôt.

Ce critère se calcule partout, sans configuration, et exprime une bonne pratique
universelle plutôt qu'une particularité de cette machine. Appliqué au relevé
ci-dessus : `demo-app-landing` (sur `main`) passe, `demo-app-redesign` et `demo-app`
sont refusés.

**Comment la branche par défaut est déterminée**, dans cet ordre :

1. `git symbolic-ref --short refs/remotes/origin/HEAD` — la référence que le
   dépôt distant déclare lui-même ;
2. à défaut, la première de `main` puis `master` qui existe localement ;
3. si aucune ne peut être établie : **passage**. On ne bloque pas sur une
   supposition.

Hors dépôt git : passage (on ne peut pas juger, on ne bloque pas).

### Forcer

Refus contournable par `DEVCTX_ALLOW_PROD=1` sur l'appel, jamais dans le profil.
Le message de refus le rappelle et nomme la base visée.

Choix assumé : une variable d'environnement se pose délibérément, alors qu'une
confirmation interactive se valide machinalement — et qu'un agent la valide
toujours.

---

## Le marquage « production »

Champ `env` ajouté à chaque entrée de `supabase-index.json` :

```json
{
  "<ref>": { "key": "supabase-token-2", "name": "demo-app-prod", "env": "prod" }
}
```

`sb-index` le **propose**, l'humain **dispose** :

- nom contenant `prod` / `production` → `prod`
- nom contenant `dev`, `staging`, `preview`, `test` → `dev`
- sinon → `null` (inconnu, donc passage)

L'heuristique seule serait fragile ; la déclaration manuelle seule ne serait
jamais remplie. La combinaison donne une valeur juste dès le premier `sb-index`,
corrigeable à la main, et jamais écrasée une fois posée explicitement.

Les entrées existantes sont enrichies sans être réécrites : l'index actuel
(4 entrées, aucun orphelin) reste valide.

---

## La lisibilité

Nouvelle commande `ctx-sb` :

```
  COMPTE            PROJET             ENV    DOSSIERS
  supabase-token    third-app   -      third-app
  supabase-token    other-app          -      other-app
  supabase-token    fourth-app         -      fourth-app
  supabase-token-2  demo-app-prod        PROD   demo-app, demo-app-landing, demo-app-redesign  ⚠
```

Elle croise l'index avec les fichiers `supabase/.temp/project-ref` trouvés sous
la racine du contexte, et signale tout projet visé par plus d'un dossier.

Cette commande n'est pas un confort. Le 13 août 2026, la question *« third-app
est sur quel compte ? »* n'a pu être tranchée qu'en lisant l'index à la main,
alors que la réponse était sur la machine depuis le début. Un garde-fou dont on
ne peut pas inspecter les données est un garde-fou qu'on finit par désactiver.

---

## Tests

Aucun test n'existe aujourd'hui sur 1 016 lignes et 11 commandes publiques.
La section « Ce qui est vérifié, et ce qui ne l'est pas » du `README.md` le
reconnaît déjà. Ce chantier apporte le premier harnais.

**Outil : Pester 6.1.0**, installé le 13 août 2026. Standard PowerShell,
multiplateforme.

Windows livre par ailleurs **Pester 3.4.0** dans `System32`, non désinstallable
et de syntaxe incompatible. Le harnais devra donc importer explicitement une
version minimale plutôt que se fier à la résolution par défaut :
`Import-Module Pester -MinimumVersion 5.0.0`.

| Couvert | Pourquoi |
|---|---|
| `Test-CtxSupabaseGuard` — matrice complète sous-commande × env × branche | le cœur de la décision, fonction pure, aucun effet de bord |
| Refus absolu de `db reset` sur `prod` | la règle qui justifie le chantier |
| Passage de toute commande hors liste noire | garantit l'absence de régression |
| Repli : index absent, projet inconnu, hors contexte, hors dépôt git | garantit que le doute ne bloque jamais |
| `Resolve-DevContextForPath` — dont le piège du préfixe (`…\Apps-Autre` ne doit pas résoudre vers le contexte de `…\Apps`) | vérifié à la main le 5 août, jamais rejoué depuis |
| `Resolve-CtxSupabaseKey` — ref → clé, sur index de test | déjà en production, jamais testé |
| Propagation du code de sortie par le shim | un shim qui avale un échec est pire que pas de shim |

Aucun test n'appelle Supabase, ne lit le coffre, ni ne touche au réseau. Les
index et arborescences sont montés en dossier temporaire et détruits ensuite.

---

## Ce qui ne change pas

- La logique d'`Invoke-DevSupabase` — résolution du jeton, `finally` de
  restauration, annonce du compte non par défaut.
- `ctx`, `work`, `ctx-off`, `ctx-new`, `ctx-end` : aucun changement.
- Les sessions PowerShell déjà ouvertes. Le module est chargé en mémoire à
  l'import : modifier le `.psm1` n'a aucun effet sur un terminal en cours.
  **Corollaire assumé** — le garde-fou ne s'appliquera à ces sessions qu'après
  un réimport ou l'ouverture d'un nouveau terminal.
- Aucune commande de lecture n'est concernée.

## Limites assumées

- **Un appel par chemin absolu contourne le shim** (`& 'C:\…\supabase.exe'`).
  Ce garde-fou vise l'erreur et l'automatisme, pas un adversaire déterminé —
  même portée que le reste du module, qui isole des sessions et ne prétend pas
  être une frontière cryptographique.
- **Supabase uniquement.** Vercel et GitHub relèvent du même principe mais ne
  sont pas traités ici : l'inventaire du 13 août montre 4 projets Vercel pour
  4 identifiants distincts, donc aucun recouvrement à protéger aujourd'hui.
- **Le compte de migrations n'est pas comparé entre branches.** Le critère
  retenu est la branche, pas le diff : calculable partout, sans configuration.

## Points touchant la machine — autorisés le 13 août 2026

Ces deux points requéraient un accord explicite (`CLAUDE.md` — « installation de
nouvelle dépendance requiert une validation explicite »). Accord donné le
13 août 2026.

1. **Ajouter un dossier de shims au PATH utilisateur.** Modification de
   `HKCU\Environment`, réversible, sans droits administrateur. Sans elle, la
   couche 1 n'existe pas et le garde-fou ne couvre que PowerShell.
2. **Installer Pester** — ✅ fait le 13 août 2026, version 6.1.0, portée
   `CurrentUser`. Dépendance de développement, jamais chargée à l'exécution du
   module.

## Portée pour d'autres développeurs

Rien dans cette conception ne dépend de la machine de référence : pas de chemin
en dur, pas de nom de projet, pas d'hypothèse sur le nombre de comptes.
L'heuristique de marquage repose sur des conventions de nommage courantes, et
reste corrigeable à la main.

Le shim est le seul élément spécifique à Windows (`.cmd`). L'équivalent POSIX
est un script exécutable de même nom, sans autre changement — à traiter lors du
portage, qui fait l'objet d'un chantier distinct.
