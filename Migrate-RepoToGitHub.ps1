# Migrate-RepoToGitHub.ps1
# Interactive script to migrate a Git repository to GitHub

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

Write-Host ""
Write-Host "Starting migration process..." -ForegroundColor Green

# Convert secure string token to plain text
$PlainTextToken = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto([System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($SecureToken))

# Extract repository name from source URL
Write-Host "Extracting repository name from source URL..." -ForegroundColor Cyan
$RepoName = ""
if ($SourceRepoUrl -match '([^/]+?)(?:\.git)?/?$') {
    $RepoName = $matches[1] -replace '\.git$', ''
    Write-Host "Repository name extracted: $RepoName" -ForegroundColor Green
} else {
    Write-Host "Error: Could not extract repository name from URL" -ForegroundColor Red
    exit 1
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
    Write-Host "Repository cloned successfully" -ForegroundColor Green
} catch {
    Write-Host "Error: Failed to clone repository - $_" -ForegroundColor Red
    exit 1
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
    exit 1
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
        $AuthUrl = "https://$GitHubUsername`:$PlainTextToken@github.com/$GitHubOrgName/$DestRepoName.git"
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

# Push all tags
Write-Host ""
Write-Host "Pushing all tags..." -ForegroundColor Cyan
try {
    $AuthUrl = "https://$GitHubUsername`:$PlainTextToken@github.com/$GitHubOrgName/$DestRepoName.git"
    git push $AuthUrl --tags
    
    if ($LASTEXITCODE -eq 0) {
        Write-Host "All tags pushed successfully" -ForegroundColor Green
    } else {
        Write-Host "Warning: Some tags may not have been pushed" -ForegroundColor Yellow
    }
} catch {
    Write-Host "Warning: Error pushing tags - $_" -ForegroundColor Yellow
}

# Clear the plain text token from memory
$PlainTextToken = $null

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
