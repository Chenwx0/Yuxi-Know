# Yuxi-Know Linux 自动化部署文档

## 概述

Yuxi-Know 提供了一套完整的自动化部署脚本，支持快速初始化、更新、健康检查、备份和回滚操作。所有脚本基于 Bash 编写，遵循 DRY 原则，使用统一的配置和日志系统。

---

## 目录结构

```
scripts/deploy/
├── deploy.sh              # 主入口脚本（命令路由）
├── init.sh                # 首次首次初始化部署
├── update.sh              # 更新部署（支持零停机）
├── health.sh              # 服务健康检查
├── backup.sh              # 数据备份
├── rollback.sh            # 版本回滚
├── manage_data_volumes.sh # 数据卷管理
├── config/
│   └── deploy.conf        # 部署配置文件
└── utils/
    ├── logger.sh          # 日志工具函数
    └── validator.sh       # 环境验证工具
```

---

## 快速开始

### 环境要求

- **操作系统**: Linux (Ubuntu 20.04+, CentOS 7+, Debian 10+, Fedora 35+)
- **磁盘空间**: 至少 10GB 可用空间
- **内存**: 建议 4GB+
- **sudo 权限**: 用于自动安装 Docker 和 Docker Compose（如未安装）

### 首次部署

部署脚本支持**自动检测和安装 Docker、Docker Compose 和 Git**，无需手动安装依赖。

```bash
# 克隆仓库（如果未安装 Git，可以使用 wget/curl 下载）
git clone https://github.com/Chenwx0/Yuxi-Know.git
cd Yuxi-Know

# 执行初始化（会自动检测并提示安装缺失的依赖）
bash scripts/deploy/deploy.sh init
```

#### 自动安装功能

初始化时会自动检查以下依赖，如果未安装会提示：

| 依赖 | 检测命令 | 自动安装 |
|------|----------|----------|
| Docker | `docker --version` | ✅ 支持 Ubuntu/Debian/CentOS/RHEL/Fedora |
| Docker Compose | `docker compose version` | ✅ 支持 Ubuntu/Debian/CentOS/RHEL/Fedora |
| Git | `git --version` | ✅ 支持 Ubuntu/Debian/CentOS/RHEL/Fedora |

**安装提示示例**:
```bash
⚠️  Docker 未安装

Yuxi-Know 需要 Docker 来运行容器化服务。

您可以：

  1) 自动安装 Docker（推荐）
  2) 手动安装 Docker：https://docs.docker.com/get-docker/
  3) 跳过检查（不推荐）

是否自动安装 Docker? (Y/n):
```

#### 注意事项

1. **sudo 权限**: 自动安装需要 sudo 权限，脚本会自动检测并使用
2. **用户组**: Docker 安装后会自动添加当前用户到 `docker` 组，需要执行 `newgrp docker` 或重新登录生效
3. **网络访问**: 自动安装需要访问 Docker 官方仓库

```bash
# 克隆仓库
git clone https://github.com/Chenwx0/Yuxi-Know.git
cd Yuxi-Know

# 执行初始化
bash scripts/deploy/deploy.sh init
```

---

## 命令详解

### 1. init - 首次初始化部署

**用途**: 在全新环境中部署 Yuxi-Know

```bash
# 基本用法
bash scripts/deploy/deploy.sh init

# 强制模式（跳过确认）
bash scripts/deploy/deploy.sh init --force
```

**执行流程**:
1. 环境预检（Docker、磁盘空间、端口等）
2. 初始化数据卷目录
3. 克隆/拉取代码仓库
4. 配置环境变量（.env 文件）
5. **配置系统防火墙**（自动检测并开放必需端口）
6. 拉取 Docker 镜像
7. 构建自定义镜像（api、web）
8. 启动所有服务
9. 执行数据库初始化（如需要）

**输出**:
```
┌─────────────────────────────────────────────────────────────┐
│  ✅ Yuxi-Know 部署初始化完成！                            │
└─────────────────────────────────────────────────────────────┘

📍 项目信息:
  项目目录: /opt/yuxi-know
  数据目录: ./data-volume
  Git 仓库: https://github.com/Chenwx0/Yuxi-Know.git
  Git 分支: main

🌐 访问地址:
  - 前端: http://localhost:5173
  - 后端 API: http://localhost:5050
  - API 文档: http://localhost:5050/docs
  - Neo4j Browser: http://localhost:7474
  - MinIO Console: http://localhost:9001
```

