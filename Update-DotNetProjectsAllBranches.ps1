<#
.SYNOPSIS
    Updates all .NET projects across all repository branches to .NET 8.0 and C# 12.

.DESCRIPTION
    This script performs repository-wide .NET project updates by:
    - Iterating through every branch in the local Git repository
    - Discovering and updating every .NET project file (*.csproj, *.vbproj, *.fsproj)
    - Setting Target Framework to .NET 8.0 and C# Language Version to 12
    - Adding .idea/ to .gitignore to exclude JetBrains IDE files
    - Synchronizing .devcontainer folder from main/default branch to ensure consistent Codespace environments
    - Committing and pushing changes for each branch with modifications

.PARAMETER RepositoryPath
    The path to the Git repository to process (mandatory)

.PARAMETER DryRun
    Preview changes without applying them

.PARAMETER SkipPush
    Skip pushing changes to remote repository

.EXAMPLE
    .\Update-DotNetProjectsAllBranches.ps1 -RepositoryPath "C:\repos\my-dotnet-project"

.EXAMPLE
    .\Update-DotNetProjectsAllBranches.ps1 -RepositoryPath "." -DryRun

.NOTES
    Author: .NET Repository Enhancement Protocol
    Version: 1.0
    Requires: PowerShell 5.1+, Git, .NET SDK
    Security: Uses $env:GIT_PAT for authentication
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$RepositoryPath,
    
    [Parameter(Mandatory = $false)]
    [switch]$DryRun,
    
    [Parameter(Mandatory = $false)]
    [switch]$SkipPush
)

# Color output functions (defined first to be available everywhere)
function Write-ColorOutput {
    param([string]$Message, [string]$Color = "White")
    Write-Host $Message -ForegroundColor $Color
}

function Write-Success {
    param([string]$Message)
    Write-ColorOutput "[SUCCESS] $Message" "Green"
}

function Write-Info {
    param([string]$Message)
    Write-ColorOutput "[INFO] $Message" "Cyan"
}

function Write-Warning {
    param([string]$Message)
    Write-ColorOutput "[WARNING] $Message" "Yellow"
}

function Write-Error {
    param([string]$Message)
    Write-ColorOutput "[ERROR] $Message" "Red"
}

# Constants
$TARGET_FRAMEWORK = "net8.0"
$CSHARP_VERSION = "12"
$PROJECT_EXTENSIONS = @("*.csproj", "*.vbproj", "*.fsproj")
$GITIGNORE_ENTRY = ".idea/"
$DEVCONTAINER_FOLDER = ".devcontainer"
$DEFAULT_BRANCH_NAMES = @("main", "master", "develop")

# Global variables
$script:ProcessedBranches = @()
$script:SkippedBranches = @()
$script:ErrorBranches = @()
$script:TotalProjectsUpdated = 0
$script:DevcontainerSourcePath = $null
$script:DevcontainerSourceBranch = $null

# Prerequisites validation
function Test-Prerequisites {
    Write-Info "Validating prerequisites..."
    
    # Check Git
    if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
        throw "Git is not installed or not in the PATH. Please install Git and try again."
    }
    
    # Check .NET SDK
    if (-not (Get-Command dotnet -ErrorAction SilentlyContinue)) {
        throw ".NET SDK is not installed or not in the PATH. Please install .NET SDK and try again."
    }
    
    # Check repository path
    if (-not (Test-Path $RepositoryPath)) {
        throw "Repository path does not exist: $RepositoryPath"
    }
    
    # Check if it's a Git repository
    Push-Location $RepositoryPath
    try {
        git rev-parse --git-dir 2>$null | Out-Null
        if ($LASTEXITCODE -ne 0) {
            throw "The specified path is not a Git repository: $RepositoryPath"
        }
    } finally {
        Pop-Location
    }
    
    # Check Git credentials if not skipping push
    if (-not $SkipPush -and -not $DryRun) {
        if (-not (Test-Path env:GIT_PAT)) {
            Write-Warning "GIT_PAT environment variable is not set!"
            Write-Info "For security reasons, this script uses environment variables for Git credentials."
            Write-Info "Set your GitHub Personal Access Token: `$env:GIT_PAT = 'your_token_here'"
            Write-Info "Or use -SkipPush to skip pushing changes to remote repository."
            throw "GIT_PAT environment variable is required for pushing changes."
        }
        
        if ([string]::IsNullOrWhiteSpace($env:GIT_PAT)) {
            throw "GIT_PAT environment variable is empty!"
        }
    }
    
    Write-Success "Prerequisites validated"
}

