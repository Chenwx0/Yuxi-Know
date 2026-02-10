# Yuxi-Know 部署脚本使用说明

## 概述

Yuxi-Know 提供了两套自动化部署脚本：

1. **Linux 部署脚本** (`scripts/deploy/deploy.sh`) - 在 Linux 服务器上直接运行
2. **Windows 远程部署脚本** (`scripts/deploy/deploy.ps1`) - 从 Windows 通过 SSH 远程部署到 Linux 服务器

---

## 一、Linux 部署脚本使用说明

### 环境要求

- **操作系统**: Ubuntu 20.04+, Debian 11+, CentOS 7+, RHEL 8+
- **必需软件**:
  - Docker 20.10+
  - Docker Compose v2+
  - Git 2.25+
  - bash 4.0+
- **硬件要求**:
  - 最小 4GB RAM (推荐 8GB+)
  - 最小 20GB 磁盘空间
  - CPU: 2核心+

### 脚本位置

```
scripts/deploy/
├── deploy.sh              # 主入口脚本
├── init.sh                # 首次初始化
├── update.sh              # 更新部署
├── health.sh              # 健康检查
├── backup.sh              # 数据备份
├── rollback.sh            # 版本回滚
├── manage_data_volumes.sh # 数据卷管理
├── config/
│   ├── deploy.conf        # 部署配置文件
│   └── windows-deploy.conf # Windows 远程部署配置
└── utils/
    ├── logger.sh          # 日志工具
    └── validator.sh       # 验证工具
```

### 主命令语法

```bash
bash scripts/deploy/deploy.sh [命令] [选项]
```

### 命令列表

#### 1. `init` - 首次初始化部署

在目标服务器上首次部署 Yuxi-Know。

```bash
# 基本用法（使用配置文件中的配置）
bash scripts/deploy/deploy.sh init

# 指定分支初始化
bash scripts/deploy/deploy.sh init --branch dev
bash scripts/deploy/deploy.sh init --branch feature/new-feature

# 强制模式（跳过确认）
bash scripts/deploy/deploy.sh init --force

# 静默模式（只输出错误和警告）
bash scripts/deploy/deploy.sh init --quiet

# 详细模式
bash scripts/deploy/deploy.sh init --verbose
```

**执行流程**:
1. 检查系统环境（Docker、Git 等）
2. 克隆代码仓库
3. 检查磁盘空间
4. 创建数据卷目录结构
5. 同步配置文件（从 `CONFIG_DIR` 到项目目录）
6. 启动所有 Docker 服务
7. 健康检查验证

#### 2. `update` - 更新部署

拉取最新代码并重启服务。

```bash
# 基本用法（使用配置文件中的分支）
bash scripts/deploy/deploy.sh update

# 更新到指定分支
bash scripts/deploy/deploy.sh update --branch dev
bash scripts/deploy/deploy.sh update --branch main

# 强制更新（跳过备份）
bash scripts/deploy/deploy.sh update --force --no-backup

# 仅执行备份
bash scripts/deploy/deploy.sh update --backup-only

# 组合使用
bash scripts/deploy/deploy.sh update --branch dev --verbose
```

**分支参数优先级** (从高到低):
1. 命令行 `--branch` 参数
2. 环境变量 `DEPLOY_BRANCH`
3. 配置文件 `config/deploy.conf` 中的 `GIT_BRANCH`
4. Git 仓库默认分支

**执行流程**:
1. 检查当前服务健康状态
2. 执行数据备份（除非 `--no-backup`）
3. 拉取最新代码并切换到指定分支
4. 同步配置文件
5. 重启 Docker 服务
6. 健康检查

#### 3. `health` - 健康检查

检查所有服务的运行状态。

```bash
# 基本检查
bash scripts/deploy/deploy.sh health

# 详细检查
bash scripts/deploy/deploy.sh health --detailed

# 尝试自动修复问题
bash scripts/deploy/deploy.sh health --fix

# 持续监控模式（每 30 秒检查一次）
bash scripts/deploy/deploy.sh health --watch

# 指定监控间隔
bash scripts/deploy/deploy.sh health --watch 60
```

