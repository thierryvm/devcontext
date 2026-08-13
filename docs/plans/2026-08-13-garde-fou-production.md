# Garde-fou production — plan d'implémentation

> **Pour les agents :** SOUS-COMPÉTENCE REQUISE — utiliser
> `superpowers:subagent-driven-development` (recommandé) ou
> `superpowers:executing-plans` pour dérouler ce plan tâche par tâche. Les
> étapes utilisent la syntaxe case à cocher (`- [ ]`) pour le suivi.

**But :** empêcher qu'une commande Supabase destructrice atteigne une base de
production, quel que soit le shell d'où elle part.

**Architecture :** deux couches. Un *shim* placé dans le PATH répond « ai-je le
droit ? » et se trouve sur le chemin de tout appelant — PowerShell, git-bash,
scripts npm, agents. Le wrapper PowerShell existant continue de répondre « sous
quelle identité ? », rôle inchangé. La décision elle-même est une fonction pure,
sans réseau ni secret, donc testable seule.

**Pile technique :** PowerShell 7, Pester 6.1.0, batch Windows (`.cmd`), shell
POSIX (git-bash).

**Spec de référence :** `docs/specs/2026-08-13-garde-fou-production-design.md`
(commit `9e0b500`).

## Contraintes globales

Ces règles s'appliquent à **toutes** les tâches.

- **Repli par le passage, jamais par le blocage.** Toute incertitude — index
  illisible, projet inconnu, hors contexte, hors dépôt git, erreur inattendue —
  laisse passer la commande.
- **Aucun test n'accède au réseau, au coffre SecretStore, ni à Supabase.** Les
  index et arborescences sont montés sous `$TestDrive` (fourni par Pester) et
  détruits automatiquement.
- **Aucun secret dans un message, un log, un test ou un commit.**
- **Encodage UTF-8 sans BOM**, fins de ligne conservées telles que le dépôt les
  écrit.
- **Commentaires et code en anglais ; documentation en français**, conformément
  à ce que contient déjà ce dépôt.
- **Messages de commit en anglais**, format
  `feat|fix|test|docs|refactor(scope): description`.
- Le module tourne sous **PowerShell 7** (`pwsh`), jamais `powershell.exe` 5.1.
- Pester doit être importé explicitement : `Import-Module Pester -MinimumVersion
  5.0.0` — Windows livre un Pester 3.4.0 non désinstallable et incompatible.
- **Ne rien casser :** aucune commande hors liste noire ne doit changer de
  comportement, de sortie, ni de code de retour.

---

## Structure des fichiers

| Fichier | Responsabilité | État |
|---|---|---|
| `DevContext.psm1` | module — accueille la décision, le résolveur d'exécutable, le marquage `env`, `ctx-sb` | modifié |
| `shims/supabase.ps1` | logique du shim : rassemble le contexte, appelle la décision, délègue ou refuse | créé |
| `shims/supabase.cmd` | point d'entrée cmd.exe / PowerShell / npm — filtre grossier puis délégation | créé |
| `shims/supabase` | point d'entrée git-bash / WSL (script POSIX) | créé |
| `installer-shims.ps1` | pose et retire le dossier de shims dans le PATH utilisateur | créé |
| `tests/RunTests.ps1` | lanceur unique, importe Pester ≥ 5 | créé (T1) |
| `tests/Guard.Tests.ps1` | décision pure — matrice complète | créé (T1) |
| `tests/Executable.Tests.ps1` | résolution du binaire réel hors shims | créé (T2) |
| `tests/SupabaseIndex.Tests.ps1` | marquage `env`, heuristique, fusion | créé (T3) |
| `tests/Shim.Tests.ps1` | délégation, propagation du code de sortie, refus | créé (T4) |
| `tests/SupabaseMap.Tests.ps1` | `ctx-sb` — comptes, partage entre dossiers | créé (T5) |
| `tests/Installer.Tests.ps1` | modes de l'installateur, innocuité de `-Verifier` | créé (T6) |
| `tests/ContextResolution.Tests.ps1` | dossier → contexte (piège du préfixe), ref → clé | créé (T7) |
| `tests/README.md` | comment lancer, et ce qu'aucun test ne fait | créé (T8) |

Le dossier `shims/` vit **dans le dépôt**, jamais copié ailleurs — même doctrine
que le module lui-même (leçon du 12 août 2026). Il devient de ce fait un
quatrième consommateur externe à chemin absolu, à inscrire dans
`INSTALLATION.md` (tâche 7).

---

### Tâche 1 : la décision pure et le harnais de tests

**Fichiers :**
- Modifier : `DevContext.psm1` (insérer avant `function Invoke-DevSupabase`, ligne 614)
- Créer : `tests/Guard.Tests.ps1`
- Créer : `tests/RunTests.ps1`

**Interfaces :**
- Consomme : rien.
- Produit : `Test-CtxSupabaseGuard` — paramètres `[string[]]$Arguments`,
  `[string]$Environment`, `[string]$CurrentBranch`, `[string]$DefaultBranch`,
  `[switch]$Override`. Renvoie un `PSCustomObject` à trois propriétés :
  `Allowed` (`[bool]`), `Rule` (`[string]`), `Reason` (`[string]`).
  Également `Get-CtxSupabaseSubcommand` — `[string[]]$Arguments` → `[string]`
  (les deux premiers arguments non-option, en minuscules, séparés par une
  espace ; chaîne vide si aucun).

- [ ] **Étape 1 : écrire le lanceur de tests**

Créer `tests/RunTests.ps1` :

```powershell
#Requires -Version 7
# Lanceur unique. Importe explicitement un Pester >= 5 : Windows livre un
# Pester 3.4.0 dans System32, non desinstallable et de syntaxe incompatible.
Import-Module Pester -MinimumVersion 5.0.0 -ErrorAction Stop

$config = New-PesterConfiguration
$config.Run.Path       = $PSScriptRoot
$config.Output.Verbosity = 'Detailed'
$config.Run.Exit      = $true

Invoke-Pester -Configuration $config
```

- [ ] **Étape 2 : écrire les tests qui échouent**

Créer `tests/Guard.Tests.ps1` :

```powershell
BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '..' 'DevContext.psd1') -Force
}

Describe 'Get-CtxSupabaseSubcommand' {
    It 'joint les deux premiers arguments non-option' {
        InModuleScope DevContext {
            Get-CtxSupabaseSubcommand @('db','reset') | Should -Be 'db reset'
        }
    }
    It 'ignore les options placees avant la sous-commande' {
        InModuleScope DevContext {
            Get-CtxSupabaseSubcommand @('--debug','db','reset') | Should -Be 'db reset'
        }
    }
    It 'ignore les options placees apres la sous-commande' {
        InModuleScope DevContext {
            Get-CtxSupabaseSubcommand @('db','reset','--linked') | Should -Be 'db reset'
        }
    }
    It 'normalise la casse' {
        InModuleScope DevContext {
            Get-CtxSupabaseSubcommand @('DB','Reset') | Should -Be 'db reset'
        }
    }
    It 'rend une chaine vide sans argument' {
        InModuleScope DevContext {
            Get-CtxSupabaseSubcommand @() | Should -Be ''
        }
    }
}

Describe 'Test-CtxSupabaseGuard — hors production' {
    It 'laisse passer db reset quand le projet est marque dev' {
        $r = Test-CtxSupabaseGuard -Arguments @('db','reset') -Environment 'dev' `
             -CurrentBranch 'feat/x' -DefaultBranch 'main'
        $r.Allowed | Should -BeTrue
    }
    It 'laisse passer db reset quand l environnement est inconnu' {
        $r = Test-CtxSupabaseGuard -Arguments @('db','reset') -Environment $null `
             -CurrentBranch 'feat/x' -DefaultBranch 'main'
        $r.Allowed | Should -BeTrue
    }
}

Describe 'Test-CtxSupabaseGuard — db reset en production' {
    It 'refuse, quelle que soit la branche' {
        $r = Test-CtxSupabaseGuard -Arguments @('db','reset') -Environment 'prod' `
             -CurrentBranch 'main' -DefaultBranch 'main'
        $r.Allowed | Should -BeFalse
        $r.Rule    | Should -Be 'db-reset-prod'
    }
    It 'refuse aussi hors depot git' {
        $r = Test-CtxSupabaseGuard -Arguments @('db','reset') -Environment 'prod' `
             -CurrentBranch $null -DefaultBranch $null
        $r.Allowed | Should -BeFalse
    }
    It 'laisse passer si le contournement explicite est pose' {
        $r = Test-CtxSupabaseGuard -Arguments @('db','reset') -Environment 'prod' `
             -CurrentBranch 'main' -DefaultBranch 'main' -Override
        $r.Allowed | Should -BeTrue
        $r.Rule    | Should -Be 'override'
    }
}

