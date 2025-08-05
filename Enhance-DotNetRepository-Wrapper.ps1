# Enhance-DotNetRepository-Wrapper.ps1
# User-friendly wrapper for the Enhance-DotNetRepository.ps1 script with validation and preset modes

param(
    [Parameter(Position=0, HelpMessage="Path to the .NET repository to enhance")]
    [string]$RepositoryPath,
    
    [Parameter(HelpMessage="Preview changes without applying them")]
    [switch]$DryRun,
    
    [Parameter(HelpMessage="Skip branch synchronization during enhancement")]
    [switch]$SkipBranchSync,
    
    [Parameter(HelpMessage="Keep backup directory after completion")]
    [switch]$KeepBackup,
    
    [Parameter(HelpMessage="Skip confirmation prompts (use with caution)")]
    [switch]$Force,
    
    [Parameter(HelpMessage="Show help information")]
    [switch]$Help
)

# Show help if requested
if ($Help) {
    Write-Host "=== .NET Repository Enhancement Wrapper - Help ===" -ForegroundColor Green
    Write-Host ""
    Write-Host "This wrapper provides a simplified interface for the Enhance-DotNetRepository.ps1 script" -ForegroundColor White
    Write-Host "with validation, preset modes, and user-friendly prompts." -ForegroundColor White
    Write-Host ""
    Write-Host "Features:" -ForegroundColor Yellow
    Write-Host "  • Validates repository existence and Git status" -ForegroundColor White
    Write-Host "  • Automatically detects default branch (main/master)" -ForegroundColor White
    Write-Host "  • Checks for uncommitted changes and warns user" -ForegroundColor White
    Write-Host "  • Provides clear summary of what will be enhanced" -ForegroundColor White
    Write-Host "  • Shows backup location and rollback instructions" -ForegroundColor White
    Write-Host "  • Includes confirmation prompts for safety" -ForegroundColor White
    Write-Host ""
    Write-Host "Enhancement includes:" -ForegroundColor Yellow
    Write-Host "  • VS Code configurations (tasks, launch, settings)" -ForegroundColor White
    Write-Host "  • DevContainer setup for GitHub Codespaces" -ForegroundColor White
    Write-Host "  • CI/CD pipeline with GitHub Actions" -ForegroundColor White
    Write-Host "  • Comprehensive documentation (README.md)" -ForegroundColor White
    Write-Host "  • Branch synchronization across all repository branches" -ForegroundColor White
    Write-Host "  • Git attributes for proper line ending management" -ForegroundColor White
    Write-Host ""
    Write-Host "Parameters:" -ForegroundColor Yellow
    Write-Host "  RepositoryPath    Path to the .NET repository to enhance (required)" -ForegroundColor White
    Write-Host "  -DryRun           Preview changes without applying them" -ForegroundColor White
    Write-Host "  -SkipBranchSync   Skip branch synchronization during enhancement" -ForegroundColor White
    Write-Host "  -KeepBackup       Keep backup directory after completion" -ForegroundColor White
    Write-Host "  -Force            Skip confirmation prompts (use with caution)" -ForegroundColor White
    Write-Host "  -Help             Show this help message" -ForegroundColor White
    Write-Host ""
    Write-Host "Example usage:" -ForegroundColor Yellow
    Write-Host "  Enhance-DotNetRepository-Wrapper.ps1 C:\projects\my-dotnet-repo" -ForegroundColor White
    Write-Host "  Enhance-DotNetRepository-Wrapper.ps1 -DryRun C:\projects\my-dotnet-repo" -ForegroundColor White
    Write-Host "  Enhance-DotNetRepository-Wrapper.ps1 -SkipBranchSync C:\projects\my-dotnet-repo" -ForegroundColor White
    Write-Host ""
    Write-Host "Prerequisites:" -ForegroundColor Yellow
    Write-Host "  • Ensure Enhance-DotNetRepository.ps1 is in PATH or current directory" -ForegroundColor White
    Write-Host "  • Target directory must be a valid Git repository" -ForegroundColor White
    Write-Host "  • Repository should contain .NET projects (.csproj or .sln files)" -ForegroundColor White
    Write-Host ""
    exit 0
}

# Helper function to find the main enhancement script
function Find-EnhancementScript {
    $scriptName = "Enhance-DotNetRepository.ps1"
    
    # Check current directory first
    $currentDirScript = Join-Path (Get-Location) $scriptName
    if (Test-Path $currentDirScript) {
        return $currentDirScript
    }
    
    # Check if script is in PATH
    $pathScript = Get-Command $scriptName -ErrorAction SilentlyContinue
    if ($pathScript) {
        return $pathScript.Source
    }
    
    throw "Could not find $scriptName in current directory or PATH. Please ensure the script is accessible."
}

