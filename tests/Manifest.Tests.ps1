# This file deliberately does NOT import the module.
#
# It checks the things that decide whether the module CAN load at all. A test
# that imports what it is verifying proves nothing when that import is the
# broken part: on 13 Aug 2026 a double hyphen inside an XML comment made the
# manifest refuse the whole module, and the format tests -- which lived beside
# an Import-Module -- went down with everything else instead of pointing at the
# cause.

BeforeAll {
    $script:Root       = Split-Path $PSScriptRoot -Parent
    $script:Manifest   = Join-Path $script:Root 'DevContext.psd1'
    $script:FormatFile = Join-Path $script:Root 'DevContext.format.ps1xml'
}

Describe 'manifeste' {
    It 'est lisible sans charger le module' {
        { Import-PowerShellDataFile $script:Manifest } | Should -Not -Throw
    }

    It 'porte une version semantique' {
        $m = Import-PowerShellDataFile $script:Manifest
        $m.ModuleVersion | Should -Match '^\d+\.\d+\.\d+$'
    }

    It 'reference tous les fichiers qu il declare' {
        $m = Import-PowerShellDataFile $script:Manifest
        foreach ($f in @($m.RootModule) + @($m.FormatsToProcess)) {
            if ($f) { Test-Path (Join-Path $script:Root $f) | Should -BeTrue -Because "$f est declare" }
        }
    }

    It 'exporte les memes fonctions que le module' {
        # The real export is the intersection of psd1 and psm1. Adding a
        # function to only one makes it silently invisible: no error, just a
        # command that cannot be found.
        $m    = Import-PowerShellDataFile $script:Manifest
        $psm1 = Get-Content (Join-Path $script:Root 'DevContext.psm1') -Raw

        if ($psm1 -match '(?s)\$exportedFunctions\s*=\s*@\((.*?)\)') {
            $declarees = ([regex]::Matches($Matches[1], "'([^']+)'") | ForEach-Object { $_.Groups[1].Value })
            foreach ($f in $m.FunctionsToExport) {
                $declarees | Should -Contain $f -Because "$f est dans le manifeste"
            }
            foreach ($f in $declarees) {
                $m.FunctionsToExport | Should -Contain $f -Because "$f est dans le psm1"
            }
        }
        else { throw "Bloc exportedFunctions introuvable dans DevContext.psm1" }
    }

    It 'exporte les memes alias que le module' {
        $m    = Import-PowerShellDataFile $script:Manifest
        $psm1 = Get-Content (Join-Path $script:Root 'DevContext.psm1') -Raw

        if ($psm1 -match '(?s)\$exportedAliases\s*=\s*@\((.*?)\)') {
            $declares = ([regex]::Matches($Matches[1], "'([^']+)'") | ForEach-Object { $_.Groups[1].Value })
            foreach ($a in $m.AliasesToExport) {
                $declares | Should -Contain $a -Because "$a est dans le manifeste"
            }
            foreach ($a in $declares) {
                $m.AliasesToExport | Should -Contain $a -Because "$a est dans le psm1"
            }
        }
        else { throw "Bloc exportedAliases introuvable dans DevContext.psm1" }
    }
}

Describe 'fichier de format' {
    It 'existe' {
        Test-Path $script:FormatFile | Should -BeTrue
    }

    It 'est un XML valide' {
        # A malformed format file does not merely break a layout: the manifest
        # refuses to load the module, and work/ctx stop existing.
        { [xml](Get-Content $script:FormatFile -Raw) } | Should -Not -Throw
    }

    It 'ne contient pas de double tiret dans un commentaire' {
        # The exact mistake of 13 Aug 2026, named so the next reader sees it.
        $xml = [xml](Get-Content $script:FormatFile -Raw)
        foreach ($c in $xml.SelectNodes('//comment()')) {
            $c.Value | Should -Not -Match '--'
        }
    }

    It 'declare une vue table pour <_>' -ForEach @(
        'DevContext.SupabaseMapEntry'
        'DevContext.DoctorCheck'
    ) {
        # Chaque type publie doit avoir la sienne : sans vue, PowerShell bascule
        # en liste des la cinquieme propriete, et une sortie lue un paragraphe
        # par ligne n'est plus lue jusqu'au bout.
        $type = $_
        $xml  = [xml](Get-Content $script:FormatFile -Raw)
        $vue  = @($xml.Configuration.ViewDefinitions.View |
                  Where-Object { $_.ViewSelectedBy.TypeName -eq $type })
        $vue.Count        | Should -Be 1 -Because "$type doit avoir exactement une vue"
        $vue[0].TableControl | Should -Not -BeNullOrEmpty
    }

    It 'est reference par le manifeste' {
        # Without this the file is inert and the layout silently reverts to a
        # list, the exact failure this view exists to prevent.
        (Import-PowerShellDataFile $script:Manifest).FormatsToProcess |
            Should -Contain 'DevContext.format.ps1xml'
    }
}
