<#
.SYNOPSIS
    Delete a GitHub repository by URL (supports SSH and HTTPS).

.DESCRIPTION
    This script deletes a GitHub repository via the GitHub REST API.
    - Accepts either SSH (git@github.com:owner/repo.git) or HTTPS (https://github.com/owner/repo.git) URL formats
    - Extracts owner and repo name
    - Authenticates with a Personal Access Token read from an environment variable (default: GIT_PAT)
    - Confirms before deletion (Supports -WhatIf/-Confirm; -Force to bypass interactive prompt)
    - Provides clear success/failure messages and handles common errors (invalid URL, 404, 403/401, network issues)

.PARAMETER RepoUrl
    The GitHub repository URL (SSH or HTTPS). Examples:
      - git@github.com:owner/repo.git
      - https://github.com/owner/repo.git
      - https://github.com/owner/repo

.PARAMETER Force
    Skip the extra confirmation prompt. Still honors -WhatIf/-Confirm semantics via ShouldProcess.

.PARAMETER TokenEnvVar
    Name of the environment variable that contains the GitHub Personal Access Token (default: GIT_PAT).

.EXAMPLE
    PS> .\Delete-GitHubRepository.ps1 -RepoUrl "https://github.com/owner/repo" -Confirm

.EXAMPLE
    PS> .\Delete-GitHubRepository.ps1 "git@github.com:owner/repo.git" -Force

.EXAMPLE
    PS> .\Delete-GitHubRepository.ps1 -RepoUrl "https://github.com/owner/repo" -WhatIf

.NOTES
    Requires a GitHub token with repo admin/delete permissions stored in $env:GIT_PAT (or custom via -TokenEnvVar).
    API: DELETE https://api.github.com/repos/{owner}/{repo}
#>

[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
param(
    [Parameter(Mandatory, Position = 0)]
    [ValidateNotNullOrEmpty()]
    [string]$RepoUrl,

    [Parameter()]
    [switch]$Force,

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$TokenEnvVar = 'GIT_PAT'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Parse-GitHubRepoUrl {
    [CmdletBinding()] param(
        [Parameter(Mandatory)] [string]$Url
    )
    # Trim whitespace
    $u = $Url.Trim()

    # Patterns:
    # SSH:    git@github.com:owner/repo.git
    # HTTPS:  https://github.com/owner/repo(.git)
    $ssh = '^(?i)git@github\.com:(?<owner>[^/]+)/(?<repo>[^/]+?)(?:\.git)?$'
    $https = '^(?i)https://github\.com/(?<owner>[^/]+)/(?<repo>[^/]+?)(?:\.git)?/?$'

    $m = [regex]::Match($u, $ssh)
    if (-not $m.Success) { $m = [regex]::Match($u, $https) }

    if (-not $m.Success) {
        throw [System.ArgumentException]::new("Invalid GitHub repository URL. Supported formats: SSH git@github.com:owner/repo(.git) or HTTPS https://github.com/owner/repo(.git)")
    }

    $owner = $m.Groups['owner'].Value
    $repo = $m.Groups['repo'].Value

    if ([string]::IsNullOrWhiteSpace($owner) -or [string]::IsNullOrWhiteSpace($repo)) {
        throw [System.ArgumentException]::new("Could not parse owner/repo from URL: $Url")
    }

    # Normalize repo by stripping trailing .git if any (already handled in regex, but double-safeguard)
    if ($repo.EndsWith('.git', [System.StringComparison]::OrdinalIgnoreCase)) {
        $repo = $repo.Substring(0, $repo.Length - 4)
    }

    [PSCustomObject]@{ Owner = $owner; Repo = $repo }
}

function Get-StatusCodeFromException {
    param([Parameter(Mandatory)] $ErrorRecord)
    $ex = $ErrorRecord.Exception

    # PowerShell 7+: HttpResponseException with Response.StatusCode
    if ($ex -and $ex.PSObject.Properties.Name -contains 'Response' -and $ex.Response) {
        try {
            if ($ex.Response.StatusCode) { return [int]$ex.Response.StatusCode }
        } catch { }
    }

    # Windows PowerShell 5.1: WebException with Response
    if ($ex -and $ex.PSObject.Properties.Name -contains 'Response' -and $ex.Response) {
        try {
            return [int][System.Net.HttpWebResponse]$ex.Response | ForEach-Object { $_.StatusCode }
        } catch { }
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

try {
    $parsed = Parse-GitHubRepoUrl -Url $RepoUrl
    $owner = $parsed.Owner
    $repo  = $parsed.Repo

    $token = [Environment]::GetEnvironmentVariable($TokenEnvVar)
    if ([string]::IsNullOrWhiteSpace($token)) {
        throw [System.Security.SecurityException]::new("GitHub token not found. Set the `$env:$TokenEnvVar environment variable.")
    }

    $apiUrl = "https://api.github.com/repos/$owner/$repo"

    $headers = @{
        Authorization           = "Bearer $token"
        Accept                  = 'application/vnd.github+json'
        'X-GitHub-Api-Version'  = '2022-11-28'
        'User-Agent'            = 'Delete-GitHubRepository.ps1'
    }

    $target = "$owner/$repo"

    if ($PSCmdlet.ShouldProcess($target, 'Delete GitHub repository')) {
        if (-not $Force) {
            $title = "This action cannot be undone."
            $question = "Are you absolutely sure you want to permanently delete '$owner/$repo'?"
            if (-not $PSCmdlet.ShouldContinue($question, $title)) {
                Write-Host "Deletion cancelled." -ForegroundColor Yellow
                return
            }
        }

        try {
            Invoke-RestMethod -Method Delete -Uri $apiUrl -Headers $headers -ErrorAction Stop | Out-Null
            Write-Host "Repository '$owner/$repo' deleted successfully." -ForegroundColor Green
        } catch {
            $status = Get-StatusCodeFromException -ErrorRecord $_
            $body   = Get-ResponseBodyFromException -ErrorRecord $_

            switch ($status) {
                401 { Write-Error "Unauthorized (401): Token is missing, invalid, or lacks required scopes. Ensure `$env:$TokenEnvVar has a token with appropriate repo deletion permissions." }
                403 {
                    if ($body -and $body -match 'rate limit') {
                        Write-Error "Forbidden (403): API rate limit exceeded or access forbidden. Check token scopes and rate limits."
                    } else {
                        Write-Error "Forbidden (403): Insufficient permissions to delete '$owner/$repo'. Ensure the token has admin rights to this repository."
                    }
                }
                404 { Write-Error "Not Found (404): Repository '$owner/$repo' not found or you do not have access." }
                Default {
                    if ($status) {
                        Write-Error ("HTTP {0}: Failed to delete '{1}'. Response: {2}" -f $status, $target, ($body ?? $_))
                    } else {
                        Write-Error "Network/Connectivity error: $_"
                    }
                }
            }
        }
    } else {
        # -WhatIf path - ShouldProcess declined
        Write-Verbose "Operation skipped by ShouldProcess."
    }
}
catch {
    Write-Error $_
}

