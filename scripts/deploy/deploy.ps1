# ================================================================================
# Yuxi-Know Windows Remote Deployment Script
# Connect from Windows to Linux server for deployment
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
    [switch]$DebugMode,

    [Parameter(Mandatory = $false)]
    [string]$ConfigFile = "",

    [Parameter(Mandatory = $false)]
    [string]$Version = "",
    [Parameter(Mandatory = $false)]
    [string]$Branch = ""
)
# Auto-detect config file if not specified
if (-not $ConfigFile) {
    $windowsConf = "$PSScriptRoot\config\windows-deploy.conf"
    $deployConf = "$PSScriptRoot\config\deploy.conf"
    if (Test-Path $windowsConf) {
        $ConfigFile = $windowsConf
    }
    elseif (Test-Path $deployConf) {
        $ConfigFile = $deployConf
    }
}

# ============================================================================
# Configuration Management
# ============================================================================

function Load-Config {
    param([string]$ConfigPath)

    if (Test-Path $ConfigPath) {
        Write-Verbose "Loading config: $ConfigPath"
        Get-Content $ConfigPath | ForEach-Object {
            if ($_ -match '^(\w+)=(.*)$') {
                $name = $matches[1]
                $value = $matches[2].Trim()

                # Only load if command-line parameter is not already set
                switch ($name) {
                    "SSH_SERVER" { if (-not $script:Server) { $script:Server = $value } }
                    "SSH_PORT"   { if (-not $script:Port) { $script:Port = $value } }
                    "SSH_USER"   { if (-not $script:User) { $script:User = $value } }
                    "SSH_KEY_PATH" { if (-not $script:KeyPath) { $script:KeyPath = $value } }
                    "PROJECT_DIR" { if (-not $script:ProjectDir) { $script:ProjectDir = $value } }
                    "SSH_BRANCH" { if (-not $script:Branch) { $script:Branch = $value } }
                }
            }
        }
        return $true
    }
    return $false
}

# ============================================================================
# Log Tools
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
            Write-Host "[$timestamp] [$Level] [OK] $Message" -ForegroundColor $color
        }
        "ERROR" {
            Write-Host "[$timestamp] [$Level] [X] $Message" -ForegroundColor $color
        }
        default {
            Write-Host "[$timestamp] [$Level] $Message" -ForegroundColor $color
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
# SSH Connection Management
# ============================================================================

function Test-SSHTool {
    $sshPath = Get-Command ssh -ErrorAction SilentlyContinue

    if ($sshPath) {
        Write-Verbose "Found SSH: $($sshPath.Source)"
        return @{
            Available = $true
            Tool      = "ssh"
            Path      = $sshPath.Source
        }
    }

    $plinkPath = Get-Command plink -ErrorAction SilentlyContinue
    if ($plinkPath) {
        Write-Verbose "Found Plink: $($plinkPath.Source)"
        return @{
            Available = $true
            Tool      = "plink"
            Path      = $plinkPath.Source
        }
    }

    Write-Error-Log "SSH client not found! Please install OpenSSH or PuTTY"
    Write-Info-Log "Windows 10/11 has built-in OpenSSH"
    return @{ Available = $false }
}

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
        $sshArgs = @()
        $sshArgs += "-p", $Port

        if ($KeyPath -and (Test-Path $KeyPath)) {
            $sshArgs += "-i", "`"$KeyPath`""
        }

        $sshArgs += "-o", "StrictHostKeyChecking=no"
        $sshArgs += "-o", "UserKnownHostsFile=nul"
        $sshArgs += "-o", "LogLevel=ERROR"

        if ($env:AI_MODE -eq "true") {
            $sshArgs += "-o", "BatchMode=yes"
        }

        $connectionString = "${User}@${Server}"

        if ($Command) {
            $sshConfig = "ssh $($sshArgs -join ' ') ${connectionString} `"$Command`""
        }
        else {
            $sshConfig = "ssh $($sshArgs -join ' ') ${connectionString}"
        }
    }
    elseif ($Tool -eq "plink") {
        $plinkArgs = @()
        $plinkArgs += "-P", $Port

        if ($KeyPath -and (Test-Path $KeyPath)) {
            $plinkArgs += "-i", "`"$KeyPath`""
        }

        $plinkArgs += "-batch"

        $connectionString = "${User}@${Server}"

        if ($Command) {
            $sshConfig = "plink $($plinkArgs -join ' ') ${connectionString} `"$Command`""
        }
        else {
            $sshConfig = "plink $($plinkArgs -join ' ') ${connectionString}"
        }
    }

    Write-Debug-Log "SSH cmd: $sshConfig"
    return $sshConfig
}

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

    Write-Debug-Log "Remote cmd: $Command"

    try {
        if ($Password -and $env:AI_MODE -ne "true") {
            $securePassword = ConvertTo-SecureString $Password -AsPlainText -Force
            $credential = New-Object System.Management.Automation.PSCredential ($User, $securePassword)

            if ($Tool -eq "ssh") {
                Write-Warning-Log "OpenSSH does not support password in command line"
                Write-Info-Log "Please use SSH key authentication"
                exit 1
            }
            else {
                $result = & plink -P $Port -pw $Password -batch "${User}@${Server}" $Command
                $exitCode = $LASTEXITCODE

                if ($exitCode -eq 0 -or $ExpectFail) {
                    return @{ Success = $true; Output = $result; ExitCode = $exitCode }
                }
                else {
                    return @{ Success = $false; Output = $result; ExitCode = $exitCode }
                }
            }
        }
        else {
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
        Write-Error-Log "Remote command failed: $_"
        return @{ Success = $false; Output = $_.Exception.Message; ExitCode = 1 }
    }
}

