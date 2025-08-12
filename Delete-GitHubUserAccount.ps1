<#
.SYNOPSIS
    Safely initiate deletion of a GitHub user account with confirmations and guidance.

.DESCRIPTION
    IMPORTANT: Deleting a GitHub.com user account is NOT available via the public REST API.
    This script follows best practices to:
      - Validate the requested username
      - Load a GitHub Personal Access Token (default from $env:GIT_PAT)
      - Confirm intent multiple times (Supports -WhatIf/-Confirm and an extra typed confirmation; -Force to bypass extra prompts)
      - Query the API to verify the user exists and who the token authenticates as
      - For GitHub.com (api.github.com): explain the limitation and guide you to the web UI and docs to close the account
      - Optionally support GitHub Enterprise Server site-admin deletion using the /admin/users/{username} endpoint when -ApiBaseUrl is set to a GHES API URL AND -EnterpriseAdmin is specified

    The script clearly communicates what deletion entails and prevents accidental removal via multiple confirmations.

.PARAMETER Username
    The GitHub username to delete. Must begin and end with an alphanumeric character, may include hyphens, up to 39 chars.

.PARAMETER TokenEnvVar
    Name of the environment variable that contains the GitHub Personal Access Token (default: GIT_PAT).

.PARAMETER ApiBaseUrl
    Base URL of the GitHub API to call. Defaults to https://api.github.com (public GitHub). For GHES, supply your instance API URL, e.g., https://ghe.example.com/api/v3

.PARAMETER EnterpriseAdmin
    When targeting GHES, opt-in to attempt site-admin deletion via DELETE /admin/users/{username}. Requires a token with site admin privileges on GHES. Not applicable to GitHub.com.

.PARAMETER Force
    Skip the extra typed confirmation prompts. Still honors -WhatIf/-Confirm via ShouldProcess.

.EXAMPLE
    PS> .\Delete-GitHubUserAccount.ps1 -Username "octocat" -Confirm

    Verifies existence, shows warnings, and guides you to the web flow for GitHub.com account deletion.

.EXAMPLE
    PS> .\Delete-GitHubUserAccount.ps1 -Username "devuser" -ApiBaseUrl "https://ghe.example.com/api/v3" -EnterpriseAdmin -Confirm

    For GHES site admins only: attempts DELETE /admin/users/devuser after multiple confirmations.

.NOTES
    GitHub.com account deletion must be done via the web UI: https://github.com/settings/admin (must be logged in as the account).
    Docs: https://docs.github.com/account-and-profile/setting-up-and-managing-your-github-user-account/managing-your-account/closing-your-account

    Deletion effects (non-exhaustive):
      - All personal repositories (including forks), wikis, releases, and GitHub Pages are deleted
      - All gists, packages (Container/NuGet/npm), Codespaces, and Actions artifacts/secrets are deleted
      - All personal access tokens, SSH keys, OAuth apps, and webhooks are revoked/removed
      - Organization memberships are removed; owned organizations may need transfer/deletion first
      - Issues, PRs, and comments you authored in other repos remain but attribution changes to "ghost"
#>

