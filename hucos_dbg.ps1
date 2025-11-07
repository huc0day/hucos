# ======================================================================
# HucOS 操作系统自动化构建/调试/清理脚本（Bochs 3.0 内置调试版）
# 项目主目录：c:/os/sources/hucos
# Bochs 安装目录：C:\applications\bochs\3.0
# 依赖：NASM、Bochs 3.0、Windows DD 工具
# ======================================================================

# ------------------------------
# 1. 全局配置（根据实际情况修改）
# ------------------------------
$projectRoot = "c:/os/sources/hucos"          # 项目根目录
$srcDir      = Join-Path $projectRoot "src"    # 源码目录（mbr/dbr/kernel.asm）
$buildDir    = Join-Path $projectRoot "build"  # 编译输出目录（mbr/dbr/kernel.bin）
$binDir      = Join-Path $projectRoot "bin"    # 镜像与工具目录（hucos.img）
$bakDir      = Join-Path $projectRoot "bak"    # 源码备份目录
$logDir      = Join-Path $projectRoot "logs"   # Bochs 日志目录
$diskImg     = Join-Path $binDir "hucos.img"   # 最终虚拟磁盘镜像

# Bochs 专属配置
$bochsDir    = "C:/applications/bochs/3.0"        # Bochs 安装目录
$bochsExe    = Join-Path $bochsDir "bochs.exe"    # Bochs 调试版程序
$bxcfgFile   = Join-Path $projectRoot "bxcfg.bxrc"# 自动生成的 Bochs 配置文件
$imageSizeMB = 4                                  # 虚拟磁盘大小（MB）
$biosDir     = $bochsDir                          # BIOS 文件位于 Bochs 根目录

# ------------------------------
# 2. 辅助函数库
# ------------------------------
#region 工具函数

# 检查依赖工具是否存在
function Check-Dependency {
    param([string]$Name, [string]$Path, [string]$Hint)
    if (-not (Get-Command $Path -ErrorAction SilentlyContinue)) {
        Write-Host "❌ 致命错误：未找到 $Name！" -ForegroundColor Red
        Write-Host "! 解决：$Hint" -ForegroundColor Yellow
        exit 1
    }
}

# 安全清理确认
function Confirm-Cleanup {
    param([string]$Desc, [string]$Path)
    $item = Get-Item $Path -ErrorAction SilentlyContinue
    if (-not $item) {
        Write-Host "ℹ️ $Desc 不存在：$Path" -ForegroundColor Yellow
        return $false
    }
    $choice = Read-Host "`n确定清理 $Desc ($($item.FullName))? (Y/N)"
    return ($choice -in 'Y','y')
}

# 终止 Bochs 进程
function Stop-Bochs {
    $procName = "bochs"  # Bochs 进程名
    $procs = Get-Process $procName -ErrorAction SilentlyContinue
    if ($procs) {
        $procs | ForEach-Object {
            try { Stop-Process $_.Id -Force -ErrorAction Stop }
            catch { Write-Host "❌ 终止 Bochs (PID $($_.Id)) 失败：$_" -ForegroundColor Red }
        }
        Write-Host "✅ 所有 Bochs 进程已终止！" -ForegroundColor Green
    } else {
        Write-Host "ℹ️ 无运行的 Bochs 进程" -ForegroundColor Yellow
    }
}

# 验证 BIOS 文件是否存在
function Test-BiosFiles {
    $biosFile1 = Join-Path $biosDir "BIOS-bochs-latest"
    $biosFile2 = Join-Path $biosDir "VGABIOS-lgpl-latest.bin"
    $biosFiles = @($biosFile1, $biosFile2)
    foreach ($file in $biosFiles) {
        if (-not (Test-Path $file -PathType Leaf)) {
            Write-Host "❌ BIOS 文件不存在：$file" -ForegroundColor Red
            Write-Host "! 请确认文件已放置在 $biosDir 目录" -ForegroundColor Yellow
            exit 1
        }
    }
    Write-Host "✅ BIOS 文件验证通过！" -ForegroundColor Green
}

#endregion

# ------------------------------
# 3. 初始化环境
# ------------------------------
Write-Host "`n🚀 步骤1：初始化项目环境..." -ForegroundColor Green

# 备份源码
Write-Host "  💾 备份源码到 $bakDir..."
if (-not (Test-Path $bakDir)) { New-Item -ItemType Directory -Path $bakDir | Out-Null }
robocopy "$srcDir" "$bakDir" /MIR /NFL /NDL /NJH /NJS /nc /ns /np | Out-Null
if ($LASTEXITCODE -le 1) { Write-Host "✅ 源码备份完成！" -ForegroundColor Green } 
else { Write-Host "❌ 源码备份失败（代码：$LASTEXITCODE）" -ForegroundColor Red; exit 1 }

