<# Example: pwsh -File scripts/new-app.ps1 -Name SecondApp -BundleId com.sjx13.ios.secondapp #>
[CmdletBinding()] param([Parameter(Mandatory)][string]$Name, [Parameter(Mandatory)][string]$BundleId)
. "$PSScriptRoot/common.ps1"
Invoke-Checked python @("$PSScriptRoot/new_app.py", $Name, $BundleId)
