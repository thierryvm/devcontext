# Reading the vault: "this context has no such secret" is not
# "the vault could not be read".
#
# Until 1.11.1, Get-CtxSecret called Get-Secret with -ErrorAction
# SilentlyContinue, and every failure came back as $null -- which every caller
# reads as "no such secret". Measured on 27 September 2026: three parallel
# reads of the SecretStore vault in one process, two of them failed with
# `Unable to get secret ... from vault DevContext`, and nothing said so. `work`
# then announced a context with a token silently missing.
#
# The shape of that failure was measured before this file was written, on
# SecretManagement 1.1.2 / SecretStore 1.0.6, and it is what the fakes below
# reproduce:
#
#   absent name      ONE non-terminating error, GetSecretNotFound
#                    (ItemNotFoundException, ObjectNotFound)
#   concurrent read  TWO non-terminating errors: GetSecretInvalidOperation
#                    (inner: "a pipeline is already running"), THEN
#                    GetSecretNotFound
#   absent vault     a TERMINATING GetSecretVaultNotFound, which
#                    -ErrorAction SilentlyContinue does not stop
#
# The second line is the trap: a rule of "it says not found, so it is absent"
# reproduces the defect exactly. Absent means EVERY error is GetSecretNotFound.
#
# The real vault is never touched: Get-Secret is mocked inside the module.

BeforeAll {
    $script:Module = (Resolve-Path (Join-Path $PSScriptRoot '..' 'DevContext.psd1')).Path
    Import-Module $script:Module -Force

    # Restore, never remove: clearing a real variable in a `finally` once
    # disarmed a leak test that ran later (AGENTS.md).
    # The secret variables come FROM the module's table, never a copy of it: a
    # key added there must not leave a variable this file forgets to restore.
    $script:VariablesTouchees = @(
        'DEVCTX', 'DEVCTX_LABEL', 'DEVCTX_DIR', 'DEVCTX_ROOT_PATH', 'DEVCTX_GH_LOGIN',
        'GH_CONFIG_DIR', 'DEVCTX_VERCEL_CONFIG', 'VERCEL_ORG_ID', 'DEVCTX_VERCEL_SCOPE',
        'DEVCTX_SUPABASE_KEY'
    ) + @(InModuleScope DevContext { $script:SecretMap.Values })
    function Save-CtxTestEnv {
        $copie = @{}
        foreach ($n in $script:VariablesTouchees) {
            $copie[$n] = [Environment]::GetEnvironmentVariable($n, 'Process')
        }
        $copie
    }
    function Restore-CtxTestEnv($Copie) {
        foreach ($n in $Copie.Keys) {
            [Environment]::SetEnvironmentVariable($n, $Copie[$n], 'Process')
        }
    }
}

