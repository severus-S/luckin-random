<# Validate a local IPA, open its folder, optionally open Sideloadly. Installation remains manual.
Example: ./scripts/deploy-ios.ps1 -Ipa artifacts/path/MyFirstApp-unsigned.ipa #>
[CmdletBinding()] param([Parameter(Mandatory)][string]$Ipa, [string]$SideloadlyPath, [switch]$Open)
. "$PSScriptRoot/common.ps1"
$file = (Resolve-Path -LiteralPath $Ipa).Path
Invoke-Checked python @("$PSScriptRoot/validate_ipa.py", $file)
Write-Host "IPA: $file"
Write-Host 'Sideloadly: select device, drop IPA, use same Apple ID and effective Bundle ID; enable automatic refresh, then Start.'
Write-Host 'On iPhone enable Developer Mode/trust as prompted. Check version, count and saved note.'
Write-Host 'New version installation is manual. Daemon refresh renews its cached version only. See docs/SIDELOAD_AND_RENEW.md.'
if ($Open) {
    Start-Process explorer.exe -ArgumentList @('/select,', ('"' + $file + '"'))
    if ($SideloadlyPath) {
        $exe = (Resolve-Path -LiteralPath $SideloadlyPath).Path
        if ([IO.Path]::GetExtension($exe) -ne '.exe') { throw 'Expected a Sideloadly .exe path.' }
        Start-Process -FilePath $exe
    }
}
