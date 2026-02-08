# ================================================================================
# Yuxi-Know Windows 远程部署脚本
# 从 Windows 机器远程连接 Linux 服务器执行部署
# ================================================================================

param(
    [Parameter(Position = 0, Mandatory = $false)]
    [ValidateSet("init", "update", "health", "backup", "rollback", "status", "data")]
    [string]$Command = "",

    [Parameter(Mandatory = $false)]
    [string]$Server = "",

    [Parameter(Mandatory = $false)]
    [string]$Port = "22",

    [Parameter(Mandatory = $false)]
    [string]$User = "",

    [Parameter(Mandatory = $false)]
    [string]$Password = "",

    [Parameter(Mandatory = $false)]
    [string]$KeyPath = "",

    [Parameter(Mandatory = $false)]
    [string]$ProjectDir = "/opt/yuxi-know",

    [Parameter(Mandatory = $false)]
    [switch]$Force,

    [Parameter(Mandatory = $false)]
    [switch]$Quiet,

    [Parameter(Mandatory = $false)]
    [switch]$Verbose,

    [Parameter(Mandatory = $false)]
    [string]$ConfigFile = "$PSScriptRoot\config\deploy.conf",

    [Parameter(Mandatory = $false)]
    [string]$Version = ""
)

# ============================================================================
# 配置管理
# ============================================================================

# 加载配置文件
function Load-Config {
    param(
        [string]$ConfigPath
    )

    if (Test-Path $ConfigPath) {
        Write-Verbose "加载配置文件: $ConfigPath"
        Get-Content $ConfigPath | ForEach-Object {
            if ($_ -match '^(\w+)=["'']?(.*)["'']?$') {
                $name = $matches[1]
                $value = $matches[2]

                # 转换布尔值
                if ($value -eq "true") { $value = $true }
                elseif ($value -eq "false") { $value = $false }

                # 设置全局变量（去除 Windows 特有的引号）
                if ($name -eq "PROJECT_DIR" -or $name -eq "DATA_ROOT") {
                    Set-Variable -Name $name -Value $value -Scope Script
                }
            }
        }
        return $true
    }
    return $false
}

# ============================================================================
# 日志工具
# ============================================================================

$COLORS = @{
    "DEBUG"    = "Cyan"
    "INFO"     = "White"
    "SUCCESS"  = "Green"
    "WARNING"  = "Yellow"
    "ERROR"    = "Red"
    "SECTION"  = "Magenta"
}

function Write-Log {
    param(
        [string]$Message,
        [ValidateSet("DEBUG", "INFO", "SUCCESS", "WARNING", "ERROR", "SECTION")]
        [string]$Level = "INFO"
    )

    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $color = $COLORS[$Level]

    if ($Quiet -and ($Level -ne "ERROR" -and $Level -ne "WARNING")) {
        return
    }

    switch ($Level) {
        "SECTION" {
            $width = 80
            $pad = [math]::Floor(($width - $Message.Length) / 2) - 2
            Write-Host ""
            Write-Host ("=" * $width) -ForegroundColor $color
            Write-Host (" " * $pad + $Message + " " * $pad) -ForegroundColor $color
            Write-Host ("=" * $width) -ForegroundColor $color
            Write-Host ""
        }
        "SUCCESS" {
            Write-Host "[${timestamp}] [${Level}] [✅] $Message" -ForegroundColor $color
        }
        "ERROR" {
            Write-Host "[${timestamp}] [${Level}] [❌] $Message" -ForegroundColor $color
        }
        default {
            Write-Host "[${timestamp}] [${Level}] $Message" -ForegroundColor $color
        }
    }
}

function Write-Debug-Log { param($msg); Write-Log -Message $msg -Level "DEBUG" }
function Write-Info-Log { param($msg); Write-Log -Message $msg -Level "INFO" }
function Write-Success-Log { param($msg); Write-Log -Message $msg -Level "SUCCESS" }
function Write-Warning-Log { param($msg); Write-Log -Message $msg -Level "WARNING" }
function Write-Error-Log { param($msg); Write-Log -Message $msg -Level "ERROR" }
function Write-Section-Log { param($msg); Write-Log -Message $msg -Level "SECTION" }

# ============================================================================
# SSH 连接管理
# ================================================================================

