# Windows 远程部署文档

## 概述

`deploy.ps1` 是一个 PowerShell 脚本，用于从 Windows 机器远程连接到 Linux 服务器执行部署操作。

## 前置条件

### 1. SSH 客户端

Windows 10/11 自带 OpenSSH 客户端。检查方法：

```powershell
ssh -V
```

如果未安装，可通过以下方式启用：

**Windows 10/11:**
1. 设置 → 应用 → 可选功能
2. 点击"添加功能"
3. 搜索"OpenSSH 客户端"并安装

**或使用 PowerShell 管理员权限：**
```powershell
Add-WindowsCapability -Online -Name OpenSSH.Client~~~~0.0.1.0
```

### 2. SSH 密钥认证（推荐）

生成 SSH 密钥：

```powershell
ssh-keygen -t ed25519 -C "your_email@example.com"
```

将公钥复制到服务器：

```powershell
type $env:USERPROFILE\.ssh\id_ed25519.pub | ssh user@server "cat >> ~/.ssh/authorized_keys"
```

### 3. PowerShell 执行策略

如果遇到执行策略限制，运行：

```powershell
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
```

---

## 快速开始

### 方法一: 交互式执行（手工操作）

```powershell
# 进入脚本目录
cd E:\git\chenwx\Yuxi-Know\scripts\deploy

# 运行部署脚本
.\deploy.ps1 update
```

按照提示输入服务器地址、用户名、密钥路径等信息。

### 方法二: 命令行参数

```powershell
# 使用 SSH 密钥认证（推荐）
.\deploy.ps1 init `
    -Server "192.168.1.100" `
    -User "root" `
    -KeyPath "C:\Users\username\.ssh\id_rsa"

# 更新部署
.\deploy.ps1 update `
    -Server "192.168.1.100" `
    -User "root" `
    -KeyPath "C:\Users\username\.ssh\id_rsa"

# 健康检查
.\deploy.ps1 health `
    -Server "192.168.1.100" `
    -User "root" `
    -KeyPath "C:\Users\username\.ssh\id_rsa"
```

### 方法三: 使用配置文件

1. 复制配置模板：
```powershell
copy config\windows-deploy.conf.template config\windows-deploy.conf
```

2. 编辑配置文件，填入实际配置：
```ini
SSH_SERVER=192.168.1.100
SSH_PORT=22
SSH_USER=root
SSH_KEY_PATH=C:\Users\username\.ssh\id_rsa
PROJECT_DIR=/opt/yuxi-know
```

3. 使用配置文件执行：
```powershell
.\deploy.ps1 update -ConfigFile config\windows-deploy.conf
```

### 方法四: AI 自动执行（无人值守）

适用于 AI 工具自动执行，无需用户交互。

**设置环境变量：**
```powershell
$env:AI_MODE = "true"
```

**完整命令：**
```powershell
$env:AI_MODE="true"
.\deploy.ps1 `
    -Command "update" `
    -Server "192.168.1.100" `
    -User "root" `
    -KeyPath "C:\Users\username\.ssh\id_rsa" `
    -ProjectDir "/opt/yuxi-know"
```

**在脚本中设置：**
```powershell
# 在 deploy.ps1 顶部添加
$env:AI_MODE = "true"
```

---

## 命令详解

### 1. init - 首次初始化部署

```powershell
# 交互式
.\deploy.ps1 init

# 命令行参数
.\deploy.ps1 init -Server 192.168.1.100 -User root -KeyPath C:\Users\user\.ssh\id_rsa

# 带强制模式
.\deploy.ps1 init -Server 192.168.1.100 -User root -KeyPath C:\Users\user\.ssh\id_rsa -Force
```

**执行内容：**
- 检查环境（Docker、磁盘空间等）
- 克隆代码仓库
- 创建数据卷目录
- 配置环境变量
- 拉取 Docker 镜像
- 构建项目镜像
- 启动服务

### 2. update - 更新部署

```powershell
# 交互式
.\deploy.ps1 update

# 命令行参数
.\deploy.ps1 update -Server 192.168.1.100 -User root -KeyPath C:\Users\user\.ssh\id_rsa

# 强制更新（跳过备份）
.\deploy.ps1 update -Server 192.168.1.100 -User root -KeyPath C:\Users\user\.ssh\id_rsa -SkipBackup -Force
```

**执行内容：**
- 检查服务健康状态
- 执行数据备份（可跳过）
- 拉取最新代码
- 执行数据库迁移
- 重新构建镜像（如需要）
- 零停机重启服务
- 健康检查

### 3. health - 健康检查