# ============================================================================
# Deployment Command Functions
# ============================================================================

function Invoke-RemoteInit {
    Write-Section-Log "Execute remote init deployment"
    Write-Info-Log "Project dir: $ProjectDir"

    # Set branch from config if not provided via command-line
    if (-not $Branch -and $script:Branch) {
        Write-Info-Log "Using branch from config file: ${script:Branch}"
        $Branch = $script:Branch
    }

    # Step 0: Check if Git is installed
    Write-Info-Log "Step 0: Checking Git installation"
    $cmd = "if command -v git >/dev/null 2>&1; then echo 'INSTALLED'; else echo 'NOT_FOUND'; fi"
    $result = Invoke-RemoteCommand -Server $Server -Port $Port -User $User -Password $Password -KeyPath $KeyPath -Command $cmd -Tool $script:SSHTool.Tool

    if ($result.Output -notmatch "INSTALLED") {
        Write-Warning-Log "Git is not installed on the remote server"

        # Detect OS and install Git
        Write-Info-Log "Detecting OS distribution..."
        $checkOsCmd = "if [ -f /etc/os-release ]; then cat /etc/os-release | grep '^ID=' | cut -d'=' -f2; elif [ -f /etc/redhat-release ]; then echo 'rhel'; else echo 'unknown'; fi"
        $osResult = Invoke-RemoteCommand -Server $Server -Port $Port -User $User -Password $Password -KeyPath $KeyPath -Command $checkOsCmd -Tool $script:SSHTool.Tool

        $osId = $osResult.Output.Trim().Trim('"')
        Write-Info-Log "Detected OS: $osId"

        Write-Info-Log "Installing Git automatically..."
        $installCmd = ""

        switch ($osId) {
            "ubuntu" { $installCmd = "apt-get update -qq && apt-get install -y -qq git" }
            "debian" { $installCmd = "apt-get update -qq && apt-get install -y -qq git" }
            "centos" { $installCmd = "yum install -y -q git" }
            "rhel" { $installCmd = "yum install -y -q git" }
            "alinux" { $installCmd = "yum install -y -q git" }
            "anolis" { $installCmd = "yum install -y -q git" }
            "fedora" { $installCmd = "dnf install -y -q git" }
            "almalinux" { $installCmd = "dnf install -y -q git" }
            "rocky" { $installCmd = "dnf install -y -q git" }
            default {
                Write-Error-Log "Unsupported OS: $osId"
                Write-Info-Log "Please install Git manually on the remote server:"
                Write-Info-Log "  Ubuntu/Debian: apt-get install git"
                Write-Info-Log "  CentOS/RHEL/Alinux: yum install git"
                Write-Info-Log "  Fedora/AlmaLinux/Rocky: dnf install git"
                exit 1
            }
        }

        if ($installCmd) {
            # Run installation with sudo (will prompt for password if needed in AI mode)
            $sudoCmd = "sudo $installCmd"
            Write-Info-Log "Running: $sudoCmd"

            # For AI mode, we may need to handle sudo prompting
            if ($env:AI_MODE -eq "true") {
                $sudoCmd = "export DEBIAN_FRONTEND=noninteractive; $sudoCmd"
            }

            $installResult = Invoke-RemoteCommand -Server $Server -Port $Port -User $User -Password $Password -KeyPath $KeyPath -Command $sudoCmd -Tool $script:SSHTool.Tool

            if (-not $installResult.Success) {
                Write-Error-Log "Failed to install Git automatically"
                Write-Info-Log "Output: $($installResult.Output)"
                Write-Info-Log "Please install Git manually on the remote server"
                exit 1
            }

            Write-Success-Log "Git installed successfully"
        }
    }
    else {
        Write-Success-Log "Git is already installed"
    }

    # Step 1: Create project directory
    Write-Info-Log "Step 1: Creating project directory"
    $cmd = "mkdir -p ${ProjectDir} && cd ${ProjectDir} && pwd"
    $result = Invoke-RemoteCommand -Server $Server -Port $Port -User $User -Password $Password -KeyPath $KeyPath -Command $cmd -Tool $script:SSHTool.Tool
    if (-not $result.Success) {
        Write-Error-Log "Failed to create project directory"
        exit 1
    }

    # Step 2: Check if Git repo already exists
    Write-Info-Log "Step 2: Checking if repository already exists"
    $checkCmd = "cd ${ProjectDir}; ls -A > /dev/null 2>&1 && echo NOT_EMPTY || echo EMPTY; [ -d .git ] && echo GIT_REPO || echo NO_GIT"
    $checkResult = Invoke-RemoteCommand -Server $Server -Port $Port -User $User -Password $Password -KeyPath $KeyPath -Command $checkCmd -Tool $script:SSHTool.Tool

    if ($checkResult.Output -match "GIT_REPO") {
        Write-Warning-Log "Repository already exists. Pulling latest changes..."
        $cmd = "cd ${ProjectDir} && git pull"
        $result = Invoke-RemoteCommand -Server $Server -Port $Port -User $User -Password $Password -KeyPath $KeyPath -Command $cmd -Tool $script:SSHTool.Tool
    }
    elseif ($checkResult.Output -match "NOT_EMPTY") {
        # Directory exists but is not a git repository
        Write-Warning-Log "Directory exists but is not a git repository: ${ProjectDir}"

        if ($Force) {
            Write-Info-Log "Removing directory and cloning fresh (Force mode)..."
            $cmd = "rm -rf ${ProjectDir} && mkdir -p ${ProjectDir} && cd ${ProjectDir} && git clone https://github.com/Chenwx0/Yuxi-Know.git ."
            $result = Invoke-RemoteCommand -Server $Server -Port $Port -User $User -Password $Password -KeyPath $KeyPath -Command $cmd -Tool $script:SSHTool.Tool

            if (-not $result.Success) {
                Write-Error-Log "Failed to clone repository"
                Write-Info-Log "Output: $($result.Output)"
                exit 1
            }
        }
        else {
            Write-Error-Log "Directory is not empty and not a git repository"
            Write-Host ""
            Write-Host "Please choose one of the following:" -ForegroundColor Yellow
            Write-Host "  1. Manually remove the directory: ssh ${User}@${Server} 'rm -rf ${ProjectDir}'"
            Write-Host "  2. Or run with -Force flag to automatically remove and reclone"
            Write-Host ""
            exit 1
        }
    }
    else {
        # Directory is empty or doesn't exist (should exist after Step 1)
        Write-Info-Log "Step 3: Cloning repository"
        $repoUrl = "https://github.com/Chenwx0/Yuxi-Know.git"
        $cmd = "cd ${ProjectDir} && git clone ${repoUrl} ."
        $result = Invoke-RemoteCommand -Server $Server -Port $Port -User $User -Password $Password -KeyPath $KeyPath -Command $cmd -Tool $script:SSHTool.Tool

        if (-not $result.Success) {
            Write-Error-Log "Failed to clone repository"
            Write-Info-Log "Output: $($result.Output)"
            exit 1
        }
    }

    # Step 2.5: Switch to specified branch (if provided)
    if ($Branch) {
        Write-Info-Log "Step 2.5: Switching to branch: ${Branch}"
        $checkoutCmd = "cd ${ProjectDir} && git checkout ${Branch}"
        $checkoutResult = Invoke-RemoteCommand -Server $Server -Port $Port -User $User -Password $Password -KeyPath $KeyPath -Command $checkoutCmd -Tool $script:SSHTool.Tool
        if (-not $checkoutResult.Success) {
            Write-Error-Log "Failed to switch to branch: ${Branch}"
            Write-Info-Log "Output: $($checkoutResult.Output)"
            exit 1
        }
        Write-Success-Log "Switched to branch: ${Branch}"
    }

    # Step 2.5: Ensure branch is correct (PowerShell parameter takes priority)
    if ($Branch) {
        Write-Info-Log "Ensuring branch: ${Branch}"
        $checkoutCmd = "cd ${ProjectDir} && git checkout ${Branch}"
        $checkoutResult = Invoke-RemoteCommand -Server $Server -Port $Port -User $User -Password $Password -KeyPath $KeyPath -Command $checkoutCmd -Tool $script:SSHTool.Tool
        if (-not $checkoutResult.Success) {
            Write-Error-Log "Failed to switch to branch: ${Branch}"
            Write-Info-Log "Output: $($checkoutResult.Output)"
            exit 1
        }
        Write-Success-Log "Switched to branch: ${Branch}"
    }

    # Step 3: Run the init.sh script
    Write-Info-Log "Step 3: Running initialization script"
    $cmd = "cd ${ProjectDir}; bash scripts/deploy/init.sh"

    # Note: If Branch was specified, init.sh will still see the config file's GIT_BRANCH,
    # but we've already switched to the correct branch above, so it doesn't matter.
    # The git checkout we performed takes precedence.

    $result = Invoke-RemoteCommand -Server $Server -Port $Port -User $User -Password $Password -KeyPath $KeyPath -Command $cmd -Tool $script:SSHTool.Tool

    if ($result.Success) {
        Write-Success-Log "Init deployment successful!"
        if ($result.Output) {
            Write-Host ""
            Write-Host "========= Remote Output =========" -ForegroundColor Cyan
            Write-Host $result.Output
            Write-Host "==============================" -ForegroundColor Cyan
        }
    }
    else {
        Write-Error-Log "Init deployment failed!"
        if ($result.Output) {
            Write-Host ""
            Write-Host "========= Error Output =========" -ForegroundColor Red
            Write-Host $result.Output
            Write-Host "============================" -ForegroundColor Red
        }
        exit 1
    }
}

