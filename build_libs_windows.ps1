# build_libs_windows.ps1 - Build libgcc.a and libc.a on Windows
# Requires: arm-none-eabi toolchain (devkitARM or binutils-arm-none-eabi)
# Usage: .\build_libs_windows.ps1

$ErrorActionPreference = "Stop"

$projectDir = Split-Path -Parent $MyInvocation.MyCommand.Path

Write-Host "=== Building agbcc libraries ===" -ForegroundColor Cyan
Write-Host ""

# Check for ARM toolchain
$armAs = $null
$armAr = $null
$armCpp = $null

# Check devkitARM first
if ($env:DEVKITARM -and (Test-Path "$env:DEVKITARM\bin")) {
    $armAs = Join-Path $env:DEVKITARM "bin\arm-none-eabi-as.exe"
    $armAr = Join-Path $env:DEVKITARM "bin\arm-none-eabi-ar.exe"
    $armCpp = Join-Path $env:DEVKITARM "bin\arm-none-eabi-cpp.exe"
    Write-Host "Using devkitARM from: $env:DEVKITARM" -ForegroundColor Green
}

# Check for arm-none-eabi in PATH
if (-not $armAs -or -not (Test-Path $armAs)) {
    $armAs = Get-Command "arm-none-eabi-as.exe" -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Source
    $armAr = Get-Command "arm-none-eabi-ar.exe" -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Source
    $armCpp = Get-Command "arm-none-eabi-cpp.exe" -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Source
    
    if ($armAs) {
        Write-Host "Using arm-none-eabi from PATH" -ForegroundColor Green
    }
}

# Check for cpp (use gcc's cpp if arm-none-eabi-cpp not found)
if (-not $armCpp -or -not (Test-Path $armCpp)) {
    $armCpp = Get-Command "cpp.exe" -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Source
    if (-not $armCpp) {
        $armCpp = Get-Command "gcc.exe" -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Source
        if ($armCpp) {
            # Use gcc -E instead of cpp
            $useGccE = $true
        }
    }
}

if (-not $armAs -or -not (Test-Path $armAs)) {
    Write-Host "ERROR: arm-none-eabi-as not found!" -ForegroundColor Red
    Write-Host ""
    Write-Host "Please install one of the following:"
    Write-Host "  - devkitARM (https://devkitpro.org/)"
    Write-Host "  - ARM GNU Toolchain (https://developer.arm.com/tools-and-software/open-source-software/developer-tools/gnu-toolchain)"
    Write-Host ""
    Write-Host "Make sure the bin directory is in your PATH or DEVKITARM environment variable is set."
    exit 1
}

if (-not $armAr -or -not (Test-Path $armAr)) {
    Write-Host "ERROR: arm-none-eabi-ar not found!" -ForegroundColor Red
    exit 1
}

Write-Host "  AS:  $armAs"
Write-Host "  AR:  $armAr"
Write-Host "  CPP: $armCpp"
Write-Host ""

# Check for old_agbcc
$oldAgbcc = Join-Path $projectDir "old_agbcc.exe"
if (-not (Test-Path $oldAgbcc)) {
    Write-Host "ERROR: old_agbcc.exe not found!" -ForegroundColor Red
    Write-Host "Please run .\build_windows.ps1 first."
    exit 1
}

# ============================================================================
# Build libgcc.a
# ============================================================================

Write-Host "Building libgcc.a..." -ForegroundColor Yellow
Push-Location (Join-Path $projectDir "libgcc")

# Clean
Remove-Item -Force *.o, *.a, *.s, *.i -ErrorAction SilentlyContinue

# Generate fp-bit.c and dp-bit.c
Write-Host "  Generating fp-bit.c and dp-bit.c..."
"#define FLOAT`n#define FLOAT_BIT_ORDER_MISMATCH`n" + (Get-Content fp-bit-base.c -Raw) | Out-File -FilePath fp-bit.c -Encoding ascii
"#define FLOAT_BIT_ORDER_MISMATCH`n#define FLOAT_WORD_ORDER_MISMATCH`n" + (Get-Content fp-bit-base.c -Raw) | Out-File -FilePath dp-bit.c -Encoding ascii

