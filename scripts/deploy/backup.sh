#!/bin/bash

# ============================================================================
# 数据备份脚本
# ============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/utils/logger.sh"
source "${SCRIPT_DIR}/config/deploy.conf"

# 解析参数
QUICK_MODE=false
COMPRESS=true
UPLOAD_REMOTE=false
REMOTE_PATH=""
DRY_RUN=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --quick|-q)
            QUICK_MODE=true
            shift
            ;;
        --no-compress)
            COMPRESS=false
            shift
            ;;
        --remote|-r)
            UPLOAD_REMOTE=true
            REMOTE_PATH="$2"
            shift 2
            ;;
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        *)
            shift
            ;;
    esac
done

# 创建备份目录
create_backup_dir() {
    local timestamp=$(date +"%Y%m%d_%H%M%S")
    local backup_path="${BACKUP_DIR}/${timestamp}"

    mkdir -p "$backup_path"

    echo "$backup_path"
}

# 清理旧备份
cleanup_old_backups() {
    log_info "清理旧备份（保留 ${BACKUP_RETENTION_DAYS} 天）..."

    local deleted_count=$(find "${BACKUP_DIR}" -maxdepth 1 -type d -mtime +"${BACKUP_RETENTION_DAYS}" -exec rm -rf {} \; 2>/dev/null | wc -l)

    log_ok "✅ 清理完成，删除了 $deleted_count 个旧备份"
}

# 备份数据卷元信息
backup_metadata() {
    local backup_path="$1"

    log_info "备份数据卷元信息..."

    local data_root="${DATA_ROOT}"

    cat > "${backup_path}/data_volumes_info.txt" << EOF
备份时间: $(date)
备份版本: $(cd "${PROJECT_DIR}" && git log -1 --oneline 2>/dev/null || echo "unknown")
数据卷根目录: $(realpath "$data_root" 2>/dev/null || echo "$data_root")
备份模式: $([ "$QUICK_MODE" = true ] && echo "快速" || echo "完整")
压缩模式: $([ "$COMPRESS" = true ] && echo "启用" || echo "禁用")
远程上传: $([ "$UPLOAD_REMOTE" = true ] && echo "启用" || echo "禁用")
EOF

    # 记录数据卷目录结构
    log_info "记录数据卷结构..."
    if command -v tree >/dev/null 2>&1; then
        tree -L 3 "$data_root" > "${backup_path}/data_volume_structure.txt" 2>/dev/null || true
    else
        find "$data_root" -maxdepth 2 -type d > "${backup_path}/data_volume_structure.txt" 2>/dev/null || true
    fi

    log_ok "✅ 元信息已备份"
}

# 备份 PostgreSQL
backup_postgres() {
    local backup_path="$1"

    log_info "备份 PostgreSQL..."

    cd "${PROJECT_DIR}"

    # 记录数据库大小
    local db_size=$(docker compose exec -T postgres psql -U "${POSTGRES_USER:-postgres}" -d "${POSTGRES_DB:-yuxi_know}" -tAc "SELECT pg_size_pretty(pg_database_size('${POSTGRES_DB:-yuxi_know}'))" 2>/dev/null || echo "unknown")
    echo "PostgreSQL 数据库大小: $db_size" >> "${backup_path}/data_volumes_info.txt"

    local backup_file="${backup_path}/postgres.sql"

    if [ "$DRY_RUN" = true ]; then
        log_warning "[DRY RUN] 将备份 PostgreSQL 到 $backup_file"
        return 0
    fi

    # 执行备份
    if docker compose exec -T postgres pg_dump -U "${POSTGRES_USER:-postgres}" \
        "${POSTGRES_DB:-yuxi_know}" > "$backup_file" 2>/dev/null; then

        # 压缩
        if [ "$COMPRESS" = true ]; then
            gzip "$backup_file"
            backup_file="${backup_file}.gz"
        fi

        local backup_size=$(du -h "$backup_file" | cut -f1)
        log_ok "✅ PostgreSQL 备份完成 (${backup_size})"
    else
        log_error "❌ PostgreSQL 备份失败"
        return 1
    fi
}

