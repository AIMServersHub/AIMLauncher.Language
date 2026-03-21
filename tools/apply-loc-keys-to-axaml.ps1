param(
    [string]$RepoRoot = "../../..",
    [string]$LocaleFile = "../locales/en-US.json",
    [string]$TargetGlob = "src/AIMLauncher/Views/**/*.axaml",
    [switch]$Apply
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Get-NormalizedPath {
    param([string]$Path)
    return [System.IO.Path]::GetFullPath($Path)
}

function Get-PreferredKey {
    param(
        [string]$FilePath,
        [string]$Value,
        [hashtable]$ValueToKeys
    )

    if (-not $ValueToKeys.ContainsKey($Value)) {
        return $null
    }

    $keys = @($ValueToKeys[$Value])
    if ($keys.Count -eq 0) {
        return $null
    }

    $rel = $FilePath.Replace('\\', '/')
    $prefix = $null
    if ($rel -match 'src/AIMLauncher/Views/(.+)\.axaml$') {
        $segments = $Matches[1].Split('/')
        $segments = $segments | ForEach-Object {
            if ([string]::IsNullOrWhiteSpace($_)) { return $_ }
            $lower = $_.ToLowerInvariant()
            return ($lower.Substring(0,1).ToUpperInvariant() + $lower.Substring(1))
        }
        $prefix = "Ui.Views." + ($segments -join '.')
    }

    if (-not [string]::IsNullOrWhiteSpace($prefix)) {
        $prefixMatch = $keys | Where-Object { $_.StartsWith($prefix, [System.StringComparison]::OrdinalIgnoreCase) }
        if ($prefixMatch.Count -gt 0) {
            return ($prefixMatch | Sort-Object Length | Select-Object -First 1)
        }
    }

    return ($keys | Sort-Object Length | Select-Object -First 1)
}

function Ensure-SharedNamespace {
    param([string]$Content)

    if ($Content -match 'xmlns:shared="using:AIMLauncher.Views.Shared"') {
        return $Content
    }

    return [regex]::Replace(
        $Content,
        '(?m)^(\s*xmlns:[^\r\n]+\r?\n)',
        {
            param($m)
            return $m.Groups[1].Value + '    xmlns:shared="using:AIMLauncher.Views.Shared"' + [Environment]::NewLine
        },
        1
    )
}

$repoRootAbs = if ([System.IO.Path]::IsPathRooted($RepoRoot)) {
    Get-NormalizedPath $RepoRoot
}
else {
    Get-NormalizedPath (Join-Path $PSScriptRoot $RepoRoot)
}
$localeFileAbs = Get-NormalizedPath (Join-Path $PSScriptRoot $LocaleFile)

if (-not (Test-Path $localeFileAbs)) {
    throw "Locale file not found: $localeFileAbs"
}

$localeRaw = Get-Content $localeFileAbs -Raw
$locale = $localeRaw | ConvertFrom-Json

$valueToKeys = @{}
foreach ($prop in $locale.PSObject.Properties) {
    if ([string]::IsNullOrWhiteSpace($prop.Name)) {
        continue
    }
    $value = [string]$prop.Value
    if ([string]::IsNullOrWhiteSpace($value)) {
        continue
    }
    if (-not $valueToKeys.ContainsKey($value)) {
        $valueToKeys[$value] = New-Object System.Collections.Generic.List[string]
    }
    $valueToKeys[$value].Add($prop.Name)
}

$files = Get-ChildItem -Path (Join-Path $repoRootAbs "src/AIMLauncher/Views") -Recurse -Filter *.axaml

$attributePattern = '(?<attr>Text|Content|Title|PlaceholderText|ToolTip\.Tip|OnContent|OffContent)="(?<value>[^"]+)"'
$globalMatches = 0
$globalFilesChanged = 0

foreach ($file in $files) {
    $text = Get-Content $file.FullName -Raw
    $original = $text
    $script:fileMatches = 0
    $script:needsShared = $false

    $text = [regex]::Replace($text, $attributePattern, {
        param($m)
        $attr = $m.Groups['attr'].Value
        $value = $m.Groups['value'].Value

        if ([string]::IsNullOrWhiteSpace($value)) {
            return $m.Value
        }

        if ($value.StartsWith('{') -or $value.StartsWith('&#x')) {
            return $m.Value
        }

        $key = Get-PreferredKey -FilePath $file.FullName -Value $value -ValueToKeys $valueToKeys
        if ([string]::IsNullOrWhiteSpace($key)) {
            return $m.Value
        }

        $script:fileMatches++
        $script:needsShared = $true
        return ('{0}="{1}"' -f $attr, ('{shared:Loc Key=' + $key + '}'))
    })

    if ($script:needsShared) {
        $text = Ensure-SharedNamespace -Content $text
    }

    if ($script:fileMatches -gt 0 -and $text -ne $original) {
        $globalMatches += $script:fileMatches
        $globalFilesChanged++
        $relativePath = $file.FullName.Replace($repoRootAbs + '\\', '')
        Write-Host "[$($script:fileMatches)] $relativePath"
        if ($Apply) {
            Set-Content -Path $file.FullName -Value $text -NoNewline
        }
    }
}

Write-Host "Matches: $globalMatches"
Write-Host "FilesChanged: $globalFilesChanged"
if (-not $Apply) {
    Write-Host "Dry run only. Use -Apply to write changes."
}
