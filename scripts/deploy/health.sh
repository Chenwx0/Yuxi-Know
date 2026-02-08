#!/bin/bash

# ============================================================================
# 服务健康检查脚本
# ============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/utils/logger.sh"
source "${SCRIPT_DIR}/config/deploy.conf"

# 解析参数
DETAILED=false
FIX_ISSUES=false
WATCH_MODE=false
WATCH_INTERVAL=30

while [[ $# -gt 0 ]]; do
    case $1 in
        --detailed|-d)
            DETAILED=true
            shift
            ;;
        --fix|-f)
            FIX_ISSUES=true
            shift
            ;;
        --watch|-w)
            WATCH_MODE=true
            if [[ -n "$2" && "$2" =~ ^[0-9]+$ ]]; then
                WATCH_INTERVAL=$2
                shift
            fi
            shift
            ;;
        *)
            shift
            ;;
    esac
done

# 检查容器状态
check_containers() {
    log_info "检查容器状态..."

    local all_running=true
    local failed_services=()

    for service in "${SERVICE_NAMES[@]}"; do
        if docker compose ps -q "$service" | xargs -I {} docker inspect --format='{{.State.Status}}' {} 2>/dev/null | grep -q "running"; then
            log_ok "✅ $service: 运行中"
        else
            log_fail "❌ $service: 未运行"
            all_running=false
            failed_services+=("$service")

            # 显示容器详细信息
            if [ "$DETAILED" = true ]; then
                local state=$(docker compose ps "$service" --format "{{.Status}}" 2>/dev/null || echo "unknown")
                echo "    状态: $state"

                # 显示最近的日志
                echo "    最近日志:"
                docker compose logs --tail=3 "$service" 2>/dev/null | sed 's/^/      /' || true
            fi
        fi
    done

    if [ "$all_running" = false ]; then
        log_warning "异常服务数量: ${#failed_services[@]}"
        return 1
    fi

    return 0
}

# 检查 API 健康端点
check_api_health() {
    log_info "检查 API 健康端点..."

    local api_url="http://localhost:5050/api/system/health"
    local timeout=5

    if curl -sf --max-time "$timeout" "$api_url" > /dev/null 2>&1; then
        log_ok "✅ API 健康检查通过"

        if [ "$DETAILED" = true ]; then
            local health_response=$(curl -s --max-time "$timeout" "$api_url" 2>/dev/null || echo '{}')
            echo "    API 响应: $health_response"

            # 检查关键端点
            log_info "    检查 API 关键端点..."

            local endpoints=(
                "http://localhost:5050/docs"
                "http://localhost:5050/openapi.json"
            )

            for endpoint in "${endpoints[@]}"; do
                if curl -sf --max-time "$timeout" "$endpoint" > /dev/null 2>&1; then
                    echo "    ✅ $(basename "$endpoint")"
                else
                    echo "    ❌ $(basename "$endpoint")"
                fi
            done
        fi

        return 0
    else
        log_fail "❌ API 健康检查失败"
        return 1
    fi
}

# 检查前端访问
check_frontend() {
    log_info "检查前端访问..."

    local frontend_url="http://localhost:5173"
    local timeout=5

    if curl -sf --max-time "$timeout" "$frontend_url" > /dev/null 2>&1; then
        log_ok "✅ 前端可访问"

        if [ "$DETAILED" = true ]; then
            local http_code=$(curl -s -o /dev/null -w "%{http_code}" --max-time "$timeout" "$frontend_url" 2>/dev/null || echo "000")
            echo "    HTTP 状态码: $http_code"

            # 检查静态资源
            if curl -sf --max-time "$timeout" "${frontend_url}/favicon.ico" > /dev/null 2>&1; then
                echo "    ✅ 静态资源可访问"
            fi
        fi

        return 0
    else
        log_fail "❌ 前端无法访问"

        if [ "$DETAILED" = true ]; then
            log_info "    前端可能还在启动中，或者未配置反向代理"
            echo "    请检查: docker compose logs web"
        fi

        return 1
    fi
}

