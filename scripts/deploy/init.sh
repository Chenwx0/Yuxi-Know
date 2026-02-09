#!/bin/bash

# ============================================================================
# 首次初始化部署脚本
# ============================================================================

# 错误处理
trap 'echo "错误发生在: $0 第 $LINENO 行"; exit 1' ERR

# 设置模式
set -u

# 确保错误输出到终端
exec 2>&1

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# 加载配置文件
if [ -f "${SCRIPT_DIR}/config/deploy.conf" ]; then
    source "${SCRIPT_DIR}/config/deploy.conf"
else
    echo "错误：配置文件不存在: ${SCRIPT_DIR}/config/deploy.conf"
    exit 1
fi

# 加载工具函数
source "${SCRIPT_DIR}/utils/logger.sh" || { echo "无法加载 logger.sh"; exit 1; }
source "${SCRIPT_DIR}/utils/validator.sh" || { echo "无法加载 validator.sh"; exit 1; }

# 允许通过命令行覆盖分支配置
if [ -n "$DEPLOY_BRANCH" ]; then
    GIT_BRANCH="$DEPLOY_BRANCH"
fi

# 解析命令行参数
while [[ $# -gt 0 ]]; do
    case $1 in
        --branch)
            GIT_BRANCH="$2"
            shift 2
            ;;
        *)
            shift
            ;;
    esac
done

# 克隆或更新代码仓库
setup_repository() {
    log_section "获取代码仓库"

    local project_dir="${PROJECT_DIR}"
    mkdir -p "$(dirname "$project_dir")"

    if [ -d "$project_dir/.git" ]; then
        log_info "代码仓库已存在，拉取最新代码..."
        cd "$project_dir"

        # 检查并切换分支
        local current_branch=$(git branch --show-current)
        if [ "$current_branch" != "$GIT_BRANCH" ]; then
            log_info "切换到分支: $GIT_BRANCH"
            git checkout -f "$GIT_BRANCH" 2>/dev/null || {
                log_warning "分支 $GIT_BRANCH 不存在，创建并跟踪远程分支"
                git branch -f "$GIT_BRANCH" "origin/$GIT_BRANCH"
                git checkout "$GIT_BRANCH"
            }
        fi

        # 拉取最新代码并覆盖本地修改
        git fetch origin "$GIT_BRANCH"
        git reset --hard "origin/$GIT_BRANCH"

    else
        log_info "克隆代码仓库..."
        log_info "  仓库: $GIT_REPO"
        log_info "  分支: $GIT_BRANCH"
        git clone -b "$GIT_BRANCH" "$GIT_REPO" "$project_dir"
        cd "$project_dir"
    fi

    log_ok "✅ 代码准备完成"
}

# 配置环境变量
setup_environment() {
    log_section "配置环境变量"

    cd "${PROJECT_DIR}"

    local env_file=".env"
    local config_env_file="${CONFIG_DIR}/env/.env"

    # 计算数据卷路径
    local SAVE_DIR="${DATA_ROOT}/saves"
    local MODEL_DIR="${DATA_ROOT}/models"
    local postgres_data_dir="${DATA_ROOT}/postgres"
    local neo4j_data_dir="${DATA_ROOT}/neo4j"
    local milvus_data_dir="${DATA_ROOT}/milvus"
    local paddlex_data_dir="${DATA_ROOT}/paddlex"

    # 优先使用 CONFIG_DIR 的配置
    if [ -f "$config_env_file" ]; then
        log_info "使用配置目录的 .env 文件"
        cp "$config_env_file" "$env_file"

    # 否则检查项目中的 .env
    elif [ -f "$env_file" ]; then
        log_info "使用项目目录的 .env 文件"
        # 同步到配置目录
        mkdir -p "$(dirname "$config_env_file")"
        cp "$env_file" "$config_env_file"

    # 都没有则从模板创建
    elif [ -f ".env.template" ]; then
        log_warning "未找到 .env 文件，从模板创建..."
        cp ".env.template" "$env_file"

        # 添加数据卷配置
        {
            echo ""
            echo "# ============================ 数据卷配置 ============================"
            echo "DATA_ROOT=${DATA_ROOT}"
            echo "SAVE_DIR=${SAVE_DIR}"
            echo "POSTGRES_DATA_DIR=${postgres_data_dir}"
            echo "NEO4J_DATA_DIR=${neo4j_data_dir}"
            echo "MILVUS_DATA_DIR=${milvus_data_dir}"
            echo "PADDLEX_DATA_DIR=${paddlex_data_dir}"
            echo "MODEL_DIR=${MODEL_DIR}"
            echo "# ========================================================================"
        } >> "$env_file"

        # 同步到配置目录
        mkdir -p "$(dirname "$config_env_file")"
        cp "$env_file" "$config_env_file"

        log_warning "⚠️  请编辑 .env 配置必要的环境变量"
        log_info "  必须配置: SILICONFLOW_API_KEY"

    else
        log_error "未找到 .env 或 .env.template 文件"
        exit 1
    fi

    # 添加缺失的数据卷配置
    for var_entry in "DATA_ROOT=${DATA_ROOT}" \
        "SAVE_DIR=${SAVE_DIR}" \
        "POSTGRES_DATA_DIR=${postgres_data_dir}" \
        "NEO4J_DATA_DIR=${neo4j_data_dir}" \
        "MILVUS_DATA_DIR=${milvus_data_dir}" \
        "PADDLEX_DATA_DIR=${paddlex_data_dir}" \
        "MODEL_DIR=${MODEL_DIR}"; do

        local var_name="${var_entry%%=*}"
        if ! grep -q "^${var_name}=" "$env_file"; then
            echo "${var_entry}" >> "$env_file"
        fi
    done

    # 同步回配置目录
    cp "$env_file" "$config_env_file"

    log_ok "✅ 环境变量配置完成"
}

