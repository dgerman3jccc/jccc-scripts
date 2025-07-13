<#
.SYNOPSIS
    Creates a private, clean copy of a source repository for a specific student (no git history, all branches recreated as orphan).
.DESCRIPTION
    This script creates a private copy of a source repository for a specific student.
    All branches are copied, but commit history is removed.

    Prerequisites:
    - GitHub CLI installed: https://cli.github.com/
    - Authenticated: gh auth login --scopes "repo,read:org,admin:org"
#>
param(
    [Parameter(Mandatory=$true, HelpMessage="Enter the name of the source repository.")]
    [string]$SourceRepo,
    [Parameter(Mandatory=$true, HelpMessage="Enter the student's email address.")]
    [string]$StudentEmail
)

# Hard-coded values
$OrgName = 'jccc-oop'

# 1. Verify GitHub CLI is available
if (-not (Get-Command gh -ErrorAction SilentlyContinue)) {
    Write-Error "GitHub CLI ('gh') not found. Install it from https://cli.github.com/."
    exit 1
}

# 2. Verify authentication
gh auth status 2>$null
if ($LASTEXITCODE -ne 0) {
    Write-Error "GitHub CLI not authenticated. Run 'gh auth login' first."
    exit 1
}

# 3. Slugify email as team name
$teamSlug = ($StudentEmail -replace '[^a-zA-Z0-9]', '-').ToLower()

# 4. Verify team exists
$null = gh api "orgs/$OrgName/teams/$teamSlug" 2>$null
if ($LASTEXITCODE -ne 0) {
    Write-Error "Team '$teamSlug' doesn't exist. Run Add-Students.ps1 first to create the team."
    exit 1
}

# 5. Verify source repository exists
Write-Host "Verifying source repository '$OrgName/$SourceRepo'..."
gh repo view "$OrgName/$SourceRepo" >$null 2>&1
if ($LASTEXITCODE -ne 0) {
    Write-Error "Source repository '$OrgName/$SourceRepo' not found. Please verify it exists."
    exit 1
}

# 6. Create the student repository name
$studentRepoName = "$teamSlug-$SourceRepo"

# Check if repository already exists and delete it for testing
gh repo view "$OrgName/$studentRepoName" >$null 2>&1
if ($LASTEXITCODE -eq 0) {
    Write-Host "Repository '$OrgName/$studentRepoName' already exists. Deleting for testing purposes..."
    gh repo delete "$OrgName/$studentRepoName" --yes
    if ($LASTEXITCODE -ne 0) {
        Write-Error "Failed to delete existing repository '$OrgName/$studentRepoName'."
        exit 1
    }
}

# Create new private repository
Write-Host "Creating repository '$studentRepoName' in organization '$OrgName'..."
gh repo create "$OrgName/$studentRepoName" --private --description "Private clean copy of $SourceRepo for $StudentEmail" | Out-Null

# 7. Give the team permissions to the repository
Write-Host "Giving team '$teamSlug' write access to repository '$studentRepoName'..."
gh api "orgs/$OrgName/teams/$teamSlug/repos/$OrgName/$studentRepoName" -X PUT -f permission="admin" | Out-Null

# 8. Clone the source repository to a temporary directory
$tempDir = Join-Path -Path $env:TEMP -ChildPath ([guid]::NewGuid().ToString())
New-Item -ItemType Directory -Path $tempDir -Force | Out-Null
Write-Host "Cloning source repository '$SourceRepo' to temporary directory..."
Push-Location $tempDir
try {
    gh repo clone "$OrgName/$SourceRepo" . | Out-Null

    # 9. Get all branches from the source repo
    $branches = git branch -r | ForEach-Object { $_.Trim() -replace 'origin/', '' } | Where-Object { $_ -ne 'HEAD -> main' -and $_ -ne 'main' }
    $branches += "main" # Ensure main is included and processed
    $uniqueBranches = $branches | Select-Object -Unique

    # 10. Create and push main branch first
    Write-Host "Processing branch 'main'..."
    $mainCleanDir = Join-Path -Path $env:TEMP -ChildPath ([guid]::NewGuid().ToString())
    New-Item -ItemType Directory -Path $mainCleanDir -Force | Out-Null
    try {
        git checkout main --force
        Copy-Item -Path "$tempDir\*" -Destination $mainCleanDir -Recurse -Exclude ".git"
        Push-Location $mainCleanDir
        git init -b main
        git remote add origin "https://github.com/$OrgName/$studentRepoName.git"
        git add .
        git commit -m "Initial commit for main"
        git push origin main --force
        Pop-Location
    } finally {
        Remove-Item -Path $mainCleanDir -Recurse -Force -ErrorAction SilentlyContinue
    }

    # 11. Clone student repo and create assignment branch from main
    $studentTempDir = Join-Path -Path $env:TEMP -ChildPath ([guid]::NewGuid().ToString())
    New-Item -ItemType Directory -Path $studentTempDir -Force | Out-Null
    Write-Host "Cloning student repo to create assignment branch..."
    Push-Location $studentTempDir
    try {
        # Ensure $tempDir is checked out to the correct branch before copying
        Push-Location $tempDir
        git checkout assignment --force
        Pop-Location

        git clone "https://github.com/$OrgName/$studentRepoName.git" .
        git checkout -b assignment main
        # Remove all files/folders except .git before copying
        Get-ChildItem -Path $studentTempDir -Force -Exclude ".git" | Remove-Item -Recurse -Force
        Copy-Item -Path "$tempDir\*" -Destination $studentTempDir -Recurse -Force -Exclude ".git"
        git add .
        git commit -m "Initial commit for assignment"
        git push origin assignment --force
    } finally {
        Pop-Location
        Remove-Item -Path $studentTempDir -Recurse -Force -ErrorAction SilentlyContinue
    }

    # 12. Set branch protection for the main branch
    $defaultBranch = "main"
    Write-Host "Setting up branch protection rules for $defaultBranch branch..."
    $protectionBody = @{
        required_status_checks = $null
        enforce_admins = $false
        required_pull_request_reviews = @{
            required_approving_review_count = 1
        }
        restrictions = $null
    } | ConvertTo-Json -Depth 10
    $tempFile = [System.IO.Path]::GetTempFileName()
    Set-Content -Path $tempFile -Value $protectionBody
    gh api "repos/$OrgName/$studentRepoName/branches/$defaultBranch/protection" `
        --method PUT `
        --header "Accept: application/vnd.github+json" `
        --input $tempFile
    Remove-Item -Path $tempFile -Force

    Write-Host "✅ Clean repository '$studentRepoName' created successfully for student '$StudentEmail'."
}
finally {
    # Clean up
    Pop-Location
    Remove-Item -Path $tempDir -Recurse -Force -ErrorAction SilentlyContinue
}
