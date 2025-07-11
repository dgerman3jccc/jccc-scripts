<#
.SYNOPSIS
    Creates a secret GitHub team for a single student (by email) in the 'jccc-oop' organization and invites them.
.DESCRIPTION
    Prompts for a student's email, slugifies it to a team name, ensures GitHub CLI is installed and authenticated,
    then creates a secret team and sends an email invitation to that student.

Prerequisites:
  - GitHub CLI installed: https://cli.github.com/
  - Authenticated: gh auth login --scopes "repo,read:org"
#>

# Hard-coded organization
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

# 3. Read student email
$StudentEmail = Read-Host "Enter student email (e.g. user@example.com)"
if ([string]::IsNullOrWhiteSpace($StudentEmail)) {
    Write-Error "No email provided. Exiting."
    exit 1
}

# 4. Slugify email as team name
$teamSlug = ($StudentEmail -replace '[^a-zA-Z0-9]', '-').ToLower()

# 5. Check if team exists (suppress errors)
$null = gh api "orgs/$OrgName/teams/$teamSlug" 2>$null
if ($LASTEXITCODE -ne 0) {
    Write-Host "Creating secret team '$teamSlug' in org '$OrgName'..."
    gh api "orgs/$OrgName/teams" -X POST -f name=$teamSlug -f privacy=secret | Out-Null
} else {
    Write-Host "Team '$teamSlug' already exists. Skipping creation."
}

# 6. Invite student via org invitations endpoint
#    Use team ID to scope invitation
$teamInfo = gh api "orgs/$OrgName/teams/$teamSlug"
$teamId   = ($teamInfo | ConvertFrom-Json).id
Write-Host "Inviting '$StudentEmail' to team '$teamSlug' (ID $teamId)..."

# POST to /orgs/:org/invitations with email and team_ids
# Use typed flag -F for numeric team IDs
gh api "orgs/$OrgName/invitations" -X POST `
    -f "email=$StudentEmail" `
    -f "role=direct_member" `
    -F "team_ids[]=$teamId" | Out-Null

if ($LASTEXITCODE -eq 0) {
    Write-Host "✅ '$StudentEmail' invited successfully to '$teamSlug' in '$OrgName'."
} else {
    Write-Error "Invitation failed (HTTP $LASTEXITCODE)."
}