---

### 2. update - 更新部署

**用途**: 拉取最新代码并重启服务（支持零停机）

```bash
# 标准更新（带备份）
bash scripts/deploy/deploy.sh update

# 强制更新（跳过备份确认）
bash scripts/deploy/deploy.sh update --force

# 跳过备份（快速更新）
bash scripts/deploy/deploy.sh update --no-backup

# 仅备份（不执行更新）
bash scripts/deploy/deploy.sh update --backup-only
```

**更新流程**:
1. 检查当前服务健康状态
2. 执行数据备份
3. 检查代码更新
4. 显示变更摘要（文件数量、变更类型）
5. 应用代码更新
6. 执行数据库迁移（如需要）
7. 重新构建镜像（如需要）
8. 零停机重启服务（先web后api）
9. 执行更新后脚本
10. 健康检查
11. 自动回滚（失败时，可启用）

**变更检测**:
- 🐳 Dockerfile 变更 → 重新构建镜像
- 🗄️ 数据库迁移文件 → 执行 Alembic 迁移
- ⚙️ 环境变量模板变更 → 提示检查配置
- 📦 Python 依赖变更 → 自动更新依赖

**零停机策略**:
```bash
# 1. 先重启前端（快速）
docker compose restart web
wait_for_service web 30s

# 2. 再重启后端（数据库先就绪）
docker compose restart api
wait_for_service api 60s
```

---

### 3. health - 健康检查

**用途**: 检查服务运行状态和健康度

```bash
# 基本检查
bash scripts/deploy/deploy.sh health

# 详细模式（显示更多信息）
bash scripts/deploy/deploy.sh health --detailed

# 自动修复异常
bash scripts/deploy/deploy.sh health --fix

# 监控模式（持续刷新）
bash scripts/deploy/deploy.sh health --watch
bash scripts/deploy/deploy.sh health --watch 30  # 30秒间隔
```

**检查项**:
- ✅ 容器运行状态
- ✅ API 健康端点
- ✅ 前端访问
- ✅ PostgreSQL 连接
- ✅ Neo4j 连接
- ✅ Milvus 连接
- ✅ 资源使用（CPU、内存）
- ✅ 数据卷完整性
- ✅ Docker 网络配置

**详细输出示例**:
```
┌─────────────────────────────────────────────────────────────┐
│  ✅ 所有检查通过！系统运行正常                            │
└─────────────────────────────────────────────────────────────┘

系统状态:
  - 所有容器运行正常
  - API 服务健康
  - 前端可访问
  - 数据库连接正常
  - 网络配置正确
```

---

### 4. backup - 数据备份

**用途**: 备份所有重要数据

```bash
# 完整备份
bash scripts/deploy/deploy.sh backup

# 快速备份（跳过 MinIO 和 saves）
bash scripts/deploy/deploy.sh backup --quick

# 不压缩
bash scripts/deploy/deploy.sh backup --no-compress

# 上传到远程
bash scripts/deploy/deploy.sh backup --remote user@remote:/backups

# 试运行（查看将备份什么）
bash scripts/deploy/deploy.sh backup --dry-run
```

**备份内容**:
| 组件 | 备份方式 | 说明 |
|------|----------|------|
| PostgreSQL | `pg_dump` | SQL 文件（可压缩） |
| Neo4j | `neo4j-admin dump` / `cypher-shell` | dump 文件 + Cypher 导出 |
| Milvus | 配置文件 + 元数据 | 不包含向量数据 |
| MinIO | `mc mirror` | 对象存储完整备份 |
| 配置文件 | 文件复制 | .env, docker-compose.yml |
| 数据卷 | 目录结构记录 | 元信息和大小统计 |

**备份目录结构**:
```
backups/
└── 20240205_143022/
    ├── data_volumes_info.txt      # 备份元信息
    ├── data_volume_structure.txt  # 目录结构
    ├── postgres.sql.gz            # PostgreSQL 备份
    ├── neo4j.dump                 # Neo4j dump
    ├── neo4j.cypher.gz            # Neo4j Cypher 导出
    ├── milvus.conf                # Milvus 配置
    ├── configs/                   # 配置文件
    │   ├── .env
    │   └── docker-compose.yml
    └── saves/                     # saves 目录
```

