# Les tests ci-dessous, ajoutes le 15 aout 2026 apres un audit de securite,
# couvrent une faille que la suite d'origine ne pouvait pas voir : elle
# n'eprouvait que des flags BOOLEENS. Or la CLI Supabase a six options globales
# qui prennent une VALEUR en argument separe, et cobra les accepte AVANT la
# commande. La valeur devenait alors le premier mot, decalait la fenetre de
# detection, et le garde-fou se taisait.
#
#   supabase db reset --linked                 -> refuse
#   supabase --workdir . db reset --linked      -> PASSAIT
#
Describe 'contournement par un flag global a valeur' {
    BeforeAll { Import-Module (Join-Path $PSScriptRoot '..' 'DevContext.psd1') -Force }

    # Les branches sont fournies parce que `db push`, `migration up` et
    # `migration repair` sont lies a la branche : sans elles, le garde-fou passe
    # DELIBEREMENT, et le test mesurerait ce comportement-la plutot que le
    # contournement qu'il vise.
    It 'refuse "<_>" en production' -ForEach @(
        '--workdir . db reset --linked'
        '-o json db push'
        '--profile monprofil db reset'
        '--dns-resolver native db reset'
        '--network-id reseau migration up'
        '--agent no db reset --linked'
        '--output json migration repair'
        # Forme --flag=valeur : la valeur ne devient pas un mot separe, mais on
        # verifie que la detection ne s'y perd pas non plus.
        '--workdir=. db reset'
        # Deux flags a valeur enchaines.
        '--workdir . --profile x db reset'
    ) {
        InModuleScope DevContext -Parameters @{ a = ($_ -split ' ') } { param($a)
            (Test-CtxSupabaseGuard -Arguments $a -Environment 'prod' `
                -CurrentBranch 'feat/chantier' -DefaultBranch 'main').Allowed | Should -BeFalse
        }
    }

    It 'laisse toujours passer une commande inoffensive avec les memes flags' {
        # La correction ne doit pas transformer « je ne comprends pas » en refus
        # general : ce serait rendre l outil insupportable.
        InModuleScope DevContext {
            (Test-CtxSupabaseGuard -Arguments ('--workdir . db pull' -split ' ') -Environment 'prod').Allowed |
                Should -BeTrue
            (Test-CtxSupabaseGuard -Arguments ('-o json projects list' -split ' ') -Environment 'prod').Allowed |
                Should -BeTrue
        }
    }

    It 'refuse meme si la valeur d un flag imite une commande racine' {
        # `--profile db db reset` : le mot « db » apparait deux fois, une fois
        # comme valeur de flag. Une detection ancree sur le premier mot connu
        # lirait « db db » et laisserait passer.
        InModuleScope DevContext {
            (Test-CtxSupabaseGuard -Arguments ('--profile db db reset' -split ' ') -Environment 'prod').Allowed |
                Should -BeFalse
        }
    }
}

Describe 'contournement par reciblage de la commande' {
    BeforeAll { Import-Module (Join-Path $PSScriptRoot '..' 'DevContext.psd1') -Force }

    It 'refuse db reset porteur d un --db-url, meme hors projet de production' {
        # Le garde-fou deduit la base du DOSSIER ; la CLI, elle, obeit a ses
        # flags. Une commande copiee d un runbook et lancee depuis le mauvais
        # dossier detruisait la prod sans un mot. C est le seul endroit ou le
        # fail-open coute trop cher : ici on refuse a defaut de savoir.
        InModuleScope DevContext {
            $r = Test-CtxSupabaseGuard -Arguments @('db', 'reset', '--db-url', 'postgresql://postgres.abc:pwd@x.pooler.supabase.com:5432/postgres') `
                -Environment 'dev' -IndexContientProd
            $r.Allowed | Should -BeFalse
            $r.Rule    | Should -Be 'cible-indeterminee'
        }
    }

    It 'ne refuse pas un --db-url quand l index ne contient aucune production' {
        InModuleScope DevContext {
            (Test-CtxSupabaseGuard -Arguments @('db', 'reset', '--db-url', 'postgresql://x') -Environment 'dev').Allowed |
                Should -BeTrue
        }
    }

    It 'ne refuse pas un --db-url sur une sous-commande non gardee' {
        InModuleScope DevContext {
            (Test-CtxSupabaseGuard -Arguments @('db', 'pull', '--db-url', 'postgresql://x') -Environment 'dev' -IndexContientProd).Allowed |
                Should -BeTrue
        }
    }
}

# Ce bloc s'appelait 'Get-CtxSupabaseCible' alors qu'il n'eprouvait ni cette
# fonction -- qui n'existait pas -- ni rien qui s'en approche. Renomme le
# 24 aout 2026 pour ce qu'il mesure vraiment, le nom etant desormais pris par
# une fonction reelle, juste en dessous.
Describe 'lecture des arguments Supabase' {
    BeforeAll { Import-Module (Join-Path $PSScriptRoot '..' 'DevContext.psd1') -Force }

    It 'extrait le project-ref d une URL de connexion directe' {
        InModuleScope DevContext {
            Get-CtxSupabaseRefDepuisUrl 'postgresql://postgres:pwd@db.abcdefghijklmnopqrst.supabase.co:5432/postgres' |
                Should -Be 'abcdefghijklmnopqrst'
        }
    }

    It 'extrait le project-ref d une URL de pooler' {
        InModuleScope DevContext {
            Get-CtxSupabaseRefDepuisUrl 'postgresql://postgres.abcdefghijklmnopqrst:pwd@aws-0-eu-central-1.pooler.supabase.com:5432/postgres' |
                Should -Be 'abcdefghijklmnopqrst'
        }
    }

    It 'rend null sur une URL dont on ne sait rien' {
        InModuleScope DevContext {
            Get-CtxSupabaseRefDepuisUrl 'postgresql://user:pwd@interne.exemple.local:5432/base' |
                Should -BeNullOrEmpty
        }
    }

    It 'lit la valeur d un --workdir sous ses deux formes' {
        InModuleScope DevContext {
            Get-CtxArgumentValeur @('--workdir', 'C:\projet', 'db', 'reset') 'workdir' | Should -Be 'C:\projet'
            Get-CtxArgumentValeur @('--workdir=C:\projet', 'db', 'reset') 'workdir'   | Should -Be 'C:\projet'
            Get-CtxArgumentValeur @('db', 'reset') 'workdir'                          | Should -BeNullOrEmpty
        }
    }
}

BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '..' 'DevContext.psd1') -Force
}

