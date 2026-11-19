<#
.SYNOPSIS
  Applies the custom sound set (.\sounds\set) to THIS running Windows installation.
  Undo any time with .\Restore-Sounds.ps1.

  * Backs up every original file it replaces + the related registry values to
    .\backup\sounds-original (first run only - a second run never overwrites the originals)
  * Copies the new sounds into C:\Windows\Media (and the dark-mode copies in Media\dm)
  * Disables the built-in startup sound and plays the new one at boot (lock screen)
  * Restores the original file permissions/owner (TrustedInstaller) afterwards
#>
$ErrorActionPreference = 'Stop'

# --- self-elevate ------------------------------------------------------------------------
$admin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
         ).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $admin) {
    Start-Process powershell.exe -Verb RunAs -ArgumentList '-NoExit', '-ExecutionPolicy', 'Bypass', '-File', "`"$PSCommandPath`""
    return
}

$Root    = $PSScriptRoot
$SetDir  = Join-Path $Root 'sounds\set'
$Backup  = Join-Path $Root 'backup\sounds-original'
$Media   = Join-Path $env:WINDIR 'Media'
$RunKey  = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run'
$RegVals = @(
    @{ Path = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Authentication\LogonUI\BootAnimation'; Name = 'DisableStartupSound' },
    @{ Path = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\EditionOverrides'; Name = 'UserSetting_DisableStartupSound' },
    @{ Path = $RunKey; Name = 'StartupSound' }
)
New-Item -ItemType Directory -Force (Join-Path $Root 'backup') | Out-Null
Start-Transcript -Path (Join-Path $Root 'backup\apply.log') -Force | Out-Null

Add-Type -Namespace Native -Name Fs -MemberDefinition @'
[DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
public static extern bool MoveFileEx(string existing, string newName, int flags);
'@
function Set-FileContent($source, $dest) {
    # Windows' audio engine can keep a sound file memory-mapped; such a file can't be
    # overwritten but CAN be renamed. Rename it aside, copy the new one in, and delete the
    # old copy at the next reboot.
    try { Copy-Item $source $dest -Force }
    catch {
        $aside = "$dest.old-$([guid]::NewGuid().ToString('N').Substring(0, 8))"
        Rename-Item $dest (Split-Path $aside -Leaf) -Force
        Copy-Item $source $dest -Force
        [void][Native.Fs]::MoveFileEx($aside, $null, 4)       # MOVEFILE_DELAY_UNTIL_REBOOT
        Write-Host "    (in use, swapped: $(Split-Path $dest -Leaf))"
    }
}
$permsChanged = $false

try {
    if (-not (Test-Path "$SetDir\Startup.wav")) { throw "Sound set not found in $SetDir" }
    $files = @(Get-ChildItem $SetDir -Recurse -File -Filter *.wav | Where-Object Name -ne 'Startup.wav')

    # --- 1) back up originals (once) -------------------------------------------------------
    if (-not (Test-Path "$Backup\registry.json")) {
        Write-Host '==> Backing up original sounds and settings'
        foreach ($f in $files) {
            $rel = $f.FullName.Substring($SetDir.Length + 1)
            $orig = Join-Path $Media $rel
            if (Test-Path $orig) {
                $dest = Join-Path $Backup "Media\$rel"
                New-Item -ItemType Directory -Force (Split-Path $dest) | Out-Null
                Copy-Item $orig $dest -Force
            }
        }
        $reg = foreach ($r in $RegVals) {
            $v = (Get-ItemProperty -Path $r.Path -ErrorAction SilentlyContinue).($r.Name)
            [pscustomobject]@{ Path = $r.Path; Name = $r.Name; Existed = ($null -ne $v); Value = $v }
        }
        $reg | ConvertTo-Json | Set-Content "$Backup\registry.json" -Encoding UTF8
        # original permissions of the Media folder tree
        & icacls.exe $Media /save "$Backup\media-acl.txt" /T /C /Q | Out-Null
        Write-Host "    backed up $((Get-ChildItem "$Backup\Media" -Recurse -File).Count) files to $Backup"
    } else {
        Write-Host "==> Backup already exists (keeping the true originals): $Backup"
    }

    # --- 2) copy the new sounds ------------------------------------------------------------
    Write-Host '==> Installing the new sounds'
    $permsChanged = $true
    & takeown.exe /F $Media /A /R /D Y | Out-Null
    & icacls.exe $Media /grant '*S-1-5-32-544:F' /T /C /Q | Out-Null
    # clean up copies set aside by earlier runs (skipped if still in use - run again after a restart)
    Get-ChildItem $Media -Recurse -File -Filter '*.old-*' | ForEach-Object {
        try { Remove-Item $_.FullName -Force } catch { [void][Native.Fs]::MoveFileEx($_.FullName, $null, 4) }
    }
    $n = 0
    foreach ($f in $files) {
        $rel = $f.FullName.Substring($SetDir.Length + 1)
        $dest = Join-Path $Media $rel
        if (Test-Path (Split-Path $dest)) { Set-FileContent $f.FullName $dest; $n++ }
    }
    Set-FileContent "$SetDir\Startup.wav" "$Media\Startup.wav"
    Write-Host "    replaced $n sounds, added Startup.wav"

    # --- 3) startup sound --------------------------------------------------------------------
    Write-Host '==> Switching the startup sound'
    foreach ($r in $RegVals[0..1]) {
        if (-not (Test-Path $r.Path)) { New-Item -Path $r.Path -Force | Out-Null }
        Set-ItemProperty -Path $r.Path -Name $r.Name -Value 1 -Type DWord
    }
    # The old Run-key entry only fired AFTER sign-in (i.e. after typing the PIN/password).
    # A SYSTEM task with a boot trigger plays it on the lock/sign-in screen instead - the moment
    # the boot logo hands over to the lock screen, like Windows' own startup sound.
    Remove-ItemProperty -Path $RunKey -Name 'StartupSound' -ErrorAction SilentlyContinue
    $TaskDir = Join-Path $env:ProgramData 'CustomStartupSound'
    New-Item -ItemType Directory -Force $TaskDir | Out-Null
    @"
param([switch]`$Now)
# Plays the custom startup sound when the lock screen appears after boot.
`$wav = '$Media\Startup.wav'
`$deadline = (Get-Date).AddSeconds(90)
# 1) audio engine ready
while ((Get-Service Audiosrv -ErrorAction SilentlyContinue).Status -ne 'Running' -and (Get-Date) -lt `$deadline) {
    Start-Sleep -Milliseconds 200 }
if (-not `$Now) {
    # 2) boot logo -> lock screen: LogonUI.exe draws the lock / sign-in screen.
    #    With automatic sign-in there is no lock screen, so the desktop (explorer) also counts.
    while (-not (Get-Process LogonUI, explorer -ErrorAction SilentlyContinue) -and (Get-Date) -lt `$deadline) {
        Start-Sleep -Milliseconds 150 }
    Start-Sleep -Milliseconds 700          # let the lock screen finish fading in
}
if (Test-Path `$wav) { (New-Object Media.SoundPlayer `$wav).PlaySync() }
"@ | Set-Content (Join-Path $TaskDir 'play.ps1') -Encoding UTF8

    $psArgs    = "-NoProfile -NonInteractive -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$TaskDir\play.ps1`""
    $action    = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument $psArgs
    $trigger   = New-ScheduledTaskTrigger -AtStartup
    $principal = New-ScheduledTaskPrincipal -UserId 'S-1-5-18' -LogonType ServiceAccount -RunLevel Highest
    $settings  = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries `
                   -ExecutionTimeLimit (New-TimeSpan -Minutes 3) -MultipleInstances IgnoreNew
    Register-ScheduledTask -TaskName 'CustomStartupSound' -Action $action -Trigger $trigger `
        -Principal $principal -Settings $settings -Force | Out-Null

    # Fast Startup makes "Shut down" a hibernate, so power-on is not a boot and boot tasks don't
    # run. Turn it off (previous value backed up once; Restore-Sounds puts it back).
    $pwrKey = 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Power'
    $fsBackup = Join-Path $Root 'backup\fast-startup.json'
    if (-not (Test-Path $fsBackup)) {
        $hb = (Get-ItemProperty -Path $pwrKey -ErrorAction SilentlyContinue).HiberbootEnabled
        [pscustomobject]@{ Existed = ($null -ne $hb); Value = $hb } | ConvertTo-Json | Set-Content $fsBackup -Encoding UTF8
    }
    Set-ItemProperty -Path $pwrKey -Name 'HiberbootEnabled' -Value 0 -Type DWord
    Write-Host '    startup sound now plays when the lock screen appears after the boot logo'
    Write-Host '    (Fast Startup turned off so it also plays after Shut down -> power on)'

    # Test: play it exactly the way the boot task will (as SYSTEM, from the scheduler)
    Write-Host '==> Test: playing the startup sound through the boot-time path - you should hear it now'
    $testAction = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument "$psArgs -Now"
    Register-ScheduledTask -TaskName 'CustomStartupSound-Test' -Action $testAction -Principal $principal `
        -Settings $settings -Force | Out-Null
    Start-ScheduledTask -TaskName 'CustomStartupSound-Test'
    $t0 = Get-Date
    do { Start-Sleep -Milliseconds 300 } while ((Get-ScheduledTask -TaskName 'CustomStartupSound-Test').State -eq 'Running' -and
                                                 ((Get-Date) - $t0).TotalSeconds -lt 20)
    $res = (Get-ScheduledTaskInfo -TaskName 'CustomStartupSound-Test').LastTaskResult
    Unregister-ScheduledTask -TaskName 'CustomStartupSound-Test' -Confirm:$false
    Write-Host "    test run finished (result code $res; 0 = played without errors)"

    Write-Host "`nDONE. New sounds are active (the startup sound plays at your next boot)." -ForegroundColor Green
    Write-Host 'Restart your PC (or sign out and back in) so every app picks up the new sounds.' -ForegroundColor Yellow
    Write-Host 'To undo: run Restore-Sounds.ps1'
}
catch {
    Write-Host "`nFAILED: $($_.Exception.Message)" -ForegroundColor Red
}
finally {
    # --- 4) always put permissions back (even after a failure) -----------------------------
    if ($permsChanged -and (Test-Path "$Backup\media-acl.txt")) {
        Write-Host '==> Restoring original permissions'
        . (Join-Path $Root 'Sound-Permissions.ps1')
        Restore-MediaPermissions $Media "$Backup\media-acl.txt"
    }
    Stop-Transcript | Out-Null
}