**保留策略**:
- 默认保留 7 天
- 自动清理过期备份
- 可在 `deploy.conf` 中配置 `BACKUP_RETENTION_DAYS`

---

### 5. rollback - 版本回滚

**用途**: 回滚到指定版本或从备份恢复数据

```bash
# 回滚到指定版本
bash scripts/deploy/deploy.sh rollback abc123def

# 回滚并恢复数据
bash scripts/deploy/deploy.sh rollback abc123def --data

# 从指定备份恢复数据
bash scripts/deploy/deploy.sh rollback --backup 20240205_143022

# 交互式选择版本（不指定版本号）
bash scripts/deploy/deploy.sh rollback
```

**回滚流程**:
1. 显示可用版本历史
2. 确认回滚操作（需要输入 "YES"）
3. 自动备份当前状态
4. 执行数据恢复（如果启用）
5. 切换代码到目标版本
6. 重新构建镜像
7. 按顺序重启服务（数据库 → 应用）
8. 健康检查

**安全机制**:
- 当前状态自动备份到 `backups/before_rollback_<commit>`
- 数据恢复前二次确认（需要输入 "RESTORE"）
- 失败时提供回滚路径

---

### 6. status - 查看部署状态

**用途**: 查看当前部署的详细信息

```bash
bash scripts/deploy/deploy.sh status
```

**输出示例**:
```
┌─────────────────────────────────────────────────────────────┐
│  部署状态                                                   │
└─────────────────────────────────────────────────────────────┘

Git 信息:
  分支: main
  提交: abc123def456789
  作者: John Doe <john@example.com>
  时间: 2024-02-05 14:30:22 +0800

Docker 容器状态:
  api-dev: Up 2 hours
  web-dev: Up 2 hours
  postgres: Up 2 days
  neo4j: Up 2 days
  milvus: Up 2 days

数据卷信息:
  根目录: /opt/yuxi-know/data-volume
  磁盘使用: 8.5G

最近部署历史:
  2024-02-05T14:30:22+08:00 | init | abc123def | 首次初始化部署
  2024-02-06T10:15:00+08:00 | update | def456abc | 日常更新
```

---

### 7. data - 数据卷管理

**用途**: 管理数据卷的维护操作

```bash
# 查看数据卷使用情况
bash scripts/deploy/deploy.sh data usage

# 清理日志
bash scripts/deploy/deploy.sh data clean-logs

# 验证数据卷完整性
bash scripts/deploy/deploy.sh data verify

# 迁移数据卷到新位置
bash scripts/deploy/deploy.sh data migrate
```

---

## 配置文件

### deploy.conf

位置：`scripts/deploy/config/deploy.conf`

