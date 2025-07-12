<#
.SYNOPSIS
    Deletes student-related repositories in a GitHub organization based on a name pattern.

.DESCRIPTION
    This script lists all repositories in a specified organization, filters out template repositories,
    and then identifies student repositories using a regular expression pattern on the repository name.
    It will prompt for confirmation before deleting each repository unless the -Force switch is used.

.PARAMETER OrgName
    The GitHub organization to scan for repositories. Defaults to 'jccc-oop'.

.PARAMETER Pattern
    A regular expression used to identify student repositories by name.
    The default pattern matches names that start with an alphanumeric user prefix followed by a hyphen,
    which is consistent with the 'Create-StudentRepo.ps1' script.

.PARAMETER Force
    If specified, the script will delete matching repositories without prompting for confirmation.

.EXAMPLE
    .\Clean-StudentRepos.ps1
    Scans the 'jccc-oop' organization and interactively prompts to delete repositories like 'dgerman3-assignment-1'.

.EXAMPLE
    .\Clean-StudentRepos.ps1 -Force
    Deletes all matching student repositories in 'jccc-oop' without confirmation.

.EXAMPLE
    .\Clean-StudentRepos.ps1 -Pattern '^testuser-'
    Deletes repositories starting with 'testuser-'.
#>
Param(
    [string]$OrgName = 'jccc-oop',
    # Only match repos with email-like prefix (e.g., facmet107-gmail-com-) before assignment name
    [string]$Pattern = '^[a-z0-9]+(-[a-z0-9]+)*@[a-z0-9]+(-[a-z0-9]+)*-[a-zA-Z]',
    [switch]$Force
)

# Verify GitHub CLI
if (-not (Get-Command gh -ErrorAction SilentlyContinue)) {
    Write-Error "GitHub CLI ('gh') not found. Install from https://cli.github.com/."
    exit 1
}

Write-Host "Fetching repositories from organization '$OrgName'..."
$repos = gh repo list $OrgName --limit 1000 --json name,isTemplate | ConvertFrom-Json

if (-not $repos) {
    Write-Host "No repositories found or failed to fetch from '$OrgName'."
    exit 0
}

$studentRepos = $repos | Where-Object { -not $_.isTemplate -and $_.name -match $Pattern }

if (-not $studentRepos) {
    Write-Host "No student repositories matching the pattern '$Pattern' found."
    exit 0
}

Write-Host "The following student repositories will be deleted:"
$studentRepos.name | ForEach-Object { Write-Host " - $_" }

foreach ($repo in $studentRepos) {
    $repoFullName = "$OrgName/$($repo.name)"
    if ($Force) {
        Write-Host "Deleting repository $repoFullName..."
        gh repo delete $repoFullName --yes
    } else {
        $confirmation = Read-Host "Are you sure you want to delete '$repoFullName'? (y/N)"
        if ($confirmation -eq 'y') {
            Write-Host "Deleting repository $repoFullName..."
            gh repo delete $repoFullName --yes
        } else {
            Write-Host "Skipping deletion of '$repoFullName'."
        }
    }
}

Write-Host "Cleanup complete."
