# ======================================================================
# HucOS Operating System Automated Build/Debug/Clean Script (Bochs 3.0 Built-in Debug Edition)
# Project Root: c:/os/sources/hucos
# Bochs Installation Directory: C:\applications\bochs\3.0
# Dependencies: NASM, Bochs 3.0, Windows DD Tool
# Author: huc0day(GaoJian)
# ======================================================================

# ------------------------------
# 1. Global Configuration (Modify According to Actual Situation)
# ------------------------------
$projectRoot = "c:/os/sources/hucos"          # Project Root Directory
$srcDir      = Join-Path $projectRoot "src"    # Source Code Directory (mbr/dbr/kernel.asm)
$buildDir    = Join-Path $projectRoot "build"  # Compilation Output Directory (mbr/dbr/kernel.bin)
$binDir      = Join-Path $projectRoot "bin"    # Image and Tool Directory (hucos.img)
$bakDir      = Join-Path $projectRoot "bak"    # Source Code Backup Directory
$logDir      = Join-Path $projectRoot "logs"   # Bochs Log Directory
$diskImg     = Join-Path $binDir "hucos.img"   # Final Virtual Disk Image

# Bochs-Specific Configuration
$bochsDir    = "C:/applications/bochs/3.0"        # Bochs Installation Directory
$bochsExe    = Join-Path $bochsDir "bochs.exe"    # Bochs Debug Version Executable
$bxcfgFile   = Join-Path $projectRoot "bxcfg.bxrc"# Auto-Generated Bochs Configuration File
$imageSizeMB = 4                                  # Virtual Disk Size (MB)
$biosDir     = $bochsDir                          # BIOS Files Located in Bochs Root Directory

# ------------------------------
# 2. Utility Function Library
# ------------------------------
#region Utility Functions

# Check if Dependent Tools Exist
function Check-Dependency {
    param([string]$Name, [string]$Path, [string]$Hint)
    if (-not (Get-Command $Path -ErrorAction SilentlyContinue)) {
        Write-Host "❌ Fatal Error: $Name Not Found!" -ForegroundColor Red
        Write-Host "! Solution: $Hint" -ForegroundColor Yellow
        exit 1
    }
}

# Safe Cleanup Confirmation
function Confirm-Cleanup {
    param([string]$Desc, [string]$Path)
    $item = Get-Item $Path -ErrorAction SilentlyContinue
    if (-not $item) {
        Write-Host "ℹ️ $Desc Does Not Exist: $Path" -ForegroundColor Yellow
        return $false
    }
    $choice = Read-Host "`nConfirm Cleanup of $Desc ($($item.FullName))? (Y/N)"
    return ($choice -in 'Y','y')
}

# Terminate Bochs Process
function Stop-Bochs {
    $procName = "bochs"  # Bochs Process Name
    $procs = Get-Process $procName -ErrorAction SilentlyContinue
    if ($procs) {
        $procs | ForEach-Object {
            try { Stop-Process $_.Id -Force -ErrorAction Stop }
            catch { Write-Host "❌ Failed to Terminate Bochs (PID $($_.Id)): $_" -ForegroundColor Red }
        }
        Write-Host "✅ All Bochs Processes Terminated!" -ForegroundColor Green
    } else {
        Write-Host "ℹ️ No Running Bochs Processes" -ForegroundColor Yellow
    }
}

# Verify if BIOS Files Exist
function Test-BiosFiles {
    $biosFile1 = Join-Path $biosDir "BIOS-bochs-latest"
    $biosFile2 = Join-Path $biosDir "VGABIOS-lgpl-latest.bin"
    $biosFiles = @($biosFile1, $biosFile2)
    foreach ($file in $biosFiles) {
        if (-not (Test-Path $file -PathType Leaf)) {
            Write-Host "❌ BIOS File Not Found: $file" -ForegroundColor Red
            Write-Host "! Please Ensure the File is Placed in $biosDir Directory" -ForegroundColor Yellow
            exit 1
        }
    }
    Write-Host "✅ BIOS Files Verified!" -ForegroundColor Green
}

#endregion

# ------------------------------
# 3. Initialize Environment
# ------------------------------
Write-Host "`n🚀 Step 1: Initialize Project Environment..." -ForegroundColor Green

# Backup Source Code
Write-Host "  💾 Backing Up Source Code to $bakDir..."
if (-not (Test-Path $bakDir)) { New-Item -ItemType Directory -Path $bakDir | Out-Null }
robocopy "$srcDir" "$bakDir" /MIR /NFL /NDL /NJH /NJS /nc /ns /np | Out-Null
if ($LASTEXITCODE -le 1) { Write-Host "✅ Source Code Backup Completed!" -ForegroundColor Green } 
else { Write-Host "❌ Source Code Backup Failed (Code: $LASTEXITCODE)" -ForegroundColor Red; exit 1 }

