#!/bin/bash

# ============================================================================
# 数据卷管理工具
# ============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/utils/logger.sh"
source "${SCRIPT_DIR}/config/deploy.conf"

# 帮助信息
usage() {
    cat << EOF
用法: $0 [命令] [选项]

命令:
  usage      显示数据卷使用情况
  clean-logs 清理数据卷日志（7 天前）
  verify     验证数据卷完整性
  migrate    迁移数据卷到新位置

选项:
  --help, -h 显示此帮助信息

示例:
  $0 usage          # 查看数据卷使用情况
  $0 clean-logs     # 清理日志
  $0 verify        # 验证数据卷完整性
  $0 migrate /data/new-yuxi-know  # 迁移数据卷

EOF
}

# 显示数据卷使用情况
show_usage() {
    log_section "数据卷使用情况"

    local data_root="${DATA_ROOT}"

    if [ ! -d "$data_root" ]; then
        log_error "数据卷根目录不存在: ${data_root}"
        log_info "请运行部署初始化: ${SCRIPT_DIR}/deploy.sh init"
        exit 1
    fi

    echo "数据卷根目录: $(realpath "$data_root" 2>/dev/null || echo "$data_root")"
    echo ""

    # 总体使用情况
    log_info "总体磁盘使用:"
    df -h "$data_root" | tail -1 | awk '{printf "  总空间: %s\n  已用: %s\n  可用: %s\n  使用率: %s\n", $2, $3, $4, $5}'
    echo ""

    # 总大小
    local total_size=$(du -sh "$data_root" 2>/dev/null | cut -f1)
    echo "  总大小: $total_size"
    echo ""

    # 分目录使用情况
    log_info "各目录使用情况:"
    printf "  %-25s %15s\n" "目录" "大小"
    printf "  %-25s %15s\n" "-------------------------" "---------------"

    for dir in "${SAVES_DIR}" "${MODELS_DIR}" "${LOGS_DIR}" "${CONFIG_DIR}"; do
        if [ -d "$dir" ]; then
            local size=$(du -sh "$dir" 2>/dev/null | cut -f1)
            local relative_path="${dir#$data_root/}"
            printf "  %-25s %15s\n" "$relative_path/" "$size"
        fi
    done

    echo ""

    # 数据库数据目录
    log_info "数据库数据目录:"
    printf "  %-25s %15s\n" "目录" "大小"
    printf "  %-25s %15s\n" "-------------------------" "---------------"

    local db_dirs=(
        "${POSTGRES_DATA_DIR}"
        "${NEO4J_DATA_DIR}"
        "${MILVUS_DATA_DIR}"
    )

    for db_dir in "${db_dirs[@]}"; do
        if [ -d "$db_dir" ]; then
            local size=$(du -sh "$db_dir" 2>/dev/null | cut -f1)
            local relative_path="${db_dir#$data_root/}"
            printf "  %-25s %15s\n" "$relative_path/" "$size"

            # 显示子目录
            if [ -d "$db_dir" ]; then
                declare -A subdirs
                while IFS= read -r subdir; do
                    local subname=$(basename "$subdir")
                    local subsize=$(du -sh "$subdir" 2>/dev/null | cut -f1)
                    subdirs["$subname/"]="$subsize"
                done < <(find "$db_dir" -maxdepth 1 -type d | sort)

                for subname in "${!subdirs[@]}"; do
                    printf "    %-23s %15s\n" "$subname" "${subdirs[$subname]}"
                done
            fi
        fi
    done

    echo ""

    # Milvus 和 MinIO 子目录
    log_info "Milvus 子目录:"
    printf "  %-25s %15s\n" "目录" "大小"
    printf "  %-25s %15s\n" "-------------------------" "---------------"

    for sub_dir in "milvus/milvus" "milvus/minio" "milvus/etcd" "milvus/logs"; do
        local full_path="${data_root}/data/${sub_dir}"
        if [ -d "$full_path" ]; then
            local size=$(du -sh "$full_path" 2>/dev/null | cut -f1)
            printf "  %-25s %15s\n" "${sub_dir}/" "$size"
        fi
    done

    echo ""

    # 文件统计
    log_info "文件统计:"
    echo "  PostgreSQL 数据文件: $(find "${POSTGRES_DATA_DIR}" -type f 2>/dev/null | wc -l)"
    echo "  Neo4j 数据文件: $(find "${NEO4J_DATA_DIR}" -type f 2>/dev/null | wc -l)"
    echo "  Milvus 数据文件: $(find "${MILVUS_DATA_DIR}" -type f 2>/dev/null | wc -l)"
    echo "  MinIO 对象文件: $(find "${data_root}/data/milvus/minio" -type f 2>/dev/null | wc -l)"
    echo ""

    # 权限检查
    log_info "目录权限:"
    echo "  数据卷根目录: $(stat -c '%a' "$data_root" 2>/dev/null || echo 'unknown') ($(stat -c '%U:%G' "$data_root" 2>/dev/null || echo 'unknown'))"
    echo ""

    # 推荐操作
    log_info "推荐操作:"
    if [ "$(find "${LOGS_DIR}" -type f -mtime +7 2>/dev/null | wc -l)" -gt 0 ]; then
        echo "  ⚠️  发现超过 7 天的日志文件，建议清理: $0 clean-logs"
    fi

    local disk_percent=$(df -P "$data_root" 2>/dev/null | tail -1 | awk '{print $5}' | sed 's/%//')
    if [ "$disk_percent" -gt 80 ]; then
        echo "  ⚠️  磁盘使用率超过 80%，建议:"
        echo "     1. 清理旧日志: $0 clean-logs"
        echo "     2. 清理 Docker 未使用的资源: docker system prune -a"
    fi
}