# 检查 SSH 工具是否可用
function Test-SSHTool {
    $sshPath = Get-Command ssh -ErrorAction SilentlyContinue

    if ($sshPath) {
        Write-Verbose "找到 SSH 客户端: $($sshPath.Source)"
        return @{
            Available = $true
            Tool      = "ssh"
            Path      = $sshPath.Source
        }
    }

    # 检查 plink (PuTTY)
    $plinkPath = Get-Command plink -ErrorAction SilentlyContinue
    if ($plinkPath) {
        Write-Verbose "找到 Plink 客户端: $($plinkPath.Source)"
        return @{
            Available = $true
            Tool      = "plink"
            Path      = $plinkPath.Source
        }
    }

    Write-Error-Log "未找到 SSH 客户端！请安装 OpenSSH 或 PuTTY"
    Write-Info-Log "Windows 10/11 自带 OpenSSH，可通过以下方式启用："
    Write-Info-Log "  设置 -> 应用 -> 可选功能 -> 添加功能 -> OpenSSH 客户端"
    Write-Info-Log "或访问: https://github.com/PowerShell/Win32-OpenSSH/releases"

    return @{ Available = $false }
}

# 构建 SSH 连接命令
function Build-SSHCommand {
    param(
        [string]$Server,
        [string]$Port = "22",
        [string]$User,
        [string]$Password,
        [string]$KeyPath,
        [string]$Command,
        [string]$Tool = "ssh"
    )

    $sshConfig = ""

    if ($Tool -eq "ssh") {
        # OpenSSH (Windows 自带)
        $sshArgs = @()

        # 端口
        $sshArgs += "-p", $Port

        # 密钥认证
        if ($KeyPath -and (Test-Path $KeyPath)) {
            $sshArgs += "-i", "`"$KeyPath`""
        }

        # 连接参数
        $sshArgs += "-o", "StrictHostKeyChecking=no"
        $sshArgs += "-o", "UserKnownHostsFile=nul"
        $sshArgs += "-o", "LogLevel=ERROR"

        # 如果是 AI 自动执行模式，添加批处理模式
        if ($env:AI_MODE -eq "true") {
            $sshArgs += "-o", "BatchMode=yes"
        }

        # 构建连接字符串
        $connectionString = "${User}@${Server}"

        # 组合命令
        if ($Command) {
            $sshConfig = "ssh $($sshArgs -join ' ') ${connectionString} `"$Command`""
        }
        else {
            $sshConfig = "ssh $($sshArgs -join ' ') ${connectionString}"
        }
    }
    elseif ($Tool -eq "plink") {
        # Plink (PuTTY)
        $plinkArgs = @()

        # 端口
        $plinkArgs += "-P", $Port

        # 密钥认证
        if ($KeyPath -and (Test-Path $KeyPath)) {
            $plinkArgs += "-i", "`"$KeyPath`""
        }

        # 连接参数
        $plinkArgs += "-batch"

        # 构建连接字符串
        $connectionString = "${User}@${Server}"

        # 组合命令
        if ($Command) {
            $sshConfig = "plink $($plinkArgs -join ' ') ${connectionString} `"$Command`""
        }
        else {
            $sshConfig = "plink $($plinkArgs -join ' ') ${connectionString}"
        }
    }

    Write-Debug-Log "SSH 命令: $sshConfig"
    return $sshConfig
}

# 通过 SSH 远程执行命令
function Invoke-RemoteCommand {
    param(
        [string]$Server,
        [string]$Port = "22",
        [string]$User,
        [string]$Password,
        [string]$KeyPath,
        [string]$Command,
        [string]$Tool = "ssh",
        [switch]$ExpectFail = $false
    )

    $sshCmd = Build-SSHCommand -Server $Server -Port $Port -User $User -Password $Password -KeyPath $KeyPath -Command $Command -Tool $Tool

    Write-Debug-Log "远程执行命令: $Command"

    try {
        # 如果提供了密码，使用 PowerShell 交互式方式
        if ($Password -and $env:AI_MODE -ne "true") {
            $securePassword = ConvertTo-SecureString $Password -AsPlainText -Force
            $credential = New-Object System.Management.Automation.PSCredential ($User, $securePassword)

            if ($Tool -eq "ssh") {
                # OpenSSH with password - 需要使用 sshpass (Linux) 或 expect (跨平台)
                # Windows 下建议使用 SSH 密钥
                Write-Warning-Log "OpenSSH 不支持在命令行中直接传递密码"
                Write-Info-Log "请使用 SSH 密钥认证或手动输入密码"
                Write-Info-Log "生成 SSH 密钥命令: ssh-keygen -t ed25519"
            }
            else {
                # 使用 plink 密码认证
                $passwordFile = [System.IO.Path]::GetTempFileName()
                $Password | Out-File -FilePath $passwordFile -Encoding ASCII -NoNewline

                try {
                    $result = & plink -P $Port -pw $Password -batch "${User}@${Server}" $Command
                    $exitCode = $LASTEXITCODE

                    if ($exitCode -eq 0 -or $ExpectFail) {
                        return @{ Success = $true; Output = $result; ExitCode = $exitCode }
                    }
                    else {
                        return @{ Success = $false; Output = $result; ExitCode = $exitCode }
                    }
                }
                finally {
                    Remove-Item $passwordFile -Force -ErrorAction SilentlyContinue
                }
            }
        }
        else {
            # 使用 SSH 密钥或 AI 自动执行模式
            $output = Invoke-Expression $sshCmd
            $exitCode = $LASTEXITCODE

            if ($exitCode -eq 0 -or $ExpectFail) {
                return @{ Success = $true; Output = $output; ExitCode = $exitCode }
            }
            else {
                return @{ Success = $false; Output = $output; ExitCode = $exitCode }
            }
        }
    }
    catch {
        Write-Error-Log "远程命令执行失败: $_"
        return @{ Success = $false; Output = $_.Exception.Message; ExitCode = 1 }
    }
}