# 检查数据库连接
check_databases() {
    log_info "检查数据库连接..."

    local all_ok=true

    # PostgreSQL
    log_info "  PostgreSQL..."
    if docker compose exec -T postgres pg_isready -U "${POSTGRES_USER:-postgres}" -d "${POSTGRES_DB:-yuxi_know}" > /dev/null 2>&1; then
        log_ok "    ✅ PostgreSQL: 可连接"

        if [ "$DETAILED" = true ]; then
            local db_size=$(docker compose exec -T postgres psql -U "${POSTGRES_USER:-postgres}" -d "${POSTGRES_DB:-yuxi_know}" -tAc "SELECT pg_size_pretty(pg_database_size('${POSTGRES_DB:-yuxi_know}'))" 2>/dev/null || echo "unknown")
            echo "    数据库大小: $db_size"

            local conn_count=$(docker compose exec -T postgres psql -U "${POSTGRES_USER:-postgres}" -d "${POSTGRES_DB:-yuxi_know}" -tAc "SELECT count(*) FROM pg_stat_activity" 2>/dev/null || echo "0")
            echo "    活跃连接数: $conn_count"
        fi
    else
        log_fail "    ❌ PostgreSQL: 连接失败"
        all_ok=false
    fi

    # Neo4j
    log_info "  Neo4j..."
    if curl -sf http://localhost:7474 > /dev/null 2>&1; then
        log_ok "    ✅ Neo4j: 可访问"

        if [ "$DETAILED" = true ]; then
            # 检查节点和关系数量
            local node_count=$(curl -s -H "Content-Type: application/json" \
                -u "${NEO4J_USERNAME:-neo4j}:${NEO4J_PASSWORD:-0123456789}" \
                -d '{"statement":"MATCH (n) RETURN count(n) as count"}' \
                http://localhost:7474/db/neo4j/tx/commit 2>/dev/null | \
                jq -r '.results[0].data[0].row[0]' 2>/dev/null || echo "unknown")

            local rel_count=$(curl -s -H "Content-Type: application/json" \
                -u "${NEO4J_USERNAME:-neo4j}:${NEO4J_PASSWORD:-0123456789}" \
                -d '{"statement":"MATCH ()-[r]->() RETURN count(r) as count"}' \
                http://localhost:7474/db/neo4j/tx/commit 2>/dev/null | \
                jq -r '.results[0].data[0].row[0]' 2>/dev/null || echo "unknown")

            echo "    节点数量: $node_count"
            echo "    关系数量: $rel_count"
        fi
    else
        log_fail "    ❌ Neo4j: 无法访问"
        all_ok=false
    fi

    # Milvus
    log_info "  Milvus..."
    if curl -sf http://localhost:9091/healthz > /dev/null 2>&1; then
        log_ok "    ✅ Milvus: 可访问"
    else
        log_fail "    ❌ Milvus: 无法访问"
        all_ok=false
    fi

    return $([ "$all_ok" = true ] && echo 0 || echo 1)
}

# 检查资源使用
check_resources() {
    log_info "检查资源使用..."

    local header="  %-20s %-10s %-15s %-10s"
    local format="  %-20s %-10s %-15s %-10s"

    printf "$header\n" "服务" "CPU%" "内存" "状态"
    printf "%-20s %-10s %-15s %-10s\n" "--------------------" "--------" "---------------" "--------"

    local high_memory=0

    while IFS= read -r line; do
        local name=$(echo "$line" | awk '{print $1}')
        local cpu=$(echo "$line" | awk '{print $2}' | sed 's/%//')
        local mem=$(echo "$line" | awk '{print $3}')

        printf "$format\n" "$name" "$cpu" "$mem" "OK"

        # 检查内存使用超过 2GB
        local mem_mb=$(echo "$mem" | awk -F'[MG]' '{if ($2=="M") print $1; else if ($2=="G") print $1*1024}')
        if [ "$mem_mb" -gt 2048 ]; then
            log_warning "⚠️  $name 内存使用较高: $mem"
            ((high_memory++))
        fi
    done < <(docker stats --no-stream --format "table {{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}" $(docker compose ps -q) 2>/dev/null | tail -n +2)

    if [ "$high_memory" -gt 0 ]; then
        log_warning "发现 $high_memory 个服务内存使用较高"
    fi
}

# 检查数据卷
check_data_volumes() {
    log_info "检查数据卷..."

    local data_root="${DATA_ROOT}"

    if [ ! -d "$data_root" ]; then
        log_error "数据卷根目录不存在: ${data_root}"
        return 1
    fi

    log_ok "✅ 数据卷根目录存在: ${data_root}"

    if [ "$DETAILED" = true ]; then
        log_info "数据卷磁盘使用:"
        du -h "$data_root" --max-depth=2 2>/dev/null | tail -10 | sed 's/^/  /'

        # 检查数据库数据目录
        local db_dirs=(
            "${POSTGRES_DATA_DIR}"
            "${NEO4J_DATA_DIR}"
            "${MILVUS_DATA_DIR}"
        )

        log_info "数据库数据目录:"
        for dir in "${db_dirs[@]}"; do
            if [ -d "$dir" ]; then
                local size=$(du -sh "$dir" 2>/dev/null | cut -f1)
                local relative_path="${dir#$data_root/}"
                echo "  ${relative_path}: $size"
            fi
        done
    fi

    return 0
}

