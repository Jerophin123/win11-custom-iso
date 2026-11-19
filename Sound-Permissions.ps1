# Shared helper for Apply-Sounds.ps1 / Restore-Sounds.ps1 (dot-sourced).
# Puts the original owner (TrustedInstaller) and the exact saved permissions back on
# C:\Windows\Media, using the backup/restore privileges every administrator holds.

if (-not ('Native.Priv' -as [type])) {
    Add-Type -Namespace Native -Name Priv -MemberDefinition @'
[DllImport("advapi32.dll", SetLastError = true)]
static extern bool OpenProcessToken(IntPtr h, uint acc, out IntPtr tok);
[DllImport("advapi32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
static extern bool LookupPrivilegeValue(string sys, string name, out long luid);
[DllImport("advapi32.dll", SetLastError = true)]
static extern bool AdjustTokenPrivileges(IntPtr tok, bool all, ref TP ns, int len, IntPtr prev, IntPtr rlen);
[DllImport("kernel32.dll")] static extern IntPtr GetCurrentProcess();
[StructLayout(LayoutKind.Sequential, Pack = 1)]
struct TP { public int Count; public long Luid; public int Attr; }
public static bool Enable(string name) {
    IntPtr tok; if (!OpenProcessToken(GetCurrentProcess(), 0x28, out tok)) return false;
    TP tp = new TP(); tp.Count = 1; tp.Attr = 2;
    if (!LookupPrivilegeValue(null, name, out tp.Luid)) return false;
    return AdjustTokenPrivileges(tok, false, ref tp, 0, IntPtr.Zero, IntPtr.Zero);
}
'@
}

function Restore-MediaPermissions([string]$Media, [string]$AclFile) {
    foreach ($p in 'SeRestorePrivilege', 'SeTakeOwnershipPrivilege', 'SeBackupPrivilege') {
        [void][Native.Priv]::Enable($p)
    }
    $ti = New-Object System.Security.Principal.NTAccount('NT SERVICE', 'TrustedInstaller')
    # icacls /save format: one line with the path (relative to the parent folder), next line SDDL
    $lines = Get-Content $AclFile -Encoding Unicode
    $parent = Split-Path $Media
    $ok = 0; $fail = 0
    for ($i = 0; $i + 1 -lt $lines.Count; $i += 2) {
        $path = Join-Path $parent $lines[$i].Trim()
        if (-not (Test-Path -LiteralPath $path)) { continue }
        try {
            $sd = Get-Acl -LiteralPath $path
            $sd.SetSecurityDescriptorSddlForm($lines[$i + 1].Trim(), 'Access')   # saved permissions
            $sd.SetOwner($ti)                                                    # original owner
            Set-Acl -LiteralPath $path -AclObject $sd
            $ok++
        } catch { $fail++ }
    }
    # anything newly added (e.g. Startup.wav) just gets the TrustedInstaller owner
    foreach ($item in Get-ChildItem -LiteralPath $Media -Recurse -Force) {
        try {
            $sd = Get-Acl -LiteralPath $item.FullName
            if ($sd.Owner -ne 'NT SERVICE\TrustedInstaller') { $sd.SetOwner($ti); Set-Acl -LiteralPath $item.FullName -AclObject $sd }
        } catch { $fail++ }
    }
    Write-Host "    permissions restored on $ok items$(if ($fail) { ", $fail failed" })"
}