Describe 'Get-CtxSupabasePaires' {
    # Remplace Get-CtxSupabaseSubcommand, qui ne gardait que les DEUX premiers
    # mots non-option. Cette hypothese — « toute option est un booleen isole » —
    # etait fausse et exploitable ; voir le Describe en tete de fichier.
    It 'rend la paire d une commande simple' {
        InModuleScope DevContext {
            Get-CtxSupabasePaires @('db', 'reset') | Should -Be 'db reset'
        }
    }
    It 'ignore les options, ou qu elles soient' {
        InModuleScope DevContext {
            Get-CtxSupabasePaires @('--debug', 'db', 'reset', '--linked') | Should -Be 'db reset'
        }
    }
    It 'normalise la casse' {
        InModuleScope DevContext {
            Get-CtxSupabasePaires @('DB', 'Reset') | Should -Be 'db reset'
        }
    }
    It 'rend toutes les paires adjacentes, pas seulement la premiere' {
        # C est la propriete qui ferme le contournement : la valeur d un flag
        # decale les mots, mais la paire gardee reste presente quelque part.
        InModuleScope DevContext {
            $p = @(Get-CtxSupabasePaires @('--workdir', '.', 'db', 'reset'))
            $p | Should -Contain 'db reset'
            $p.Count | Should -Be 2
        }
    }
    It 'ne rend rien sans argument, ni avec un seul mot' {
        InModuleScope DevContext {
            @(Get-CtxSupabasePaires @()).Count        | Should -Be 0
            @(Get-CtxSupabasePaires @('db')).Count    | Should -Be 0
        }
    }
}

Describe 'Test-CtxSupabaseGuard — hors production' {
    It 'laisse passer db reset quand le projet est marque dev' {
        $r = Test-CtxSupabaseGuard -Arguments @('db', 'reset') -Environment 'dev' `
             -CurrentBranch 'feat/x' -DefaultBranch 'main'
        $r.Allowed | Should -BeTrue
    }
    It 'laisse passer db reset quand l environnement est inconnu' {
        $r = Test-CtxSupabaseGuard -Arguments @('db', 'reset') -Environment $null `
             -CurrentBranch 'feat/x' -DefaultBranch 'main'
        $r.Allowed | Should -BeTrue
    }
}

