# DevContext — isolation de contextes de travail

Un contexte = un dossier + un jeu de variables d'environnement.
Plus aucune déconnexion : chaque terminal, chaque VS Code, chaque fenêtre Chrome
porte une identité, et plusieurs identités coexistent en simultané.

Conçu pour le modèle « 1 Gmail dédié par client, transféré au client en fin de mission ».

**Le perso est un contexte comme les autres.** Il n'existe pas d'état neutre : un
état neutre, c'est l'identité du dernier qui a parlé — exactement ce que ce module
existe pour supprimer.

| | |
|---|---|
| **[INSTALLATION.md](INSTALLATION.md)** | poser le module sur une machine neuve, et ce que ce dépôt ne restaure pas |
| **[POURQUOI.md](POURQUOI.md)** | ce que ce module cherche à empêcher, et ce qui l'a fait naître |
| Ce fichier | l'usage quotidien |

---

## Installation

```powershell
# 1. Coffre de secrets (une seule fois)
Install-Module Microsoft.PowerShell.SecretManagement -Scope CurrentUser
Install-Module Microsoft.PowerShell.SecretStore      -Scope CurrentUser

# 2. LIER le dépôt — pas le copier. Terminal administrateur.
New-Item -ItemType SymbolicLink `
  -Path   "$HOME\Documents\PowerShell\Modules\DevContext" `
  -Target (Resolve-Path .)

# 3. Charger au démarrage
Add-Content $PROFILE "`nImport-Module DevContext"
```

> ⚠️ **Un lien, jamais une copie.** L'étape 2 disait autrefois `Copy-Item`. Le
> module se retrouvait alors en deux exemplaires : celui qu'on lit et modifie,
> et celui que PowerShell charge réellement. Le 12/08/2026, une correction
> apportée au premier n'a eu **aucun effet**, en silence — il a fallu comparer
> les deux fichiers pour le comprendre.
>
> Procédure complète, vérification et retour arrière : **[INSTALLATION.md](INSTALLATION.md)**.

Racine des contextes : `F:\CTX` par défaut, surchargeable via `$env:DEVCTX_ROOT`
(à poser dans `$PROFILE` **avant** l'`Import-Module`).

---

## Le contexte perso — à créer en premier

Sans lui, `ctx-off` n'a nulle part où aller : il retire `GH_CONFIG_DIR`, et `gh`
retombe sur la config **globale** de la machine, c'est-à-dire sur le dernier compte
connecté. C'était le seul trou du dispositif — les projets clients blindés, le
projet perso non. Et c'est le projet perso qui a failli partir sur le mauvais compte.

```powershell
ctx-new perso `
  -Label "Perso" `
  -Email "ton-gmail@gmail.com" `
  -Root "F:\PROJECTS\Apps" `
  -GithubLogin "ton-login-github"
```

Le nom `perso` est celui que `ctx-off` cherche ; surchargeable via `$env:DEVCTX_HOME`.

## Créer un contexte client

```powershell
ctx-new acme `
  -Label "ACME Corp" `
  -Email "projet.acme@gmail.com" `
  -Root "F:\PROJECTS\Clients\acme" `
  -GithubOrg "acme-corp" `
  -GithubLogin "compte-github-du-client" `
  -VercelScope "acme-team"
