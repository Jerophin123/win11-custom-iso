<#
.SYNOPSIS
  Run INSIDE the installed Windows (VM). Tells you which startup sound Windows will play
  (the new one or the stock Windows 11 one), shows the related settings, then plays it.

  Right-click -> Run with PowerShell   (or: powershell -ExecutionPolicy Bypass -File .\Check-StartupSound.ps1)
#>
$NEW   = 'A835766B39C3306EA736466D7F83C6C29443E6B83B1001A64BF8D5550469475A'   # sounds\set\Startup.wav
$STOCK = '8DABD90C9AD1BE80F3B67258DA0B78D0DDA6F4257D41A57427629C0837650A26'   # Windows 11 stock

Add-Type -Namespace CK -Name R -MemberDefinition @'
[DllImport("kernel32", CharSet=CharSet.Unicode)] public static extern IntPtr LoadLibraryEx(string f, IntPtr h, uint fl);
[DllImport("kernel32")] public static extern bool FreeLibrary(IntPtr h);
[DllImport("kernel32", CharSet=CharSet.Unicode)] public static extern IntPtr FindResource(IntPtr m, IntPtr name, string type);
[DllImport("kernel32")] public static extern IntPtr LoadResource(IntPtr m, IntPtr r);
[DllImport("kernel32")] public static extern IntPtr LockResource(IntPtr r);
[DllImport("kernel32")] public static extern uint SizeofResource(IntPtr m, IntPtr r);
'@

$mun = "$env:WINDIR\SystemResources\imageres.dll.mun"
$m = [CK.R]::LoadLibraryEx($mun, [IntPtr]::Zero, 0x22)
$r = [CK.R]::FindResource($m, [IntPtr]5080, 'WAVE')
$n = [CK.R]::SizeofResource($m, $r); $wav = New-Object byte[] $n
[Runtime.InteropServices.Marshal]::Copy([CK.R]::LockResource([CK.R]::LoadResource($m, $r)), $wav, 0, $n)
[void][CK.R]::FreeLibrary($m)
$h = -join ([Security.Cryptography.SHA256]::Create().ComputeHash($wav) | ForEach-Object { $_.ToString('X2') })

$which = if ($h -eq $NEW) { 'NEW (your custom startup sound)' } elseif ($h -eq $STOCK) { 'STOCK Windows 11 sound' } else { 'UNKNOWN (neither)' }
$ba  = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Authentication\LogonUI\BootAnimation' -ErrorAction SilentlyContinue
$eo  = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\EditionOverrides' -ErrorAction SilentlyContinue
$hib = (Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Power' -ErrorAction SilentlyContinue).HiberbootEnabled

Write-Host ''
Write-Host "Startup sound inside Windows : $which" -ForegroundColor $(if ($h -eq $NEW) { 'Green' } else { 'Red' })
Write-Host "  size $([math]::Round($n / 1KB)) KB, SHA256 $($h.Substring(0, 16))..."
Write-Host "Windows startup sound feature: $(if ($ba.DisableStartupSound -eq 0) { 'ON' } else { 'OFF' }) (DisableStartupSound=$($ba.DisableStartupSound), UserSetting=$($eo.UserSetting_DisableStartupSound))"
Write-Host "Update safety-net task       : $(if (Get-ScheduledTask -TaskName StartupSoundGuard -ErrorAction SilentlyContinue) { 'present' } else { 'MISSING' })"
Write-Host "Fast Startup                 : $(if ($hib -eq 0) { 'off' } else { 'on' })"
Write-Host "Old boot-task approach       : $(if (Get-ScheduledTask -TaskName CustomStartupSound -ErrorAction SilentlyContinue) { 'STILL PRESENT (would play a 2nd sound)' } else { 'not present (good)' })"
Write-Host ''
Write-Host 'Playing the exact sound Windows plays at startup...' -ForegroundColor Cyan
(New-Object Media.SoundPlayer (New-Object IO.MemoryStream (, $wav))).PlaySync()
