<#
    LogMover.ps1 - watches a folder and moves new test logs to their destination.

    Replaces archive\rename-atd.ps1, copyfiles.ps1, copyfilesNEW.PS1,
    autocollection6.PS1 and copyfinal.ps1 with a single pass:
    find new files -> back up -> rename -> move to default or exception folder.

    Settings live in LogMover.config.ini. Launch with Run-LogMover.bat.
#>

$ErrorActionPreference = 'Stop'

$ScriptDir      = Split-Path -Parent $MyInvocation.MyCommand.Path
$ConfigPath     = Join-Path $ScriptDir 'LogMover.config.ini'
$StatePath      = Join-Path $ScriptDir 'LogMover.state.json'
$OverlapSeconds = 60


function Read-Ini($path) {
    $ini = [ordered]@{}
    $section = ''
    foreach ($line in (Get-Content -LiteralPath $path)) {
        $text = ($line -replace '\s+;.*$', '').Trim()
        if ($text -eq '' -or $text.StartsWith(';') -or $text.StartsWith('#')) { continue }
        if ($text -match '^\[(.+)\]$') {
            $section = $Matches[1].Trim()
            if (-not $ini.Contains($section)) { $ini[$section] = [ordered]@{} }
            continue
        }
        $split = $text.IndexOf('=')
        if ($split -lt 1 -or $section -eq '') { continue }
        $ini[$section][$text.Substring(0, $split).Trim()] = $text.Substring($split + 1).Trim()
    }
    return $ini
}

function Get-Setting($ini, $section, $key, $default) {
    if ($ini.Contains($section) -and $ini[$section].Contains($key) -and $ini[$section][$key] -ne '') {
        return $ini[$section][$key]
    }
    return $default
}

function Save-WatchFolder($path, $folder) {
    $out = New-Object System.Collections.Generic.List[string]
    $inGeneral = $false
    $written   = $false
    foreach ($line in (Get-Content -LiteralPath $path)) {
        if ($line -match '^\s*\[(.+)\]\s*$') { $inGeneral = ($Matches[1].Trim() -eq 'General') }
        if ($inGeneral -and -not $written -and $line -match '^\s*WatchFolder\s*=') {
            $out.Add("WatchFolder         = $folder")
            $written = $true
            continue
        }
        $out.Add($line)
    }
    Set-Content -LiteralPath $path -Value $out -Encoding UTF8
}