# 创建必要目录
$dirs = $buildDir, $logDir
$dirs | ForEach-Object {
    if (-not (Test-Path $_)) { 
        New-Item -ItemType Directory -Path $_ | Out-Null 
        Write-Host "✅ 创建目录：$_" -ForegroundColor Green 
    }
}

# 验证 BIOS 文件
Write-Host "  📋 验证 BIOS 文件..."
Test-BiosFiles

# 生成 Bochs 配置文件（基于可用配置完善）
Write-Host "  📝 生成 Bochs 配置文件：$bxcfgFile..."
$biosFile = (Join-Path $biosDir "BIOS-bochs-latest") -replace '/', '\'
$vgaBiosFile = (Join-Path $biosDir "VGABIOS-lgpl-latest.bin") -replace '/', '\'
$diskImgPath = $diskImg -replace '/', '\'
$logFilePath = (Join-Path $logDir "bochsout.txt") -replace '/', '\'

$bxcfgContent = @"
# ======================================================================
# Bochs 3.0 配置文件（HucOS 专用）
# 自动生成时间：$(Get-Date -Format "yyyy-MM-dd HH:mm:ss")
# 适用系统：HucOS 自研操作系统
# ======================================================================

# ------------------------------
# 内存配置
# ------------------------------
megs: 4

# ------------------------------
# BIOS 镜像路径
# ------------------------------
romimage: file=$biosFile
vgaromimage: file=$vgaBiosFile

# ------------------------------
# 存储设备配置
# ------------------------------
ata0-master: type=disk, path="$diskImgPath", mode=flat
boot: disk

# ------------------------------
# 显示与输入配置
# ------------------------------
display_library: win32
#mouse: enabled=1, mode=ps2
#keyboard: type=ps2, serial_delay=250

# ------------------------------
# 调试配置
# ------------------------------
debug: action=ignore
debugger_log: -
magic_break: enabled=1


# ------------------------------
# 串口与日志配置
# ------------------------------
serial: enabled=1, port=0x3f8, mode=file, dev="$logDir\bochs_serial.log"
log: file=$logFilePath
panic: action=report

# ------------------------------
# 其他优化配置
# ------------------------------
ne2k: enabled=0
#usb: enabled=0
clock: sync=realtime, time0=local
"@

$bxcfgContent | Out-File -FilePath $bxcfgFile -Encoding ascii
if (Test-Path $bxcfgFile) { 
    Write-Host "✅ Bochs 配置文件生成成功！" -ForegroundColor Green 
}
else { 
    Write-Host "❌ Bochs 配置文件生成失败：$bxcfgFile" -ForegroundColor Red 
    exit 1 
}

# ------------------------------
# 4. 检查开发依赖
# ------------------------------
Write-Host "`n🔍 步骤2：检查开发依赖..." -ForegroundColor Green
Check-Dependency "NASM 汇编器" "nasm.exe" "https://www.nasm.us/pub/nasm/releasebuilds/?C=M;O=D"
Check-Dependency "Bochs 调试器" $bochsExe "请安装 Bochs 3.0 到 $bochsDir"
Check-Dependency "DD 磁盘工具" "dd.exe" "http://www.chrysocome.net/dd/（需添加到 PATH）"

# ------------------------------
# 5. 编译核心组件（MBR/DBR/Kernel）
# ------------------------------
Write-Host "`n⚙️ 步骤3：编译汇编代码..." -ForegroundColor Green

function Compile-Source {
    param([string]$Src, [string]$Out, [string]$Desc)
    Write-Host "  🔨 编译 $Desc..."
    nasm -f bin $Src -o $Out
    if ($LASTEXITCODE -ne 0) {
        Write-Host "❌ 编译 $Desc 失败！" -ForegroundColor Red
        exit 1
    }
    if (-not (Test-Path $Out)) {
        Write-Host "❌ $Desc 输出文件未生成：$Out" -ForegroundColor Red
        exit 1
    }
    Write-Host "✅ 已生成：$Out ($(Get-Item $Out).Length 字节)" -ForegroundColor Green
}

# 编译 MBR、DBR、内核
Compile-Source "$srcDir/mbr.asm" "$buildDir/mbr.bin" "MBR"
Compile-Source "$srcDir/dbr.asm" "$buildDir/dbr.bin" "DBR"
Compile-Source "$srcDir/kernel.asm" "$buildDir/kernel.bin" "Kernel"

Write-Host "`n✅ 所有组件编译完成！" -ForegroundColor Green

# ------------------------------
# 6. 构建虚拟磁盘（hucos.img）
# ------------------------------
Write-Host "`n💿 步骤4：构建操作系统镜像..." -ForegroundColor Green