# Build libgcc1.a from assembly
Write-Host "  Building libgcc1.a (assembly functions)..."
$lib1funcs = @("_udivsi3", "_divsi3", "_umodsi3", "_modsi3", "_dvmd_tls", "_call_via_rX")

foreach ($func in $lib1funcs) {
    Write-Host "    $func" -ForegroundColor Gray
    
    # Preprocess
    if ($useGccE) {
        & $armCpp -E -undef -nostdinc "-DL$func" -x assembler-with-cpp -o "$func.s" lib1thumb.asm 2>$null
    } else {
        & $armCpp -undef -nostdinc "-DL$func" -x assembler-with-cpp -o "$func.s" lib1thumb.asm 2>$null
    }
    
    # Add alignment
    "`n.text`n`t.align`t2, 0`n" | Out-File -FilePath "$func.s" -Append -Encoding ascii
    
    # Assemble
    & $armAs -mcpu=arm7tdmi -o "$func.o" "$func.s"
    
    # Add to archive
    & $armAr -rc libgcc1.a "$func.o"
    
    Remove-Item "$func.s", "$func.o" -ErrorAction SilentlyContinue
}

# Build libgcc2.a from C
Write-Host "  Building libgcc2.a (C functions)..."
$lib2funcs = @(
    "_muldi3", "_divdi3", "_moddi3", "_udivdi3", "_umoddi3", "_negdi2",
    "_lshrdi3", "_ashldi3", "_ashrdi3", "_ffsdi2",
    "_udiv_w_sdiv", "_udivmoddi4", "_cmpdi2", "_ucmpdi2", "_floatdidf", "_floatdisf",
    "_fixunsdfsi", "_fixunssfsi", "_fixunsdfdi", "_fixdfdi", "_fixunssfdi", "_fixsfdi"
)

foreach ($func in $lib2funcs) {
    Write-Host "    $func" -ForegroundColor Gray
    
    # Preprocess
    if ($useGccE) {
        & $armCpp -E -undef -I ..\ginclude -nostdinc "-DL$func" -o "$func.i" libgcc2.c 2>$null
    } else {
        & $armCpp -undef -I ..\ginclude -nostdinc "-DL$func" -o "$func.i" libgcc2.c 2>$null
    }
    
    # Compile with old_agbcc
    & $oldAgbcc -O2 "$func.i" 2>$null
    
    # Add alignment
    "`n.text`n`t.align`t2, 0`n" | Out-File -FilePath "$func.s" -Append -Encoding ascii
    
    # Assemble
    & $armAs -mcpu=arm7tdmi -o "$func.o" "$func.s"
    
    # Add to archive
    & $armAr -rc libgcc2.a "$func.o"
    
    Remove-Item "$func.i", "$func.s", "$func.o" -ErrorAction SilentlyContinue
}

# Build fp-bit.o
Write-Host "  Building fp-bit.o..."
if ($useGccE) {
    & $armCpp -E -undef -I ..\ginclude -nostdinc -o fp-bit.i fp-bit.c 2>$null
} else {
    & $armCpp -undef -I ..\ginclude -nostdinc -o fp-bit.i fp-bit.c 2>$null
}
& $oldAgbcc -O2 fp-bit.i 2>$null
"`n.text`n`t.align`t2, 0`n" | Out-File -FilePath fp-bit.s -Append -Encoding ascii
& $armAs -mcpu=arm7tdmi -o fp-bit.o fp-bit.s
Remove-Item fp-bit.i, fp-bit.s -ErrorAction SilentlyContinue

