# install_windows.ps1 - Install script for agbcc on Windows
# Usage: .\install_windows.ps1 <target_directory>
# Example: .\install_windows.ps1 ..\pokeemerald

param(
    [Parameter(Position=0)]
    [string]$TargetDir
)

$ErrorActionPreference = "Stop"

if ([string]::IsNullOrEmpty($TargetDir)) {
    Write-Host "Usage: .\install_windows.ps1 <target_directory>" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "Example: .\install_windows.ps1 ..\pokeemerald"
    Write-Host "         .\install_windows.ps1 C:\Projects\pokeemerald"
    exit 1
}

# Resolve the target directory path
$TargetPath = $TargetDir
if (-not [System.IO.Path]::IsPathRooted($TargetDir)) {
    $TargetPath = Join-Path $PSScriptRoot $TargetDir
}
$TargetPath = [System.IO.Path]::GetFullPath($TargetPath)

# Check if target directory exists
if (-not (Test-Path $TargetPath -PathType Container)) {
    Write-Host "Error: Target directory does not exist: $TargetPath" -ForegroundColor Red
    Write-Host ""
    
    # Try to give helpful suggestions
    $ParentPath = Join-Path $PSScriptRoot "..\$TargetDir"
    if (Test-Path $ParentPath -PathType Container) {
        Write-Host "Did you mean: .\install_windows.ps1 ..\$TargetDir" -ForegroundColor Yellow
    } else {
        Write-Host "Make sure the target repository has been cloned and the path is correct."
    }
    exit 1
}

$ScriptDir = $PSScriptRoot

# Check if required files exist
$RequiredFiles = @("agbcc.exe", "old_agbcc.exe")
$OptionalFiles = @("agbcc_arm.exe", "libgcc.a", "libc.a")

foreach ($file in $RequiredFiles) {
    $filePath = Join-Path $ScriptDir $file
    if (-not (Test-Path $filePath)) {
        Write-Host "Error: Required file not found: $file" -ForegroundColor Red
        Write-Host "Please run .\build_windows.ps1 first to build the compiler." -ForegroundColor Yellow
        exit 1
    }
}

Write-Host "=== Installing agbcc ===" -ForegroundColor Cyan
Write-Host "Target: $TargetPath"
Write-Host ""

# Create directories
$ToolsDir = Join-Path $TargetPath "tools\agbcc"
$BinDir = Join-Path $ToolsDir "bin"
$IncludeDir = Join-Path $ToolsDir "include"
$LibDir = Join-Path $ToolsDir "lib"

Write-Host "Creating directories..." -ForegroundColor Yellow
New-Item -ItemType Directory -Path $BinDir -Force | Out-Null
New-Item -ItemType Directory -Path $IncludeDir -Force | Out-Null
New-Item -ItemType Directory -Path $LibDir -Force | Out-Null

# Copy executables
Write-Host "Copying executables..." -ForegroundColor Yellow
Copy-Item (Join-Path $ScriptDir "agbcc.exe") $BinDir -Force
Copy-Item (Join-Path $ScriptDir "old_agbcc.exe") $BinDir -Force

# Copy agbcc_arm if it exists
$AgbccArm = Join-Path $ScriptDir "agbcc_arm.exe"
if (Test-Path $AgbccArm) {
    Copy-Item $AgbccArm $BinDir -Force
    Write-Host "  - agbcc_arm.exe" -ForegroundColor Gray
}

Write-Host "  - agbcc.exe" -ForegroundColor Gray
Write-Host "  - old_agbcc.exe" -ForegroundColor Gray

# Copy include files
Write-Host "Copying include files..." -ForegroundColor Yellow

# Copy libc includes
$LibcInclude = Join-Path $ScriptDir "libc\include"
if (Test-Path $LibcInclude) {
    Get-ChildItem $LibcInclude -Recurse | ForEach-Object {
        $relativePath = $_.FullName.Substring($LibcInclude.Length + 1)
        $destPath = Join-Path $IncludeDir $relativePath
        if ($_.PSIsContainer) {
            New-Item -ItemType Directory -Path $destPath -Force | Out-Null
        } else {
            $destDir = Split-Path $destPath -Parent
            if (-not (Test-Path $destDir)) {
                New-Item -ItemType Directory -Path $destDir -Force | Out-Null
            }
            Copy-Item $_.FullName $destPath -Force
        }
    }
    Write-Host "  - libc/include/*" -ForegroundColor Gray
}

# Copy ginclude files
$GInclude = Join-Path $ScriptDir "ginclude"
if (Test-Path $GInclude) {
    Get-ChildItem $GInclude -File | ForEach-Object {
        Copy-Item $_.FullName $IncludeDir -Force
    }
    Write-Host "  - ginclude/*" -ForegroundColor Gray
}

# Copy libraries
Write-Host "Copying libraries..." -ForegroundColor Yellow

$MissingLibs = @()

$LibGcc = Join-Path $ScriptDir "libgcc.a"
if (Test-Path $LibGcc) {
    Copy-Item $LibGcc $LibDir -Force
    Write-Host "  - libgcc.a" -ForegroundColor Gray
} else {
    $MissingLibs += "libgcc.a"
}

$LibC = Join-Path $ScriptDir "libc.a"
if (Test-Path $LibC) {
    Copy-Item $LibC $LibDir -Force
    Write-Host "  - libc.a" -ForegroundColor Gray
} else {
    $MissingLibs += "libc.a"
}

Write-Host ""
Write-Host "=== agbcc successfully installed! ===" -ForegroundColor Green
Write-Host ""
Write-Host "Installed to: $ToolsDir"
Write-Host ""
Write-Host "Contents:"
Write-Host "  bin/      - Compiler executables"
Write-Host "  include/  - Header files"
Write-Host "  lib/      - Static libraries"

if ($MissingLibs.Count -gt 0) {
    Write-Host ""
    Write-Host "WARNING: The following libraries were not found and were not installed:" -ForegroundColor Yellow
    foreach ($lib in $MissingLibs) {
        Write-Host "  - $lib" -ForegroundColor Yellow
    }
    Write-Host ""
    Write-Host "To build these libraries, you need arm-none-eabi toolchain (devkitARM or binutils-arm-none-eabi)."
    Write-Host "Run: .\build_libs_windows.ps1"
}