# ============================================================================
# 部署命令函数
# ============================================================================

# 远程执行 init 命令
function Invoke-RemoteInit {
    $deployScript = "deploy.sh"
    $cmd = "cd ${ProjectDir} && bash scripts/deploy/${deployScript} init"

    if ($Force) { $cmd += " --force" }
    if ($Quiet) { $cmd += " --quiet" }
    if ($Verbose) { $cmd += " --verbose" }

    Write-Section-Log "执行远程初始化部署"
    Write-Info-Log "项目目录: $ProjectDir"

    $result = Invoke-RemoteCommand -Server $Server -Port $Port -User $User -Password $Password -KeyPath $KeyPath -Command $cmd -Tool $script:SSHTool.Tool

    if ($result.Success) {
        Write-Success-Log "✅ 初始化部署成功！"
        if ($result.Output) {
            Write-Host ""
            Write-Host "========= 远程输出 =========" -ForegroundColor Cyan
            Write-Host $result.Output
            Write-Host "==========================" -ForegroundColor Cyan
        }
    }
    else {
        Write-Error-Log "❌ 初始化部署失败！"
        if ($result.Output) {
            Write-Host ""
            Write-Host "========= 错误输出 =========" -ForegroundColor Red
            Write-Host $result.Output
            Write-Host "========================" -ForegroundColor Red
        }
        exit 1
    }
}

# 远程执行 update 命令
function Invoke-RemoteUpdate {
    $deployScript = "deploy.sh"
    $argsList = @()

    if ($Force) { $argsList += "--force" }
    if ($Quiet) { $argsList += "--quiet" }
    if ($Verbose) { $argsList += "--verbose" }

    $argsStr = $argsList -join " "
    $cmd = "cd ${ProjectDir} && bash scripts/deploy/${deployScript} update ${argsStr}"

    Write-Section-Log "执行远程更新部署"
    Write-Info-Log "项目目录: $ProjectDir"

    $result = Invoke-RemoteCommand -Server $Server -Port $Port -User $User -Password $Password -KeyPath $KeyPath -Command $cmd -Tool $script:SSHTool.Tool

    if ($result.Success) {
        Write-Success-Log "✅ 更新部署成功！"
        if ($result.Output) {
            Write-Host ""
            Write-Host "========= 远程输出 =========" -ForegroundColor Cyan
            Write-Host $result.Output
            Write-Host "==========================" -ForegroundColor Cyan
        }
    }
    else {
        Write-Error-Log "❌ 更新部署失败！"
        if ($result.Output) {
            Write-Host ""
            Write-Host "========= 错误输出 =========" -ForegroundColor Red
            Write-Host $result.Output
            Write-Host "========================" -ForegroundColor Red
        }
        exit 1
    }
}

# 远程执行 health 命令
function Invoke-RemoteHealth {
    $cmd = "cd ${ProjectDir} && bash scripts/deploy/health.sh"

    Write-Section-Log "执行远程健康检查"
    Write-Info-Log "项目目录: $ProjectDir"

    $result = Invoke-RemoteCommand -Server $Server -Port $Port -User $User -Password $Password -KeyPath $KeyPath -Command $cmd -Tool $script:SSHTool.Tool

    Write-Success-Log "✅ 健康检查完成"
    if ($result.Output) {
        Write-Host ""
        Write-Host $result.Output
    }
}