function Invoke-RemoteUpdate {
    Write-Section-Log "Execute remote update deployment"
    Write-Info-Log "Project dir: $ProjectDir"

    # Step 1: If Branch is specified, switch to that branch first
    if ($Branch) {
        Write-Info-Log "Switching to branch: ${Branch}"
        $checkoutCmd = "cd ${ProjectDir} && git fetch origin && git checkout ${Branch} && git pull origin ${Branch}"
        $checkoutResult = Invoke-RemoteCommand -Server $Server -Port $Port -User $User -Password $Password -KeyPath $KeyPath -Command $checkoutCmd -Tool $script:SSHTool.Tool
        if (-not $checkoutResult.Success) {
            Write-Error-Log "Failed to switch to branch: ${Branch}"
            Write-Info-Log "Output: $($checkoutResult.Output)"
            exit 1
        }
        Write-Success-Log "Switched to branch: ${Branch}"
    }

    # Step 2: Run deploy.sh update
    $deployScript = "deploy.sh"
    $argsList = @()

    if ($Force) { $argsList += "--force" }
    if ($Quiet) { $argsList += "--quiet" }
    if ($DebugMode) { $argsList += "--verbose" }

    $argsStr = $argsList -join " "
    $cmd = "cd ${ProjectDir}; bash scripts/deploy/${deployScript} update ${argsStr}"

    $result = Invoke-RemoteCommand -Server $Server -Port $Port -User $User -Password $Password -KeyPath $KeyPath -Command $cmd -Tool $script:SSHTool.Tool

    if ($result.Success) {
        Write-Success-Log "Update deployment successful!"
        if ($result.Output) {
            Write-Host ""
            Write-Host "========= Remote Output =========" -ForegroundColor Cyan
            Write-Host $result.Output
            Write-Host "==============================" -ForegroundColor Cyan
        }
    }
    else {
        Write-Error-Log "Update deployment failed!"
        if ($result.Output) {
            Write-Host ""
            Write-Host "========= Error Output =========" -ForegroundColor Red
            Write-Host $result.Output
            Write-Host "============================" -ForegroundColor Red
        }
        exit 1
    }
}