# 创建数据卷目录
init_data_volumes() {
    log_section "初始化数据卷目录"

    local data_root="${DATA_ROOT}"

    if [ -z "$data_root" ]; then
        log_error "DATA_ROOT 未定义"
        return 1
    fi

    log_info "创建数据卷目录: $data_root"

    # 创建所有目录
    for dir in "${DATA_DIRECTORIES[@]}"; do
        mkdir -p "$dir" || {
            log_error "创建目录失败: $dir"
            return 1
        }
    done

    # 清理数据库目录中的非数据文件（如 .gitkeep）
    for db_dir in "${POSTGRES_DATA_DIR}" "${NEO4J_DATA_DIR}/data" "${MILVUS_DATA_DIR}/etcd"; do
        if [ -d "$db_dir" ]; then
            # 检查是否是有效的数据库目录
            local is_valid=false
            [[ "$db_dir" == *"postgres"* ]] && [ -f "$db_dir/PG_VERSION" ] && is_valid=true
            [[ "$db_dir" == *"neo4j"* ]] && [ -f "$db_dir/dbms" ] && is_valid=true
            [[ "$db_dir" == *"etcd"* ]] && [ -d "$db_dir/member" ] && is_valid=true

            # 如果目录不为空且无效，清理非数据文件
            if [ "$(ls -A "$db_dir" 2>/dev/null)" ] && [ "$is_valid" = false ]; then
                log_info "清理 $db_dir 中的非数据文件..."
                # 只删除非隐藏文件，保留可能的系统文件
                find "$db_dir" -maxdepth 1 -type f \( ! -name ".*" ! -name "lost+found" \) -delete 2>/dev/null || true
            fi
        fi
    done

    # 检查磁盘空间
    local available_gb=$(df -BG "$data_root" 2>/dev/null | tail -1 | awk '{print $4}' | tr -d 'G')
    if [ "${available_gb:-0}" -lt ${REQUIRED_DISK_SPACE_GB:-10} ]; then
        log_warning "磁盘空间不足 (可用: ${available_gb}GB)"
    fi

    log_ok "✅ 数据卷目录初始化完成"
}

# 配置防火墙
configure_firewall() {
    log_section "配置防火墙"

    # 切换到项目目录
    cd "${PROJECT_DIR}" || {
        log_error "无法切换到项目目录: ${PROJECT_DIR}"
        return 1
    }

    # 检查是否为非交互模式
    local interactive=true
    if [[ "${AI_MODE:-false}" == "true" || "${AUTO_DEPLOY:-false}" == "true" ]]; then
        interactive=false
        log_info "非交互模式：使用默认配置"
    fi

    # 从 .env 文件读取实际配置的 PostgreSQL 端口
    local postgres_port=$(grep "^POSTGRES_PORT=" .env 2>/dev/null | cut -d'=' -f2)
    postgres_port=${postgres_port:-5432}  # 默认 5432

    # 定义需要开放的端口
    local ports=("80/tcp" "443/tcp")

    # 可选端口（仅在交互模式下询问，或通过环境变量控制）
    local optional_ports=()
    if [[ "${OPEN_ALL_PORTS:-}" == "true" ]]; then
        local optional_ports=(
            "5173/tcp"    # 前端开发端口
            "5050/tcp"    # 后端 API
            "${postgres_port}/tcp"    # PostgreSQL（从 .env 读取）
            "7474/tcp"    # Neo4j HTTP
            "7687/tcp"    # Neo4j Bolt
            "19530/tcp"   # Milvus
            "9000/tcp"    # MinIO API
            "9001/tcp"    # MinIO Console
        )
    fi

    # firewalld
    if command -v firewall-cmd >/dev/null 2>&1; then
        log_info "使用 firewalld 配置"
        systemctl start firewalld 2>/dev/null || true

        # 检查并开放端口
        local existing_ports=$(firewall-cmd --list-ports 2>/dev/null || echo "")
        for port in "${ports[@]}" "${optional_ports[@]}"; do
            if ! echo "$existing_ports" | grep -q "$port" && \
               ! echo "$existing_ports" | grep -q "${port%/*}"; then
                firewall-cmd --permanent --add-service="${port%/*}" >/dev/null 2>&1 || \
                    firewall-cmd --permanent --add-port="$port" >/dev/null 2>&1 || true
                log_info "已开放端口: $port"
            fi
        done

        firewall-cmd --reload >/dev/null 2>&1 || true
        log_ok "✅ 防火墙配置完成"

    # ufw
    elif command -v ufw >/dev/null 2>&1; then
        log_info "使用 UFW 配置"
        ufw --force enable >/dev/null 2>&1 || true

        local existing_rules=$(ufw status 2>/dev/null | grep -E "^[0-9]+" | awk '{print $2}' | sort -u || echo "")
        for port in "${ports[@]}" "${optional_ports[@]}"; do
            local port_num="${port%/*}"
            if ! echo "$existing_rules" | grep -q "$port_num"; then
                ufw allow "$port" >/dev/null 2>&1 || true
                log_info "已开放端口: $port"
            fi
        done

        log_ok "✅ 防火墙配置完成"

    else
        log_warning "未检测到防火墙工具"
    fi
}

