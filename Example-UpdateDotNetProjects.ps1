<#
.SYNOPSIS
    Example usage script for Update-DotNetProjectsAllBranches.ps1

.DESCRIPTION
    This script demonstrates various ways to use the .NET Projects Multi-Branch Updater.
    It includes examples for different scenarios and use cases.

.NOTES
    Author: .NET Repository Enhancement Protocol
    Version: 1.0
    
    Before running any of these examples:
    1. Ensure your GitHub Personal Access Token is set: $env:GIT_PAT = "your_token"
    2. Navigate to the directory containing Update-DotNetProjectsAllBranches.ps1
    3. Modify the repository paths in the examples below as needed
#>

# Example 1: Basic usage - Update current repository
Write-Host "=== Example 1: Basic Usage ===" -ForegroundColor Green
Write-Host "Update all .NET projects in the current repository to .NET 8.0 and C# 12"
Write-Host "Also adds .idea/ to .gitignore to exclude JetBrains IDE files"
Write-Host "Command: .\Update-DotNetProjectsAllBranches.ps1 -RepositoryPath '.'"
Write-Host ""

# Uncomment to run:
# .\Update-DotNetProjectsAllBranches.ps1 -RepositoryPath "."

# Example 2: Dry run - Preview changes without applying them
Write-Host "=== Example 2: Dry Run Mode ===" -ForegroundColor Green
Write-Host "Preview what changes would be made without actually modifying files"
Write-Host "Shows which project files and .gitignore would be updated"
Write-Host "Command: .\Update-DotNetProjectsAllBranches.ps1 -RepositoryPath '.' -DryRun"
Write-Host ""

# Uncomment to run:
# .\Update-DotNetProjectsAllBranches.ps1 -RepositoryPath "." -DryRun

# Example 3: Skip push - Update locally but don't push to remote
Write-Host "=== Example 3: Skip Push Mode ===" -ForegroundColor Green
Write-Host "Update projects and commit changes locally, but don't push to remote repository"
Write-Host "Command: .\Update-DotNetProjectsAllBranches.ps1 -RepositoryPath '.' -SkipPush"
Write-Host ""

# Uncomment to run:
# .\Update-DotNetProjectsAllBranches.ps1 -RepositoryPath "." -SkipPush

# Example 4: Specific repository path
Write-Host "=== Example 4: Specific Repository Path ===" -ForegroundColor Green
Write-Host "Update projects in a specific repository location"
Write-Host "Command: .\Update-DotNetProjectsAllBranches.ps1 -RepositoryPath 'C:\repos\my-project'"
Write-Host ""

# Uncomment and modify path to run:
# .\Update-DotNetProjectsAllBranches.ps1 -RepositoryPath "C:\repos\my-project"

# Example 5: Combined options - Dry run with skip push
Write-Host "=== Example 5: Combined Options ===" -ForegroundColor Green
Write-Host "Preview changes without applying them or pushing (useful for testing)"
Write-Host "Command: .\Update-DotNetProjectsAllBranches.ps1 -RepositoryPath '.' -DryRun -SkipPush"
Write-Host ""

# Uncomment to run:
# .\Update-DotNetProjectsAllBranches.ps1 -RepositoryPath "." -DryRun -SkipPush

# Example 6: Batch processing multiple repositories
Write-Host "=== Example 6: Batch Processing Multiple Repositories ===" -ForegroundColor Green
Write-Host "Process multiple repositories in sequence"
Write-Host ""

$repositories = @(
    "C:\repos\project1",
    "C:\repos\project2",
    "C:\repos\project3"
)

Write-Host "Repositories to process:"
foreach ($repo in $repositories) {
    Write-Host "  • $repo" -ForegroundColor White
}
Write-Host ""

# Uncomment and modify paths to run:
<#
foreach ($repo in $repositories) {
    if (Test-Path $repo) {
        Write-Host "Processing repository: $repo" -ForegroundColor Cyan
        .\Update-DotNetProjectsAllBranches.ps1 -RepositoryPath $repo
        Write-Host "Completed: $repo" -ForegroundColor Green
        Write-Host ""
    } else {
        Write-Host "Repository not found: $repo" -ForegroundColor Red
    }
}
#>

# Example 7: Error handling and logging
Write-Host "=== Example 7: Error Handling and Logging ===" -ForegroundColor Green
Write-Host "Run with error handling and output logging"
Write-Host ""

# Uncomment and modify to run:
<#
$logFile = "update-dotnet-projects-$(Get-Date -Format 'yyyyMMdd-HHmmss').log"
try {
    .\Update-DotNetProjectsAllBranches.ps1 -RepositoryPath "." 2>&1 | Tee-Object -FilePath $logFile
    Write-Host "Operation completed successfully. Log saved to: $logFile" -ForegroundColor Green
} catch {
    Write-Host "Operation failed: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "Check log file for details: $logFile" -ForegroundColor Yellow
}
#>

# Example 8: Pre-flight checks
Write-Host "=== Example 8: Pre-flight Checks ===" -ForegroundColor Green
Write-Host "Perform checks before running the update script"
Write-Host ""

function Test-UpdatePrerequisites {
    param([string]$RepoPath)
    
    Write-Host "Performing pre-flight checks for: $RepoPath" -ForegroundColor Cyan
    
    # Check if path exists
    if (-not (Test-Path $RepoPath)) {
        Write-Host "✗ Repository path does not exist" -ForegroundColor Red
        return $false
    }
    
    # Check if it's a Git repository
    Push-Location $RepoPath
    try {
        git rev-parse --git-dir 2>$null | Out-Null
        if ($LASTEXITCODE -ne 0) {
            Write-Host "✗ Not a Git repository" -ForegroundColor Red
            return $false
        }
        Write-Host "✓ Valid Git repository" -ForegroundColor Green
    } finally {
        Pop-Location
    }
    
    # Check for .NET projects
    $projectFiles = Get-ChildItem -Path $RepoPath -Include "*.csproj", "*.vbproj", "*.fsproj" -Recurse
    if ($projectFiles.Count -eq 0) {
        Write-Host "⚠ No .NET project files found" -ForegroundColor Yellow
    } else {
        Write-Host "✓ Found $($projectFiles.Count) .NET project file(s)" -ForegroundColor Green
    }
    
    # Check Git credentials
    if (-not (Test-Path env:GIT_PAT)) {
        Write-Host "⚠ GIT_PAT environment variable not set (use -SkipPush if not pushing)" -ForegroundColor Yellow
    } else {
        Write-Host "✓ Git credentials configured" -ForegroundColor Green
    }
    
    # Check for uncommitted changes
    Push-Location $RepoPath
    try {
        $status = git status --porcelain
        if ($status) {
            Write-Host "⚠ Repository has uncommitted changes" -ForegroundColor Yellow
            Write-Host "  Consider committing or stashing changes before running the update" -ForegroundColor Yellow
        } else {
            Write-Host "✓ Repository is clean" -ForegroundColor Green
        }
    } finally {
        Pop-Location
    }
    
    return $true
}

# Uncomment to run pre-flight checks:
# Test-UpdatePrerequisites "."

Write-Host ""
Write-Host "=== Instructions ===" -ForegroundColor Yellow
Write-Host "1. Set your GitHub Personal Access Token: `$env:GIT_PAT = 'your_token'"
Write-Host "2. Uncomment the example you want to run"
Write-Host "3. Modify repository paths as needed"
Write-Host "4. Run this script or copy the commands to your PowerShell session"
Write-Host ""
Write-Host "For detailed documentation, see: UPDATE-DOTNET-PROJECTS-GUIDE.md" -ForegroundColor Cyan