function Invoke-RemoteHealth {
    $cmd = "cd ${ProjectDir}; bash scripts/deploy/health.sh"

    Write-Section-Log "Execute remote health check"
    Write-Info-Log "Project dir: $ProjectDir"

    $result = Invoke-RemoteCommand -Server $Server -Port $Port -User $User -Password $Password -KeyPath $KeyPath -Command $cmd -Tool $script:SSHTool.Tool

    Write-Success-Log "Health check completed"
    if ($result.Output) {
        Write-Host ""
        Write-Host $result.Output
    }
}

function Invoke-RemoteBackup {
    $cmd = "cd ${ProjectDir}; bash scripts/deploy/backup.sh"

    Write-Section-Log "Execute remote data backup"
    Write-Info-Log "Project dir: $ProjectDir"

    $result = Invoke-RemoteCommand -Server $Server -Port $Port -User $User -Password $Password -KeyPath $KeyPath -Command $cmd -Tool $script:SSHTool.Tool

    if ($result.Success) {
        Write-Success-Log "Data backup successful!"
    }
    else {
        Write-Error-Log "Data backup failed!"
        if ($result.Output) {
            Write-Host $result.Output
        }
        exit 1
    }
}

function Invoke-RemoteRollback {
    if (-not $Version) {
        Write-Error-Log "Rollback requires version!"
        Write-Info-Log "Usage: .\deploy.ps1 rollback -Version 'commit-hash'"
        exit 1
    }

    $cmd = "cd ${ProjectDir}; bash scripts/deploy/rollback.sh $Version"

    Write-Section-Log "Execute remote version rollback"
    Write-Info-Log "Project dir: $ProjectDir"
    Write-Info-Log "Rollback version: $Version"

    $result = Invoke-RemoteCommand -Server $Server -Port $Port -User $User -Password $Password -KeyPath $KeyPath -Command $cmd -Tool $script:SSHTool.Tool

    if ($result.Success) {
        Write-Success-Log "Version rollback successful!"
    }
    else {
        Write-Error-Log "Version rollback failed!"
        exit 1
    }
}

