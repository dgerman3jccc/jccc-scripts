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
gh repo create "$OrgName/$repoName" --template $templateFull --private

if ($LASTEXITCODE -ne 0) {
    Write-Error "Failed to create repository (exit code $LASTEXITCODE)."
    exit 1
} else {
    Write-Host "✅ Repository created: $OrgName/$repoName"
    # Wait for GitHub to finish initializing the repository
    Write-Host "Waiting for repository initialization..."

    # Check if the repository exists and has content
    $maxWaitTime = 30 # seconds
    $waitInterval = 5 # seconds
    $elapsed = 0
    $ready = $false

    while (-not $ready -and $elapsed -lt $maxWaitTime) {
        Start-Sleep -Seconds $waitInterval
        $elapsed += $waitInterval
        Write-Host "Checking repository status... ($elapsed seconds elapsed)"

        try {
            $repoInfo = gh api "repos/$OrgName/$repoName" | ConvertFrom-Json
            if ($repoInfo.size -gt 0) {
                $ready = $true
                Write-Host "Repository is ready."
            } else {
                Write-Host "Repository still initializing..."
            }
        } catch {
            Write-Host "Error checking repository status: $_"
        }
    }

    if (-not $ready) {
        Write-Warning "Repository may not be fully initialized, but proceeding anyway."
    }
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

# Create a temp directory for Git operations
$tempDir = Join-Path $env:TEMP ([System.Guid]::NewGuid().ToString())
New-Item -ItemType Directory -Path $tempDir -Force | Out-Null

try {
    # Change to the temp directory
    Push-Location $tempDir

    # Clone the template repository
    Write-Host "Cloning template repository to temp directory..."
    gh repo clone "$templateFull" . --quiet
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to clone template repository."
    }

    # Add the student repo as a remote
    git remote add student "https://github.com/$OrgName/$repoName.git"

    # For each branch in the template repo
    foreach ($branch in $templateBranches) {
        $branchName = $branch.name
        if ($branchName -eq $defaultBranch) {
            Write-Host "Skipping default branch '$branchName' (already created by template)."
            continue
        }

        Write-Host "Pushing branch '$branchName' to student repository..."

        # Checkout the branch
        git checkout $branchName --quiet
        if ($LASTEXITCODE -ne 0) {
            Write-Error "Failed to checkout branch '$branchName'."
            continue
        }

        # Push to student repo
        git push student $branchName --quiet
        if ($LASTEXITCODE -eq 0) {
            Write-Host "  ✅ Branch '$branchName' pushed successfully."
        } else {
            Write-Error "  ❌ Failed to push branch '$branchName'."
        }
    }
} catch {
    Write-Error "Error during branch sync: $_"
} finally {
    # Return to original directory
    Pop-Location

    # Clean up temp directory
    if (Test-Path $tempDir) {
        Remove-Item -Path $tempDir -Recurse -Force -ErrorAction SilentlyContinue
    }
}

# --- Apply branch protection to the default branch ---
Write-Host "Applying branch protection to '$defaultBranch' in '$OrgName/$repoName'..."

# Define the branch protection rule payload
# This requires a pull request before merging.
$protectionPayload = @{
    required_status_checks        = $null;
    enforce_admins                = $true;
    required_pull_request_reviews = @{
        required_approving_review_count = 1
    };
    restrictions                  = $null;
} | ConvertTo-Json -Depth 4

# Use gh api to apply the rule
$protectionPayloadPath = [System.IO.Path]::GetTempFileName()
$protectionPayload | Out-File -FilePath $protectionPayloadPath -Encoding utf8
try {
    gh api "repos/$OrgName/$repoName/branches/$defaultBranch/protection" `
        -X PUT `
        --input $protectionPayloadPath `
        -H "Content-Type: application/json" | Out-Null
} finally {
    Remove-Item -Path $protectionPayloadPath -Force -ErrorAction SilentlyContinue
}

if ($LASTEXITCODE -eq 0) {
    Write-Host "  ✅ Branch protection rule applied to '$defaultBranch'."
} else {
    Write-Error "  ❌ Failed to apply branch protection to '$defaultBranch'."
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