#### 4. `backup` - 数据备份

备份所有数据库和应用数据。

```bash
# 执行完整备份
bash scripts/deploy/deploy.sh backup

# 组合选项
bash scripts/deploy/deploy.sh backup --verbose
```

**备份内容包括**:
- PostgreSQL 数据库
- Neo4j 图数据库
- MinIO 对象存储
- 应用保存的数据

#### 5. `rollback` - 版本回滚

回滚到指定版本。

```bash
# 回滚到指定 commit hash
bash scripts/deploy/deploy.sh rollback a1b2c3d4

# 回滚到指定 Git 标签（如果存在）
bash scripts/deploy/deploy.sh rollback v1.2.3
```

#### 6. `status` - 查看部署状态

显示当前部署的详细信息。

```bash
bash scripts/deploy/deploy.sh status
```

**输出内容**:
- Git 分支和提交信息
- Docker 容器运行状态
- 数据卷磁盘使用情况
- 部署历史记录

#### 7. `data` - 数据卷管理

管理数据卷的维护操作。

```bash
# 显示数据卷使用情况
bash scripts/deploy/deploy.sh data usage

# 清理日志文件
bash scripts/deploy/deploy.sh data clean-logs

# 验证数据卷完整性
bash scripts/deploy/deploy.sh data verify

# 迁移数据卷到新位置
bash scripts/deploy/deploy.sh data migrate
```

### 全局选项

| 选项 | 说明 |
|------|------|
| `--force` | 强制执行（跳过确认） |
| `--quiet` | 静默模式（只输出错误和警告） |
| `--verbose` | 详细模式（输出 DEBUG 日志） |
| `--branch` | 指定 Git 分支 |
| `--version` | 显示版本信息 |
| `--help` / `-h` | 显示帮助信息 |

### 配置文件

编辑 `scripts/deploy/config/deploy.conf` 来自定义部署配置：

```bash
# 项目配置
PROJECT_DIR="/app/yuxi-know"       # 项目代码目录
# 注意：GIT_REPO 需从系统环境变量读取（详见下方"Git 配置说明"）
# 注意：GIT_BRANCH 需从系统环境变量读取（详见下方"Git 配置说明"）

# 数据卷配置
DATA_ROOT="/app/data"               # 数据卷根目录

# 健康检查配置
HEALTH_CHECK_TIMEOUT=300            # 健康检查超时（秒）
HEALTH_CHECK_RETRIES=30             # 最大重试次数

# 备份配置
BACKUP_RETENTION_DAYS=7             # 备份保留天数

# 回滚配置
ROLLBACK_ENABLED=true               # 启用回滚
ROLLBACK_KEEP_COUNT=5               # 保留历史版本数
```

### Git 配置说明

Git 仓库地址和认证信息都需要通过系统环境变量设置。

#### Linux 本地部署

```bash
# 设置仓库地址（必需）
export GIT_REPO="https://github.com/Chenwx0/Yuxi-Know.git"
export GIT_BRANCH="dev"
# 或者使用 SSH 格式：
# export GIT_REPO="git@github.com:Chenwx0/Yuxi-Know.git"
export GIT_BRANCH="dev"

# 设置认证信息（私有仓库必需）
# 方式 1: Personal Access Token（推荐）
export GIT_AUTH_TOKEN="ghp_xxxxxxxxxxxxxxxxxxxx"

# 方式 3: 用户名密码（不推荐，仅用于测试）
# export GIT_USERNAME="your-username"
# export GIT_PASSWORD="your-password"

# 然后执行部署
bash scripts/deploy/deploy.sh init
```

