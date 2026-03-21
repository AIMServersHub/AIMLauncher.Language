$ErrorActionPreference = "Stop"

function Normalize-Text {
  param([string]$Value)

  if ([string]::IsNullOrWhiteSpace($Value)) {
    return $null
  }

  $text = $Value.Trim()
  $text = $text -replace "\r", " "
  $text = $text -replace "\n", " "
  $text = $text -replace "\s+", " "

  if ($text.StartsWith("{", [System.StringComparison]::Ordinal)) {
    return $null
  }

  if ($text.StartsWith("&#x", [System.StringComparison]::OrdinalIgnoreCase)) {
    return $null
  }

  if ($text -match "^[\d\W_]+$") {
    return $null
  }

  if ($text -notmatch "[A-Za-z]") {
    return $null
  }

  return $text
}

function To-PascalToken {
  param([string]$Value)

  if ([string]::IsNullOrWhiteSpace($Value)) {
    return "Value"
  }

  $clean = $Value -replace "[^A-Za-z0-9]+", " "
  $parts = $clean.Split(" ", [System.StringSplitOptions]::RemoveEmptyEntries)
  if ($parts.Count -eq 0) {
    return "Value"
  }

  $words = @()
  foreach ($part in $parts) {
    if ($part.Length -eq 0) {
      continue
    }

    $lower = $part.ToLowerInvariant()
    $words += ($lower.Substring(0,1).ToUpperInvariant() + $lower.Substring(1))
    if ($words.Count -ge 8) {
      break
    }
  }

  if ($words.Count -eq 0) {
    return "Value"
  }

  return ($words -join "")
}

function Get-NextKey {
  param(
    [hashtable]$Map,
    [string]$Prefix,
    [string]$Text
  )

  $suffixes = @("", "Alt", "AltB", "AltC", "AltD", "AltE", "AltF", "AltG")
  foreach ($suffix in $suffixes) {
    $candidate = if ([string]::IsNullOrWhiteSpace($suffix)) { $Prefix } else { "$Prefix.$suffix" }
    if (-not $Map.ContainsKey($candidate)) {
      return $candidate
    }

    if ([string]::Equals($Map[$candidate], $Text, [System.StringComparison]::Ordinal)) {
      return $candidate
    }
  }

  $fallback = "$Prefix.AltFallback"
  if (-not $Map.ContainsKey($fallback) -or [string]::Equals($Map[$fallback], $Text, [System.StringComparison]::Ordinal)) {
    return $fallback
  }

  throw "Too many key collisions for prefix: $Prefix"
}

function Build-KeyPrefixFromPath {
  param(
    [string]$RelativePath,
    [string]$RootPrefix
  )

  $withoutExt = [System.IO.Path]::ChangeExtension($RelativePath, $null)
  $tokens = $withoutExt -split "[\\/]" | Where-Object { $_.Length -gt 0 } | ForEach-Object { To-PascalToken $_ }
  return ($RootPrefix + "." + ($tokens -join "."))
}

function Get-RelativePath {
  param(
    [string]$BasePath,
    [string]$FullPath
  )

  $base = [System.IO.Path]::GetFullPath($BasePath)
  if (-not $base.EndsWith([System.IO.Path]::DirectorySeparatorChar)) {
    $base += [System.IO.Path]::DirectorySeparatorChar
  }

  $target = [System.IO.Path]::GetFullPath($FullPath)
  $baseUri = New-Object System.Uri($base)
  $targetUri = New-Object System.Uri($target)
  $relativeUri = $baseUri.MakeRelativeUri($targetUri)
  $relative = [System.Uri]::UnescapeDataString($relativeUri.ToString())
  return $relative.Replace('/', [System.IO.Path]::DirectorySeparatorChar)
}

function Read-Locale {
  param([string]$Path)

  if (-not (Test-Path $Path)) {
    return @{}
  }

  $jsonObject = Get-Content $Path -Raw | ConvertFrom-Json
  $table = @{}
  foreach ($prop in $jsonObject.PSObject.Properties) {
    $table[$prop.Name] = [string]$prop.Value
  }

  return $table
}

function Write-Locale {
  param(
    [hashtable]$Data,
    [string]$Path
  )

  $ordered = [ordered]@{}
  foreach ($key in ($Data.Keys | Sort-Object)) {
    $ordered[$key] = $Data[$key]
  }

  $json = $ordered | ConvertTo-Json -Depth 10
  Set-Content -Path $Path -Value $json -Encoding UTF8
}

$toolsDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$languageRepoRoot = Split-Path -Parent $toolsDir
$mainRepoRoot = Resolve-Path (Join-Path $languageRepoRoot "..\..")
$appRoot = Join-Path $mainRepoRoot "src\AIMLauncher"

