# Migrate-RepoToGitHub.ps1
# Script to migrate a Git repository to GitHub using environment variables for security

param(
    [Parameter(Position=0, HelpMessage="Source repository URL to migrate")]
    [string]$SourceRepoUrl,
    [switch]$KeepLocalRepo,
    [switch]$SetupForEnhancement,
    [switch]$Help
)

# Hard-coded target organization
$TARGET_GITHUB_ORG = "oop-jccc"

# Show help if requested
if ($Help) {
    Write-Host "=== Git Repository Migration to GitHub - Help ===" -ForegroundColor Green
    Write-Host ""
    Write-Host "This script migrates a Git repository to GitHub using environment variables for security." -ForegroundColor White
    Write-Host ""
    Write-Host "Features:" -ForegroundColor Yellow
    Write-Host "  • Migrates all branches (excluding feature/bugfix/fix branches)" -ForegroundColor White
    Write-Host "  • Migrates all repository tags with verification" -ForegroundColor White
    Write-Host "  • Sets appropriate default branch on GitHub (main > master > first available)" -ForegroundColor White
    Write-Host "  • Automatic cleanup of temporary local repository" -ForegroundColor White
    Write-Host "  • Optional setup for immediate enhancement workflow" -ForegroundColor White
    Write-Host "  • Uses environment variable for secure PAT handling" -ForegroundColor White
    Write-Host ""
    Write-Host "Prerequisites:" -ForegroundColor Yellow
    Write-Host "  • Set GIT_PAT environment variable with your GitHub Personal Access Token" -ForegroundColor White
    Write-Host "  • Target organization: $TARGET_GITHUB_ORG" -ForegroundColor White
    Write-Host ""
    Write-Host "Parameters:" -ForegroundColor Yellow
    Write-Host "  SourceRepoUrl         Source repository URL to migrate (required)" -ForegroundColor White
    Write-Host "  -KeepLocalRepo        Skip automatic cleanup of the local repository directory" -ForegroundColor White
    Write-Host "  -SetupForEnhancement  After migration, clone the new GitHub repo for immediate enhancement work" -ForegroundColor White
    Write-Host "  -Help                 Show this help message" -ForegroundColor White
    Write-Host ""
    Write-Host "Example usage:" -ForegroundColor Yellow
    Write-Host "  Migrate-RepoToGitHub.ps1 https://github.com/source/repo.git" -ForegroundColor White
    Write-Host "  Migrate-RepoToGitHub.ps1 -KeepLocalRepo https://github.com/source/repo.git" -ForegroundColor White
    Write-Host "  Migrate-RepoToGitHub.ps1 -SetupForEnhancement https://github.com/source/repo.git" -ForegroundColor White
    Write-Host ""
    exit 0
}

# Global variables for cleanup tracking
$script:OriginalLocation = Get-Location
$script:RepoDirectoryCreated = $false
$script:ChangedToRepoDirectory = $false

Write-Host "=== Git Repository Migration to GitHub ===" -ForegroundColor Green
Write-Host ""

# Validate environment variable for PAT
Write-Host "Checking environment variables..." -ForegroundColor Yellow

# Check if the environment variable exists
if (-not (Test-Path env:GIT_PAT)) {
    Write-Host "ERROR: GIT_PAT environment variable is not set!" -ForegroundColor Red
    Write-Host ""
    Write-Host "Please set your GitHub Personal Access Token as an environment variable:" -ForegroundColor Yellow
    Write-Host "  PowerShell: `$env:GIT_PAT = 'your_token_here'" -ForegroundColor White
    Write-Host "  Command Prompt: set GIT_PAT=your_token_here" -ForegroundColor White
    Write-Host "  System Environment Variables: Add GIT_PAT with your token value" -ForegroundColor White
    Write-Host ""
    Write-Host "For security reasons, this script does not accept PAT as a parameter." -ForegroundColor Yellow
    exit 1
}