**重要提示**：
- **GIT_REPO** 和 **GIT_BRANCH** 是必需的环境变量，必须先设置才能执行部署
- 所有 Git 相关配置（包括仓库地址和认证信息）都不应写入 `deploy.conf` 配置文件
- 环境变量只在当前 shell 会话有效，关闭后自动清除
- 对于长期运行的部署任务，可以将环境变量设置在 `~/.bashrc` 或 `/etc/environment` 中

#### Windows 远程部署

在 `windows-deploy.conf` 配置文件中设置 Git 配置信息：

```ini
# Git 配置
GIT_REPO=https://github.com/Chenwx0/Yuxi-Know.git
GIT_BRANCH=dev

# Git 认证信息（私有仓库必需）
GIT_AUTH_TOKEN=ghp_xxxxxxxxxxxxxxxxxxxx

# 或者使用用户名密码（不推荐）
# GIT_USERNAME=your-username
# GIT_PASSWORD=your-password
```

**执行部署**：

```powershell
.\scripts\deploy\deploy.ps1 init -ConfigFile .\scripts\deploy\config\windows-deploy.conf
```

脚本会自动将 GIT_REPO、GIT_BRANCH 和认证信息通过环境变量传递到远程 Linux 服务器执行部署，敏感信息不会持久化到配置文件中。

### 示例场景

#### 场景 1: 首次部署到生产环境

```bash
# 1. 设置环境变量
export GIT_REPO="https://github.com/Chenwx0/Yuxi-Know.git"
export GIT_BRANCH="dev"
export GIT_AUTH_TOKEN="ghp_xxxxxxxxxxxxxxxxxxxx"

# 2. 执行初始化
bash scripts/deploy/deploy.sh init --force

# 3. 检查服务状态
bash scripts/deploy/deploy.sh health --watch
```

#### 场景 2: 更新到新功能分支

```bash
# 设置环境变量
export GIT_REPO="https://github.com/Chenwx0/Yuxi-Know.git"
export GIT_BRANCH="dev"
export GIT_AUTH_TOKEN="ghp_xxxxxxxxxxxxxxxxxxxx"

# 更新到 feature/new-feature 分支
bash scripts/deploy/deploy.sh update --branch feature/new-feature

# 如果更新失败，回滚
bash scripts/deploy/deploy.sh rollback dev
```

#### 场景 3: 定期维护

```bash
# 检查健康状况
bash scripts/deploy/deploy.sh health --detailed

# 清理日志释放空间
bash scripts/deploy/deploy.sh data clean-logs

# 执行备份
bash scripts/deploy/deploy.sh backup
```

---

## 二、Windows 远程部署脚本使用说明

### 环境要求

**Windows 本机**:
- Windows 10/11
- PowerShell 5.1+
- SSH 客户端（默认已安装）或 PuTTY

**目标 Linux 服务器**:
- 满足 Linux 部署的所有要求
- SSH 服务已开启

### 使用方法

#### 方式 1: 命令行指定参数

```powershell
# 首次初始化远程部署
.\scripts\deploy\deploy.ps1 init `
    -Server "192.168.1.100" `
    -User "root" `
    -KeyPath "C:\Users\username\.ssh\id_rsa" `
    -ProjectDir "/app/yuxi-know"

# 更新远程部署
.\scripts\deploy\deploy.ps1 update `
    -Server "192.168.1.100" `
    -User "root" `
    -KeyPath "C:\Users\username\.ssh\id_rsa"

# 指定分支更新
.\scripts\deploy\deploy.ps1 update `
    -Server "192.168.1.100" `
    -User "root" `
    -KeyPath "C:\Users\username\.ssh\id_rsa" `
    -Branch "dev"
```

#### 方式 2: 使用配置文件

1. 创建配置文件 `scripts/deploy/config/windows-deploy.conf`:

```ini
# SSH 连接配置
SSH_SERVER=47.121.201.213
SSH_PORT=22
SSH_USER=root
SSH_KEY_PATH=D:\MyData\chenwx80.CN\.ssh\id_ed25519

