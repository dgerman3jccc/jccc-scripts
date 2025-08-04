<#
.SYNOPSIS
    Example usage scenarios for the .NET Repository Enhancement Protocol

.DESCRIPTION
    This script demonstrates various ways to use the Enhance-DotNetRepository.ps1 script
    for different scenarios and repository types.
#>

# Example 1: Basic enhancement of current directory
Write-Host "Example 1: Basic Enhancement" -ForegroundColor Cyan
Write-Host "Enhance-DotNetRepository.ps1 -RepositoryPath '.'"
Write-Host ""

# Example 2: Dry run to preview changes
Write-Host "Example 2: Dry Run (Preview Mode)" -ForegroundColor Cyan
Write-Host "Enhance-DotNetRepository.ps1 -RepositoryPath '.' -DryRun"
Write-Host ""

# Example 3: Enhancement with custom default branch
Write-Host "Example 3: Custom Default Branch" -ForegroundColor Cyan
Write-Host "Enhance-DotNetRepository.ps1 -RepositoryPath '.' -DefaultBranch 'main'"
Write-Host ""

# Example 4: Skip branch synchronization for faster execution
Write-Host "Example 4: Skip Branch Synchronization" -ForegroundColor Cyan
Write-Host "Enhance-DotNetRepository.ps1 -RepositoryPath '.' -SkipBranchSync"
Write-Host ""

# Example 5: Custom backup location
Write-Host "Example 5: Custom Backup Location" -ForegroundColor Cyan
Write-Host "Enhance-DotNetRepository.ps1 -RepositoryPath '.' -BackupPath 'C:\Backups\MyProject'"
Write-Host ""

# Example 6: Enhance multiple repositories in batch
Write-Host "Example 6: Batch Enhancement" -ForegroundColor Cyan
Write-Host @"
`$repositories = @(
    'C:\repos\project1',
    'C:\repos\project2',
    'C:\repos\project3'
)

foreach (`$repo in `$repositories) {
    Write-Host "Enhancing: `$repo"
    Enhance-DotNetRepository.ps1 -RepositoryPath `$repo
}
"@
Write-Host ""

# Example 7: Rollback scenario
Write-Host "Example 7: Rollback Changes" -ForegroundColor Cyan
Write-Host "Rollback-DotNetEnhancement.ps1 -BackupPath '.\backup-20241203-143022'"
Write-Host ""

# Interactive example
Write-Host "Interactive Example" -ForegroundColor Green
Write-Host "==================" -ForegroundColor Green
Write-Host ""

$choice = Read-Host @"
Choose an example to run:
1. Dry run on current directory
2. Full enhancement on current directory
3. Show help for enhancement script
4. Show help for rollback script
5. Exit

Enter your choice (1-5)
"@

switch ($choice) {
    "1" {
        Write-Host "Running dry run..." -ForegroundColor Yellow
        Enhance-DotNetRepository.ps1 -RepositoryPath "." -DryRun
    }
    "2" {
        Write-Host "Running full enhancement..." -ForegroundColor Yellow
        $confirm = Read-Host "This will modify your repository. Continue? (y/N)"
        if ($confirm -eq 'y' -or $confirm -eq 'Y') {
            Enhance-DotNetRepository.ps1 -RepositoryPath "."
        } else {
            Write-Host "Enhancement cancelled." -ForegroundColor Yellow
        }
    }
    "3" {
        Get-Help Enhance-DotNetRepository.ps1 -Full
    }
    "4" {
        Get-Help Rollback-DotNetEnhancement.ps1 -Full
    }
    "5" {
        Write-Host "Goodbye!" -ForegroundColor Green
    }
    default {
        Write-Host "Invalid choice. Please run the script again." -ForegroundColor Red
    }
}

# Advanced batch processing example
function Invoke-BatchEnhancement {
    param(
        [string[]]$RepositoryPaths,
        [switch]$DryRun,
        [switch]$SkipBranchSync
    )
    
    $results = @()
    
    foreach ($repo in $RepositoryPaths) {
        Write-Host "`nProcessing: $repo" -ForegroundColor Cyan
        
        try {
            $params = @{
                RepositoryPath = $repo
            }
            
            if ($DryRun) { $params.DryRun = $true }
            if ($SkipBranchSync) { $params.SkipBranchSync = $true }
            
            & Enhance-DotNetRepository.ps1 @params
            
            $results += [PSCustomObject]@{
                Repository = $repo
                Status = "Success"
                Error = $null
            }
        }
        catch {
            $results += [PSCustomObject]@{
                Repository = $repo
                Status = "Failed"
                Error = $_.Exception.Message
            }
            Write-Host "Failed to enhance $repo`: $_" -ForegroundColor Red
        }
    }
    
    # Summary report
    Write-Host "`nBatch Enhancement Summary" -ForegroundColor Green
    Write-Host "=========================" -ForegroundColor Green
    $results | Format-Table -AutoSize
    
    $successCount = ($results | Where-Object { $_.Status -eq "Success" }).Count
    $failCount = ($results | Where-Object { $_.Status -eq "Failed" }).Count
    
    Write-Host "Total: $($results.Count) repositories" -ForegroundColor White
    Write-Host "Successful: $successCount" -ForegroundColor Green
    Write-Host "Failed: $failCount" -ForegroundColor Red
}

# Example usage of batch function:
# $repos = @("C:\repos\proj1", "C:\repos\proj2", "C:\repos\proj3")
# Invoke-BatchEnhancement -RepositoryPaths $repos -DryRun
