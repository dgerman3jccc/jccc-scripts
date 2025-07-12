# Determine the solution or project file
$slnFile = (Get-ChildItem -Path . -Filter *.sln -ErrorAction SilentlyContinue | Select-Object -First 1).Name

# Get all .csproj files but exclude those with "test" in their name (case-insensitive)
$csprojFiles = Get-ChildItem -Path . -Filter *.csproj -ErrorAction SilentlyContinue | 
    Where-Object { $_.Name -notmatch "test" } | 
    Select-Object -First 1

$csprojFile = $csprojFiles.Name

$fileToUse = ""
if ($slnFile) {
    $fileToUse = $slnFile
} elseif ($csprojFile) {
    $fileToUse = $csprojFile
}

if (-not [string]::IsNullOrEmpty($fileToUse)) {
    # Prompt for the NuGet package name
    $packageName = Read-Host "Enter the NuGet package name"

    if (-not [string]::IsNullOrWhiteSpace($packageName)) {
        # Construct and execute the command
        $commandToRun = "dotnet nuget why ""$fileToUse"" ""$packageName"""
        Write-Host "Running command: $commandToRun"
        Invoke-Expression $commandToRun
    } else {
        Write-Error "No package name entered. Aborting."
    }
} else {
    Write-Error "No .sln or non-test .csproj file found in the current directory."
}