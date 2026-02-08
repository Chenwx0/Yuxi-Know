#!/bin/bash

# ============================================================================
# 版本回滚脚本
# ============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/utils/logger.sh"
source "${SCRIPT_DIR}/config/deploy.conf"

# 解析参数
TARGET_VERSION=""
RESTORE_DATA=false
SELECTED_BACKUP=""

while [[ $# -gt 0 ]]; do
    case $1 in
        --data|-d)
            RESTORE_DATA=true
            shift
            ;;
        --backup|-b)
            SELECTED_BACKUP="$2"
            shift 2
            ;;
        *)
            if [ -z "$TARGET_VERSION" ]; then
                TARGET_VERSION="$1"
            fi
            shift
            ;;
    esac
done

# 回滚数据
rollback_data() {
    local backup_path="$1"

    log_section "恢复数据卷数据"

    local data_root="${DATA_ROOT}"

    log_warning "⚠️  即将从备份恢复数据: ${backup_path}"
    log_warning "  目标目录: ${data_root}"
    log_warning "  此操作将覆盖现有数据！"
    log_warning ""
    log_error "⚠️  这是一个危险操作，请确保："
    log_error "   1. 已备份当前数据"
    log_error "   2. 确认备份文件完整"
    log_error "   3. 知道此操作的后果"

    read -p "确认恢复数据? (输入 RESTORE 确认): " confirm
    if [ "$confirm" != "RESTORE" ]; then
        log_info "数据恢复已取消"
        return 0
    fi

    # 恢复前再备份一次
    log_info "执行恢复前备份..."
    local pre_restore_backup="${BACKUP_DIR}/pre_restore_$(date +%Y%m%d_%H%M%S)"
    mkdir -p "$pre_restore_backup"

    cd "${PROJECT_DIR}"

    docker compose exec -T postgres pg_dump -U "${POSTGRES_USER:-postgres}" \
        "${POSTGRES_DB:-yuxi_know}" | gzip > "${pre_restore_backup}/postgres.sql.gz" 2>/dev/null || true

    log_ok "✅ 恢复前备份已保存: $pre_restore_backup"

    # 恢复 PostgreSQL
    log_info "恢复 PostgreSQL 数据..."
    local postgres_backup="${backup_path}/postgres.sql"
    if [ -f "$postgres_backup" ]; then
        if [[ "$postgres_backup" == *.gz ]]; then
            docker compose exec -T postgres psql -U "${POSTGRES_USER:-postgres}" \
                -d "${POSTGRES_DB:-yuxi_know}" < <(zcat "$postgres_backup")
        else
            docker compose exec -T postgres psql -U "${POSTGRES_USER:-postgres}" \
                -d "${POSTGRES_DB:-yuxi_know}" < "$postgres_backup"
        fi
        log_ok "✅ PostgreSQL 恢复完成"
    else
        log_error "❌ PostgreSQL 备份文件不存在: $postgres_backup"
        return 1
    fi

    # 恢复 Neo4j
    log_info "恢复 Neo4j 数据..."

    # 尝试使用 dump 文件
    if [ -f "${backup_path}/neo4j.dump" ]; then
        log_info "使用 Neo4j dump 文件恢复..."
        docker compose cp "${backup_path}/neo4j.dump" neo4j:/var/lib/neo4j/backups/
        docker compose exec -T neo4j neo4j-admin database load neo4j \
            --from-path=/var/lib/neo4j/backups/ --force=true 2>/dev/null && \
            log_ok "✅ Neo4j 数据库恢复完成"
    fi

    # 尝试使用 Cypher 文件
    local neo4j_cypher="${backup_path}/neo4j.cypher"
    if [ -f "$neo4j_cypher" ]; then
        log_info "使用 Cypher 文件恢复..."

        # 解压（如果需要）
        local cypher_file="$neo4j_cypher"
        if [[ "$neo4j_cypher" == *.gz ]]; then
            log_info "解压 Cypher 文件..."
            cypher_file="${backup_path}/neo4j-temp.cypher"
            zcat "$neo4j_cypher" > "$cypher_file"
        fi

        # 先清空数据库
        docker compose exec -T neo4j cypher-shell -u "${NEO4J_USERNAME:-neo4j}" \
            -p "${NEO4J_PASSWORD:-0123456789}" "MATCH (n) DETACH DELETE n" 2>/dev/null || true

        # 执行恢复
        docker compose exec -T neo4j cypher-shell -u "${NEO4J_USERNAME:-neo4j}" \
            -p "${NEO4J_PASSWORD:-0123456789}" < "$cypher_file" 2>/dev/null && \
            log_ok "✅ Neo4j 数据恢复完成" || \
            log_warning "⚠️  Neo4j 数据恢复失败（可能数据为空）"

        # 清理临时文件
        if [ -n "$neo4j_cypher" ] && [ -f "$cypher_file" ]; then
            rm -f "$cypher_file"
        fi
    else
        log_info "Neo4j 备份不存在，跳过"
    fi

    # 恢复 MinIO 数据
    if [ -d "${backup_path}/minio" ] && [ "$(ls -A ${backup_path}/minio)" ]; then
        log_info "恢复 MinIO 数据..."
        docker cp "${backup_path}/minio/." milvus-minio:/minio_data/ 2>/dev/null || \
            log_warning "⚠️  MinIO 数据恢复失败"
        log_ok "✅ MinIO 数据恢复完成"
    fi

    # 恢复 saves 目录
    if [ -d "${backup_path}/saves" ] && [ "$(ls -A ${backup_path}/saves)" ]; then
        log_info "恢复 saves 目录..."
        rm -rf "${data_root}/saves"/*
        cp -r "${backup_path}/saves/"* "${data_root}/saves/" 2>/dev/null || \
            log_warning "⚠️  saves 目录恢复失败"
        log_ok "✅ saves 目录恢复完成"
    fi

    # 恢复配置文件
    if [ -d "${backup_path}/configs" ]; then
        log_info "恢复配置文件..."
        if [ -f "${backup_path}/configs/.env" ]; then
            cp "${backup_path}/configs/.env" "${PROJECT_DIR}/.env"
            cp "${backup_path}/configs/.env" "${CONFIG_DIR}/env/" 2>/dev/null || true
            log_ok "✅ .env 文件已恢复"
        fi
    fi

    # 重启数据库服务
    log_info "重启数据库服务..."
    docker compose restart postgres neo4j milvus minio
    sleep 30

    log_success "✅ 数据恢复完成！"
}

# 列出可用备份
list_backups() {
    log_info "可用的备份："
    echo ""

    local backups=($(ls -t "${BACKUP_DIR}" 2>/dev/null | grep -E "^[0-9]{8}_[0-9]{6}$" || true))

    if [ ${#backups[@]} -eq 0 ]; then
        log_warning "未找到备份"
        return 1
    fi

    local index=1
    for backup in "${backups[@]}"; do
        local backup_path="${BACKUP_DIR}/${backup}"
        local info_file="${backup_path}/data_volumes_info.txt"

        echo "  [$index] $backup"

        # 显示备份信息
        if [ -f "$info_file" ]; then
            local backup_time=$(grep "^备份时间:" "$info_file" | cut -d' ' -f2- || echo "unknown")
            local backup_size=$(du -sh "$backup_path" 2>/dev/null | cut -f1 || echo "unknown")
            echo "      时间: $backup_time"
            echo "      大小: $backup_size"
        fi

        ((index++))
    done

    echo ""
}

# 选择备份
select_backup() {
    if [ -n "$SELECTED_BACKUP" ]; then
        if [ -d "${BACKUP_DIR}/${SELECTED_BACKUP}" ]; then
            echo "${BACKUP_DIR}/${SELECTED_BACKUP}"
            return 0
        else
            log_error "指定的备份不存在: ${SELECTED_BACKUP}"
            list_backups
            return 1
        fi
    fi

    list_backups

    local backups=($(ls -t "${BACKUP_DIR}" 2>/dev/null | grep -E "^[0-9]{8}_[0-9]{6}$" || true))

    if [ ${#backups[@]} -eq 0 ]; then
        log_error "无可用备份"
        return 1
    fi

    echo ""
    read -p "请选择要恢复的备份编号 [1-${#backups[@]}]: " selection

    if [[ ! "$selection" =~ ^[0-9]+$ ]] || [ "$selection" -lt 1 ] || [ "$selection" -gt ${#backups[@]} ]; then
        log_error "无效的选择"
        return 1
    fi

    local selected_backup="${backups[$((selection - 1))]}"
    echo "${BACKUP_DIR}/${selected_backup}"
}

# 主回滚函数
rollback_deployment() {
    log_section "执行版本回滚"

    cd "${PROJECT_DIR}" 2>/dev/null || emergency_exit "项目目录不存在: ${PROJECT_DIR}"

    # 确定目标版本
    local target_version="$TARGET_VERSION"

    if [ -z "$target_version" ]; then
        log_info "显示最近的版本历史："
        echo ""
        git log --oneline -10 | sed 's/^/  /'
        echo ""

        read -p "请输入要回滚到的版本（commit hash 或留空选择最新备份）: " target_version
    fi

    # 如果指定了版本，显示版本信息
    if [ -n "$target_version" ]; then
        log_info "回滚到版本: ${target_version:0:8}"
        log_info "当前版本: $(git log -1 --oneline)"
        echo ""

        # 显示版本差异
        if git rev-parse --verify "$target_version" >/dev/null 2>&1; then
            log_info "版本信息:"
            git log -1 --format="%h - %an, %ar : %s" "$target_version" | sed 's/^/  /'
            echo ""
        else
            log_error "指定的版本不存在: $target_version"
            exit 1
        fi
    fi

    # 确认回滚
    log_error "⚠️  即将执行回滚操作"
    if [ -n "$target_version" ]; then
        log_warning "  代码回滚: ${target_version:0:8}"
    fi
    if [ "$RESTORE_DATA" = true ]; then
        log_warning "  数据恢复: 将从备份恢复数据库和配置"
    fi
    log_warning ""
    log_error "此操作将："
    log_error "  1. 切换代码到指定版本"
    if [ "$RESTORE_DATA" = true ]; then
        log_error "  2. 恢复数据库到备份状态"
        log_error "  3. 覆盖现有配置文件"
    fi
    log_error "  4. 重新构建并重启服务"

    read -p "确认回滚? (输入 YES 确认): " confirm
    if [ "$confirm" != "YES" ]; then
        log_info "回滚已取消"
        exit 0
    fi

    # 记录当前版本（用于可能的双重回滚）
    local current_commit=$(git rev-parse HEAD)
    local pre_rollback_backup="${BACKUP_DIR}/before_rollback_${current_commit}"
    mkdir -p "$pre_rollback_backup"

    log_info "备份当前状态..."
    cd "${PROJECT_DIR}"

    docker compose exec -T postgres pg_dump -U "${POSTGRES_USER:-postgres}" \
        "${POSTGRES_DB:-yuxi_know}" | gzip > "${pre_rollback_backup}/postgres.sql.gz" 2>/dev/null || true

    # 数据恢复
    if [ "$RESTORE_DATA" = true ]; then
        local backup_path=$(select_backup)
        if [ $? -ne 0 ]; then
            log_warning "数据恢复失败，继续代码回滚"
        else
            rollback_data "$backup_path" || {
                log_error "数据恢复失败，代码继续回滚"
            }
        fi
    fi

    # 代码回滚
    if [ -n "$target_version" ]; then
        log_info "回滚代码..."
        git checkout "$target_version"
        log_ok "✅ 代码已回滚到 ${target_version:0:8}"
    fi

    # 重建镜像
    log_info "重建镜像..."
    docker compose build --no-cache api web 2>/dev/null || {
        log_warning "镜像构建可能使用了缓存"
        docker compose build api web
    }

    # 停止服务
    log_info "停止服务..."
    docker compose stop

    # 重启数据库服务（优先）
    log_info "启动数据库服务..."
    docker compose up -d postgres neo4j milvus minio
    log_info "等待数据库服务启动..."
    sleep 30

    # 启动应用服务
    log_info "启动应用服务..."
    docker compose up -d api web
    log_info "等待应用服务启动..."
    sleep 15

    # 健康检查
    log_info "执行健康检查..."

    local max_retries=6
    local retry_count=0
    local retry_interval=10

    while [ $retry_count -lt $max_retries ]; do
        log_info "健康检查 attempt $((retry_count + 1))/$max_retries..."

        # 检查容器状态
        local all_running=true
        for service in "${SERVICE_NAMES[@]}"; do
            if ! docker compose ps -q "$service" | xargs -I {} docker inspect --format='{{.State.Status}}' {} 2>/dev/null | grep -q "running"; then
                log_debug "$service 未运行"
                all_running=false
            fi
        done

        # 检查 API
        if $all_running && curl -sf http://localhost:5050/api/system/health > /dev/null 2>&1; then
            log_success "✅ 健康检查通过"
            break
        fi

        ((retry_count++))
        if [ $retry_count -lt $max_retries ]; then
            sleep $retry_interval
        fi
    done

    if [ $retry_count -ge $max_retries ]; then
        log_error "❌ 健康检查失败"
        log_info "请检查服务日志: docker compose logs"
        log_warning "可以尝试回滚到之前版本: git checkout $current_commit"
        emergency_exit "回滚后健康检查失败"
    fi

    # 记录部署
    local rollback_info="回滚到 ${target_version:0:8} (从 ${current_commit:0:8})"
    if [ "$RESTORE_DATA" = true ]; then
        rollback_info="${rollback_info}，数据已恢复"
    fi
    record_deployment "rollback" "$rollback_info"

    # 显示完成信息
    show_rollback_complete "$target_version" "$current_commit"
}

# 显示回滚完成信息
show_rollback_complete() {
    local target_version="$1"
    local previous_version="$2"

    log_section "回滚完成"

    cat << EOF
┌─────────────────────────────────────────────────────────────┐
│  ✅ 回滚完成！                                             │
└─────────────────────────────────────────────────────────────┘

回滚信息:
  目标版本: ${target_version:0:8}
  之前的版本: ${previous_version:0:8}
  $([ "$RESTORE_DATA" = true ] && echo "数据已恢复: 是" || echo "数据已恢复: 否")

服务状态:
  运行中: $(docker compose ps --services --filter "status=running" | wc -l)
  总数: $(docker compose config --services | wc -l)

访问地址:
  - 前端: http://localhost:5173
  - 后端: http://localhost:5050
  - API 文档: http://localhost:5050/docs

后续操作:
  1. 测试基本功能
  2. 检查数据完整性
  3. 分析回滚原因

如果需要再次回滚:
  回到之前版本: ${SCRIPT_DIR}/deploy.sh rollback ${previous_version:0:8}

备份数据已保存:
  ${BACKUP_DIR}/before_rollback_${previous_version}

EOF
}

# 捕获中断信号
trap 'log_warning "\n回滚被中断"; exit 1' INT TERM

# 执行
rollback_deployment