```

`-GithubLogin` n'est pas décoratif : c'est la valeur **attendue** que `ctx` compare
au compte réellement authentifié. Sans elle, `ctx` ne peut qu'afficher, jamais
vérifier.

Ce que ça fait :

| | |
|---|---|
| `F:\CTX\acme\gh\` | `GH_CONFIG_DIR` dédié — `gh auth login` une fois, jamais de `gh auth switch` |
| `F:\CTX\acme\vercel\` | dossier `.vercel` du contexte, injecté par le wrapper `vercel` |
| `F:\CTX\acme\vscode\` | `--user-data-dir` — sessions d'auth VS Code isolées (DPAPI) |
| `F:\CTX\acme\ssh\` | clé Ed25519 dédiée au compte client |
| `F:\CTX\acme\gitconfig` | identité git + réécriture d'URL, branché par `includeIf` |
| `~\.ssh\config` | alias `Host github-acme` |
| coffre `DevContext` | tokens sous `devctx/acme/<clé>`, jamais sur disque en clair |

Deux contextes ne peuvent pas partager la même racine : la résolution par chemin
deviendrait ambiguë, donc le garde-fou incertain, donc inutile. `ctx-new` refuse.

Puis, une seule fois : ajouter `F:\CTX\acme\ssh\id_ed25519.pub` au compte GitHub du
client, `gh auth login`, créer le profil Chrome dédié et renseigner `chromeProfile`
dans `context.json`.

---

## Au quotidien

```powershell
work acme        # active le contexte : env, secrets, cd, titre de fenêtre
ctx              # VERDICT : GO / NO-GO (dossier, compte GitHub, contexte actif)
ctx-check        # même chose, mais LÈVE — utilisable en tête de script ou en hook
ctx-who          # à quel contexte appartient le dossier courant ?
code-ctx         # VS Code isolé sur le contexte actif
web-ctx          # Chrome, profil dédié
ctx-off          # bascule vers le contexte perso
ctx-list         # tous les contextes
sb-index         # (re)construit l'index Supabase ref -> compte
```

Deux terminaux côte à côte, deux contextes différents, aucune interférence.
Idem pour VS Code : perso à gauche, client à droite, comptes GitHub et Copilot distincts.

### Garde-fou nº 1 — `ctx` juge, il ne se contente pas de rapporter

Trois questions, un verdict :

- le dossier courant appartient-il au contexte actif ?
- le compte GitHub réellement authentifié est-il celui que le manifeste attend ?
- un contexte est-il seulement actif, et `GH_CONFIG_DIR` posé ?

```
  Contexte actif : ACME (acme)
  Dossier        : F:\PROJECTS\Apps\demo-app
  ...
  NO-GO
    - Ce dossier appartient au contexte 'perso', mais 'acme' est actif.
```

C'est le seul scénario qui compte vraiment : se tenir dans le dossier d'un contexte
avec l'identité d'un autre. Un affichage qui ne juge pas ne l'attrape jamais.

`ctx-check` rend la même chose exploitable en script : il lève au lieu d'afficher.

### Garde-fou nº 2 — la réécriture d'URL

`ctx-new` écrit une réécriture d'URL dans le gitconfig du contexte :

```ini
[url "git@github-acme:"]
	insteadOf = git@github.com:
	insteadOf = https://github.com/
