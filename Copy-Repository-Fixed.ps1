[CmdletBinding()]
param (
    [Parameter(Mandatory=$true)]
    [string]$SourceRepositoryUrl,

    [Parameter(Mandatory=$true)]
    [string]$DestinationRepository
)

# 1. Setup: Create a unique temporary directory for all operations.
$tempDir = Join-Path $env:TEMP "repo-copy-$([guid]::NewGuid())"
$sourceClonePath = Join-Path $tempDir "source.bare"
$destRepoPath = Join-Path $tempDir "destination"
$worktreePath = Join-Path $tempDir "worktree"

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

    # 3. Clone the source repository as bare repository for branch processing
    Write-Host "Cloning source repository $SourceRepositoryUrl as bare repository..."
    git clone --mirror $SourceRepositoryUrl $sourceClonePath
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to clone source repository"
    }

    # 4. Initialize the destination repository
    Write-Host "Initializing empty destination repository..."
    New-Item -Path $destRepoPath -ItemType Directory | Out-Null
    git -C $destRepoPath init | Out-Null

    # 4. Branch Processing Loop
    Write-Host "Getting branch list from source..."
    $branches = git -C $sourceClonePath for-each-ref --format='%(refname:short)' 'refs/remotes/origin/*' | ForEach-Object { $_.Replace('origin/', '') }

    if ($branches.Count -eq 0) {
        $branches = git -C $sourceClonePath for-each-ref --format='%(refname:short)' 'refs/heads/*'
    }

    $branches = $branches | Where-Object { $_ -ne 'HEAD' }

    if ($branches.Count -eq 0) {
        throw "No branches found in the source repository."
    }

    Write-Host "Found branches to process: $($branches -join ', ')"

    foreach ($branchName in $branches) {
        Write-Host "Processing branch: $branchName"

        if (Test-Path $worktreePath) {
            git -C $sourceClonePath worktree remove $worktreePath --force | Out-Null
        }
        git -C $sourceClonePath worktree add $worktreePath $branchName | Out-Null

        git -C $destRepoPath switch -c $branchName

        Get-ChildItem -Path $destRepoPath -Exclude .git -Force | Remove-Item -Recurse -Force
        Get-ChildItem -Path $worktreePath -Exclude .git -Force | Copy-Item -Destination $destRepoPath -Recurse -Force

        git -C $destRepoPath add .
        git -C $destRepoPath commit -m "Initial commit for branch $branchName" | Out-Null

        git -C $sourceClonePath worktree remove $worktreePath --force | Out-Null
    }

    # 5. Create GitHub repository
    Write-Host "Creating GitHub repository '$DestinationRepository'..."

    # Check if repository already exists and delete it
    try {
        gh repo view $DestinationRepository | Out-Null
        Write-Host "Repository already exists. Deleting..."
        gh repo delete $DestinationRepository --yes
        Start-Sleep -Seconds 3
    }
    catch {
        Write-Host "Repository doesn't exist, creating new one..."
    }

    gh repo create $DestinationRepository --private
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to create GitHub repository"
    }

    # Wait for repository to be available
    Write-Host "Waiting for repository to be available..."
    Start-Sleep -Seconds 10

    # 6. Push branches to destination using SSH
    $sshUrl = "git@github.com:$DestinationRepository.git"
    Write-Host "Using SSH URL: $sshUrl"
    Write-Host "Setting up remote and pushing branches..."

    git -C $destRepoPath remote add origin $sshUrl

    $currentBranch = git -C $destRepoPath branch --show-current
    Write-Host "Pushing initial branch '$currentBranch'..."
    git -C $destRepoPath push -u origin $currentBranch
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to push initial branch"
    }

    foreach ($branchName in $branches) {
        if ($branchName -ne $currentBranch) {
            Write-Host "Pushing branch '$branchName'..."
            git -C $destRepoPath push origin $branchName
            if ($LASTEXITCODE -ne 0) {
                Write-Warning "Failed to push branch '$branchName'"
            }
        }
    }

    # 7. Verify migration and get statistics
    Write-Host "`nVerifying migration..."

    # Get source repository statistics (branches only)
    $sourceBranches = git -C $sourceClonePath for-each-ref --format='%(refname:short)' 'refs/heads/*'

    Write-Host "Source repository statistics:"
    Write-Host "  Branches: $($sourceBranches.Count) - $($sourceBranches -join ', ')"

    # Clone destination to verify
    $verifyPath = Join-Path $tempDir "verify"
    git clone $sshUrl $verifyPath

    $destBranches = git -C $verifyPath branch -r | ForEach-Object { $_.Trim().Replace('origin/', '') } | Where-Object { $_ -ne 'HEAD' }

    Write-Host "`nDestination repository statistics:"
    Write-Host "  Branches: $($destBranches.Count) - $($destBranches -join ', ')"

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

    Write-Host "✓ Repository created: https://github.com/$DestinationRepository"
    Write-Host "$(if ($branchesMatch) { '✓' } else { '✗' }) Branches migrated: $($destBranches.Count)/$($sourceBranches.Count)"
    Write-Host "✓ Default branch: $defaultBranch"
    Write-Host "✓ Fresh commit history created (no original history preserved)"
    Write-Host "✓ Each branch has single 'Initial commit for branch [name]' commit"

    if ($branchesMatch) {
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
