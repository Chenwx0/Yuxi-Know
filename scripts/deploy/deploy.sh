#!/bin/bash

# ============================================================================
# Yuxi-Know 自动化部署主脚本
# ============================================================================

set -e

# 脚本目录
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# 加载配置和工具函数
source "${SCRIPT_DIR}/utils/logger.sh"
export SCRIPT_DIR
source "${SCRIPT_DIR}/config/deploy.conf"

# 初始化日志目录
init_log_dir

# 显示版本信息
show_version() {
    cat << EOF
Yuxi-Know 自动化部署工具 v1.0.0
Copyright (c) 2026 Yuxi-Know Project
EOF
}

# 显示用法
usage() {
    show_version
    cat << EOF

用法: $0 [命令] [选项]

命令:
  init        首次初始化部署环境
  update      更新部署（拉取代码+重启服务）
  health      检查服务健康状态
  backup      备份数据
  rollback    回滚到指定版本
  status      查看部署状态
  data        数据卷管理工具

数据卷子命令:
  data usage      显示数据卷使用情况
  data clean-logs 清理数据卷日志
  data verify     验证数据卷完整性
  data migrate    迁移数据卷到新位置

全局选项:
  --force     强制执行（跳过确认）
  --quiet     静默模式（只输出错误和警告）
  --verbose   详细模式
  --version   显示版本信息

示例:
  # 首次部署
  $0 init

  # 日常更新
  $0 update

  # 强制更新（跳过备份）
  $0 update --force --no-backup

  # 健康检查
  $0 health

  # 手动备份
  $0 backup

  # 查看部署状态
  $0 status

  # 回滚到指定版本
  $0 rollback v1.2.3 或 commit-hash

  # 查看数据卷使用情况
  $0 data usage

  # 验证数据卷
  $0 data verify

更多文档请访问: https://github.com/xerrors/Yuxi-Know/blob/main/docs/deployment.md
EOF
}

# 显示部署状态
show_deploy_status() {
    log_section "部署状态"

    cd "${PROJECT_DIR}" 2>/dev/null || {
        log_error "项目目录不存在: ${PROJECT_DIR}"
        exit 1
    }

    # Git 信息
    log_info "Git 信息:"
    echo "  分支: $(git branch --show-current)"
    echo "  提交: $(git rev-parse HEAD)"
    echo "  作者: $(git log -1 --format='%an <%ae>')"
    echo "  时间: $(git log -1 --format='%ai')"
    echo ""

    # Docker 容器状态
    log_info "Docker 容器状态:"
    docker compose ps --format "  {{.Name}}: {{.Status}}" | grep -v "exited\|dead" || \
        echo "  无运行中的容器"
    echo ""

    # 数据卷信息
    log_info "数据卷信息:"
    echo "  根目录: ${DATA_ROOT}"
    if [ -d "${DATA_ROOT}" ]; then
        echo "  磁盘使用: $(du -sh "${DATA_ROOT}" 2>/dev/null | cut -f1)"
    else
        echo "  状态: 目录不存在"
    fi
    echo ""

    # 部署历史
    log_info "最近部署历史:"
    if [ -f ".deploy_history" ]; then
        tail -5 .deploy_history | sed 's/^/  /' || true
    else
        echo "  无部署记录"
    fi
}

# 确认操作
confirm_action() {
    local message="$1"
    local default="${2:-N}"

    if [ "$FORCE" = true ]; then
        return 0
    fi

    if [ "$default" = "Y" ]; then
        read -p "${message} [Y/n]: " -n 1 -r response
        echo
        [[ ! $response =~ ^[Nn]$ ]]
    else
        read -p "${message} [y/N]: " -n 1 -r response
        echo
        [[ $response =~ ^[Yy]$ ]]
    fi
}