Describe 'Get-CtxSecret -- absent versus unreadable' {
    BeforeEach {
        # The retry waits are real sleeps in production; here they would only
        # slow the suite down.
        Mock Start-Sleep {} -ModuleName DevContext
    }

    It 'rend la valeur quand le coffre la fournit' {
        Mock Get-Secret { 'valeur-factice' } -ModuleName DevContext
        InModuleScope DevContext {
            Get-CtxSecret -Name 'demo' -Key 'github-token' | Should -Be 'valeur-factice'
        }
    }

    It 'lit le bon nom, dans le bon coffre, en clair' {
        # The fakes below answer whatever they are asked. Without this, a typo
        # in the key contract would turn every secret into "absent" -- in
        # silence, the very class of defect this file exists for.
        Mock Get-Secret { 'valeur-factice' } -ModuleName DevContext
        InModuleScope DevContext { $null = Get-CtxSecret -Name 'demo' -Key 'github-token' }
        Should -Invoke Get-Secret -ModuleName DevContext -Times 1 -Exactly -ParameterFilter {
            $Vault -eq 'DevContext' -and $Name -eq 'devctx/demo/github-token' -and $AsPlainText
        }
    }

    It 'leve aussi quand la panne arrive APRES le not found -- la regle ne depend pas de l ordre' {
        Mock Get-Secret {
            Write-Error -Exception ([System.Management.Automation.ItemNotFoundException]::new("The secret $Name was not found.")) `
                -ErrorId 'GetSecretNotFound' -Category ObjectNotFound
            Write-Error -Exception ([System.Management.Automation.PSInvalidOperationException]::new("Unable to get secret $Name from vault DevContext")) `
                -ErrorId 'GetSecretInvalidOperation' -Category InvalidOperation
        } -ModuleName DevContext
        InModuleScope DevContext {
            { Get-CtxSecret -Name 'demo' -Key 'github-token' } | Should -Throw -ErrorId 'DevCtxSecretIllisible*'
        }
    }

    It 'une erreur TERMINALE n est jamais une preuve d absence, meme si elle dit not found' {
        # The real cmdlet reports an absent name as NON-terminating. A
        # terminating one is a fault of the call itself; its id proves nothing.
        Mock Get-Secret {
            throw [System.Management.Automation.ErrorRecord]::new(
                [System.Management.Automation.ItemNotFoundException]::new('nf'), 'GetSecretNotFound',
                [System.Management.Automation.ErrorCategory]::ObjectNotFound, $null)
        } -ModuleName DevContext
        InModuleScope DevContext {
            { Get-CtxSecret -Name 'demo' -Key 'github-token' } | Should -Throw -ErrorId 'DevCtxSecretIllisible*'
        }
    }

    It 'ne reessaie pas une erreur terminale -- un coffre absent du registre ne reviendra pas en 250 ms' {
        Mock Get-Secret {
            throw [System.Management.Automation.PSInvalidOperationException]::new('Vault not found in registry: DevContext')
        } -ModuleName DevContext
        InModuleScope DevContext {
            { Get-CtxSecret -Name 'demo' -Key 'github-token' } | Should -Throw -ErrorId 'DevCtxSecretIllisible*'
        }
        Should -Invoke Get-Secret -ModuleName DevContext -Times 1 -Exactly
    }

    It 'leve quand le coffre ne rend RIEN sans aucune erreur -- l absence doit se prouver' {
        # The real cmdlet always says GetSecretNotFound for an absent name. A
        # read that answers nothing at all is not that answer: ambiguous,
        # never absent.
        Mock Get-Secret { } -ModuleName DevContext
        InModuleScope DevContext {
            { Get-CtxSecret -Name 'demo' -Key 'github-token' } | Should -Throw -ErrorId 'DevCtxSecretIllisible*'
        }
    }

    It 'rend $null quand la seule erreur est GetSecretNotFound -- le secret est absent' {
        Mock Get-Secret {
            Write-Error -Exception ([System.Management.Automation.ItemNotFoundException]::new("The secret $Name was not found.")) `
                -ErrorId 'GetSecretNotFound' -Category ObjectNotFound
        } -ModuleName DevContext
        InModuleScope DevContext {
            Get-CtxSecret -Name 'demo' -Key 'github-token' | Should -BeNullOrEmpty
        }
        Should -Invoke Get-Secret -ModuleName DevContext -Times 1 -Exactly
    }

    It 'leve quand le coffre echoue PUIS dit not found -- la forme mesuree de la lecture concurrente' {
        Mock Get-Secret {
            Write-Error -Exception ([System.Management.Automation.PSInvalidOperationException]::new("Unable to get secret $Name from vault DevContext")) `
                -ErrorId 'GetSecretInvalidOperation' -Category InvalidOperation
            Write-Error -Exception ([System.Management.Automation.ItemNotFoundException]::new("The secret $Name was not found.")) `
                -ErrorId 'GetSecretNotFound' -Category ObjectNotFound
        } -ModuleName DevContext

        $erreur = InModuleScope DevContext {
            try { Get-CtxSecret -Name 'demo' -Key 'github-token'; $null } catch { $_ }
        }
        $erreur | Should -Not -BeNullOrEmpty -Because 'a $null here is the defect itself'
        $erreur.FullyQualifiedErrorId | Should -BeLike 'DevCtxSecretIllisible*'
        $erreur.TargetObject | Should -Be 'github-token'
        $erreur.Exception.Message | Should -Match 'github-token'
    }

    It 'leve quand Get-Secret leve malgre SilentlyContinue -- coffre absent du registre' {
        Mock Get-Secret {
            throw [System.Management.Automation.PSInvalidOperationException]::new('Vault not found in registry: DevContext')
        } -ModuleName DevContext

        $erreur = InModuleScope DevContext {
            try { Get-CtxSecret -Name 'demo' -Key 'vercel-token'; $null } catch { $_ }
        }
        $erreur.FullyQualifiedErrorId | Should -BeLike 'DevCtxSecretIllisible*'
        $erreur.TargetObject | Should -Be 'vercel-token'
    }

    It 'reessaie une lecture concurrente et rend la valeur obtenue au troisieme essai' {
        $script:essais = 0
        Mock Get-Secret {
            $script:essais++
            if ($script:essais -lt 3) {
                Write-Error -Exception ([System.Management.Automation.PSInvalidOperationException]::new("Unable to get secret $Name from vault DevContext")) `
                    -ErrorId 'GetSecretInvalidOperation' -Category InvalidOperation
                return
            }
            'valeur-factice'
        } -ModuleName DevContext

        InModuleScope DevContext {
            Get-CtxSecret -Name 'demo' -Key 'github-token' | Should -Be 'valeur-factice'
        }
        Should -Invoke Get-Secret -ModuleName DevContext -Times 3 -Exactly
    }

    It 'borne les essais : un coffre qui echoue toujours leve apres un nombre fixe de lectures' {
        Mock Get-Secret {
            Write-Error -Exception ([System.Management.Automation.PSInvalidOperationException]::new('A valid password is required to access the vault.')) `
                -ErrorId 'GetSecretInvalidOperation' -Category InvalidOperation
        } -ModuleName DevContext

        $attendu = InModuleScope DevContext { $script:SecretLectureDelaisMs.Count + 1 }
        $attendu | Should -BeGreaterThan 1 -Because 'a single attempt is no retry'
        $attendu | Should -BeLessOrEqual 4 -Because 'an unbounded retry turns a locked vault into a hang'

        InModuleScope DevContext {
            { Get-CtxSecret -Name 'demo' -Key 'github-token' } | Should -Throw -ErrorId 'DevCtxSecretIllisible*'
        }
        Should -Invoke Get-Secret -ModuleName DevContext -Times $attendu -Exactly
    }

    It 'ne reessaie pas un secret absent -- l absence est une reponse, pas une panne' {
        Mock Get-Secret {
            Write-Error -Exception ([System.Management.Automation.ItemNotFoundException]::new("The secret $Name was not found.")) `
                -ErrorId 'GetSecretNotFound' -Category ObjectNotFound
        } -ModuleName DevContext
        InModuleScope DevContext { $null = Get-CtxSecret -Name 'demo' -Key 'github-token' }
        Should -Invoke Start-Sleep -ModuleName DevContext -Times 0 -Exactly
    }

    It 'caviarde un jeton que la cause d erreur porterait' {
        # Nothing in SecretStore is known to quote a value in an error. The
        # message passes through Protect-CtxMessage anyway, because "is known
        # to" is what leaked a bypass token into a URL on 24 April 2026.
        #
        # The value is ASSEMBLED, never written: GitHub's push protection reads
        # a fake token of the right shape as a real one, and refused the push.
        Mock Get-Secret {
            Write-Error -Exception ([System.Management.Automation.PSInvalidOperationException]::new(('decrypt failed near ' + 'sbp' + '_' + ('0123456789abcdef' * 3) + '01234567'))) `
                -ErrorId 'GetSecretInvalidOperation' -Category InvalidOperation
        } -ModuleName DevContext

        $erreur = InModuleScope DevContext {
            try { Get-CtxSecret -Name 'demo' -Key 'supabase-token'; $null } catch { $_ }
        }
        $erreur.Exception.Message | Should -Not -Match 'sbp_0123456789abcdef'
        $erreur.Exception.Message | Should -Match 'supabase-token'
    }
}

Describe 'work -- une cle illisible ne passe plus pour une cle absente' {
    BeforeEach {
        $script:envAvant = Save-CtxTestEnv
        $script:titreAvant = try { $Host.UI.RawUI.WindowTitle } catch { $null }

        Mock Start-Sleep {} -ModuleName DevContext
        Mock Test-CtxVault {} -ModuleName DevContext
        Mock Read-CtxManifest {
            [pscustomobject]@{ name = 'demo'; label = 'Demo'; email = 'demo@exemple.com' }
        } -ModuleName DevContext
        Mock Get-CtxPath { 'C:\inexistant\demo' } -ModuleName DevContext
        Mock Sync-CtxSupabaseEnv {} -ModuleName DevContext

        # Every key is readable except github-token, whose read fails the way
        # a concurrent read was measured to fail.
        Mock Get-Secret {
            if ($Name -like '*/github-token') {
                Write-Error -Exception ([System.Management.Automation.PSInvalidOperationException]::new("Unable to get secret $Name from vault DevContext")) `
                    -ErrorId 'GetSecretInvalidOperation' -Category InvalidOperation
                Write-Error -Exception ([System.Management.Automation.ItemNotFoundException]::new("The secret $Name was not found.")) `
                    -ErrorId 'GetSecretNotFound' -Category ObjectNotFound
                return
            }
            if ($Name -like '*/vercel-token') { return 'valeur-vercel-factice' }
            Write-Error -Exception ([System.Management.Automation.ItemNotFoundException]::new("The secret $Name was not found.")) `
                -ErrorId 'GetSecretNotFound' -Category ObjectNotFound
        } -ModuleName DevContext
    }
    AfterEach {
        Restore-CtxTestEnv $script:envAvant
        if ($null -ne $script:titreAvant) { try { $Host.UI.RawUI.WindowTitle = $script:titreAvant } catch { } }
    }

    It 'echoue -- $? faux, un `work x && cmd` ne part pas' {
        # Its own id, not the per-key one: one id carrying two shapes of record
        # is the same question answered in two places.
        { InModuleScope DevContext { Use-DevContext -Name 'demo' -NoCd 6>$null } } |
            Should -Throw -ErrorId 'DevCtxActivationIncomplete*'
    }

    It 'nomme la variable illisible dans l erreur, jamais une valeur' {
        $erreur = InModuleScope DevContext {
            try { Use-DevContext -Name 'demo' -NoCd 6>$null; $null } catch { $_ }
        }
        $erreur.Exception.Message | Should -Match 'GH_TOKEN'
        $erreur.Exception.Message | Should -Not -Match 'valeur-vercel-factice'
    }

    It 'efface la variable illisible : aucune valeur d un autre contexte ne survit' {
        # The direction that matters. Before `work demo`, the shell held another
        # context's token. If the read fails and the variable is left alone,
        # the next command runs under the PREVIOUS account.
        $env:GH_TOKEN = 'jeton-du-contexte-precedent'
        InModuleScope DevContext { try { Use-DevContext -Name 'demo' -NoCd 6>$null } catch { } }
        $env:GH_TOKEN | Should -BeNullOrEmpty
    }

    It 'interrompu pendant une lecture, ne laisse aucun jeton du contexte precedent' {
        # Ctrl+C at a password prompt, or during a retry wait, is a pipeline
        # stop: no catch sees it. Measured by the audit of 29 October 2026,
        # and older than the secret-read fix: the shell said B and held A's
        # tokens. Any exception escaping mid-loop takes the same path.
        # A real stop cannot be raised inside Pester without stopping Pester,
        # and Get-CtxSecret turns every vault fault into its own error. So the
        # escape is staged one level up: an exception that is not a vault
        # fault, leaving the loop halfway.
        Mock Get-CtxSecret {
            if ($Key -eq 'vercel-token') { throw [System.OperationCanceledException]::new('interrompu') }
            'valeur-demo-factice'
        } -ModuleName DevContext
        $env:VERCEL_TOKEN          = 'jeton-a-vercel'
        $env:SUPABASE_ACCESS_TOKEN = 'jeton-a-supabase'
        $env:SUPABASE_DB_PASSWORD  = 'jeton-a-db'
        $env:SENTRY_READ_TOKEN     = 'jeton-a-sentry'
        $env:DEVCTX_SUPABASE_KEY   = 'supabase-token-a'

        InModuleScope DevContext { try { Use-DevContext -Name 'demo' -NoCd 6>$null } catch { } }

        foreach ($n in 'VERCEL_TOKEN', 'SUPABASE_ACCESS_TOKEN', 'SUPABASE_DB_PASSWORD', 'SENTRY_READ_TOKEN', 'DEVCTX_SUPABASE_KEY') {
            [Environment]::GetEnvironmentVariable($n, 'Process') | Should -Not -BeLike 'jeton-a-*' -Because "$n belongs to the previous context"
            [Environment]::GetEnvironmentVariable($n, 'Process') | Should -Not -Be 'supabase-token-a' -Because "$n belongs to the previous context"
        }
    }

    It 'charge malgre tout les cles lisibles' {
        InModuleScope DevContext { try { Use-DevContext -Name 'demo' -NoCd 6>$null } catch { } }
        $env:VERCEL_TOKEN | Should -Be 'valeur-vercel-factice'
        $env:DEVCTX | Should -Be 'demo'
    }

    It 'echoue aussi quand c est le jeton Supabase du dossier qui est illisible' {
        Mock Get-Secret {
            Write-Error -Exception ([System.Management.Automation.ItemNotFoundException]::new("The secret $Name was not found.")) `
                -ErrorId 'GetSecretNotFound' -Category ObjectNotFound
        } -ModuleName DevContext
        Mock Sync-CtxSupabaseEnv {
            # A mock body runs in the TEST's scope, where the module's private
            # functions do not exist: build the record in the module's.
            throw (& (Get-Module DevContext) { New-CtxSecretIllisibleError -Key 'supabase-token-b' -Cause 'Unable to get secret' })
        } -ModuleName DevContext

        $erreur = InModuleScope DevContext {
            try { Use-DevContext -Name 'demo' -NoCd 6>$null; $null } catch { $_ }
        }
        $erreur.FullyQualifiedErrorId | Should -BeLike 'DevCtxActivationIncomplete*'
        $erreur.Exception.Message | Should -Match 'SUPABASE_ACCESS_TOKEN'
    }

    It 'n annonce pas parmi les secrets charges un jeton Supabase que Sync vient d effacer' {
        Mock Get-Secret {
            if ($Name -like '*/supabase-token') { return 'valeur-supabase-factice' }
            Write-Error -Exception ([System.Management.Automation.ItemNotFoundException]::new("The secret $Name was not found.")) `
                -ErrorId 'GetSecretNotFound' -Category ObjectNotFound
        } -ModuleName DevContext
        Mock Sync-CtxSupabaseEnv {
            Remove-Item Env:SUPABASE_ACCESS_TOKEN -ErrorAction SilentlyContinue
            throw (& (Get-Module DevContext) { New-CtxSecretIllisibleError -Key 'supabase-token-b' -Cause 'Unable to get secret' })
        } -ModuleName DevContext

        # @() at the CALL site: one line crossing InModuleScope arrives as a bare
        # string, and [0] then reads its first CHARACTER -- a space, which never
        # matches. That kept this test green on the very defect it names.
        $lignes = @(InModuleScope DevContext {
            # T does not substitute an empty string: format with a marker, cut it.
            $prefixe = ((T 'work.secrets' 'MARQUEUR') -replace 'MARQUEUR', '').Trim()
            # -InformationVariable, not 6>&1: an assignment never happens when
            # the command throws, and this one does.
            $flux = $null
            try { Use-DevContext -Name 'demo' -NoCd -InformationVariable flux 6>$null } catch { }
            @($flux | ForEach-Object { "$_" } | Where-Object { $_.Trim().StartsWith($prefixe) })
        })
        $lignes.Count | Should -Be 1
        $lignes[0] | Should -Not -Match 'SUPABASE_ACCESS_TOKEN'
    }

    It 'ne signale pas illisible un jeton Supabase que Sync a finalement charge' {
        # The loop's read of supabase-token failed, then Sync -- which owns the
        # folder's token -- read it fine. Failing here would block `work x &&
        # cmd` on a token that IS loaded, with a message saying it was cleared.
        Mock Get-Secret {
            if ($Name -like '*/supabase-token') {
                Write-Error -Exception ([System.Management.Automation.PSInvalidOperationException]::new("Unable to get secret $Name from vault DevContext")) `
                    -ErrorId 'GetSecretInvalidOperation' -Category InvalidOperation
                return
            }
            Write-Error -Exception ([System.Management.Automation.ItemNotFoundException]::new("The secret $Name was not found.")) `
                -ErrorId 'GetSecretNotFound' -Category ObjectNotFound
        } -ModuleName DevContext
        Mock Sync-CtxSupabaseEnv {
            $env:SUPABASE_ACCESS_TOKEN = 'valeur-du-dossier-factice'
            $env:DEVCTX_SUPABASE_KEY   = 'supabase-token'
        } -ModuleName DevContext

        { InModuleScope DevContext { Use-DevContext -Name 'demo' -NoCd 6>$null } } | Should -Not -Throw
        $env:SUPABASE_ACCESS_TOKEN | Should -Be 'valeur-du-dossier-factice'
    }

    It 'n annonce pas charge un jeton Supabase que Sync a efface parce que le secret du dossier est ABSENT' {
        # A stale index: the folder's key resolves, the vault has no such
        # secret, Sync clears the token without raising. Listing it as loaded
        # would announce a token the next command does not have -- and the CLI
        # would fall back on its own global login.
        Mock Get-Secret {
            if ($Name -like '*/supabase-token') { return 'valeur-supabase-factice' }
            Write-Error -Exception ([System.Management.Automation.ItemNotFoundException]::new("The secret $Name was not found.")) `
                -ErrorId 'GetSecretNotFound' -Category ObjectNotFound
        } -ModuleName DevContext
        Mock Sync-CtxSupabaseEnv {
            Remove-Item Env:SUPABASE_ACCESS_TOKEN -ErrorAction SilentlyContinue
            Remove-Item Env:DEVCTX_SUPABASE_KEY   -ErrorAction SilentlyContinue
        } -ModuleName DevContext

        $lignes = @(InModuleScope DevContext {
            $prefixe = ((T 'work.secrets' 'MARQUEUR') -replace 'MARQUEUR', '').Trim()
            $flux = $null
            Use-DevContext -Name 'demo' -NoCd -InformationVariable flux 6>$null
            @($flux | ForEach-Object { "$_" } | Where-Object { $_.Trim().StartsWith($prefixe) })
        })
        $lignes.Count | Should -Be 1
        $lignes[0] | Should -Not -Match 'SUPABASE_ACCESS_TOKEN'
    }

    It 'refuse un manifeste dont le nom n est pas celui de son dossier' {
        # The loop read devctx/<folder>/*, Sync read devctx/<manifest name>/*:
        # one shell, two contexts' tokens. Measured by the audit of 30 October
        # 2026 on a hand-copied context folder.
        Mock Read-CtxManifest {
            [pscustomobject]@{ name = 'autre'; label = 'Autre'; email = 'autre@exemple.com' }
        } -ModuleName DevContext
        $env:DEVCTX = 'contexte-precedent'
        { InModuleScope DevContext { Use-DevContext -Name 'demo' -NoCd 6>$null } } | Should -Throw
        $env:DEVCTX | Should -Be 'contexte-precedent' -Because 'nothing may be applied from a manifest that names another context'
        Should -Invoke Get-Secret -ModuleName DevContext -Times 0 -Exactly
    }

    It 'efface les jetons precedents meme quand le coffre manque a l appel' {
        # If Test-CtxVault throws, the editor shim catches it and opens the
        # editor anyway: with the previous context's tokens, unless they are
        # already gone.
        Mock Test-CtxVault { throw 'SecretManagement absent' } -ModuleName DevContext
        $env:GH_TOKEN = 'jeton-du-contexte-precedent'
        InModuleScope DevContext { try { Use-DevContext -Name 'demo' -NoCd 6>$null } catch { } }
        $env:GH_TOKEN | Should -BeNullOrEmpty
    }

    It 'reste silencieux et reussit quand les cles sont simplement absentes' {
        Mock Get-Secret {
            Write-Error -Exception ([System.Management.Automation.ItemNotFoundException]::new("The secret $Name was not found.")) `
                -ErrorId 'GetSecretNotFound' -Category ObjectNotFound
        } -ModuleName DevContext
        { InModuleScope DevContext { Use-DevContext -Name 'demo' -NoCd 6>$null } } | Should -Not -Throw
    }
}