Describe 'Test-CtxSupabaseGuard — db push en production' {
    It 'laisse passer depuis la branche par defaut' {
        $r = Test-CtxSupabaseGuard -Arguments @('db','push') -Environment 'prod' `
             -CurrentBranch 'main' -DefaultBranch 'main'
        $r.Allowed | Should -BeTrue
    }
    It 'refuse depuis une autre branche' {
        $r = Test-CtxSupabaseGuard -Arguments @('db','push') -Environment 'prod' `
             -CurrentBranch 'feat/pwa-start-url-cockpit' -DefaultBranch 'main'
        $r.Allowed | Should -BeFalse
        $r.Rule    | Should -Be 'branch-mismatch'
    }
    It 'laisse passer si la branche par defaut est indeterminable' {
        $r = Test-CtxSupabaseGuard -Arguments @('db','push') -Environment 'prod' `
             -CurrentBranch 'feat/x' -DefaultBranch $null
        $r.Allowed | Should -BeTrue
    }
    It 'laisse passer hors depot git' {
        $r = Test-CtxSupabaseGuard -Arguments @('db','push') -Environment 'prod' `
             -CurrentBranch $null -DefaultBranch 'main'
        $r.Allowed | Should -BeTrue
    }
    It 'applique la meme regle a migration repair' {
        $r = Test-CtxSupabaseGuard -Arguments @('migration','repair') -Environment 'prod' `
             -CurrentBranch 'feat/x' -DefaultBranch 'main'
        $r.Allowed | Should -BeFalse
    }
    It 'applique la meme regle a migration up' {
        $r = Test-CtxSupabaseGuard -Arguments @('migration','up') -Environment 'prod' `
             -CurrentBranch 'feat/x' -DefaultBranch 'main'
        $r.Allowed | Should -BeFalse
    }
}

