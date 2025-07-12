<#
.SYNOPSIS
    Creates a private GitHub repository for a student based on a template repository.

.PARAMETER StudentEmail
    Student's email, used to slugify the repo name.

.PARAMETER TemplateRepo
    Template repository to copy (format: owner/name or name if in same org).

.PARAMETER OrgName
    GitHub organization name (default: 'jccc-oop').
#>
Param(
    [Parameter(Mandatory=$true)]
    [string]$StudentEmail,

    [Parameter(Mandatory=$true)]
    [string]$TemplateRepo,

    [Parameter(Mandatory=$false)]
    [string]$OrgName = 'jccc-oop'
)

# Verify GitHub CLI
if (-not (Get-Command gh -ErrorAction SilentlyContinue)) {
    Write-Error "GitHub CLI ('gh') not found. Install from https://cli.github.com/."
    exit 1
}

# Verify authentication
gh auth status 2>$null
if ($LASTEXITCODE -ne 0) {
    Write-Error "GitHub CLI not authenticated. Run 'gh auth login' first."
    exit 1
}

# Slugify template repo name for new repo
if ($TemplateRepo -match '^https?://') {
    if ($TemplateRepo -match 'github\.com/([^/]+/[^/]+)') {
        $templateFull = $matches[1]
        $templateName = ($matches[1].Split('/')[1])
    } else {
        Write-Error "Cannot parse TemplateRepo URL. Use owner/name or valid GitHub URL."; exit 1
    }
} elseif ($TemplateRepo -match '^([^/]+)/([^/]+)$') {
    $templateFull = $TemplateRepo
    $templateName = $matches[2]
} else {
    $templateFull = "$OrgName/$TemplateRepo"
    $templateName = $TemplateRepo
}

# Get email prefix
$emailPrefix = $StudentEmail.Split('@')[0]
# Slugify template repo name
$templateSlug = ($templateName -replace '[^a-zA-Z0-9]', '-').ToLower()
# Combine for unique repo name
$repoName = "$emailPrefix-$templateSlug"
Write-Host "Planned repository name: $repoName"

# Check if repo already exists
$null = gh repo view "$OrgName/$repoName" 2>$null
if ($LASTEXITCODE -eq 0) {
    Write-Host "Repository '$OrgName/$repoName' already exists. Skipping creation."
    exit 0
}

# Create new repo from template
Write-Host "Creating private repo '$OrgName/$repoName' from template '$templateFull'..."
gh repo create "$OrgName/$repoName" --template $templateFull --private --confirm

if ($LASTEXITCODE -ne 0) {
    Write-Error "Failed to create repository (exit code $LASTEXITCODE)."
    exit 1
} else {
    Write-Host "✅ Repository created: $OrgName/$repoName"
    # Assignment branch creation removed; ensure it exists in template repo.
}

# --- Sync all branches from template to new repo ---
Write-Host "Syncing all branches from template '$templateFull' to '$OrgName/$repoName'..."

# Get all branches from the template repo
try {
    $templateBranches = gh api "repos/$templateFull/branches" | ConvertFrom-Json
} catch {
    Write-Error "Failed to retrieve branches from template repository '$templateFull'."; exit 1
}

# Get the default branch of the template repo to skip it
try {
    $templateInfo = gh api "repos/$templateFull" | ConvertFrom-Json
    $defaultBranch = $templateInfo.default_branch
} catch {
    Write-Error "Failed to retrieve default branch from template repository '$templateFull'."; exit 1
}

foreach ($branch in $templateBranches) {
    $branchName = $branch.name
    if ($branchName -eq $defaultBranch) {
        Write-Host "Skipping default branch '$branchName' (already created by template)."
        continue
    }

    $commitSha = $branch.commit.sha
    Write-Host "Creating branch '$branchName' in '$OrgName/$repoName' from commit SHA '$commitSha'..."

    # Create the new branch in the student repo by creating a new git ref
    gh api "repos/$OrgName/$repoName/git/refs" -X POST -f "ref=refs/heads/$branchName" -f "sha=$commitSha" | Out-Null

    if ($LASTEXITCODE -eq 0) {
        Write-Host "  ✅ Branch '$branchName' created successfully."
    } else {
        Write-Error "  ❌ Failed to create branch '$branchName'."
    }
}

# Grant repo access to corresponding team if it exists
$teamSlug = ($StudentEmail -replace '[^a-zA-Z0-9]', '-').ToLower()
$null = gh api "orgs/$OrgName/teams/$teamSlug" 2>$null
if ($LASTEXITCODE -eq 0) {
    Write-Host "Assigning 'push' permission for team '$teamSlug' to repo '$repoName'..."
    gh api "orgs/$OrgName/teams/$teamSlug/repos/$OrgName/$repoName" -X PUT -f permission=push
    if ($LASTEXITCODE -eq 0) {
        Write-Host "✅ Team permission set."
    } else {
        Write-Error "Failed to set team permission (exit code $LASTEXITCODE)."
    }
} else {
    Write-Warning "Team '$teamSlug' not found; skipping permission assignment."
}