```bash
# ============================ 项目配置 ============================
PROJECT_NAME="Yuxi-Know"
PROJECT_DIR="/opt/yuxi-know"
GIT_REPO="https://github.com/Chenwx0/Yuxi-Know.git"
GIT_BRANCH="main"

# ============================ 数据卷配置 ============================

# 数据卷根目录（所有容器挂载的目录都基于此根目录）
DATA_ROOT="/app/data"

# 实际数据目录（基于 DATA_ROOT）
SAVES_DIR="${DATA_ROOT}/saves"
MODELS_DIR="${DATA_ROOT}/models"
CONFIG_DIR="${DATA_ROOT}/config"
LOGS_DIR="${DATA_ROOT}/logs"

# 数据库数据目录（基于 DATA_ROOT）
POSTGRES_DATA_DIR="${DATA_ROOT}/postgres"
NEO4J_DATA_DIR="${DATA_ROOT}/neo4j"
MILVUS_DATA_DIR="${DATA_ROOT}/milvus"
PADDLEX_DATA_DIR="${DATA_ROOT}/paddlex"

# 数据目录结构定义（用于初始化检查和验证）
DATA_DIRECTORIES=(
    # 数据库数据目录
    "${POSTGRES_DATA_DIR}"
    "${NEO4J_DATA_DIR}"
    "${MILVUS_DATA_DIR}"
    "${PADDLEX_DATA_DIR}"

    # 应用数据目录
    "${SAVES_DIR}"
    "${MODELS_DIR}"

    # 配置和日志目录
    "${CONFIG_DIR}/env"
    "${LOGS_DIR}/docker"

    # Neo4j 子目录
    "${DATA_ROOT}/neo4j/data"
    "${DATA_ROOT}/neo4j/logs"

    # Milvus 子目录
    "${DATA_ROOT}/milvus/etcd"
    "${DATA_ROOT}/milvus/minio"
    "${DATA_ROOT}/milvus/minio_config"
    "${DATA_ROOT}/milvus/logs"
)

# ============================ 服务配置 ============================
COMPOSE_FILE="docker-compose.yml"
SERVICE_NAMES=("api" "web" "postgres" "neo4j" "milvus" "minio")

# ============================ 健康检查配置 ============================
HEALTH_CHECK_TIMEOUT=300
HEALTH_CHECK_INTERVAL=10
HEALTH_CHECK_RETRIES=30

# ============================ 备份配置 ============================
BACKUP_DIR="./backups"
BACKUP_RETENTION_DAYS=7
BACKUP_DATABASES=("postgres" "neo4j" "milvus")

# ============================ 日志配置 ============================
LOG_DIR="./logs/deploy"
LOG_LEVEL="INFO"

# ============================ 回滚配置 ============================
ROLLBACK_ENABLED=true
ROLLBACK_KEEP_COUNT=5

# ============================ 磁盘空间要求 ============================
REQUIRED_DISK_SPACE_GB=20

# ============================ 网络配置 ============================
NETWORK_NAME="app-network"
```

### 防火墙配置

初始化部署时，脚本会自动检测并配置防火墙开放必需端口。

#### 支持的防火墙类型
- **firewalld** (CentOS/RHEL/Fedora)
- **ufw** (Ubuntu/Debian)
- **iptables** (其他 Linux 发行版)

#### 自动开放的端口
**必需端口（自动开放）**:
- `80/tcp` - 前端 Web
- `443/tcp` - 前端 Web HTTPS

**可选端口（需交互确认）**:
- `5050/tcp` - API
- `5432/tcp` - PostgreSQL
- `7474/tcp` - Neo4j HTTP
- `7687/tcp` - Neo4j Bolt
- `19530/tcp` - Milvus
- `9000/tcp` - MinIO API
- `9001/tcp` - MinIO Console
- `30000/tcp` - MinerU VLLM
- `30001/tcp` - MinerU API
- `8080/tcp` - PaddleX OCR

---

## 日志系统

### 日志级别

- `DEBUG`: 调试信息
- `INFO`: 一般信息
- `SUCCESS`: 成功消息
- `WARNING`: 警告信息
- `ERROR`: 错误信息
- `CRITICAL`: 严重错误

### 日志输出

```bash
# 默认输出到控制台
bash scripts/deploy/deploy.sh init

# 启用详细模式
bash scripts/deploy/deploy.sh init --verbose

# 静默模式（只显示错误和警告）
bash scripts/deploy/deploy.sh init --quiet

# 日志文件位置
./logs/deploy/deploy.log
```

### 日志格式示例

```
[2024-02-05 14:30:22] [INFO] 开始首次初始化部署...
[2024-02-05 14:30:22] [INFO] 部署配置:
[2024-02-05 14:30:22] [INFO]   项目名称: Yuxi-Know
[2024-02-05 14:30:22] [SUCCESS] ✅ 所有检查通过
[2024-02-05 14:30:23] [INFO] 拉取 Docker 镜像...
[2024-02-05 14:31:05] [SUCCESS] ✅ Docker 镜像拉取完成
```

---

## 系统管理命令

### Docker 服务管理

服务器重启后 Docker 会自动启动。以下是 Docker 服务的常用管理命令：

```bash
# 查看 Docker 服务状态
systemctl status docker

# 启动 Docker 服务
systemctl start docker

# 停止 Docker 服务
systemctl stop docker

# 重启 Docker 服务
systemctl restart docker

# 启用 Docker 开机自启动（初始化时已自动配置）
systemctl enable docker

# 禁用 Docker 开机自启动
systemctl disable docker

# 查看 Docker 服务是否已设置开机自启
systemctl is-enabled docker
# 输出: enabled (已启用) 或 disabled (未启用)
```

