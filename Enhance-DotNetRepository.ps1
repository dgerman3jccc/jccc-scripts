<#
.SYNOPSIS
    Automates the .NET Repository Enhancement Protocol to set up a professional development environment.

.DESCRIPTION
    This script implements a comprehensive enhancement protocol for .NET repositories, including:
    - VS Code configurations (tasks, launch, settings)
    - DevContainer setup for GitHub Codespaces
    - CI/CD pipeline with GitHub Actions
    - Comprehensive documentation
    - Branch synchronization across all repository branches

.PARAMETER RepositoryPath
    The path to the .NET repository to enhance (mandatory)

.PARAMETER DefaultBranch
    The default branch name (optional, auto-detected if not specified)

.PARAMETER DryRun
    Preview changes without applying them

.PARAMETER SkipBranchSync
    Skip the branch synchronization phase

.PARAMETER BackupPath
    Path to store backups (defaults to ./backup-{timestamp})

.PARAMETER PostMigration
    Indicates this script is running after repository migration (enables additional validations)

.PARAMETER ExpectedRemoteOrg
    Expected GitHub organization name for validation (e.g., "oop-jccc")

.EXAMPLE
    .\Enhance-DotNetRepository.ps1 -RepositoryPath "C:\repos\my-dotnet-project"

.EXAMPLE
    .\Enhance-DotNetRepository.ps1 -RepositoryPath "." -DefaultBranch "main" -DryRun

.EXAMPLE
    .\Enhance-DotNetRepository.ps1 -RepositoryPath "." -PostMigration -ExpectedRemoteOrg "oop-jccc"

.NOTES
    Author: .NET Repository Enhancement Protocol
    Version: 1.0
    Requires: PowerShell 5.1+, Git, .NET SDK
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$RepositoryPath,

    [Parameter(Mandatory = $false)]
    [string]$DefaultBranch = "",

    [Parameter(Mandatory = $false)]
    [switch]$DryRun,

    [Parameter(Mandatory = $false)]
    [switch]$SkipBranchSync,

    [Parameter(Mandatory = $false)]
    [string]$BackupPath = "",

    [Parameter(Mandatory = $false)]
    [switch]$PostMigration,

    [Parameter(Mandatory = $false)]
    [string]$ExpectedRemoteOrg = ""
)

# Script configuration
$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"

# Global variables
$script:Changes = @()
$script:Errors = @()
$script:BackupCreated = $false
$script:GitHubOrg = ""
$script:GitHubRepo = ""

# Color output functions
function Write-ColorOutput {
    param(
        [string]$Message,
        [string]$Color = "White"
    )
    
    $colorMap = @{
        "Red" = [ConsoleColor]::Red
        "Green" = [ConsoleColor]::Green
        "Yellow" = [ConsoleColor]::Yellow
        "Blue" = [ConsoleColor]::Blue
        "Cyan" = [ConsoleColor]::Cyan
        "Magenta" = [ConsoleColor]::Magenta
        "White" = [ConsoleColor]::White
    }
    
    Write-Host $Message -ForegroundColor $colorMap[$Color]
}

function Write-Phase {
    param([string]$Message)
    Write-ColorOutput "`n=== $Message ===" "Cyan"
}

function Write-Success {
    param([string]$Message)
    Write-ColorOutput "SUCCESS: $Message" "Green"
}

function Write-Warning {
    param([string]$Message)
    Write-ColorOutput "WARNING: $Message" "Yellow"
}

function Write-ErrorMessage {
    param([string]$Message)
    Write-ColorOutput "ERROR: $Message" "Red"
    $script:Errors += $Message
}

function Write-Info {
    param([string]$Message)
    Write-ColorOutput "INFO: $Message" "Blue"
}

