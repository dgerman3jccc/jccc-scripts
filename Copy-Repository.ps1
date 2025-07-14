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

    # 3. Cloning the Source Repository
    Write-Host "Cloning source repository $SourceRepositoryUrl into a bare repository..."
    git clone --bare $SourceRepositoryUrl $sourceClonePath

    # 4. Initializing the Destination Repository
    Write-Host "Initializing empty destination repository..."
    New-Item -Path $destRepoPath -ItemType Directory | Out-Null
    git -C $destRepoPath init | Out-Null

    # 5. Branch Processing Loop
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

    # 6. GitHub Integration
    Write-Host "Creating GitHub repository '$DestinationRepository' and pushing initial branch..."
    gh repo create $DestinationRepository --private --source=$destRepoPath --push

    $currentBranch = git -C $destRepoPath branch --show-current
    Write-Host "Successfully pushed '$currentBranch'. Pushing remaining branches..."

    foreach ($branchName in $branches) {
        if ($branchName -ne $currentBranch) {
            Write-Host "Pushing branch '$branchName'..."
            git -C $destRepoPath push origin $branchName
        }
    }

    Write-Host "All branches have been pushed successfully."
    Write-Host "Script finished successfully."

}
catch {
    Write-Error "An error occurred during the script execution: $($_.Exception.Message)"
}
finally {
    # 7. Cleanup
    if (Test-Path $tempDir) {
        Write-Host "Cleaning up temporary directory: $tempDir"
        Remove-Item -Recurse -Force $tempDir
    }
}