Describe 'Test-CtxSupabaseGuard — db reset en production' {
    It 'refuse, quelle que soit la branche' {
        $r = Test-CtxSupabaseGuard -Arguments @('db', 'reset') -Environment 'prod' `
             -CurrentBranch 'main' -DefaultBranch 'main'
        $r.Allowed | Should -BeFalse
        $r.Rule    | Should -Be 'db-reset-prod'
    }
    It 'refuse aussi hors depot git' {
        $r = Test-CtxSupabaseGuard -Arguments @('db', 'reset') -Environment 'prod' `
             -CurrentBranch $null -DefaultBranch $null
        $r.Allowed | Should -BeFalse
    }
    It 'laisse passer si le contournement explicite est pose' {
        $r = Test-CtxSupabaseGuard -Arguments @('db', 'reset') -Environment 'prod' `
             -CurrentBranch 'main' -DefaultBranch 'main' -Override
        $r.Allowed | Should -BeTrue
        $r.Rule    | Should -Be 'override'
    }
}

Describe 'Test-CtxSupabaseGuard — db push en production' {
    It 'laisse passer depuis la branche par defaut' {
        $r = Test-CtxSupabaseGuard -Arguments @('db', 'push') -Environment 'prod' `
             -CurrentBranch 'main' -DefaultBranch 'main'
        $r.Allowed | Should -BeTrue
    }
    It 'refuse depuis une autre branche' {
        $r = Test-CtxSupabaseGuard -Arguments @('db', 'push') -Environment 'prod' `
             -CurrentBranch 'feat/pwa-start-url-cockpit' -DefaultBranch 'main'
        $r.Allowed | Should -BeFalse
        $r.Rule    | Should -Be 'branch-mismatch'
    }
    It 'laisse passer si la branche par defaut est indeterminable' {
        $r = Test-CtxSupabaseGuard -Arguments @('db', 'push') -Environment 'prod' `
             -CurrentBranch 'feat/x' -DefaultBranch $null
        $r.Allowed | Should -BeTrue
    }
    It 'laisse passer hors depot git' {
        $r = Test-CtxSupabaseGuard -Arguments @('db', 'push') -Environment 'prod' `
             -CurrentBranch $null -DefaultBranch 'main'
        $r.Allowed | Should -BeTrue
    }
    It 'applique la meme regle a migration repair' {
        $r = Test-CtxSupabaseGuard -Arguments @('migration', 'repair') -Environment 'prod' `
             -CurrentBranch 'feat/x' -DefaultBranch 'main'
        $r.Allowed | Should -BeFalse
    }
    It 'applique la meme regle a migration up' {
        $r = Test-CtxSupabaseGuard -Arguments @('migration', 'up') -Environment 'prod' `
             -CurrentBranch 'feat/x' -DefaultBranch 'main'
        $r.Allowed | Should -BeFalse
    }
}

Describe 'Test-CtxSupabaseGuard — commandes hors liste noire' {
    It 'laisse passer db pull en production depuis une branche quelconque' {
        $r = Test-CtxSupabaseGuard -Arguments @('db', 'pull') -Environment 'prod' `
             -CurrentBranch 'feat/x' -DefaultBranch 'main'
        $r.Allowed | Should -BeTrue
    }
    It 'laisse passer db dump en production' {
        (Test-CtxSupabaseGuard -Arguments @('db', 'dump') -Environment 'prod' `
         -CurrentBranch 'feat/x' -DefaultBranch 'main').Allowed | Should -BeTrue
    }
    It 'laisse passer gen types en production' {
        (Test-CtxSupabaseGuard -Arguments @('gen', 'types') -Environment 'prod' `
         -CurrentBranch 'feat/x' -DefaultBranch 'main').Allowed | Should -BeTrue
    }
    It 'laisse passer une invocation sans argument' {
        (Test-CtxSupabaseGuard -Arguments @() -Environment 'prod' `
         -CurrentBranch 'feat/x' -DefaultBranch 'main').Allowed | Should -BeTrue
    }
    It 'laisse passer projects list' {
        (Test-CtxSupabaseGuard -Arguments @('projects', 'list', '-o', 'json') -Environment 'prod' `
         -CurrentBranch 'feat/x' -DefaultBranch 'main').Allowed | Should -BeTrue
    }
}

# ---------------------------------------------------------------------------
# 24 aout 2026 -- le faux positif le plus couteux du garde-fou.
#
# `db reset` vise la base LOCALE par defaut ; la CLI l'ecrit elle-meme. Le
# garde-fou ne lisait que `--db-url` et refusait donc `db reset --local` dans
# tout dossier lie a une production, sur toutes les branches. Quatre refus
# mesures ce jour-la, un seul vrai positif.
# ---------------------------------------------------------------------------

