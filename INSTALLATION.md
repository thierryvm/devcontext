# Installer DevContext sur une machine neuve

Ce dépôt est la **source unique** du module. Il n'existe pas de seconde copie —
c'est délibéré, et c'est le point le plus important de ce document.

---

## Pourquoi un lien symbolique, et pas une copie

Le module a longtemps vécu en **deux exemplaires** : un dossier de référence sur
le Bureau, et la copie que PowerShell chargeait réellement depuis
`Documents\PowerShell\Modules\`.

Les deux étaient identiques — jusqu'au jour où une correction a été apportée à
la référence. Elle n'a eu **aucun effet**, en silence, parce que ce n'était pas
la copie exécutée. Il a fallu comparer les deux fichiers pour comprendre.

Un lien symbolique supprime la classe entière de ce problème : il n'y a plus
qu'un fichier réel, donc plus rien à synchroniser, donc plus de dérive possible.

---

## Installation

### 1. Cloner le dépôt

```powershell
git clone git@github.com:<login>/devcontext.git F:\PROJECTS\Apps\devcontext
```

Le chemin importe peu, mais `F:\PROJECTS\Apps\` place le dépôt sous la racine du
contexte `perso` — DevContext se gère alors lui-même.

### 2. Lier le dossier de modules PowerShell — **terminal administrateur**

```powershell
$modules = "$HOME\Documents\PowerShell\Modules\DevContext"
if (Test-Path $modules) { Rename-Item $modules "DevContext.avant-lien" }
New-Item -ItemType SymbolicLink -Path $modules -Target "F:\PROJECTS\Apps\devcontext"
```

> L'élévation n'est nécessaire que si le **mode développeur** de Windows est
> désactivé. S'il est actif, la commande passe sans administrateur.

### 3. Vérifier — dans un terminal NEUF

```powershell
work perso -NoCd
ctx
```

`ctx` doit répondre **GO**. Tant qu'il n'a pas répondu, **ne rien supprimer**.

### 4. Une fois la preuve faite

```powershell
Remove-Item "$HOME\Documents\PowerShell\Modules\DevContext.avant-lien" -Recurse -Force
```

### En cas de problème — retour arrière

```powershell
Remove-Item "$HOME\Documents\PowerShell\Modules\DevContext" -Force   # retire le lien
Rename-Item "$HOME\Documents\PowerShell\Modules\DevContext.avant-lien" "DevContext"
```

---

## Ce qui pointe vers ce dépôt depuis l'extérieur

Le lien symbolique ne couvre que PowerShell. **Trois autres choses référencent ce
dossier par son chemin absolu**, et aucune ne suit un déplacement :

| Consommateur | Ce qu'il vise | Comment le remettre en place |
|---|---|---|
| 10 raccourcis `Desktop\Raccourcis-outils\VS Code — *.lnk` | `lancer-vscode.ps1` | réécrire l'argument `-File` de chaque `.lnk` |
| Clé `HKCU\Software\Classes\vscode\shell\open\command` | `vscode-uri-router.ps1` | relancer `installer-uri-router.ps1` **depuis le dépôt** |
| `~\.claude\devcontext-agent.md` | chemin cité dans la doc agent | corriger à la main |

**Déplacer ce dépôt sans faire ces trois choses casse tout en silence.** Vécu le
13 août 2026 : le dossier `Desktop\02-OUTILS\DevContext\` a été supprimé après la
migration, les raccourcis ont ouvert un terminal qui se fermait aussitôt (script
introuvable), et le routeur `vscode://` pointant dans le vide a fait revenir la
réauthentification GitHub permanente sur tous les projets.

Vérification après tout déplacement :

```powershell
# les raccourcis visent-ils un script qui existe ?
$sh = New-Object -ComObject WScript.Shell
Get-ChildItem "$HOME\Desktop\Raccourcis-outils" -Filter 'VS Code*.lnk' | ForEach-Object {
    $a = $sh.CreateShortcut($_.FullName).Arguments
    $f = [regex]::Match($a, '-File "([^"]+)"').Groups[1].Value
    '{0,-34} {1}' -f $_.BaseName, (Test-Path -LiteralPath $f)
}

# le routeur d'URI est-il actif ET verrouillé ?
.\installer-uri-router.ps1 -Verifier
```

---

## Ce que ce dépôt ne contient pas, et ne contiendra jamais

| Quoi | Où ça vit réellement |
|---|---|
| Jetons (GitHub, Vercel, Supabase, Sentry) | coffre **SecretStore** `DevContext` |
| Identités de contexte (`context.json`) | `F:\CTX\<contexte>\` |
| Clés SSH | `~\.ssh\` |
| Configurations `gh` / `vercel` par contexte | `F:\CTX\<contexte>\` |

**Cloner ce dépôt sur une machine neuve ne restaure donc PAS les contextes.** Il
restaure l'outil. Les contextes se recréent avec `ctx-new`, et les jetons se
redéposent à la main dans le coffre — c'est voulu : un secret qui se restaure
depuis une sauvegarde est un secret qui a fui.

## Recréer un contexte après réinstallation

```powershell
ctx-new perso -Label "Perso" -Email "..." -Root "F:\PROJECTS\Apps" -GithubLogin "..."
```

`ctx-new` demande les jetons un par un, en saisie masquée. Entrée pour passer
ceux qu'on ne veut pas poser tout de suite.

Voir `README.md` pour l'usage quotidien, et `POURQUOI.md` pour ce que ce module
cherche à empêcher.
