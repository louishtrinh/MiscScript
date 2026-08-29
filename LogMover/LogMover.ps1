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

function Save-Setting($path, $section, $key, $value) {
    $line    = '{0,-19} = {1}' -f $key, $value
    $out     = New-Object System.Collections.Generic.List[string]
    $current = ''
    $written = $false
    foreach ($text in (Get-Content -LiteralPath $path)) {
        if ($text -match '^\s*\[(.+)\]\s*$') {
            # Leaving the section without having found the key - add it here.
            if ($current -eq $section -and -not $written) { $out.Add($line); $written = $true }
            $current = $Matches[1].Trim()
        }
        if ($current -eq $section -and -not $written -and $text -match "^\s*$key\s*=") {
            $out.Add($line)
            $written = $true
            continue
        }
        $out.Add($text)
    }
    if (-not $written) {
        if ($current -ne $section) { $out.Add(''); $out.Add("[$section]") }
        $out.Add($line)
    }
    Set-Content -LiteralPath $path -Value $out -Encoding UTF8
}

function Read-Folder {
    param($Label, $Current, [switch]$MustExist)
    while ($true) {
        $answer = Read-Host $(if ($Current) { "$Label [$Current]" } else { $Label })
        if ($answer -eq '') { $answer = $Current }
        if ($answer -eq '') {
            Write-Host "  A folder is needed."
            continue
        }
        $answer = $answer.Trim().Trim('"').TrimEnd('\')
        if ($MustExist -and -not (Test-Path -LiteralPath $answer)) {
            Write-Host "  Cannot reach $answer"
            continue
        }
        return $answer
    }
}


function Read-Cursor($current) {
    $shown = $current.ToLocalTime().ToString('yyyy-MM-dd HH:mm')
    while ($true) {
        $answer = (Read-Host "Collect files newer than [$shown]").Trim()
        if ($answer -eq '') { return $current }
        try { return ([datetime]::Parse($answer)).ToUniversalTime() }
        catch { Write-Host "  Cannot read that. Try 2026-08-26 06:00 or 8/26/2026" }
    }
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
        # The @() must wrap the filter too, or a single surviving entry comes
        # back as a bare object and += fails.
        $entries = @(Get-Content -LiteralPath $StatePath -Raw | ConvertFrom-Json |
                     Where-Object { $_.Folder -ne $key })
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
    foreach ($from in $Renames.Keys) {
        # A leading dot is optional in the config, so .atd and atd both work.
        $ext = if ($from.StartsWith('.')) { $from } else { ".$from" }
        if ($file.Extension -ieq $ext) {
            $to = $Renames[$from]
            if (-not $to.StartsWith('.')) { $to = ".$to" }
            return [IO.Path]::GetFileNameWithoutExtension($file.Name) + $to
        }
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
$Renames      = if ($Config.Contains('Rename')) { $Config['Rename'] } else { [ordered]@{} }
$DefaultDest  = Get-Setting $Config Destination Default ''
$Exceptions   = if ($Config.Contains('Exceptions')) { $Config['Exceptions'] } else { [ordered]@{} }

$LogPath = Get-Setting $Config General LogFile ''
if ($LogPath -and -not [IO.Path]::IsPathRooted($LogPath)) { $LogPath = Join-Path $ScriptDir $LogPath }


# --- menu ----------------------------------------------------------------
# A folder the config leaves blank is asked for once, then the menu takes
# over. Pressing Enter at the menu runs the collection.

$WatchFolder = Get-Setting $Config General WatchFolder ''
if (-not $WatchFolder) {
    $WatchFolder = Read-Folder 'Watch folder' '' -MustExist
    Save-Setting $ConfigPath 'General' 'WatchFolder' $WatchFolder
}
if (-not $DefaultDest) {
    $DefaultDest = Read-Folder 'Destination folder' ''
    Save-Setting $ConfigPath 'Destination' 'Default' $DefaultDest
}

$Cursor = Get-Cursor $WatchFolder
if (-not $Cursor) { $Cursor = (Get-Date).ToUniversalTime().AddDays(-$LookbackDays) }

$Run = $false
while ($true) {
    Write-Host ""
    Write-Host "LogMover"
    Write-Host ""
    Write-Host "  1  Run"
    Write-Host "  2  Watch folder       $WatchFolder"
    Write-Host "  3  Destination        $DefaultDest"
    Write-Host ("  4  Last collected     {0}" -f $Cursor.ToLocalTime().ToString('yyyy-MM-dd HH:mm'))
    Write-Host ""

    switch ((Read-Host "Choice [1]").Trim()) {
        { $_ -eq '' -or $_ -eq '1' } { $Run = $true }
        '2' {
            $picked = Read-Folder 'Watch folder' $WatchFolder -MustExist
            if ($picked -ne $WatchFolder) {
                $WatchFolder = (Get-Item -LiteralPath $picked).FullName.TrimEnd('\')
                Save-Setting $ConfigPath 'General' 'WatchFolder' $WatchFolder
                # Each watch folder carries its own last-collected time.
                $Cursor = Get-Cursor $WatchFolder
                if (-not $Cursor) { $Cursor = (Get-Date).ToUniversalTime().AddDays(-$LookbackDays) }
            }
        }
        '3' {
            $DefaultDest = Read-Folder 'Destination folder' $DefaultDest
            Save-Setting $ConfigPath 'Destination' 'Default' $DefaultDest
        }
        '4' {
            $Cursor = Read-Cursor $Cursor
            Set-Cursor $WatchFolder $Cursor
        }
        default { Write-Host "  Pick 1, 2, 3 or 4." }
    }
    if ($Run) { break }
}

Write-Host ""
Write-Host "Watching $WatchFolder for $($FileTypes -join ' ')...Press CTRL+C to stop."
Write-Host ""

$FirstPass    = $true
$LastDeferred = 0


# --- collect -------------------------------------------------------------

while ($true) {
    try {
        $scanStart = (Get-Date).ToUniversalTime()
        $since     = $Cursor.AddSeconds(-$OverlapSeconds)
        $deferred  = @()

        $matched = @(foreach ($type in $FileTypes) {
            Get-ChildItem -LiteralPath $WatchFolder -Filter $type -Recurse -File -ErrorAction SilentlyContinue |
                Where-Object { $_.Name -like $type }
        }) | Sort-Object FullName -Unique
        $files = @($matched | Where-Object { $_.LastWriteTimeUtc -gt $since }) | Sort-Object LastWriteTimeUtc

        # One summary on the first pass, so a folder that yields nothing says why.
        if ($FirstPass) {
            Write-Host ("  {0} file(s) match {1}, {2} newer than {3}" -f
                @($matched).Count, ($FileTypes -join ' '), @($files).Count,
                $since.ToLocalTime().ToString('yyyy-MM-dd HH:mm'))
            $FirstPass = $false
        }

        foreach ($file in $files) {
            if (Test-Locked $file) { $deferred += $file.LastWriteTimeUtc; continue }   # reported below

            $name        = Get-TargetName $file
            $destination = Get-Destination $file.FullName
            $target      = $null
            try {
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

        # Files in use are retried next pass. Say so, but only when it changes,
        # or a stuck file would print every few seconds forever.
        if (@($deferred).Count -ne $LastDeferred) {
            if ($deferred) { Write-Host ("  {0} file(s) in use, will retry" -f @($deferred).Count) }
            $LastDeferred = @($deferred).Count
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