Describe 'Get-CtxSupabaseCible' {
    BeforeAll { Import-Module (Join-Path $PSScriptRoot '..' 'DevContext.psd1') -Force }

    It '"<ligne>" vise <attendu>' -ForEach @(
        # Aucun drapeau de cible : c'est la CLI qui decidera, pas nous.
        @{ ligne = 'db reset';                                  attendu = 'aucune' }
        @{ ligne = 'db reset --local';                          attendu = 'locale' }
        @{ ligne = 'db reset --linked';                         attendu = 'liee' }
        @{ ligne = 'db push --local --dry-run';                 attendu = 'locale' }
        @{ ligne = 'migration up --local --include-all';        attendu = 'locale' }
        @{ ligne = 'db reset --db-url postgresql://x';          attendu = 'url' }
        @{ ligne = 'db reset --db-url=postgresql://x';          attendu = 'url' }

        # Combinaisons que la CLI 2.109.1 refuse elle-meme, mesure du
        # 24 aout 2026. On ne s'y fie pas : elles doivent deja etre illisibles
        # ICI, sans quoi la regle dependrait d'une version de la CLI.
        @{ ligne = 'db reset --local --linked';                 attendu = 'ambigue' }
        @{ ligne = 'db reset --local --db-url postgresql://x';  attendu = 'ambigue' }
        @{ ligne = 'db reset --linked --db-url=postgresql://x'; attendu = 'ambigue' }

        # Ecritures booleennes de cobra. `--local=false` dit le CONTRAIRE du
        # drapeau nu : le lire comme une cible locale serait le seul faux
        # laissez-passer possible dans cette fonction.
        @{ ligne = 'db reset --local=true';                     attendu = 'locale' }
        @{ ligne = 'db reset --local=false';                    attendu = 'aucune' }
        @{ ligne = 'db reset --local=oui';                      attendu = 'ambigue' }

        # La valeur d'une option n'est pas un drapeau : cobra consomme le mot
        # suivant, et la commande part alors sur la cible par DEFAUT.
        @{ ligne = 'db reset --profile --local';                attendu = 'aucune' }
        @{ ligne = '--workdir --local db reset';                attendu = 'aucune' }
        @{ ligne = 'db push -p --local';                        attendu = 'aucune' }
        # ... alors que la forme --option=valeur ne consomme rien.
        @{ ligne = 'db reset --profile=x --local';              attendu = 'locale' }

        # Cobra distingue la casse : `--LOCAL` lui est un drapeau inconnu.
        @{ ligne = 'db reset --LOCAL';                          attendu = 'aucune' }
        # Repete, un drapeau reste le meme drapeau.
        @{ ligne = 'db reset --local --local';                  attendu = 'locale' }
    ) {
        InModuleScope DevContext -Parameters @{ a = ($ligne -split ' '); att = $attendu } {
            param($a, $att)
            Get-CtxSupabaseCible $a | Should -Be $att
        }
    }
}

Describe 'Test-CtxSupabaseGuard — une cible locale n est pas une production' {
    BeforeAll { Import-Module (Join-Path $PSScriptRoot '..' 'DevContext.psd1') -Force }

    # Branche LATERALE et index contenant une production : le cas le plus
    # defavorable. Avant le 24 aout 2026 les quatre lignes etaient refusees.
    It 'laisse passer "<_>" sur un projet de production' -ForEach @(
        'db reset --local'
        'db push --local'
        'migration up --local'
        'migration repair --local'
    ) {
        InModuleScope DevContext -Parameters @{ a = ($_ -split ' ') } { param($a)
            $r = Test-CtxSupabaseGuard -Arguments $a -Environment 'prod' `
                -CurrentBranch 'feat/chantier' -DefaultBranch 'main' -IndexContientProd
            $r.Allowed | Should -BeTrue
            $r.Rule    | Should -Be 'cible-locale'
        }
    }

    It 'refuse toujours "<_>" — la cible n est pas certaine' -ForEach @(
        # Le contournement que la regle conjonctive existe pour fermer : un
        # `if (--local) { passe }` naif aurait laisse partir celui-ci.
        'db reset --local --db-url postgresql://postgres.abcdefghijklmnopqrst:x@aws-0.pooler.supabase.com:5432/postgres'
        'db reset --local --linked'
        'db reset --local=false'
        # Un profil nomme '--local' n'a aucune forme realiste, mais nous ne
        # savons pas lire cette ligne : faute de certitude, on refuse.
        'db reset --profile --local'
        # Sans drapeau, la cible depend du DEFAUT de la CLI -- une propriete de
        # sa version, pas de la commande. Le refus reste.
        'db reset'
        'db reset --linked'
    ) {
        InModuleScope DevContext -Parameters @{ a = ($_ -split ' ') } { param($a)
            (Test-CtxSupabaseGuard -Arguments $a -Environment 'prod' `
                -CurrentBranch 'feat/chantier' -DefaultBranch 'main' -IndexContientProd).Allowed |
                Should -BeFalse
        }
    }

    It 'ne desarme pas le garde-fou des qu un --local traine dans les arguments' {
        # `--local` porte par une AUTRE commande de la ligne ne doit rien
        # ouvrir : ici il n y a qu une commande, et elle est gardee.
        InModuleScope DevContext {
            $r = Test-CtxSupabaseGuard -Arguments @('--workdir', '--local', 'db', 'reset') `
                -Environment 'prod' -CurrentBranch 'main' -DefaultBranch 'main' -IndexContientProd
            $r.Allowed | Should -BeFalse
            $r.Rule    | Should -Be 'db-reset-prod'
        }
    }
}