[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
param(
    [Parameter(Mandatory, Position = 0)]
    [ValidateNotNullOrEmpty()]
    [ValidatePattern('^(?i)[a-z0-9](?:[a-z0-9-]{0,37}[a-z0-9])?$')]
    [string]$Username,

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$TokenEnvVar = 'GIT_PAT',

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$ApiBaseUrl = 'https://api.github.com',

    [Parameter()]
    [switch]$EnterpriseAdmin,

    [Parameter()]
    [switch]$Force
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-StatusCodeFromException {
    param([Parameter(Mandatory)] $ErrorRecord)
    $ex = $ErrorRecord.Exception
    if ($ex -and $ex.PSObject.Properties.Name -contains 'Response' -and $ex.Response) {
        try { if ($ex.Response.StatusCode) { return [int]$ex.Response.StatusCode } } catch { }
        try { return [int][System.Net.HttpWebResponse]$ex.Response | ForEach-Object { $_.StatusCode } } catch { }
    }
    return $null
}

function Get-ResponseBodyFromException {
    param([Parameter(Mandatory)] $ErrorRecord)
    try {
        $resp = $ErrorRecord.Exception.Response
        if ($resp -and $resp.GetResponseStream) {
            $reader = New-Object System.IO.StreamReader($resp.GetResponseStream())
            $body = $reader.ReadToEnd()
            $reader.Dispose()
            if ($body) { return $body }
        }
    } catch { }
    return $null
}

function Get-GitHubHeaders {
    param([Parameter(Mandatory)][string]$Token)
    return @{
        Authorization          = "Bearer $Token"
        Accept                 = 'application/vnd.github+json'
        'X-GitHub-Api-Version' = '2022-11-28'
        'User-Agent'           = 'Delete-GitHubUserAccount.ps1'
    }
}

try {
    Write-Host "WARNING: Deleting a GitHub account is irreversible and permanently removes most data." -ForegroundColor Yellow
    Write-Host "- Personal repositories, gists, packages, Codespaces, Actions secrets/artifacts, SSH keys, and tokens will be deleted." -ForegroundColor Yellow
    Write-Host "- Issues/PRs/comments in other repos generally remain but attribution changes to 'ghost'." -ForegroundColor Yellow

    $token = [Environment]::GetEnvironmentVariable($TokenEnvVar)
    if ([string]::IsNullOrWhiteSpace($token)) {
        throw [System.Security.SecurityException]::new("GitHub token not found. Set the `$env:$TokenEnvVar environment variable.")
    }

    $headers = Get-GitHubHeaders -Token $token

    # Who am I?
    $me = $null
    try {
        $me = Invoke-RestMethod -Method Get -Uri ("{0}/user" -f $ApiBaseUrl.TrimEnd('/')) -Headers $headers -ErrorAction Stop
    } catch {
        # If we cannot identify the caller, continue but warn; may be due to insufficient scopes
        Write-Verbose "Could not identify authenticated user: $_"
    }

    # Does the target user exist?
    $targetUser = $null
    try {
        $targetUser = Invoke-RestMethod -Method Get -Uri ("{0}/users/{1}" -f $ApiBaseUrl.TrimEnd('/'), $Username) -Headers $headers -ErrorAction Stop
    } catch {
        $status = Get-StatusCodeFromException -ErrorRecord $_
        switch ($status) {
            404 { throw "User '$Username' not found (404)." }
            401 { throw "Unauthorized (401): Token is missing, invalid, or lacks required scopes." }
            403 { throw "Forbidden (403): Insufficient permissions or access restrictions to view user '$Username'." }
            Default { throw ("Failed to verify user existence. {0}" -f ($_)) }
        }
    }

    $isPublicGitHub = $ApiBaseUrl.TrimEnd('/').Equals('https://api.github.com', [System.StringComparison]::OrdinalIgnoreCase)

    $actor = if ($me -and $me.login) { $me.login } else { '<unknown>' }
    Write-Verbose ("Authenticated as: {0}" -f $actor)

    $operationLabel = "Delete GitHub user account: $Username"

    if ($PSCmdlet.ShouldProcess($Username, $operationLabel)) {
        if (-not $Force) {
            $title = "IRREVERSIBLE: Delete user '$Username'?"
            $question = "Are you absolutely sure you want to permanently delete the GitHub account '$Username'?"
            if (-not $PSCmdlet.ShouldContinue($question, $title)) {
                Write-Host "Deletion cancelled." -ForegroundColor Yellow
                return
            }

            $typed = Read-Host "Type the username EXACTLY to confirm"
            if ($typed -ne $Username) {
                Write-Host "Confirmation did not match. Deletion cancelled." -ForegroundColor Yellow
                return
            }

            $typed2 = Read-Host "Final confirmation: type DELETE $Username to proceed"
            if ($typed2 -ne ("DELETE {0}" -f $Username)) {
                Write-Host "Final confirmation did not match. Deletion cancelled." -ForegroundColor Yellow
                return
            }
        }

        if ($isPublicGitHub -and -not $EnterpriseAdmin) {
            # Public GitHub limitation path
            Write-Warning "The public GitHub REST API does not provide an endpoint to delete user accounts."
            if ($me -and $me.login -and ($me.login -ne $Username)) {
                Write-Warning ("Your token is authenticated as '{0}'. Only the account owner can close their own account via the web UI." -f $me.login)
            }
            Write-Host "To close the account, sign in as '$Username' and use the web UI:" -ForegroundColor Cyan
            Write-Host "  https://github.com/settings/admin" -ForegroundColor Cyan
            Write-Host "Documentation:" -ForegroundColor Cyan
            Write-Host "  https://docs.github.com/account-and-profile/setting-up-and-managing-your-github-user-account/managing-your-account/closing-your-account" -ForegroundColor Cyan
            Write-Host "If the account is managed (SSO/enterprise) or you need assistance, contact GitHub Support:" -ForegroundColor Cyan
            Write-Host "  https://support.github.com/" -ForegroundColor Cyan
            return
        }

        # GHES site-admin path (opt-in)
        if (-not $isPublicGitHub -and $EnterpriseAdmin) {
            $deleteUri = ("{0}/admin/users/{1}" -f $ApiBaseUrl.TrimEnd('/'), $Username)
            try {
                Invoke-RestMethod -Method Delete -Uri $deleteUri -Headers $headers -ErrorAction Stop | Out-Null
                Write-Host "User '$Username' deleted successfully on GHES." -ForegroundColor Green
            } catch {
                $status = Get-StatusCodeFromException -ErrorRecord $_
                $body = Get-ResponseBodyFromException -ErrorRecord $_
                switch ($status) {
                    401 { Write-Error "Unauthorized (401): Token is missing/invalid or not a site admin on GHES." }
                    403 { Write-Error "Forbidden (403): Insufficient permissions. Site admin privileges are required to delete users on GHES." }
                    404 { Write-Error "Not Found (404): User '$Username' not found on GHES or endpoint unavailable." }
                    Default {
                        if ($status) { Write-Error ("HTTP {0}: Failed to delete user '{1}'. Response: {2}" -f $status, $Username, ($body ?? $_)) }
                        else { Write-Error "Network/Connectivity error: $_" }
                    }
                }
            }
            return
        }

        # If we got here, either user attempted GHES without -EnterpriseAdmin or misconfigured ApiBaseUrl
        if (-not $isPublicGitHub -and -not $EnterpriseAdmin) {
            Write-Warning "Detected GHES API base URL but -EnterpriseAdmin was not specified. For site-admin deletion, pass -EnterpriseAdmin."
        } else {
            Write-Warning "Unsupported operation or misconfiguration. No deletion performed."
        }
    } else {
        Write-Verbose "Operation skipped by ShouldProcess (-WhatIf or declined confirmation)."
    }
}
catch {
    $status = Get-StatusCodeFromException -ErrorRecord $_
    if ($status) { Write-Error ("HTTP {0} error: {1}" -f $status, $_) } else { Write-Error $_ }
}