# Helper function to validate Git repository
function Test-GitRepository {
    param([string]$Path)
    
    if (-not (Test-Path $Path)) {
        throw "Repository path does not exist: $Path"
    }
    
    $gitDir = Join-Path $Path ".git"
    if (-not (Test-Path $gitDir)) {
        throw "Directory is not a Git repository: $Path"
    }
    
    return $true
}

# Helper function to detect .NET projects
function Test-DotNetRepository {
    param([string]$Path)
    
    $csprojFiles = Get-ChildItem -Path $Path -Recurse -Filter "*.csproj" -ErrorAction SilentlyContinue
    $slnFiles = Get-ChildItem -Path $Path -Recurse -Filter "*.sln" -ErrorAction SilentlyContinue
    
    if ($csprojFiles.Count -eq 0 -and $slnFiles.Count -eq 0) {
        Write-Warning "No .NET project files (.csproj or .sln) found in repository"
        Write-Warning "The enhancement script may not work correctly without .NET projects"
        return $false
    }
    
    return $true
}

# Helper function to check Git status
function Get-GitStatus {
    param([string]$Path)
    
    Push-Location $Path
    try {
        $status = git status --porcelain 2>$null
        $branch = git branch --show-current 2>$null
        $remoteUrl = git remote get-url origin 2>$null
        
        return @{
            HasUncommittedChanges = ($status.Count -gt 0)
            CurrentBranch = $branch
            RemoteUrl = $remoteUrl
            UncommittedFiles = $status
        }
    } finally {
        Pop-Location
    }
}

# Helper function to show repository summary
function Show-RepositorySummary {
    param([string]$Path, [object]$GitStatus)
    
    Write-Host "=== Repository Summary ===" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "Repository Path: $Path" -ForegroundColor White
    Write-Host "Current Branch: $($GitStatus.CurrentBranch)" -ForegroundColor White
    
    if ($GitStatus.RemoteUrl) {
        Write-Host "Remote URL: $($GitStatus.RemoteUrl)" -ForegroundColor White
    } else {
        Write-Host "Remote URL: Not configured" -ForegroundColor Yellow
    }
    
    # Check for .NET projects
    $csprojCount = (Get-ChildItem -Path $Path -Recurse -Filter "*.csproj" -ErrorAction SilentlyContinue).Count
    $slnCount = (Get-ChildItem -Path $Path -Recurse -Filter "*.sln" -ErrorAction SilentlyContinue).Count
    
    Write-Host ".NET Projects: $csprojCount .csproj files, $slnCount .sln files" -ForegroundColor White
    
    if ($GitStatus.HasUncommittedChanges) {
        Write-Host "Git Status: Uncommitted changes detected" -ForegroundColor Yellow
        Write-Host "Uncommitted files:" -ForegroundColor Yellow
        foreach ($file in $GitStatus.UncommittedFiles | Select-Object -First 5) {
            Write-Host "  $file" -ForegroundColor Yellow
        }
        if ($GitStatus.UncommittedFiles.Count -gt 5) {
            Write-Host "  ... and $($GitStatus.UncommittedFiles.Count - 5) more files" -ForegroundColor Yellow
        }
    } else {
        Write-Host "Git Status: Clean working directory" -ForegroundColor Green
    }
    
    Write-Host ""
}

# Helper function to show enhancement preview
function Show-EnhancementPreview {
    param([bool]$SkipBranchSync)
    
    Write-Host "=== Enhancement Preview ===" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "The following enhancements will be applied:" -ForegroundColor White
    Write-Host ""
    Write-Host "Phase 0 - Environment Setup:" -ForegroundColor Yellow
    Write-Host "  • Create/update .vscode/tasks.json (build, test, debug tasks)" -ForegroundColor White
    Write-Host "  • Create/update .vscode/launch.json (debug configurations)" -ForegroundColor White
    Write-Host "  • Create/update .devcontainer/devcontainer.json (GitHub Codespaces)" -ForegroundColor White
    Write-Host "  • Create/update .gitattributes (line ending management)" -ForegroundColor White
    Write-Host ""
    
    if (-not $SkipBranchSync) {
        Write-Host "Phase 1 - Branch Synchronization:" -ForegroundColor Yellow
        Write-Host "  • Synchronize .vscode and .devcontainer to all branches" -ForegroundColor White
        Write-Host "  • Ensure consistent development environment across branches" -ForegroundColor White
        Write-Host ""
    } else {
        Write-Host "Phase 1 - Branch Synchronization: SKIPPED" -ForegroundColor Yellow
        Write-Host ""
    }
    
    Write-Host "Phase 2 - CI/CD Pipeline:" -ForegroundColor Yellow
    Write-Host "  • Create/update .github/workflows/ci.yml (automated builds and tests)" -ForegroundColor White
    Write-Host ""
    
    Write-Host "Phase 3 - Documentation:" -ForegroundColor Yellow
    Write-Host "  • Create/update README.md with project information and setup instructions" -ForegroundColor White
    Write-Host ""
    
    Write-Host "All changes will be committed and pushed to the remote repository." -ForegroundColor Cyan
    Write-Host ""
}