```powershell
.\deploy.ps1 health -Server 192.168.1.100 -User root -KeyPath C:\Users\user\.ssh\id_rsa
```

**检查内容：**
- 容器运行状态
- 服务健康端点
- 资源使用情况
- 日志错误检查

### 4. backup - 手动备份

```powershell
.\deploy.ps1 backup -Server 192.168.1.100 -User root -KeyPath C:\Users\user\.ssh\id_rsa
```

**备份内容：**
- PostgreSQL 数据库
- Neo4j 图数据库
- Milvus 向量数据库
- MinIO 存储数据
- 配置文件

### 5. rollback - 版本回滚

```powershell
# 回滚到指定版本
.\deploy.ps1 rollback `
    -Server 192.168.1.100 `
    -User root `
    -KeyPath C:\Users\user\.ssh\id_rsa `
    -Version "abc123def"
```

**版本号：**
- Git commit hash（完整或前 8 位）
- Git tag

### 6. status - 查看部署状态

```powershell
.\deploy.ps1 status -Server 192.168.1.100 -User root -KeyPath C:\Users\user\.ssh\id_rsa
```

**显示内容：**
- Git 信息（分支、提交、时间）
- Docker 容器状态
- 数据卷使用情况
- 最近部署历史

### 7. data - 数据卷管理

```powershell
# 查看数据卷使用情况
.\deploy.ps1 data usage -Server 192.168.1.100 -User root -KeyPath C:\Users\user\.ssh\id_rsa

# 清理日志
.\deploy.ps1 data clean-logs -Server 192.168.1.100 -User root -KeyPath C:\Users\user\.ssh\id_rsa

# 验证数据卷
.\deploy.ps1 data verify -Server 192.168.1.100 -User root -KeyPath C:\Users\user\.ssh\id_rsa

# 迁移数据卷
.\deploy.ps1 data migrate -Server 192.168.1.100 -User root -KeyPath C:\Users\user\.ssh\id_rsa
```

---

## AI 自动执行最佳实践

### 1. 推荐方式（密钥认证 + AI 模式）

```powershell
# 设置 AI 模式
$env:AI_MODE = "true"

# 执行部署
.\deploy.ps1 `
    -Command "update" `
    -Server "your-server-ip" `
    -User "username" `
    -KeyPath "C:\Users\username\.ssh\id_ed25519" `
    -ProjectDir "/opt/yuxi-know"
```

### 2. 创建快捷脚本

创建 `auto-deploy.ps1`：

```powershell
# auto-deploy.ps1

param(
    [string]$Command = "update",
    [string]$Server = "192.168.1.100",
    [string]$User = "root",
    [string]$KeyPath = "C:\Users\username\.ssh\id_ed25519",
    [string]$ProjectDir = "/opt/yuxi-know"
)

# 启用 AI 模式
$env:AI_MODE = "true"

# 执行部署
& "$PSScriptRoot\deploy.ps1" `
    -Command $Command `
    -Server $Server `
    -User $User `
    -KeyPath $KeyPath `
    -ProjectDir $ProjectDir `
    -Force
```

使用：
```powershell
.\auto-deploy.ps1 update
.\auto-deploy.ps1 health
.\auto-deploy.ps1 backup
```

### 3. 使用配置文件 + AI 模式

创建 `config\windows-deploy.conf`：
```ini
SSH_SERVER=192.168.1.100
SSH_PORT=22
SSH_USER=root
SSH_KEY_PATH=C:\Users\username\.ssh\id_ed25519
PROJECT_DIR=/opt/yuxi-know
AI_MODE=true
```

执行：
```powershell
$env:AI_MODE="true"
.\deploy.ps1 update -ConfigFile config\windows-deploy.conf
```

---

## 常见问题

### 1. SSH 连接失败

**问题提示：** "无法连接到服务器"

**解决方法：**
1. 检查服务器地址和端口是否正确
2. 确保服务器 SSH 服务已启动
3. 检查防火墙规则
4. 测试连接：`ssh -p 22 user@server`

### 2. 密钥认证失败

**问题提示：** "Permission denied (publickey)"

**解决方法：**
1. 确认私钥路径正确
2. 检查私钥权限：`(Get-Acl id_rsa).Access`
3. 确认公钥已添加到服务器：`cat ~/.ssh/authorized_keys`
4. 测试密钥：`ssh -i "C:\path\to\key" user@server`

### 3. 执行策略限制

**问题提示：** "无法加载，因为在此系统上禁止运行脚本"

**解决方法：**
```powershell
# 临时允许（仅当前会话）
Set-ExecutionPolicy -ExecutionPolicy Bypass -Scope Process