# 检查网络连接
check_network() {
    log_info "检查网络..."

    network_name="${NETWORK_NAME:-app-network}"

    if docker network inspect "$network_name" >/dev/null 2>&1; then
        log_ok "✅ Docker 网络存在: $network_name"

        if [ "$DETAILED" = true ]; then
            log_info "网络中的容器:"
            docker network inspect "$network_name" --format '{{range .Containers}}{{.Name}} {{end}}' | sed 's/^/  /'
        fi
    else
        log_fail "❌ Docker 网络不存在: $network_name"
        return 1
    fi
}

# 尝试修复问题
fix_issues() {
    log_section "尝试修复问题"

    cd "${PROJECT_DIR}" 2>/dev/null || {
        log_error "项目目录不存在: ${PROJECT_DIR}"
        return 1
    }

    log_info "重启异常容器..."

    for service in "${SERVICE_NAMES[@]}"; do
        if ! docker compose ps -q "$service" | xargs -I {} docker inspect --format='{{.State.Status}}' {} 2>/dev/null | grep -q "running"; then
            log_info "  启动服务: $service"
            docker compose up -d "$service" || true
        fi
    done

    log_info "等待服务启动..."
    sleep 10

    log_error "修复完成，请重新运行健康检查"
}

# 显示健康报告
show_health_report() {
    local exit_code=$1

    log_section "健康检查报告"

    if [ $exit_code -eq 0 ]; then
        cat << EOF
┌─────────────────────────────────────────────────────────────┐
│  ✅ 所有检查通过！系统运行正常                            │
└─────────────────────────────────────────────────────────────┘

系统状态:
  - 所有容器运行正常
  - API 服务健康
  - 前端可访问
  - 数据库连接正常
  - 网络配置正确

建议:
  - 定期监控系统资源使用
  - 及时清理日志和数据快照
  - 保持系统和依赖更新

EOF
        return 0
    else
        cat << EOF
┌─────────────────────────────────────────────────────────────┐
│  ⚠️  健康检查发现问题！                                     │
└─────────────────────────────────────────────────────────────┘

问题排查:
  1. 查看服务日志: docker compose logs -f
  2. 检查容器状态: docker compose ps
  3. 查看资源使用: docker stats

自动修复:
  - 运行: $0 --fix
  - 或: docker compose restart

手动修复:
  1. 停止服务: docker compose stop
  2. 启动服务: docker compose start
  3. 如需完全重建: docker compose down && docker compose up -d

EOF
        return 1
    fi
}

# 监控模式
watch_mode() {
    log_info "进入监控模式 (Ctrl+C 退出)"
    echo "监控间隔: ${WATCH_INTERVAL} 秒"
    echo ""

    while true; do
        clear
        printf "\033[2J\033[H"
        log_section "实时健康监控 - $(date '+%Y-%m-%d %H:%M:%S')"

        cd "${PROJECT_DIR}" 2>/dev/null || {
            log_error "项目目录不存在，无法监控"
            exit 1
        }

        check_containers
        check_api_health
        check_databases
        check_resources

        echo ""
        echo "下次检查: ${WATCH_INTERVAL} 秒后 (按 Ctrl+C 退出)"

        sleep $WATCH_INTERVAL
    done
}

# 主健康检查函数
main_health_check() {
    cd "${PROJECT_DIR}" 2>/dev/null || emergency_exit "项目目录不存在: ${PROJECT_DIR}"

    if [ "$WATCH_MODE" = true ]; then
        watch_mode
        return
    fi

    log_section "执行健康检查"

    local all_healthy=true

    # 执行各项检查
    check_containers || all_healthy=false
    check_api_health || all_healthy=false
    check_frontend || all_healthy=false  # 前端检查失败不视为致命错误
    check_databases || all_healthy=false
    check_resources

    if [ "$DETAILED" = true ]; then
        check_data_volumes
        check_network || all_healthy=false
    fi

    # 显示结果
    if [ "$all_healthy" = true ]; then
        show_health_report 0
        return 0
    else
        show_health_report 1

        if [ "$FIX_ISSUES" = true ]; then
            fix_issues
        fi

        return 1
    fi
}

# 捕获 Ctrl+C
trap 'echo ""; log_warning "监控已停止"; exit 0' INT TERM

# 执行
main_health_check