# Check if the environment variable is empty
if ([string]::IsNullOrWhiteSpace($env:GIT_PAT)) {
    Write-Host "ERROR: GIT_PAT environment variable is empty!" -ForegroundColor Red
    Write-Host "Please ensure the GIT_PAT environment variable contains your GitHub Personal Access Token." -ForegroundColor Yellow
    exit 1
}

Write-Host "SUCCESS: GIT_PAT environment variable found" -ForegroundColor Green

# Validate source repository URL
if ([string]::IsNullOrWhiteSpace($SourceRepoUrl)) {
    Write-Host "ERROR: Source repository URL is required!" -ForegroundColor Red
    Write-Host ""
    Write-Host "Usage:" -ForegroundColor Yellow
    Write-Host "  Migrate-RepoToGitHub.ps1 <source-repo-url>" -ForegroundColor White
    Write-Host ""
    Write-Host "Example:" -ForegroundColor Yellow
    Write-Host "  Migrate-RepoToGitHub.ps1 https://github.com/source/repo.git" -ForegroundColor White
    Write-Host ""
    Write-Host "Use -Help for more information." -ForegroundColor Yellow
    exit 1
}

# Basic URL validation
if ($SourceRepoUrl -notmatch '^https?://.*\.git$|^git@.*\.git$|^https?://github\.com/.*$') {
    Write-Host "WARNING: Source repository URL format may be invalid." -ForegroundColor Yellow
    Write-Host "Expected formats: https://github.com/user/repo.git or git@github.com:user/repo.git" -ForegroundColor Yellow
    $confirm = Read-Host "Continue anyway? (y/N)"
    if ($confirm -ne 'y' -and $confirm -ne 'Y') {
        Write-Host "Migration cancelled." -ForegroundColor Yellow
        exit 0
    }
}

# Set values from environment and constants
$GitHubOrgName = $TARGET_GITHUB_ORG
$script:PlainTextToken = $env:GIT_PAT

# Hardcoded Values
$GitHubUsername = "d-german"

Write-Host ""
Write-Host "Configuration:" -ForegroundColor Yellow
Write-Host "  • Source Repository: $SourceRepoUrl" -ForegroundColor White
Write-Host "  • Target Organization: $GitHubOrgName" -ForegroundColor White
Write-Host "  • GitHub PAT: [LOADED FROM ENVIRONMENT]" -ForegroundColor White
Write-Host ""

# Helper function to convert HTTPS URL to SSH format
function Convert-HttpsToSsh {
    param(
        [string]$HttpsUrl
    )

    if ($HttpsUrl -match 'https://github\.com/([^/]+)/(.+?)(?:\.git)?/?$') {
        $org = $matches[1]
        $repo = $matches[2]
        return "git@github.com:$org/$repo.git"
    }

    # If it's not a GitHub HTTPS URL, return as-is
    return $HttpsUrl
}