# 永久设置为 RemoteSigned（推荐）
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
```

### 4. 路径包含空格

**问题提示：** 路径解析错误

**解决方法：**
```powershell
# 使用双引号包裹路径
.\deploy.ps1 update -KeyPath "C:\Users\John Doe\.ssh\id_rsa"
```

### 5. 密码认证不推荐

**说明：** OpenSSH 不建议在命令行中直接传递密码

**推荐方法：** 使用 SSH 密钥认证

**临时方案：** 安装 PuTTY 并使用 Plink
```
- 下载 PuTTY: https://www.putty.org/
- 使用参数: -Password "your-password"
```

---

## 高级用法

### 1. 批量部署多台服务器

```powershell
# servers.txt
192.168.1.100
192.168.1.101
192.168.1.102

# batch-deploy.ps1
$servers = Get-Content "servers.txt"
$env:AI_MODE = "true"

foreach ($server in $servers) {
    Write-Host "部署到 $server" -ForegroundColor Cyan
    .\deploy.ps1 `
        -Command "update" `
        -Server $server `
        -User "root" `
        -KeyPath "C:\Users\username\.ssh\id_rsa"
}
```

### 2. 定时部署（Windows 任务计划程序）

1. 打开"任务计划程序"
2. 创建基本任务
3. 触发器：每天/每周
4. 操作：启动程序
5. 程序：`powershell.exe`
6. 参数：
```
-ExecutionPolicy Bypass -File "E:\git\chenwx\Yuxi-Know\scripts\deploy\auto-deploy.ps1" -Command "update"
```

### 3. 集成到 CI/CD

**示例：GitHub Actions**

```yaml
name: Deploy to Production

on:
  push:
    branches: [ main ]

jobs:
  deploy:
    runs-on: windows-latest
    steps:
      - uses: actions/checkout@v3

      - name: Setup SSH Key
        run: |
          echo "${{ secrets.SSH_PRIVATE_KEY }}" > id_rsa
          chmod 600 id_rsa

      - name: Deploy
        run: |
          $env:AI_MODE = "true"
          ./scripts/deploy/deploy.ps1 `
            -Command "update" `
            -Server "${{ secrets.SERVER_IP }}" `
            -User "${{ secrets.SERVER_USER }}" `
            -KeyPath "id_rsa"
```

---

## 参数参考

| 参数 | 类型 | 必填 | 默认值 | 说明 |
|------|------|------|--------|------|
| `-Command` | string | 否 | - | 部署命令 (init/update/health...) |
| `-Server` | string | 否* | - | 服务器地址 |
| `-Port` | string | 否 | 22 | SSH 端口 |
| `-User` | string | 否* | - | SSH 用户名 |
| `-Password` | string | 否 | - | SSH 密码（不推荐） |
| `-KeyPath` | string | 否 | - | SSH 私钥路径（推荐） |
| `-ProjectDir` | string | 否 | /opt/yuxi-know | 远程项目目录 |
| `-Force` | switch | 否 | false | 强制执行（跳过确认） |
| `-Quiet` | switch | 否 | false | 静默模式 |
| `-Verbose` | switch | 否 | false | 详细模式 |
| `-ConfigFile` | string | 否 | config/deploy.conf | 配置文件路径 |
| `-Version` | string | 否 | - | 回滚版本号 |

* 必填项可通过配置文件或交互式输入提供

---

## 安全建议

1. **使用 SSH 密钥认证**，避免密码明文传输
2. **限制 SSH 访问 IP**，使用防火墙规则
3. **定期更新 SSH 密钥**，轮换密钥
4. **使用配置文件时**，确保文件权限正确，避免泄露
5. **生产环境启用防火墙**，限制 22 端口访问
6. **定期备份数据**，测试恢复流程

---

## 故障排查

### 查看详细日志

```powershell
# 启用详细模式
.\deploy.ps1 update -Verbose -Server ....

# 查看 SSH 连接日志
$env:GIT_SSH_COMMAND = "ssh -vvv"
.\deploy.ps1 update -Server ....
```

### 直接 SSH 到服务器排查

```powershell
# 使用相同参数连接
ssh -i "C:\path\to\key" -p 22 user@server

# 检查 Docker 状态
docker ps
docker compose ps

# 查看服务日志
docker compose logs -f

# 检查部署脚本
cd /opt/yuxi-know
bash scripts/deploy/deploy.sh status
```

---

## 相关文档

- [Linux 部署文档](./DEPLOYMENT.md)
- [项目文档](https://github.com/xerrors/Yuxi-Know)
- [Docker Compose 文档](https://docs.docker.com/compose/)