# 远程执行 backup 命令
function Invoke-RemoteBackup {
    $cmd = "cd ${ProjectDir} && bash scripts/deploy/backup.sh"

    Write-Section-Log "执行远程数据备份"
    Write-Info-Log "项目目录: $ProjectDir"

    $result = Invoke-RemoteCommand -Server $Server -Port $Port -User $User -Password $Password -KeyPath $KeyPath -Command $cmd -Tool $script:SSHTool.Tool

    if ($result.Success) {
        Write-Success-Log "✅ 数据备份成功！"
    }
    else {
        Write-Error-Log "❌ 数据备份失败！"
        if ($result.Output) {
            Write-Host $result.Output
        }
        exit 1
    }
}

# 远程执行 rollback 命令
function Invoke-RemoteRollback {
    if (-not $Version) {
        Write-Error-Log "回滚需要指定版本！"
        Write-Info-Log "用法: .\deploy.ps1 rollback -Version <commit-hash>"
        exit 1
    }

    $cmd = "cd ${ProjectDir} && bash scripts/deploy/rollback.sh $Version"

    Write-Section-Log "执行远程版本回滚"
    Write-Info-Log "项目目录: $ProjectDir"
    Write-Info-Log "回滚版本: $Version"

    $result = Invoke-RemoteCommand -Server $Server -Port $Port -User $User -Password $Password -KeyPath $KeyPath -Command $cmd -Tool $script:SSHTool.Tool

    if ($result.Success) {
        Write-Success-Log "✅ 版本回滚成功！"
    }
    else {
        Write-Error-Log "❌ 版本回滚失败！"
        exit 1
    }
}

# 远程执行 status 命令
function Invoke-RemoteStatus {
    $cmd = "cd ${ProjectDir} && bash scripts/deploy/deploy.sh status"

    Write-Section-Log "获取远程部署状态"
    Write-Info-Log "项目目录: $ProjectDir"

    $result = Invoke-RemoteCommand -Server $Server -Port $Port -User $User -Password $Password -KeyPath $KeyPath -Command $cmd -Tool $script:SSHTool.Tool

    Write-Success-Log "✅ 状态获取完成"
    if ($result.Output) {
        Write-Host ""
        Write-Host $result.Output
    }
}

# 远程执行 data 命令
function Invoke-RemoteData {
    if (-not $args) {
        Write-Info-Log "用法: .\deploy.ps1 data <SubCommand>"
        Write-Info-Log "子命令: usage, clean-logs, verify, migrate"
        exit 1
    }

    $subCommand = $args[0]
    $cmd = "cd ${ProjectDir} && bash scripts/deploy/deploy.sh data $subCommand"

    Write-Section-Log "执行远程数据卷管理"
    Write-Info-Log "项目目录: $ProjectDir"
    Write-Info-Log "子命令: $subCommand"

    $result = Invoke-RemoteCommand -Server $Server -Port $Port -User $User -Password $Password -KeyPath $KeyPath -Command $cmd -Tool $script:SSHTool.Tool

    if ($result.Output) {
        Write-Host $result.Output
    }
}

# ============================================================================
# 交互式配置
# ============================================================================

function Show-Usage {
    @"

Yuxi-Know Windows 远程部署工具 v1.0.0
======================================

用法:
  .\deploy.ps1 [命令] [选项]

命令:
  init        首次初始化远程部署环境
  update      更新远程部署（拉取代码+重启服务）
  health      检查远程服务健康状态
  backup      备份远程数据
  rollback    回滚到指定版本
  status      查看远程部署状态
  data        远程数据卷管理

选项:
  -Server     远程服务器地址（必填）
  -Port       SSH 端口（默认: 22）
  -User       SSH 用户名（必填）
  -Password   SSH 密码（建议使用密钥）
  -KeyPath    SSH 私钥路径（推荐）
  -ProjectDir 远程项目目录（默认: /opt/yuxi-know）
  -Force      强制执行（跳过确认）
  -Quiet      静默模式（只输出错误和警告）
  -Verbose    详细模式
  -ConfigFile 配置文件路径
  -Version    回滚版本（rollback 命令使用）

环境变量（AI 自动执行）:
  AI_MODE=true  启用 AI 自动执行模式（使用批处理 SSH）

示例:
  # 首次部署
  .\deploy.ps1 init -Server 192.168.1.100 -User root -KeyPath C:\Users\user\.ssh\id_rsa

  # 更新部署
  .\deploy.ps1 update -Server 192.168.1.100 -User root -KeyPath C:\Users\user\.ssh\id_rsa

  # 健康检查
  .\deploy.ps1 health -Server 192.168.1.100 -User root -KeyPath C:\Users\user\.ssh\id_rsa

  # 使用配置文件
  .\deploy.ps1 update -ConfigFile .\config\deploy.conf

  # AI 自动执行（设置环境变量）
  $env:AI_MODE="true"
  .\deploy.ps1 update -Server 192.168.1.100 -User root -KeyPath C:\Users\user\.ssh\id_rsa

配置文件示例 (config\deploy.conf):
  SSH_SERVER=192.168.1.100
  SSH_PORT=22
  SSH_USER=root
  SSH_KEY_PATH=C:\Users\user\.ssh\id_rsa
  PROJECT_DIR=/opt/yuxi-know

更多文档请访问: https://github.com/xerrors/Yuxi-Know

"@
}