if (-not (Test-Path $appRoot)) {
  throw "Could not find app source at $appRoot"
}

$enPath = Join-Path $languageRepoRoot "locales\en-US.json"
$frPath = Join-Path $languageRepoRoot "locales\fr-FR.json"

$en = Read-Locale $enPath
$fr = Read-Locale $frPath

# Remove previously generated keys so we can recreate deterministic non-text keys.
foreach ($key in @($en.Keys)) {
  if ($key.StartsWith("Ui.", [System.StringComparison]::Ordinal) -or
      $key.StartsWith("Vm.", [System.StringComparison]::Ordinal)) {
    $en.Remove($key)
    $fr.Remove($key)
  }
}

# Build reverse index to keep already curated keys where possible.
$keyByEnglish = @{}
foreach ($key in $en.Keys) {
  $value = $en[$key]
  if (-not [string]::IsNullOrWhiteSpace($value) -and -not $keyByEnglish.ContainsKey($value)) {
    $keyByEnglish[$value] = $key
  }
}

$addedKeys = 0
$candidates = @{}

$axamlRegex = [regex]'(Content|Text|Header|Watermark|PlaceholderText|ToolTip\.Tip)\s*=\s*"([^"]+)"'
$axamlFiles = Get-ChildItem -Path $appRoot -Recurse -Filter *.axaml -File
foreach ($file in $axamlFiles) {
  $relative = Get-RelativePath -BasePath $appRoot -FullPath $file.FullName
  $prefix = Build-KeyPrefixFromPath -RelativePath $relative -RootPrefix "Ui"
  $content = Get-Content $file.FullName -Raw
  foreach ($match in $axamlRegex.Matches($content)) {
    $attributeName = To-PascalToken $match.Groups[1].Value
    $raw = $match.Groups[2].Value
    $text = Normalize-Text $raw
    if ($null -eq $text) {
      continue
    }

    $textSlug = To-PascalToken $text
    $basePrefix = "$prefix.$attributeName.$textSlug"
    $key = Get-NextKey -Map $candidates -Prefix $basePrefix -Text $text
    $candidates[$key] = $text
  }
}

$csFiles = Get-ChildItem -Path (Join-Path $appRoot "ViewModels") -Recurse -Filter *.cs -File
$stringRegex = [regex]'"([^"\\]*(?:\\.[^"\\]*)*)"'
foreach ($file in $csFiles) {
  $relative = Get-RelativePath -BasePath $appRoot -FullPath $file.FullName
  $prefix = Build-KeyPrefixFromPath -RelativePath $relative -RootPrefix "Vm"
  $lines = Get-Content $file.FullName

  foreach ($line in $lines) {
    $context = $null
    if ($line -match "StatusMessage\s*=") { $context = "StatusMessage" }
    elseif ($line -match "LauncherServersStatus\s*=") { $context = "LauncherServersStatus" }
    elseif ($line -match "VerificationStatusText\s*=") { $context = "VerificationStatus" }
    elseif ($line -match "\.Information\(") { $context = "NotificationInformation" }
    elseif ($line -match "\.Warning\(") { $context = "NotificationWarning" }
    elseif ($line -match "\.Error\(") { $context = "NotificationError" }
    elseif ($line -match "\.Success\(") { $context = "NotificationSuccess" }
    elseif ($line -match "\breturn\s+") { $context = "Return" }

    if ($null -eq $context) {
      continue
    }

    foreach ($match in $stringRegex.Matches($line)) {
      $raw = $match.Groups[1].Value.Replace('\"', '"')
      $text = Normalize-Text $raw
      if ($null -eq $text) {
        continue
      }

      $textSlug = To-PascalToken $text
      $basePrefix = "$prefix.$context.$textSlug"
      $key = Get-NextKey -Map $candidates -Prefix $basePrefix -Text $text
      $candidates[$key] = $text
    }
  }
}

foreach ($candidateKey in ($candidates.Keys | Sort-Object)) {
  $text = $candidates[$candidateKey]

  if ($keyByEnglish.ContainsKey($text)) {
    continue
  }

  $key = $candidateKey
  $en[$key] = $text
  if (-not $fr.ContainsKey($key)) {
    $fr[$key] = $text
  }

  $keyByEnglish[$text] = $key
  $addedKeys++
}

Write-Locale -Data $en -Path $enPath
Write-Locale -Data $fr -Path $frPath

Write-Host "Locale extraction completed." -ForegroundColor Green
Write-Host "Candidate strings: $($candidates.Count)" -ForegroundColor Green
Write-Host "New keys added: $addedKeys" -ForegroundColor Green