Describe 'Test-CtxSupabaseGuard — commandes hors liste noire' {
    It 'laisse passer db pull en production depuis une branche quelconque' {
        $r = Test-CtxSupabaseGuard -Arguments @('db','pull') -Environment 'prod' `
             -CurrentBranch 'feat/x' -DefaultBranch 'main'
        $r.Allowed | Should -BeTrue
    }
    It 'laisse passer db dump en production' {
        (Test-CtxSupabaseGuard -Arguments @('db','dump') -Environment 'prod' `
         -CurrentBranch 'feat/x' -DefaultBranch 'main').Allowed | Should -BeTrue
    }
    It 'laisse passer gen types en production' {
        (Test-CtxSupabaseGuard -Arguments @('gen','types') -Environment 'prod' `
         -CurrentBranch 'feat/x' -DefaultBranch 'main').Allowed | Should -BeTrue
    }
    It 'laisse passer une invocation sans argument' {
        (Test-CtxSupabaseGuard -Arguments @() -Environment 'prod' `
         -CurrentBranch 'feat/x' -DefaultBranch 'main').Allowed | Should -BeTrue
    }
    It 'laisse passer projects list' {
        (Test-CtxSupabaseGuard -Arguments @('projects','list','-o','json') -Environment 'prod' `
         -CurrentBranch 'feat/x' -DefaultBranch 'main').Allowed | Should -BeTrue
    }
}
```

- [ ] **Étape 3 : lancer les tests pour vérifier qu'ils échouent**

```powershell
pwsh -NoProfile -File .\tests\RunTests.ps1
```

Attendu : ÉCHEC, `CommandNotFoundException` sur `Test-CtxSupabaseGuard`.

- [ ] **Étape 4 : écrire l'implémentation minimale**

Insérer dans `DevContext.psm1`, juste avant `function Invoke-DevSupabase` :

```powershell
# ---------------------------------------------------------------------------
# Production guard — pure decision, no I/O
# ---------------------------------------------------------------------------

# Sub-commands that destroy data. No legitimate use against a production
# project, in any scenario.
$script:GuardDestructive = @('db reset')

# Sub-commands that are legitimate in production, but only from the repo's
# default branch. Pushing migrations from a side branch is how a schema goes
# backwards.
$script:GuardBranchBound = @('db push', 'migration repair', 'migration up')

function Get-CtxSupabaseSubcommand {
    # First two non-option arguments, lowercased. Options may appear anywhere.
    param([string[]]$Arguments = @())
    $words = @($Arguments | Where-Object { $_ -and -not $_.StartsWith('-') })
    if ($words.Count -eq 0) { return '' }
    ($words | Select-Object -First 2) -join ' ' | ForEach-Object { $_.ToLowerInvariant() }
}

function Test-CtxSupabaseGuard {
    <#
      Pure decision. No network, no vault, no filesystem. Everything it needs
      is passed in, which is what makes it testable on its own.
    #>
    [CmdletBinding()]
    param(
        [string[]]$Arguments = @(),
        [AllowNull()][string]$Environment,
        [AllowNull()][string]$CurrentBranch,
        [AllowNull()][string]$DefaultBranch,
        [switch]$Override
    )

    $pass = { param($rule) [pscustomobject]@{ Allowed = $true; Rule = $rule; Reason = '' } }

    if ($Environment -ne 'prod') { return (& $pass 'not-production') }

    $sub = Get-CtxSupabaseSubcommand $Arguments
    $destructive = $sub -in $script:GuardDestructive
    $branchBound = $sub -in $script:GuardBranchBound
    if (-not $destructive -and -not $branchBound) { return (& $pass 'not-guarded') }

    if ($Override) { return (& $pass 'override') }

    if ($destructive) {
        return [pscustomobject]@{
            Allowed = $false
            Rule    = 'db-reset-prod'
            Reason  = "'$sub' detruit et recree la base. Refuse sur un projet de production."
        }
    }

    # Branch-bound from here. Any doubt lets the command through.
    if (-not $CurrentBranch -or -not $DefaultBranch) { return (& $pass 'branch-unknown') }
    if ($CurrentBranch -eq $DefaultBranch)           { return (& $pass 'default-branch') }

    [pscustomobject]@{
        Allowed = $false
        Rule    = 'branch-mismatch'
        Reason  = "'$sub' vers un projet de production depuis la branche '$CurrentBranch' au lieu de '$DefaultBranch'."
    }
}
```

- [ ] **Étape 5 : exporter la fonction**

Dans `DevContext.psm1`, ajouter `'Test-CtxSupabaseGuard'` à `$exportedFunctions`
(ligne 1005). `Get-CtxSupabaseSubcommand` reste interne — les tests y accèdent
par `InModuleScope`.

- [ ] **Étape 6 : lancer les tests pour vérifier qu'ils passent**

```powershell
pwsh -NoProfile -File .\tests\RunTests.ps1
```

Attendu : 21 tests, tous verts.

- [ ] **Étape 7 : commit**

```bash
git add DevContext.psm1 tests/Guard.Tests.ps1 tests/RunTests.ps1
git commit -m "test: add the production guard decision and its first harness"
```

---

### Tâche 2 : résoudre le binaire réel sans se trouver soi-même

Une fois le shim dans le PATH, `Get-Command supabase -CommandType Application`
le retournera lui. Le shim s'appellerait alors en boucle, et le module
appellerait le shim au lieu du binaire. Il faut un résolveur qui exclut le
dossier des shims.

**Fichiers :**
- Modifier : `DevContext.psm1` (ligne 520 dans `Update-DevSupabaseIndex`,
  ligne 618 dans `Invoke-DevSupabase`, + nouvelle fonction)
- Créer : `tests/Executable.Tests.ps1`

**Interfaces :**
- Consomme : rien.
- Produit : `Get-CtxSupabaseExe` — paramètre `[string]$ExcludeDir` (optionnel,
  défaut `$script:ShimDir`). Renvoie un `[string]` : chemin complet du binaire
  réel. Lève si introuvable.
- Produit : `$script:ShimDir` — `[string]`, `<racine du module>/shims`.

- [ ] **Étape 1 : écrire les tests qui échouent**

Créer `tests/Executable.Tests.ps1` :

```powershell
BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '..' 'DevContext.psd1') -Force
}

Describe 'Get-CtxSupabaseExe' {
    It 'ne renvoie jamais un chemin situe dans le dossier des shims' {
        InModuleScope DevContext {
            $exe = try { Get-CtxSupabaseExe } catch { $null }
            if ($exe) {
                $exe | Should -Not -BeLike (Join-Path $script:ShimDir '*')
            }
        }
    }
    It 'expose un dossier de shims sous la racine du module' {
        InModuleScope DevContext {
            $script:ShimDir | Should -BeLike '*shims'
        }
    }
    It 'leve un message explicite quand tout est exclu' {
        InModuleScope DevContext {
            $all = Split-Path (Get-Command supabase -CommandType Application -ErrorAction SilentlyContinue |
                   Select-Object -First 1 -ExpandProperty Source) -Parent
            if ($all) {
                { Get-CtxSupabaseExe -ExcludeDir $all } | Should -Throw '*introuvable*'
            }
        }
    }
}
```

- [ ] **Étape 2 : lancer les tests pour vérifier qu'ils échouent**

```powershell
pwsh -NoProfile -File .\tests\RunTests.ps1
```

Attendu : ÉCHEC sur `Get-CtxSupabaseExe`.

- [ ] **Étape 3 : implémenter**

Ajouter dans `DevContext.psm1`, près des autres helpers Supabase (après
`Get-CtxSupabaseIndexPath`, ligne 477) :

```powershell
# The shim lives inside the repo, never copied elsewhere -- same doctrine as
# the module itself (lesson of 12 Aug 2026: two copies, one of them silently
# ignored).
$script:ShimDir = Join-Path $PSScriptRoot 'shims'

function Get-CtxSupabaseExe {
    <#
      Resolves the REAL supabase binary, skipping our own shim directory.
      Without this, the shim finds itself and recurses, and the module calls
      the shim instead of the CLI.
    #>
    param([string]$ExcludeDir = $script:ShimDir)

    $normalized = if ($ExcludeDir) { $ExcludeDir.TrimEnd('\', '/') } else { $null }

    $candidate = Get-Command supabase -CommandType Application -All -ErrorAction SilentlyContinue |
        Where-Object {
            -not $normalized -or (Split-Path $_.Source -Parent).TrimEnd('\', '/') -ne $normalized
        } | Select-Object -First 1

    if (-not $candidate) { throw "supabase introuvable dans le PATH (hors shims)." }
    $candidate.Source
}
```

- [ ] **Étape 4 : brancher les deux appelants existants**

Dans `Update-DevSupabaseIndex`, remplacer les lignes 520-521 :

```powershell
    $exe = Get-Command supabase -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $exe) { throw "supabase introuvable dans le PATH." }
```

par :

```powershell
    $exe = Get-CtxSupabaseExe
```

puis remplacer les deux usages de `$exe.Source` par `$exe` dans cette fonction
(ligne 537).

Dans `Invoke-DevSupabase`, remplacer les lignes 618-619 par la même chose, et
les deux usages de `$exe.Source` par `$exe` (lignes 651 et 656).

- [ ] **Étape 5 : vérifier que rien n'a bougé**

```powershell
pwsh -NoProfile -File .\tests\RunTests.ps1
pwsh -NoProfile -Command "Import-Module .\DevContext.psd1 -Force; supabase --version"
```

Attendu : tests verts, et `supabase --version` répond comme avant.

- [ ] **Étape 6 : commit**

```bash
git add DevContext.psm1 tests/Executable.Tests.ps1
git commit -m "refactor: resolve the real supabase binary, skipping our own shims"
```

---

### Tâche 3 : marquer la production dans l'index, sans jamais écraser un choix manuel

`Update-DevSupabaseIndex` reconstruit l'index de zéro (`$index = [ordered]@{}`,
ligne 526) et l'écrit par-dessus l'ancien. Un `env` posé à la main serait effacé
au premier `sb-index`. La fusion doit être explicite.

**Fichiers :**
- Modifier : `DevContext.psm1` (`Update-DevSupabaseIndex`, lignes 515-558)
- Créer : `tests/SupabaseIndex.Tests.ps1`

**Interfaces :**
- Consomme : `Get-CtxSupabaseIndexPath` (existant).
- Produit : `Get-CtxSupabaseEnvGuess` — `[string]$ProjectName` → `[string]`
  (`'prod'`, `'dev'`, ou `$null`).
- Produit : `Get-CtxSupabaseEnv` — `[string]$Ref`, `[string]$ContextName` →
  `[string]` ou `$null`. Lit l'index et renvoie le champ `env`.
- Produit : chaque entrée d'index gagne deux champs — `env`
  (`'prod'`/`'dev'`/`null`) et `envSource` (`'auto'` ou `'manual'`).

- [ ] **Étape 1 : écrire les tests qui échouent**

Créer `tests/SupabaseIndex.Tests.ps1` :

```powershell
BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '..' 'DevContext.psd1') -Force
}

Describe 'Get-CtxSupabaseEnvGuess' {
    It 'reconnait prod dans le nom' {
        InModuleScope DevContext { Get-CtxSupabaseEnvGuess 'ankora-prod' | Should -Be 'prod' }
    }
    It 'reconnait production dans le nom' {
        InModuleScope DevContext { Get-CtxSupabaseEnvGuess 'shop production' | Should -Be 'prod' }
    }
    It 'reconnait staging comme non-production' {
        InModuleScope DevContext { Get-CtxSupabaseEnvGuess 'ankora-staging' | Should -Be 'dev' }
    }
    It 'reconnait dev, preview et test' {
        InModuleScope DevContext {
            Get-CtxSupabaseEnvGuess 'app-dev'     | Should -Be 'dev'
            Get-CtxSupabaseEnvGuess 'app-preview' | Should -Be 'dev'
            Get-CtxSupabaseEnvGuess 'app-test'    | Should -Be 'dev'
        }
    }
    It 'ignore la casse' {
        InModuleScope DevContext { Get-CtxSupabaseEnvGuess 'Ankora-PROD' | Should -Be 'prod' }
    }
    It 'rend null sur un nom neutre' {
        InModuleScope DevContext { Get-CtxSupabaseEnvGuess 'IronTrack' | Should -BeNullOrEmpty }
    }
    It 'ne confond pas reproduction avec production' {
        InModuleScope DevContext { Get-CtxSupabaseEnvGuess 'reproduction-bug' | Should -BeNullOrEmpty }
    }
}

Describe 'Get-CtxSupabaseEnv' {
    BeforeAll {
        $script:ctxDir = Join-Path $TestDrive 'CTX' 'demo'
        New-Item -ItemType Directory -Path $script:ctxDir -Force | Out-Null
        @{
            'aaaa' = @{ key = 'supabase-token';   name = 'app-prod'; env = 'prod'; envSource = 'auto' }
            'bbbb' = @{ key = 'supabase-token-2'; name = 'app-dev';  env = 'dev';  envSource = 'auto' }
            'cccc' = @{ key = 'supabase-token';   name = 'neutre' }
        } | ConvertTo-Json -Depth 4 | Set-Content (Join-Path $script:ctxDir 'supabase-index.json') -Encoding UTF8
    }
    It 'rend prod pour une entree marquee' {
        InModuleScope DevContext -Parameters @{ dir = $script:ctxDir } {
            param($dir)
            Mock Get-CtxSupabaseIndexPath { Join-Path $dir 'supabase-index.json' }
            Get-CtxSupabaseEnv -Ref 'aaaa' -ContextName 'demo' | Should -Be 'prod'
        }
    }
    It 'rend null pour une entree sans champ env' {
        InModuleScope DevContext -Parameters @{ dir = $script:ctxDir } {
            param($dir)
            Mock Get-CtxSupabaseIndexPath { Join-Path $dir 'supabase-index.json' }
            Get-CtxSupabaseEnv -Ref 'cccc' -ContextName 'demo' | Should -BeNullOrEmpty
        }
    }
    It 'rend null pour un ref absent' {
        InModuleScope DevContext -Parameters @{ dir = $script:ctxDir } {
            param($dir)
            Mock Get-CtxSupabaseIndexPath { Join-Path $dir 'supabase-index.json' }
            Get-CtxSupabaseEnv -Ref 'zzzz' -ContextName 'demo' | Should -BeNullOrEmpty
        }
    }
    It 'rend null quand l index n existe pas' {
        InModuleScope DevContext {
            Mock Get-CtxSupabaseIndexPath { Join-Path $TestDrive 'nulle-part.json' }
            Get-CtxSupabaseEnv -Ref 'aaaa' -ContextName 'demo' | Should -BeNullOrEmpty
        }
    }
}

Describe 'Merge-CtxSupabaseEnv' {
    It 'conserve un env pose a la main' {
        InModuleScope DevContext {
            $ancien = @{ 'aaaa' = [pscustomobject]@{ env = 'dev'; envSource = 'manual' } }
            $r = Merge-CtxSupabaseEnv -Ref 'aaaa' -ProjectName 'app-prod' -Previous $ancien
            $r.env       | Should -Be 'dev'
            $r.envSource | Should -Be 'manual'
        }
    }
    It 'reevalue un env pose automatiquement' {
        InModuleScope DevContext {
            $ancien = @{ 'aaaa' = [pscustomobject]@{ env = $null; envSource = 'auto' } }
            $r = Merge-CtxSupabaseEnv -Ref 'aaaa' -ProjectName 'app-prod' -Previous $ancien
            $r.env       | Should -Be 'prod'
            $r.envSource | Should -Be 'auto'
        }
    }
    It 'devine sur une entree entierement nouvelle' {
        InModuleScope DevContext {
            $r = Merge-CtxSupabaseEnv -Ref 'aaaa' -ProjectName 'app-prod' -Previous @{}
            $r.env       | Should -Be 'prod'
            $r.envSource | Should -Be 'auto'
        }
    }
}
```

- [ ] **Étape 2 : lancer les tests pour vérifier qu'ils échouent**

```powershell
pwsh -NoProfile -File .\tests\RunTests.ps1
```

Attendu : ÉCHEC sur les trois nouvelles fonctions.

- [ ] **Étape 3 : implémenter les trois fonctions**

Ajouter dans `DevContext.psm1`, avant `function Update-DevSupabaseIndex` :

```powershell
# Naming conventions, not a source of truth. sb-index proposes, the human
# disposes: anything marked 'manual' is never recomputed.
$script:EnvPatternProd = '(^|[^a-z])(prod|production)([^a-z]|$)'
$script:EnvPatternDev  = '(^|[^a-z])(dev|develop|staging|preview|test|sandbox)([^a-z]|$)'

function Get-CtxSupabaseEnvGuess {
    param([AllowNull()][string]$ProjectName)
    if (-not $ProjectName) { return $null }
    $n = $ProjectName.ToLowerInvariant()
    if ($n -match $script:EnvPatternProd) { return 'prod' }
    if ($n -match $script:EnvPatternDev)  { return 'dev' }
    return $null
}

function Merge-CtxSupabaseEnv {
    # Keeps a hand-set value, recomputes an auto one.
    param(
        [Parameter(Mandatory)][string]$Ref,
        [AllowNull()][string]$ProjectName,
        $Previous
    )
    $old = if ($Previous -and $Previous[$Ref]) { $Previous[$Ref] } else { $null }
    if ($old -and $old.envSource -eq 'manual') {
        return [pscustomobject]@{ env = $old.env; envSource = 'manual' }
    }
    [pscustomobject]@{ env = (Get-CtxSupabaseEnvGuess $ProjectName); envSource = 'auto' }
}

function Get-CtxSupabaseEnv {
    param(
        [Parameter(Mandatory)][string]$Ref,
        [Parameter(Mandatory)][string]$ContextName
    )
    $path = Get-CtxSupabaseIndexPath $ContextName
    if (-not (Test-Path $path)) { return $null }
    try {
        $index = Get-Content $path -Raw | ConvertFrom-Json
        $entry = $index.PSObject.Properties | Where-Object { $_.Name -eq $Ref } | Select-Object -First 1
        if ($entry) { return $entry.Value.env }
    }
    catch { return $null }
    return $null
}
```

- [ ] **Étape 4 : faire fusionner `Update-DevSupabaseIndex`**

Dans `Update-DevSupabaseIndex`, après la ligne `$index = [ordered]@{}`
(ligne 526), insérer la lecture de l'index existant :

```powershell
    # Read the previous index BEFORE rebuilding: a hand-set env must survive.
    $previous = @{}
    $previousPath = Get-CtxSupabaseIndexPath $Name
    if (Test-Path $previousPath) {
        try {
            (Get-Content $previousPath -Raw | ConvertFrom-Json).PSObject.Properties |
                ForEach-Object { $previous[$_.Name] = $_.Value }
        }
        catch { Write-Warning "Index existant illisible, il sera reconstruit." }
    }
```

Puis remplacer la ligne 547 :

```powershell
                $index[$p.id] = [ordered]@{ key = $key; name = $p.name }
```

par :

```powershell
                $merged = Merge-CtxSupabaseEnv -Ref $p.id -ProjectName $p.name -Previous $previous
                $index[$p.id] = [ordered]@{
                    key       = $key
                    name      = $p.name
                    env       = $merged.env
                    envSource = $merged.envSource
                }
```

- [ ] **Étape 5 : lancer les tests**

```powershell
pwsh -NoProfile -File .\tests\RunTests.ps1
```

Attendu : tous verts.

- [ ] **Étape 6 : régénérer l'index réel et vérifier**

```powershell
work perso -NoCd; sb-index
Get-Content F:\CTX\perso\supabase-index.json | ConvertFrom-Json |
    Select-Object -ExpandProperty PSObject |
    Select-Object -ExpandProperty Properties |
    ForEach-Object { '{0,-20} {1,-6} {2}' -f $_.Value.name, $_.Value.env, $_.Value.envSource }
```

Attendu : `ankora-prod` porte `prod` / `auto`. Les trois autres portent une
valeur vide et `auto`. Toujours 4 entrées, aucune perte.

- [ ] **Étape 7 : commit**

```bash
git add DevContext.psm1 tests/SupabaseIndex.Tests.ps1
git commit -m "feat: tag production projects in the supabase index, preserving manual choices"
```

---

### Tâche 4 : le shim, joignable depuis n'importe quel shell

**Fichiers :**
- Créer : `shims/supabase.ps1`
- Créer : `shims/supabase.cmd`
- Créer : `shims/supabase`
- Créer : `tests/Shim.Tests.ps1`

**Interfaces :**
- Consomme : `Test-CtxSupabaseGuard`, `Get-CtxSupabaseEnv`,
  `Resolve-CtxSupabaseRef`, `Get-CtxSupabaseExe` (tâches 1 à 3).
- Produit : trois exécutables nommés `supabase` dans `shims/`. Code de sortie
  `1` en cas de refus, sinon celui du binaire réel.

- [ ] **Étape 1 : écrire la logique du shim**

Créer `shims/supabase.ps1` :

```powershell
#Requires -Version 7
<#
  Production guard. Sits in the PATH, so it is reached by every caller --
  PowerShell, git-bash, npm scripts, Node child processes, AI agents. The
  module's `supabase` alias only ever covered PowerShell, which is the one
  caller least likely to make the mistake.

  Refuses only on a case it is certain about. Any doubt passes through.
#>
[CmdletBinding()]
param([Parameter(ValueFromRemainingArguments)][string[]]$Rest = @())

$ErrorActionPreference = 'Stop'

function Invoke-Real {
    param([string[]]$Arguments)
    $exe = $null
    try {
        Import-Module (Join-Path $PSScriptRoot '..' 'DevContext.psd1') -Force -ErrorAction Stop
        $exe = & (Get-Module DevContext) { Get-CtxSupabaseExe }
    }
    catch {
        # Module unavailable: find the binary ourselves, skipping this folder.
        $here = $PSScriptRoot.TrimEnd('\', '/')
        $exe = Get-Command supabase -CommandType Application -All -ErrorAction SilentlyContinue |
            Where-Object { (Split-Path $_.Source -Parent).TrimEnd('\', '/') -ne $here } |
            Select-Object -First 1 -ExpandProperty Source
    }
    if (-not $exe) {
        Write-Error "supabase introuvable dans le PATH."
        exit 127
    }
    & $exe @Arguments
    exit $LASTEXITCODE
}

# --- decide -----------------------------------------------------------------

$verdict = $null
try {
    Import-Module (Join-Path $PSScriptRoot '..' 'DevContext.psd1') -Force -ErrorAction Stop

    $ref = & (Get-Module DevContext) { Resolve-CtxSupabaseRef }
    if (-not $ref -or -not $env:DEVCTX) { Invoke-Real $Rest }

    $environment = & (Get-Module DevContext) { param($r, $c) Get-CtxSupabaseEnv -Ref $r -ContextName $c } $ref $env:DEVCTX
    if ($environment -ne 'prod') { Invoke-Real $Rest }

    $current = (git rev-parse --abbrev-ref HEAD 2>$null)
    if ($LASTEXITCODE -ne 0) { $current = $null }

    $default = (git symbolic-ref --short refs/remotes/origin/HEAD 2>$null)
    if ($LASTEXITCODE -eq 0 -and $default) { $default = ($default -split '/')[-1] }
    else {
        $default = $null
        foreach ($candidate in 'main', 'master') {
            git show-ref --verify --quiet "refs/heads/$candidate" 2>$null
            if ($LASTEXITCODE -eq 0) { $default = $candidate; break }
        }
    }

    $verdict = & (Get-Module DevContext) {
        param($a, $e, $c, $d, $o)
        Test-CtxSupabaseGuard -Arguments $a -Environment $e -CurrentBranch $c -DefaultBranch $d -Override:$o
    } $Rest $environment $current $default ($env:DEVCTX_ALLOW_PROD -eq '1')
}
catch {
    # A guard that breaks when it hesitates is a guard that gets uninstalled.
    Invoke-Real $Rest
}

if (-not $verdict -or $verdict.Allowed) { Invoke-Real $Rest }

# --- refuse -----------------------------------------------------------------

$name = & (Get-Module DevContext) { param($r, $c)
    $p = Get-CtxSupabaseIndexPath $c
    if (Test-Path $p) {
        $i = Get-Content $p -Raw | ConvertFrom-Json
        ($i.PSObject.Properties | Where-Object { $_.Name -eq $r } | Select-Object -First 1).Value.name
    }
} $ref $env:DEVCTX

Write-Host ''
Write-Host '  REFUSE — garde-fou production DevContext' -ForegroundColor Red
Write-Host ''
Write-Host "    Base visee : $name" -ForegroundColor Yellow
Write-Host "    Raison     : $($verdict.Reason)"
Write-Host ''
Write-Host '    Pour forcer, deliberement et pour cette commande seulement :' -ForegroundColor DarkGray
Write-Host '      $env:DEVCTX_ALLOW_PROD = 1' -ForegroundColor DarkGray
Write-Host ''
exit 1
```

- [ ] **Étape 2 : écrire les deux points d'entrée**

Créer `shims/supabase.cmd` :

```bat
@echo off
rem Coarse filter first: only pay the pwsh startup cost when an argument could
rem possibly match the blacklist. Every other supabase call stays as fast as
rem before.
echo %* | findstr /i /r "\<reset\> \<push\> \<repair\> \<up\>" >nul
if errorlevel 1 (
    for /f "delims=" %%i in ('pwsh -NoLogo -NoProfile -Command "(Get-Command supabase -CommandType Application -All | Where-Object { (Split-Path $_.Source -Parent) -ne '%~dp0'.TrimEnd('\') } | Select-Object -First 1).Source"') do set "REAL=%%i"
    "%REAL%" %*
    exit /b %ERRORLEVEL%
)
pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0supabase.ps1" %*
exit /b %ERRORLEVEL%
```

Créer `shims/supabase` (sans extension, pour git-bash et WSL) :

```sh
#!/bin/sh
# git-bash resolves `supabase` to this file. Delegates to the same logic.
DIR=$(dirname "$0")
exec pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File "$DIR/supabase.ps1" "$@"
```

- [ ] **Étape 3 : écrire les tests**

Créer `tests/Shim.Tests.ps1` :

```powershell
BeforeAll {
    $script:Shim = Join-Path $PSScriptRoot '..' 'shims' 'supabase.ps1'
}

Describe 'shim — fichiers presents' {
    It 'expose les trois points d entree' {
        Test-Path (Join-Path $PSScriptRoot '..' 'shims' 'supabase.ps1') | Should -BeTrue
        Test-Path (Join-Path $PSScriptRoot '..' 'shims' 'supabase.cmd') | Should -BeTrue
        Test-Path (Join-Path $PSScriptRoot '..' 'shims' 'supabase')     | Should -BeTrue
    }
    It 'a une syntaxe PowerShell valide' {
        $errors = $null
        [System.Management.Automation.Language.Parser]::ParseFile(
            (Resolve-Path $script:Shim).Path, [ref]$null, [ref]$errors) | Out-Null
        $errors.Count | Should -Be 0
    }
}

Describe 'shim — delegation hors contexte' {
    It 'transmet et propage le code de sortie du binaire reel' {
        # Hors contexte DevContext : le shim doit deleguer sans juger.
        $out = pwsh -NoProfile -File $script:Shim --version 2>&1
        $LASTEXITCODE | Should -Be 0
        ($out -join ' ') | Should -Not -BeLike '*REFUSE*'
    }
    It 'propage un echec du binaire reel' {
        pwsh -NoProfile -File $script:Shim 'commande-qui-n-existe-pas' 2>&1 | Out-Null
        $LASTEXITCODE | Should -Not -Be 0
    }
}
```

- [ ] **Étape 4 : lancer les tests**

```powershell
pwsh -NoProfile -File .\tests\RunTests.ps1
```

Attendu : tous verts. Le shim n'est pas encore dans le PATH — ces tests
l'appellent par son chemin.

- [ ] **Étape 5 : vérifier le refus pour de vrai, sans rien détruire**

```powershell
work perso -NoCd
Set-Location F:\PROJECTS\Apps\ankora-refonte
pwsh -NoProfile -File F:\PROJECTS\Apps\devcontext\shims\supabase.ps1 db reset --dry-run
```

Attendu : bloc **REFUSE**, base visée `ankora-prod`, code de sortie 1. Le
binaire réel n'est jamais appelé — `--dry-run` n'est ici qu'une ceinture de
sécurité supplémentaire.

Puis vérifier qu'une commande inoffensive passe depuis le même dossier :

```powershell
pwsh -NoProfile -File F:\PROJECTS\Apps\devcontext\shims\supabase.ps1 --version
```

Attendu : le numéro de version, aucun message de refus.

- [ ] **Étape 6 : commit**

```bash
git add shims/ tests/Shim.Tests.ps1
git commit -m "feat: add a PATH shim so the guard covers every shell, not just PowerShell"
```

---

### Tâche 5 : `ctx-sb`, voir le parc d'un coup d'œil

**Fichiers :**
- Modifier : `DevContext.psm1` (nouvelle fonction + alias + exports)
- Créer : `tests/SupabaseMap.Tests.ps1`

**Interfaces :**
- Consomme : `Get-CtxSupabaseIndexPath`, `Get-CtxPath`, `Read-CtxManifest`,
  `Get-CtxProp` (existants).
- Produit : `Get-DevSupabaseMap` — paramètre `[string]$Name = $env:DEVCTX`.
  Renvoie un tableau de `PSCustomObject` à six propriétés : `Compte`, `Projet`,
  `Ref`, `Env`, `Dossiers` (`[string[]]`), `Partage` (`[bool]`).
  Alias `ctx-sb`.

- [ ] **Étape 1 : écrire les tests qui échouent**

Créer `tests/SupabaseMap.Tests.ps1` :

```powershell
BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '..' 'DevContext.psd1') -Force
}

Describe 'Get-DevSupabaseMap' {
    BeforeAll {
        $script:root = Join-Path $TestDrive 'PROJECTS'
        foreach ($pair in @(@('alpha','aaaa'), @('beta','bbbb'), @('beta-wt','bbbb'))) {
            $d = Join-Path $script:root $pair[0] 'supabase' '.temp'
            New-Item -ItemType Directory -Path $d -Force | Out-Null
            Set-Content (Join-Path $d 'project-ref') $pair[1] -NoNewline
        }
        $script:ctxDir = Join-Path $TestDrive 'CTX' 'demo'
        New-Item -ItemType Directory -Path $script:ctxDir -Force | Out-Null
        @{
            'aaaa' = @{ key = 'supabase-token';   name = 'alpha-dev';  env = 'dev'  }
            'bbbb' = @{ key = 'supabase-token-2'; name = 'beta-prod';  env = 'prod' }
        } | ConvertTo-Json -Depth 4 | Set-Content (Join-Path $script:ctxDir 'supabase-index.json') -Encoding UTF8
    }

    It 'associe chaque projet a son compte' {
        InModuleScope DevContext -Parameters @{ c = $script:ctxDir; r = $script:root } {
            param($c, $r)
            Mock Get-CtxSupabaseIndexPath { Join-Path $c 'supabase-index.json' }
            Mock Get-CtxSupabaseMapRoot   { $r }
            $m = Get-DevSupabaseMap -Name 'demo'
            ($m | Where-Object Projet -eq 'beta-prod').Compte | Should -Be 'supabase-token-2'
        }
    }
    It 'liste tous les dossiers qui visent un meme projet' {
        InModuleScope DevContext -Parameters @{ c = $script:ctxDir; r = $script:root } {
            param($c, $r)
            Mock Get-CtxSupabaseIndexPath { Join-Path $c 'supabase-index.json' }
            Mock Get-CtxSupabaseMapRoot   { $r }
            $e = Get-DevSupabaseMap -Name 'demo' | Where-Object Projet -eq 'beta-prod'
            $e.Dossiers.Count | Should -Be 2
            $e.Partage        | Should -BeTrue
        }
    }
    It 'ne signale pas un projet vise par un seul dossier' {
        InModuleScope DevContext -Parameters @{ c = $script:ctxDir; r = $script:root } {
            param($c, $r)
            Mock Get-CtxSupabaseIndexPath { Join-Path $c 'supabase-index.json' }
            Mock Get-CtxSupabaseMapRoot   { $r }
            ($m = Get-DevSupabaseMap -Name 'demo' | Where-Object Projet -eq 'alpha-dev').Partage |
                Should -BeFalse
        }
    }
    It 'leve un message clair quand l index est absent' {
        InModuleScope DevContext {
            Mock Get-CtxSupabaseIndexPath { Join-Path $TestDrive 'nulle-part.json' }
            { Get-DevSupabaseMap -Name 'demo' } | Should -Throw '*sb-index*'
        }
    }
}
```

- [ ] **Étape 2 : lancer les tests pour vérifier qu'ils échouent**

```powershell
pwsh -NoProfile -File .\tests\RunTests.ps1
```

Attendu : ÉCHEC sur `Get-DevSupabaseMap`.

- [ ] **Étape 3 : implémenter**

Ajouter dans `DevContext.psm1`, après `Update-DevSupabaseIndex` :

```powershell
function Get-CtxSupabaseMapRoot {
    # Isolated so tests can point it elsewhere.
    param([Parameter(Mandatory)][string]$Name)
    Get-CtxProp (Read-CtxManifest $Name) 'root'
}

function Get-DevSupabaseMap {
    <#
      Which project lives on which account, which one is production, and which
      folders point at it.

      Not a convenience. On 13 Aug 2026 the question "which account is
      airsoft-aywaille on?" could only be answered by reading the index by
      hand, though the answer had been on the machine all along. A guard whose
      data cannot be inspected is a guard that eventually gets switched off.
    #>
    [CmdletBinding()]
    param([string]$Name = $env:DEVCTX)

    if (-not $Name) { throw "Aucun contexte actif. 'work <contexte>' d'abord, ou 'ctx-sb <contexte>'." }

    $indexPath = Get-CtxSupabaseIndexPath $Name
    if (-not (Test-Path $indexPath)) { throw "Aucun index Supabase pour '$Name'. Lance 'sb-index'." }
    $index = Get-Content $indexPath -Raw | ConvertFrom-Json

    $root = Get-CtxSupabaseMapRoot $Name
    $byRef = @{}
    if ($root -and (Test-Path $root)) {
        Get-ChildItem $root -Recurse -Depth 4 -Filter 'project-ref' -File -ErrorAction SilentlyContinue |
            Where-Object { $_.DirectoryName -like '*supabase*.temp' } |
            ForEach-Object {
                $ref = (Get-Content $_.FullName -Raw).Trim()
                $folder = $_.FullName.Substring($root.Length).TrimStart('\', '/') -replace '[\\/]supabase[\\/]\.temp[\\/]project-ref$', ''
                if (-not $byRef.ContainsKey($ref)) { $byRef[$ref] = @() }
                $byRef[$ref] += $folder
            }
    }

    $index.PSObject.Properties | ForEach-Object {
        $folders = @(if ($byRef.ContainsKey($_.Name)) { $byRef[$_.Name] } else { @() })
        [pscustomobject]@{
            Compte   = $_.Value.key
            Projet   = $_.Value.name
            Ref      = $_.Name
            Env      = $_.Value.env
            Dossiers = $folders
            Partage  = ($folders.Count -gt 1)
        }
    } | Sort-Object Compte, Projet
}
```

- [ ] **Étape 4 : brancher l'alias et les exports**

Dans `DevContext.psm1` :

```powershell
Set-Alias -Name ctx-sb    -Value Get-DevSupabaseMap
```

Ajouter `'Get-DevSupabaseMap'` à `$exportedFunctions` et `'ctx-sb'` à
`$exportedAliases`.

- [ ] **Étape 5 : lancer les tests**

```powershell
pwsh -NoProfile -File .\tests\RunTests.ps1
```

Attendu : tous verts.

- [ ] **Étape 6 : vérifier sur le parc réel**

```powershell
work perso -NoCd; ctx-sb | Format-Table Compte, Projet, Env, Partage, @{n='Dossiers';e={$_.Dossiers -join ', '}} -AutoSize
```

Attendu : `ankora-prod` en `prod`, `Partage` à `$true`, trois dossiers listés.
Les trois autres projets avec un seul dossier chacun.

- [ ] **Étape 7 : commit**

```bash
git add DevContext.psm1 tests/SupabaseMap.Tests.ps1
git commit -m "feat: add ctx-sb, showing which project lives on which account"
```

---

### Tâche 6 : poser le shim dans le PATH, et pouvoir le retirer

Modelé sur `installer-uri-router.ps1`, qui a déjà les bons réflexes : un mode
`-Verifier`, un mode `-Restaurer`, et une sauvegarde de l'état d'avant.

**Fichiers :**
- Créer : `installer-shims.ps1`
- Créer : `tests/Installer.Tests.ps1`

**Interfaces :**
- Consomme : `shims/` (tâche 4).
- Produit : `installer-shims.ps1`, trois modes — sans paramètre (pose),
  `-Verifier` (rapporte), `-Restaurer` (retire).

- [ ] **Étape 1 : relever l'état actuel du PATH**

```powershell
$sauvegarde = 'F:\Backups\devcontext-path-2026-08-13'
New-Item -ItemType Directory -Path $sauvegarde -Force | Out-Null

[Environment]::GetEnvironmentVariable('Path', 'User') |
    Set-Content (Join-Path $sauvegarde 'path-utilisateur-AVANT.txt') -Encoding UTF8

(Get-Command supabase -CommandType Application -All).Source |
    Set-Content (Join-Path $sauvegarde 'resolution-supabase-AVANT.txt') -Encoding UTF8

@'
# PATH utilisateur — 13 août 2026

Sauvegarde prise avant d'ajouter `F:\PROJECTS\Apps\devcontext\shims` en tête du
PATH utilisateur (`HKCU\Environment`).

## Pourquoi

Le garde-fou production doit être joignable depuis n'importe quel shell —
git-bash, npm, Node, agent IA — et pas seulement depuis PowerShell. Le seul
point de passage commun à tous est le PATH.

## Contenu

| Fichier | Quoi |
|---|---|
| `path-utilisateur-AVANT.txt` | valeur brute du PATH utilisateur |
| `resolution-supabase-AVANT.txt` | ce que `supabase` résolvait avant le shim |

## Retour arrière

```powershell
& 'F:\PROJECTS\Apps\devcontext\installer-shims.ps1' -Restaurer
```

L'installateur sauvegarde aussi le PATH dans
`%LOCALAPPDATA%\DevContext\path-utilisateur-avant-shims.txt`. Ce dossier-ci est
la copie hors profil, conservée selon la convention de `F:\Backups\`.

Les terminaux déjà ouverts gardent l'ancien PATH : le retrait ne prend effet
qu'à l'ouverture d'un terminal neuf.
'@ | Set-Content (Join-Path $sauvegarde 'README.md') -Encoding UTF8
```

- [ ] **Étape 2 : écrire les tests qui échouent**

Créer `tests/Installer.Tests.ps1` :

```powershell
BeforeAll {
    $script:Installer = (Resolve-Path (Join-Path $PSScriptRoot '..' 'installer-shims.ps1')).Path
}

Describe 'installer-shims' {
    It 'existe et a une syntaxe valide' {
        $errors = $null
        [System.Management.Automation.Language.Parser]::ParseFile(
            $script:Installer, [ref]$null, [ref]$errors) | Out-Null
        $errors.Count | Should -Be 0
    }
    It 'expose les modes -Verifier et -Restaurer' {
        $ast = [System.Management.Automation.Language.Parser]::ParseFile(
            $script:Installer, [ref]$null, [ref]$null)
        $names = $ast.ParamBlock.Parameters.Name.VariablePath.UserPath
        $names | Should -Contain 'Verifier'
        $names | Should -Contain 'Restaurer'
    }
    It 'rapporte sans rien modifier en mode -Verifier' {
        $avant = [Environment]::GetEnvironmentVariable('Path', 'User')
        pwsh -NoProfile -File $script:Installer -Verifier | Out-Null
        [Environment]::GetEnvironmentVariable('Path', 'User') | Should -Be $avant
    }
}
```

- [ ] **Étape 3 : lancer les tests pour vérifier qu'ils échouent**

```powershell
pwsh -NoProfile -File .\tests\RunTests.ps1
```

Attendu : ÉCHEC, fichier introuvable.

- [ ] **Étape 4 : écrire l'installateur**

Créer `installer-shims.ps1` :

```powershell
#Requires -Version 7
<#
  Puts the shim folder at the FRONT of the user PATH, so `supabase` resolves to
  the guard before it resolves to the real CLI.

  User scope only -- no administrator rights, fully reversible.

  Like the module itself, the shims are used from the repository, never copied.
  This makes the PATH a fourth external consumer pointing at this folder by
  absolute path. Moving the repository breaks it silently, exactly as it broke
  the shortcuts and the registry key on 13 Aug 2026. See INSTALLATION.md.
#>
[CmdletBinding()]
param([switch]$Verifier, [switch]$Restaurer)

$ShimDir = (Join-Path $PSScriptRoot 'shims')

function Get-UserPath { [Environment]::GetEnvironmentVariable('Path', 'User') }
function Set-UserPath { param([string]$Value) [Environment]::SetEnvironmentVariable('Path', $Value, 'User') }

function Test-Pose {
    $entries = (Get-UserPath) -split ';' | ForEach-Object { $_.TrimEnd('\') }
    $entries -contains $ShimDir.TrimEnd('\')
}

if ($Verifier) {
    Write-Host ''
    if (Test-Pose) { Write-Host '  SHIM ACTIF' -ForegroundColor Green }
    else           { Write-Host '  SHIM ABSENT du PATH utilisateur' -ForegroundColor Yellow }
    Write-Host "    dossier : $ShimDir"
    Write-Host ''
    Write-Host '  Resolution de "supabase" dans ce processus :'
    Get-Command supabase -CommandType Application -All -ErrorAction SilentlyContinue |
        ForEach-Object { '    ' + $_.Source }
    Write-Host ''
    foreach ($f in 'supabase.ps1', 'supabase.cmd', 'supabase') {
        $p = Join-Path $ShimDir $f
        '    {0,-14} {1}' -f $f, (Test-Path -LiteralPath $p)
    }
    Write-Host ''
    return
}

if ($Restaurer) {
    $kept = (Get-UserPath) -split ';' | Where-Object { $_ -and $_.TrimEnd('\') -ne $ShimDir.TrimEnd('\') }
    Set-UserPath ($kept -join ';')
    Write-Host '  Shim retire du PATH utilisateur.' -ForegroundColor Green
    Write-Host '  Les terminaux deja ouverts gardent l ancien PATH.' -ForegroundColor DarkGray
    return
}

foreach ($f in 'supabase.ps1', 'supabase.cmd', 'supabase') {
    if (-not (Test-Path -LiteralPath (Join-Path $ShimDir $f))) {
        throw "Fichier manquant : $f. Le depot est incomplet, installation interrompue."
    }
}

if (Test-Pose) {
    Write-Host '  Deja pose. Rien a faire.' -ForegroundColor DarkGray
    return
}

$backup = Join-Path $env:LOCALAPPDATA "DevContext\path-utilisateur-avant-shims.txt"
New-Item -ItemType Directory -Path (Split-Path $backup) -Force | Out-Null
Get-UserPath | Set-Content $backup -Encoding UTF8

Set-UserPath (@($ShimDir) + ((Get-UserPath) -split ';' | Where-Object { $_ })) -join ';'

Write-Host '  Shim pose en tete du PATH utilisateur.' -ForegroundColor Green
Write-Host "    $ShimDir"
Write-Host "  PATH d avant sauvegarde : $backup" -ForegroundColor DarkGray
Write-Host '  Les terminaux deja ouverts gardent l ancien PATH — en ouvrir un neuf.' -ForegroundColor Yellow
```

- [ ] **Étape 5 : lancer les tests**

```powershell
pwsh -NoProfile -File .\tests\RunTests.ps1
```

Attendu : tous verts.

- [ ] **Étape 6 : poser, puis vérifier depuis chaque shell**

```powershell
pwsh -NoProfile -File .\installer-shims.ps1
pwsh -NoProfile -File .\installer-shims.ps1 -Verifier
```

Puis, dans un **terminal neuf** :

```powershell
work perso -NoCd
Set-Location F:\PROJECTS\Apps\ankora-refonte
supabase --version          # doit repondre normalement
```

Et depuis **git-bash**, dans le même dossier — c'est le vecteur qui compte :

```bash
supabase --version
```

Attendu : la version s'affiche dans les deux cas. Aucun refus sur une commande
inoffensive.

- [ ] **Étape 7 : vérifier le blocage depuis git-bash**

C'est la vérification qui justifie tout le chantier : le shell qu'un agent
utilise.

```bash
cd /f/PROJECTS/Apps/ankora-refonte
supabase db reset --dry-run
echo "code de sortie : $?"
```

Attendu : bloc **REFUSE**, code de sortie **1**.

> Si git-bash ne trouve pas le shim, c'est que MSYS n'a pas résolu le fichier
> sans extension. Vérifier son bit exécutable :
> `git update-index --chmod=+x shims/supabase`

- [ ] **Étape 8 : commit**

```bash
git add installer-shims.ps1 tests/Installer.Tests.ps1
git commit -m "feat: add a reversible installer putting the shims first in PATH"
```

---

### Tâche 7 : filet de régression sur la résolution existante

Deux fonctions décident déjà, en production, à quel contexte et à quel compte
appartient un dossier. Elles ont été vérifiées **à la main** le 5 août 2026 et
jamais rejouées depuis. Le garde-fou s'appuie dessus : si elles se trompent, il
protège la mauvaise base.

**Fichiers :**
- Créer : `tests/ContextResolution.Tests.ps1`

**Interfaces :**
- Consomme : `Resolve-DevContextForPath`, `Get-CtxManifests`,
  `Resolve-CtxSupabaseKey`, `Resolve-CtxSupabaseRef`,
  `Get-CtxSupabaseIndexPath` (tous existants, aucun à créer).
- Produit : rien. Tâche de couverture pure — aucun code de production modifié.

- [ ] **Étape 1 : écrire les tests**

Créer `tests/ContextResolution.Tests.ps1` :

```powershell
BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '..' 'DevContext.psd1') -Force
}

Describe 'Resolve-DevContextForPath' {
    BeforeAll {
        $script:apps  = Join-Path $TestDrive 'PROJECTS' 'Apps'
        $script:autre = Join-Path $TestDrive 'PROJECTS' 'Apps-Autre'
        $script:sous  = Join-Path $script:apps 'client-a'
        New-Item -ItemType Directory -Force -Path $script:apps, $script:autre, $script:sous | Out-Null
    }

    It 'ne resout PAS Apps-Autre vers le contexte dont la racine est Apps' {
        # Le piege du prefixe. Sans le separateur final ajoute par
        # Get-NormalizedRoot, 'Apps-Autre' commence par 'Apps' et le garde-fou
        # dirait le contraire du vrai.
        InModuleScope DevContext -Parameters @{ apps = $script:apps; autre = $script:autre } {
            param($apps, $autre)
            Mock Get-CtxManifests {
                @(('{"name":"perso","root":"' + ($apps -replace '\\', '\\') + '"}') | ConvertFrom-Json)
            }
            Resolve-DevContextForPath -Path $autre | Should -BeNullOrEmpty
        }
    }

    It 'resout un dossier situe sous la racine' {
        InModuleScope DevContext -Parameters @{ apps = $script:apps; sous = $script:sous } {
            param($apps, $sous)
            Mock Get-CtxManifests {
                @(('{"name":"perso","root":"' + ($apps -replace '\\', '\\') + '"}') | ConvertFrom-Json)
            }
            (Resolve-DevContextForPath -Path $sous).name | Should -Be 'perso'
        }
    }

    It 'choisit la racine la plus longue quand deux contextes s imbriquent' {
        InModuleScope DevContext -Parameters @{ apps = $script:apps; sous = $script:sous } {
            param($apps, $sous)
            Mock Get-CtxManifests {
                @(
                    ('{"name":"perso","root":"'  + ($apps -replace '\\', '\\') + '"}') | ConvertFrom-Json
                    ('{"name":"client","root":"' + ($sous -replace '\\', '\\') + '"}') | ConvertFrom-Json
                )
            }
            (Resolve-DevContextForPath -Path $sous).name | Should -Be 'client'
        }
    }

    It 'rend null hors de toute racine connue' {
        InModuleScope DevContext -Parameters @{ apps = $script:apps } {
            param($apps)
            Mock Get-CtxManifests {
                @(('{"name":"perso","root":"' + ($apps -replace '\\', '\\') + '"}') | ConvertFrom-Json)
            }
            Resolve-DevContextForPath -Path $TestDrive | Should -BeNullOrEmpty
        }
    }

    It 'rend null quand aucun contexte n existe' {
        InModuleScope DevContext {
            Mock Get-CtxManifests { @() }
            Resolve-DevContextForPath -Path $TestDrive | Should -BeNullOrEmpty
        }
    }
}

Describe 'Resolve-CtxSupabaseKey' {
    BeforeAll {
        $script:ctxDir = Join-Path $TestDrive 'CTX' 'demo'
        New-Item -ItemType Directory -Path $script:ctxDir -Force | Out-Null
        @{ 'aaaa' = @{ key = 'supabase-token-2'; name = 'app-prod' } } |
            ConvertTo-Json -Depth 4 |
            Set-Content (Join-Path $script:ctxDir 'supabase-index.json') -Encoding UTF8

        $script:devctxAvant = $env:DEVCTX
        $env:DEVCTX = 'demo'
    }
    AfterAll {
        if ($script:devctxAvant) { $env:DEVCTX = $script:devctxAvant }
        else { Remove-Item Env:DEVCTX -ErrorAction SilentlyContinue }
    }

    It 'rend la cle du projet lie' {
        InModuleScope DevContext -Parameters @{ dir = $script:ctxDir } {
            param($dir)
            Mock Resolve-CtxSupabaseRef     { 'aaaa' }
            Mock Get-CtxSupabaseIndexPath   { Join-Path $dir 'supabase-index.json' }
            Resolve-CtxSupabaseKey | Should -Be 'supabase-token-2'
        }
    }

    It 'rend null quand le dossier est lie mais le projet absent de l index' {
        # Contrat explicite du code : l appelant doit alerter, jamais deviner.
        InModuleScope DevContext -Parameters @{ dir = $script:ctxDir } {
            param($dir)
            Mock Resolve-CtxSupabaseRef     { 'zzzz' }
            Mock Get-CtxSupabaseIndexPath   { Join-Path $dir 'supabase-index.json' }
            Resolve-CtxSupabaseKey | Should -BeNullOrEmpty
        }
    }

    It 'rend la cle par defaut quand le dossier n est lie a aucun projet' {
        InModuleScope DevContext {
            Mock Resolve-CtxSupabaseRef { $null }
            Resolve-CtxSupabaseKey | Should -Be 'supabase-token'
        }
    }

    It 'rend null quand l index n existe pas' {
        InModuleScope DevContext {
            Mock Resolve-CtxSupabaseRef   { 'aaaa' }
            Mock Get-CtxSupabaseIndexPath { Join-Path $TestDrive 'nulle-part.json' }
            Resolve-CtxSupabaseKey | Should -BeNullOrEmpty
        }
    }
}
```

- [ ] **Étape 2 : lancer les tests**

```powershell
pwsh -NoProfile -File .\tests\RunTests.ps1
```

Attendu : tous verts **du premier coup**. Ces tests décrivent un comportement
existant — ils ne sont pas en TDD, ils sont un filet.

> **Si l'un échoue, ne pas ajuster le test.** Un échec ici signifie que la
> résolution est fausse en production, donc que le garde-fou protégerait la
> mauvaise base. Comprendre la cause d'abord, corriger le code ensuite.

- [ ] **Étape 3 : commit**

```bash
git add tests/ContextResolution.Tests.ps1
git commit -m "test: cover context and supabase key resolution, including the prefix trap"
```

---

### Tâche 8 : documenter, et empêcher la rechute du 13 août

Le PATH devient le **quatrième** consommateur externe pointant sur ce dépôt par
chemin absolu. Les trois premiers ont cassé en silence le 13 août. Celui-ci doit
naître documenté.

**Fichiers :**
- Modifier : `INSTALLATION.md` (tableau des consommateurs externes, ligne 74)
- Modifier : `README.md` (commandes du quotidien, ligne 104 ; nouveau garde-fou)
- Modifier : `CHANGELOG.md` (nouvelle version)
- Modifier : `DevContext.psd1` (`ModuleVersion`)
- Créer : `tests/README.md`

- [ ] **Étape 1 : ajouter le quatrième consommateur externe**

Dans `INSTALLATION.md`, ajouter au tableau « Ce qui pointe vers ce dépôt depuis
l'extérieur » :

```markdown
| PATH utilisateur (`HKCU\Environment`) | `shims/` | relancer `installer-shims.ps1` **depuis le dépôt** |
```

Et compléter la commande de vérification de cette section :

```powershell
.\installer-shims.ps1 -Verifier
```

Remplacer aussi « **Trois autres choses référencent ce dossier** » par
« **Quatre autres choses** ».

- [ ] **Étape 2 : documenter les nouvelles commandes**

Dans `README.md`, ajouter à la liste des commandes du quotidien :

```powershell
ctx-sb           # quel projet Supabase sur quel compte, et qui est en prod
```

Puis insérer cette section après le garde-fou nº 3 :

```markdown
### Garde-fou nº 4 — la production ne se détruit pas par accident

`ctx` juge **qui tu es**. Il ne jugeait pas **ce que tu vas toucher**.

Le 13 août 2026, trois dossiers — `ankora`, `ankora-landing`, `ankora-refonte` —
visaient la même base `ankora-prod`. Ce sont trois *worktrees* du même dépôt,
donc partager la base est cohérent. Mais l'un portait 19 migrations contre 22
sur `main` : un `supabase db reset` depuis ce dossier aurait reconstruit la
production trois crans en arrière. `ctx` répondait GO, en toute bonne foi.

**Le marquage.** Chaque entrée de `supabase-index.json` porte désormais un champ
`env`. `sb-index` le devine d'après le nom du projet (`prod`, `staging`, `dev`…)
et pose `envSource: auto`. Corrige-le à la main et passe `envSource` à `manual`
— il ne sera plus jamais recalculé.

**Les règles.** Sur un projet marqué `prod` :

| Commande | Verdict |
|---|---|
| `db reset` | **refusée**, sans condition — elle détruit et recrée la base, ce qui n'a aucun usage légitime en production |
| `db push`, `migration repair`, `migration up` | refusées **hors de la branche par défaut** du dépôt |
| tout le reste | inchangé |

Hors dépôt git, branche par défaut indéterminable, index illisible ou projet
inconnu : **la commande passe**. Un garde-fou qui casse quand il hésite est un
garde-fou qu'on désinstalle.

**Forcer**, délibérément et pour une seule commande :

```powershell
$env:DEVCTX_ALLOW_PROD = 1
```

À ne jamais poser dans `$PROFILE` — ce serait retirer le garde-fou en croyant
le garder.

**Pourquoi ce contrôle n'est pas dans le wrapper PowerShell.** `supabase` y est
un simple alias : il n'existe que dans une session PowerShell ayant importé le
module. Il ne couvre ni git-bash, ni les scripts npm, ni `execFileSync` depuis
Node, ni un agent IA — c'est-à-dire aucun des appelants les plus susceptibles de
se tromper. Le contrôle vit donc dans `shims/`, posé en tête du **PATH**, seul
point de passage commun à tous les shells.

Vérifier qu'il est en place :

```powershell
.\installer-shims.ps1 -Verifier
```
```

- [ ] **Étape 3 : mettre à jour la section « ce qui est vérifié »**

Dans `README.md`, la section « Ce qui est vérifié, et ce qui ne l'est pas »
affirme aujourd'hui qu'aucun test automatique n'existe. Elle doit désormais
renvoyer vers `tests/` et indiquer comment les lancer :

```powershell
pwsh -File .\tests\RunTests.ps1
```

- [ ] **Étape 4 : écrire `tests/README.md`**

```markdown
# Tests

```powershell
pwsh -File .\tests\RunTests.ps1
```

## Pourquoi une version minimale de Pester

Windows livre **Pester 3.4.0** dans `System32`. Il n'est pas désinstallable et
sa syntaxe est incompatible avec Pester 5+. `RunTests.ps1` impose donc
`Import-Module Pester -MinimumVersion 5.0.0` plutôt que de se fier à la
résolution par défaut.

## Ce qu'aucun test ne fait

Aucun test n'accède au réseau, ne lit le coffre SecretStore, ni n'appelle
Supabase. Les index et arborescences sont montés sous `$TestDrive`, que Pester
détruit à la fin de chaque fichier.

C'est ce qui permet de les lancer n'importe où, y compris en intégration
continue, sans identité ni secret.

## Où vit la décision

`Test-CtxSupabaseGuard` est une fonction **pure** : tout ce dont elle a besoin
lui est passé en paramètre. C'est ce qui la rend testable seule, sans dépôt git,
sans index et sans contexte actif. Le shim se contente de rassembler ces
entrées.

## Si un test échoue

Comprendre la cause avant de toucher au code, et ne jamais ajuster l'attendu au
résultat obtenu. Ces tests décrivent des règles de sécurité : un test qui échoue
est une information, pas un obstacle.
```

- [ ] **Étape 5 : journaliser la version**

Dans `CHANGELOG.md`, insérer avant `## Avant le dépôt` (ajuster la date si
l'implémentation a lieu un autre jour) :

```markdown
## [1.1.0] — 13 août 2026

`ctx` jugeait qui tu es. Il juge désormais aussi ce que tu vas toucher.

### Ajouté

- **Garde-fou production.** Un shim placé en tête du PATH refuse les commandes
  Supabase irréversibles visant un projet marqué `prod`. `db reset` sans
  condition ; `db push`, `migration repair` et `migration up` hors de la branche
  par défaut du dépôt. Contournable pour une commande par
  `DEVCTX_ALLOW_PROD=1`.
- **Champ `env` dans `supabase-index.json`.** `sb-index` le devine d'après le
  nom du projet et pose `envSource: auto` ; une valeur passée à `manual` n'est
  plus jamais recalculée.
- **`ctx-sb`** : quel projet Supabase vit sur quel compte, lequel est en
  production, et quels dossiers pointent dessus. Signale tout projet visé par
  plus d'un dossier.
- **`installer-shims.ps1`** : pose, vérifie (`-Verifier`) et retire
  (`-Restaurer`) le dossier de shims du PATH utilisateur. Sans droits
  administrateur, réversible, avec sauvegarde du PATH d'avant.
- **Premiers tests automatiques** (Pester 6). Couvrent la décision du garde-fou,
  le marquage `env` et sa fusion, la résolution dossier → contexte — piège du
  préfixe compris — et la résolution ref → clé de secret. Aucun n'accède au
  réseau, au coffre ni à Supabase.

### Modifié

- `Update-DevSupabaseIndex` lit l'index existant avant de le reconstruire. Il
  l'écrasait intégralement : un `env` posé à la main n'aurait pas survécu au
  premier `sb-index`.
- Le binaire `supabase` est désormais résolu par `Get-CtxSupabaseExe`, qui
  exclut le dossier des shims. Sans cela, le shim se serait trouvé lui-même et
  aurait bouclé.

### Sécurité

Le 13 août 2026, `ankora`, `ankora-landing` et `ankora-refonte` — trois
*worktrees* du même dépôt — visaient tous `ankora-prod`. Partager la base est
cohérent puisque c'est la même application ; ce ne l'était pas que
`ankora-refonte` porte **19 migrations contre 22** sur `main`. Un
`supabase db reset` depuis ce dossier aurait reconstruit la production trois
crans en arrière, données comprises, avec `ctx` répondant GO.

Le contrôle est placé dans le **PATH**, jamais dans l'alias PowerShell. Un alias
ne couvre ni git-bash, ni les scripts npm, ni `execFileSync` depuis Node, ni un
agent IA — c'est-à-dire aucun des appelants les plus susceptibles de se tromper.
Le manque était déjà décrit dans le code depuis le 8 août
(`Sync-CtxSupabaseEnv`) sans avoir été comblé.

> **Un garde-fou qui ne couvre que l'appelant le plus prudent ne couvre rien.**
```

Dans `DevContext.psd1`, porter `ModuleVersion` à `1.1.0`.

- [ ] **Étape 6 : dernière passe complète**

```powershell
pwsh -NoProfile -File .\tests\RunTests.ps1
pwsh -NoProfile -File .\installer-shims.ps1 -Verifier
work perso -NoCd; ctx
```

Attendu : tous les tests verts, shim actif, `ctx` → GO.

- [ ] **Étape 7 : commit et tag**

```bash
git add INSTALLATION.md README.md CHANGELOG.md DevContext.psd1 tests/README.md
git commit -m "docs: document the production guard and its fourth external consumer"
git tag -a v1.1.0 -m "Production guard"
```

**Ne pas pousser** sans accord explicite de Thierry.

---

## Ce que ce plan ne fait pas

- **Vercel et GitHub.** Même principe, hors périmètre : l'inventaire du 13 août
  donne 4 projets Vercel pour 4 identifiants distincts, donc aucun recouvrement
  à protéger aujourd'hui.
- **Le portage macOS/Linux.** `Resolve-CtxSupabaseRef` (ligne 493) construit son
  chemin avec des antislashs littéraux (`'supabase\.temp\project-ref'`), ce qui
  ne résoudra pas sous POSIX. Dette réelle, chantier distinct.
- **Le `.gitattributes`.** Git signale déjà des conversions LF/CRLF. À traiter
  avec le portage, avant que des scripts shell partent en CRLF.
- **La comparaison des migrations entre branches.** Le critère retenu est la
  branche, pas le diff — calculable partout, sans configuration.
