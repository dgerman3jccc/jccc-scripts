# Migrate-RepoToGitHub.ps1
# Interactive script to migrate a Git repository to GitHub

param(
    [switch]$KeepLocalRepo,
    [switch]$Help
)

# Show help if requested
if ($Help) {
    Write-Host "=== Git Repository Migration to GitHub - Help ===" -ForegroundColor Green
    Write-Host ""
    Write-Host "This script migrates a Git repository to GitHub with automatic cleanup functionality." -ForegroundColor White
    Write-Host ""
    Write-Host "Features:" -ForegroundColor Yellow
    Write-Host "  • Migrates all branches (excluding feature/bugfix/fix branches)" -ForegroundColor White
    Write-Host "  • Migrates all repository tags with verification" -ForegroundColor White
    Write-Host "  • Sets appropriate default branch on GitHub (main > master > first available)" -ForegroundColor White
    Write-Host "  • Automatic cleanup of temporary local repository" -ForegroundColor White
    Write-Host ""
    Write-Host "Parameters:" -ForegroundColor Yellow
    Write-Host "  -KeepLocalRepo    Skip automatic cleanup of the local repository directory" -ForegroundColor White
    Write-Host "  -Help             Show this help message" -ForegroundColor White
    Write-Host ""
    Write-Host "Example usage:" -ForegroundColor Yellow
    Write-Host "  .\Migrate-RepoToGitHub.ps1                    # Normal execution with automatic cleanup" -ForegroundColor White
    Write-Host "  .\Migrate-RepoToGitHub.ps1 -KeepLocalRepo     # Keep local repo for verification/debugging" -ForegroundColor White
    Write-Host ""
    exit 0
}

# Global variables for cleanup tracking
$script:OriginalLocation = Get-Location
$script:RepoDirectoryCreated = $false
$script:ChangedToRepoDirectory = $false

Write-Host "=== Git Repository Migration to GitHub ===" -ForegroundColor Green
Write-Host ""

# Interactive Prompts
Write-Host "This script will help you migrate a Git repository to GitHub." -ForegroundColor Yellow
Write-Host ""

# Prompt for Source Repository URL
$SourceRepoUrl = Read-Host "Please enter the full source repository URL to clone"

# Prompt for GitHub Personal Access Token (hidden input)
Write-Host ""
$SecureToken = Read-Host "Please enter your GitHub Personal Access Token (PAT)" -AsSecureString

# Hardcoded Values
$GitHubOrgName = "HylandSoftware"
$GitHubUsername = "d-german"

# Cleanup function
function Invoke-Cleanup {
    param(
        [bool]$SkipRepoCleanup = $false,
        [bool]$IsErrorCleanup = $false
    )
    
    Write-Host ""
    if ($IsErrorCleanup) {
        Write-Host "=== Performing Error Cleanup ===" -ForegroundColor Yellow
    } else {
        Write-Host "=== Performing Cleanup ===" -ForegroundColor Cyan
    }
    
    # Clear sensitive data from memory
    Write-Host "Clearing sensitive data from memory..." -ForegroundColor Cyan
    if ($script:PlainTextToken) {
        $script:PlainTextToken = $null
        [System.GC]::Collect()
        Write-Host "✓ Personal Access Token cleared from memory" -ForegroundColor Green
    }
    if ($SecureToken) {
        $SecureToken.Dispose()
        Write-Host "✓ Secure token disposed" -ForegroundColor Green
    }
    
    # Return to original directory if we changed directories
    if ($script:ChangedToRepoDirectory) {
        Write-Host "Returning to original directory..." -ForegroundColor Cyan
        try {
            Set-Location $script:OriginalLocation
            Write-Host "✓ Returned to original directory: $($script:OriginalLocation)" -ForegroundColor Green
        } catch {
            Write-Host "⚠ Warning: Could not return to original directory - $_" -ForegroundColor Yellow
        }
    }
    
    # Clean up local repository directory if requested and it exists
    if (-not $SkipRepoCleanup -and $script:RepoDirectoryCreated -and $RepoName) {
        $repoPath = Join-Path $script:OriginalLocation $RepoName
        if (Test-Path $repoPath) {
            Write-Host "Removing local repository directory..." -ForegroundColor Cyan
            try {
                # Force removal of read-only files that Git might create
                Get-ChildItem $repoPath -Recurse -Force | ForEach-Object {
                    if ($_.Attributes -band [System.IO.FileAttributes]::ReadOnly) {
                        $_.Attributes = $_.Attributes -band (-bnot [System.IO.FileAttributes]::ReadOnly)
                    }
                }
                Remove-Item $repoPath -Recurse -Force
                Write-Host "✓ Local repository directory removed: $repoPath" -ForegroundColor Green
            } catch {
                Write-Host "⚠ Warning: Could not remove local repository directory - $_" -ForegroundColor Yellow
                Write-Host "  You may need to manually delete: $repoPath" -ForegroundColor Yellow
            }
        }
    }
    
    Write-Host "Cleanup completed." -ForegroundColor Cyan
}

