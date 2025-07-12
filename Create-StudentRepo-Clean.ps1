<#
.SYNOPSIS
    Creates a private, clean copy of a source repository for a specific student (no git history, all branches recreated as orphan).
.DESCRIPTION
    This script creates a private copy of a source repository for the student with email facmet107@gmail.com.
    All branches are copied, but commit history is removed.

    Prerequisites:
    - GitHub CLI installed: https://cli.github.com/
    - Authenticated: gh auth login --scopes "repo,read:org,admin:org"
#>

# Hard-coded values
$OrgName = 'jccc-oop'
$SourceRepo = 'abstract-animal-sounds' # <-- FIX ME: Verify this repository exists in the 'jccc-oop' organization.
$StudentEmail = 'facmet107@gmail.com'

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

    # 10. For each branch, create a clean version and push it
    foreach ($branch in $uniqueBranches) {
        Write-Host "Processing branch '$branch'..."
        # Create a temporary directory for the clean branch
        $cleanDir = Join-Path -Path $env:TEMP -ChildPath ([guid]::NewGuid().ToString())
        New-Item -ItemType Directory -Path $cleanDir -Force | Out-Null

        try {
            # Checkout the branch files into the clean directory
            git checkout $branch --force
            Copy-Item -Path "$tempDir\*" -Destination $cleanDir -Recurse -Exclude ".git"

            Push-Location $cleanDir
            # Initialize a new git repo to remove history
            git init -b $branch
            git remote add origin "https://github.com/$OrgName/$studentRepoName.git"
            git add .
            git commit -m "Initial commit for $branch"
            git push origin $branch --force
            Pop-Location
        }
        finally {
            Remove-Item -Path $cleanDir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    # 11. Set branch protection for the main branch
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