# 备份 Neo4j
backup_neo4j() {
    local backup_path="$1"

    log_info "备份 Neo4j..."

    cd "${PROJECT_DIR}"

    # 记录 Neo4j 数据大小
    local neo4j_size=$(du -sh "${NEO4J_DATA_DIR}" 2>/dev/null | cut -f1 || echo "unknown")
    echo "Neo4j 数据目录大小: $neo4j_size" >> "${backup_path}/data_volumes_info.txt"

    if [ "$DRY_RUN" = true ]; then
        log_warning "[DRY RUN] 将备份 Neo4j"
        return 0
    fi

    # 方法1: 使用 neo4j-admin dump
    log_info "使用 neo4j-admin dump 备份..."
    local dump_backup_dir="${backup_path}/neo4j_dump"

    if docker compose exec -T neo4j neo4j-admin database dump neo4j \
        --to-path=/var/lib/neo4j/backups --force=true 2>/dev/null; then

        # 复制备份文件到主机
        docker cp neo4j:/var/lib/neo4j/backups/neo4j.dump "${backup_path}/" 2>/dev/null
        log_ok "✅ Neo4j dump 备份完成"
    fi

    # 方法2: 使用 cypher-shell 导出（需要 APOC 插件）
    log_info "尝试使用 cypher-shell 导出..."
    local cypher_backup="${backup_path}/neo4j.cypher"

    if docker compose exec -T neo4j cypher-shell -u "${NEO4J_USERNAME:-neo4j}" \
        -p "${NEO4J_PASSWORD:-0123456789}" "CALL apoc.export.cypher.all('neo4j.cypher', {})" \
        > "$cypher_backup" 2>/dev/null; then

        if [ "$COMPRESS" = true ]; then
            gzip "$cypher_backup"
            cypher_backup="${cypher_backup}.gz"
        fi

        log_ok "✅ Neo4j Cypher 导出完成"
    else
        log_warning "⚠️  Cypher 导出失败（可能未安装 APOC 插件）"
    fi
}

# 备份 Milvus
backup_milvus() {
    local backup_path="$1"

    log_info "备份 Milvus 配置和元数据..."

    cd "${PROJECT_DIR}"

    # 记录 Milvus 数据大小
    local milvus_size=$(du -sh "${MILVUS_DATA_DIR}/milvus" 2>/dev/null | cut -f1 || echo "unknown")
    echo "Milvus 数据目录大小: $milvus_size" >> "${backup_path}/data_volumes_info.txt"

    if [ "$DRY_RUN" = true ]; then
        log_warning "[DRY RUN] 将备份 Milvus 配置"
        return 0
    fi

    # 备份配置文件
    docker compose exec -T milvus cat /milvus/configs/milvus.yaml \
        > "${backup_path}/milvus.conf" 2>/dev/null || log_warning "⚠️  Milvus 配置备份失败"

    # 记录向量集合信息
    docker compose exec -T milvus ls -la /var/lib/milvus \
        > "${backup_path}/milvus_files.txt" 2>/dev/null || true

    log_ok "✅ Milvus 配置已备份"
}

# 备份 MinIO
backup_minio() {
    local backup_path="$1"

    # 快速模式跳过 MinIO 备份（通常数据量很大）
    if [ "$QUICK_MODE" = true ]; then
        log_info "⚡ 快速模式：跳过 MinIO 数据备份"
        return 0
    fi

    log_info "备份 MinIO 数据..."

    cd "${PROJECT_DIR}"

    # 记录 MinIO 数据大小
    local minio_size=$(du -sh "${MILVUS_DATA_DIR}/minio" 2>/dev/null | cut -f1 || echo "unknown")
    echo "MinIO 数据目录大小: $minio_size" >> "${backup_path}/data_volumes_info.txt"

    if [ "$DRY_RUN" = true ]; then
        log_warning "[DRY RUN] 将备份 MinIO 数据"
        return 0
    fi

    # 使用 mc 工具备份
    local minio_backup_dir="${backup_path}/minio"

    docker run --rm --network app-network \
        -v "${backup_path}:/backup" \
        minio/mc sh -c \
        "mc alias set minio http://milvus-minio:9000 ${MINIO_ACCESS_KEY:-minioadmin} ${MINIO_SECRET_KEY:-minioadmin} 2>/dev/null && \
         mc mirror minio /backup/minio" || \
        log_warning "⚠️  MinIO 数据备份失败"

    if [ -d "$minio_backup_dir" ] && [ "$(ls -A $minio_backup_dir)" ]; then
        local backup_size=$(du -sh "$minio_backup_dir" | cut -f1)
        log_ok "✅ MinIO 数据备份完成 (${backup_size})"
    fi
}

# 备份配置文件
backup_configs() {
    local backup_path="$1"

    log_info "备份配置文件..."

    cd "${PROJECT_DIR}"

    mkdir -p "${backup_path}/configs"

    # 备份 .env 文件
    local env_files=(
        "${CONFIG_DIR}/env/.env"
        "${PROJECT_DIR}/.env"
        "${PROJECT_DIR}/.env.template"
    )

    for env_file in "${env_files[@]}"; do
        if [ -f "$env_file" ]; then
            cp "$env_file" "${backup_path}/configs/"
            log_debug "已复制: $(basename "$env_file")"
        fi
    done

    # 备份 docker-compose 文件
    if [ -f "docker-compose.yml" ]; then
        cp docker-compose.yml "${backup_path}/configs/"
    fi

    log_ok "✅ 配置文件已备份"
}

# 备份 saves 和 models 目录
backup_additional_data() {
    local backup_path="$1"

    # 快速模式跳过
    if [ "$QUICK_MODE" = true ]; then
        return 0
    fi

    log_info "备份 saves 和 models 目录..."

    local data_root="${DATA_ROOT}"

    # 备份 saves 目录
    if [ -d "${data_root}/saves" ] && [ "$(ls -A ${data_root}/saves)" ]; then
        log_info "  备份 saves 目录..."
        mkdir -p "${backup_path}/saves"
        cp -r "${data_root}/saves/"* "${backup_path}/saves/" 2>/dev/null || true
    fi

    # models 目录太大，只备份元信息
    if [ -d "${data_root}/models" ] && [ "$(ls -A ${data_root}/models)" ]; then
        log_info "  记录 models 目录信息..."
        ls -lh "${data_root}/models" > "${backup_path}/models_info.txt" 2>/dev/null || true
    fi

    log_ok "✅ 额外数据已备份"
}