function Invoke-RemoteStatus {
    $cmd = "cd ${ProjectDir}; bash scripts/deploy/deploy.sh status"

    Write-Section-Log "Get remote deployment status"
    Write-Info-Log "Project dir: $ProjectDir"

    $result = Invoke-RemoteCommand -Server $Server -Port $Port -User $User -Password $Password -KeyPath $KeyPath -Command $cmd -Tool $script:SSHTool.Tool

    Write-Success-Log "Status retrieved"
    if ($result.Output) {
        Write-Host ""
        Write-Host $result.Output
    }
}

function Invoke-RemoteData {
    if (-not $args) {
        Write-Info-Log "Usage: .\deploy.ps1 data 'SubCommand'"
        Write-Info-Log "Sub commands: usage, clean-logs, verify, migrate"
        exit 1
    }

    $subCommand = $args[0]
    $cmd = "cd ${ProjectDir}; bash scripts/deploy/deploy.sh data $subCommand"

    Write-Section-Log "Execute remote data volume management"
    Write-Info-Log "Project dir: $ProjectDir"
    Write-Info-Log "Sub command: $subCommand"

    $result = Invoke-RemoteCommand -Server $Server -Port $Port -User $User -Password $Password -KeyPath $KeyPath -Command $cmd -Tool $script:SSHTool.Tool

    if ($result.Output) {
        Write-Host $result.Output
    }
}

