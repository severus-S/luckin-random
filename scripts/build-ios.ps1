<# Dispatch an existing remote ref. -BillingChecked confirms you checked GitHub budget/allowance.
   -Wait watches the run identified by the dispatch response (never guesses the latest run).
   Example: ./scripts/build-ios.ps1 -Repo OWNER/REPO -BillingChecked -Wait #>
[CmdletBinding()] param([string]$Repo, [string]$App = 'ALL', [string]$Ref = 'main', [switch]$BillingChecked, [switch]$Wait)
. "$PSScriptRoot/common.ps1"
if (!$BillingChecked) { throw 'Check GitHub Settings > Billing & licensing > usage/budgets first, then pass -BillingChecked.' }
$gh = Assert-Gh
$Repo = Resolve-Repo $Repo
$body = @{ ref = $Ref; inputs = @{ app = $App } } | ConvertTo-Json -Compress
$response = $body | & $gh api --method POST "repos/$Repo/actions/workflows/build-ios.yml/dispatches" -H 'X-GitHub-Api-Version: 2026-03-10' --input -
if ($LASTEXITCODE -ne 0) { throw 'Workflow dispatch failed; check remote workflow, write access, and default branch.' }
$run = $response | ConvertFrom-Json
if (!$run.workflow_run_id) { throw 'Server did not return a run ID. Inspect gh run list; do not assume another run is yours.' }
Write-Host "Run ID: $($run.workflow_run_id) $($run.html_url)"
if ($Wait) { Invoke-Checked $gh @('run','watch', [string]$run.workflow_run_id, '--repo', $Repo, '--exit-status') }