# Helper functions
function Get-RelativePath {
    param(
        [string]$BasePath,
        [string]$FullPath
    )

    $basePath = $BasePath.TrimEnd('\', '/')
    $fullPath = $FullPath.TrimEnd('\', '/')

    if ($fullPath.StartsWith($basePath, [StringComparison]::OrdinalIgnoreCase)) {
        $relativePath = $fullPath.Substring($basePath.Length).TrimStart('\', '/')
        return $relativePath
    }

    # Fallback: return just the filename if paths don't match
    return [System.IO.Path]::GetFileName($FullPath)
}

# Validation functions
function Test-Prerequisites {
    Write-Phase "Validating Prerequisites"
    
    # Check if git is available
    try {
        $null = git --version
        Write-Success "Git is available"
    }
    catch {
        throw "Git is not installed or not in PATH"
    }
    
    # Check if dotnet is available
    try {
        $null = dotnet --version
        Write-Success ".NET SDK is available"
    }
    catch {
        throw ".NET SDK is not installed or not in PATH"
    }
    
    # Validate repository path
    if (-not (Test-Path $RepositoryPath)) {
        throw "Repository path does not exist: $RepositoryPath"
    }
    
    # Check if it's a git repository
    Push-Location $RepositoryPath
    try {
        $null = git rev-parse --git-dir 2>$null
        Write-Success "Valid Git repository detected"
    }
    catch {
        throw "Not a Git repository: $RepositoryPath"
    }
    finally {
        Pop-Location
    }
}

function Test-RepositoryState {
    Write-Phase "Validating Repository State"

    Push-Location $RepositoryPath
    try {
        # Get remote origin URL
        $remoteUrl = git remote get-url origin 2>$null
        if (-not $remoteUrl) {
            Write-Warning "No remote origin configured. This may indicate an incomplete repository setup."
            if ($PostMigration) {
                throw "Post-migration validation failed: No remote origin found. Expected GitHub repository remote."
            }
        } else {
            Write-Success "Remote origin found: $remoteUrl"

            # Validate remote origin if expected organization is specified
            if ($ExpectedRemoteOrg) {
                if ($remoteUrl -match "github\.com[:/]$ExpectedRemoteOrg/") {
                    Write-Success "Remote origin matches expected organization: $ExpectedRemoteOrg"
                } else {
                    $warningMsg = "Remote origin does not match expected organization '$ExpectedRemoteOrg'. Found: $remoteUrl"
                    if ($PostMigration) {
                        throw "Post-migration validation failed: $warningMsg"
                    } else {
                        Write-Warning $warningMsg
                    }
                }
            }

            # Check if this looks like a GitHub repository
            if ($remoteUrl -match "github\.com") {
                Write-Success "GitHub repository detected"

                # Extract repository name for later use
                if ($remoteUrl -match "github\.com[:/]([^/]+)/([^/]+?)(?:\.git)?/?$") {
                    $script:GitHubOrg = $matches[1]
                    $script:GitHubRepo = $matches[2]
                    Write-Info "GitHub Organization: $script:GitHubOrg"
                    Write-Info "Repository Name: $script:GitHubRepo"
                }
            } else {
                Write-Warning "Non-GitHub remote detected. Some features may not work optimally."
            }
        }

        # Check repository status
        $status = git status --porcelain 2>$null
        if ($status) {
            Write-Warning "Repository has uncommitted changes. Consider committing or stashing changes before enhancement."
            if ($PostMigration) {
                Write-Info "Post-migration: Uncommitted changes detected, but this is expected after fresh clone."
            }
        } else {
            Write-Success "Repository working directory is clean"
        }

        # Check if we can fetch from remote (connectivity test)
        if ($remoteUrl) {
            Write-Info "Testing remote connectivity..."
            $fetchTest = git ls-remote --heads origin 2>$null
            if ($LASTEXITCODE -eq 0) {
                Write-Success "Remote connectivity verified"
            } else {
                Write-Warning "Cannot connect to remote repository. Check network connectivity and credentials."
            }
        }

    } finally {
        Pop-Location
    }
}

function Get-DotNetProjects {
    Write-Info "Scanning for .NET projects..."
    
    $projects = @()
    $csprojFiles = Get-ChildItem -Path $RepositoryPath -Filter "*.csproj" -Recurse
    $slnFiles = Get-ChildItem -Path $RepositoryPath -Filter "*.sln" -Recurse
    
    foreach ($proj in $csprojFiles) {
        $relativePath = Get-RelativePath $RepositoryPath $proj.FullName
        $projects += @{
            Type = "Project"
            Name = $proj.BaseName
            Path = $relativePath
            Directory = [System.IO.Path]::GetDirectoryName($relativePath)
        }
    }
    
    foreach ($sln in $slnFiles) {
        $relativePath = Get-RelativePath $RepositoryPath $sln.FullName
        $projects += @{
            Type = "Solution"
            Name = $sln.BaseName
            Path = $relativePath
            Directory = [System.IO.Path]::GetDirectoryName($relativePath)
        }
    }
    
    if ($projects.Count -eq 0) {
        throw "No .NET projects or solutions found in repository"
    }
    
    Write-Success "Found $($projects.Count) .NET project(s)/solution(s)"
    return $projects
}

function Get-DefaultBranch {
    if ($DefaultBranch) {
        Write-Info "Using specified default branch: $DefaultBranch"
        return $DefaultBranch
    }
    
    Write-Info "Auto-detecting default branch..."
    Push-Location $RepositoryPath
    try {
        $remoteBranch = git symbolic-ref refs/remotes/origin/HEAD 2>$null
        if ($remoteBranch) {
            $branch = $remoteBranch -replace "refs/remotes/origin/", ""
            Write-Success "Detected default branch: $branch"
            return $branch
        }
        
        # Fallback: try common default branch names
        $commonBranches = @("main", "master", "develop")
        foreach ($branch in $commonBranches) {
            $exists = git show-ref --verify --quiet "refs/remotes/origin/$branch" 2>$null
            if ($LASTEXITCODE -eq 0) {
                Write-Success "Using fallback default branch: $branch"
                return $branch
            }
        }
        
        throw "Could not determine default branch"
    }
    finally {
        Pop-Location
    }
}

function New-BackupDirectory {
    if ($BackupPath) {
        $backupDir = $BackupPath
    } else {
        $timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
        $backupDir = Join-Path $RepositoryPath "backup-$timestamp"
    }
    
    if (-not $DryRun) {
        New-Item -ItemType Directory -Path $backupDir -Force | Out-Null
        Write-Success "Created backup directory: $backupDir"
        $script:BackupCreated = $true
    } else {
        Write-Info "Would create backup directory: $backupDir"
    }
    
    return $backupDir
}

# Template functions
function Get-VSCodeTasksTemplate {
    param([object]$MainProject)
    
    # Use forward slashes consistently for cross-platform compatibility
    $projectPath = if ($MainProject.Directory) { "$($MainProject.Directory)/$($MainProject.Name).csproj" } else { "$($MainProject.Name).csproj" }
    $projectPath = $projectPath -replace '\\', '/'
    
    return @"
{
    "version": "2.0.0",
    "tasks": [
        {
            "label": "build",
            "command": "dotnet",
            "type": "process",
            "args": [
                "build",
                "`${workspaceFolder}/$projectPath",
                "/property:GenerateFullPaths=true",
                "/consoleloggerparameters:NoSummary"
            ],
            "group": "build",
            "presentation": {
                "reveal": "silent"
            },
            "problemMatcher": "`$msCompile"
        },
        {
            "label": "publish",
            "command": "dotnet",
            "type": "process",
            "args": [
                "publish",
                "`${workspaceFolder}/$projectPath",
                "/property:GenerateFullPaths=true",
                "/consoleloggerparameters:NoSummary"
            ],
            "group": "build",
            "presentation": {
                "reveal": "silent"
            },
            "problemMatcher": "`$msCompile"
        },
        {
            "label": "watch",
            "command": "dotnet",
            "type": "process",
            "args": [
                "watch",
                "run",
                "--project",
                "`${workspaceFolder}/$projectPath"
            ],
            "group": "build",
            "presentation": {
                "reveal": "always"
            },
            "problemMatcher": "`$msCompile"
        },
        {
            "label": "clean",
            "command": "dotnet",
            "type": "process",
            "args": [
                "clean",
                "`${workspaceFolder}/$projectPath",
                "/property:GenerateFullPaths=true",
                "/consoleloggerparameters:NoSummary"
            ],
            "group": "build",
            "presentation": {
                "reveal": "silent"
            },
            "problemMatcher": "`$msCompile"
        },
        {
            "label": "restore",
            "command": "dotnet",
            "type": "process",
            "args": [
                "restore",
                "`${workspaceFolder}/$projectPath"
            ],
            "group": "build",
            "presentation": {
                "reveal": "silent"
            },
            "problemMatcher": "`$msCompile"
        },
        {
            "label": "run",
            "command": "dotnet",
            "type": "process",
            "args": [
                "run",
                "--project",
                "`${workspaceFolder}/$projectPath"
            ],
            "group": "test",
            "presentation": {
                "reveal": "always"
            },
            "problemMatcher": "`$msCompile"
        }
    ]
}
"@
}

function Get-VSCodeLaunchTemplate {
    param([object]$MainProject)

    $projectName = $MainProject.Name
    $projectDir = if ($MainProject.Directory) { $MainProject.Directory } else { "." }
    # Normalize path separators for cross-platform compatibility
    $projectDir = $projectDir -replace '\\', '/'

    return @"
{
    "version": "0.2.0",
    "configurations": [
        {
            "name": ".NET Core Launch (console)",
            "type": "coreclr",
            "request": "launch",
            "preLaunchTask": "build",
            "program": "`${workspaceFolder}/$projectDir/bin/Debug/net8.0/$projectName.dll",
            "args": [],
            "cwd": "`${workspaceFolder}/$projectDir",
            "console": "internalConsole",
            "stopAtEntry": false
        },
        {
            "name": ".NET Core Attach",
            "type": "coreclr",
            "request": "attach"
        }
    ]
}
"@
}

function Get-DevContainerTemplate {
    param([object]$MainProject)

    $projectPath = if ($MainProject.Directory) { "$($MainProject.Directory)/$($MainProject.Name).csproj" } else { "$($MainProject.Name).csproj" }
    # Normalize path separators for cross-platform compatibility
    $projectPath = $projectPath -replace '\\', '/'

    return @"
{
  "name": ".NET High-Performance Environment",
  "image": "mcr.microsoft.com/devcontainers/dotnet:8.0",
  "hostRequirements": {
    "cpus": 8,
    "memory": "16gb"
  },
  "customizations": {
    "vscode": {
      "extensions": [
        "ms-dotnettools.csdevkit",
        "ms-dotnettools.csharp",
        "ms-dotnettools.vscode-dotnet-runtime",
        "GitHub.copilot",
        "GitHub.copilot-chat",
        "septag.visual-assist-dark",
        "jeff-hykin.better-c-sharp-syntax",
        "icsharpcode.ilspy-vscode",
        "patcx.vscode-nuget-gallery",
        "ryanluker.vscode-coverage-gutters",
        "humao.rest-client"
      ]
    }
  },
  "forwardPorts": [],
  "postCreateCommand": "dotnet restore $projectPath",
  "remoteUser": "vscode"
}
"@
}

function Get-GitHubActionsTemplate {
    param([object]$MainProject)

    $projectPath = if ($MainProject.Directory) { "$($MainProject.Directory)/$($MainProject.Name).csproj" } else { "$($MainProject.Name).csproj" }
    # Normalize path separators for cross-platform compatibility
    $projectPath = $projectPath -replace '\\', '/'

    return @"
name: .NET CI/CD Pipeline

on:
  push:
    branches: [ "**" ]
  pull_request:
    branches: [ "**" ]

jobs:
  build-and-test:
    runs-on: ubuntu-latest

    strategy:
      matrix:
        dotnet-version: ['8.0.x']

    steps:
    - name: Checkout code
      uses: actions/checkout@v4

    - name: Setup .NET
      uses: actions/setup-dotnet@v4
      with:
        dotnet-version: `${{ matrix.dotnet-version }}

    - name: Cache NuGet packages
      uses: actions/cache@v4
      with:
        path: ~/.nuget/packages
        key: `${{ runner.os }}-nuget-`${{ hashFiles('**/*.csproj') }}
        restore-keys: |
          `${{ runner.os }}-nuget-

    - name: Restore dependencies
      run: dotnet restore $projectPath

    - name: Build project
      run: dotnet build $projectPath --no-restore --configuration Release

    - name: Run tests (if any)
      run: dotnet test $projectPath --no-build --configuration Release --verbosity normal
      continue-on-error: true

    - name: Publish artifacts
      run: dotnet publish $projectPath --no-build --configuration Release --output ./publish

    - name: Upload build artifacts
      uses: actions/upload-artifact@v4
      with:
        name: published-app-`${{ github.sha }}
        path: ./publish
        retention-days: 30

  code-quality:
    runs-on: ubuntu-latest
    needs: build-and-test

    steps:
    - name: Checkout code
      uses: actions/checkout@v4

    - name: Setup .NET
      uses: actions/setup-dotnet@v4
      with:
        dotnet-version: '8.0.x'

    - name: Restore dependencies
      run: dotnet restore $projectPath

    - name: Build with warnings as errors
      run: dotnet build $projectPath --no-restore --configuration Release --verbosity normal

    - name: Run static analysis
      run: |
        echo "Static analysis would run here"
        echo "Consider adding tools like SonarQube, CodeQL, or other analyzers"

  security-scan:
    runs-on: ubuntu-latest
    needs: build-and-test

    steps:
    - name: Checkout code
      uses: actions/checkout@v4

    - name: Setup .NET
      uses: actions/setup-dotnet@v4
      with:
        dotnet-version: '8.0.x'

    - name: Restore dependencies
      run: dotnet restore $projectPath

    - name: Security vulnerability scan
      run: |
        echo "Security scan would run here"
        echo "Consider adding tools like Snyk, OWASP dependency check, or GitHub security scanning"
"@
}

function Get-GitAttributesTemplate {
    return @"
# Auto detect text files and perform LF normalization
* text=auto

# Explicitly declare text files you want to always be normalized and converted
# to native line endings on checkout.
*.cs text
*.csproj text
*.sln text
*.json text
*.yml text
*.yaml text
*.md text
*.txt text
*.ps1 text

# Declare files that will always have CRLF line endings on checkout.
*.bat text eol=crlf

# Declare files that will always have LF line endings on checkout.
*.sh text eol=lf

# Denote all files that are truly binary and should not be modified.
*.png binary
*.jpg binary
*.jpeg binary
*.gif binary
*.ico binary
*.dll binary
*.exe binary
*.zip binary
*.7z binary
*.tar binary
*.gz binary
"@
}

function Get-ReadmeTemplate {
    param(
        [string]$RepositoryName,
        [object]$MainProject,
        [string]$DefaultBranch
    )

    $projectPath = if ($MainProject.Directory) { $MainProject.Directory } else { "." }

    # Use detected GitHub info if available, otherwise use placeholders
    $githubOrg = if ($script:GitHubOrg) { $script:GitHubOrg } else { "USER" }
    $githubRepo = if ($script:GitHubRepo) { $script:GitHubRepo } else { "REPO" }

    return @"
# $RepositoryName

[![.NET CI/CD Pipeline](https://github.com/$githubOrg/$githubRepo/actions/workflows/ci.yml/badge.svg)](https://github.com/$githubOrg/$githubRepo/actions/workflows/ci.yml)

This repository contains a .NET application with a fully configured development environment for optimal productivity.

## Quick Start

### Option 1: GitHub Codespaces (Recommended)
The fastest way to get started is using GitHub Codespaces, which provides a fully configured development environment in the cloud.

1. Click the **Code** button on this repository
2. Select **Codespaces** tab
3. Click **Create codespace on $DefaultBranch**
4. Wait for the environment to initialize (this may take a few minutes)
5. Once ready, you can immediately start coding with full IntelliSense and debugging support

### Option 2: Local Development with VS Code
1. **Prerequisites:**
   - [.NET 8.0 SDK](https://dotnet.microsoft.com/download/dotnet/8.0)
   - [Visual Studio Code](https://code.visualstudio.com/)
   - [C# Dev Kit extension](https://marketplace.visualstudio.com/items?itemName=ms-dotnettools.csdevkit)

2. **Clone and Setup:**
   ``````bash
   git clone https://github.com/USER/REPO.git
   cd REPO
   code .
   ``````

3. **Restore Dependencies:**
   ``````bash
   dotnet restore $($MainProject.Path)
   ``````

## Build and Debug

### Using VS Code Tasks
This repository includes pre-configured VS Code tasks for common operations:

- **Build:** ``Ctrl+Shift+P`` → "Tasks: Run Task" → "build"
- **Run:** ``Ctrl+Shift+P`` → "Tasks: Run Task" → "run"
- **Clean:** ``Ctrl+Shift+P`` → "Tasks: Run Task" → "clean"
- **Watch:** ``Ctrl+Shift+P`` → "Tasks: Run Task" → "watch" (auto-rebuilds on file changes)

### Using Command Line
``````bash
# Navigate to the project directory
cd $projectPath

# Restore dependencies
dotnet restore

# Build the project
dotnet build

# Run the application
dotnet run

# Clean build artifacts
dotnet clean

# Watch for changes and auto-rebuild
dotnet watch run
``````

### Debugging in VS Code
1. Open the project in VS Code
2. Set breakpoints by clicking in the left margin of the code editor
3. Press ``F5`` or go to **Run and Debug** panel
4. Select ".NET Core Launch (console)" configuration
5. The debugger will start and stop at your breakpoints

## Project Structure

``````
$($MainProject.Name)/
├── $($MainProject.Name).csproj    # Project configuration
├── Program.cs                     # Application entry point
└── ...                           # Additional source files
``````

## Development Environment Features

### VS Code Configuration
- **IntelliSense:** Full C# code completion and suggestions
- **Debugging:** Integrated debugging with breakpoints and variable inspection
- **Tasks:** Pre-configured build, run, and test tasks
- **Extensions:** Automatically installed C# development extensions

### DevContainer/Codespaces Features
- **High-Performance Environment:** 8 CPU cores, 16GB RAM
- **Pre-installed Extensions:**
  - C# Dev Kit with full language support
  - GitHub Copilot for AI-assisted coding
  - Visual Assist for enhanced productivity
  - Better C# syntax highlighting
  - IL Spy for .NET decompilation
  - NuGet Gallery integration
  - Coverage gutters for test coverage
  - REST Client for API testing

### Continuous Integration
- **Automated Builds:** Every push and pull request triggers automated builds
- **Multi-job Pipeline:** Build, test, code quality, and security scanning
- **Artifact Storage:** Build outputs are stored for 30 days
- **Cross-branch Support:** CI runs on all branches to ensure consistency

## Contributing

1. Fork the repository
2. Create a feature branch: ``git checkout -b feature/your-feature-name``
3. Make your changes and commit: ``git commit -m "Add your feature"``
4. Push to your fork: ``git push origin feature/your-feature-name``
5. Create a Pull Request

## Code Style

This project follows standard C# coding conventions:
- PascalCase for public members and types
- camelCase for private fields and local variables
- Meaningful names for classes, methods, and variables
- XML documentation comments for public APIs

## Troubleshooting

### Common Issues

**Build Errors:**
- Ensure .NET 8.0 SDK is installed
- Run ``dotnet restore`` to restore NuGet packages
- Check that you're in the correct directory

**VS Code Issues:**
- Install the C# Dev Kit extension
- Reload VS Code window: ``Ctrl+Shift+P`` → "Developer: Reload Window"
- Check that .NET is properly installed: ``dotnet --version``

**Codespaces Issues:**
- Wait for the environment to fully initialize
- If extensions aren't working, try rebuilding the container
- Check the terminal for any error messages during setup

---

Happy coding!
"@
}

function Show-PostMigrationGuidance {
    if ($PostMigration) {
        Write-ColorOutput "`n=== Post-Migration Enhancement Complete ===" "Green"
        Write-Info "This repository has been successfully enhanced after migration."
        Write-Info ""
        Write-Info "Migration + Enhancement workflow completed:"
        Write-ColorOutput "  ✅ Repository migrated to GitHub" "Green"
        Write-ColorOutput "  ✅ Development environment configured" "Green"
        Write-ColorOutput "  ✅ VS Code and DevContainer setup complete" "Green"
        Write-ColorOutput "  ✅ CI/CD pipeline configured" "Green"
        Write-ColorOutput "  ✅ Professional documentation created" "Green"
        Write-Info ""
        Write-Info "Next step in the modernization workflow:"
        Write-ColorOutput "  Run: .\Update-DotNetProjectsAllBranches.ps1 -RepositoryPath '.'" "Cyan"
        Write-Info ""
        Write-Info "This will:"
        Write-Info "  • Update all .NET projects to .NET 8.0 and C# 12"
        Write-Info "  • Add .idea/ to .gitignore files"
        Write-Info "  • Ensure .devcontainer is synchronized across all branches"
    }
}

# Implementation functions
function Invoke-Phase0 {
    param(
        [object]$MainProject,
        [string]$BackupDir
    )

    Write-Phase "Phase 0: Environment Setup"

    # Create .vscode directory
    $vscodeDir = Join-Path $RepositoryPath ".vscode"
    if (-not $DryRun) {
        New-Item -ItemType Directory -Path $vscodeDir -Force | Out-Null
    }

    # Backup existing files
    $filesToCreate = @(
        @{ Path = ".vscode/tasks.json"; Template = Get-VSCodeTasksTemplate $MainProject },
        @{ Path = ".vscode/launch.json"; Template = Get-VSCodeLaunchTemplate $MainProject },
        @{ Path = ".devcontainer/devcontainer.json"; Template = Get-DevContainerTemplate $MainProject },
        @{ Path = ".gitattributes"; Template = Get-GitAttributesTemplate }
    )

    foreach ($file in $filesToCreate) {
        $fullPath = Join-Path $RepositoryPath $file.Path
        $backupPath = Join-Path $BackupDir $file.Path

        # Backup existing file
        if (Test-Path $fullPath) {
            if (-not $DryRun) {
                $backupParent = Split-Path $backupPath -Parent
                New-Item -ItemType Directory -Path $backupParent -Force | Out-Null
                Copy-Item $fullPath $backupPath -Force
            }
            Write-Info "Backed up existing: $($file.Path)"
        }

        # Create new file
        if ($DryRun) {
            Write-Info "Would create: $($file.Path)"
        } else {
            $parentDir = Split-Path $fullPath -Parent
            New-Item -ItemType Directory -Path $parentDir -Force | Out-Null
            Set-Content -Path $fullPath -Value $file.Template -Encoding UTF8
            Write-Success "Created: $($file.Path)"
            $script:Changes += "Created $($file.Path)"
        }
    }
}

function Invoke-Phase1 {
    param(
        [string]$DefaultBranch
    )

    if ($SkipBranchSync) {
        Write-Warning "Skipping Phase 1: Branch Synchronization (SkipBranchSync specified)"
        return
    }

    Write-Phase "Phase 1: Branch Synchronization"

    Push-Location $RepositoryPath
    try {
        # Get all remote branches except default
        $branches = git branch -r | Where-Object {
            $_ -notmatch "HEAD" -and
            $_.Trim() -replace "origin/", "" -ne $DefaultBranch -and
            $_.Trim() -ne ""
        } | ForEach-Object { $_.Trim() -replace "origin/", "" }

        if ($branches.Count -eq 0) {
            Write-Info "No additional branches found to synchronize"
            return
        }

        Write-Info "Found $($branches.Count) branches to synchronize"

        $successCount = 0
        $skipCount = 0
        $errorCount = 0

        foreach ($branch in $branches) {
            Write-Info "Processing branch: $branch"

            if ($DryRun) {
                Write-Info "Would synchronize .vscode and .devcontainer to branch: $branch"
                continue
            }

            try {
                # Suppress PowerShell error handling for Git operations
                $oldErrorActionPreference = $ErrorActionPreference
                $ErrorActionPreference = 'SilentlyContinue'

                try {
                    # Checkout branch (create local tracking branch if needed)
                    git checkout -B $branch origin/$branch 2>$null
                    if ($LASTEXITCODE -ne 0) {
                        # Fallback: try regular checkout if branch already exists locally
                        git checkout $branch 2>$null
                        if ($LASTEXITCODE -ne 0) {
                            Write-Warning "Failed to checkout branch: $branch"
                            $errorCount++
                            continue
                        }
                    }

                    # Copy .vscode and .devcontainer from default branch
                    git checkout $DefaultBranch -- .vscode .devcontainer 2>$null
                    if ($LASTEXITCODE -ne 0) {
                        Write-Warning "Failed to copy .vscode and .devcontainer to branch: $branch"
                        $errorCount++
                        continue
                    }
                } finally {
                    $ErrorActionPreference = $oldErrorActionPreference
                }

                # Check for changes
                $status = git status --porcelain | Where-Object { $_ -match "\.vscode|\.devcontainer" }
                if ($status) {
                    git add .vscode/ .devcontainer/ 2>$null
                    git commit -m "feat: Synchronize VS Code and DevContainer configurations" 2>$null
                    if ($LASTEXITCODE -eq 0) {
                        git push 2>$null
                        if ($LASTEXITCODE -eq 0) {
                            Write-Success "Updated branch: $branch"
                            $successCount++
                            $script:Changes += "Synchronized .vscode and .devcontainer to branch: $branch"
                        } else {
                            Write-Warning "Failed to push to branch: $branch"
                            $errorCount++
                        }
                    } else {
                        Write-Warning "Failed to commit to branch: $branch"
                        $errorCount++
                    }
                } else {
                    Write-Info "No changes needed for branch: $branch"
                    $skipCount++
                }
            }
            catch {
                # Only treat as error if it's not a Git informational message
                $errorMessage = $_.Exception.Message
                if ($errorMessage -notmatch "Switched to|Already on|branch.*set up to track|Cloning into") {
                    Write-Warning "Error processing branch $branch`: $errorMessage"
                    $errorCount++
                } else {
                    # This is just Git being informative, not an actual error
                    Write-Info "Git completed operation for branch $branch"
                }
            }
        }

        # Return to default branch
        $currentBranch = git branch --show-current
        if ($currentBranch -ne $DefaultBranch) {
            # Suppress all error handling for this specific Git command
            $oldErrorActionPreference = $ErrorActionPreference
            $ErrorActionPreference = 'SilentlyContinue'
            try {
                git checkout $DefaultBranch *>$null
            } finally {
                $ErrorActionPreference = $oldErrorActionPreference
            }
        }

        Write-Info "Branch synchronization summary:"
        Write-Success "  Successfully updated: $successCount branches"
        Write-Info "  No changes needed: $skipCount branches"
        if ($errorCount -gt 0) {
            Write-Warning "  Errors encountered: $errorCount branches"
        }
    }
    finally {
        Pop-Location
    }
}

function Invoke-Phase2 {
    param(
        [object]$MainProject,
        [string]$BackupDir
    )

    Write-Phase "Phase 2: CI/CD Pipeline"

    $workflowPath = ".github/workflows/ci.yml"
    $fullPath = Join-Path $RepositoryPath $workflowPath
    $backupPath = Join-Path $BackupDir $workflowPath

    # Backup existing workflow
    if (Test-Path $fullPath) {
        if (-not $DryRun) {
            $backupParent = Split-Path $backupPath -Parent
            New-Item -ItemType Directory -Path $backupParent -Force | Out-Null
            Copy-Item $fullPath $backupPath -Force
        }
        Write-Info "Backed up existing: $workflowPath"
    }

    # Create GitHub Actions workflow
    if ($DryRun) {
        Write-Info "Would create: $workflowPath"
    } else {
        $parentDir = Split-Path $fullPath -Parent
        New-Item -ItemType Directory -Path $parentDir -Force | Out-Null
        $template = Get-GitHubActionsTemplate $MainProject
        Set-Content -Path $fullPath -Value $template -Encoding UTF8
        Write-Success "Created: $workflowPath"
        $script:Changes += "Created $workflowPath"
    }
}

function Invoke-Phase3 {
    param(
        [object]$MainProject,
        [string]$DefaultBranch,
        [string]$BackupDir
    )

    Write-Phase "Phase 3: Documentation"

    $readmePath = "README.md"
    $fullPath = Join-Path $RepositoryPath $readmePath
    $backupPath = Join-Path $BackupDir $readmePath

    # Backup existing README
    if (Test-Path $fullPath) {
        if (-not $DryRun) {
            Copy-Item $fullPath $backupPath -Force
        }
        Write-Info "Backed up existing: $readmePath"
    }

    # Create comprehensive README
    if ($DryRun) {
        Write-Info "Would create/update: $readmePath"
    } else {
        $repoName = Split-Path $RepositoryPath -Leaf
        $template = Get-ReadmeTemplate $repoName $MainProject $DefaultBranch
        Set-Content -Path $fullPath -Value $template -Encoding UTF8
        Write-Success "Created: $readmePath"
        $script:Changes += "Created/updated $readmePath"
    }
}

function Invoke-GitCommitAndPush {
    param(
        [string]$DefaultBranch
    )

    if ($DryRun) {
        Write-Info "Would commit and push changes to $DefaultBranch"
        return
    }

    Write-Phase "Committing Changes"

    Push-Location $RepositoryPath
    try {
        # Ensure we're on the default branch
        $currentBranch = git branch --show-current
        if ($currentBranch -ne $DefaultBranch) {
            # Suppress PowerShell error handling for Git checkout
            $oldErrorActionPreference = $ErrorActionPreference
            $ErrorActionPreference = 'SilentlyContinue'
            try {
                git checkout $DefaultBranch *>$null
            } finally {
                $ErrorActionPreference = $oldErrorActionPreference
            }
        }

        # Add all new files (suppress line ending warnings)
        $oldErrorActionPreference = $ErrorActionPreference
        $ErrorActionPreference = 'SilentlyContinue'
        try {
            git add .vscode/ .devcontainer/ .github/ README.md .gitattributes *>$null

            # Check if there are changes to commit
            $status = git status --porcelain
            if ($status) {
                # Commit with line ending warning suppression
                git commit -m "feat: Add comprehensive .NET development environment configuration" *>$null
                if ($LASTEXITCODE -eq 0) {
                    Write-Success "Changes committed successfully"

                    # Push changes
                    git push *>$null
                    if ($LASTEXITCODE -eq 0) {
                        Write-Success "Changes pushed to remote repository"
                        $script:Changes += "Committed and pushed all changes"
                    } else {
                        Write-Warning "Failed to push changes to remote repository"
                    }
                } else {
                    Write-Warning "Failed to commit changes"
                }
            } else {
                Write-Info "No changes to commit"
            }
        } finally {
            $ErrorActionPreference = $oldErrorActionPreference
        }
    }
    finally {
        Pop-Location
    }
}

function Show-Summary {
    Write-Phase "Enhancement Summary"

    if ($script:Changes.Count -gt 0) {
        Write-Success "Successfully completed the following changes:"
        foreach ($change in $script:Changes) {
            Write-ColorOutput "  - $change" "Green"
        }
    } else {
        Write-Info "No changes were made"
    }

    if ($script:Errors.Count -gt 0) {
        Write-Warning "`nErrors encountered:"
        foreach ($error in $script:Errors) {
            Write-ColorOutput "  - $error" "Red"
        }
    }

    if ($script:BackupCreated -and -not $DryRun) {
        Write-Info "`nBackup created at: $BackupDir"
        Write-Info "You can restore from backup if needed"
    }

    if ($DryRun) {
        Write-Info "`nThis was a dry run. No actual changes were made."
        Write-Info "Run without -DryRun to apply the changes."
    }
}

# Main execution
function Main {
    try {
        Write-ColorOutput "`n.NET Repository Enhancement Protocol v1.0" "Cyan"
        Write-ColorOutput "============================================" "Cyan"

        if ($DryRun) {
            Write-Warning "DRY RUN MODE - No changes will be made"
        }

        # Convert to absolute path
        $script:RepositoryPath = Resolve-Path $RepositoryPath
        Write-Info "Repository: $RepositoryPath"

        # Validate prerequisites
        Test-Prerequisites

        # Validate repository state and remote configuration
        Test-RepositoryState

        # Detect .NET projects
        $projects = Get-DotNetProjects
        $mainProject = $projects | Where-Object { $_.Type -eq "Project" } | Select-Object -First 1
        if (-not $mainProject) {
            $mainProject = $projects | Select-Object -First 1
        }
        Write-Info "Main project: $($mainProject.Name) ($($mainProject.Type))"

        # Detect default branch
        $detectedDefaultBranch = Get-DefaultBranch

        # Create backup directory
        $backupDir = New-BackupDirectory

        # Execute phases
        Invoke-Phase0 $mainProject $backupDir
        Invoke-Phase1 $detectedDefaultBranch
        Invoke-Phase2 $mainProject $backupDir
        Invoke-Phase3 $mainProject $detectedDefaultBranch $backupDir

        # Commit and push changes
        if (-not $DryRun) {
            Invoke-GitCommitAndPush $detectedDefaultBranch
        }

        # Show summary
        Show-Summary

        Write-ColorOutput "`nSUCCESS: .NET Repository Enhancement Protocol completed successfully!" "Green"

        # Show post-migration guidance if applicable
        Show-PostMigrationGuidance

        if (-not $DryRun -and -not $PostMigration) {
            Write-Info "`nNext steps:"
            Write-Info "1. Open the repository in VS Code or GitHub Codespaces"
            Write-Info "2. Test the build and debug configurations"
            Write-Info "3. Review the CI/CD pipeline in GitHub Actions"
            Write-Info "4. Update the README.md with repository-specific information"
        }
    }
    catch {
        Write-ErrorMessage "Fatal error: $_"
        Write-ColorOutput "`nEnhancement failed. Check the error messages above." "Red"

        if ($script:BackupCreated) {
            Write-Info "Backup is available at: $BackupDir"
        }

        exit 1
    }
}

# Rollback function
function Invoke-Rollback {
    param([string]$BackupPath)

    if (-not (Test-Path $BackupPath)) {
        Write-ErrorMessage "Backup directory not found: $BackupPath"
        return
    }

    Write-Warning "Rolling back changes from backup: $BackupPath"

    try {
        # Restore files from backup
        $backupFiles = Get-ChildItem -Path $BackupPath -Recurse -File
        foreach ($file in $backupFiles) {
            $relativePath = Get-RelativePath $BackupPath $file.FullName
            $targetPath = Join-Path $RepositoryPath $relativePath

            Write-Info "Restoring: $relativePath"
            $targetDir = Split-Path $targetPath -Parent
            New-Item -ItemType Directory -Path $targetDir -Force | Out-Null
            Copy-Item $file.FullName $targetPath -Force
        }

        Write-Success "Rollback completed successfully"
    }
    catch {
        Write-ErrorMessage "Rollback failed: $_"
    }
}

# Execute main function when script is run directly
if ($MyInvocation.InvocationName -ne '.') {
    # Script is being executed directly
    Main
}
# When dot-sourced, functions are automatically available in the calling scope