# ============================================================================
# Interactive Configuration
# ============================================================================

function Show-Usage {
    @"

Yuxi-Know Windows Remote Deployment Tool v1.0.0
==============================================

Usage:
  .\deploy.ps1 [command] [options]

Commands:
  init        Initialize remote deployment environment
  update      Update remote deployment (pull code + restart services)
  health      Check remote service health status
  backup      Backup remote data
  rollback    Rollback to specific version
  status      View remote deployment status
  data        Remote data volume management

Options:
  -Server     Remote server address (required)
  -Port       SSH port (default: 22)
  -User       SSH username (required)
  -Password   SSH password (SSH key recommended)
  -KeyPath    SSH private key path (recommended)
  -ProjectDir Remote project directory (default: /opt/yuxi-know)
  -Branch     Git branch to deploy (default: repository default branch)
  -Force      Force execution (skip confirmation)
  -Quiet      Quiet mode (errors and warnings only)
  -Verbose    Verbose mode
  -ConfigFile Config file path
  -Version    Rollback version (for rollback command)

Environment Variable (AI auto execution):
  AI_MODE=true  Enable AI auto execution mode (batch SSH)

Examples:
  # First deployment
  .\deploy.ps1 init -Server 192.168.1.100 -User root -KeyPath C:\Users\user\.ssh\id_rsa
# First deployment with specific branch  .deploy.ps1 init -Server 192.168.1.100 -User root -KeyPath C:Usersuser.sshid_rsa -Branch "dev"

  # Update deployment
  .\deploy.ps1 update -Server 192.168.1.100 -User root -KeyPath C:\Users\user\.ssh\id_rsa

  # Health check
  .\deploy.ps1 health -Server 192.168.1.100 -User root -KeyPath C:\Users\user\.ssh\id_rsa

  # Use config file
  .\deploy.ps1 update -ConfigFile .\config\deploy.conf

  # AI auto execution
  `$env:AI_MODE=`"true`"
  .\deploy.ps1 update -Server 192.168.1.100 -User root -KeyPath C:\Users\user\.ssh\id_rsa

Config file example (config\deploy.conf):
  SSH_SERVER=192.168.1.100
  SSH_PORT=22
  SSH_USER=root
  SSH_KEY_PATH=C:\Users\user\.ssh\id_rsa
  PROJECT_DIR=/opt/yuxi-know

More docs: https://github.com/xerrors/Yuxi-Know

"@
}

