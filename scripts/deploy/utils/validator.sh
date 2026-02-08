#!/bin/bash

# ============================================================================
# 环境验证工具函数
# ============================================================================

# 检查环境函数
check_environment() {
    log_info "检查系统环境..."

    # 检查操作系统
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        log_info "操作系统: $NAME $VERSION"
    else
        log_warning "无法检测操作系统信息"
    fi

    # 检查可用磁盘空间
    local data_root="${DATA_ROOT:-./data-volume}"
    local required_space=${REQUIRED_DISK_SPACE_GB:-10}

    # 如果 DATA_ROOT 是相对路径，转换为绝对路径
    if [[ "$data_root" != /* ]]; then
        data_root="$(cd "$(dirname "$data_root")" && pwd)/$(basename "$data_root")"
    fi

    # 获取挂载点
    local mount_point=$(df -P "$data_root" 2>/dev/null | tail -1 | awk '{print $6}')

    if [ -n "$mount_point" ]; then
        local available_mb=$(df -m "$mount_point" 2>/dev/null | tail -1 | awk '{print $4}')
        local available_gb=$((available_mb / 1024))

        if [ "$available_gb" -lt "$required_space" ]; then
            log_error "磁盘空间不足！"
            log_error "  要求: 最少 ${required_space}GB"
            log_error "  可用: ${available_gb}GB"
            log_error "  挂载点: ${mount_point}"
            return 1
        fi

        log_ok "✅ 磁盘空间充足: ${available_gb}GB 可用"
    fi

    # 检查用户权限
    if [ "$(id -u)" -eq 0 ]; then
        log_warning "正在以 root 用户运行部署"
    else
        log_info "运行用户: $(whoami) ($(id -un))"
    fi

    return 0
}

# 自动安装 Docker
install_docker() {
    log_section "自动安装 Docker"

    # 检测操作系统
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS_NAME=$ID
        OS_VERSION=$VERSION_ID
    else
        log_error "无法检测操作系统，请手动安装 Docker"
        return 1
    fi

    log_info "检测到操作系统: $NAME $VERSION"

    # 检查是否是 root 用户
    if [ "$(id -u)" -ne 0 ]; then
        log_warning "安装 Docker 需要 root 权限"
        log_info "将使用 sudo 执行安装命令"

        if ! sudo -n true 2>/dev/null; then
            log_error "当前用户没有 sudo 权限或需要密码"
            return 1
        fi
    fi

    # 根据发行版安装 Docker
    case "$OS_NAME" in
        ubuntu|debian)
            log_info "安装 Docker (Ubuntu/Debian)..."

            # 卸载旧版本
            sudo apt-get remove -y docker docker-engine docker.io containerd runc 2>/dev/null || true

            # 更新包索引
            sudo apt-get update

            # 安装依赖
            sudo apt-get install -y \
                ca-certificates \
                curl \
                gnupg \
                lsb-release

            # 添加 Docker 官方 GPG key
            sudo mkdir -p /etc/apt/keyrings
            curl -fsSL https://download.docker.com/linux/${OS_NAME}/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg

            # 设置 Docker 仓库
            echo \
                "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/${OS_NAME} \
                $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

            # 更新包索引
            sudo apt-get update

            # 安装 Docker Engine
            sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

            log_ok "✅ Docker 安装完成"
            ;;

        centos|rhel|fedora)
            log_info "安装 Docker (CentOS/RHEL/Fedora)..."

            # 卸载旧版本
            sudo yum remove -y docker docker-client docker-client-latest docker-common \
                docker-latest docker-latest-logrotate docker-logrotate docker-engine 2>/dev/null || true

            # 安装依赖
            sudo yum install -y yum-utils

            # 添加 Docker 仓库
            sudo yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo

            # 安装 Docker Engine
            sudo yum install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

            log_ok "✅ Docker 安装完成"
            ;;

        *)
            log_error "不支持的操作系统: $OS_NAME"
            log_info "请访问 https://docs.docker.com/get-docker/ 手动安装 Docker"
            return 1
            ;;
    esac

    # 启动 Docker 服务
    log_info "启动 Docker 服务..."
    sudo systemctl start docker
    sudo systemctl enable docker

    # 添加当前用户到 docker 组
    if [ "$(id -u)" -ne 0 ]; then
        log_info "添加用户 $USER 到 docker 组..."
        sudo usermod -aG docker $USER
        log_warning "⚠️  请执行 'newgrp docker' 或注销后重新登录以使组权限生效"
    fi

    # 验证安装
    if sudo docker --version &> /dev/null; then
        local version=$(sudo docker --version | awk '{print $3}' | sed 's/,//')
        log_ok "✅ Docker 安装成功！版本: ${version}"

        # 如果不是 root，提示需要重新登录
        if [ "$(id -u)" -ne 0 ]; then
            log_info ""
            log_info "========================================"
            log_info "需要执行以下命令使权限生效："
            log_info "  newgrp docker"
            log_info "或注销并重新登录"
            log_info "========================================"
            log_info ""
            read -p "是否现在继续部署？(y/N): " -n 1 -r
            echo
            if [[ ! $REPLY =~ ^[Yy]$ ]]; then
                return 1
            fi
        fi

        return 0
    else
        log_error "❌ Docker 安装失败"
        return 1
    fi
}

# 检查 Docker
check_docker() {
    log_info "检查 Docker..."

    if ! command -v docker &> /dev/null; then
        log_warning "⚠️  Docker 未安装"
        echo ""
        cat << EOF
Yuxi-Know 需要 Docker 来运行容器化服务。
您可以：

  1) 自动安装 Docker（推荐）
  2) 手动安装 Docker：https://docs.docker.com/get-docker/
  3) 跳过检查（不推荐）

EOF
        read -p "是否自动安装 Docker? (Y/n): " -n 1 -r
        echo

        if [[ ! $REPLY =~ ^[Nn]$ ]]; then
            # 尝试自动安装
            if install_docker; then
                # 安装成功，检查是否可以运行 docker
                if docker info &> /dev/null; then
                    log_ok "✅ Docker 可用"
                    return 0
                else
                    log_error "❌ Docker 安装但无法运行"
                    log_info "可能原因："
                    log_info "  1. 用户组权限未生效，请执行: newgrp docker"
                    log_info "  2. Docker 服务未启动，请执行: sudo systemctl start docker"
                    return 1
                fi
            else
                log_error "❌ Docker 自动安装失败"
                log_info "请访问 https://docs.docker.com/get-docker/ 手动安装"
                return 1
            fi
        else
            log_error "❌ 必须安装 Docker 才能继续部署"
            log_info "请访问 https://docs.docker.com/get-docker/ 手动安装"
            return 1
        fi
    fi

    local docker_version=$(docker --version | awk '{print $3}' | sed 's/,//')
    log_ok "✅ Docker 版本: ${docker_version}"

    # 检查 Docker 服务是否运行
    if ! docker info &> /dev/null; then
        log_warning "⚠️  Docker 服务未运行"
        log_info "尝试启动 Docker 服务..."

        if [ "$(id -u)" -eq 0 ]; then
            systemctl start docker
            systemctl enable docker
        else
            sudo systemctl start docker
            sudo systemctl enable docker
        fi

        if docker info &> /dev/null; then
            log_ok "✅ Docker 服务已启动"
            log_info "✅ Docker 服务已设置开机自启动"
        else
            log_error "❌ Docker 服务启动失败"
            log_info "请手动启动: sudo systemctl start docker"
            log_info "并设置开机自启: sudo systemctl enable docker"
            return 1
        fi
    else
        log_ok "✅ Docker 服务运行中"

        # 检查并设置开机自启动
        log_debug "检查 Docker 服务开机自启动状态..."
        if is_docker_enabled; then
            log_ok "✅ Docker 服务已设置开机自启动"
        else
            log_info "设置 Docker 服务开机自启动..."
            if [ "$(id -u)" -eq 0 ]; then
                systemctl enable docker
            else
                sudo systemctl enable docker
            fi
            log_ok "✅ Docker 服务已设置开机自启动"
        fi
    fi

    return 0
}

# 检查 Docker 服务是否已设置开机自启
is_docker_enabled() {
    if [ "$(id -u)" -eq 0 ]; then
        systemctl is-enabled docker &> /dev/null
    else
        sudo systemctl is-enabled docker &> /dev/null
    fi
    return $?
}

# 自动安装 Docker Compose v2（插件方式）
install_docker_compose_v2() {
    log_section "自动安装 Docker Compose v2"

    # 检查是否是 root 用户
    if [ "$(id -u)" -ne 0 ]; then
        log_warning "安装 Docker Compose 需要 root 权限"
        if ! sudo -n true 2>/dev/null; then
            log_error "当前用户没有 sudo 权限或需要密码"
            return 1
        fi
    fi

    # 检测操作系统
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS_NAME=$ID
    else
        log_error "无法检测操作系统"
        return 1
    fi

    case "$OS_NAME" in
        ubuntu|debian)
            log_info "安装 Docker Compose v2 (Ubuntu/Debian)..."

            # 更新包索引
            sudo apt-get update

            # 安装 docker-compose 插件
            sudo apt-get install -y docker-compose-plugin

            log_ok "✅ Docker Compose v2 安装完成"
            ;;

        centos|rhel|fedora)
            log_info "安装 Docker Compose v2 (CentOS/RHEL/Fedora)..."

            # 安装 docker-compose 插件
            sudo yum install -y docker-compose-plugin

            log_ok "✅ Docker Compose v2 安装完成"
            ;;

        *)
            log_error "不支持的操作系统: $OS_NAME"
            return 1
            ;;
    esac

    # 验证安装
    if docker compose version &> /dev/null; then
        local version=$(docker compose version --short)
        log_ok "✅ Docker Compose v2 安装成功！版本: ${version}"
        return 0
    else
        log_error "❌ Docker Compose v2 安装失败"
        return 1
    fi
}

# 检查 Docker Compose
check_docker_compose() {
    log_info "检查 Docker Compose..."

    if docker compose version &> /dev/null; then
        local compose_version=$(docker compose version --short)
        log_ok "✅ Docker Compose 版本: ${compose_version}"
        return 0
    elif command -v docker-compose &> /dev/null; then
        local compose_version=$(docker-compose --version | awk '{print $4}' | sed 's/,//')
        log_ok "✅ Docker Compose（独立安装）版本: ${compose_version}"
        return 0
    else
        log_warning "⚠️  Docker Compose 未安装"
        echo ""
        cat << EOF
Yuxi-Know 需要 Docker Compose 来管理多容器服务。
推荐安装 Docker Compose v2（插件版本）。

您可以：

  1) 自动安装 Docker Compose v2（推荐）
  2) 手动安装：https://docs.docker.com/compose/install/
  3) 跳过检查（不推荐）

EOF
        read -p "是否自动安装 Docker Compose v2? (Y/n): " -n 1 -r
        echo

        if [[ ! $REPLY =~ ^[Nn]$ ]]; then
            if install_docker_compose_v2; then
                return 0
            else
                log_error "❌ Docker Compose 自动安装失败"
                log_info "请访问 https://docs.docker.com/compose/install/ 手动安装"
                return 1
            fi
        else
            log_error "❌ 必须安装 Docker Compose 才能继续部署"
            log_info "请访问 https://docs.docker.com/compose/install/ 手动安装"
            return 1
        fi
    fi
}

# 自动安装 Git
install_git() {
    log_section "自动安装 Git"

    # 检查是否是 root 用户
    if [ "$(id -u)" -ne 0 ]; then
        log_warning "安装 Git 需要 root 权限"
        if ! sudo -n true 2>/dev/null; then
            log_error "当前用户没有 sudo 权限或需要密码"
            return 1
        fi
    fi

    # 检测操作系统
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS_NAME=$ID
    else
        log_error "无法检测操作系统"
        return 1
    fi

    case "$OS_NAME" in
        ubuntu|debian)
            log_info "安装 Git (Ubuntu/Debian)..."
            sudo apt-get update
            sudo apt-get install -y git
            log_ok "✅ Git 安装完成"
            ;;

        centos|rhel|fedora)
            log_info "安装 Git (CentOS/RHEL/Fedora)..."
            sudo yum install -y git
            log_ok "✅ Git 安装完成"
            ;;

        *)
            log_error "不支持的操作系统: $OS_NAME"
            return 1
            ;;
    esac

    # 验证安装
    if git --version &> /dev/null; then
        local version=$(git --version | awk '{print $3}')
        log_ok "✅ Git 安装成功！版本: ${version}"
        return 0
    else
        log_error "❌ Git 安装失败"
        return 1
    fi
}

# 检查 Git
check_git() {
    log_info "检查 Git..."

    if ! command -v git &> /dev/null; then
        log_warning "⚠️  Git 未安装"
        echo ""
        cat << EOF
Yuxi-Know 需要 Git 来拉取代码仓库。

您可以：

  1) 自动安装 Git（推荐）
  2) 手动安装 Git：https://git-scm.com/downloads
  3) 跳过检查（不推荐）

EOF
        read -p "是否自动安装 Git? (Y/n): " -n 1 -r
        echo

        if [[ ! $REPLY =~ ^[Nn]$ ]]; then
            if install_git; then
                return 0
            else
                log_error "❌ Git 自动安装失败"
                log_info "请访问 https://git-scm.com/downloads 手动安装"
                return 1
            fi
        else
            log_error "❌ 必须安装 Git 才能继续部署"
            log_info "请访问 https://git-scm.com/downloads 手动安装"
            return 1
        fi
    fi

    local git_version=$(git --version | awk '{print $3}')
    log_ok "✅ Git 版本: ${git_version}"

    return 0
}

# 检查 .env 文件
check_env_file() {
    log_info "检查环境配置文件..."

    local env_files=(
        ".env"
        "docker-compose.yml"
        "pyproject.toml"
    )

    for file in "${env_files[@]}"; do
        if [ -f "$file" ]; then
            log_ok "✅ $file 存在"
        else
            log_warning "⚠️  $file 不存在"
        fi
    done

    return 0
}

# 检查必要端口
check_ports() {
    log_info "检查必要端口..."

    local ports=(
        "5050:API 服务"
        "5173:Web 服务"
        "5432:PostgreSQL"
        "7474:Neo4j HTTP"
        "7687:Neo4j Bolt"
        "9000:MinIO API"
        "9001:MinIO Console"
        "19530:Milvus"
    )

    for port_info in "${ports[@]}"; do
        local port="${port_info%%:*}"
        local service="${port_info##*:}"

        if netstat -tuln 2>/dev/null | grep -q ":${port} " || \
           ss -tuln 2>/dev/null | grep -q ":${port} "; then
            log_warning "⚠️  端口 ${port} (${service}) 已被占用"
        else
            log_ok "✅ 端口 ${port} (${service}) 可用"
        fi
    done

    return 0
}

# 检查数据卷目录
check_data_volumes() {
    log_info "检查数据卷目录..."

    local data_root="${DATA_ROOT}"

    if [ -z "$data_root" ]; then
        log_error "DATA_ROOT 未配置！"
        return 1
    fi

    if [ ! -d "$data_root" ]; then
        log_warning "数据卷根目录不存在: ${data_root}"
        return 0
    fi

    # 检查目录结构
    local missing=0
    for dir in "${DATA_DIRECTORIES[@]}"; do
        if [ ! -d "$dir" ]; then
            log_warning "⚠️  缺失目录: $dir"
            ((missing++))
        fi
    done

    if [ "$missing" -eq 0 ]; then
        log_ok "✅ 所有数据卷目录存在"
    fi

    # 检查目录权限
    if [ ! -w "$data_root" ]; then
        log_error "数据卷根目录不可写: ${data_root}"
        return 1
    fi

    return 0
}

# 综合环境检查
check_all() {
    log_section "环境预检"

    local failed=0

    check_environment || ((failed++))
    check_docker || ((failed++))
    check_docker_compose || ((failed++))
    check_git || ((failed++))
    check_env_file || ((failed++))
    check_ports || ((failed++))
    check_data_volumes || ((failed++))

    if [ "$failed" -eq 0 ]; then
        log_success "✅ 所有检查通过"
        return 0
    else
        log_error "❌ ${failed} 项检查失败"
        return 1
    fi
}

# 等待服务就绪
wait_for_service() {
    local service_name="$1"
    local max_wait=${2:-60}
    local interval=${3:-2}

    local elapsed=0
    while [ $elapsed -lt $max_wait ]; do
        if docker compose ps "$service_name" | grep -q "Up"; then
            return 0
        fi
        sleep $interval
        elapsed=$((elapsed + interval))
    done

    log_error "服务 ${service_name} 启动超时"
    return 1
}

# 重试函数
retry() {
    local timeout=$1
    local interval=$2
    shift 2
    local command=("$@")

    local elapsed=0
    while [ $elapsed -lt $timeout ]; do
        if "${command[@]}"; then
            return 0
        fi
        sleep $interval
        elapsed=$((elapsed + interval))
    done

    return 1
}

# 导出函数
export -f check_environment
export -f check_docker
export -f check_docker_compose
export -f check_git
export -f check_env_file
export -f check_ports
export -f check_data_volumes
export -f check_all
export -f wait_for_service
export -f retry
export -f install_docker
export -f install_docker_compose_v2
export -f install_git
export -f is_docker_enabled