### Yuxi-Know 服务容器管理

初始化部署时会创建 systemd 服务 `yuxi-know.service`，确保服务器重启后所有容器自动启动。

```bash
# 查看 Yuxi-Know 服务状态
systemctl status yuxi-know.service

# 启动 Yuxi-Know 服务
systemctl start yuxi-know.service

# 停止 Yuxi-Know 服务
systemctl stop yuxi-know.service

# 重启 Yuxi-Know 服务
systemctl restart yuxi-know.service

# 查看 Yuxi-Know 服务是否已设置开机自启
systemctl is-enabled yuxi-know.service
# 输出: enabled (已启用) 或 disabled (未启用)

# 启用 Yuxi-Know 开机自启动（初始化时已自动配置）
systemctl enable yuxi-know.service

# 禁用 Yuxi-Know 开机自启动
systemctl disable yuxi-know.service

# 查看 Yuxi-Know 服务日志
journalctl -u yuxi-know.service -f
```

### 服务文件位置

systemd 服务文件位于：
```
/etc/systemd/system/yuxi-know.service
```

服务文件内容示例：
```ini
[Unit]
Description=Yuxi-Know Docker Compose Services
After=docker.service
Requires=docker.service

[Service]
Type=oneshot
RemainAfterExit=yes
WorkingDirectory=/opt/yuxi-know
ExecStart=/usr/bin/docker compose -f /opt/yuxi-know/docker-compose.yml up -d
ExecStop=/usr/bin/docker compose -f /opt/yuxi-know/docker-compose.yml down
TimeoutStartSec=0

[Install]
WantedBy=multi-user.target
```

### 容器级别管理

除了 systemd 服务命令，也可以直接使用 `docker compose` 管理容器：

```bash
# 进入项目目录
cd /opt/yuxi-know

# 查看容器状态
docker compose ps

# 启动所有容器（如果已停止）
docker compose start

# 停止所有容器
docker compose stop

# 重启所有容器
docker compose restart

# 重启指定服务
docker compose restart api
docker compose restart web
docker compose restart postgres

# 查看所有容器日志
docker compose logs -f

# 查看指定服务日志
docker compose logs -f api
docker compose logs -f postgres

# 查看最近 100 行日志
docker compose logs --tail=100

# 查看容器资源使用
docker compose top
docker stats
```

### 常用运维场景

**场景 1: 修改代码后重启服务**
```bash
# 重启应用服务（保留数据库等服务）
docker compose restart api web

# 或使用 systemd 服务
systemctl restart yuxi-know.service
```

**场景 2: 完全停止所有服务**
```bash
# 停止 systemd 服务（会停止所有容器）
systemctl stop yuxi-know.service

# 或使用 docker compose
docker compose down
```

**场景 3: 完全重新启动所有服务**
```bash
# 使用 systemd 服务
systemctl restart yuxi-know.service

# 或使用 docker compose
docker compose down
docker compose up -d
```

**场景 4: 查看服务启动失败原因**
```bash
# 查看 systemd 服务日志
journalctl -u yuxi-know.service -n 50

# 查看容器日志
docker compose logs api
docker compose logs web
```

**场景 5: 测试开机自启**
```bash
# 1. 停止所有服务
systemctl stop yuxi-know.service

# 2. 验证 Docker 服务已启用
systemctl is-enabled docker
# 输出应: enabled

# 3. 验证 Yuxi-Know 服务已启用
systemctl is-enabled yuxi-know.service
# 输出应: enabled

# 4. 重启系统
sudo reboot

# 5. 系统重启后验证
systemctl status docker
systemctl status yuxi-know.service
docker compose ps
```

### 权限问题

如果运行 `docker compose` 命令时遇到权限错误：

```bash
# 方案 1: 使用 sudo（临时解决）
sudo docker compose ps

# 方案 2: 添加用户到 docker 组（推荐）
sudo usermod -aG docker $USER
newgrp docker  # 立即生效，或注销后重新登录

# 方案 3: 使用 systemd 服务（避免权限问题）
systemctl start yuxi-know.service
```

---