# 上传到远程
upload_to_remote() {
    local backup_path="$1"
    local backup_name=$(basename "$backup_path")

    log_info "上传备份到远程..."

    if [ -z "$REMOTE_PATH" ]; then
        log_warning "⚠️  未指定远程路径，跳过上传"
        return 0
    fi

    if [ "$DRY_RUN" = true ]; then
        log_warning "[DRY RUN] 将上传到: ${REMOTE_PATH}/${backup_name}"
        return 0
    fi

    # 使用 rsync 上传
    if command -v rsync >/dev/null 2>&1; then
        log_info "使用 rsync 上传..."
        rsync -avz --progress "$backup_path/" "${REMOTE_PATH}/${backup_name}/" || {
            log_warning "⚠️  rsync 上传失败，尝试使用 scp..."
        }
    fi

    # 如果 rsync 失败，尝试 scp
    if command -v scp >/dev/null 2>&1 && [ ! -d "${REMOTE_PATH}/${backup_name}" ]; then
        log_info "使用 scp 上传..."
        scp -r "$backup_path" "${REMOTE_PATH}/" 2>/dev/null || {
            log_error "❌ 远程上传失败"
            return 1
        }
    fi

    log_ok "✅ 远程上传完成"
}

# 计算备份大小
calculate_backup_size() {
    local backup_path="$1"

    local total_size=$(du -sh "$backup_path" 2>/dev/null | cut -f1)
    echo "$total_size" >> "${backup_path}/data_volumes_info.txt"

    log_info "备份大小: $total_size"
}

# 显示备份摘要
show_backup_summary() {
    local backup_path="$1"
    local exit_code=$2

    log_section "备份完成"

    if [ $exit_code -eq 0 ]; then
        cat << EOF
┌─────────────────────────────────────────────────────────────┐
│  ✅ 备份成功！                                             │
└─────────────────────────────────────────────────────────────┘

备份信息:
  备份路径: $backup_path
  备份时间: $(date)
  备份大小: $(du -sh "$backup_path" 2>/dev/null | cut -f1)
  备份模式: $([ "$QUICK_MODE" = true ] && echo "快速" || echo "完整")

备份内容:
  - PostgreSQL 数据库
  - Neo4j 知识图谱
  - Milvus 配置和元数据
  $([ "$QUICK_MODE" = false ] && echo "- MinIO 对象存储")
  - 配置文件 (.env, docker-compose.yml)
  - 数据卷元信息

恢复命令:
  ${SCRIPT_DIR}/deploy.sh rollback --backup $(basename "$backup_path")

远程上传:
  $([ "$UPLOAD_REMOTE" = true ] && echo "已上传到: ${REMOTE_PATH}" || echo "未启用")

保留策略:
  - 自动清理 ${BACKUP_RETENTION_DAYS} 天前的备份

安全建议:
  1. 将备份复制到异地存储
  2. 定期测试备份恢复
  3. 加密敏感数据备份

EOF
    else
        cat << EOF
┌─────────────────────────────────────────────────────────────┐
│  ❌ 备份失败！                                             │
└─────────────────────────────────────────────────────────────┘

可能的原因:
  1. 容器服务未运行
  2. 磁盘空间不足
  3. 权限问题
  4. 数据库连接失败

排查步骤:
  1. 检查容器状态: docker compose ps
  2. 查看服务日志: docker compose logs
  3. 检查磁盘空间: df -h
  4. 重新执行备份: ${SCRIPT_DIR}/deploy.sh backup

EOF
    fi

    return $exit_code
}

# 主备份函数
main_backup() {
    log_section "开始数据备份"

    cd "${PROJECT_DIR}" 2>/dev/null || emergency_exit "项目目录不存在: ${PROJECT_DIR}"

    # 创建备份目录
    local backup_path=$(create_backup_dir)
    log_info "备份目录: $backup_path"

    # 执行各项备份
    backup_metadata "$backup_path"
    backup_postgres "$backup_path"
    backup_neo4j "$backup_path"
    backup_milvus "$backup_path"
    backup_minio "$backup_path"
    backup_configs "$backup_path"
    backup_additional_data "$backup_path"

    # 计算大小
    calculate_backup_size "$backup_path"

    # 远程上传（如果启用）
    if [ "$UPLOAD_REMOTE" = true ]; then
        upload_to_remote "$backup_path" || true
    fi

    # 清理旧备份
    cleanup_old_backups

    # 显示摘要
    show_backup_summary "$backup_path" 0
}

# 捕获中断信号
trap 'log_warning "\n备份被中断"; exit 1' INT TERM

# 执行
main_backup