# 项目路径配置
PROJECT_DIR=/app/yuxi-know

# Git 配置
GIT_REPO=https://github.com/Chenwx0/Yuxi-Know.git
# 对于私有仓库，设置以下认证信息（将通过环境变量传递到远程服务器）
# GIT_AUTH_TOKEN=ghp_xxxxxxxxxxxxxxxxxxxx

# 部署配置
GIT_BRANCH=dev
AI_MODE=true
LOG_LEVEL=INFO
ROLLBACK_ENABLED=true
ROLLBACK_KEEP_COUNT=1
OPEN_ALL_PORTS=true
```

2. 使用配置文件部署:

```powershell
# 首次初始化
.\scripts\deploy\deploy.ps1 init -ConfigFile .\scripts\deploy\config\windows-deploy.conf

# 更新部署
.\scripts\deploy\deploy.ps1 update -ConfigFile .\scripts\deploy\config\windows-deploy.conf

# 健康检查
.\scripts\deploy\deploy.ps1 health -ConfigFile .\scripts\deploy\config\windows-deploy.conf
```

#### 方式 3: AI 自动执行模式

```powershell
# 设置 AI 模式环境变量（非交互式）
$env:AI_MODE="true"

# 执行部署（不会提示输入任何信息）
.\scripts\deploy\deploy.ps1 update `
    -Server "192.168.1.100" `
    -User "root" `
    -KeyPath "C:\Users\username\.ssh\id_rsa"
```

### 常用命令

| 命令 | 说明 |
|------|------|
| `init` | 初始化远程部署环境 |
| `update` | 更新远程部署（拉取代码+重启） |
| `health` | 检查远程服务健康状态 |
| `backup` | 备份远程数据 |
| `rollback` | 回滚到指定版本 |
| `status` | 查看远程部署状态 |
| `data` | 远程数据卷管理 |

### 参数说明

| 参数 | 说明 | 必需 | 默认值 |
|------|------|------|--------|
| `-Server` | 远程服务器地址 | 是 | - |
| `-Port` | SSH 端口 | 否 | 22 |
| `-User` | SSH 用户名 | 是 | - |
| `-KeyPath` | SSH 私钥路径 | 是* | - |
| `-Password` | SSH 密码（不推荐） | 否 | - |
| `-ProjectDir` | 远程项目目录 | 否 | `/opt/yuxi-know` |
| `-Branch` | Git 分支 | 否 | 仓库默认分支 |
| `-Force` | 强制执行 | 否 | - |
| `-Quiet` | 静默模式 | 否 | - |
| `-Verbose` | 详细模式 | 否 | - |
| `-ConfigFile` | 配置文件路径 | 否 | - |
| `-Version` | 回滚版本（用于 rollback）| - | - |

*注：推荐使用 SSH 密钥认证，密码认证仅在不支持密钥时使用。

### SSH 密钥配置

#### 生成 SSH 密钥对（如果还没有）

```powershell
# 在 Windows 上生成密钥
ssh-keygen -t ed25519 -f $env:USERPROFILE\.ssh\id_ed25519

# 将公钥复制到服务器
type $env:USERPROFILE\.ssh\id_ed25519.pub | ssh root@192.168.1.100 "mkdir -p ~/.ssh && cat >> ~/.ssh/authorized_keys"
```

### 使用示例

#### 示例 1: 完整部署流程

```powershell
# 1. 检查远程服务健康状态
.\scripts\deploy\deploy.ps1 health `
    -Server "192.168.1.100" `
    -User "root" `
    -KeyPath "C:\Users\user\.ssh\id_rsa"

# 2. 执行远程备份
.\scripts\deploy\deploy.ps1 backup `
    -Server "192.168.1.100" `
    -User "root" `
    -KeyPath "C:\Users\user\.ssh\id_rsa"

# 3. 更新部署
.\scripts\deploy\deploy.ps1 update `
    -Server "192.168.1.100" `
    -User "root" `
    -KeyPath "C:\Users\user\.ssh\id_rsa" `
    -Branch "dev" `
    -Verbose