# Helper function to create repository on GitHub
function New-GitHubRepository {
    param(
        [string]$OrgName,
        [string]$RepoName,
        [string]$AccessToken,
        [string]$Description = "Migrated repository"
    )

    Write-Host "Creating repository '$RepoName' in organization '$OrgName'..." -ForegroundColor Cyan

    try {
        # Check if repository already exists
        $checkUrl = "https://api.github.com/repos/$OrgName/$RepoName"
        $checkHeaders = @{
            "Authorization" = "token $AccessToken"
            "Accept" = "application/vnd.github.v3+json"
            "User-Agent" = "PowerShell-Migration-Script"
        }

        try {
            Invoke-RestMethod -Uri $checkUrl -Method GET -Headers $checkHeaders | Out-Null
            Write-Host "✓ Repository already exists: https://github.com/$OrgName/$RepoName" -ForegroundColor Yellow
            return $true
        } catch {
            # Repository doesn't exist, which is what we want
            if ($_.Exception.Response.StatusCode.value__ -eq 404) {
                Write-Host "Repository doesn't exist yet - proceeding with creation..." -ForegroundColor Green
            } else {
                Write-Host "Warning: Could not check if repository exists - $_" -ForegroundColor Yellow
            }
        }

        # Create the repository
        $createUrl = "https://api.github.com/orgs/$OrgName/repos"
        $createHeaders = @{
            "Authorization" = "token $AccessToken"
            "Accept" = "application/vnd.github.v3+json"
            "User-Agent" = "PowerShell-Migration-Script"
        }
        $createBody = @{
            "name" = $RepoName
            "description" = $Description
            "private" = $false
            "has_issues" = $true
            "has_projects" = $true
            "has_wiki" = $true
        } | ConvertTo-Json

        $newRepo = Invoke-RestMethod -Uri $createUrl -Method POST -Headers $createHeaders -Body $createBody -ContentType "application/json"
        Write-Host "✓ Repository created successfully: $($newRepo.html_url)" -ForegroundColor Green
        return $true

    } catch {
        $errorMessage = $_.Exception.Message
        if ($_.Exception.Response) {
            $statusCode = $_.Exception.Response.StatusCode.value__
            Write-Host "✗ Failed to create repository (HTTP $statusCode): $errorMessage" -ForegroundColor Red

            # Try to get more detailed error information
            try {
                $errorStream = $_.Exception.Response.GetResponseStream()
                $reader = New-Object System.IO.StreamReader($errorStream)
                $errorBody = $reader.ReadToEnd()
                $errorJson = $errorBody | ConvertFrom-Json
                if ($errorJson.message) {
                    Write-Host "GitHub API Error: $($errorJson.message)" -ForegroundColor Red
                }
            } catch {
                # Ignore errors when trying to read error details
            }
        } else {
            Write-Host "✗ Failed to create repository: $errorMessage" -ForegroundColor Red
        }
        return $false
    }
}

# Helper function to execute Git commands with HTTPS-to-SSH fallback
function Invoke-GitWithFallback {
    param(
        [string]$Operation,
        [string]$HttpsUrl,
        [string[]]$GitArgs,
        [string]$SuccessMessage,
        [string]$FailureMessage,
        [switch]$ThrowOnFailure
    )

    Write-Host "Attempting $Operation using HTTPS..." -ForegroundColor Cyan

    # First attempt with HTTPS
    $gitCommand = @('git') + $GitArgs
    & $gitCommand[0] $gitCommand[1..($gitCommand.Length-1)] | Out-Null

    if ($LASTEXITCODE -eq 0) {
        Write-Host "SUCCESS: $SuccessMessage (HTTPS)" -ForegroundColor Green
        return $true
    }

    # HTTPS failed, try SSH fallback
    Write-Host "WARNING: HTTPS $Operation failed (exit code: $LASTEXITCODE)" -ForegroundColor Yellow
    Write-Host "Attempting $Operation using SSH fallback..." -ForegroundColor Cyan

    # Convert HTTPS URL to SSH format
    $sshUrl = Convert-HttpsToSsh -HttpsUrl $HttpsUrl

    # Replace HTTPS URL with SSH URL in the git arguments
    $sshGitArgs = $GitArgs | ForEach-Object {
        if ($_ -eq $HttpsUrl -or $_ -match '^https://.*@github\.com/') {
            $sshUrl
        } else {
            $_
        }
    }

    # Execute with SSH
    $sshGitCommand = @('git') + $sshGitArgs
    & $sshGitCommand[0] $sshGitCommand[1..($sshGitCommand.Length-1)] | Out-Null

    if ($LASTEXITCODE -eq 0) {
        Write-Host "SUCCESS: $SuccessMessage (SSH fallback)" -ForegroundColor Green
        return $true
    } else {
        Write-Host "ERROR: SSH $Operation also failed (exit code: $LASTEXITCODE)" -ForegroundColor Red
        Write-Host "$FailureMessage" -ForegroundColor Red

        if ($ThrowOnFailure) {
            throw "Both HTTPS and SSH $Operation failed"
        }
        return $false
    }
}

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
        Write-Host "SUCCESS: Personal Access Token cleared from memory" -ForegroundColor Green
    }
    
    # Return to original directory if we changed directories
    if ($script:ChangedToRepoDirectory) {
        Write-Host "Returning to original directory..." -ForegroundColor Cyan
        try {
            Set-Location $script:OriginalLocation
            Write-Host "SUCCESS: Returned to original directory: $($script:OriginalLocation)" -ForegroundColor Green
        } catch {
            Write-Host "WARNING: Could not return to original directory - $_" -ForegroundColor Yellow
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
                Write-Host "SUCCESS: Local repository directory removed: $repoPath" -ForegroundColor Green
            } catch {
                Write-Host "WARNING: Could not remove local repository directory - $_" -ForegroundColor Yellow
                Write-Host "  You may need to manually delete: $repoPath" -ForegroundColor Yellow
            }
        }
    }
    
    Write-Host "Cleanup completed." -ForegroundColor Cyan
}

