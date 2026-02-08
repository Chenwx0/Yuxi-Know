#!/bin/bash

# ============================================================================
# 首次初始化部署脚本
# ============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/utils/logger.sh"
source "${SCRIPT_DIR}/utils/validator.sh"
source "${SCRIPT_DIR}/config/deploy.conf"

# 检查并创建数据卷目录
init_data_volumes() {
    log_section "初始化数据卷目录"

    local data_root="${DATA_ROOT}"

    log_info "数据卷根目录: $(realpath "$data_root" 2>/dev/null || echo "$data_root")"

    # 检查 DATA_ROOT 是否已定义
    if [ -z "$data_root" ]; then
        log_error "DATA_ROOT 未定义！请在 deploy.conf 或 .env 文件中设置 DATA_ROOT"
        exit 1
    fi

    # 创建所有必需的目录
    log_info "创建目录结构..."

    local total=${#DATA_DIRECTORIES[@]}
    local created=0

    for dir in "${DATA_DIRECTORIES[@]}"; do
        if [ ! -d "$dir" ]; then
            log_debug "创建目录: $dir"
            mkdir -p "$dir"
            ((created++))

            # 设置权限
            case "$dir" in
                *"postgres"*|*"neo4j"*|*"milvus"*|*"minio"*)
                    # 数据库目录需要特殊权限
                    chmod 755 "$dir"
                    ;;
                *"models"*|*"saves"*)
                    # 模型和保存文件目录
                    chmod 755 "$dir"
                    ;;
            esac
        fi
    done

    log_ok "✅ 创建了 $created 个新目录"

    # 复制 .env 文件到配置目录（如果不存在）
    local env_backup_dir="${CONFIG_DIR}/env"
    local project_env="${PROJECT_DIR}/.env"
    local env_template="${PROJECT_DIR}/.env.template"

    if [ ! -f "${env_backup_dir}/.env" ]; then
        if [ -f "$project_env" ]; then
            log_info "备份 .env 文件到配置目录..."
            mkdir -p "$env_backup_dir"
            cp "$project_env" "${env_backup_dir}/.env"
        elif [ -f "$env_template" ]; then
            log_warning "未找到 .env 文件，将从 .env.template 创建..."
            mkdir -p "$env_backup_dir"
            cp "$env_template" "${env_backup_dir}/.env"
            log_warning "请编辑 ${env_backup_dir}/.env 配置必要的环境变量"
        fi
    fi

    # 创建 .gitkeep 文件
    log_info "创建 .gitkeep 文件..."
    find "$data_root" -type d -exec touch {}/.gitkeep \; 2>/dev/null || true

    # 检查磁盘空间
    check_disk_space "$data_root"

    log_success "✅ 数据卷目录初始化完成！"
}

