# .NET Projects Multi-Branch Updater Guide

## Overview

The `Update-DotNetProjectsAllBranches.ps1` script automates the process of updating all .NET projects across every branch in a Git repository to use .NET 8.0 and C# 12, while also ensuring JetBrains IDE files are properly ignored. This script is designed for repository-wide modernization efforts.

## Features

- **Multi-Branch Processing**: Automatically discovers and processes all branches in the repository
- **Comprehensive Project Discovery**: Finds all .NET project files (*.csproj, *.vbproj, *.fsproj)
- **Safe XML Manipulation**: Validates XML structure before making changes
- **GitIgnore Management**: Automatically adds .idea/ to .gitignore to exclude JetBrains IDE files
- **Git Integration**: Commits and pushes changes with descriptive commit messages
- **Security-First**: Uses environment variables for Git credentials
- **Error Handling**: Gracefully handles branches without projects or XML parsing errors
- **Progress Feedback**: Provides detailed progress information and summary reports
- **Dry Run Support**: Preview changes without applying them

## Prerequisites

### Required Software
- **PowerShell 5.1+**: The script requires PowerShell 5.1 or later
- **Git**: Must be installed and available in PATH
- **.NET SDK**: Required for project validation (any version)

### Git Repository Requirements
- Must be a valid Git repository
- Should have remote origin configured for pushing changes
- All branches should be accessible (local or remote tracking branches will be created as needed)

### Authentication Setup
For pushing changes to remote repositories, set up your GitHub Personal Access Token:

```powershell
# PowerShell
$env:GIT_PAT = "your_github_personal_access_token_here"

# Command Prompt
set GIT_PAT=your_github_personal_access_token_here

# System Environment Variables (Recommended for permanent setup)
# Add GIT_PAT as a system environment variable with your token value
```

**Security Note**: The script reads credentials from environment variables only. It does not accept tokens as parameters for security reasons.

## Usage

### Basic Usage
```powershell
# Update all projects in the current repository
.\Update-DotNetProjectsAllBranches.ps1 -RepositoryPath "."

# Update all projects in a specific repository
.\Update-DotNetProjectsAllBranches.ps1 -RepositoryPath "C:\repos\my-dotnet-project"
```

### Advanced Usage
```powershell
# Preview changes without applying them
.\Update-DotNetProjectsAllBranches.ps1 -RepositoryPath "." -DryRun

# Update projects but skip pushing to remote
.\Update-DotNetProjectsAllBranches.ps1 -RepositoryPath "." -SkipPush

# Combine options
.\Update-DotNetProjectsAllBranches.ps1 -RepositoryPath "." -DryRun -SkipPush
```

## Parameters

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `RepositoryPath` | String | Yes | Path to the Git repository to process |
| `DryRun` | Switch | No | Preview changes without applying them |
| `SkipPush` | Switch | No | Skip pushing changes to remote repository |

## What the Script Does

### 1. Branch Discovery
- Discovers all local and remote branches
- Creates local tracking branches for remote-only branches
- Processes each branch independently

### 2. Project File Discovery
For each branch, the script finds all:
- `*.csproj` files (C# projects)
- `*.vbproj` files (VB.NET projects)  
- `*.fsproj` files (F# projects)

### 3. Project Updates
For each project file, the script:
- Validates XML structure before modification
- Updates `<TargetFramework>` to `net8.0`
- Updates `<LangVersion>` to `12` (for C# projects only)
- Preserves all other project settings and structure

### 4. GitIgnore Updates
For each branch, the script:
- Checks if `.idea/` entry exists in .gitignore
- Adds `.idea/` entry if not present (to exclude JetBrains IDE files)
- Preserves all existing .gitignore content

### 5. Git Operations
For branches with changes:
- Stages all modified files
- Commits with descriptive message (e.g., `"feat: Update .NET projects to net8.0 and C# 12; Add .idea/ to .gitignore"`)
- Pushes changes to remote repository (unless `-SkipPush` is specified)

## Example Project File Changes

### Before
```xml
<Project Sdk="Microsoft.NET.Sdk">
  <PropertyGroup>
    <TargetFramework>net6.0</TargetFramework>
    <LangVersion>10</LangVersion>
  </PropertyGroup>
</Project>
```

### After
```xml
<Project Sdk="Microsoft.NET.Sdk">
  <PropertyGroup>
    <TargetFramework>net8.0</TargetFramework>
    <LangVersion>12</LangVersion>
  </PropertyGroup>
</Project>
```

## Output and Reporting

The script provides comprehensive progress feedback:

### During Execution
- Branch discovery and count
- Current branch being processed
- Project files found per branch
- Individual file update status
- Git operation results

### Summary Report
- Total branches processed successfully
- Branches skipped (no changes needed)
- Branches with errors
- Total project files updated
- Detailed lists of processed, skipped, and failed branches

## Error Handling

The script handles various error conditions gracefully:

### Branch-Level Errors
- Branches that cannot be checked out
- Branches without .NET projects (skipped, not errors)
- Git operation failures

### File-Level Errors
- Invalid XML structure in project files
- File access permissions issues
- Malformed project files

### Repository-Level Errors
- Invalid Git repository
- Missing remote origin
- Authentication failures

## Safety Features

### Backup and Recovery
- Git's version control serves as the backup mechanism
- Original branch is restored after processing
- Each branch maintains its commit history

### Validation
- XML structure validation before modification
- Git repository validation before processing
- Prerequisites checking before execution

### Dry Run Mode
Use `-DryRun` to preview all changes without applying them:
- Shows which files would be updated
- Displays the changes that would be made
- Reports which branches would be processed

## Troubleshooting

### Common Issues

**"GIT_PAT environment variable is not set"**
- Solution: Set up your GitHub Personal Access Token as described in Authentication Setup

**"Failed to checkout branch: [branch-name]"**
- Solution: Ensure all branches are accessible and not corrupted
- Check for uncommitted changes that might prevent branch switching

**"Invalid XML structure in: [file-path]"**
- Solution: Manually fix the XML structure in the problematic project file
- The script will skip invalid files and continue processing others

**"No .NET project files found"**
- This is informational, not an error
- The script will skip branches without .NET projects

### Getting Help
- Use `-DryRun` to preview operations before execution
- Check the detailed summary report for specific error information
- Ensure all prerequisites are met before running the script

## Best Practices

1. **Always test first**: Use `-DryRun` on a test repository or branch
2. **Backup important repositories**: Although Git provides version control, consider additional backups for critical repositories
3. **Review changes**: Check a few updated project files manually to ensure correctness
4. **Gradual rollout**: Consider processing a subset of branches first for large repositories
5. **Monitor CI/CD**: Ensure your build pipelines support .NET 8.0 before running the script

## Integration with Existing Workflows

This script complements other repository enhancement tools:
- Run before `Enhance-DotNetRepository.ps1` for comprehensive repository modernization
- Use alongside CI/CD pipeline updates
- Coordinate with team members for large-scale repository changes