# 创建空白 RAW 镜像
Write-Host "  📦 创建虚拟磁盘：$diskImg ($imageSizeMB MB)..."
& "dd.exe" if=/dev/zero of="$diskImg" bs=1M count=$imageSizeMB status=progress
if (-not (Test-Path $diskImg)) { 
    Write-Host "❌ 创建镜像失败：$diskImg" -ForegroundColor Red
    exit 1 
}

# 写入 MBR到扇区0
Write-Host "  ✍️ 写入 MBR 到扇区0..."
& "dd.exe" if="$buildDir/mbr.bin" of="$diskImg" bs=512 count=1
if ($LASTEXITCODE -ne 0) { 
    Write-Host "❌ 写入MBR失败！" -ForegroundColor Red
    exit 1 
}

# 写入 DBR到扇区1
Write-Host "  ✍️ 写入 DBR 到扇区1..."
& "dd.exe" if="$buildDir/dbr.bin" of="$diskImg" bs=512 count=1 seek=1
if ($LASTEXITCODE -ne 0) { 
    Write-Host "❌ 写入DBR失败！" -ForegroundColor Red
    exit 1 
}

# 写入内核到扇区2
Write-Host "  ✍️ 写入 Kernel 到扇区2..."
& "dd.exe" if="$buildDir/kernel.bin" of="$diskImg" bs=512 seek=2
if ($LASTEXITCODE -ne 0) { 
    Write-Host "❌ 写入内核失败！" -ForegroundColor Red
    exit 1 
}

Write-Host "`n✅ 镜像创建成功: $diskImg" -ForegroundColor Green

# ------------------------------
# 7. 启动 Bochs 内置调试环境
# ------------------------------
Write-Host "`n🔧 步骤5：启动调试环境..." -ForegroundColor Green

Write-Host "`n📌 调试提示：" -ForegroundColor Cyan
Write-Host "  - Bochs 启动后会自动进入调试界面（因 magic_break 会在 0x7c00 处中断）" -ForegroundColor Cyan
Write-Host "  - 常用命令：c（继续）、s（单步）、b 0xXXXX（设断点）、r（看寄存器）、x /nwx 0xXXXX（看内存）" -ForegroundColor Cyan

# 启动 Bochs
$bochsArgs = @("-dbg", "-q", "-f", $bxcfgFile)
Start-Process -FilePath $bochsExe -ArgumentList $bochsArgs -Wait -NoNewWindow

# ------------------------------
# 8. 清理与退出
# ------------------------------
Write-Host "`n🧹 步骤6：终止 Bochs 进程..." -ForegroundColor Green
Stop-Bochs

Write-Host "`n🔚 步骤7：选择操作：" -ForegroundColor Green
Write-Host "1. 清理编译中间文件（保留镜像和日志）"
Write-Host "2. 保留所有文件"
Write-Host "3. 完全清理（删除镜像和编译文件）"
Write-Host "4. 退出"

$choice = Read-Host "请输入选项 (1-4)"
switch ($choice) {
    "1" {
        Write-Host "`n🧹 清理编译目录..." -ForegroundColor Green
        if (Confirm-Cleanup "编译目录" $buildDir) {
            Remove-Item $buildDir -Recurse -Force
            Write-Host "✅ 已清理：$buildDir" -ForegroundColor Green
        }
        Write-Host "`n✅ 清理完成，保留镜像：$diskImg 和日志目录：$logDir" -ForegroundColor Green
    }
    "2" {
        Write-Host "`nℹ️ 保留所有文件" -ForegroundColor Yellow
    }
    "3" {
        Write-Host "`n🧹 完全清理..." -ForegroundColor Green
        if (Confirm-Cleanup "编译目录" $buildDir) {
            Remove-Item $buildDir -Recurse -Force
            Write-Host "✅ 已清理：$buildDir" -ForegroundColor Green
        }
        if (Confirm-Cleanup "镜像文件" $diskImg) {
            Remove-Item $diskImg -Force
            Write-Host "✅ 已清理：$diskImg" -ForegroundColor Green
        }
        if (Confirm-Cleanup "日志目录" $logDir) {
            Remove-Item $logDir -Recurse -Force
            Write-Host "✅ 已清理：$logDir" -ForegroundColor Green
        }
        Write-Host "`n✅ 完全清理完成" -ForegroundColor Green
    }
    "4" {
        Write-Host "`n👋 退出，保留所有文件" -ForegroundColor Yellow
    }
    default {
        Write-Host "`n❌ 无效选项，保留所有文件" -ForegroundColor Yellow
    }
}

Write-Host "`n🎉 操作完成！" -ForegroundColor Green
