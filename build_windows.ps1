# build_windows.ps1 - Build script for agbcc on Windows with xmake and MinGW
# Usage: .\build_windows.ps1

$ErrorActionPreference = "Continue"

$projectDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$gccDir = Join-Path $projectDir "gcc"
$genDir = Join-Path $projectDir "build\generators"

Write-Host "=== AGBCC Windows Build Script ===" -ForegroundColor Cyan
Write-Host "Project directory: $projectDir"
Write-Host ""

# Configure xmake for MinGW
Write-Host "Configuring xmake for MinGW..." -ForegroundColor Yellow
Push-Location $projectDir
xmake config -p mingw -m release -y 2>$null
if ($LASTEXITCODE -ne 0) { 
    Write-Host "Configuration failed" -ForegroundColor Red
    exit 1 
}

# Step 1: Build initial generators (no dependencies on generated files)
Write-Host ""
Write-Host "Step 1: Building initial code generators..." -ForegroundColor Yellow

xmake build gengenrtl 2>$null
xmake build gencheck 2>$null

# Step 2: Generate genrtl.h and genrtl.c first (needed by other generators)
Write-Host ""
Write-Host "Step 2: Generating genrtl.h and genrtl.c..." -ForegroundColor Yellow

$mdFile = Join-Path $gccDir "thumb.md"
$gengenrtl = Join-Path $genDir "gengenrtl.exe"
& $gengenrtl (Join-Path $gccDir "genrtl.h") (Join-Path $gccDir "genrtl.c")

# Generate tree-check.h
Write-Host "  Generating tree-check.h..."
$gencheck = Join-Path $genDir "gencheck.exe"
& $gencheck | Out-File -FilePath (Join-Path $gccDir "tree-check.h") -Encoding ascii

# Step 3: Build generators that need genrtl.h
Write-Host ""
Write-Host "Step 3: Building generators that need genrtl.h..." -ForegroundColor Yellow

$generators = @("genconfig", "genflags", "gencodes", "genattr", "genemit", "genrecog", "genopinit", "genpeep", "genoutput")
foreach ($gen in $generators) {
    Write-Host "  Building $gen..."
    xmake build $gen 2>$null
}

# Step 4: Generate header files needed by genextract and genattrtab
Write-Host ""
Write-Host "Step 4: Generating insn header files..." -ForegroundColor Yellow

$headerGenerators = @(
    @{name="genconfig"; output="insn-config.h"},
    @{name="genflags"; output="insn-flags.h"},
    @{name="gencodes"; output="insn-codes.h"},
    @{name="genattr"; output="insn-attr.h"}
)

foreach ($gen in $headerGenerators) {
    Write-Host "  Generating $($gen.output)..."
    $genPath = Join-Path $genDir "$($gen.name).exe"
    $outputPath = Join-Path $gccDir $gen.output
    & $genPath $mdFile | Out-File -FilePath $outputPath -Encoding ascii
}

# Step 5: Build genextract and genattrtab (they need insn-config.h)
Write-Host ""
Write-Host "Step 5: Building genextract and genattrtab..." -ForegroundColor Yellow
xmake build genextract 2>$null
xmake build genattrtab 2>$null

# Step 6: Generate all source files
Write-Host ""
Write-Host "Step 6: Generating insn source files..." -ForegroundColor Yellow

$sourceGenerators = @(
    @{name="genemit"; output="insn-emit.c"},
    @{name="genrecog"; output="insn-recog.c"},
    @{name="genopinit"; output="insn-opinit.c"},
    @{name="genextract"; output="insn-extract.c"},
    @{name="genpeep"; output="insn-peep.c"},
    @{name="genattrtab"; output="insn-attrtab.c"},
    @{name="genoutput"; output="insn-output.c"}
)

foreach ($gen in $sourceGenerators) {
    Write-Host "  Generating $($gen.output)..."
    $genPath = Join-Path $genDir "$($gen.name).exe"
    $outputPath = Join-Path $gccDir $gen.output
    # Redirect stderr to null and only capture stdout
    $result = & $genPath $mdFile 2>$null
    $result | Out-File -FilePath $outputPath -Encoding ascii
}

# Step 7: Build main compilers
Write-Host ""
Write-Host "Step 7: Building agbcc..." -ForegroundColor Yellow
xmake build agbcc
if ($LASTEXITCODE -ne 0) { 
    Write-Host "Failed to build agbcc" -ForegroundColor Red
    exit 1 
}

Write-Host ""
Write-Host "Step 8: Building old_agbcc..." -ForegroundColor Yellow
xmake build old_agbcc
if ($LASTEXITCODE -ne 0) { 
    Write-Host "Failed to build old_agbcc" -ForegroundColor Red
    exit 1 
}

Pop-Location

Write-Host ""
Write-Host "=== Build Complete ===" -ForegroundColor Green
Write-Host "Output files:"
Write-Host "  - agbcc.exe"
Write-Host "  - old_agbcc.exe"