# Create Necessary Directories
$dirs = $buildDir, $logDir
$dirs | ForEach-Object {
    if (-not (Test-Path $_)) { 
        New-Item -ItemType Directory -Path $_ | Out-Null 
        Write-Host "✅ Directory Created: $_" -ForegroundColor Green 
    }
}

# Verify BIOS Files
Write-Host "  📋 Verifying BIOS Files..."
Test-BiosFiles

# Generate Bochs Configuration File (Based on Available Configuration)
Write-Host "  📝 Generating Bochs Configuration File: $bxcfgFile..."
$biosFile = (Join-Path $biosDir "BIOS-bochs-latest") -replace '/', '\'
$vgaBiosFile = (Join-Path $biosDir "VGABIOS-lgpl-latest.bin") -replace '/', '\'
$diskImgPath = $diskImg -replace '/', '\'
$logFilePath = (Join-Path $logDir "bochsout.txt") -replace '/', '\'

$bxcfgContent = @"
# ======================================================================
# Bochs 3.0 Configuration File (Dedicated to HucOS)
# Auto-Generated Time: $(Get-Date -Format "yyyy-MM-dd HH:mm:ss")
# Applicable System: HucOS Self-Developed Operating System
# ======================================================================

# ------------------------------
# Memory Configuration
# ------------------------------
megs: 4

# ------------------------------
# BIOS Image Path
# ------------------------------
romimage: file=$biosFile
vgaromimage: file=$vgaBiosFile

# ------------------------------
# Storage Device Configuration
# ------------------------------
ata0-master: type=disk, path="$diskImgPath", mode=flat
boot: disk

# ------------------------------
# Display and Input Configuration
# ------------------------------
display_library: win32
#mouse: enabled=1, mode=ps2
#keyboard: type=ps2, serial_delay=250

# ------------------------------
# Debug Configuration
# ------------------------------
debug: action=ignore
debugger_log: -
magic_break: enabled=1


# ------------------------------
# Serial and Log Configuration
# ------------------------------
serial: enabled=1, port=0x3f8, mode=file, dev="$logDir\bochs_serial.log"
log: file=$logFilePath
panic: action=report

# ------------------------------
# Other Optimization Configuration
# ------------------------------
ne2k: enabled=0
#usb: enabled=0
clock: sync=realtime, time0=local
"@

$bxcfgContent | Out-File -FilePath $bxcfgFile -Encoding ascii
if (Test-Path $bxcfgFile) { 
    Write-Host "✅ Bochs Configuration File Generated Successfully!" -ForegroundColor Green 
}
else { 
    Write-Host "❌ Bochs Configuration File Generation Failed: $bxcfgFile" -ForegroundColor Red 
    exit 1 
}

# ------------------------------
# 4. Check Development Dependencies
# ------------------------------
Write-Host "`n🔍 Step 2: Check Development Dependencies..." -ForegroundColor Green
Check-Dependency "NASM Assembler" "nasm.exe" "https://www.nasm.us/pub/nasm/releasebuilds/?C=M;O=D"
Check-Dependency "Bochs Debugger" $bochsExe "Please Install Bochs 3.0 to $bochsDir"
Check-Dependency "DD Disk Tool" "dd.exe" "http://www.chrysocome.net/dd/ (Need to Add to PATH)"

# ------------------------------
# 5. Compile Core Components (MBR/DBR/Kernel)
# ------------------------------
Write-Host "`n⚙️ Step 3: Compile Assembly Code..." -ForegroundColor Green

function Compile-Source {
    param([string]$Src, [string]$Out, [string]$Desc)
    Write-Host "  🔨 Compiling $Desc..."
    nasm -f bin $Src -o $Out
    if ($LASTEXITCODE -ne 0) {
        Write-Host "❌ Compilation of $Desc Failed!" -ForegroundColor Red
        exit 1
    }
    if (-not (Test-Path $Out)) {
        Write-Host "❌ $Desc Output File Not Generated: $Out" -ForegroundColor Red
        exit 1
    }
    Write-Host "✅ Generated: $Out ($(Get-Item $Out).Length Bytes)" -ForegroundColor Green
}

# Compile MBR, DBR, Kernel
Compile-Source "$srcDir/mbr.asm" "$buildDir/mbr.bin" "MBR"
Compile-Source "$srcDir/dbr.asm" "$buildDir/dbr.bin" "DBR"
Compile-Source "$srcDir/kernel.asm" "$buildDir/kernel.bin" "Kernel"

Write-Host "`n✅ All Components Compiled!" -ForegroundColor Green

# ------------------------------
# 6. Build Virtual Disk (hucos.img)
# ------------------------------
Write-Host "`n💿 Step 4: Build Operating System Image..." -ForegroundColor Green