# Get all branches in the repository
function Get-AllBranches {
    Write-Info "Discovering repository branches..."

    Push-Location $RepositoryPath
    try {
        # Get all local branches
        $localBranches = @()
        $gitLocalOutput = git branch
        if ($gitLocalOutput) {
            $localBranches = $gitLocalOutput | ForEach-Object { $_.Trim() -replace '^\*\s*', '' } | Where-Object { $_ -ne "" }
        }

        # Get all remote branches and create local tracking branches if needed
        $remoteBranches = @()
        $gitRemoteOutput = git branch -r
        if ($gitRemoteOutput) {
            $remoteBranches = $gitRemoteOutput |
                Where-Object { $_ -notmatch 'HEAD' } |
                ForEach-Object { ($_.Trim() -replace '^remotes/origin/', '' -replace '^origin/', '') } |
                Where-Object { $_ -ne "" }
        }

        # Combine and deduplicate - ensure we have arrays
        $allBranches = @()
        if ($localBranches) { $allBranches += $localBranches }
        if ($remoteBranches) { $allBranches += $remoteBranches }
        $allBranches = $allBranches | Sort-Object -Unique

        Write-Success "Found $($allBranches.Count) branches: $($allBranches -join ', ')"
        return $allBranches
    } finally {
        Pop-Location
    }
}

# Discover .NET project files in current branch
function Get-DotNetProjectFiles {
    $projectFiles = @()
    
    foreach ($extension in $PROJECT_EXTENSIONS) {
        $files = Get-ChildItem -Path $RepositoryPath -Filter $extension -Recurse -ErrorAction SilentlyContinue
        $projectFiles += $files
    }
    
    return $projectFiles
}

# Validate XML structure of project file
function Test-ProjectFileXml {
    param([string]$FilePath)
    
    try {
        $xml = [xml](Get-Content $FilePath -Raw)
        return $true
    } catch {
        Write-Warning "Invalid XML structure in: $FilePath - $($_.Exception.Message)"
        return $false
    }
}

# Update a single project file
function Update-ProjectFile {
    param(
        [string]$FilePath,
        [string]$BranchName
    )

    if (-not (Test-ProjectFileXml $FilePath)) {
        return $false
    }

    try {
        $xml = [xml](Get-Content $FilePath -Raw)
        $modified = $false

        # Find or create PropertyGroup
        $propertyGroup = $xml.Project.PropertyGroup | Select-Object -First 1
        if (-not $propertyGroup) {
            $propertyGroup = $xml.CreateElement("PropertyGroup")
            $xml.Project.AppendChild($propertyGroup) | Out-Null
        }

        # Update TargetFramework
        $targetFrameworkNodes = $propertyGroup.SelectNodes("TargetFramework")
        if ($targetFrameworkNodes.Count -eq 0) {
            $targetFrameworkNode = $xml.CreateElement("TargetFramework")
            $targetFrameworkNode.InnerText = $TARGET_FRAMEWORK
            $propertyGroup.AppendChild($targetFrameworkNode) | Out-Null
            $modified = $true
        } else {
            $targetFrameworkNode = $targetFrameworkNodes[0]
            if ($targetFrameworkNode.InnerText -ne $TARGET_FRAMEWORK) {
                $targetFrameworkNode.InnerText = $TARGET_FRAMEWORK
                $modified = $true
            }
        }

        # Update LangVersion (for C# projects)
        if ($FilePath -like "*.csproj") {
            $langVersionNodes = $propertyGroup.SelectNodes("LangVersion")
            if ($langVersionNodes.Count -eq 0) {
                $langVersionNode = $xml.CreateElement("LangVersion")
                $langVersionNode.InnerText = $CSHARP_VERSION
                $propertyGroup.AppendChild($langVersionNode) | Out-Null
                $modified = $true
            } else {
                $langVersionNode = $langVersionNodes[0]
                if ($langVersionNode.InnerText -ne $CSHARP_VERSION) {
                    $langVersionNode.InnerText = $CSHARP_VERSION
                    $modified = $true
                }
            }
        }

        if ($modified) {
            if (-not $DryRun) {
                $xml.Save($FilePath)
            }
            $relativePath = Get-RelativePath $RepositoryPath $FilePath
            Write-Success "Updated: $relativePath (Branch: $BranchName)"
            return $true
        } else {
            $relativePath = Get-RelativePath $RepositoryPath $FilePath
            Write-Info "Already up-to-date: $relativePath (Branch: $BranchName)"
            return $false
        }
    } catch {
        $relativePath = Get-RelativePath $RepositoryPath $FilePath
        Write-Error "Failed to update: $relativePath - $($_.Exception.Message)"
        return $false
    }
}