function Get-StateKey($folder) { return $folder.TrimEnd('\').ToLowerInvariant() }

function Get-Cursor($folder) {
    if (-not (Test-Path -LiteralPath $StatePath)) { return $null }
    $key = Get-StateKey $folder
    $entry = @(Get-Content -LiteralPath $StatePath -Raw | ConvertFrom-Json) |
             Where-Object { $_.Folder -eq $key } | Select-Object -First 1
    if ($entry) { return ([datetime]$entry.LastRun).ToUniversalTime() }
    return $null
}

function Set-Cursor($folder, $utc) {
    $key = Get-StateKey $folder
    $entries = @()
    if (Test-Path -LiteralPath $StatePath) {
        $entries = @(Get-Content -LiteralPath $StatePath -Raw | ConvertFrom-Json) |
                   Where-Object { $_.Folder -ne $key }
    }
    $entries += [pscustomobject]@{ Folder = $key; LastRun = $utc.ToString('o') }
    Set-Content -LiteralPath $StatePath -Value (@($entries) | ConvertTo-Json) -Encoding UTF8
}


function Get-Destination($fullPath) {
    foreach ($match in $Exceptions.Keys) {
        if ($fullPath.IndexOf($match, [StringComparison]::OrdinalIgnoreCase) -ge 0) {
            return $Exceptions[$match]
        }
    }
    return $DefaultDest
}

function Get-TargetName($file) {
    if ($RenameFrom -and $file.Extension -ieq $RenameFrom) {
        return [IO.Path]::GetFileNameWithoutExtension($file.Name) + $RenameTo
    }
    return $file.Name
}

function Get-FreePath($folder, $name) {
    $target = Join-Path $folder $name
    if (-not (Test-Path -LiteralPath $target)) { return $target }
    $base = [IO.Path]::GetFileNameWithoutExtension($name)
    $ext  = [IO.Path]::GetExtension($name)
    $n = 2
    while (Test-Path -LiteralPath ($target = Join-Path $folder ('{0}_{1}{2}' -f $base, $n, $ext))) { $n++ }
    return $target
}

function Test-Locked($file) {
    try {
        $stream = [IO.File]::Open($file.FullName, 'Open', 'Read', 'None')
        $stream.Close()
        return $false
    } catch { return $true }
}

function Write-LogLine($action, $source, $target) {
    if (-not $LogPath) { return }
    if (-not (Test-Path -LiteralPath $LogPath)) {
        Set-Content -LiteralPath $LogPath -Value 'Timestamp,Action,Source,Destination' -Encoding UTF8
    }
    Add-Content -LiteralPath $LogPath -Encoding UTF8 -Value (
        '{0},{1},"{2}","{3}"' -f (Get-Date -Format s), $action, $source, $target)
}


# --- settings ------------------------------------------------------------

if (-not (Test-Path -LiteralPath $ConfigPath)) {
    Write-Host "Cannot find LogMover.config.ini next to this script."
    exit 1
}
$Config = Read-Ini $ConfigPath

$FileTypes = @((Get-Setting $Config General FileTypes '*.*') -split ';' |
               ForEach-Object { $_.Trim() } | Where-Object { $_ -ne '' })
$PollSeconds  = [int](Get-Setting $Config General PollSeconds 5)
$LookbackDays = [int](Get-Setting $Config General InitialLookbackDays 1)
$BackupFolder = Get-Setting $Config General BackupFolder ''
$RenameFrom   = Get-Setting $Config Rename From ''
$RenameTo     = Get-Setting $Config Rename To ''
$DefaultDest  = Get-Setting $Config Destination Default ''
$Exceptions   = if ($Config.Contains('Exceptions')) { $Config['Exceptions'] } else { [ordered]@{} }

$LogPath = Get-Setting $Config General LogFile ''
if ($LogPath -and -not [IO.Path]::IsPathRooted($LogPath)) { $LogPath = Join-Path $ScriptDir $LogPath }

if (-not $DefaultDest) {
    Write-Host "LogMover.config.ini has no [Destination] Default folder."
    exit 1
}


# --- watch folder --------------------------------------------------------

Write-Host "LogMover is running...Press CTRL+C to stop."
Write-Host ""

$Remembered = Get-Setting $Config General WatchFolder ''
while ($true) {
    $answer = Read-Host $(if ($Remembered) { "Watch folder [$Remembered]" } else { "Watch folder" })
    if ($answer -eq '') { $answer = $Remembered }
    if ($answer -eq '') { Write-Host "  A watch folder is needed."; continue }
    if (-not (Test-Path -LiteralPath $answer)) { Write-Host "  Cannot reach $answer"; continue }
    $WatchFolder = (Get-Item -LiteralPath $answer).FullName.TrimEnd('\')
    break
}
if ($WatchFolder -ne $Remembered) { Save-WatchFolder $ConfigPath $WatchFolder }

$Cursor = Get-Cursor $WatchFolder
if (-not $Cursor) { $Cursor = (Get-Date).ToUniversalTime().AddDays(-$LookbackDays) }

Write-Host ""
Write-Host "Watching $WatchFolder for $($FileTypes -join ' ')"
Write-Host ""


# --- collect -------------------------------------------------------------

while ($true) {
    try {
        $scanStart = (Get-Date).ToUniversalTime()
        $since     = $Cursor.AddSeconds(-$OverlapSeconds)
        $deferred  = @()

        $files = @(foreach ($type in $FileTypes) {
            Get-ChildItem -LiteralPath $WatchFolder -Filter $type -Recurse -File -ErrorAction SilentlyContinue |
                Where-Object { $_.Name -like $type -and $_.LastWriteTimeUtc -gt $since }
        }) | Sort-Object FullName -Unique | Sort-Object LastWriteTimeUtc

        foreach ($file in $files) {
            if (Test-Locked $file) { $deferred += $file.LastWriteTimeUtc; continue }

            $name        = Get-TargetName $file
            $destination = Get-Destination $file.FullName
            $target      = $null
            try {
                if ($BackupFolder) {
                    $relative  = $file.DirectoryName.Substring($WatchFolder.Length).TrimStart([IO.Path]::DirectorySeparatorChar)
                    $backupDir = if ($relative) { Join-Path $BackupFolder $relative } else { $BackupFolder }
                    New-Item -ItemType Directory -Path $backupDir -Force | Out-Null
                    Copy-Item -LiteralPath $file.FullName -Destination (Get-FreePath $backupDir $name)
                }

                New-Item -ItemType Directory -Path $destination -Force | Out-Null
                $target = Get-FreePath $destination $name
                Copy-Item -LiteralPath $file.FullName -Destination $target
                if ((Get-Item -LiteralPath $target).Length -ne $file.Length) {
                    throw "copy landed short at $target"
                }
                Remove-Item -LiteralPath $file.FullName -Force

                Write-Host ("  {0} -> {1}" -f $file.Name, (Split-Path -Leaf $destination))
                Write-LogLine 'MOVED' $file.FullName $target
            }
            catch {
                if ($target -and (Test-Path -LiteralPath $target)) {
                    Remove-Item -LiteralPath $target -Force -ErrorAction SilentlyContinue
                }
                $deferred += $file.LastWriteTimeUtc
                Write-Host ("  FAILED {0} - {1}" -f $file.Name, $_.Exception.Message)
                Write-LogLine 'FAILED' $file.FullName $_.Exception.Message
            }
        }

        # Never step the cursor past a file this pass could not move.
        $Cursor = $scanStart
        if ($deferred) {
            $oldest = ($deferred | Sort-Object | Select-Object -First 1).AddSeconds(-1)
            if ($oldest -lt $Cursor) { $Cursor = $oldest }
        }
        Set-Cursor $WatchFolder $Cursor
    }
    catch {
        # Share dropped, config folder gone, and the like. Hold the cursor and retry.
        Write-Host ("  Pass skipped - {0}" -f $_.Exception.Message)
    }

    Start-Sleep -Seconds $PollSeconds
}