# 启动服务
start_services() {
    log_section "启动服务"

    cd "${PROJECT_DIR}"

    log_info "使用 docker compose 启动服务..."

    if docker compose up --build -d; then
        log_ok "✅ 服务启动成功"
    else
        log_error "服务启动失败"
        exit 1
    fi
}

# 创建 systemd 服务
create_systemd_service() {
    log_info "设置开机自启动..."

    local service_name="yuxi-know.service"
    local service_path="/etc/systemd/system/${service_name}"
    local compose_file=$(realpath docker-compose.yml)

    cat > "/tmp/${service_name}" << EOF
[Unit]
Description=Yuxi-Know Docker Compose Services
After=docker.service
Requires=docker.service

[Service]
Type=oneshot
RemainAfterExit=yes
WorkingDirectory=$(dirname "$compose_file")
ExecStart=/usr/bin/docker compose -f ${compose_file} up -d
ExecStop=/usr/bin/docker compose -f ${compose_file} down
TimeoutStartSec=0

[Install]
WantedBy=multi-user.target
EOF

    [ "$(id -u)" -eq 0 ] && mv "/tmp/${service_name}" "$service_path" || sudo mv "/tmp/${service_name}" "$service_path"
    [ "$(id -u)" -eq 0 ] && systemctl daemon-reload && systemctl enable "$service_name" || \
        sudo systemctl daemon-reload && sudo systemctl enable "$service_name"

    log_ok "✅ 已设置开机自启动"
}

# 显示完成信息
show_completion_info() {
    cat << EOF
┌─────────────────────────────────────────────────────────────┐
│  ✅ Yuxi-Know 部署初始化完成！                            │
└─────────────────────────────────────────────────────────────┘

📍 项目信息:
  项目目录: ${PROJECT_DIR}
  数据目录: ${DATA_ROOT}

🌐 访问地址:
  - 前端: http://localhost:5173
  - 后端 API: http://localhost:5050
  - API 文档: http://localhost:5050/docs
  - Neo4j Browser: http://localhost:7474
  - MinIO Console: http://localhost:9001

📋 常用命令:
  查看状态: docker compose ps
  查看日志: docker compose logs -f
  重启服务: docker compose restart
  停止服务: docker compose stop

🚀 开机自启动:
  启动: systemctl start yuxi-know.service
  停止: systemctl stop yuxi-know.service
  状态: systemctl status yuxi-know.service
  禁用: systemctl disable yuxi-know.service
EOF
}

# 主初始化函数
init_deployment() {
    log_section "Yuxi-Know 部署初始化"

    log_info "部署配置:"
    log_info "  项目目录: $PROJECT_DIR"
    log_info "  数据目录: $DATA_ROOT"
    log_info "  Git 分支: $GIT_BRANCH"

    # 1. 环境检查
    log_info "执行环境检查..."
    check_all || exit 1

    # 2. 拉取代码
    setup_repository || exit 1

    # 3. 配置环境变量
    setup_environment || exit 1

    # 4. 创建数据卷目录
    init_data_volumes || exit 1

    # 5. 配置防火墙
    configure_firewall || true

    # 6. 启动服务
    start_services || exit 1

    # 7. 创建 systemd 服务
    create_systemd_service || true

    # 8. 显示完成信息
    show_completion_info
}

# 执行初始化
init_deployment