## 自动安装依赖

### 工作原理

部署脚本在执行 `init` 命令时会自动检查以下依赖：
- Docker
- Docker Compose (v2 插件版本)
- Git

如果检测到依赖未安装，脚本会显示提示信息并询问是否自动安装。

### 支持的操作系统

| 发行版 | 支持版本 |
|--------|----------|
| Ubuntu | 20.04+ |
| Debian | 10+ |
| CentOS | 7+ |
| RHEL | 7+ |
| Fedora | 35+ |

### 安装流程

1. **检测操作系统** - 读取 `/etc/os-release` 识别发行版
2. **权限检查** - 确认用户有 sudo 权限
3. **执行安装** - 使用系统包管理器安装依赖
4. **服务启动** - 自动启动并启用 Docker 服务
5. **用户组配置** - 添加当前用户到 docker 组
6. **验证安装** - 检查安装是否成功

### 交互示例

```bash
$ bash scripts/deploy/deploy.sh init

[2024-02-05 14:30:00] [INFO] 执行环境预检...
[2024-02-05 14:30:00] [INFO] 检查系统环境...
[2024-02-05 14:30:00] [INFO] 操作系统: Ubuntu 22.04.3 LTS
[2024-02-05 14:30:00] [INFO] 检查 Docker...
[2024-02-05 14:30:00] [WARNING] ⚠️  Docker 未安装

Yuxi-Know 需要 Docker 来运行容器化服务。

您可以：

  1) 自动安装 Docker（推荐）
  2) 手动安装 Docker：https://docs.docker.com/get-docker/
  3) 跳过检查（不推荐）

是否自动安装 Docker? (Y/n): Y

================================================================================
                          自动安装 Docker
================================================================================
[2024-02-05 14:30:05] [INFO] 检测到操作系统: Ubuntu 22.04.3 LTS
[2024-02-05 14:30:05] [INFO] 安装 Docker (Ubuntu/Debian)...
[2024-02-05 14:31:30] [SUCCESS] ✅ Docker 安装完成
[2024-02-05 14:31:30] [INFO] 启动 Docker 服务...
[2024-02-05 14:31:31] [INFO] 添加用户 ubuntu 到 docker 组...
[2024-02-05 14:31:31] [WARNING] ⚠️  请执行 'newgrp docker' 或注销后重新登录以使组权限生效
[2024-02-05 14:31:31] [SUCCESS] ✅ Docker 安装成功！版本: 24.0.7
[2024-02-05 14:31:31] [INFO]
[2024-02-05 14:31:31] [INFO] ========================================
[2024-02-05 14:31:31] [INFO] 需要执行以下命令使权限生效：
[2024-02-05 14:31:31] [INFO]   newgrp docker
[2024-02-05 14:31:31] [INFO] 或注销并重新登录
[2024-02-05 14:31:31] [INFO] ========================================
[2024-02-05 14:31:31] [INFO]
是否现在继续部署？(y/N): Y
[2024-02-05 14:31:33] [SUCCESS] ✅ Docker 可用
```

### 注意事项

#### Docker 用户组权限

Docker 安装后，当前用户需要重新登录才能获得 docker 组权限：

```bash
# 方法 1: 使组权限立即生效（推荐）
newgrp docker

# 方法 2: 注销并重新登录
# logout 后再 login

# 方法 3: 使用 sudo 临时执行（不推荐）
sudo docker ps
```

#### 网络要求

自动安装需要访问以下地址：
- Docker 官方 GPG key: `download.docker.com`
- Docker 仓库: `download.docker.com`
- CentOS/RHEL 仓库: ` mirrors.centos.org` 或 `yum.repos.d`

如果网络受限，请手动安装或配置镜像源。

#### 手动安装 Docker

如果自动安装失败，可以手动安装：

**Ubuntu/Debian:**
```bash
curl -fsSL https://get.docker.com | sh
sudo usermod -aG docker $USER
newgrp docker
```

**CentOS/RHEL:**
```bash
sudo yum install -y yum-utils
sudo yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
sudo yum install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
sudo systemctl start docker
sudo systemctl enable docker
sudo usermod -aG docker $USER
newgrp docker
```

#### Docker Compose 版本说明

脚本自动安装 Docker Compose v2（插件版本），使用以下命令：

