<#
.SYNOPSIS
    Creates a private copy of the abstract-animal-sounds repository for a specific student.
.DESCRIPTION
    This script creates a private copy of the abstract-animal-sounds repository
    for the student with email facmet107@gmail.com under their team slug.

    Prerequisites:
    - GitHub CLI installed: https://cli.github.com/
    - Authenticated: gh auth login --scopes "repo,read:org,admin:org"
#>

# Hard-coded values
$OrgName = 'jccc-oop'
$SourceRepo = 'abstract-animal-sounds'
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

# 5. Create a new repository with team permissions
$studentRepoName = "$teamSlug-$SourceRepo"

# Check if repository already exists
$null = gh repo view "$OrgName/$studentRepoName" 2>$null
if ($LASTEXITCODE -eq 0) {
    Write-Error "Repository '$OrgName/$studentRepoName' already exists."
    exit 1
}

# Create new private repository
Write-Host "Creating repository '$studentRepoName' in organization '$OrgName'..."
gh repo create "$OrgName/$studentRepoName" --private --description "Private copy of $SourceRepo for $StudentEmail" | Out-Null

# 6. Give the team permissions to the repository
Write-Host "Giving team '$teamSlug' write access to repository '$studentRepoName'..."
gh api "orgs/$OrgName/teams/$teamSlug/repos/$OrgName/$studentRepoName" -X PUT -f permission="admin" | Out-Null

# 7. Clone the source repository to a temporary directory
$tempDir = Join-Path -Path $env:TEMP -ChildPath ([guid]::NewGuid().ToString())
New-Item -ItemType Directory -Path $tempDir -Force | Out-Null

Write-Host "Cloning source repository '$SourceRepo' to temporary directory..."
Push-Location $tempDir
try {
    gh repo clone "$OrgName/$SourceRepo" . | Out-Null

    # 8. Add the student repository as a remote and push all branches
    Write-Host "Pushing content to student repository '$studentRepoName'..."
    git remote add student "https://github.com/$OrgName/$studentRepoName.git"

    # Fetch all branches from origin
    git fetch origin --prune

    # Push all local and remote branches to student repository
    git push student --all
    git push student --tags

    # Push all remote branches
    $branches = git branch -r | Where-Object { $_ -match "origin/" -and $_ -notmatch "HEAD" } | ForEach-Object { $_.Trim() }
    foreach ($branch in $branches) {
        $localBranch = $branch -replace "origin/", ""
        Write-Host "Pushing branch $localBranch to student repository..."
        git checkout -b $localBranch $branch --force
        git push student $localBranch
    }

    # Return to main/master branch
    $defaultBranch = git remote show origin | Select-String "HEAD branch" | ForEach-Object { ($_ -split ":")[1].Trim() }
    git checkout $defaultBranch --force

    Write-Host "✅ Repository '$studentRepoName' created successfully for student '$StudentEmail'."
} finally {
    # Clean up
    Pop-Location
    Remove-Item -Path $tempDir -Recurse -Force -ErrorAction SilentlyContinue
}