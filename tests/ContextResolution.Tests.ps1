# Filet de regression sur les deux fonctions qui decident, en production, a quel
# contexte et a quel compte appartient un dossier.
#
# Elles n'avaient ete verifiees qu'a LA MAIN, le 5 aout 2026. C'est le pire
# endroit du depot ou laisser ce vide : Resolve-DevContextForPath arme desormais
# le garde-fou production ET le shim, donc une regression ici ne casse pas un
# affichage, elle rouvre en silence la porte que tout le reste ferme.
#
# Aucun de ces tests ne touche au disque : Get-CtxManifests est simule, ce qui
# isole la DECISION de l'etat de la machine qui les execute.

BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '..' 'DevContext.psd1') -Force
}

Describe 'Resolve-DevContextForPath' {
    BeforeAll {
        $script:Faux = {
            @(
                [pscustomobject]@{ name = 'perso';   email = 'p@x.be'; root = 'F:\PROJECTS\Apps' }
                [pscustomobject]@{ name = 'client';  email = 'c@y.com'; root = 'F:\PROJECTS\Clients\acme' }
                [pscustomobject]@{ name = 'imbrique'; email = 'i@z.io'; root = 'F:\PROJECTS\Apps\special' }
            )
        }
    }

    It 'resout un dossier vers le contexte qui le contient' {
        InModuleScope DevContext -Parameters @{ f = $script:Faux } { param($f)
            Mock Get-CtxManifests $f
            (Resolve-DevContextForPath -Path 'F:\PROJECTS\Apps\demo-app').name | Should -Be 'perso'
        }
    }

    It 'ne confond PAS un dossier voisin dont le nom commence pareil' {
        # Le piege du prefixe. Sans separateur final, 'F:\PROJECTS\Apps'
        # matcherait aussi 'F:\PROJECTS\Apps-Autre', et le garde-fou dirait le
        # contraire du vrai — en accordant a un dossier l'identite d'un autre.
        InModuleScope DevContext -Parameters @{ f = $script:Faux } { param($f)
            Mock Get-CtxManifests $f
            Resolve-DevContextForPath -Path 'F:\PROJECTS\Apps-Autre\projet' | Should -BeNullOrEmpty
        }
    }

    It 'ne confond pas non plus au niveau du dossier lui-meme' {
        InModuleScope DevContext -Parameters @{ f = $script:Faux } { param($f)
            Mock Get-CtxManifests $f
            Resolve-DevContextForPath -Path 'F:\PROJECTS\Apps-Autre' | Should -BeNullOrEmpty
        }
    }

    It 'la racine la plus longue gagne sur un contexte imbrique' {
        InModuleScope DevContext -Parameters @{ f = $script:Faux } { param($f)
            Mock Get-CtxManifests $f
            (Resolve-DevContextForPath -Path 'F:\PROJECTS\Apps\special\projet').name |
                Should -Be 'imbrique'
        }
    }

    It 'resout la racine du contexte elle-meme' {
        InModuleScope DevContext -Parameters @{ f = $script:Faux } { param($f)
            Mock Get-CtxManifests $f
            (Resolve-DevContextForPath -Path 'F:\PROJECTS\Apps').name | Should -Be 'perso'
        }
    }

    It 'ignore la casse, comme le systeme de fichiers Windows' {
        InModuleScope DevContext -Parameters @{ f = $script:Faux } { param($f)
            Mock Get-CtxManifests $f
            (Resolve-DevContextForPath -Path 'f:\projects\APPS\demo-app').name | Should -Be 'perso'
        }
    }

    It 'tolere un antislash final' {
        InModuleScope DevContext -Parameters @{ f = $script:Faux } { param($f)
            Mock Get-CtxManifests $f
            (Resolve-DevContextForPath -Path 'F:\PROJECTS\Apps\demo-app\').name | Should -Be 'perso'
        }
    }

    It 'rend null hors de toute racine connue' {
        InModuleScope DevContext -Parameters @{ f = $script:Faux } { param($f)
            Mock Get-CtxManifests $f
            Resolve-DevContextForPath -Path 'C:\Windows' | Should -BeNullOrEmpty
        }
    }

    It 'rend null quand aucun contexte n existe' {
        InModuleScope DevContext {
            Mock Get-CtxManifests { @() }
            Resolve-DevContextForPath -Path 'F:\PROJECTS\Apps\x' | Should -BeNullOrEmpty
        }
    }

    It 'ignore un manifeste sans racine plutot que de lever' {
        InModuleScope DevContext {
            Mock Get-CtxManifests { @([pscustomobject]@{ name = 'casse'; email = 'x@y.z' }) }
            { Resolve-DevContextForPath -Path 'F:\PROJECTS\Apps\x' } | Should -Not -Throw
        }
    }

    It 'resout un chemin inexistant sans lever' {
        # Resolve-Path echoue sur un dossier absent ; la resolution doit rester
        # possible, ne serait-ce que pour diagnostiquer une faute de frappe.
        InModuleScope DevContext -Parameters @{ f = $script:Faux } { param($f)
            Mock Get-CtxManifests $f
            (Resolve-DevContextForPath -Path 'F:\PROJECTS\Apps\jamais-cree').name | Should -Be 'perso'
        }
    }
}

Describe 'Get-NormalizedRoot' {
    It 'pose un separateur final sur <_>' -ForEach @(
        'F:\PROJECTS\Apps', 'F:\PROJECTS\Apps\', 'F:\PROJECTS\Apps/'
    ) {
        InModuleScope DevContext -Parameters @{ p = $_ } { param($p)
            Get-NormalizedRoot $p | Should -Be 'F:\PROJECTS\Apps\'
        }
    }
}

Describe 'Resolve-CtxSupabaseRef' {
    BeforeAll {
        $script:racine = Join-Path $TestDrive 'projet'
        New-Item -ItemType Directory -Path (Join-Path $script:racine 'supabase\.temp') -Force | Out-Null
        Set-Content (Join-Path $script:racine 'supabase\.temp\project-ref') "  refavecespaces000000 `n" -NoNewline
        New-Item -ItemType Directory -Path (Join-Path $script:racine 'apps\web\src') -Force | Out-Null
    }

    It 'trouve le ref a la racine du projet' {
        InModuleScope DevContext -Parameters @{ r = $script:racine } { param($r)
            Resolve-CtxSupabaseRef -Path $r | Should -Be 'refavecespaces000000'
        }
    }

    It 'remonte l arborescence depuis un sous-dossier profond' {
        # Indispensable : on travaille depuis apps/web, pas depuis la racine.
        InModuleScope DevContext -Parameters @{ r = $script:racine } { param($r)
            Resolve-CtxSupabaseRef -Path (Join-Path $r 'apps\web\src') | Should -Be 'refavecespaces000000'
        }
    }

    It 'rend null hors de tout projet lie' {
        InModuleScope DevContext -Parameters @{ t = $TestDrive } { param($t)
            Resolve-CtxSupabaseRef -Path $t | Should -BeNullOrEmpty
        }
    }

    It 'rend null sur un chemin inexistant, sans boucler' {
        InModuleScope DevContext {
            Resolve-CtxSupabaseRef -Path 'Z:\nexiste\pas' | Should -BeNullOrEmpty
        }
    }

    It 'rejette un contenu qui n a pas la forme d un project-ref : <_>' -ForEach @(
        'abcdefghijklmnopqrst" & calc.exe & "'
        'trop-court'
        'AVECDESMAJUSCULES000'
        'abcdefghijklmnopqrstu'
        '../../autre-projet'
        '$(Get-Secret)'
    ) {
        # supabase/.temp/project-ref appartient au DEPOT : son contenu est choisi
        # par qui a fabrique le depot. Il ressortait tel quel dans les `args`
        # d un `npx` inscrit par `ctx mcp` — une commande que l assistant relance
        # a chaque demarrage, depuis un fichier fait pour etre commite.
        # Releve par l audit de securite du 15 aout 2026.
        InModuleScope DevContext -Parameters @{ v = $_; t = $TestDrive } { param($v, $t)
            $d = Join-Path $t ('hostile-' + [guid]::NewGuid().ToString('N').Substring(0, 6))
            New-Item -ItemType Directory -Path (Join-Path $d 'supabase\.temp') -Force | Out-Null
            Set-Content (Join-Path $d 'supabase\.temp\project-ref') $v -NoNewline
            Resolve-CtxSupabaseRef -Path $d | Should -BeNullOrEmpty
        }
    }

    It 'accepte un project-ref au format reel' {
        InModuleScope DevContext -Parameters @{ t = $TestDrive } { param($t)
            $d = Join-Path $t 'projet-valide'
            New-Item -ItemType Directory -Path (Join-Path $d 'supabase\.temp') -Force | Out-Null
            Set-Content (Join-Path $d 'supabase\.temp\project-ref') 'fkscabcdefghijklmnop' -NoNewline
            Resolve-CtxSupabaseRef -Path $d | Should -Be 'fkscabcdefghijklmnop'
        }
    }
}

Describe 'Get-CtxVerdictDossier' {
    # Ce comportement n'avait AUCUN test jusqu'au 19 aout 2026, et c'est
    # exactement pour cela que `ctx` et `ctx doctor` ont pu se contredire sur le
    # meme fait sans que rien ne rougisse.

    It 'rend <Attendu> pour proprietaire=<P> et actif=<A>' -ForEach @(
        @{ P = 'perso'; A = 'perso'; Attendu = 'accord' }
        @{ P = 'goldteam'; A = 'perso'; Attendu = 'dossierAutre' }
        @{ P = 'goldteam'; A = ''; Attendu = 'dossierSansActif' }
        @{ P = ''; A = 'perso'; Attendu = 'sansProprietaire' }
        @{ P = ''; A = ''; Attendu = 'neutre' }
    ) {
        InModuleScope DevContext -Parameters @{ p = $P; a = $A; attendu = $Attendu } {
            param($p, $a, $attendu)
            Get-CtxVerdictDossier -Proprietaire $p -Actif $a | Should -Be $attendu
        }
    }

    It 'traite $null comme une absence, pas comme un nom' {
        InModuleScope DevContext {
            Get-CtxVerdictDossier -Proprietaire $null -Actif 'perso' | Should -Be 'sansProprietaire'
            Get-CtxVerdictDossier -Proprietaire 'perso' -Actif $null | Should -Be 'dossierSansActif'
            Get-CtxVerdictDossier -Proprietaire $null -Actif $null | Should -Be 'neutre'
            Get-CtxVerdictDossier -Proprietaire '   ' -Actif 'perso' | Should -Be 'sansProprietaire'
        }
    }

    It 'ne confond pas un dossier SANS proprietaire avec un dossier d un AUTRE contexte' {
        # LE correctif du 19 aout 2026, en une assertion. Les deux etats etaient
        # confondus parce qu'un contexte n'a qu'UNE racine : « hors de ma
        # racine » etait lu comme « appartient a quelqu'un d'autre ». Le premier
        # ne croise rien et ne doit pas refuser ; le second refuse toujours.
        InModuleScope DevContext {
            $sansProprio = Get-CtxVerdictDossier -Proprietaire '' -Actif 'perso'
            $autre = Get-CtxVerdictDossier -Proprietaire 'goldteam' -Actif 'perso'

            $sansProprio | Should -Not -Be $autre
            $sansProprio | Should -Be 'sansProprietaire'
            $autre | Should -Be 'dossierAutre' -Because 'le vrai croisement doit toujours refuser'
        }
    }

    It 'ne rend jamais un etat que Test-DevContext ne sait pas traiter' {
        # Un etat inconnu tomberait dans aucune branche du switch appelant : ni
        # refus, ni remarque, ni rien -- un silence qu'aucun test ne verrait.
        InModuleScope DevContext {
            $connus = @('accord', 'dossierSansActif', 'dossierAutre', 'sansProprietaire', 'neutre')
            foreach ($p in @('', 'perso', 'goldteam', $null)) {
                foreach ($a in @('', 'perso', 'goldteam', $null)) {
                    $connus | Should -Contain (Get-CtxVerdictDossier -Proprietaire $p -Actif $a)
                }
            }
        }
    }
}

Describe 'Test-DevContext, sur un dossier que personne ne possede' {
    It 'appelle la remarque, jamais un probleme' {
        # Le canal compte autant que l'etat : range dans $problems, ce constat
        # redeviendrait un NO-GO. La source est lue plutot que la sortie, parce
        # que faire tourner `ctx` en test demanderait git, gh et une racine de
        # contextes -- trois choses absentes d'un agent de CI.
        InModuleScope DevContext {
            $source = (Get-Command Test-DevContext).ScriptBlock.ToString()

            $source | Should -Match "'sansProprietaire'\s*\{\s*\`$remarques"
            $source | Should -Not -Match "'sansProprietaire'\s*\{\s*\`$problems"
        }
    }

    It 'n annonce pas un accord de dossier qu il n a pas mesure' {
        # Le GO habituel affirme « identite, dossier et compte concordent ». Sans
        # proprietaire, cette phrase affirme un accord avec quelqu un qui n
        # existe pas -- deux lignes au-dessus d une remarque qui dit le
        # contraire. Meme raison d etre que 'ctx.goSansCompte'.
        InModuleScope DevContext {
            (Get-Command Test-DevContext).ScriptBlock.ToString() |
                Should -Match "ctx\.goSansProprietaire"

            foreach ($langue in @('fr', 'en')) {
                $cle = Import-PowerShellDataFile -LiteralPath (
                    Join-Path (Split-Path (Get-Module DevContext).Path -Parent) "lang/$langue.psd1")
                $cle.Keys | Should -Contain 'ctx.goSansProprietaire'
                $cle.Keys | Should -Contain 'ctx.note.sansProprietaire'
                $cle.Keys | Should -Not -Contain 'ctx.pb.horsRacine'
            }
        }
    }
}