```bash
# v2 插件版本（推荐）
docker compose version

# v1 独立版本（已弃用，不建议使用）
docker-compose --version
```

---

## 常见问题

### 1. Docker 权限问题

**问题**: `Permission denied when trying to connect to the Docker daemon socket`

**解决**:
```bash
# 添加用户到 docker 组
sudo usermod -aG docker $USER

# 刷新用户组
newgrp docker

# 或重启再登录
```

### 2. 端口被占用

**问题**: `Port 5173 is already in use`

**解决**:
```bash
# 查看占用端口的进程
lsof -i :5173
netstat -tuln | grep :5173

# 停止占用进程
kill <pid>

# 或修改 docker-compose.yml 中的端口映射
```

### 3. 磁盘空间不足

**问题**: `No space left on device`

**解决**:
```bash
# 查看磁盘使用
df -h

# 清理 Docker 未使用的资源
docker system prune -a

# 查看数据卷大小
du -sh ./data-volume

# 清理旧备份（保留 3 天）
find ./backups -maxdepth 1 -type d -mtime +3 -exec rm -rf {} \;
```

### 4. 健康检查失败

**问题**: 服务启动后健康检查失败

**解决**:
```bash
# 查看详细容日志
docker compose logs -f api
docker compose logs -f web

# 进入容器排查
docker compose exec api bash

# 检查环境变量
docker compose exec api env

# 手动执行健康检查
curl http://localhost:5050/api/system/health
```

### 5. 更新失败后恢复

**问题**: `update` 命令执行失败

**解决**:
```bash
# 查看部署历史
cat .deploy_history

# 回滚到上一个版本
bash scripts/deploy/deploy.sh rollback <previous-commit>

# 查看更新日志
cd logs/deploy
cat deploy.log | tail -100
```

---

## 高级用法

### 1. 定时备份（Cron）

```bash
# 编辑 crontab
crontab -e

# 添加定时任务（每天凌晨 2 点备份）
0 2 * * * cd /opt/yuxi-know && bash scripts/deploy/deploy.sh backup >> /var/log/yuxi-know-backup.log 2>&1

# 每周日凌晨备份
0 2 * * 0 cd /opt/yuxi-know && bash scripts/deploy/deploy.sh backup --no-compress --remote user@backup-server:/backups
```

### 2. 自定义健康检查通知

创建 `scripts/deploy/notify.sh`:

```bash
#!/bin/bash
# 自定义通知脚本

WEBHOOK_URL="https://hooks.slack.com/your-webhook"
MESSAGE="$1"

curl -X POST -H 'Content-type: application/json' \
  --data "{\"text\":\"Yuxi-Know: $MESSAGE\"}" \
  $WEBHOOK_URL
```

在 `health.sh` 中调用：
```bash
notify_health_check() {
    if [ $exit_code -ne 0 ]; then
        bash "${SCRIPT_DIR}/notify.sh" "❌ 健康检查失败"
    fi
}
```

### 3. 批量部署多台服务器

创建 `deploy-all.sh`:

```bash
#!/bin/bash
SERVERS=("server1.example.com" "server2.example.com" "server3.example.com")

for server in "${SERVERS[@]}"; do
    echo "部署到 $server..."
    ssh $server "cd /opt/yuxi-know && bash scripts/deploy/deploy.sh update --force"
done
```

### 4. 集成 CI/CD

**GitHub Actions 示例**:

```yaml
name: Deploy to Production

on:
  push:
    branches: [ main ]

jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3

      - name: Deploy
        run: |
          ssh ${{ secrets.SSH_USER }}@${{ secrets.SSH_SERVER }} \
            'cd /opt/yuxi-know && bash scripts/deploy/deploy.sh update --force'

      - name: Health Check
        run: |
          ssh ${{ secrets.SSH_USER }}@${{ secrets.SSH_SERVER }} \
            'cd /opt/yuxi-know && bash scripts/deploy/deploy.sh health'
```

**GitLab CI 示例**:

```yaml
deploy:
  stage: deploy
  script:
    - ssh $SSH_USER@$SSH_SERVER "cd /opt/yuxi-know && bash scripts/deploy/deploy.sh update --force"
    - ssh $SSH_USER@$SSH_SERVER "cd /opt/yuxi-know && bash scripts/deploy/deploy.sh health"
  only:
    - main
```

