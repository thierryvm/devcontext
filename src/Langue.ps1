# ---------------------------------------------------------------------------
# Langue — la sortie parle celle de son lecteur
# ---------------------------------------------------------------------------
#
# LE PROBLEME
#
# La documentation est en anglais, la sortie des commandes en francais. Un
# developpeur a Berlin qui installe ce module lit un README qu'il comprend, puis
# recoit des refus et des diagnostics dans une langue qu'il ne parle peut-etre
# pas. C'est l'incoherence la plus visible du projet, et celle qui fait
# desinstaller a la premiere execution.
#
# TROIS REGLES
#
# 1. DEVCTX_LANG a le dernier mot. Un shell, un test, une CI, une capture
#    d'ecran pour la documentation : il faut pouvoir forcer.
# 2. Sinon, la langue du systeme. Personne ne devrait avoir a configurer quoi
#    que ce soit pour etre compris.
# 3. Sinon l'anglais. C'est la langue de repli d'un outil destine a circuler,
#    et celle de la documentation.
#
# ET UNE QUATRIEME, POUR LES CLES MANQUANTES
#
# Une traduction absente rend la cle entre crochets — « [ctx.noGo] » — jamais
# une chaine vide. Un message vide se lit comme une commande qui n'a rien dit ;
# une cle visible se lit comme une traduction a ecrire, et un test la trouve.
#
# CE FICHIER N'A AUCUNE DEPENDANCE, VOLONTAIREMENT
#
# Il est source par le module ET par les scripts autonomes (installateurs,
# lanceurs), qui tournent sans lui. Tout ce dont il a besoin, il l'a.

$script:LanguesDisponibles = @('en', 'fr')
$script:LangueSecours = 'en'

function Get-CtxLangue {
    <#
      PURE. Quelle langue, a partir de quoi.

      Les trois sources sont des PARAMETRES, pas des lectures directes : c'est
      ce qui rend la decision verifiable sans changer la culture de la machine
      qui execute les tests.

      Accepte 'fr-BE' comme 'fr' : une culture systeme porte presque toujours
      une region, et exiger le code court reviendrait a ne jamais reconnaitre
      personne.
    #>
    param(
        [AllowNull()][AllowEmptyString()][string]$Demandee = $env:DEVCTX_LANG,
        [AllowNull()][AllowEmptyString()][string]$Culture,
        [string[]]$Disponibles = $script:LanguesDisponibles
    )

    foreach ($candidat in @($Demandee, $Culture)) {
        if (-not $candidat) { continue }
        $court = $candidat.Trim().ToLowerInvariant() -replace '[_-].*$', ''
        if ($court -in $Disponibles) { return $court }
    }
    $script:LangueSecours
}

function Get-CtxCultureSysteme {
    # Isole du reste pour que Get-CtxLangue reste pure et testable.
    try { [System.Globalization.CultureInfo]::CurrentUICulture.Name } catch { '' }
}

function Import-CtxTextes {
    <#
      Charge une table de textes depuis lang/<code>.psd1.

      Import-PowerShellDataFile et non Invoke-Expression : un fichier de
      donnees ne doit pas pouvoir executer de code, meme livre avec le module.
    #>
    param(
        [Parameter(Mandatory)][string]$Code,
        [string]$Dossier = (Join-Path (Split-Path $PSScriptRoot -Parent) 'lang')
    )

    $fichier = [System.IO.Path]::Combine($Dossier, "$Code.psd1")
    if (-not (Test-Path -LiteralPath $fichier)) { return @{} }
    try { Import-PowerShellDataFile -LiteralPath $fichier -ErrorAction Stop }
    catch {
        # En anglais, et sans passer par T : c'est la traduction elle-meme qui a
        # echoue. Un message de panne qui depend du systeme en panne ne s'affiche pas.
        Write-Warning "DevContext: strings for '$Code' are unreadable: $($_.Exception.Message)"
        @{}
    }
}

function Set-CtxLangue {
    <#
      (Re)charge les textes pour une langue. Appelee au chargement du module, et
      par les tests qui verifient les deux langues dans le meme processus.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '',
        Justification = 'Aide privee, non exportee : charge une table en memoire du module, ne touche aucun etat systeme.')]
    param([string]$Code)

    if (-not $Code) { $Code = Get-CtxLangue -Culture (Get-CtxCultureSysteme) }
    $script:Langue = $Code
    $script:Textes = Import-CtxTextes -Code $Code
    # Le repli est charge meme quand c'est deja la langue active : cela evite un
    # cas particulier dans T, et une table de plus en memoire ne coute rien.
    $script:TextesSecours = if ($Code -eq $script:LangueSecours) { $script:Textes }
    else { Import-CtxTextes -Code $script:LangueSecours }
    $Code
}

function T {
    <#
      Le texte d'une cle, dans la langue active.

      Nom d'une lettre, et ce n'est pas de la paresse : il apparait a plus de
      deux cents endroits, et un nom long y transformerait chaque message en
      ligne illisible. Il reste INTERNE au module — jamais exporte, jamais
      visible depuis un terminal.

      Les arguments restants alimentent l'operateur -f, donc les textes portent
      {0}, {1}… Cela permet a une traduction de reordonner ses substitutions,
      ce qu'une concatenation interdirait.
    #>
    param(
        [Parameter(Mandatory, Position = 0)][string]$Cle,
        [Parameter(ValueFromRemainingArguments = $true)][object[]]$Arguments
    )

    $texte = $null
    if ($script:Textes -and $script:Textes.ContainsKey($Cle)) { $texte = $script:Textes[$Cle] }
    elseif ($script:TextesSecours -and $script:TextesSecours.ContainsKey($Cle)) { $texte = $script:TextesSecours[$Cle] }

    # Cle inconnue : on la montre. Une chaine vide se lirait comme une commande
    # qui n'a rien dit ; « [ctx.noGo] » se lit comme un defaut, et se cherche.
    if ($null -eq $texte) { return "[$Cle]" }
    if ($Arguments -and $Arguments.Count) { return ($texte -f $Arguments) }
    $texte
}
