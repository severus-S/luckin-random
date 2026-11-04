<# Stage only reviewed paths, commit and push main; push triggers CI.
Example: ./scripts/publish-ios.ps1 -Paths apps/MyFirstApp -Message 'Update welcome' -BillingChecked #>
[CmdletBinding()] param([Parameter(Mandatory)][string[]]$Paths, [Parameter(Mandatory)][string]$Message, [switch]$BillingChecked)
. "$PSScriptRoot/common.ps1"
if (!$BillingChecked) { throw 'Push can start billable Actions. Check allowance/budget and pass -BillingChecked.' }
Push-Location $script:Root
try {
    $branch = & git branch --show-current
    if ($LASTEXITCODE -ne 0 -or $branch -ne 'main') { throw 'Publish script requires local main.' }
    $staged = & git diff --cached --name-only
    if ($LASTEXITCODE -ne 0 -or $staged) { throw 'Existing staged changes found; review and commit separately.' }
    Invoke-Checked git (@('add','--') + $Paths)
    Invoke-Checked git @('diff','--cached','--stat')
    Invoke-Checked git @('commit','-m',$Message)
    Invoke-Checked git @('push','-u','origin','main')
} finally { Pop-Location }
