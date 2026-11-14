param(
    [Parameter(Mandatory=$true)][string]$IPA,
    [string]$Rapport
)
$ErrorActionPreference = 'Stop'
$cadenceIPAPath = (Resolve-Path -LiteralPath $IPA).Path
$cadenceInspector = Join-Path $PSScriptRoot 'inspect_ipa.py'
$cadencePython = Get-Command python -ErrorAction SilentlyContinue
if (-not $cadencePython) { throw "Python 3 est nécessaire pour ce diagnostic local ; aucun envoi réseau n’est effectué." }
if ($Rapport) {
    & $cadencePython.Source $cadenceInspector $cadenceIPAPath --output $Rapport
} else {
    & $cadencePython.Source $cadenceInspector $cadenceIPAPath
}
if ($LASTEXITCODE -ne 0) { throw "Le diagnostic IPA a échoué." }