# 记录部署信息
record_deployment() {
    local type="$1"
    local description="$2"
    local deploy_file="${PROJECT_DIR}/.deploy_history"

    mkdir -p "$(dirname "$deploy_file")"

    cat >> "$deploy_file" << EOF
$(date -Iseconds) | $type | $(cd "${PROJECT_DIR}" 2>/dev/null && git rev-parse HEAD) | $description
EOF
}

# 紧急退出
emergency_exit() {
    log_error "紧急退出: $*"
    exit 1
}

# 确保配置文件优先级（CONFIG_DIR优先于项目目录）
ensure_config_priority() {
    cd "${PROJECT_DIR}" 2>/dev/null || {
        log_error "项目目录不存在: ${PROJECT_DIR}"
        exit 1
    }

    # 处理 .env 和 .env.prod 两个配置文件
    local env_files=("env" "env.prod")

    for env_suffix in "${env_files[@]}"; do
        local env_file=".$env_suffix"
        local config_env_file="${CONFIG_DIR}/env/$env_file"

        # 如果配置目录有 .env 且项目目录也有 .env，比较修改时间
        if [ -f "$config_env_file" ] && [ -f "$env_file" ]; then
            local config_mtime=$(stat -c %Y "$config_env_file" 2>/dev/null || stat -f %m "$config_env_file" 2>/dev/null || echo "0")
            local project_mtime=$(stat -c %Y "$env_file" 2>/dev/null || stat -f %m "$env_file" 2>/dev/null || echo "0")

            if [ "$config_mtime" -gt "$project_mtime" ]; then
                log_info "配置目录的 $env_file 更新，同步到项目目录..."
                if cp "$config_env_file" "$env_file"; then
                    log_debug "✅ 已同步配置文件: $config_env_file → $env_file"
                else
                    log_warning "⚠️  同步 $env_file 失败"
                fi
            fi
        fi

        # 如果只有配置目录有 .env，复制到项目目录
        if [ -f "$config_env_file" ] && [ ! -f "$env_file" ]; then
            log_info "从配置目录复制 $env_file 到项目目录..."
            if cp "$config_env_file" "$env_file"; then
                log_ok "✅ 已复制配置文件: $config_env_file → $env_file"
            else
                log_warning "⚠️  复制 $env_file 失败"
            fi
        fi
    done

    return 0
}

# 主函数
main() {
    local command="$1"
    shift || true

    # 处理全局选项
    FORCE=false
    QUIET=false
    VERBOSE=false

    while [[ $# -gt 0 ]]; do
        case $1 in
            --force)
                FORCE=true
                shift
                ;;
            --quiet)
                QUIET=true
                LOG_LEVEL="WARNING"
                shift
                ;;
            --verbose)
                VERBOSE=true
                LOG_LEVEL="DEBUG"
                shift
                ;;
            --version)
                show_version
                exit 0
                ;;
            *)
                break
                ;;
        esac
    done

    # 执行命令
    case "$command" in
        init)
            log_info "开始首次初始化部署..."
            bash "${SCRIPT_DIR}/init.sh" "$@"
            ;;
        update)
            log_info "开始更新部署..."
            ensure_config_priority
            bash "${SCRIPT_DIR}/update.sh" "$@"
            ;;
        health)
            bash "${SCRIPT_DIR}/health.sh" "$@"
            ;;
        backup)
            bash "${SCRIPT_DIR}/backup.sh" "$@"
            ;;
        rollback)
            bash "${SCRIPT_DIR}/rollback.sh" "$@"
            ;;
        status)
            show_deploy_status
            ;;
        data)
            if [ -z "$1" ]; then
                bash "${SCRIPT_DIR}/manage_data_volumes.sh"
            else
                bash "${SCRIPT_DIR}/manage_data_volumes.sh" "$@"
            fi
            ;;
        ""|--help|-h)
            usage
            ;;
        *)
            log_error "未知命令: $command"
            usage
            exit 1
            ;;
    esac
}

# 捕获退出信号
trap 'log_error "脚本被中断"; exit 1' INT TERM

# 执行
main "$@"