# Build dp-bit.o
Write-Host "  Building dp-bit.o..."
if ($useGccE) {
    & $armCpp -E -undef -I ..\ginclude -nostdinc -o dp-bit.i dp-bit.c 2>$null
} else {
    & $armCpp -undef -I ..\ginclude -nostdinc -o dp-bit.i dp-bit.c 2>$null
}
& $oldAgbcc -O2 dp-bit.i 2>$null
"`n.text`n`t.align`t2, 0`n" | Out-File -FilePath dp-bit.s -Append -Encoding ascii
& $armAs -mcpu=arm7tdmi -o dp-bit.o dp-bit.s
Remove-Item dp-bit.i, dp-bit.s -ErrorAction SilentlyContinue

# Combine into libgcc.a
Write-Host "  Combining into libgcc.a..."
& $armAr -x libgcc1.a
& $armAr -x libgcc2.a
& $armAr -rc libgcc.a (Get-ChildItem *.o).Name

# Copy to project root
Copy-Item libgcc.a $projectDir -Force

# Clean up
Remove-Item *.o, libgcc1.a, libgcc2.a, fp-bit.c, dp-bit.c -ErrorAction SilentlyContinue

Pop-Location
Write-Host "  libgcc.a built successfully!" -ForegroundColor Green

# ============================================================================
# Build libc.a
# ============================================================================

Write-Host ""
Write-Host "Building libc.a..." -ForegroundColor Yellow
Push-Location (Join-Path $projectDir "libc")

# Clean
Get-ChildItem -Recurse -Include *.o, *.i, *.s | Remove-Item -Force -ErrorAction SilentlyContinue
Remove-Item libc.a -Force -ErrorAction SilentlyContinue

$cppFlags = "-I ..\ginclude -I include -nostdinc -undef -DABORT_PROVIDED -DHAVE_GETTIMEOFDAY -D__thumb__ -DARM_RDI_MONITOR -D__GNUC__ -DINTERNAL_NEWLIB -D__USER_LABEL_PREFIX__="
$asFlags = "-mcpu=arm7tdmi"
$cc1Flags = "-O2 -fno-builtin"

# Find all C source files
$cSources = Get-ChildItem -Recurse -Filter "*.c" | Where-Object { $_.Name -ne "mallocr.c" }

Write-Host "  Compiling C sources..."
foreach ($src in $cSources) {
    $relativePath = $src.FullName.Substring((Get-Location).Path.Length + 1)
    $baseName = $src.BaseName
    $dir = $src.DirectoryName
    $iFile = Join-Path $dir "$baseName.i"
    $sFile = Join-Path $dir "$baseName.s"
    $oFile = Join-Path $dir "$baseName.o"
    
    Write-Host "    $relativePath" -ForegroundColor Gray
    
    # Preprocess
    $cppArgs = $cppFlags -split ' '
    if ($useGccE) {
        & $armCpp -E @cppArgs $src.FullName -o $iFile 2>$null
    } else {
        & $armCpp @cppArgs $src.FullName -o $iFile 2>$null
    }
    
    # Compile
    & $oldAgbcc -O2 -fno-builtin $iFile 2>$null
    
    # Add alignment
    "`n.text`n`t.align`t2, 0`n" | Out-File -FilePath $sFile -Append -Encoding ascii
    
    # Assemble
    & $armAs $asFlags -o $oFile $sFile
    
    Remove-Item $iFile, $sFile -Force -ErrorAction SilentlyContinue
}

# Build malloc variants from mallocr.c
Write-Host "  Compiling malloc variants..."
$mallocVariants = @(
    @{name="mallocr"; define="DEFINE_MALLOC"},
    @{name="freer"; define="DEFINE_FREE"},
    @{name="reallocr"; define="DEFINE_REALLOC"},
    @{name="callocr"; define="DEFINE_CALLOC"},
    @{name="cfreer"; define="DEFINE_CFREE"},
    @{name="malignr"; define="DEFINE_MEMALIGN"},
    @{name="vallocr"; define="DEFINE_VALLOC"},
    @{name="pvallocr"; define="DEFINE_PVALLOC"},
    @{name="mallinfor"; define="DEFINE_MALLINFO"},
    @{name="mallstatsr"; define="DEFINE_MALLOC_STATS"},
    @{name="msizer"; define="DEFINE_MALLOC_USABLE_SIZE"},
    @{name="malloptr"; define="DEFINE_MALLOPT"}
)

