$ErrorActionPreference = "Stop"

$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$repo = Split-Path -Parent $root
$enPath = Join-Path $repo "locales/en-US.json"
$frPath = Join-Path $repo "locales/fr-FR.json"

$enObject = Get-Content $enPath -Raw | ConvertFrom-Json
$frObject = Get-Content $frPath -Raw | ConvertFrom-Json

$en = @{}
foreach ($prop in $enObject.PSObject.Properties) {
  $en[$prop.Name] = [string]$prop.Value
}

$fr = @{}
foreach ($prop in $frObject.PSObject.Properties) {
  $fr[$prop.Name] = [string]$prop.Value
}

$missingInFr = @($en.Keys | Where-Object { -not $fr.ContainsKey($_) })
$extraInFr = @($fr.Keys | Where-Object { -not $en.ContainsKey($_) })

if ($missingInFr.Count -gt 0) {
  Write-Host "Missing keys in fr-FR:" -ForegroundColor Red
  $missingInFr | ForEach-Object { Write-Host "  $_" -ForegroundColor Red }
}

if ($extraInFr.Count -gt 0) {
  Write-Host "Extra keys in fr-FR:" -ForegroundColor Yellow
  $extraInFr | ForEach-Object { Write-Host "  $_" -ForegroundColor Yellow }
}

if ($missingInFr.Count -eq 0 -and $extraInFr.Count -eq 0) {
  Write-Host "Locale parity check passed." -ForegroundColor Green
  exit 0
}

exit 1