# Update .gitignore file to include .idea/ folder
function Update-GitIgnore {
    param([string]$BranchName)

    $gitignorePath = Join-Path $RepositoryPath ".gitignore"
    $modified = $false

    try {
        # Read existing .gitignore content or create empty array
        $gitignoreContent = @()
        if (Test-Path $gitignorePath) {
            $gitignoreContent = Get-Content $gitignorePath -ErrorAction SilentlyContinue
            if (-not $gitignoreContent) {
                $gitignoreContent = @()
            }
        }

        # Check if .idea/ is already in .gitignore
        $ideaEntryExists = $gitignoreContent | Where-Object { $_.Trim() -eq $GITIGNORE_ENTRY }

        if (-not $ideaEntryExists) {
            # Add .idea/ entry to .gitignore
            $gitignoreContent += ""  # Add blank line for separation
            $gitignoreContent += "# JetBrains IDEs"
            $gitignoreContent += $GITIGNORE_ENTRY

            if (-not $DryRun) {
                Set-Content -Path $gitignorePath -Value $gitignoreContent -Encoding UTF8
            }

            Write-Success "Added $GITIGNORE_ENTRY to .gitignore (Branch: $BranchName)"
            $modified = $true
        } else {
            Write-Info ".gitignore already contains $GITIGNORE_ENTRY entry (Branch: $BranchName)"
        }

        return $modified
    } catch {
        Write-Error "Failed to update .gitignore: $($_.Exception.Message)"
        return $false
    }
}