foreach ($variant in $mallocVariants) {
    $name = $variant.name
    $define = $variant.define
    Write-Host "    stdlib/$name.o" -ForegroundColor Gray
    
    $iFile = "stdlib\$name.i"
    $sFile = "stdlib\$name.s"
    $oFile = "stdlib\$name.o"
    
    $cppArgs = $cppFlags -split ' '
    if ($useGccE) {
        & $armCpp -E @cppArgs "-D$define" stdlib\mallocr.c -o $iFile 2>$null
    } else {
        & $armCpp @cppArgs "-D$define" stdlib\mallocr.c -o $iFile 2>$null
    }
    
    & $oldAgbcc -O2 -fno-builtin $iFile 2>$null
    "`n.text`n`t.align`t2, 0`n" | Out-File -FilePath $sFile -Append -Encoding ascii
    & $armAs $asFlags -o $oFile $sFile
    
    Remove-Item $iFile, $sFile -Force -ErrorAction SilentlyContinue
}

# Build vfiprintf from vfprintf.c
Write-Host "    stdio/vfiprintf.o" -ForegroundColor Gray
$cppArgs = $cppFlags -split ' '
if ($useGccE) {
    & $armCpp -E @cppArgs "-DINTEGER_ONLY" stdio\vfprintf.c -o stdio\vfiprintf.i 2>$null
} else {
    & $armCpp @cppArgs "-DINTEGER_ONLY" stdio\vfprintf.c -o stdio\vfiprintf.i 2>$null
}
& $oldAgbcc -O2 -fno-builtin stdio\vfiprintf.i 2>$null
"`n.text`n`t.align`t2, 0`n" | Out-File -FilePath stdio\vfiprintf.s -Append -Encoding ascii
& $armAs $asFlags -o stdio\vfiprintf.o stdio\vfiprintf.s
Remove-Item stdio\vfiprintf.i, stdio\vfiprintf.s -Force -ErrorAction SilentlyContinue

# Build assembly sources
Write-Host "  Compiling assembly sources..."
$asmSources = @("arm\setjmp.s", "arm\trap.s")
foreach ($src in $asmSources) {
    if (Test-Path $src) {
        Write-Host "    $src" -ForegroundColor Gray
        $baseName = [System.IO.Path]::GetFileNameWithoutExtension($src)
        $dir = [System.IO.Path]::GetDirectoryName($src)
        $iFile = Join-Path $dir "$baseName.i"
        $oFile = Join-Path $dir "$baseName.o"
        
        $cppArgs = $cppFlags -split ' '
        if ($useGccE) {
            & $armCpp -E @cppArgs $src -o $iFile 2>$null
        } else {
            & $armCpp @cppArgs $src -o $iFile 2>$null
        }
        "`n.text`n`t.align`t2, 0`n" | Out-File -FilePath $iFile -Append -Encoding ascii
        & $armAs $asFlags -o $oFile $iFile
        
        Remove-Item $iFile -Force -ErrorAction SilentlyContinue
    }
}

# Create archive
Write-Host "  Creating libc.a..."
$allObjs = Get-ChildItem -Recurse -Filter "*.o"
& $armAr -rc libc.a $allObjs.FullName

# Copy to project root
Copy-Item libc.a $projectDir -Force

# Clean up
Get-ChildItem -Recurse -Include *.o, *.i | Remove-Item -Force -ErrorAction SilentlyContinue

Pop-Location
Write-Host "  libc.a built successfully!" -ForegroundColor Green

Write-Host ""
Write-Host "=== Libraries built successfully! ===" -ForegroundColor Green
Write-Host ""
Write-Host "Output files:"
Write-Host "  - libgcc.a"
Write-Host "  - libc.a"
Write-Host ""
Write-Host "You can now run .\install_windows.ps1 to install agbcc with libraries."