Describe 'Sync-CtxSupabaseEnv -- efface d abord, signale ensuite' {
    BeforeEach {
        $script:envAvant = Save-CtxTestEnv
        Mock Start-Sleep {} -ModuleName DevContext
        Mock Resolve-CtxSupabaseKey { 'supabase-token-b' } -ModuleName DevContext
        Mock Get-Secret {
            Write-Error -Exception ([System.Management.Automation.PSInvalidOperationException]::new("Unable to get secret $Name from vault DevContext")) `
                -ErrorId 'GetSecretInvalidOperation' -Category InvalidOperation
        } -ModuleName DevContext
        $env:DEVCTX = 'demo'
        # Left by the folder the user just came FROM.
        $env:SUPABASE_ACCESS_TOKEN = 'jeton-du-projet-precedent'
        $env:DEVCTX_SUPABASE_KEY   = 'supabase-token'
    }
    AfterEach { Restore-CtxTestEnv $script:envAvant }

    It 'leve une erreur de lecture, pas un silence' {
        { InModuleScope DevContext { Sync-CtxSupabaseEnv -Path 'C:\inexistant' } } |
            Should -Throw -ErrorId 'DevCtxSecretIllisible*'
    }

    It 'a efface le jeton du projet precedent AVANT de lever' {
        # Raising before clearing would be worse than the silence it replaces:
        # after `cd` from project A to project B, A's token would stay loaded.
        InModuleScope DevContext { try { Sync-CtxSupabaseEnv -Path 'C:\inexistant' } catch { } }
        $env:SUPABASE_ACCESS_TOKEN | Should -BeNullOrEmpty
        $env:DEVCTX_SUPABASE_KEY   | Should -BeNullOrEmpty
    }
}

Describe 'Sync-CtxSupabaseEnv -- un arret (Ctrl+C) efface aussi' {
    # A pipeline stop runs no catch, only finally: the audit of 30 October
    # 2026 measured that the clear-before-raise above did not run on Ctrl+C at
    # a vault prompt, and the previous folder's token stayed. A stop cannot be
    # raised inside Pester without stopping Pester, so this runs in a child.
    It 'le jeton du dossier precedent ne survit pas a un arret pendant la lecture' {
        $module = (Resolve-Path (Join-Path $PSScriptRoot '..' 'DevContext.psd1')).Path
        $code = @"
`$env:DEVCTX = 'demo'
`$env:SUPABASE_ACCESS_TOKEN = 'jeton-du-projet-precedent'
`$env:DEVCTX_SUPABASE_KEY = 'supabase-token'
Import-Module '$module' -Force
& (Get-Module DevContext) {
    function script:Resolve-CtxSupabaseKey { param(`$Path, `$Contexte) 'supabase-token-b' }
    function script:Get-CtxSecret { param(`$Name, `$Key) throw [System.Management.Automation.PipelineStoppedException]::new() }
}
try { & (Get-Module DevContext) { Sync-CtxSupabaseEnv -Path 'C:\inexistant' } }
finally { 'JETON=' + [bool]`$env:SUPABASE_ACCESS_TOKEN + ' CLE=' + [bool]`$env:DEVCTX_SUPABASE_KEY }
"@
        $sortie = (pwsh -NoProfile -Command $code 2>$null) -join "`n"
        $sortie | Should -Match 'JETON=False CLE=False'
    }
}

Describe 'le hook de changement de dossier -- un avertissement, pas un journal verbeux' {
    It 'un vrai changement de dossier passe par la fonction testee ci-dessous' {
        # The hook is a delegate nobody can call from a test, so its body lives
        # in a function. This is what ties the two: without it, the hook could
        # stop calling that function and every test below would stay green.
        Mock Sync-CtxSupabaseEnvSurDeplacement {} -ModuleName DevContext
        Push-Location $TestDrive
        Pop-Location
        Should -Invoke Sync-CtxSupabaseEnvSurDeplacement -ModuleName DevContext -Times 1
    }

    It 'avertit quand le jeton du nouveau dossier est illisible, sans casser la session' {
        Mock Sync-CtxSupabaseEnv {
            # A mock body runs in the TEST's scope, where the module's private
            # functions do not exist: build the record in the module's.
            throw (& (Get-Module DevContext) { New-CtxSecretIllisibleError -Key 'supabase-token-b' -Cause 'Unable to get secret' })
        } -ModuleName DevContext

        $resultat = InModuleScope DevContext {
            $leve = $false
            $flux = @()
            try { $flux = @(Sync-CtxSupabaseEnvSurDeplacement 3>&1) }
            catch { $leve = $true }
            [pscustomobject]@{ Leve = $leve; Avertissements = @($flux | Where-Object { $_ -is [System.Management.Automation.WarningRecord] }) }
        }
        $resultat.Leve | Should -BeFalse -Because 'this code runs on EVERY cd'
        $resultat.Avertissements.Count | Should -Be 1
        $resultat.Avertissements[0].Message | Should -Match 'supabase-token-b'
    }

    It 'ne casse pas le cd meme quand les avertissements sont promus en erreur' {
        # $WarningPreference = 'Stop' turns a Write-Warning into a raise, from
        # INSIDE the catch that promised never to break a cd.
        Mock Sync-CtxSupabaseEnv {
            throw (& (Get-Module DevContext) { New-CtxSecretIllisibleError -Key 'supabase-token-b' -Cause 'Unable to get secret' })
        } -ModuleName DevContext
        $leve = InModuleScope DevContext {
            $WarningPreference = 'Stop'
            try { Sync-CtxSupabaseEnvSurDeplacement 3>$null; $false } catch { $true }
        }
        $leve | Should -BeFalse
    }

    It 'une autre panne reste un journal verbeux : ni avertissement, ni levee' {
        Mock Sync-CtxSupabaseEnv { throw 'index illisible' } -ModuleName DevContext
        $resultat = InModuleScope DevContext {
            $leve = $false
            $flux = @()
            try { $flux = @(Sync-CtxSupabaseEnvSurDeplacement 3>&1) } catch { $leve = $true }
            [pscustomobject]@{ Leve = $leve; Avertissements = @($flux | Where-Object { $_ -is [System.Management.Automation.WarningRecord] }).Count }
        }
        $resultat.Leve | Should -BeFalse
        $resultat.Avertissements | Should -Be 0
    }
}

Describe 'alias supabase -- un jeton illisible ne lance pas la CLI' {
    BeforeAll {
        $script:temoin = Join-Path $TestDrive 'leurre-appele.txt'
        $script:leurre = Join-Path $TestDrive 'supabase-leurre.ps1'
        "Set-Content -LiteralPath '$($script:temoin)' -Value 'LEURRE-APPELE'" | Set-Content $script:leurre -Encoding UTF8
        $script:index = Join-Path $TestDrive 'supabase-index.json'
        @{ 'refdemo0000000000000' = @{ key = 'supabase-token-b'; name = 'demo-app'; env = 'dev'; envSource = 'auto' } } |
            ConvertTo-Json -Depth 4 | Set-Content $script:index -Encoding UTF8
    }
    BeforeEach {
        $script:envAvant = Save-CtxTestEnv
        Remove-Item -LiteralPath $script:temoin -ErrorAction SilentlyContinue
        $env:DEVCTX = 'demo'
        Mock Start-Sleep {} -ModuleName DevContext
        Mock Resolve-CtxSupabaseVerdict { $null } -ModuleName DevContext
        Mock Get-CtxSupabaseExe { $script:leurre } -ModuleName DevContext
        Mock Resolve-CtxSupabaseRef { 'refdemo0000000000000' } -ModuleName DevContext
        Mock Get-CtxSupabaseIndexPath { $script:index } -ModuleName DevContext
        Mock Get-Secret {
            Write-Error -Exception ([System.Management.Automation.PSInvalidOperationException]::new("Unable to get secret $Name from vault DevContext")) `
                -ErrorId 'GetSecretInvalidOperation' -Category InvalidOperation
        } -ModuleName DevContext
    }
    AfterEach { Restore-CtxTestEnv $script:envAvant }

    It 'le leurre n est pas appele' {
        # Before: the token came back $null and the CLI ran with whatever
        # SUPABASE_ACCESS_TOKEN the shell held -- the account `work` loaded for
        # ANOTHER project, or the CLI's own global login.
        InModuleScope DevContext { try { Invoke-DevSupabase projects list 6>$null } catch { } }
        Test-Path -LiteralPath $script:temoin | Should -BeFalse
    }

    It 'leve l erreur de lecture' {
        { InModuleScope DevContext { Invoke-DevSupabase projects list 6>$null } } |
            Should -Throw -ErrorId 'DevCtxSecretIllisible*'
    }
}

Describe 'sb-index -- une cle illisible ne reecrit pas l index' {
    # Measured by the audit of 29 October 2026 on 1.11.1: one unreadable key
    # was skipped like an absent one, and the rebuilt index lost every project
    # of that account -- its `env: prod` tag with it. The production guard
    # judges a project by that tag, so it stopped guarding them, in silence.
    BeforeAll {
        $script:leurreIndex = Join-Path $TestDrive 'supabase-liste.ps1'
        "'[{""id"":""refa000000000000000a"",""name"":""appli-a""}]'" | Set-Content $script:leurreIndex -Encoding UTF8
        $script:indexSb = Join-Path $TestDrive 'index-sb.json'
    }
    BeforeEach {
        $script:envAvant = Save-CtxTestEnv
        @{
            'refa000000000000000a' = @{ key = 'supabase-token';   name = 'appli-a'; env = 'dev';  envSource = 'auto' }
            'refb000000000000000b' = @{ key = 'supabase-token-b'; name = 'appli-b'; env = 'prod'; envSource = 'manual' }
        } | ConvertTo-Json -Depth 4 | Set-Content $script:indexSb -Encoding UTF8
        $script:indexAvant = Get-Content $script:indexSb -Raw

        Mock Start-Sleep {} -ModuleName DevContext
        Mock Get-CtxSupabaseExe { $script:leurreIndex } -ModuleName DevContext
        Mock Get-CtxSupabaseKeys { 'supabase-token', 'supabase-token-b' } -ModuleName DevContext
        Mock Get-CtxSupabaseIndexPath { $script:indexSb } -ModuleName DevContext
        Mock Get-Secret {
            if ($Name -like '*/supabase-token-b') {
                Write-Error -Exception ([System.Management.Automation.PSInvalidOperationException]::new("Unable to get secret $Name from vault DevContext")) `
                    -ErrorId 'GetSecretInvalidOperation' -Category InvalidOperation
                return
            }
            'valeur-a-factice'
        } -ModuleName DevContext
        $env:SUPABASE_ACCESS_TOKEN = 'jeton-avant-sb-index'
    }
    AfterEach { Restore-CtxTestEnv $script:envAvant }

    It 'leve l erreur de lecture' {
        { InModuleScope DevContext { Update-DevSupabaseIndex -Name 'demo' 6>$null } } |
            Should -Throw -ErrorId 'DevCtxSecretIllisible*'
    }

    It 'laisse l index intact -- l etiquette prod du compte illisible survit' {
        InModuleScope DevContext { try { Update-DevSupabaseIndex -Name 'demo' 6>$null } catch { } }
        Get-Content $script:indexSb -Raw | Should -Be $script:indexAvant
    }

    It 'rend le jeton qu il avait trouve' {
        InModuleScope DevContext { try { Update-DevSupabaseIndex -Name 'demo' 6>$null } catch { } }
        $env:SUPABASE_ACCESS_TOKEN | Should -Be 'jeton-avant-sb-index'
    }
}
