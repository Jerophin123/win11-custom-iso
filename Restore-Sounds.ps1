<#
.SYNOPSIS
  Restores the original Windows sounds and startup sound that Apply-Sounds.ps1 replaced,
  using the backup in .\backup\sounds-original.
#>
$ErrorActionPreference = 'Stop'

$admin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
         ).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $admin) {
    Start-Process powershell.exe -Verb RunAs -ArgumentList '-NoExit', '-ExecutionPolicy', 'Bypass', '-File', "`"$PSCommandPath`""
    return
}

$Root   = $PSScriptRoot
$Backup = Join-Path $Root 'backup\sounds-original'
$Media  = Join-Path $env:WINDIR 'Media'
Start-Transcript -Path (Join-Path $Root 'backup\restore.log') -Force | Out-Null

Add-Type -Namespace Native -Name Fs -MemberDefinition @'
[DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
public static extern bool MoveFileEx(string existing, string newName, int flags);
'@
function Set-FileContent($source, $dest) {
    # a sound in use can't be overwritten but can be renamed: swap it, delete old at reboot
    try { Copy-Item $source $dest -Force }
    catch {
        $aside = "$dest.old-$([guid]::NewGuid().ToString('N').Substring(0, 8))"
        Rename-Item $dest (Split-Path $aside -Leaf) -Force
        Copy-Item $source $dest -Force
        [void][Native.Fs]::MoveFileEx($aside, $null, 4)
        Write-Host "    (in use, swapped: $(Split-Path $dest -Leaf))"
    }
}
$permsChanged = $false

try {
    if (-not (Test-Path "$Backup\registry.json")) { throw "No backup found in $Backup - nothing to restore." }

    Write-Host '==> Restoring original sound files'
    $permsChanged = $true
    & takeown.exe /F $Media /A /R /D Y | Out-Null
    & icacls.exe $Media /grant '*S-1-5-32-544:F' /T /C /Q | Out-Null
    # clean up copies set aside by earlier runs (skipped if still in use - run again after a restart)
    Get-ChildItem $Media -Recurse -File -Filter '*.old-*' | ForEach-Object {
        try { Remove-Item $_.FullName -Force } catch { [void][Native.Fs]::MoveFileEx($_.FullName, $null, 4) }
    }
    $n = 0
    foreach ($f in Get-ChildItem "$Backup\Media" -Recurse -File) {
        $rel = $f.FullName.Substring("$Backup\Media".Length + 1)
        Set-FileContent $f.FullName (Join-Path $Media $rel); $n++
    }
    if (Test-Path "$Media\Startup.wav") {
        try { Remove-Item "$Media\Startup.wav" -Force }
        catch { [void][Native.Fs]::MoveFileEx("$Media\Startup.wav", $null, 4) }   # in use: remove at reboot
    }
    Write-Host "    restored $n files, removed Startup.wav"

    Write-Host '==> Restoring startup-sound settings'
    Unregister-ScheduledTask -TaskName 'CustomStartupSound' -Confirm:$false -ErrorAction SilentlyContinue
    Unregister-ScheduledTask -TaskName 'CustomStartupSound-Test' -Confirm:$false -ErrorAction SilentlyContinue
    $taskDir = Join-Path $env:ProgramData 'CustomStartupSound'
    if (Test-Path $taskDir) { Remove-Item $taskDir -Recurse -Force }
    # Fast Startup back to how it was before Apply-Sounds turned it off
    $fsBackup = Join-Path $Root 'backup\fast-startup.json'
    if (Test-Path $fsBackup) {
        $fs = Get-Content $fsBackup -Raw | ConvertFrom-Json
        $pwrKey = 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Power'
        if ($fs.Existed) { Set-ItemProperty -Path $pwrKey -Name 'HiberbootEnabled' -Value ([int]$fs.Value) -Type DWord }
        else { Remove-ItemProperty -Path $pwrKey -Name 'HiberbootEnabled' -ErrorAction SilentlyContinue }
        Remove-Item $fsBackup -Force      # next Apply records the then-current value afresh
    }
    foreach ($r in (Get-Content "$Backup\registry.json" -Raw | ConvertFrom-Json)) {
        if ($r.Existed) {
            $type = if ($r.Value -is [string]) { 'String' } else { 'DWord' }
            Set-ItemProperty -Path $r.Path -Name $r.Name -Value $r.Value -Type $type
        } elseif (Test-Path $r.Path) {
            Remove-ItemProperty -Path $r.Path -Name $r.Name -ErrorAction SilentlyContinue
        }
    }

    Write-Host "`nDONE. Original Windows sounds are back." -ForegroundColor Green
    Write-Host 'Restart your PC (or sign out and back in): apps that already played a sound keep the' -ForegroundColor Yellow
    Write-Host 'old one cached in memory until they restart.' -ForegroundColor Yellow
    (New-Object Media.SoundPlayer "$Media\Windows Notify System Generic.wav").Play()
}
catch {
    Write-Host "`nFAILED: $($_.Exception.Message)" -ForegroundColor Red
}
finally {
    if ($permsChanged -and (Test-Path "$Backup\media-acl.txt")) {
        Write-Host '==> Restoring original permissions'
        . (Join-Path $Root 'Sound-Permissions.ps1')
        Restore-MediaPermissions $Media "$Backup\media-acl.txt"
    }
    Stop-Transcript | Out-Null
}
