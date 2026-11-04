Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$script:Root = Split-Path $PSScriptRoot -Parent
function Invoke-Checked {
    param([string]$Exe, [string[]]$Arguments)
    & $Exe @Arguments
    if ($LASTEXITCODE -ne 0) { throw "$Exe failed (exit $LASTEXITCODE)." }
}
function Get-Gh {
    $installed = Get-Command gh -ErrorAction SilentlyContinue
    if ($installed) { return $installed.Source }
    $portable = Join-Path $script:Root '.tools/gh/bin/gh.exe'
    if (Test-Path $portable) { return $portable }
    throw 'GitHub CLI missing. Install official gh, then gh auth login.'
}
function Assert-Gh {
    $gh = Get-Gh
    & $gh auth status *> $null
    if ($LASTEXITCODE -ne 0) { throw "GitHub login required. Run: & '$gh' auth login --web --git-protocol https" }
    return $gh
}
function Resolve-Repo {
    param([string]$Repo)
    if ($Repo) {
        if ($Repo -notmatch '^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$') { throw 'Repo must be OWNER/REPO.' }
        return $Repo
    }
    $gh = Assert-Gh
    Push-Location $script:Root
    try {
        $value = & $gh repo view --json nameWithOwner --jq .nameWithOwner
        if ($LASTEXITCODE -ne 0) { throw 'No GitHub repository. Set origin or pass -Repo OWNER/REPO.' }
        return $value.Trim()
    } finally { Pop-Location }
}