# 4. 验证部署状态
.\scripts\deploy\deploy.ps1 status `
    -Server "192.168.1.100" `
    -User "root" `
    -KeyPath "C:\Users\user\.ssh\id_rsa"
```

#### 示例 2: 使用配置文件自动化部署

```powershell
# 编辑配置文件
notepad .\scripts\deploy\config\windows-deploy.conf

# 自动部署
$env:AI_MODE="true"
.\scripts\deploy\deploy.ps1 update -ConfigFile .\scripts\deploy\config\windows-deploy.conf
```

---

## 三、常见问题

### Q1: 如何查看详细日志?

```bash
# Linux: 使用 --verbose 选项
bash scripts/deploy/deploy.sh update --verbose

# Windows: 使用 -Verbose 参数
.\scripts\deploy\deploy.ps1 update -Server X.X.X.X -KeyPath X -Verbose

# 查看日志文件
cat logs/deploy/*.log
```

### Q2: 如何修改数据存储位置?

编辑 `config/deploy.conf`:

```bash
DATA_ROOT="/data/yuxi-know"  # 修改为持久目录
```

### Q3: 如何切换部署分支?

```bash
# 方式 1: 命令行指定
bash scripts/deploy/deploy.sh update --branch main

# 方式 2: 修改配置文件
vim scripts/deploy/config/deploy.conf  # 修改 GIT_BRANCH
bash scripts/deploy/deploy.sh update
```

### Q4: 更新失败如何回滚?

```bash
# 查看历史提交
cd /app/yuxi-know
git log --oneline

# 回滚到指定版本
bash scripts/deploy/deploy.sh rollback <commit-hash>
```

### Q5: 如何备份和恢复数据?

```bash
# 备份
bash scripts/deploy/deploy.sh backup

# 备份文件位于 ./backups/ 目录

# 恢复（手动操作）
docker compose down
cp -r backups/backup-YYYYMMDD/* /app/data/
docker compose up -d
```

### Q6: Docker Compose 版本问题?

```bash
# 检查版本
docker compose version

# 如果版本过低，升级
curl -SL https://github.com/docker/compose/releases/download/v2.24.6/docker-compose-linux-x86_64 -o /usr/local/bin/docker-compose
chmod +x /usr/local/bin/docker-compose
```

---

## 四、故障排查

### 1. 容器启动失败

```bash
# 查看容器日志
docker compose logs -f

# 查看特定服务日志
docker logs api-dev --tail 100
docker logs milvus --tail 100
```

### 2. 网络连接问题

```bash
# 检查网络
docker network ls
docker network inspect app-network

# 重建网络
docker compose down
docker network rm app-network
docker compose up -d
```

### 3. 磁盘空间不足

```bash
# 检查空间
df -h

# 清理数据卷日志
bash scripts/deploy/deploy.sh data clean-logs

# 清理 Docker
docker system prune -a
```

---

## 五、最佳实践

1. **使用配置文件**: 将常用配置保存到 `deploy.conf`
2. **定期备份**: 设置定时任务自动备份
3. **健康检查**: 更新后始终执行健康检查
4. **日志管理**: 定期清理日志释放空间
5. **权限控制**: 使用 SSH 密钥而非密码认证
6. **网络隔离**: 生产环境使用防火墙限制端口访问

### 设置定时备份（示例）

```bash
# 编辑 crontab
crontab -e

# 添加每天凌晨 2 点自动备份
0 2 * * * /app/yuxi-know/scripts/deploy/deploy.sh backup >> /var/log/yuxi-backup.log 2>&1
```

---

## 六、更多资源

- [项目文档](https://xerrors.github.io/Yuxi-Know/)
- [问题反馈](https://github.com/xerrors/Yuxi-Know/issues)
- [更新日志](CHANGELOG.md)