function Read-ServerConfig {
    Write-Section-Log "配置远程服务器连接"

    # 如果提供了配置文件，从配置文件读取
    if ($ConfigFile -and (Test-Path $ConfigFile)) {
        Write-Info-Log "从配置文件加载: $ConfigFile"
        Get-Content $ConfigFile | ForEach-Object {
            if ($_ -match '^(\w+)=(.*)$') {
                switch ($matches[1]) {
                    "SSH_SERVER" { $script:Server = $matches[2] }
                    "SSH_PORT"   { $script:Port = $matches[2] }
                    "SSH_USER"   { $script:User = $matches[2] }
                    "SSH_KEY_PATH" { $script:KeyPath = $matches[2] }
                    "PROJECT_DIR" { $script:ProjectDir = $matches[2] }
                }
            }
        }
    }

    # 交互式输入（如果没有提供足够的参数）
    if (-not $script:Server) {
        $script:Server = Read-Host "请输入服务器地址"
    }

    if (-not $script:Port) {
        $portInput = Read-Host "请输入 SSH 端口（默认 22）"
        $script:Port = if ($portInput) { $portInput } else { "22" }
    }

    if (-not $script:User) {
        $script:User = Read-Host "请输入用户名"
    }

    if (-not $script:KeyPath -and -not $script:Password -and $env:AI_MODE -ne "true") {
        $useKey = Read-Host "使用 SSH 密钥吗？(Y/n)"
        if ($useKey -ne "n") {
            $defaultKeyPath = "$env:USERPROFILE\.ssh\id_rsa"
            $keyInput = Read-Host "请输入私钥路径（默认: $defaultKeyPath）"
            $script:KeyPath = if ($keyInput) { $keyInput } else { $defaultKeyPath }
        }
        else {
            $script:Password = Read-Host "请输入密码（注意：密码明文传输，建议使用密钥）" -AsSecureString
            $script:Password = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto([System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($script:Password))
        }
    }

    if (-not $script:ProjectDir) {
        $projectInput = Read-Host "请输入项目目录（默认: /opt/yuxi-know）"
        $script:ProjectDir = if ($projectInput) { $projectInput } else { "/opt/yuxi-know" }
    }

    # 确认配置
    Write-Host ""
    Write-Host "======== 连接配置 ========" -ForegroundColor Cyan
    Write-Host "服务器: $script:Server:$script:Port"
    Write-Host "用户:   $script:User"
    if ($script:KeyPath) { Write-Host "认证:   密钥 ($script:KeyPath)" }
    else { Write-Host "认证:   密码" }
    Write-Host "目录:   $script:ProjectDir"
    Write-Host "========================" -ForegroundColor Cyan
    Write-Host ""

    $confirm = Read-Host "确认配置？(Y/n)"
    if ($confirm -eq "n") {
        exit 0
    }
}

# ============================================================================
# 主函数
# ================================================================================

function Main {
    # 显示版本信息
    if ($Command -eq "" -or $Command -eq "-h" -or $Command -eq "--help") {
        Show-Usage
        exit 0
    }

    # 检查 SSH 工具
    $script:SSHTool = Test-SSHTool
    if (-not $script:SSHTool.Available) {
        exit 1
    }

    # 读取服务器配置
    if (-not $Server -or -not $User) {
        Read-ServerConfig
    }

    # 记录配置
    Write-Verbose "服务器: $Server:$Port"
    Write-Verbose "用户: $User"
    Write-Verbose "项目目录: $ProjectDir"
    Write-Verbose "AI 模式: $env:AI_MODE"

    # 执行命令
    switch ($Command) {
        "init"    { Invoke-RemoteInit }
        "update"  { Invoke-RemoteUpdate }
        "health"  { Invoke-RemoteHealth }
        "backup"  { Invoke-RemoteBackup }
        "rollback" { Invoke-RemoteRollback }
        "status"  { Invoke-RemoteStatus }
        "data"    { Invoke-RemoteData -args $args }
        default   {
            Write-Error-Log "未知命令: $Command"
            Show-Usage
            exit 1
        }
    }
}

# 执行主函数
Main
