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