# Get relative path for display
function Get-RelativePath {
    param([string]$BasePath, [string]$FullPath)
    return $FullPath.Substring($BasePath.Length).TrimStart('\', '/')
}

# Find and cache the devcontainer source from the default branch
function Initialize-DevcontainerSource {
    Write-Info "Looking for .devcontainer folder in default branches..."

    # First, try to detect the actual default branch from Git
    $actualDefaultBranch = $null

    Push-Location $RepositoryPath
    try {
        # Method 1: Check remote HEAD to get the actual default branch
        $remoteHead = git symbolic-ref refs/remotes/origin/HEAD 2>$null
        if ($LASTEXITCODE -eq 0 -and $remoteHead) {
            $actualDefaultBranch = $remoteHead -replace "refs/remotes/origin/", ""
            Write-Info "Detected default branch from remote HEAD: $actualDefaultBranch"
        }

        # Method 2: If remote HEAD is not set, try to determine it
        if (-not $actualDefaultBranch) {
            # Try to set remote HEAD first
            git remote set-head origin -a 2>$null | Out-Null
            if ($LASTEXITCODE -eq 0) {
                $remoteHead = git symbolic-ref refs/remotes/origin/HEAD 2>$null
                if ($LASTEXITCODE -eq 0 -and $remoteHead) {
                    $actualDefaultBranch = $remoteHead -replace "refs/remotes/origin/", ""
                    Write-Info "Auto-detected default branch: $actualDefaultBranch"
                }
            }
        }

        # Method 3: Fallback to common default branch names
        if (-not $actualDefaultBranch) {
            foreach ($branchName in $DEFAULT_BRANCH_NAMES) {
                git show-ref --verify --quiet "refs/remotes/origin/$branchName" 2>$null
                if ($LASTEXITCODE -eq 0) {
                    $actualDefaultBranch = $branchName
                    Write-Info "Using fallback default branch: $actualDefaultBranch"
                    break
                }
            }
        }

        # Method 4: Use current branch as last resort
        if (-not $actualDefaultBranch) {
            $actualDefaultBranch = git branch --show-current 2>$null
            if ($actualDefaultBranch) {
                Write-Warning "Using current branch as default: $actualDefaultBranch"
            }
        }

        if (-not $actualDefaultBranch) {
            Write-Error "Could not determine default branch"
            return $false
        }

        # Check if .devcontainer exists in the detected default branch using git show (no checkout needed)
        $gitShowPath = "${actualDefaultBranch}:${DEVCONTAINER_FOLDER}/devcontainer.json"
        git show $gitShowPath 2>$null | Out-Null
        if ($LASTEXITCODE -eq 0) {
            $script:DevcontainerSourceBranch = $actualDefaultBranch
            $script:DevcontainerSourcePath = Join-Path $RepositoryPath $DEVCONTAINER_FOLDER
            Write-Success "Found .devcontainer folder in branch: $actualDefaultBranch"
            return $true
        } else {
            Write-Warning "No .devcontainer folder found in default branch: $actualDefaultBranch"
            return $false
        }

    } catch {
        Write-Error "Error while searching for .devcontainer source: $($_.Exception.Message)"
        return $false
    } finally {
        Pop-Location
    }
}

# Synchronize .devcontainer folder to current branch
function Sync-DevcontainerFolder {
    param([string]$BranchName)

    # Skip if no devcontainer source found or if we're on the source branch
    if (-not $script:DevcontainerSourceBranch -or $BranchName -eq $script:DevcontainerSourceBranch) {
        return $false
    }

    try {
        Push-Location $RepositoryPath

        # Create temporary directory for devcontainer extraction
        $tempDevcontainerPath = Join-Path $env:TEMP "devcontainer-sync-$(Get-Random)"
        New-Item -ItemType Directory -Path $tempDevcontainerPath -Force | Out-Null

        # Extract .devcontainer files from source branch using git show (no checkout needed)
        Write-Info "Extracting .devcontainer files from $script:DevcontainerSourceBranch branch..."

        # Get list of files in .devcontainer folder from source branch
        $devcontainerFiles = git ls-tree -r --name-only $script:DevcontainerSourceBranch -- $DEVCONTAINER_FOLDER 2>$null
        if ($LASTEXITCODE -ne 0 -or -not $devcontainerFiles) {
            Write-Warning ".devcontainer folder not found in source branch $script:DevcontainerSourceBranch"
            Remove-Item -Path $tempDevcontainerPath -Recurse -Force -ErrorAction SilentlyContinue
            return $false
        }

        # Extract each file from the source branch
        $extractedFiles = @()
        foreach ($file in $devcontainerFiles) {
            $relativePath = $file.Substring($DEVCONTAINER_FOLDER.Length + 1) # Remove ".devcontainer/" prefix
            $targetFile = Join-Path $tempDevcontainerPath $relativePath
            $targetDir = Split-Path $targetFile -Parent

            # Create directory structure if needed
            if (-not (Test-Path $targetDir)) {
                New-Item -ItemType Directory -Path $targetDir -Force | Out-Null
            }

            # Extract file content using git show
            $gitShowPath = "${script:DevcontainerSourceBranch}:${file}"
            $fileContent = git show $gitShowPath 2>$null
            if ($LASTEXITCODE -eq 0) {
                Set-Content -Path $targetFile -Value $fileContent -Encoding UTF8
                $extractedFiles += $targetFile
            } else {
                Write-Warning "Failed to extract file: $file"
            }
        }

        if ($extractedFiles.Count -eq 0) {
            Write-Warning "No .devcontainer files could be extracted from $script:DevcontainerSourceBranch"
            Remove-Item -Path $tempDevcontainerPath -Recurse -Force -ErrorAction SilentlyContinue
            return $false
        }

        $targetDevcontainerPath = Join-Path $RepositoryPath $DEVCONTAINER_FOLDER
        $needsSync = $true

        # Check if target already has .devcontainer and if it's different
        if (Test-Path $targetDevcontainerPath) {
            Write-Info "Comparing existing .devcontainer with source..."
            $needsSync = $false

            # Compare each extracted file with existing target
            foreach ($extractedFile in $extractedFiles) {
                $relativePath = $extractedFile.Substring($tempDevcontainerPath.Length).TrimStart('\', '/')
                $targetFile = Join-Path $targetDevcontainerPath $relativePath

                if (-not (Test-Path $targetFile)) {
                    Write-Info "New file detected: $relativePath"
                    $needsSync = $true
                    break
                }

                # Compare file content
                $sourceContent = Get-Content $extractedFile -Raw -ErrorAction SilentlyContinue
                $targetContent = Get-Content $targetFile -Raw -ErrorAction SilentlyContinue

                if ($sourceContent -ne $targetContent) {
                    Write-Info "Content difference detected in: $relativePath"
                    $needsSync = $true
                    break
                }
            }
        }

        if (-not $needsSync) {
            Write-Info ".devcontainer already up-to-date (Branch: $BranchName)"
            Remove-Item -Path $tempDevcontainerPath -Recurse -Force -ErrorAction SilentlyContinue
            return $false
        }

        if (-not $DryRun) {
            # Remove existing .devcontainer folder if it exists
            if (Test-Path $targetDevcontainerPath) {
                Remove-Item -Path $targetDevcontainerPath -Recurse -Force -ErrorAction Stop
            }

            # Create .devcontainer directory
            New-Item -ItemType Directory -Path $targetDevcontainerPath -Force | Out-Null

            # Copy extracted files to target location
            foreach ($extractedFile in $extractedFiles) {
                $relativePath = $extractedFile.Substring($tempDevcontainerPath.Length).TrimStart('\', '/')
                $targetFile = Join-Path $targetDevcontainerPath $relativePath
                $targetDir = Split-Path $targetFile -Parent

                # Create directory structure if needed
                if (-not (Test-Path $targetDir)) {
                    New-Item -ItemType Directory -Path $targetDir -Force | Out-Null
                }

                Copy-Item -Path $extractedFile -Destination $targetFile -Force
            }

            # Verify the sync was successful
            if (-not (Test-Path $targetDevcontainerPath)) {
                throw "Failed to create .devcontainer folder in target location"
            }
        }

        # Clean up temp folder
        Remove-Item -Path $tempDevcontainerPath -Recurse -Force -ErrorAction SilentlyContinue

        Write-Success "Synchronized .devcontainer from $script:DevcontainerSourceBranch branch (Branch: $BranchName)"
        return $true

    } catch {
        Write-Error "Failed to sync .devcontainer folder: $($_.Exception.Message)"
        return $false
    } finally {
        Pop-Location
    }
}

# Process a single branch
function Process-Branch {
    param([string]$BranchName)

    Write-Info "Processing branch: $BranchName"

    Push-Location $RepositoryPath
    try {
        # Store current branch
        $currentBranch = git branch --show-current

        # Checkout target branch
        if ($currentBranch -ne $BranchName) {
            # Check if local branch exists
            $localBranchExists = git branch --list $BranchName
            if (-not $localBranchExists) {
                # Create local tracking branch
                git checkout -b $BranchName origin/$BranchName 2>$null
                if ($LASTEXITCODE -ne 0) {
                    Write-Warning "Failed to create local branch for: $BranchName"
                    return $false
                }
            } else {
                git checkout $BranchName 2>$null
                if ($LASTEXITCODE -ne 0) {
                    Write-Warning "Failed to checkout branch: $BranchName"
                    return $false
                }
            }
        }

        # Discover project files
        $projectFiles = Get-DotNetProjectFiles
        if ($projectFiles.Count -eq 0) {
            Write-Info "No .NET project files found in branch: $BranchName"
            $script:SkippedBranches += $BranchName
            return $true
        }

        Write-Info "Found $($projectFiles.Count) project file(s) in branch: $BranchName"

        # Update each project file
        $updatedCount = 0
        foreach ($projectFile in $projectFiles) {
            if (Update-ProjectFile $projectFile.FullName $BranchName) {
                $updatedCount++
                $script:TotalProjectsUpdated++
            }
        }

        # Update .gitignore file
        $gitignoreUpdated = Update-GitIgnore $BranchName

        # Synchronize .devcontainer folder
        $devcontainerUpdated = Sync-DevcontainerFolder $BranchName

        if ($updatedCount -eq 0 -and -not $gitignoreUpdated -and -not $devcontainerUpdated) {
            Write-Info "No updates needed for branch: $BranchName"
            $script:SkippedBranches += $BranchName
            return $true
        }

        # Commit changes
        if (-not $DryRun) {
            git add . 2>$null

            # Create descriptive commit message
            $commitParts = @()
            if ($updatedCount -gt 0) {
                $commitParts += "Update .NET projects to $TARGET_FRAMEWORK and C# $CSHARP_VERSION"
            }
            if ($gitignoreUpdated) {
                $commitParts += "Add .idea/ to .gitignore"
            }
            if ($devcontainerUpdated) {
                $commitParts += "Sync .devcontainer"
            }
            $commitMessage = "feat: " + ($commitParts -join "; ")

            git commit -m $commitMessage 2>$null

            if ($LASTEXITCODE -eq 0) {
                $changesSummary = @()
                if ($updatedCount -gt 0) {
                    $changesSummary += "$updatedCount project update(s)"
                }
                if ($gitignoreUpdated) {
                    $changesSummary += ".gitignore update"
                }
                if ($devcontainerUpdated) {
                    $changesSummary += ".devcontainer sync"
                }
                Write-Success "Committed $($changesSummary -join ', ') in branch: $BranchName"

                # Push changes if not skipping
                if (-not $SkipPush) {
                    git push origin $BranchName 2>$null
                    if ($LASTEXITCODE -eq 0) {
                        Write-Success "Pushed changes for branch: $BranchName"
                    } else {
                        Write-Warning "Failed to push changes for branch: $BranchName"
                    }
                }
            } else {
                Write-Warning "Failed to commit changes for branch: $BranchName"
                return $false
            }
        } else {
            $dryRunSummary = @()
            if ($updatedCount -gt 0) {
                $dryRunSummary += "$updatedCount project update(s)"
            }
            if ($gitignoreUpdated) {
                $dryRunSummary += ".gitignore update"
            }
            if ($devcontainerUpdated) {
                $dryRunSummary += ".devcontainer sync"
            }
            Write-Info "Would commit $($dryRunSummary -join ', ') in branch: $BranchName"
        }

        $script:ProcessedBranches += $BranchName
        return $true

    } catch {
        Write-Error "Error processing branch $BranchName`: $($_.Exception.Message)"
        $script:ErrorBranches += $BranchName
        return $false
    } finally {
        Pop-Location
    }
}



# Main execution
try {
    Write-ColorOutput "`n.NET Projects Multi-Branch Updater v1.0" "Cyan"
    Write-ColorOutput "===========================================" "Cyan"

    if ($DryRun) {
        Write-Warning "DRY RUN MODE - No changes will be made"
    }

    if ($SkipPush) {
        Write-Warning "SKIP PUSH MODE - Changes will not be pushed to remote"
    }

    # Convert to absolute path
    $script:RepositoryPath = Resolve-Path $RepositoryPath
    Write-Info "Repository: $RepositoryPath"

    # Validate prerequisites
    Test-Prerequisites

    # Initialize devcontainer source
    Initialize-DevcontainerSource | Out-Null

    # Get all branches
    $branches = Get-AllBranches
    if ($branches.Count -eq 0) {
        Write-Warning "No branches found in repository"
        return
    }

    # Store original branch
    Push-Location $RepositoryPath
    $originalBranch = git branch --show-current
    Pop-Location

    Write-Info "Starting processing of $($branches.Count) branches..."
    Write-Info "Original branch: $originalBranch"
    Write-ColorOutput ""

    # Process each branch
    foreach ($branch in $branches) {
        Process-Branch $branch
        Write-ColorOutput ""
    }

    # Restore original branch
    if ($originalBranch) {
        Push-Location $RepositoryPath
        try {
            git checkout $originalBranch 2>$null | Out-Null
            Write-Info "Restored original branch: $originalBranch"
        } finally {
            Pop-Location
        }
    }

    # Summary
    Write-ColorOutput "=== PROCESSING SUMMARY ===" "Green"
    Write-Success "Successfully processed: $($script:ProcessedBranches.Count) branches"
    Write-Info "Skipped (no changes needed): $($script:SkippedBranches.Count) branches"
    Write-Error "Failed: $($script:ErrorBranches.Count) branches"
    Write-Info "Total projects updated: $script:TotalProjectsUpdated"

    if ($script:ProcessedBranches.Count -gt 0) {
        Write-ColorOutput "`nProcessed branches:" "Green"
        $script:ProcessedBranches | ForEach-Object { Write-ColorOutput "  • $_" "White" }
    }

    if ($script:SkippedBranches.Count -gt 0) {
        Write-ColorOutput "`nSkipped branches:" "Yellow"
        $script:SkippedBranches | ForEach-Object { Write-ColorOutput "  • $_" "White" }
    }

    if ($script:ErrorBranches.Count -gt 0) {
        Write-ColorOutput "`nFailed branches:" "Red"
        $script:ErrorBranches | ForEach-Object { Write-ColorOutput "  • $_" "White" }
    }

    Write-ColorOutput "`n=== OPERATION COMPLETED ===" "Green"

} catch {
    Write-Error "Script execution failed: $($_.Exception.Message)"
    exit 1
}