# 检查磁盘空间
check_disk_space() {
    local mount_point="$1"
    local required_space_gb=${REQUIRED_DISK_SPACE_GB:-10}

    log_info "检查磁盘空间..."

    # 相对路径转换为绝对路径
    if [[ "$mount_point" != /* ]]; then
        mount_point="$(cd "$(dirname "$mount_point")" 2>/dev/null && pwd)/$(basename "$mount_point")"
    fi

    # 获取挂载点
    local df_output=$(df -P "$mount_point" 2>/dev/null | tail -1)
    local available_mb=$(echo "$df_output" | awk '{print $4}')
    local available_gb=$((available_mb / 1024))

    if [ "$available_gb" -lt "$required_space_gb" ]; then
        log_error "磁盘空间不足！"
        log_error "  要求: 最少 ${required_space_gb}GB"
        log_error "  可用: ${available_gb}GB"
        log_error "  挂载点: $mount_point"
        exit 1
    fi

    log_ok "✅ 磁盘空间充足: ${available_gb}GB 可用"
}

# 检查数据卷权限
check_data_volume_permissions() {
    log_info "检查数据卷目录权限..."

    local data_root="${DATA_ROOT}"

    # 创建父目录（如果不存在）
    mkdir -p "$data_root"

    local user_id=$(id -u)
    local group_id=$(id -g)

    # 检查是否可以写入
    if [ ! -w "$data_root" ]; then
        log_error "数据卷根目录不可写: ${data_root}"
        log_error "当前用户: ${user_id}:${group_id}"
        log_error "目录权限: $(stat -c '%a' "$data_root" 2>/dev/null || echo '无法获取')"
        log_error "目录所有者: $(stat -c '%U:%G' "$data_root" 2>/dev/null || echo '无法获取')"

        read -p "是否尝试修复权限? (y/N): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            log_info "尝试修复权限..."
            sudo chown -R ${user_id}:${group_id} "$data_root" || {
                log_error "无法修复权限，请手动执行:"
                log_error "  sudo chown -R ${user_id}:${group_id} ${data_root}"
                exit 1
            }
        else
            exit 1
        fi
    fi

    log_ok "✅ 数据卷目录权限正常"
}

# 克隆或检查代码仓库
setup_repository() {
    log_section "设置代码仓库"

    local project_dir="${PROJECT_DIR}"

    # 创建项目目录（如果不存在）
    mkdir -p "$(dirname "$project_dir")"

    if [ -d "$project_dir/.git" ]; then
        log_info "代码仓库已存在，跳过克隆"
        cd "$project_dir"

        # 检查是否在正确的分支
        local current_branch=$(git branch --show-current)
        if [ "$current_branch" != "$GIT_BRANCH" ]; then
            log_info "切换到分支: $GIT_BRANCH"
            git checkout "$GIT_BRANCH" 2>/dev/null || {
                log_warning "分支 $GIT_BRANCH 不存在，创建并跟踪远程分支"
                git checkout -b "$GIT_BRANCH" "origin/$GIT_BRANCH" 2>/dev/null || {
                    log_error "无法切换到分支 $GIT_BRANCH"
                    exit 1
                }
            }
        fi

        # 拉取最新代码
        log_info "拉取最新代码..."
        git pull origin "$GIT_BRANCH"

    else
        log_info "克隆代码仓库..."
        log_info "  仓库: $GIT_REPO"
        log_info "  分支: $GIT_BRANCH"
        log_info "  目录: $project_dir"

        git clone -b "$GIT_BRANCH" "$GIT_REPO" "$project_dir"
        cd "$project_dir"
    fi

    log_ok "✅ 代码仓库准备完成"
}

# 配置环境变量
setup_environment() {
    log_section "配置环境变量"

    cd "${PROJECT_DIR}"

    local env_file=".env"
    local env_file_template=".env.template"
    local config_env_file="${CONFIG_DIR}/env/.env"

    # 计算展开后的路径变量（直接基于 DATA_ROOT）
    local SAVE_DIR="${DATA_ROOT}/saves"
    local MODEL_DIR="${DATA_ROOT}/models"
    local postgres_data_dir="${DATA_ROOT}/postgres"
    local neo4j_data_dir="${DATA_ROOT}/neo4j"
    local milvus_data_dir="${DATA_ROOT}/milvus"
    local paddlex_data_dir="${DATA_ROOT}/paddlex"

    # 优先使用 CONFIG_DIR 目录中的 .env 配置
    if [ -f "$config_env_file" ]; then
        log_ok "✅ 找到配置目录 .env 文件: $config_env_file"
        log_info "将配置目录的 .env 复制到项目目录..."

        # 复制到项目目录
        cp "$config_env_file" "$env_file"
        log_ok "✅ 已复制配置文件到: $env_file"

        # 检查并添加数据卷相关环境变量
        local need_update=false

        for var_entry in "DATA_ROOT=${DATA_ROOT}" \
            "SAVE_DIR=${SAVE_DIR}" \
            "POSTGRES_DATA_DIR=${postgres_data_dir}" \
            "NEO4J_DATA_DIR=${neo4j_data_dir}" \
            "MILVUS_DATA_DIR=${milvus_data_dir}" \
            "PADDLEX_DATA_DIR=${paddlex_data_dir}" \
            "MODEL_DIR=${MODEL_DIR}"; do

            local var_name="${var_entry%%=*}"
            if ! grep -q "^${var_name}=" "$env_file"; then
                if [ "$need_update" = false ]; then
                    log_info "添加数据卷配置到 .env 文件..."
                    need_update=true
                fi
                echo "${var_entry}" >> "$env_file"
                log_debug "  添加: ${var_entry}"
            fi
        done

        if [ "$need_update" = true ]; then
            # 同步回配置目录
            cp "$env_file" "$config_env_file"
            log_ok "✅ 数据卷配置已添加到 .env 文件（已同步到配置目录）"
        fi
        return 0
    fi

    # 如果项目目录中已经有 .env，同步到配置目录
    if [ -f "$env_file" ]; then
        log_ok "✅ 项目目录 .env 文件已存在，同步到配置目录..."

        # 检查并添加数据卷相关环境变量
        local need_update=false

        for var_entry in "DATA_ROOT=${DATA_ROOT}" \
            "SAVE_DIR=${SAVE_DIR}" \
            "POSTGRES_DATA_DIR=${postgres_data_dir}" \
            "NEO4J_DATA_DIR=${neo4j_data_dir}" \
            "MILVUS_DATA_DIR=${milvus_data_dir}" \
            "PADDLEX_DATA_DIR=${paddlex_data_dir}" \
            "MODEL_DIR=${MODEL_DIR}"; do

            local var_name="${var_entry%%=*}"
            if ! grep -q "^${var_name}=" "$env_file"; then
                if [ "$need_update" = false ]; then
                    log_info "添加数据卷配置到 .env 文件..."
                    need_update=true
                fi
                echo "${var_entry}" >> "$env_file"
                log_debug "  添加: ${var_entry}"
            fi
        done

        # 同步到配置目录
        mkdir -p "$(dirname "$config_env_file")"
        cp "$env_file" "$config_env_file"
        log_ok "✅ 已同步到配置目录: $config_env_file"

        if [ "$need_update" = true ]; then
            log_ok "✅ 数据卷配置已添加到 .env 文件"
        fi
        return 0
    fi

    # 尝试从模板创建
    if [ -f "$env_file_template" ]; then
        log_info "从 .env.template 创建 .env 文件..."
        cp "$env_file_template" "$env_file"

        # 添加数据卷配置（展开后的路径）
        log_info "添加数据卷环境变量..."
        {
            echo ""
            echo "# ============================ 数据卷配置 ============================"
            echo "# 以下配置由部署脚本根据 deploy.conf 自动生成"
            echo ""
            echo "DATA_ROOT=${DATA_ROOT}"
            echo "SAVE_DIR=${SAVE_DIR}"
            echo "POSTGRES_DATA_DIR=${postgres_data_dir}"
            echo "NEO4J_DATA_DIR=${neo4j_data_dir}"
            echo "MILVUS_DATA_DIR=${milvus_data_dir}"
            echo "PADDLEX_DATA_DIR=${paddlex_data_dir}"
            echo "MODEL_DIR=${MODEL_DIR}"
echo "# ========================================================================"
        } >> "$env_file"

        log_ok "✅ 数据卷配置已添加到 .env 文件"

        log_warning "⚠️  请编辑配置文件配置必要的环境变量"
        log_info "建议在配置目录编辑 (生产环境推荐):"
        log_info "  $config_env_file"
        log_info "或者在项目目录编辑:"
        log_info "  $env_file"
        log_info ""
        log_info "特别是以下配置:"
        log_info "  - SILICONFLOW_API_KEY (必填)"
        log_info "  - POSTGRES_PASSWORD (建议修改)"
        log_info "  - NEO4J_PASSWORD (建议修改)"
        log_info "  - MINIO_ACCESS_KEY 和 MINIO_SECRET_KEY (建议修改)"

        read -p "是否现在编辑 .env 文件? (y/N): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            ${EDITOR:-vi} "$env_file"
        fi

        # 同步到配置目录
        mkdir -p "$(dirname "$config_env_file")"
        cp "$env_file" "$config_env_file"
        log_ok "✅ 配置文件已同步到配置目录: $config_env_file"

    else
        log_error "未找到 .env 或 .env.template 文件"
        exit 1
    fi

    log_ok "✅ 环境变量配置完成"
}

# 拉取 Docker 镜像
pull_docker_images() {
    log_section "拉取 Docker 镜像"

    cd "${PROJECT_DIR}"

    log_info "拉取 Docker Compose 定义的所有镜像..."

    if docker compose pull; then
        log_ok "✅ Docker 镜像拉取完成"
    else
        log_error "Docker 镜像拉取失败"
        exit 1
    fi
}

# 构建项目镜像
build_images() {
    log_section "构建项目镜像"

    cd "${PROJECT_DIR}"

    log_info "构建自定义镜像（api 和 web）..."

    if docker compose build api web; then
        log_ok "✅ 镜像构建完成"
    else
        log_error "镜像构建失败"
        exit 1
    fi
}

# 创建 systemd 服务以实现开机自启动
create_systemd_service() {
    log_info "设置服务容器开机自启动..."

    cd "${PROJECT_DIR}"

    local service_name="yuxi-know.service"
    local service_path="/etc/systemd/system/${service_name}"

    # 检查是否已存在
    if [ -f "$service_path" ]; then
        log_debug "systemd 服务已存在，更新配置..."
        if [ "$(id -u)" -eq 0 ]; then
            rm -f "$service_path"
        else
            sudo rm -f "$service_path"
        fi
    fi

    # 获取 docker compose 文件路径（转换为绝对路径）
    local compose_file=$(realpath docker-compose.yml 2>/dev/null || echo "${PROJECT_DIR}/docker-compose.yml")
    local project_dir_with_compose="$(dirname "$compose_file")"

    # 创建 systemd 服务文件
    cat > "/tmp/${service_name}" << EOF
[Unit]
Description=Yuxi-Know Docker Compose Services
After=docker.service
Requires=docker.service

[Service]
Type=oneshot
RemainAfterExit=yes
WorkingDirectory=${project_dir_with_compose}
ExecStart=/usr/bin/docker compose -f ${compose_file} up -d
ExecStop=/usr/bin/docker compose -f ${compose_file} down
TimeoutStartSec=0

[Install]
WantedBy=multi-user.target
EOF

    # 安装服务文件
    if [ "$(id -u)" -eq 0 ]; then
        mv "/tmp/${service_name}" "$service_path"
    else
        sudo mv "/tmp/${service_name}" "$service_path"
    fi

    # 重新加载 systemd 配置
    if [ "$(id -u)" -eq 0 ]; then
        systemctl daemon-reload
        systemctl enable "$service_name"
    else
        sudo systemctl daemon-reload
        sudo systemctl enable "$service_name"
    fi

    log_ok "✅ 已创建并启用 systemd 服务: ${service_name}"
    log_info "  服务会在系统启动后自动启动容器"
    log_info "  管理命令:"
    log_info "    启动:   systemctl start ${service_name}"
    log_info "    停止:   systemctl stop ${service_name}"
    log_info "    状态:   systemctl status ${service_name}"
    log_info "    禁用:   systemctl disable ${service_name}"
}

# 配置防火墙 opens
configure_firewall() {
    log_section "配置系统防火墙"

    # 检测防火墙类型
    local firewall_type=""
    if command -v firewall-cmd >/dev/null 2>&1; then
        firewall_type="firewalld"
    elif command -v ufw >/dev/null 2>&1; then
        firewall_type="ufw"
    elif command -v iptables >/dev/null 2>&1; then
        firewall_type="iptables"
    else
        log_warning "⚠️  未检测到防火墙工具 (firewalld/ufw/iptables)"
        log_info "如果服务器启用了防火墙，请手动开放以下端口："
        log_info ""
        log_info "必需端口:"
        log_info "  - 80/tcp    (前端 Web)"
        log_info "  - 443/tcp   (前端 Web HTTPS)"
        log_info ""
        log_info "端口管理（可选，用于远程访问）："
        log_info "  - 5050/tcp    (后端 API)"
        log_info "  - 5432/tcp    (PostgreSQL 数据库)"
        log_info "  - 7474/tcp    (Neo4j HTTP)"
        log_info "  - 7687/tcp    (Neo4j Bolt)"
        log_info "  - 19530/tcp   (Milvus 向量数据库)"
        log_info "  - 9000/tcp    (MinIO API)"
        log_info "  - 9001/tcp    (MinIO Console)"
        log_info "  - 30000/tcp   (MinerU VLLM Server)"
        log_info "  - 30001/tcp   (MinerU API)"
        log_info "  - 8080/tcp    (PaddleX OCR)"
        return 0
    fi

    log_info "检测到防火墙类型: $firewall_type"

    # 定义需要开放的端口
    local frontend_ports=("80/tcp" "443/tcp")
    local optional_ports=(
        "5050/tcp"      # 后端 API
        "5432/tcp"      # PostgreSQL
        "7474/tcp"      # Neo4j HTTP
        "7687/tcp"      # Neo4j Bolt
        "19530/tcp"     # Milvus
        "9000/tcp"      # MinIO API
        "9001/tcp"      # MinIO Console
        "30000/tcp"     # MinerU VLLM Server
        "30001/tcp"     # MinerU API
        "8080/tcp"      # PaddleX OCR
    )

    case "$firewall_type" in
        firewalld)
            configure_firewalld "${frontend_ports[@]}" "${optional_ports[@]}"
            ;;
        ufw)
            configure_ufw "${frontend_ports[@]}" "${optional_ports[@]}"
            ;;
        iptables)
            configure_iptables "${frontend_ports[@]}" "${optional_ports[@]}"
            ;;
    esac
}

# 使用 firewalld 配置防火墙
configure_firewalld() {
    local frontend_ports=("$@")
    shift
    shift
    local optional_ports=("$@")

    log_info "使用 firewalld 配置防火墙..."

    # 检查 firewalld 是否运行
    if ! systemctl is-active --quiet firewalld 2>/dev/null; then
        log_warning "⚠️  firewalld 服务未运行"
        read -p "是否启动 firewalld 服务? (y/N): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            if [ "$(id -u)" -eq 0 ]; then
                systemctl start firewalld || emergency_exit "无法启动 firewalld"
            else
                sudo systemctl start firewalld || emergency_exit "无法启动 firewalld"
            fi
            log_ok "✅ firewalld 已启动"
        else
            log_info "跳过防火墙配置"
            return 0
        fi
    fi

    # 开放必需端口（前端）
    log_info "开放必需端口（前端 Web）:"
    for port in "${frontend_ports[@]}"; do
        if [ "$(id -u)" -eq 0 ]; then
            firewall-cmd --permanent --add-service="${port%/*}" >/dev/null 2>&1 || \
                firewall-cmd --permanent --add-port="$port" >/dev/null 2>&1 || \
                log_warning "⚠️  无法开放端口 $port"
        else
            sudo firewall-cmd --permanent --add-service="${port%/*}" >/dev/null 2>&1 || \
                sudo firewall-cmd --permanent --add-port="$port" >/dev/null 2>&1 || \
                log_warning "⚠️  无法开放端口 $port"
        fi
        echo "  ✅ $port"
    done

    # 询问是否开放可选端口
    log_info ""
    log_info "检测到以下可选端口（用于开发和管理）:"
    for port in "${optional_ports[@]}"; do
        echo "  - $port"
    done

    read -p "是否开放所有可选端口? (推荐生产环境不开放) [y/N]: " -n 1 -r
    echo

    if [[ $REPLY =~ ^[Yy]$ ]]; then
        log_info "开放可选端口:"
        for port in "${optional_ports[@]}"; do
            if [ "$(id -u)" -eq 0 ]; then
                firewall-cmd --permanent --add-port="$port" >/dev/null 2>&1 || \
                    log_warning "⚠️  无法开放端口 $port"
            else
                sudo firewall-cmd --permanent --add-port="$port" >/dev/null 2>&1 || \
                    log_warning "⚠️  无法开放端口 $port"
            fi
            echo "  ✅ $port"
        done
    else
        log_info "只开放必需端口（更安全）"

        # 询问是否单独开放某些端口
        for port in "${optional_ports[@]}"; do
            read -p "是否开放 $port ? (y/N): " -n 1 -r
            echo
            if [[ $REPLY =~ ^[Yy]$ ]]; then
                if [ "$(id -u)" -eq 0 ]; then
                    firewall-cmd --permanent --add-port="$port" >/dev/null 2>&1 || \
                        log_warning "⚠️  无法开放端口 $port"
                else
                    sudo firewall-cmd --permanent --add-port="$port" >/dev/null 2>&1 || \
                        log_warning "⚠️  无法开放端口 $port"
                fi
                log_ok "✅ 已开放 $port"
            fi
        done
    fi

    # 重新加载防火墙规则
    log_info "重新加载防火墙规则..."
    if [ "$(id -u)" -eq 0 ]; then
        firewall-cmd --reload >/dev/null 2>&1 || log_warning "⚠️  防火墙重载失败"
    else
        sudo firewall-cmd --reload >/dev/null 2>&1 || log_warning "⚠️  防火墙重载失败"
    fi

    # 显示当前开放的端口
    log_info "当前开放的端口:"
    if [ "$(id -u)" -eq 0 ]; then
        firewall-cmd --list-ports | sed 's/^/  /'
    else
        sudo firewall-cmd --list-ports | sed 's/^/  /'
    fi

    log_ok "✅ 防火墙配置完成"
}

# 使用 ufw 配置防火墙
configure_ufw() {
    local frontend_ports=("$@")
    shift
    shift
    local optional_ports=("$@")

    log_info "使用 UFW 配置防火墙..."

    # 检查 ufw 是否启用
    local ufw_status
    if command ufw status | grep -q "Status: active"; then
        ufw_status="active"
    elif command ufw status | grep -q "Status: inactive"; then
        ufw_status="inactive"
    else
        ufw_status="unknown"
    fi

    if [ "$ufw_status" = "inactive" ]; then
        log_warning "⚠️  UFW 未启用"
        read -p "是否启用 UFW 防火墙? (y/N): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            if [ "$(id -u)" -eq 0 ]; then
                ufw --force enable >/dev/null 2>&1 || emergency_exit "无法启用 UFW"
            else
                sudo ufw --force enable >/dev/null 2>&1 || emergency_exit "无法启用 UFW"
            fi
            log_ok "✅ UFW 已启用"
        else
            log_info "跳过防火墙配置"
            return 0
        fi
    fi

    # 开放必需端口
    log_info "开放必需端口（前端 Web）:"
    for port in "${frontend_ports[@]}"; do
        if [ "$(id -u)" -eq 0 ]; then
            ufw allow "$port" >/dev/null 2>&1 || log_warning "⚠️  无法开放端口 $port"
        else
            sudo ufw allow "$port" >/dev/null 2>&1 || log_warning "⚠️  无法开放端口 $port"
        fi
        echo "  ✅ $port"
    done

    # 询问是否开放可选端口
    log_info ""
    log_info "检测到以下可选端口（用于开发和管理）:"
    for port in "${optional_ports[@]}"; do
        echo "  - $port"
    done

    read -p "是否开放所有可选端口? (推荐生产环境不开放) [y/N]: " -n 1 -r
    echo

    if [[ $REPLY =~ ^[Yy]$ ]]; then
        log_info "开放可选端口:"
        for port in "${optional_ports[@]}"; do
            if [ "$(id -u)" -eq 0 ]; then
                ufw allow "$port" >/dev/null 2>&1 || log_warning "⚠️  无法开放端口 $port"
            else
                sudo ufw allow "$port" >/dev/null 2>&1 || log_warning "⚠️  无法开放端口 $port"
            fi
            echo "  ✅ $port"
        done
    else
        log_info "只开放必需端口（更安全）"

        # 询问是否单独开放某些端口
        for port in "${optional_ports[@]}"; do
            read -p "是否开放 $port ? (y/N): " -n 1 -r
            echo
            if [[ $REPLY =~ ^[Yy]$ ]]; then
                if [ "$(id -u)" -eq 0 ]; then
                    ufw allow "$port" >/dev/null 2>&1 || log_warning "⚠️  无法开放端口 $port"
                else
                    sudo ufw allow "$port" >/dev/null 2>&1 || log_warning "⚠️  无法开放端口 $port"
                fi
                log_ok "✅ 已开放 $port"
            fi
        done
    fi

    # 显示当前状态
    log_info "当前防火墙状态:"
    if [ "$(id -u)" -eq 0 ]; then
        ufw status numbered | sed 's/^/  /'
    else
        sudo ufw status numbered | sed 's/^/  /'
    fi

    log_ok "✅ 防火墙配置完成"
}

# 使用 iptables 配置防火墙
configure_iptables() {
    local frontend_ports=("$@")
    shift
    shift
    local optional_ports=("$@")

    log_info "使用 iptables 配置防火墙..."
    log_warning "⚠️  直接使用 iptables 配置较为复杂，建议改用 firewalld 或 ufw"
    log_info ""
    log_info "手动配置 iptables 的示例命令："
    echo ""

    for port in "${frontend_ports[@]}" "${optional_ports[@]}"; do
        echo "  # 开放 $port"
        echo "  iptables -I INPUT -p tcp --dport ${port%/tcp} -j ACCEPT"
        if [ "$(id -u)" -eq 0 ]; then
            echo "  iptables-save > /etc/iptables/rules.v4"
        else
            echo "  sudo iptables-save > /etc/iptables/rules.v4"
        fi
    done

    echo ""
    echo "  # 保存规则"
    echo "  if command -v netfilter-persistent >/dev/null 2>&1; then"
    echo "    netfilter-persistent save"
    echo "  fi"

    read -p "是否按照上述命令手动配置 iptables? (y/N): " -n 1 -r
    echo

    if [[ $REPLY =~ ^[Yy]$ ]]; then
        for port in "${frontend_ports[@]}"; do
            if [ "$(id -u)" -eq 0 ]; then
                iptables -I INPUT -p tcp --dport ${port%/tcp} -j ACCEPT 2>/dev/null || \
                    log_warning "⚠️  无法开放端口 $port"
            else
                sudo iptables -I INPUT -p tcp --dport ${port%/tcp} -j ACCEPT 2>/dev/null || \
                    log_warning "⚠️  无法开放端口 $port"
            fi
        done

        if command -v netfilter-persistent >/dev/null 2>&1; then
            if [ "$(id -u)" -eq 0 ]; then
                netfilter-persistent save >/dev/null 2>&1 || log_warning "⚠️  无法保存 iptables 规则"
            else
                sudo netfilter-persistent save >/dev/null 2>&1 || log_warning "⚠️  无法保存 iptables 规则"
            fi
        fi

        log_info "当前 iptables 规则:"
        if [ "$(id -u)" -eq 0 ]; then
            iptables -L INPUT -n -v --line-numbers | head -20 | sed 's/^/  /'
        else
            sudo iptables -L INPUT -n -v --line-numbers | head -20 | sed 's/^/  /'
        fi

        log_ok "✅ 防火墙配置完成"
    else
        log_info "跳过防火墙配置"
    fi
}

# 启动服务
start_services() {
    log_section "启动服务"

    cd "${PROJECT_DIR}"

    log_info "启动所有服务..."

    if docker compose up -d; then
        log_ok "✅ 服务启动命令已执行"
    else
        log_error "服务启动失败"
        exit 1
    fi

    # 等待服务启动
    log_info "等待服务启动..."
    wait_for_services

    # 创建 systemd 服务以实现开机自启动
    create_systemd_service
}

# 等待所有服务就绪
wait_for_services() {
    log_info "等待关键服务就绪..."

    local timeout=${HEALTH_CHECK_TIMEOUT:-300}
    local interval=${HEALTH_CHECK_INTERVAL:-10}
    local elapsed=0

    # 主要服务列表
    local services=("postgres" "neo4j" "milvus" "api" "web")

    while [ $elapsed -lt $timeout ]; do
        local all_ready=true
        local status_output=""

        for service in "${services[@]}"; do
            if docker compose ps -q "$service" | xargs -I {} docker inspect --format='{{.State.Status}}' {} 2>/dev/null | grep -q "running"; then
                status_output+="  ✅ $service\n"
            else
                status_output+="  ⏳ $service\n"
                all_ready=false
            fi
        done

        # 清除上一行的进度
        clear_progress
        log_info "等待服务启动... (${elapsed}s/${timeout}s)"
        echo -e "$status_output"

        if [ "$all_ready" = true ]; then
            log_success "✅ 所有服务已启动！"
            return 0
        fi

        sleep $interval
        elapsed=$((elapsed + interval))
    done

    log_warning "⚠️  部分服务可能未完全启动，请检查日志"
}

# 执行数据库初始化（如果需要）
initialize_database() {
    log_section "数据库初始化"

    cd "${PROJECT_DIR}"

    # 检查是否有初始化脚本
    local init_scripts=(
        "scripts/init_database.py"
        "scripts/alembic_init.py"
        "scripts/db_init.sh"
    )

    local has_init=false
    for script in "${init_scripts[@]}"; do
        if [ -f "$script" ]; then
            has_init=true
            break
        fi
    done

    if [ "$has_init" = false ]; then
        log_info "未找到数据库初始化脚本，跳过"
        return 0
    fi

    log_info "等待数据库服务就绪..."
    sleep 10

    log_info "执行数据库初始化..."

    # 尝试执行 Python 初始化脚本
    for script in "${init_scripts[@]}"; do
        if [[ "$script" == *.py ]]; then
            if docker compose exec -T api uv run python "$script"; then
                log_ok "✅ 数据库初始化完成"
                return 0
            else
                log_warning "⚠️  数据库初始化脚本执行失败（可能已初始化）"
            fi
        fi
    done

    log_info "数据库初始化完成（或已初始化）"
}

# 显示初始化完成信息
show_completion_info() {
    log_section "初始化完成"

    cat << EOF
┌─────────────────────────────────────────────────────────────┐
│  ✅ Yuxi-Know 部署初始化完成！                            │
└─────────────────────────────────────────────────────────────┘

📍 项目信息:
  项目目录: ${PROJECT_DIR}
  数据目录: ${DATA_ROOT}
  Git 仓库: $GIT_REPO
  Git 分支: $GIT_BRANCH

🌐 访问地址:
  注意: 以下地址默认仅限本机访问 (localhost/127.0.0.1)
  如需从外部访问，请确保防火墙已开放相应端口

  - 前端: http://localhost:5173
  - 后端 API: http://localhost:5050
  - API 文档: http://localhost:5050/docs
  - Neo4j Browser: http://localhost:7474
  - MinIO Console: http://localhost:9001

🔥 防火墙配置:
  必需端口（已开放）:
    - 80/tcp    (前端 Web)
    - 443/tcp   (前端 Web HTTPS)

  可选端口（如需外部访问，请手动开放）:
    - 5050/tcp    (后端 API)
    - 5432/tcp    (PostgreSQL 数据库)
    - 7474/tcp    (Neo4j HTTP)
    - 7687/tcp    (Neo4j Bolt)
    - 19530/tcp   (Milvus 向量数据库)
    - 9000/tcp    (MinIO API)
    - 9001/tcp    (MinIO Console)
    - 30000/tcp   (MinerU VLLM Server)
    - 30001/tcp   (MinerU API)
    - 8080/tcp    (PaddleX OCR)

  防火墙管理命令:
    # firewalld (CentOS/RHEL/Fedora)
    firewall-cmd --list-all                              # 查看规则
    firewall-cmd --permanent --add-port=PORT/tcp         # 开放端口
    firewall-cmd --reload                                # 重载规则

    # ufw (Ubuntu/Debian)
    ufw status numbered                                  # 查看规则
    ufw allow PORT/tcp                                   # 开放端口

📋 常用命令:
  # 查看服务状态
  docker compose ps

  # 查看日志
  docker compose logs -f

  # 重启服务
  docker compose restart

  # 停止服务
  docker compose stop

  # 健康检查
  ${SCRIPT_DIR}/deploy.sh health

  # 更新部署
  ${SCRIPT_DIR}/deploy.sh update

📝 下一步:
  1. 访问前端页面 http://localhost:5173
  2. 创建管理员账户（首次访问时）
  3. 配置知识库和模型

🔧 故障排查:
  查看详细日志: docker compose logs -f [service-name]
  检查服务状态: docker compose ps
  重启服务: docker compose restart [service-name]

🚀 开机自启动:
  ✅ Docker 服务已设置为开机自启动
  ✅ Yuxi-Know 服务容器已设置为开机自启动

  服务器重启后，Docker 和所有服务容器会自动启动。
  如需检查或管理：
    Docker 服务状态:  systemctl status docker
    服务容器状态:    systemctl status yuxi-know.service
    手动启动服务:    systemctl start yuxi-know.service
    手动停止服务:    systemctl stop yuxi-know.service
    禁用开机启动:    systemctl disable yuxi-know.service

EOF
}

# 主初始化函数
init_deployment() {
    log_section "Yuxi-Know 部署初始化"

    log_info "部署配置:"
    log_info "  项目名称: $PROJECT_NAME"
    log_info "  项目目录: $PROJECT_DIR"
    log_info "  数据根目录: $DATA_ROOT"
    log_info "  Git 仓库: $GIT_REPO"
    log_info "  Git 分支: $GIT_BRANCH"

    # 1. 环境检查
    log_info "执行环境预检..."
    check_all || emergency_exit "环境检查失败"

    # 2. 数据卷准备
    check_data_volume_permissions
    init_data_volumes

    # 3. 代码准备
    setup_repository

    # 4. 环境配置
    setup_environment

    # 5. 配置防火墙
    configure_firewall

    # 6. Docker 准备
    pull_docker_images
    build_images

    # 7. 启动服务
    start_services

    # 8. 数据库初始化
    initialize_database

    # 9. 记录部署
    record_deployment "init" "首次初始化部署"

    # 10. 显示完成信息
    show_completion_info
}

# 执行初始化
init_deployment