# 清理数据卷日志
clean_logs() {
    log_section "清理数据卷日志"

    local data_root="${DATA_ROOT}"
    local logs_dir="${LOGS_DIR}"

    if [ ! -d "$logs_dir" ]; then
        log_warning "日志目录不存在: $logs_dir"
        return 0
    fi

    log_info "清理日志目录: $logs_dir"

    # 统计清理前的信息
    local before_size=$(du -sh "$logs_dir" 2>/dev/null | cut -f1)
    local before_count=$(find "$logs_dir" -type f 2>/dev/null | wc -l)

    log_info "清理前 大小: $before_size, 文件数: $before_count"
    echo ""

    # 查找 7 天前的日志文件
    log_info "清理 7 天前的日志文件..."

    local deleted_count=0
    local deleted_size=0

    while IFS= read -r -d '' logfile; do
        local size=$(du -k "$logfile" 2>/dev/null | cut -f1)
        deleted_size=$((deleted_size + size))

        rm -f "$logfile"
        ((deleted_count++))

        log_debug "已删除: $(basename "$logfile") ($(du -h "$logfile" 2>/dev/null | cut -f1))"
    done < <(find "$logs_dir" -type f -name "*.log" -mtime +7 -print0)

    echo ""

    # 统计清理后的信息
    local After_count=$(find "$logs_dir" -type f 2>/dev/null | wc -l)
    local after_size=$(du -sh "$logs_dir" 2>/dev/null | cut -f1)
    local deleted_size_mb=$((deleted_size / 1024))

    log_ok "✅ 日志清理完成"
    log_info "清理前: $before_size, $before_count 个文件"
    log_info "清理后: $after_size, $After_count 个文件"
    log_info "释放空间: ${deleted_size_mb}MB, 已删除 $deleted_count 个文件"

    Docker 日志清理（可选）
    log_warning "提示：Docker 容器日志可能也占用大量空间"
    log_info "清理 Docker 日志: docker system prune -a"
}