```

Depuis un dépôt situé sous la racine du contexte, toute URL `github.com` est
redirigée vers l'alias SSH correspondant — donc vers la bonne clé. Pousser avec
la mauvaise identité devient structurellement impossible, quelle que soit l'URL
que l'IA a écrite dans le remote.

Ce garde-fou vaut désormais **dans les deux sens** : le contexte perso a le sien,
donc un dépôt personnel ne peut pas partir sous une identité client, et
réciproquement.

*(Vérifié : `git remote get-url --push origin` renvoie bien `git@github-acme:...`
depuis le dossier client.)*

### Garde-fou nº 3 — le wrapper Supabase

`SUPABASE_ACCESS_TOKEN` ne porte qu'**un** compte, alors qu'un contexte peut en
posséder plusieurs — le perso en a deux. Le wrapper `supabase` résout le compte
par le **dossier**, comme `includeIf` le fait pour l'identité git :

1. il remonte l'arborescence jusqu'à `supabase/.temp/project-ref`, écrit par
   `supabase link` — donc maintenu par la CLI elle-même, pas par nous ;
2. il consulte `F:\CTX\<ctx>\supabase-index.json` (`ref` → clé de secret) ;
3. il charge ce jeton le temps de la commande, puis restaure l'état précédent.

Toute clé du coffre commençant par `supabase-token` est ramassée ; `sb-index`
reconstruit l'index en listant les projets de chacune. Aucune table à la main.

Hors contexte ou hors projet lié, le wrapper **ne décide rien** et laisse passer
ce que `work` a posé. Un wrapper qui devine est pire que pas de wrapper.

Il n'annonce la bascule que lorsque le compte utilisé n'est pas celui chargé par
`work` — signaler l'exception, pas la normale.

### Repère visuel oh-my-posh

`work` pose `$env:DEVCTX_LABEL`. À ajouter dans le thème :

```json
{
  "type": "text",
  "style": "plain",
  "foreground": "#ff5555",
  "template": "{{ if .Env.DEVCTX_LABEL }} {{ .Env.DEVCTX_LABEL }} {{ end }}"
}
```

---

## Fin de mission

```powershell
ctx-end acme            # affiche la checklist de transfert
ctx-off                 # obligatoire avant de purger : on ne purge pas sous soi
ctx-end acme -Purge     # + supprime secrets et dossier de contexte
```

La checklist couvre ce qui casse un transfert de comptes : 2FA encore liée à ton
téléphone, moyen de paiement personnel, email de récupération, tokens non révoqués.
**Supprimer un token du coffre ne le révoque pas côté fournisseur** — les URL de
révocation sont rappelées.

`-Purge` refuse de s'exécuter si le contexte visé est actif dans le terminal :
purger sous soi laisserait les secrets chargés en mémoire.

`-Purge` ne touche pas au dossier projet, seulement à l'identité sur ta machine.
Les blocs `~/.ssh/config` et `~/.gitconfig` sont à retirer à la main (volontaire :
suppression automatique dans ces fichiers = trop risqué).

---

## Ajouter un service

Une entrée dans `$script:SecretMap` en haut du module suffit :

```powershell
$script:SecretMap = [ordered]@{
    'github-token'   = 'GH_TOKEN'
    'vercel-token'   = 'VERCEL_TOKEN'
    'supabase-token' = 'SUPABASE_ACCESS_TOKEN'
    'supabase-db'    = 'SUPABASE_DB_PASSWORD'
    'stripe-key'     = 'STRIPE_SECRET_KEY'    # <-- exemple
}
```

`ctx-new` la demandera, `work` la chargera.

---

## Ce qui est vérifié, et ce qui ne l'est pas

**Exécuté sous PowerShell 7 :** parsing (2915 tokens, 0 erreur), import réel du
module et export des 11 fonctions et 11 alias, résolution de chemin vers le bon
contexte — y compris le piège du préfixe, où `F:\PROJECTS\Apps-Autre` ne doit pas
résoudre vers le contexte dont la racine est `F:\PROJECTS\Apps` — et les deux
scénarios de désaccord de `ctx` : dossier connu sans contexte actif, et dossier
d'un contexte avec l'identité d'un autre. Les deux rendent NO-GO.

**Corrigé au passage, trouvé par l'exécution :** `$home` est une variable
automatique en **lecture seule**. `ctx-off` l'écrasait, et aurait levé
« Cannot overwrite variable HOME » au tout premier appel. `$profile` et `$Args`
masquaient eux aussi des variables automatiques.

**Non vérifié :** SecretStore, `ssh-keygen`, DPAPI, résolution de `code` et
`chrome.exe`, et le wrapper `vercel` contre une vraie commande. À valider au
premier `ctx-new`.

L'option `--global-config` de la CLI Vercel, elle, est vérifiée : elle existe, et
c'est **le seul** moyen de choisir son dossier de config. Aucune variable
d'environnement ne le fait — d'où le wrapper.

## Portée

Isolation de **sessions**, pas frontière cryptographique : DPAPI est scopé à ton
compte Windows, les bases restent déchiffrables par le même utilisateur. Contre le
mélange de comptes : efficace. Contre un attaquant local : non — il faut des
comptes Windows séparés ou des VM.

Les jetons vivent en **variables d'environnement** : tout processus enfant du
terminal en hérite, y compris un agent IA. C'est ce qui le rend capable de
travailler, et c'est ce qui fait qu'il n'a jamais les secrets d'un autre contexte.
Propriété centrale du dispositif — à connaître avant de lancer un agent.