# Function to setup fresh clone for enhancement workflow
function Invoke-EnhancementSetup {
    param(
        [string]$GitHubRepoUrl,
        [string]$RepoName
    )

    Write-Host ""
    Write-Host "=== Setting Up Repository for Enhancement Workflow ===" -ForegroundColor Green

    # Return to original location
    if ($script:ChangedToRepoDirectory) {
        Write-Host "Returning to original directory..." -ForegroundColor Cyan
        Set-Location $script:OriginalLocation
    }

    # Remove the source repository clone
    $sourceRepoPath = Join-Path $script:OriginalLocation $RepoName
    if (Test-Path $sourceRepoPath) {
        Write-Host "Removing source repository clone..." -ForegroundColor Cyan
        try {
            # Force removal of read-only files that Git might create
            Get-ChildItem $sourceRepoPath -Recurse -Force | ForEach-Object {
                if ($_.Attributes -band [System.IO.FileAttributes]::ReadOnly) {
                    $_.Attributes = $_.Attributes -band (-bnot [System.IO.FileAttributes]::ReadOnly)
                }
            }
            Remove-Item $sourceRepoPath -Recurse -Force
            Write-Host "SUCCESS: Source repository clone removed" -ForegroundColor Green
        } catch {
            Write-Host "WARNING: Could not remove source repository clone - $_" -ForegroundColor Yellow
            Write-Host "  You may need to manually delete: $sourceRepoPath" -ForegroundColor Yellow
        }
    }

    # Clone the new GitHub repository
    Write-Host "Cloning the new GitHub repository for enhancement work..." -ForegroundColor Cyan
    try {
        $cloneSuccess = Invoke-GitWithFallback -Operation "clone for enhancement" -HttpsUrl $GitHubRepoUrl -GitArgs @("clone", $GitHubRepoUrl, $RepoName) -SuccessMessage "GitHub repository cloned successfully" -FailureMessage "Failed to clone GitHub repository"

        if ($cloneSuccess) {
            # Change to the new repository directory
            Set-Location $RepoName
            $script:ChangedToRepoDirectory = $true

            Write-Host ""
            Write-Host "✅ ENHANCEMENT SETUP COMPLETE" -ForegroundColor Green
            Write-Host "Repository is ready for enhancement workflow:" -ForegroundColor Green
            Write-Host "  • Current directory: $(Get-Location)" -ForegroundColor White
            Write-Host "  • Remote origin: $GitHubRepoUrl" -ForegroundColor White
            Write-Host ""
            Write-Host "Next steps:" -ForegroundColor Yellow
            Write-Host "  1. Run: .\Enhance-DotNetRepository.ps1 -RepositoryPath '.' " -ForegroundColor White
            Write-Host "  2. Run: .\Update-DotNetProjectsAllBranches.ps1 -RepositoryPath '.' " -ForegroundColor White
            Write-Host ""

            return $true
        } else {
            Write-Host "ERROR: Failed to clone GitHub repository for enhancement" -ForegroundColor Red
            return $false
        }
    } catch {
        Write-Host "ERROR: Exception during enhancement setup - $_" -ForegroundColor Red
        return $false
    }
}

Write-Host ""
Write-Host "Starting migration process..." -ForegroundColor Green