Write-Host ""
Write-Host "Starting migration process..." -ForegroundColor Green

# Main script execution with error handling
try {
    # Convert secure string token to plain text
    $script:PlainTextToken = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto([System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($SecureToken))

    # Extract repository name from source URL
    Write-Host "Extracting repository name from source URL..." -ForegroundColor Cyan
    $RepoName = ""
    if ($SourceRepoUrl -match '([^/]+?)(?:\.git)?/?$') {
        $RepoName = $matches[1] -replace '\.git$', ''
        Write-Host "Repository name extracted: $RepoName" -ForegroundColor Green
    } else {
        Write-Host "Error: Could not extract repository name from URL" -ForegroundColor Red
        throw "Could not extract repository name from URL"
    }

    # Prompt for destination repository name
    Write-Host ""
    Write-Host "The source repository name is: $RepoName" -ForegroundColor Yellow
    $DestRepoName = Read-Host "Please enter the destination repository name (press Enter to use '$RepoName')"
    if ([string]::IsNullOrWhiteSpace($DestRepoName)) {
        $DestRepoName = $RepoName
        Write-Host "Using source repository name for destination: $DestRepoName" -ForegroundColor Green
    } else {
        Write-Host "Destination repository name set to: $DestRepoName" -ForegroundColor Green
    }

    # Clone the source repository
    Write-Host ""
    Write-Host "Cloning source repository..." -ForegroundColor Cyan
    try {
        git clone $SourceRepoUrl $RepoName
        if ($LASTEXITCODE -ne 0) {
            throw "Git clone failed"
        }
        $script:RepoDirectoryCreated = $true
        Write-Host "Repository cloned successfully" -ForegroundColor Green
    } catch {
        Write-Host "Error: Failed to clone repository - $_" -ForegroundColor Red
        throw
    }

    # ============================================================================
    # PLACEHOLDER FOR HISTORY CLEANING
    # ============================================================================
    # If you need to clean the repository history (remove sensitive data, large files, etc.),
    # run the git-filter-repo command at this point, BEFORE changing directory.
    # 
    # Example commands:
    # git-filter-repo --path-glob '*.log' --invert-paths
    # git-filter-repo --strip-blobs-bigger-than 10M
    # git-filter-repo --mailmap mailmap.txt
    #
    # Make sure to install git-filter-repo first: pip install git-filter-repo
    # ============================================================================

    # Change to the cloned repository directory
    Write-Host ""
    Write-Host "Changing to repository directory..." -ForegroundColor Cyan
    Set-Location $RepoName
    $script:ChangedToRepoDirectory = $true

    # Rename master branch to main
    Write-Host ""
    Write-Host "Renaming master branch to main..." -ForegroundColor Cyan
    try {
        $currentBranch = git branch --show-current
        if ($currentBranch -eq "master") {
            git branch -m master main
            Write-Host "Branch renamed from master to main" -ForegroundColor Green
        } else {
            Write-Host "Current branch is '$currentBranch', no rename needed" -ForegroundColor Yellow
        }
    } catch {
        Write-Host "Warning: Could not rename branch - $_" -ForegroundColor Yellow
    }

    # Add GitHub remote
    Write-Host ""
    Write-Host "Adding GitHub remote..." -ForegroundColor Cyan
    $GitHubRepoUrl = "https://github.com/$GitHubOrgName/$DestRepoName.git"
    try {
        git remote add github $GitHubRepoUrl
        Write-Host "GitHub remote added: $GitHubRepoUrl" -ForegroundColor Green
    } catch {
        Write-Host "Error: Failed to add GitHub remote - $_" -ForegroundColor Red
        throw
    }

    # Get list of all branches from origin
    Write-Host ""
    Write-Host "Getting list of branches from origin..." -ForegroundColor Cyan
    $branches = git branch -r --format="%(refname:short)" | Where-Object { $_ -match '^origin/' -and $_ -ne 'origin/HEAD' }
    $branches = $branches | ForEach-Object { $_ -replace '^origin/', '' }

    Write-Host "Found branches: $($branches -join ', ')" -ForegroundColor Green

    # Branch filtering and pushing
    Write-Host ""
    Write-Host "Processing branches..." -ForegroundColor Cyan

    foreach ($branch in $branches) {
        # Filter out feature/*, bugfix/*, fix/* branches
        if ($branch -match '^(feature|bugfix|fix)/') {
            Write-Host "Skipping branch: $branch (matches exclusion pattern)" -ForegroundColor Yellow
            continue
        }
        
        Write-Host "Processing branch: $branch" -ForegroundColor Cyan
        
        try {
            # Checkout the branch
            git checkout -b $branch origin/$branch 2>$null
            if ($LASTEXITCODE -ne 0) {
                git checkout $branch 2>$null
            }
            
            # Push to GitHub with embedded credentials
            $AuthUrl = "https://$GitHubUsername`:$script:PlainTextToken@github.com/$GitHubOrgName/$DestRepoName.git"
            git push $AuthUrl $branch
            
            if ($LASTEXITCODE -eq 0) {
                Write-Host "Successfully pushed branch: $branch" -ForegroundColor Green
            } else {
                Write-Host "Warning: Failed to push branch: $branch" -ForegroundColor Yellow
            }
        } catch {
            Write-Host "Warning: Error processing branch $branch - $_" -ForegroundColor Yellow
        }
    }

    # Push all tags with verification
    Write-Host ""
    Write-Host "Processing repository tags..." -ForegroundColor Cyan

    # Get list of local tags
    $localTags = git tag
    if ($localTags) {
        $tagCount = ($localTags | Measure-Object).Count
        Write-Host "Found $tagCount tag(s) to migrate: $($localTags -join ', ')" -ForegroundColor Green

        Write-Host "Pushing all tags to GitHub..." -ForegroundColor Cyan
        try {
            $AuthUrl = "https://$GitHubUsername`:$script:PlainTextToken@github.com/$GitHubOrgName/$DestRepoName.git"
            $pushOutput = git push $AuthUrl --tags 2>&1

            if ($LASTEXITCODE -eq 0) {
                Write-Host "✓ All $tagCount tag(s) pushed successfully" -ForegroundColor Green

                # Verify tags were pushed by checking remote tags
                Write-Host "Verifying tag migration..." -ForegroundColor Cyan
                $remoteTags = git ls-remote --tags $AuthUrl 2>$null | ForEach-Object {
                    if ($_ -match 'refs/tags/(.+)$') { $matches[1] }
                } | Where-Object { $_ -notmatch '\^{}$' }

                if ($remoteTags) {
                    $remoteTagCount = ($remoteTags | Measure-Object).Count
                    if ($remoteTagCount -eq $tagCount) {
                        Write-Host "✓ Tag verification successful: $remoteTagCount/$tagCount tags confirmed on GitHub" -ForegroundColor Green
                    } else {
                        Write-Host "⚠ Warning: Tag count mismatch - Local: $tagCount, Remote: $remoteTagCount" -ForegroundColor Yellow
                    }
                } else {
                    Write-Host "⚠ Warning: Could not verify remote tags" -ForegroundColor Yellow
                }
            } else {
                Write-Host "⚠ Warning: Tag push failed with exit code $LASTEXITCODE" -ForegroundColor Yellow
                Write-Host "Push output: $pushOutput" -ForegroundColor Yellow
            }
        } catch {
            Write-Host "⚠ Warning: Error pushing tags - $_" -ForegroundColor Yellow
        }
    } else {
        Write-Host "No tags found in repository - skipping tag migration" -ForegroundColor Yellow
    }

    # Set default branch on GitHub
    Write-Host ""
    Write-Host "Configuring default branch on GitHub..." -ForegroundColor Cyan

    # Get list of pushed branches to determine the best default branch
    $pushedBranches = @()
    foreach ($branch in $branches) {
        if ($branch -notmatch '^(feature|bugfix|fix)/') {
            $pushedBranches += $branch
        }
    }

    # Determine the best default branch
    $defaultBranch = $null
    if ($pushedBranches -contains "main") {
        $defaultBranch = "main"
        Write-Host "Setting 'main' as default branch" -ForegroundColor Green
    } elseif ($pushedBranches -contains "master") {
        $defaultBranch = "master"
        Write-Host "Setting 'master' as default branch" -ForegroundColor Green
    } elseif ($pushedBranches.Count -gt 0) {
        $defaultBranch = $pushedBranches[0]
        Write-Host "Setting '$defaultBranch' as default branch (first available branch)" -ForegroundColor Yellow
    }

    if ($defaultBranch) {
        try {
            # GitHub API call to set default branch
            $apiUrl = "https://api.github.com/repos/$GitHubOrgName/$DestRepoName"
            $headers = @{
                "Authorization" = "token $script:PlainTextToken"
                "Accept" = "application/vnd.github.v3+json"
                "User-Agent" = "PowerShell-Migration-Script"
            }
            $body = @{
                "default_branch" = $defaultBranch
            } | ConvertTo-Json

            $response = Invoke-RestMethod -Uri $apiUrl -Method PATCH -Headers $headers -Body $body -ContentType "application/json"
            Write-Host "✓ Default branch successfully set to '$defaultBranch'" -ForegroundColor Green
        } catch {
            $errorMessage = $_.Exception.Message
            if ($_.Exception.Response) {
                $statusCode = $_.Exception.Response.StatusCode.value__
                Write-Host "⚠ Warning: Failed to set default branch (HTTP $statusCode): $errorMessage" -ForegroundColor Yellow
            } else {
                Write-Host "⚠ Warning: Failed to set default branch: $errorMessage" -ForegroundColor Yellow
            }
            Write-Host "  You may need to manually set the default branch in GitHub repository settings" -ForegroundColor Yellow
        }
    } else {
        Write-Host "⚠ Warning: No suitable branches found for setting as default" -ForegroundColor Yellow
    }

    # Success message
    Write-Host ""
    Write-Host "=== Migration Complete ===" -ForegroundColor Green
    Write-Host "Repository '$RepoName' has been successfully migrated to:" -ForegroundColor Green
    Write-Host "https://github.com/$GitHubOrgName/$DestRepoName" -ForegroundColor Green
    Write-Host ""
    Write-Host "Next steps:" -ForegroundColor Yellow
    Write-Host "1. Verify the repository on GitHub" -ForegroundColor White
    Write-Host "2. Update any CI/CD pipelines or integrations" -ForegroundColor White
    Write-Host "3. Notify team members of the new repository location" -ForegroundColor White
    Write-Host ""

} catch {
    Write-Host ""
    Write-Host "=== Migration Failed ===" -ForegroundColor Red
    Write-Host "Error: $_" -ForegroundColor Red
    Write-Host ""
    
    # Perform error cleanup
    Invoke-Cleanup -SkipRepoCleanup:$KeepLocalRepo -IsErrorCleanup:$true
    exit 1
} finally {
    # Always perform cleanup on successful completion
    if (-not $Error.Count) {
        # Determine if we should clean up the repository (automatic cleanup by default)
        $shouldCleanupRepo = -not $KeepLocalRepo

        if ($KeepLocalRepo) {
            Write-Host "Local repository directory '$RepoName' will be kept (KeepLocalRepo parameter specified)." -ForegroundColor Yellow
        } elseif ($script:RepoDirectoryCreated) {
            Write-Host "Automatically cleaning up local repository directory..." -ForegroundColor Cyan
        }

        # Perform cleanup
        Invoke-Cleanup -SkipRepoCleanup:(-not $shouldCleanupRepo)

        if ($shouldCleanupRepo) {
            Write-Host ""
            Write-Host "Migration completed successfully with automatic cleanup." -ForegroundColor Green
        } else {
            Write-Host ""
            Write-Host "Migration completed successfully. Local repository preserved at: $RepoName" -ForegroundColor Green
        }
    }
}