# 验证数据卷完整性
verify_integrity() {
    log_section "验证数据卷完整性"

    local data_root="${DATA_ROOT}"

    log_info "检查数据卷根目录: $data_root"

    if [ ! -d "$data_root" ]; then
        log_error "数据卷根目录不存在: $data_root"
        log_info "是否创建数据卷目录? (y/N)"
        read -r create_root
        if [[ $create_root =~ ^[Yy]$ ]]; then
            mkdir -p "$data_root"
            log_ok "✅ 已创建数据卷根目录"
        else
            exit 1
        fi
    fi

    # 检查目录结构
    log_info "检查目录结构..."

    local missing_dirs=()
    local invalid_perms=()

    for dir in "${DATA_DIRECTORIES[@]}"; do
        if [ ! -d "$dir" ]; then
            log_fail "❌ 缺失目录: $dir"
            missing_dirs+=("$dir")
        else
            log_ok "✅ $dir"

            # 检查数据库目录权限
            case "$dir" in
                *"postgres"*|*"neo4j"*|*"milvus"*|*"minio"*)
                    local perms=$(stat -c '%a' "$dir" 2>/dev/null || echo "000")
                    if [ "$perms" != "700" ] && [ "$perms" != "755" ]; then
                        log_warning "⚠️  ${dir} 权限异常: ${perms}（建议 700 或 755）"
                        invalid_perms+=("$dir:$perms")
                    fi
                    ;;
            esac
        fi
    done

    echo ""

    # 处理缺失目录
    if [ ${#missing_dirs[@]} -gt 0 ]; then
        log_warning "发现 ${#missing_dirs[@]} 个缺失目录"

        read -p "是否创建缺失目录? (y/N): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            for dir in "${missing_dirs[@]}"; do
                log_info "创建目录: $dir"
                mkdir -p "$dir"
                log_ok "✅ 已创建: $dir"
            done
        fi
    else
        log_success "✅ 所有必需目录存在"
    fi

    echo ""

    # 处理权限问题
    if [ ${#invalid_perms[@]} -gt 0 ]; then
        log_warning "发现 ${#invalid_perms[@]} 个权限异常的目录"

        for perm_info in "${invalid_perms[@]}"; do
            local dir="${perm_info%%:*}"
            local perms="${perm_info##*:}"
            log_info "  $dir: $perms"
        done

        read -p "是否修复权限为 755? (y/N): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            for perm_info in "${invalid_perms[@]}"; do
                local dir="${perm_info%%:*}"
                chmod 755 "$dir"
                log_ok "✅ 已修复: $dir"
            done
        fi
    else
        log_success "✅ 目录权限正常"
    fi

    echo ""

    # 检查磁盘空间
    log_info "检查磁盘空间..."

    local required_space=${REQUIRED_DISK_SPACE_GB:-10}

    # 获取挂载点
    local mount_point=$(df -P "$data_root" 2>/dev/null | tail -1 | awk '{print $6}')
    local available_mb=$(df -m "$mount_point" 2>/dev/null | tail -1 | awk '{print $4}')
    local available_gb=$((available_mb / 1024))

    printf "  总空间: %s\n" "$(df -h "$data_root" 2>/dev/null | tail -1 | awk '{print $2}')"
    printf "  已用: %s\n" "$(df -h "$data_root" 2>/dev/null | tail -1 | awk '{print $3}')"
    printf "  可用: %s\n" "$(df -h "$data_root" 2>/dev/null | tail -1 | awk '{print $4}')"

    if [ "$available_gb" -lt "$required_space" ]; then
        log_error "❌ 磁盘空间不足！"
        log_error "  要求: 最少 ${required_space}GB"
        log_error "  可用: ${available_gb}GB"
    else
        log_ok "✅ 磁盘空间充足（要求: ${required_space}GB, 可用: ${available_gb}GB）"
    fi

    echo ""

    # 检查文件描述符
    log_info "检查数据文件完整性..."

    local corrupted_count=0

    for db_dir in "${POSTGRES_DATA_DIR}" "${NEO4J_DATA_DIR}"; do
        if [ -d "$db_dir" ]; then
            # 简单检查：是否有文件
            local file_count=$(find "$db_dir" -type f 2>/dev/null | wc -l)

            if [ "$file_count" -eq 0 ]; then
                log_warning "⚠️  $db_dir 没有数据文件"
            else
                # 检查是否有 0 字节的大文件（可能是损坏）
                local zero_byte_files=$(find "$db_dir" -type f -size 0 2>/dev/null | wc -l)

                if [ "$zero_byte_files" -gt 0 ]; then
                    log_warning "⚠️  $db_dir 发现 $zero_byte_files 个 0 字节文件"
                    ((corrupted_count++))
                fi
            fi
        fi
    done

    if [ "$corrupted_count" -eq 0 ]; then
        log_ok "✅ 未发现明显的数据损坏"
    fi

    echo ""

    # 生成报告
    log_section "验证报告"

    if [ ${#missing_dirs[@]} -eq 0 ] && [ ${#invalid_perms[@]} -eq 0 ] && [ "$corrupted_count" -eq 0 ]; then
        log_success "✅ 数据卷完整性验证通过！"
        return 0
    else
        log_error "❌ 数据卷完整性验证发现问题"
        log_info "  缺失目录: ${#missing_dirs[@]} 个"
        log_info "  权限异常: ${#invalid_perms[@]} 个"
        log_info "  数据问题: $corrupted_count 项"
        return 1
    fi
}

# 迁移数据卷
migrate_data() {
    local new_data_root="$1"

    log_section "迁移数据卷"

    local old_data_root="${DATA_ROOT}"

    # 检查新路径
    if [ -z "$new_data_root" ]; then
        log_error "请指定目标目录"
        exit 1
    fi

    log_warning "⚠️  即将迁移数据卷:"
    log_info "  源目录: $(realpath "$old_data_root" 2>/dev/null || echo "$old_data_root")"
    log_info "  目标目录: $(realpath "$new_data_root" 2>/dev/null || echo "$new_data_root")"
    echo ""

    # 检查目标目录
    if [ -e "$new_data_root" ]; then
        log_error "目标目录已存在: $new_data_root"
        log_info "请指定一个新的目录"
        exit 1
    fi

    # 检查源目录
    if [ ! -d "$old_data_root" ]; then
        log_error "源数据卷目录不存在: $old_data_root"
        exit 1
    fi

    # 停止服务
    log_info "停止所有服务（迁移需要停止服务）..."
    cd "${PROJECT_DIR}" 2>/dev/null || exit 1

    if docker compose ps -a | grep -q "Up"; then
        read -p "是否停止所有服务? (服务将不可用) (y/N): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            docker compose stop
            log_ok "✅ 服务已停止"
        else
            log_info "迁移取消"
            exit 0
        fi
    fi

    # 计算迁移数据大小
    log_info "计算迁移数据大小..."
    local total_size=$(du -sh "$old_data_root" 2>/dev/null | cut -f1)
    local total_kb=$(du -sk "$old_data_root" 2>/dev/null | cut -f1)
    local total_size_mb=$((total_kb / 1024))

    log_info "迁移数据大小: $total_size (约 ${total_size_mb}MB)"
    echo ""

    # 确认迁移
    log_error "⚠️  数据迁移注意事项:"
    log_error "  1. 迁移过程需要较长时间"
    log_error "  2. 确保目标磁盘有足够空间"
    log_error "  3. 迁移期间服务不可用"
    log_error "  4. 建议在备份后进行"
    echo ""

    read -p "确认迁移? (输入 MIGRATE 确认): " confirm
    if [ "$confirm" != "MIGRATE" ]; then
        log_info "迁移已取消"
        exit 0
    fi

    # 创建目标目录
    log_info "创建目标目录..."
    mkdir -p "$(dirname "$new_data_root")"
    mkdir -p "$new_data_root"

    # 执行迁移
    log_info "开始迁移（使用 rsync 保留权限和时间戳）..."
    log_info "这可能需要较长时间..."

    local start_time=$(date +%s)

    if command -v rsync >/dev/null 2>&1; then
        rsync -av --progress "$old_data_root/" "$new_data_root/" 2>/dev/null
    else
        log_warning "rsync 不可用，使用 cp..."
        cp -r -p "$old_data_root/"* "$new_data_root/"
    fi

    local end_time=$(date +%s)
    local duration=$((end_time - start_time))
    local minutes=$((duration / 60))
    local seconds=$((duration % 60))

    log_ok "✅ 数据迁移完成"
    log_info "耗时: ${minutes} 分 ${seconds} 秒"
    echo ""

    # 验证迁移
    log_info "验证迁移结果..."

    local old_size_kb=$(du -sk "$old_data_root" 2>/dev/null | cut -f1)
    local new_size_kb=$(du -sk "$new_data_root" 2>/dev/null | cut -f1)

    log_info "源目录大小: $((old_size_kb / 1024))MB"
    log_info "目标目录大小: $((new_size_kb / 1024))MB"

    local size_diff=$((new_size_kb - old_size_kb))
    if [ $size_diff -gt 1024 ]; then
        log_warning "⚠️  大小差异较大 (${size_diff}KB)"
    else
        log_ok "✅ 数据大小一致"
    fi

    echo ""

    # 更新配置
    log_info "更新配置文件..."

    # 更新 .env
    local env_files=(
        "${PROJECT_DIR}/.env"
        "${CONFIG_DIR}/env/.env"
    )

    for env_file in "${env_files[@]}"; do
        if [ -f "$env_file" ]; then
            log_info "更新: $env_file"
            sed -i.bak "s|^DATA_ROOT=.*|DATA_ROOT=${new_data_root}|" "$env_file" 2>/dev/null || true
            rm -f "${env_file}.bak"
        fi
    done

    log_warning "⚠️  请手动更新以下配置文件:"
    log_info "  编辑文件: ${SCRIPT_DIR}/config/deploy.conf"
    log_info "  修改: DATA_ROOT=${new_data_root}"

    echo ""

    # 提示
    log_section "迁移完成"

    cat << EOF
┌─────────────────────────────────────────────────────────────┐
│  ✅ 数据卷迁移完成！                                      │
└─────────────────────────────────────────────────────────────┘

迁移信息:
  源目录: $old_data_root
  目标目录: $new_data_root
  数据大小: $total_size
  耗时: ${minutes} 分 ${seconds} 秒

后续步骤:
  1. 更新配置文件:
     ${SCRIPT_DIR}/config/deploy.conf
     修改: DATA_ROOT=${new_data_root}

  2. 重新加载配置:
     source ${SCRIPT_DIR}/config/deploy.conf

  3. 重启服务:
     docker compose start

  4. 验证数据:
     ${SCRIPT_DIR}/deploy.sh health
     ${SCRIPT_DIR}/deploy.sh data verify

重要提示:
  - 旧数据仍在原位置，可手动删除
  - 建议确认服务正常运行后再删除旧数据
  - 删除命令: rm -rf $old_data_root

EOF

    read -p "是否立即启动服务? (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        log_info "启动服务..."
        docker compose start
        log_warning "请先手动更新 deploy.conf 的 DATA_ROOT 配置后再启动服务！"
    fi
}

# 主函数
main() {
    case "$1" in
        usage|"")
            show_usage
            ;;
        clean-logs)
            clean_logs
            ;;
        verify)
            verify_integrity
            ;;
        migrate)
            if [ -z "$2" ]; then
                log_error "请指定目标目录"
                usage
                exit 1
            fi
            migrate_data "$2"
            ;;
        --help|-h)
            usage
            ;;
        *)
            log_error "未知命令: $1"
            usage
            exit 1
            ;;
    esac
}

# 执行
main "$@"