# Main script execution with error handling
try {
    # Token is already set from environment variable

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

    # Use source repository name for destination
    $DestRepoName = $RepoName
    Write-Host ""
    Write-Host "Repository name: $RepoName" -ForegroundColor Yellow
    Write-Host "Destination repository: $DestRepoName" -ForegroundColor Green

    # Clone the source repository
    Write-Host ""
    Write-Host "Cloning source repository..." -ForegroundColor Cyan
    try {
        # Check if directory will be created (Git creates it even on failure)
        $repoPath = Join-Path (Get-Location) $RepoName

        $cloneSuccess = Invoke-GitWithFallback -Operation "clone" -HttpsUrl $SourceRepoUrl -GitArgs @("clone", $SourceRepoUrl, $RepoName) -SuccessMessage "Repository cloned successfully" -FailureMessage "Failed to clone repository with both HTTPS and SSH" -ThrowOnFailure

        # Check if directory was created (even on failure, Git might create an empty directory)
        if (Test-Path $repoPath) {
            $script:RepoDirectoryCreated = $true
        }

        if (-not $cloneSuccess) {
            throw "Clone operation failed"
        }
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

    # Create GitHub repository
    Write-Host ""
    $repoCreated = New-GitHubRepository -OrgName $GitHubOrgName -RepoName $DestRepoName -AccessToken $script:PlainTextToken -Description "Migrated from $SourceRepoUrl"
    if (-not $repoCreated) {
        Write-Host "Error: Failed to create GitHub repository" -ForegroundColor Red
        throw "Failed to create GitHub repository"
    }

    # Add GitHub remote
    Write-Host ""
    Write-Host "Adding GitHub remote..." -ForegroundColor Cyan
    $GitHubRepoUrl = "https://github.com/$GitHubOrgName/$DestRepoName.git"
    try {
        Invoke-GitWithFallback -Operation "remote add" -HttpsUrl $GitHubRepoUrl -GitArgs @("remote", "add", "github", $GitHubRepoUrl) -SuccessMessage "GitHub remote added: $GitHubRepoUrl" -FailureMessage "Failed to add GitHub remote with both HTTPS and SSH" -ThrowOnFailure | Out-Null
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

            # Push to GitHub with HTTPS-to-SSH fallback
            $AuthUrl = "https://$GitHubUsername`:$script:PlainTextToken@github.com/$GitHubOrgName/$DestRepoName.git"
            $pushSuccess = Invoke-GitWithFallback -Operation "push branch" -HttpsUrl $AuthUrl -GitArgs @("push", $AuthUrl, $branch) -SuccessMessage "Successfully pushed branch: $branch" -FailureMessage "Failed to push branch: $branch"

            if (-not $pushSuccess) {
                Write-Host "Warning: Failed to push branch: $branch with both HTTPS and SSH" -ForegroundColor Yellow
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
            $tagPushSuccess = Invoke-GitWithFallback -Operation "push tags" -HttpsUrl $AuthUrl -GitArgs @("push", $AuthUrl, "--tags") -SuccessMessage "All $tagCount tag(s) pushed successfully" -FailureMessage "Failed to push tags"

            if ($tagPushSuccess) {
                # Verify tags were pushed by checking remote tags
                Write-Host "Verifying tag migration..." -ForegroundColor Cyan

                # Try HTTPS first, then SSH for verification
                $sshUrl = Convert-HttpsToSsh -HttpsUrl $AuthUrl
                $remoteTags = git ls-remote --tags $AuthUrl 2>$null | ForEach-Object {
                    if ($_ -match 'refs/tags/(.+)$') { $matches[1] }
                } | Where-Object { $_ -notmatch '\^{}$' }

                # If HTTPS verification failed, try SSH
                if (-not $remoteTags) {
                    Write-Host "HTTPS tag verification failed, trying SSH..." -ForegroundColor Yellow
                    $remoteTags = git ls-remote --tags $sshUrl 2>$null | ForEach-Object {
                        if ($_ -match 'refs/tags/(.+)$') { $matches[1] }
                    } | Where-Object { $_ -notmatch '\^{}$' }
                }

                if ($remoteTags) {
                    $remoteTagCount = ($remoteTags | Measure-Object).Count
                    if ($remoteTagCount -eq $tagCount) {
                        Write-Host "✓ Tag verification successful: $remoteTagCount/$tagCount tags confirmed on GitHub" -ForegroundColor Green
                    } else {
                        Write-Host "⚠ Warning: Tag count mismatch - Local: $tagCount, Remote: $remoteTagCount" -ForegroundColor Yellow
                    }
                } else {
                    Write-Host "⚠ Warning: Could not verify remote tags with either HTTPS or SSH" -ForegroundColor Yellow
                }
            } else {
                Write-Host "⚠ Warning: Failed to push tags with both HTTPS and SSH" -ForegroundColor Yellow
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

            Invoke-RestMethod -Uri $apiUrl -Method PATCH -Headers $headers -Body $body -ContentType "application/json" | Out-Null
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

    # Setup for enhancement workflow if requested
    if ($SetupForEnhancement) {
        $enhancementSetupSuccess = Invoke-EnhancementSetup -GitHubRepoUrl $GitHubRepoUrl -RepoName $RepoName
        if (-not $enhancementSetupSuccess) {
            Write-Host "⚠️ Warning: Enhancement setup failed. You can manually clone the repository:" -ForegroundColor Yellow
            Write-Host "  git clone $GitHubRepoUrl" -ForegroundColor White
            Write-Host ""
        }
    } else {
        Write-Host "Next steps:" -ForegroundColor Yellow
        Write-Host "1. Verify the repository on GitHub" -ForegroundColor White
        Write-Host "2. Clone the repository for local development:" -ForegroundColor White
        Write-Host "   git clone https://github.com/$GitHubOrgName/$DestRepoName.git" -ForegroundColor Cyan
        Write-Host "3. Update any CI/CD pipelines or integrations" -ForegroundColor White
        Write-Host "4. Notify team members of the new repository location" -ForegroundColor White
        Write-Host ""
    }

} catch {
    Write-Host ""
    Write-Host "=== Migration Failed ===" -ForegroundColor Red
    Write-Host "Error: $_" -ForegroundColor Red
    Write-Host ""
    
    # Perform error cleanup
    # On error, always clean up unless KeepLocalRepo is specified
    # SetupForEnhancement doesn't matter on error since the setup would have failed
    Invoke-Cleanup -SkipRepoCleanup:$KeepLocalRepo -IsErrorCleanup:$true
    exit 1
} finally {
    # Always perform cleanup on successful completion (only if no exception was thrown)
    if ($? -and -not $Error.Count) {
        # Determine if we should clean up the repository
        # Skip cleanup if SetupForEnhancement was used (we want to keep the new clone)
        # or if KeepLocalRepo was specified
        $shouldCleanupRepo = -not $KeepLocalRepo -and -not $SetupForEnhancement

        if ($SetupForEnhancement) {
            Write-Host "Enhancement setup completed. Repository ready for development work." -ForegroundColor Green
        } elseif ($KeepLocalRepo) {
            Write-Host "Local repository directory '$RepoName' will be kept (KeepLocalRepo parameter specified)." -ForegroundColor Yellow
        } elseif ($script:RepoDirectoryCreated) {
            Write-Host "Automatically cleaning up local repository directory..." -ForegroundColor Cyan
        }

        # Perform cleanup (but skip repo cleanup if SetupForEnhancement was used)
        Invoke-Cleanup -SkipRepoCleanup:(-not $shouldCleanupRepo)

        if ($shouldCleanupRepo) {
            Write-Host ""
            Write-Host "Migration completed successfully with automatic cleanup." -ForegroundColor Green
        } elseif (-not $SetupForEnhancement) {
            Write-Host ""
            Write-Host "Migration completed successfully. Local repository preserved at: $RepoName" -ForegroundColor Green
        }
    }
}
