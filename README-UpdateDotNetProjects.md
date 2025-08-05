# .NET Projects Multi-Branch Updater

A comprehensive PowerShell script suite for updating all .NET projects across every branch in a Git repository to .NET 8.0 and C# 12, while ensuring JetBrains IDE files are properly ignored.

## 📁 Files Included

| File | Description |
|------|-------------|
| `Update-DotNetProjectsAllBranches.ps1` | Main script that performs the multi-branch .NET project updates |
| `UPDATE-DOTNET-PROJECTS-GUIDE.md` | Comprehensive documentation and usage guide |
| `Example-UpdateDotNetProjects.ps1` | Example usage scenarios and batch processing examples |
| `README-UpdateDotNetProjects.md` | This overview file |

## 🚀 Quick Start

### 1. Set Up Authentication
```powershell
# Set your GitHub Personal Access Token
$env:GIT_PAT = "your_github_personal_access_token_here"
```

### 2. Basic Usage
```powershell
# Update all .NET projects in the current repository
.\Update-DotNetProjectsAllBranches.ps1 -RepositoryPath "."

# Preview changes without applying them
.\Update-DotNetProjectsAllBranches.ps1 -RepositoryPath "." -DryRun
```

## ✨ Key Features

- **🌿 Multi-Branch Processing**: Automatically processes all branches in the repository
- **🔍 Smart Discovery**: Finds all .NET project files (*.csproj, *.vbproj, *.fsproj)
- **🛡️ Safe Updates**: Validates XML structure before making changes
- **📁 GitIgnore Management**: Automatically adds .idea/ to .gitignore for JetBrains IDEs
- **📝 Git Integration**: Commits and pushes changes with descriptive messages
- **🔐 Secure**: Uses environment variables for Git credentials
- **🎯 Selective Processing**: Skips branches without .NET projects
- **📊 Detailed Reporting**: Comprehensive progress feedback and summary reports
- **🔍 Dry Run Support**: Preview all changes before applying them

## 🎯 What It Updates

For each .NET project file found:
- **Target Framework**: Updates to `net8.0`
- **C# Language Version**: Updates to `12` (for C# projects)
- **Preserves**: All other project settings and structure

For each branch processed:
- **GitIgnore**: Adds `.idea/` entry to exclude JetBrains IDE files
- **Preserves**: All existing .gitignore content

### Example Transformation
```xml
<!-- Before -->
<Project Sdk="Microsoft.NET.Sdk">
  <PropertyGroup>
    <TargetFramework>net6.0</TargetFramework>
    <LangVersion>10</LangVersion>
  </PropertyGroup>
</Project>

<!-- After -->
<Project Sdk="Microsoft.NET.Sdk">
  <PropertyGroup>
    <TargetFramework>net8.0</TargetFramework>
    <LangVersion>12</LangVersion>
  </PropertyGroup>
</Project>
```

## 📋 Prerequisites

- **PowerShell 5.1+**
- **Git** (installed and in PATH)
- **.NET SDK** (any version for validation)
- **GitHub Personal Access Token** (for pushing changes)

## 🔧 Parameters

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `RepositoryPath` | String | ✅ Yes | Path to the Git repository to process |
| `DryRun` | Switch | ❌ No | Preview changes without applying them |
| `SkipPush` | Switch | ❌ No | Skip pushing changes to remote repository |

## 📖 Usage Examples

### Basic Operations
```powershell
# Process current repository
.\Update-DotNetProjectsAllBranches.ps1 -RepositoryPath "."

# Process specific repository
.\Update-DotNetProjectsAllBranches.ps1 -RepositoryPath "C:\repos\my-project"

# Dry run (preview only)
.\Update-DotNetProjectsAllBranches.ps1 -RepositoryPath "." -DryRun

# Update locally but don't push
.\Update-DotNetProjectsAllBranches.ps1 -RepositoryPath "." -SkipPush
```

### Batch Processing
```powershell
# Process multiple repositories
$repos = @("C:\repos\proj1", "C:\repos\proj2", "C:\repos\proj3")
foreach ($repo in $repos) {
    .\Update-DotNetProjectsAllBranches.ps1 -RepositoryPath $repo
}
```

## 📊 Output and Reporting

The script provides detailed feedback including:
- Branch discovery and processing status
- Project files found and updated per branch
- Git operation results (commit/push status)
- Comprehensive summary report with:
  - Successfully processed branches
  - Skipped branches (no changes needed)
  - Failed branches (with error details)
  - Total project files updated

## 🛡️ Safety Features

- **XML Validation**: Ensures project files are valid before modification
- **Git Safety**: Uses Git's version control as backup mechanism
- **Branch Restoration**: Returns to original branch after processing
- **Error Isolation**: Continues processing other branches if one fails
- **Dry Run Mode**: Preview all changes before applying them

## 🔍 Error Handling

The script gracefully handles:
- Branches without .NET projects (skipped, not errors)
- Invalid XML in project files (skipped with warning)
- Git operation failures (reported but doesn't stop processing)
- Authentication issues (clear error messages)
- Repository access problems (validation before processing)

## 📚 Documentation

For detailed information, see:
- **`UPDATE-DOTNET-PROJECTS-GUIDE.md`**: Complete usage guide with troubleshooting
- **`Example-UpdateDotNetProjects.ps1`**: Practical usage examples and scenarios

## 🔗 Integration

This script complements other repository enhancement tools:
- Use before `Enhance-DotNetRepository.ps1` for comprehensive modernization
- Integrate with CI/CD pipeline updates
- Coordinate with team for large-scale repository changes

## ⚠️ Important Notes

1. **Always test first**: Use `-DryRun` on a test repository
2. **Backup critical repositories**: Although Git provides version control, consider additional backups
3. **Review changes**: Check updated project files manually for correctness
4. **Monitor CI/CD**: Ensure build pipelines support .NET 8.0 before running
5. **Team coordination**: Communicate with team members for large-scale changes

## 🤝 Contributing

This script follows the established PowerShell patterns in the repository:
- Streamlined scripts with minimal required parameters
- Hard-coded organizational constants where appropriate
- Secure environment variable handling for credentials
- Comprehensive error handling and user feedback
