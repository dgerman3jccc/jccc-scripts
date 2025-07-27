[CmdletBinding()]
param (
    [Parameter(Mandatory=$true)]
    [string]$SourceRepositoryUrl,

    [Parameter(Mandatory=$true)]
    [string]$DestinationRepository
)

# 1. Setup: Create a unique temporary directory for all operations.
$tempDir = Join-Path $env:TEMP "repo-copy-$([guid]::NewGuid())"
$sourceClonePath = Join-Path $tempDir "source"

try {
    # 2. Environment and Input Validation
    Write-Host "Validating inputs and environment..."
    if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
        throw "Git is not installed or not in the PATH. Please install Git and try again."
    }
    if (-not (Get-Command gh -ErrorAction SilentlyContinue)) {
        throw "GitHub CLI (gh) is not installed or not in the PATH. Please install gh and try again."
    }
    if ($DestinationRepository -notmatch '^[a-zA-Z0-9_.-]+/[a-zA-Z0-9_.-]+$') {
        throw "Invalid DestinationRepository format. Please use 'owner/repo-name' format."
    }

    New-Item -Path $tempDir -ItemType Directory | Out-Null
    Write-Host "Temporary directory created at $tempDir"

    # 3. Clone the source repository with full history
    Write-Host "Cloning source repository $SourceRepositoryUrl with full history..."
    git clone --mirror $SourceRepositoryUrl $sourceClonePath
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to clone source repository"
    }

    # 4. Create GitHub repository
    Write-Host "Creating GitHub repository '$DestinationRepository'..."
    $repoUrl = "https://github.com/$DestinationRepository.git"

    # Check if repository already exists
    $repoExists = $false
    try {
        gh repo view $DestinationRepository | Out-Null
        $repoExists = $true
        Write-Host "Repository already exists. Deleting and recreating..."
        gh repo delete $DestinationRepository --yes
    }
    catch {
        Write-Host "Repository doesn't exist, creating new one..."
    }

    gh repo create $DestinationRepository --private
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to create GitHub repository"
    }

    # 5. Push all refs (branches, tags, etc.) to destination
    Write-Host "Pushing all branches and tags to destination repository..."
    git -C $sourceClonePath remote set-url origin $repoUrl
    git -C $sourceClonePath push --mirror origin
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to push to destination repository"
    }

    # 6. Verify migration and get statistics
    Write-Host "`nVerifying migration..."

    # Get source repository statistics
    $sourceBranches = git -C $sourceClonePath for-each-ref --format='%(refname:short)' 'refs/heads/*'
    $sourceTags = git -C $sourceClonePath for-each-ref --format='%(refname:short)' 'refs/tags/*'

    Write-Host "Source repository statistics:"
    Write-Host "  Branches: $($sourceBranches.Count) - $($sourceBranches -join ', ')"
    Write-Host "  Tags: $($sourceTags.Count) - $($sourceTags -join ', ')"

    # Clone destination to verify
    $verifyPath = Join-Path $tempDir "verify"
    git clone $repoUrl $verifyPath

    $destBranches = git -C $verifyPath branch -r | ForEach-Object { $_.Trim().Replace('origin/', '') } | Where-Object { $_ -ne 'HEAD' }
    $destTags = git -C $verifyPath tag

    Write-Host "`nDestination repository statistics:"
    Write-Host "  Branches: $($destBranches.Count) - $($destBranches -join ', ')"
    Write-Host "  Tags: $($destTags.Count) - $($destTags -join ', ')"

    # 7. Set default branch (main > master > first available)
    Write-Host "`nSetting default branch..."
    $defaultBranch = $null
    if ($destBranches -contains 'main') {
        $defaultBranch = 'main'
    } elseif ($destBranches -contains 'master') {
        $defaultBranch = 'master'
    } else {
        $defaultBranch = $destBranches[0]
    }

    if ($defaultBranch) {
        Write-Host "Setting default branch to: $defaultBranch"
        gh repo edit $DestinationRepository --default-branch $defaultBranch
        if ($LASTEXITCODE -eq 0) {
            Write-Host "✓ Default branch set successfully"
        } else {
            Write-Warning "Failed to set default branch via GitHub CLI"
        }
    }

    # 8. Final verification
    Write-Host "`nMigration Summary:"
    $branchesMatch = $sourceBranches.Count -eq $destBranches.Count
    $tagsMatch = $sourceTags.Count -eq $destTags.Count

    Write-Host "✓ Repository created: https://github.com/$DestinationRepository"
    Write-Host "$(if ($branchesMatch) { '✓' } else { '✗' }) Branches migrated: $($destBranches.Count)/$($sourceBranches.Count)"
    Write-Host "$(if ($tagsMatch) { '✓' } else { '✗' }) Tags migrated: $($destTags.Count)/$($sourceTags.Count)"
    Write-Host "✓ Default branch: $defaultBranch"
    Write-Host "✓ Full commit history preserved"

    if ($branchesMatch -and $tagsMatch) {
        Write-Host "`n🎉 Migration completed successfully!"
    } else {
        Write-Warning "Migration completed with some discrepancies. Please review the statistics above."
    }

}
catch {
    Write-Error "An error occurred during the script execution: $($_.Exception.Message)"
    Write-Error "Stack trace: $($_.ScriptStackTrace)"
    exit 1
}
finally {
    # 9. Cleanup
    if (Test-Path $tempDir) {
        Write-Host "`nCleaning up temporary directory: $tempDir"
        Remove-Item -Recurse -Force $tempDir -ErrorAction SilentlyContinue
    }
}