# Create Blank RAW Image
Write-Host "  📦 Creating Virtual Disk: $diskImg ($imageSizeMB MB)..."
& "dd.exe" if=/dev/zero of="$diskImg" bs=1M count=$imageSizeMB status=progress
if (-not (Test-Path $diskImg)) { 
    Write-Host "❌ Image Creation Failed: $diskImg" -ForegroundColor Red
    exit 1 
}

# Write MBR to Sector 0
Write-Host "  ✍️ Writing MBR to Sector 0..."
& "dd.exe" if="$buildDir/mbr.bin" of="$diskImg" bs=512 count=1
if ($LASTEXITCODE -ne 0) { 
    Write-Host "❌ MBR Writing Failed!" -ForegroundColor Red
    exit 1 
}

# Write DBR to Sector 1
Write-Host "  ✍️ Writing DBR to Sector 1..."
& "dd.exe" if="$buildDir/dbr.bin" of="$diskImg" bs=512 count=1 seek=1
if ($LASTEXITCODE -ne 0) { 
    Write-Host "❌ DBR Writing Failed!" -ForegroundColor Red
    exit 1 
}

# Write Kernel to Sector 2 and Beyond
Write-Host "  ✍️ Writing Kernel to Sector 2..."
& "dd.exe" if="$buildDir/kernel.bin" of="$diskImg" bs=512 seek=2
if ($LASTEXITCODE -ne 0) { 
    Write-Host "❌ Kernel Writing Failed!" -ForegroundColor Red
    exit 1 
}

Write-Host "`n✅ Image Created Successfully: $diskImg" -ForegroundColor Green

# ------------------------------
# 7. Start Bochs Built-in Debug Environment
# ------------------------------
Write-Host "`n🔧 Step 5: Start Debug Environment..." -ForegroundColor Green

Write-Host "`n📌 Debug Tips:" -ForegroundColor Cyan
Write-Host "  - Bochs will automatically enter the debug interface upon startup (due to magic_break interrupting at 0x7c00)" -ForegroundColor Cyan
Write-Host "  - Common Commands: c (Continue), s (Step), b 0xXXXX (Set Breakpoint), r (View Registers), x /nwx 0xXXXX (View Memory)" -ForegroundColor Cyan

# Start Bochs
$bochsArgs = @("-dbg", "-q", "-f", $bxcfgFile)
Start-Process -FilePath $bochsExe -ArgumentList $bochsArgs -Wait -NoNewWindow

# ------------------------------
# 8. Cleanup and Exit
# ------------------------------
Write-Host "`n🧹 Step 6: Terminate Bochs Process..." -ForegroundColor Green
Stop-Bochs

Write-Host "`n🔚 Step 7: Choose an Operation:" -ForegroundColor Green
Write-Host "1. Cleanup Intermediate Compilation Files (Retain Image and Logs)"
Write-Host "2. Retain All Files"
Write-Host "3. Full Cleanup (Delete Image and Compilation Files)"
Write-Host "4. Exit"

$choice = Read-Host "Please Enter Option (1-4)"
switch ($choice) {
    "1" {
        Write-Host "`n🧹 Cleaning Up Compilation Directory..." -ForegroundColor Green
        if (Confirm-Cleanup "Compilation Directory" $buildDir) {
            Remove-Item $buildDir -Recurse -Force
            Write-Host "✅ Cleaned: $buildDir" -ForegroundColor Green
        }
        Write-Host "`n✅ Cleanup Completed, Retaining Image: $diskImg and Log Directory: $logDir" -ForegroundColor Green
    }
    "2" {
        Write-Host "`nℹ️ Retaining All Files" -ForegroundColor Yellow
    }
    "3" {
        Write-Host "`n🧹 Performing Full Cleanup..." -ForegroundColor Green
        if (Confirm-Cleanup "Compilation Directory" $buildDir) {
            Remove-Item $buildDir -Recurse -Force
            Write-Host "✅ Cleaned: $buildDir" -ForegroundColor Green
        }
        if (Confirm-Cleanup "Image File" $diskImg) {
            Remove-Item $diskImg -Force
            Write-Host "✅ Cleaned: $diskImg" -ForegroundColor Green
        }
        if (Confirm-Cleanup "Log Directory" $logDir) {
            Remove-Item $logDir -Recurse -Force
            Write-Host "✅ Cleaned: $logDir" -ForegroundColor Green
        }
        Write-Host "`n✅ Full Cleanup Completed" -ForegroundColor Green
    }
    "4" {
        Write-Host "`n👋 Exiting, Retaining All Files" -ForegroundColor Yellow
    }
    default {
        Write-Host "`n❌ Invalid Option, Retaining All Files" -ForegroundColor Yellow
    }
}

Write-Host "`n🎉 Operation Completed!" -ForegroundColor Green