function Read-ServerConfig {
    Write-Section-Log "Configure remote server connection"

    if ($ConfigFile -and (Test-Path $ConfigFile)) {
        Write-Info-Log "Loading from config: $ConfigFile"
        Load-Config -ConfigPath $ConfigFile
    }

    if (-not $script:Server) {
        $script:Server = Read-Host "Enter server address"
    }

    if (-not $script:Port) {
        $portInput = Read-Host "Enter SSH port (default: 22)"
        $script:Port = if ($portInput) { $portInput } else { "22" }
    }

    if (-not $script:User) {
        $script:User = Read-Host "Enter username"
    }

    if (-not $script:KeyPath -and -not $script:Password -and $env:AI_MODE -ne "true") {
        $useKey = Read-Host "Use SSH key? (Y/n)"
        if ($useKey -ne "n") {
            $defaultKeyPath = "$env:USERPROFILE\.ssh\id_rsa"
            $keyInput = Read-Host "Enter private key path (default: $defaultKeyPath)"
            $script:KeyPath = if ($keyInput) { $keyInput } else { $defaultKeyPath }
        }
        else {
            $script:Password = Read-Host "Enter password (WARNING: plaintext transmission, SSH key recommended)" -AsSecureString
            $script:Password = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto([System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($script:Password))
        }
    }

    if (-not $script:ProjectDir) {
        $projectInput = Read-Host "Enter project directory (default: /opt/yuxi-know)"
        $script:ProjectDir = if ($projectInput) { $projectInput } else { "/opt/yuxi-know" }
    }

    Write-Host ""
    Write-Host "======== Connection Config ========" -ForegroundColor Cyan
    Write-Host "Server:   ${script:Server}:${script:Port}"
    Write-Host "User:     ${script:User}"
    if ($script:KeyPath) { Write-Host "Auth:     SSH key (${script:KeyPath})" }
    else { Write-Host "Auth:     Password" }
    Write-Host "Directory: ${script:ProjectDir}"
    Write-Host "==================================" -ForegroundColor Cyan
    Write-Host ""

    $confirm = Read-Host "Confirm? (Y/n)"
    if ($confirm -eq "n") {
        exit 0
    }
}

# ============================================================================
# Main Function
# ============================================================================

function Main {
    if ($Command -eq "" -or $Command -eq "-h" -or $Command -eq "--help") {
        Show-Usage
        exit 0
    }

    $script:SSHTool = Test-SSHTool
    if (-not $script:SSHTool.Available) {
        exit 1
    }

    # Load config file (command-line parameters have priority)
    if ($ConfigFile -and (Test-Path $ConfigFile)) {
        Write-Info-Log "Loading config: $ConfigFile"
        Load-Config -ConfigPath $ConfigFile
    }

    # If still missing required parameters, prompt interactively
    if (-not $Server -or -not $User) {
        Read-ServerConfig
    }

    # Display configuration (including branch info)
    Write-Verbose "Server: ${Server}:${Port}"
    Write-Verbose "User: ${User}"
    Write-Verbose "Project Dir: ${ProjectDir}"
    Write-Verbose "Branch: ${Branch}"
    Write-Verbose "AI Mode: ${env:AI_MODE}"

    if ($Branch) {
        Write-Info-Log "Using branch: ${Branch}"
    }
    else {
        Write-Info-Log "Using repository default branch"
    }

    switch ($Command) {
        "init"    { Invoke-RemoteInit }
        "update"  { Invoke-RemoteUpdate }
        "health"  { Invoke-RemoteHealth }
        "backup"  { Invoke-RemoteBackup }
        "rollback" { Invoke-RemoteRollback }
        "status"  { Invoke-RemoteStatus }
        "data"    { Invoke-RemoteData -args $args }
        default   {
            Write-Error-Log "Unknown command: $Command"
            Show-Usage
            exit 1
        }
    }
}

Main
