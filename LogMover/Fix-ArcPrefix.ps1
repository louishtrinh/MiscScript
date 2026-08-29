<#
    Fix-ArcPrefix.ps1 - strips an Arc_YYMMDDHHMMSS_ prefix off file names.

    Shows what it will rename and asks before changing anything.
    Launch with "Fix Arc Names.bat".
#>

param([string]$Folder)

$ErrorActionPreference = 'Stop'

# Arc_ then the timestamp then an underscore. 6 to 14 digits so both
# YYMMDDHHMMSS and YYYYMMDDHHMMSS are covered.
$Pattern = '^Arc_\d{6,14}_'

Write-Host "Strip Arc_ prefix"
Write-Host ""

while (-not $Folder -or -not (Test-Path -LiteralPath $Folder)) {
    if ($Folder) { Write-Host "  Cannot reach $Folder" }
    $Folder = "$(Read-Host 'Folder to fix')".Trim().Trim('"').TrimEnd('\')
}

$files = @(Get-ChildItem -LiteralPath $Folder -Recurse -File |
           Where-Object { $_.Name -match $Pattern })

Write-Host ""
Write-Host ("{0} file(s) with an Arc_ prefix under {1}" -f $files.Count, $Folder)
if (-not $files) { Write-Host ""; return }

Write-Host ""
$shown = 0
foreach ($f in $files) {
    if ($shown -ge 20) { Write-Host ("  ...and {0} more" -f ($files.Count - 20)); break }
    Write-Host ("  {0}`n      -> {1}" -f $f.Name, ($f.Name -replace $Pattern, ''))
    $shown++
}

Write-Host ""
$answer = Read-Host ("Rename {0} file(s)? (y/N)" -f $files.Count)
if ("$answer".Trim() -notmatch '^(y|yes)$') {
    Write-Host "Nothing was changed."
    return
}

Write-Host ""
$renamed = 0
$skipped = 0
foreach ($f in $files) {
    $new = $f.Name -replace $Pattern, ''
    if (Test-Path -LiteralPath (Join-Path $f.DirectoryName $new)) {
        Write-Host ("  SKIP {0} - {1} is already there" -f $f.Name, $new)
        $skipped++
        continue
    }
    try {
        Rename-Item -LiteralPath $f.FullName -NewName $new
        $renamed++
    }
    catch {
        Write-Host ("  FAILED {0} - {1}" -f $f.Name, $_.Exception.Message)
        $skipped++
    }
}

Write-Host ""
Write-Host ("{0} renamed, {1} left alone." -f $renamed, $skipped)