### 5. 监控模式集成到监控系统

```bash
# 输出健康检查为 JSON 格式
bash scripts/deploy/deploy.sh health --json

# 集成到 Prometheus
# 在 health.sh 中添加：
export_metrics() {
    echo "# HELP yuxi_know_services_running Number of running services"
    echo "# TYPE yuxi_know_services_running gauge"
    echo "yuxi_know_services_running $(docker compose ps --services --filter status=running | wc -l)"
}
```

---

## 故障排查

### 获取诊断信息

```bash
# 收集诊断信息
bash scripts/deploy/diagnose.sh

# 或手动收集
docker compose ps > docker-ps.log
docker compose logs --tail=100 > docker-logs.log
df -h > disk-usage.log
netstat -tuln > network-ports.log
docker info > docker-info.log
```

### 查看部署历史

```bash
# 查看部署历史
cat .deploy_history

# Git 历史
git log --oneline --graph -20

# Docker 镜像历史
docker images | grep yuxi-know
```

### 数据恢复测试

```bash
# 在测试环境恢复备份
cp -r backups/20240205_143022 /tmp/backup-test

# 模拟恢复
bash scripts/deploy/deploy.sh rollback --test /tmp/backup-test/20240205_143022
```

---

## 最佳实践

### 1. 部署前检查

- ✅ 确认磁盘空间充足（至少 10GB 可用）
- ✅ 检查网络连接（Docker Hub 访问）
- ✅ 备份现有数据（生产环境必做）
- ✅ 在测试环境先验证更新

### 2. 更新流程

1. `update --no-backup` → 快速检查代码更新（不执行）
2. `health --detailed` → 确认当前状态
3. `update` → 执行更新
4. `health` → 验证更新后状态

### 3. 备份策略

- 每日自动备份（Cron）
- 定期上传到异地存储
- 压缩备份节省空间
- 定期测试恢复流程

### 4. 监控建议

- 启用健康检查监控
- 设置磁盘空间告警（< 20%）
- 监控容器重启频率
- 记录部署历史

### 5. 安全建议

- 限制 `.env` 文件权限（`chmod 600 .env`）
- 不要提交敏感信息到 Git
- 定期更新系统和 Docker
- 使用 SSH 密钥认证（如远程部署）
- 定期轮换数据库密码

---

## 脚本开发指南

### 添加新命令

在 `deploy.sh` 的 `main()` 函数中添加：

```bash
mycommand)
    log_info "执行自定义命令..."
    bash "${SCRIPT_DIR}/mycommand.sh"
    ;;
```

创建 `scripts/deploy/mycommand.sh`:

```bash
#!/bin/bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/utils/logger.sh"
source "${SCRIPT_DIR}/config/deploy.conf"

init_log_dir

log_section "自定义命令"

# 你的逻辑
log_info "执行操作..."

log_success "✅ 完成"
```

### 使用日志函数

```bash
# 简单日志
log_info "这是一条信息"
log_ok "✅ 操作成功"
log_error "❌ 发生错误"

# 区块日志
log_section "标题"

# 进度日志
log_progress 5 10 "处理中"
```

### 环境验证

```bash
# 执行完整环境检查
check_all || emergency_exit "环境检查失败"

# 单项检查
check_docker || exit 1
check_docker_compose || exit 1
```

---

## 相关资源

- [项目主页](https://github.com/xerrors/Yuxi-Know)
- [Docker 文档](https://docs.docker.com/)
- [Docker Compose 文档](https://docs.docker.com/compose/)
- [PostgreSQL 文档](https://www.postgresql.org/docs/)
- [Neo4j 文档](https://neo4j.com/docs/)
- [Milvus 文档](https://milvus.io/docs/)

---

## 版本历史

| 版本 | 日期 | 变更 |
|------|------|------|
| 1.1.0 | 2024-02-05 | 新增自动安装 Docker、Docker Compose、Git 功能 |
| 1.0.0 | 2024-02-05 | 初始版本 |

---

## 贡献

欢迎提交 Issue 和 Pull Request！

---

## 许可证

本项目采用 MIT 许可证。