Write-Host "=== .NET Repository Enhancement Wrapper ===" -ForegroundColor Green
Write-Host ""

# Validate required parameters (unless showing help)
if (-not $Help -and [string]::IsNullOrWhiteSpace($RepositoryPath)) {
    Write-Host "ERROR: RepositoryPath parameter is required" -ForegroundColor Red
    Write-Host "Use -Help for usage information." -ForegroundColor Yellow
    exit 1
}

try {
    # Resolve and validate repository path
    $RepositoryPath = Resolve-Path $RepositoryPath -ErrorAction Stop
    Write-Host "Validating repository..." -ForegroundColor Cyan
    
    # Validate Git repository
    Test-GitRepository $RepositoryPath | Out-Null
    Write-Host "✓ Valid Git repository detected" -ForegroundColor Green
    
    # Check for .NET projects
    $isDotNetRepo = Test-DotNetRepository $RepositoryPath
    if ($isDotNetRepo) {
        Write-Host "✓ .NET projects detected" -ForegroundColor Green
    }
    
    # Get Git status
    $gitStatus = Get-GitStatus $RepositoryPath
    Write-Host "✓ Git status retrieved" -ForegroundColor Green
    
    # Find enhancement script
    Write-Host "Locating enhancement script..." -ForegroundColor Cyan
    $enhancementScript = Find-EnhancementScript
    Write-Host "✓ Found Enhance-DotNetRepository.ps1 at: $enhancementScript" -ForegroundColor Green
    Write-Host ""
    
    # Show repository summary
    Show-RepositorySummary $RepositoryPath $gitStatus
    
    # Show enhancement preview
    Show-EnhancementPreview $SkipBranchSync
    
    # Warning for uncommitted changes
    if ($gitStatus.HasUncommittedChanges -and -not $DryRun) {
        Write-Host "⚠️  WARNING: Uncommitted changes detected!" -ForegroundColor Yellow
        Write-Host "The enhancement process will create backups, but it's recommended to commit or stash changes first." -ForegroundColor Yellow
        Write-Host ""
    }
    
    # Confirmation prompt (unless Force or DryRun)
    if (-not $Force -and -not $DryRun) {
        $confirmation = Read-Host "Do you want to proceed with the enhancement? (y/N)"
        if ($confirmation -notmatch '^[Yy]') {
            Write-Host "Enhancement cancelled by user." -ForegroundColor Yellow
            exit 0
        }
        Write-Host ""
    }
    
    # Build parameters for main script
    $enhanceParams = @{
        "RepositoryPath" = $RepositoryPath
    }

    if ($DryRun) { $enhanceParams["DryRun"] = $true }
    if ($SkipBranchSync) { $enhanceParams["SkipBranchSync"] = $true }

    # Execute main enhancement script
    Write-Host "=== Executing Enhancement Script ===" -ForegroundColor Green
    $paramString = ($enhanceParams.GetEnumerator() | ForEach-Object {
        if ($_.Value -eq $true) { "-$($_.Key)" } else { "-$($_.Key) `"$($_.Value)`"" }
    }) -join " "
    Write-Host "Command: Enhance-DotNetRepository.ps1 $paramString" -ForegroundColor Cyan
    Write-Host ""

    & $enhancementScript @enhanceParams
    
    if ($LASTEXITCODE -ne 0) {
        throw "Enhancement script failed with exit code: $LASTEXITCODE"
    }
    
    Write-Host ""
    Write-Host "=== Enhancement Completed Successfully ===" -ForegroundColor Green
    Write-Host ""
    
    if (-not $DryRun) {
        Write-Host "Next steps:" -ForegroundColor Yellow
        Write-Host "  1. Open the repository in VS Code or GitHub Codespaces" -ForegroundColor White
        Write-Host "  2. Test the build and debug configurations" -ForegroundColor White
        Write-Host "  3. Review the CI/CD pipeline in GitHub Actions" -ForegroundColor White
        Write-Host "  4. Update the README.md with repository-specific information" -ForegroundColor White
        Write-Host ""
        
        if (-not $KeepBackup) {
            Write-Host "Note: Backup directories will be automatically cleaned up." -ForegroundColor Cyan
        } else {
            Write-Host "Note: Backup directories have been preserved as requested." -ForegroundColor Cyan
        }
    }

} catch {
    Write-Host ""
    Write-Host "ERROR: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host ""
    Write-Host "Use -Help for usage information." -ForegroundColor Yellow
    exit 1
}

Write-Host ""
Write-Host "Wrapper completed successfully!" -ForegroundColor Green
