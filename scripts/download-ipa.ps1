<# Downloads latest successful main run containing the selected app, or a specific run.
Example: ./scripts/download-ipa.ps1 -Repo OWNER/REPO -App MyFirstApp #>
[CmdletBinding()] param([string]$Repo, [ValidatePattern('^[A-Za-z][A-Za-z0-9_]{0,49}$')][string]$App = 'MyFirstApp', [long]$RunId = 0)
. "$PSScriptRoot/common.ps1"
$gh = Assert-Gh
$Repo = Resolve-Repo $Repo
if (!$RunId) {
    $raw = & $gh run list --repo $Repo --workflow build-ios.yml --branch main --status success --limit 30 --json databaseId
    if ($LASTEXITCODE -ne 0) { throw 'Cannot list workflow runs.' }
    $runs = @($raw | ConvertFrom-Json)
} else { $runs = @([pscustomobject]@{ databaseId = $RunId }) }
foreach ($run in $runs) {
    $id = [long]$run.databaseId
    $statusRaw = & $gh run view $id --repo $Repo --json conclusion,headSha,url
    if ($LASTEXITCODE -ne 0) { throw 'Cannot inspect run.' }
    $status = $statusRaw | ConvertFrom-Json
    if ($status.conclusion -ne 'success') { throw "Run $id did not succeed." }
    $dest = Join-Path $script:Root "artifacts/downloads/$id/$([guid]::NewGuid().ToString('N'))"
    New-Item -ItemType Directory -Path $dest -Force | Out-Null
    & $gh run download $id --repo $Repo --pattern "ios-unsigned-$id-*" --dir $dest
    if ($LASTEXITCODE -ne 0) {
        if ($RunId) { throw 'Artifact download failed or expired.' }
        continue
    }
    $ipas = @(Get-ChildItem $dest -Recurse -Filter "$App-unsigned.ipa")
    if (!$ipas.Count) { continue }
    if ($ipas.Count -ne 1) { throw 'Ambiguous IPA artifacts; inspect run attempts.' }
    $ipa = $ipas[0]
    $manifest = Get-Content (Join-Path $ipa.DirectoryName 'manifest.json') -Raw | ConvertFrom-Json
    $config = Get-Content (Join-Path $script:Root "apps/$App/app.json") -Raw | ConvertFrom-Json
    if ($manifest.commit -ne $status.headSha -or [string]$manifest.runId -ne [string]$id) { throw 'Manifest provenance mismatch.' }
    if ((Get-FileHash $ipa.FullName -Algorithm SHA256).Hash.ToLowerInvariant() -ne $manifest.sha256) { throw 'IPA checksum mismatch.' }
    Invoke-Checked python @("$PSScriptRoot/validate_ipa.py", $ipa.FullName, '--bundle-id', $config.bundleId)
    $ready = Join-Path $script:Root "artifacts/latest/$App"
    New-Item -ItemType Directory -Path $ready -Force | Out-Null
    Copy-Item -LiteralPath $ipa.FullName -Destination (Join-Path $ready $ipa.Name) -Force
    Copy-Item -LiteralPath (Join-Path $ipa.DirectoryName 'manifest.json') -Destination (Join-Path $ready 'manifest.json') -Force
    Copy-Item -LiteralPath (Join-Path $ipa.DirectoryName 'SHA256SUMS') -Destination (Join-Path $ready 'SHA256SUMS') -Force
    Write-Host "Verified download: $($ipa.FullName)"
    Write-Host "Commit: $($status.headSha) | $($status.url)"
    Write-Output (Join-Path $ready $ipa.Name)
    return
}
throw 'No matching valid retained artifact in recent successful runs. Rebuild or pass -RunId.'
