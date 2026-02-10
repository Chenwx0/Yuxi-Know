#!/bin/bash

# ============================================================================
# 更新部署脚本（支持零停机更新）
# ============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/utils/logger.sh"
source "${SCRIPT_DIR}/utils/validator.sh"
source "${SCRIPT_DIR}/config/deploy.conf"

# 解析参数
SKIP_BACKUP=false
FORCE=false
BACKUP_ONLY=false

# 允许通过命令行覆盖分支配置
# 优先级: 命令行 > 环境变量 > 配置文件
if [ -n "$DEPLOY_BRANCH" ]; then
    # 从环境变量获取（如 PowerShell 传递）
    GIT_BRANCH="$DEPLOY_BRANCH"
fi

while [[ $# -gt 0 ]]; do
    case $1 in
        --no-backup)
            SKIP_BACKUP=true
            shift
            ;;
        --force)
            FORCE=true
            shift
            ;;
        --backup-only)
            BACKUP_ONLY=true
            shift
            ;;
        --branch)
            GIT_BRANCH="$2"
            shift 2
            ;;
        *)
            log_error "未知参数: $1"
            log_info "支持的参数: --no-backup, --force, --backup-only, --branch <分支名>"
            exit 1
            ;;
    esac
done

# 检查服务健康状态
check_current_health() {
    log_info "检查当前服务状态..."

    cd "${PROJECT_DIR}"

    # 检查容器运行状态
    local running_count=$(docker compose ps --services --filter "status=running" | wc -l)
    local total_count=$(docker compose config --services | wc -l)

    if [ "$running_count" -eq 0 ]; then
        log_error "没有运行中的服务"
        return 1
    fi

    log_ok "✅ $running_count/$total_count 个服务在运行"

    # 检查 API 健康端点
    if ! curl -sf http://localhost:5050/api/system/health > /dev/null 2>&1; then
        log_warning "⚠️  API 健康检查失败，服务可能正在启动"
    fi

    return 0
}

# 执行备份
run_backup() {
    log_info "执行数据备份..."

    if bash "${SCRIPT_DIR}/backup.sh"; then
        log_ok "✅ 备份成功"
    else
        if [ "$FORCE" = true ]; then
            log_warning "⚠️  备份失败但继续更新（--force 模式）"
        else
            log_error "备份失败，更新中止（使用 --force 跳过）"
            exit 1
        fi
    fi
}

# 处理 Git 认证 URL
get_auth_url() {
    # 检查必需的环境变量
    if [ -z "${GIT_REPO:-}" ]; then
        log_error "未设置 GIT_REPO 环境变量！"
        log_info "请运行以下命令后再试："
        log_info "  export GIT_REPO=\"https://github.com/Chenwx0/Yuxi-Know.git\""
        exit 1
    fi

    if [ -z "${GIT_BRANCH:-}" ]; then
        log_error "未设置 GIT_BRANCH 环境变量！"
        log_info "请运行以下命令后再试："
        log_info "  export GIT_BRANCH=\"dev\""
        exit 1
    fi

    local auth_url="${GIT_REPO}"

    if [ -n "${GIT_AUTH_TOKEN:-}" ]; then
        # 使用 Personal Access Token
        if [[ "$GIT_REPO" =~ ^https://.* ]]; then
            auth_url=$(echo "$GIT_REPO" | sed "s|https://|https://${GIT_AUTH_TOKEN}@|")
        fi
    elif [ -n "${GIT_USERNAME:-}" ] && [ -n "${GIT_PASSWORD:-}" ]; then
        # 使用用户名密码
        if [[ "$GIT_REPO" =~ ^https://.* ]]; then
            auth_url=$(echo "$GIT_REPO" | sed "s|https://|https://${GIT_USERNAME}:${GIT_PASSWORD}@|")
        fi
    fi

    echo "$auth_url"
}

# 执行带认证的 Git 操作
git_with_auth() {
    local auth_url=$(get_auth_url)
    local original_remote=$(git remote get-url origin 2>/dev/null || echo "")

    # 临时设置认证 URL
    if [ "$auth_url" != "$GIT_REPO" ] && [ -n "$original_remote" ]; then
        git remote set-url origin "$auth_url"
    fi

    # 执行 Git 命令
    "$@"

    # 恢复原始 URL
    if [ "$auth_url" != "$GIT_REPO" ] && [ -n "$original_remote" ]; then
        git remote set-url origin "$original_remote"
    fi
}

# 检查代码更新
check_updates() {
    log_info "检查代码更新..."

    cd "${PROJECT_DIR}"

    # 记录当前提交
    CURRENT_COMMIT=$(git rev-parse HEAD)

    # 拉取最新代码（带认证）
    log_info "拉取最新代码..."
    git_with_auth git fetch origin "${GIT_BRANCH}"

    LATEST_COMMIT=$(git rev-parse "origin/${GIT_BRANCH}")

    if [ "$CURRENT_COMMIT" = "$LATEST_COMMIT" ]; then
        log_info "已是最新版本"
        log_info "当前版本: $(git log -1 --oneline)"
        exit 0
    fi

    # 显示变更摘要
    log_info "发现新版本:"
    echo ""
    git log --oneline "${CURRENT_COMMIT}...${LATEST_COMMIT}" | head -10 | sed 's/^/  /'
    echo ""

    # 检查变更文件
    local changed_files=$(git diff --name-only "$CURRENT_COMMIT" "$LATEST_COMMIT")
    local file_count=$(echo "$changed_files" | wc -l)

    log_info "变更文件数: $file_count"

    # 分类变更
    local has_dockerfile=false
    local has_migration=false
    local has_env_change=false
    local has_py_config=false

    while IFS= read -r file; do
        [[ "$file" == docker/*Dockerfile ]] && has_dockerfile=true
        [[ "$file" == migrations/* ]] && has_migration=true
        [[ "$file" == ".env.template" ]] && has_env_change=true
        [[ "$file" == pyproject.toml || "$file" == alembic.ini ]] && has_py_config=true
    done <<< "$changed_files"

    # 输出变更类型
    log_info "变更类型:"
    [ "$has_dockerfile" = true ] && echo "  🐳 Dockerfile 变更（需要重新构建）"
    [ "$has_migration" = true ] && echo "  🗄️  数据库迁移"
    [ "$has_env_change" = true ] && echo "  ⚙️  环境变量模板变更"
    [ "$has_py_config" = true ] && echo "  📦 Python 依赖变更"
}

# 确保配置文件优先级（CONFIG_DIR优先于项目目录）
ensure_config_priority() {
    cd "${PROJECT_DIR}"

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
                    log_ok "✅ 已同步配置文件: $config_env_file → $env_file"
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

# 应用代码更新
apply_updates() {
    log_section "应用代码更新"

    cd "${PROJECT_DIR}"

    # 确保配置文件优先级
    ensure_config_priority

    log_info "切换到最新版本..."
    git_with_auth git pull origin "${GIT_BRANCH}"

    # 检查配置文件变更
    if git diff --name-only "$CURRENT_COMMIT" "$LATEST_COMMIT" | grep -q "\.env\.template"; then
        log_warning "⚠️  检测到环境变量模板变更，请检查配置文件"
        log_info "推荐在配置目录编辑: ${CONFIG_DIR}/env/.env"
        log_info "或者在项目目录编辑: .env"
        log_info ""
        log_info "运行以下命令对比模板:"
        log_info "  diff .env .env.template"

        read -p "是否现在检查配置? (y/N): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            diff .env .env.template || true
            read -p "按回车继续..."
        fi
    fi
}

# 执行数据库迁移
run_migrations() {
    log_section "数据库迁移"

    cd "${PROJECT_DIR}"

    # 检查是否有迁移变更
    if ! has_migration "$CURRENT_COMMIT" "$LATEST_COMMIT"; then
        log_info "无数据库迁移，跳过"
        return 0
    fi

    log_warning "⚠️  检测到数据库迁移"
    log_info "迁移前已备份数据"

    # 检查 Alembic
    if docker compose exec -T api uv run python -c "import alembic" 2>/dev/null; then
        log_info "执行 Alembic 迁移..."

        # 显示迁移计划
        log_info "迁移计划:"
        docker compose exec -T api uv run alembic history | tail -10 | sed 's/^/  /'

        # 执行迁移
        if docker compose exec -T api uv run alembic upgrade head; then
            log_ok "✅ 数据库迁移成功"
        else
            log_error "❌ 数据库迁移失败"
            return 1
        fi
    else
        log_warning "⚠️  未找到 Alembic，跳过数据库迁移"
    fi
}

# 检查是否有迁移
has_migration() {
    local old_commit="$1"
    local new_commit="$2"
    git diff --name-only "$old_commit" "$new_commit" | grep -q "migrations/\|alembic/"
}

# 重新构建镜像
rebuild_images() {
    log_section "重建镜像"

    cd "${PROJECT_DIR}"

    # 检查是否有 Dockerfile 变更
    if has_dockerfile_changes "$CURRENT_COMMIT" "$LATEST_COMMIT"; then
        log_info "检测到 Dockerfile 变更，重新构建镜像..."

        log_info "构建 api 镜像..."
        if docker compose build api; then
            log_ok "✅ api 镜像构建成功"
        else
            log_error "❌ api 镜像构建失败"
            return 1
        fi

        log_info "构建 web 镜像..."
        if docker compose build web; then
            log_ok "✅ web 镜像构建成功"
        else
            log_error "❌ web 镜像构建失败"
            return 1
        fi
    else
        log_info "无 Dockerfile 变更，跳过镜像构建"
    fi
}

# 检查 Dockerfile 是否变更
has_dockerfile_changes() {
    local old_commit="$1"
    local new_commit="$2"
    git diff --name-only "$old_commit" "$new_commit" | grep -q "docker/.*Dockerfile"
}

# 重启服务
restart_services() {
    log_section "重启服务"

    cd "${PROJECT_DIR}"

    log_info "采用零停机重启策略..."

    # 1. 先重启 web（前端）
    log_info "重启 web 服务..."
    docker compose restart web

    log_info "等待 web 服务就绪..."
    sleep 5
    wait_for_service web 30 2

    # 2. 再重启 api（后端）
    log_info "重启 api 服务..."
    docker compose restart api

    log_info "等待 api 服务就绪..."
    sleep 10
    wait_for_service api 60 2

    log_ok "✅ 服务重启完成"
}

# 执行更新后脚本
run_post_update_scripts() {
    log_info "检查更新后脚本..."

    cd "${PROJECT_DIR}"

    # 检查是否有 Python 依赖变更
    if git diff --name-only "$CURRENT_COMMIT" "$LATEST_COMMIT" | grep -q "pyproject.toml"; then
        log_info "检测到 Python 依赖变更，更新依赖..."
        docker compose exec -T api uv sync 2>/dev/null || log_warning "依赖更新可能失败，请手动检查"
    fi

    # 检查自定义更新后脚本
    if [ -f "scripts/post_update.sh" ]; then
        log_info "执行自定义更新后脚本..."
        bash scripts/post_update.sh
    fi
}

# 更新后健康检查
post_update_health_check() {
    log_section "更新后健康检查"

    cd "${PROJECT_DIR}"

    log_info "等待服务稳定..."
    sleep 10

    log_info "执行健康检查..."

    local max_retries=${HEALTH_CHECK_RETRIES:-30}
    local interval=${HEALTH_CHECK_INTERVAL:-10}
    local retry_count=0
    local success=false

    while [ $retry_count -lt $max_retries ]; do
        log_info "健康检查 (${retry_count}/${max_retries})..."

        # 检查容器状态
        local all_running=true
        for service in "${SERVICE_NAMES[@]}"; do
            if ! docker compose ps -q "$service" | xargs -I {} docker inspect --format='{{.State.Status}}' {} 2>/dev/null | grep -q "running"; then
                all_running=false
                log_debug "$service: 未运行"
            fi
        done

        # 检查 API 健康端点
        if $all_running && curl -sf http://localhost:5050/api/system/health > /dev/null 2>&1; then
            success=true
            break
        fi

        ((retry_count++))
        sleep $interval
    done

    if [ "$success" = true ]; then
        log_success "✅ 更新后健康检查通过"
        return 0
    else
        log_error "❌ 更新后健康检查失败"
        log_info "请检查日志: docker compose logs"
        return 1
    fi
}

# 自动回滚
auto_rollback() {
    log_error "检测到严重错误，触发自动回滚..."
    log_info "回滚到版本: ${CURRENT_COMMIT:0:8}"

    local deploy_file="${PROJECT_DIR}/.deploy_history"

    # 记录回滚信息
    cat >> "$deploy_file" << EOF
$(date -Iseconds) | rollback | ${CURRENT_COMMIT} | 自动回滚（更新失败）
EOF

    # 执行回滚
    bash "${SCRIPT_DIR}/rollback.sh" "$CURRENT_COMMIT"

    # 收集错误日志
    collect_error_logs

    emergency_exit "已自动回滚到版本 ${CURRENT_COMMIT:0:8}"
}

# 收集错误日志
collect_error_logs() {
    log_info "收集错误日志..."

    local error_log_dir="${LOG_DIR}/rollback_$(date +%Y%m%d_%H%M%S)"
    mkdir -p "$error_log_dir"

    cd "${PROJECT_DIR}"

    docker compose logs --tail=100 > "${error_log_dir}/docker-compose.log"
    docker compose logs --tail=100 api > "${error_log_dir}/api.log"
    docker compose logs --tail=100 web > "${error_log_dir}/web.log"

    log_info "错误日志已保存到: ${error_log_dir}"
}

# 显示更新结果
show_update_result() {
    log_section "更新完成"

    cd "${PROJECT_DIR}"

    cat << EOF
┌─────────────────────────────────────────────────────────────┐
│  ✅ 部署更新成功！                                         │
└─────────────────────────────────────────────────────────────┘

📋 更新信息:
  更新前版本: $(git log -1 --format='%h %s' "$CURRENT_COMMIT")
  更新后版本: $(git log -1 --oneline)

🌐 服务地址:
  - 前端: http://localhost:5173
  - 后端 API: http://localhost:5050
  - API 文档: http://localhost:5050/docs

📝 建议:
  1. 检查前端页面是否正常
  2. 测试关键功能（如知识库查询、对话等）
  3. 查看服务日志确认无错误

🔧 如有问题:
  查看日志:  docker compose logs -f
  回滚版本:  ${SCRIPT_DIR}/deploy.sh rollback ${CURRENT_COMMIT:0:8}

EOF
}

# 主更新函数
update_deployment() {
    log_section "开始更新部署"

    # 如果只是备份
    if [ "$BACKUP_ONLY" = true ]; then
        run_backup
        log_success "✅ 备份完成（--backup-only 模式）"
        exit 0
    fi

    cd "${PROJECT_DIR}" 2>/dev/null || emergency_exit "项目目录不存在: ${PROJECT_DIR}"

    # 显示使用的分支信息
    log_info "更新分支: ${GIT_BRANCH}"
    log_info "  优先级来源: $([ -n "$DEPLOY_BRANCH" ] && echo "环境变量 (PowerShell 传递)" || [ "$GIT_BRANCH" != "$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo 'unknown')" ] && echo "配置文件" || echo "当前分支")"

    # 如果指定了分支且不是当前分支，先切换
    if [ -n "$GIT_BRANCH" ]; then
        local current_branch=$(git branch --show-current 2>/dev/null || echo "unknown")
        if [ "$current_branch" != "$GIT_BRANCH" ]; then
            log_info "切换到指定分支: ${GIT_BRANCH}"

            # 尝试获取远程分支信息（带认证）
            git_with_auth git fetch origin "$GIT_BRANCH" 2>/dev/null || true

            # 检查远程是否存在该分支
            if git rev-parse --verify "origin/${GIT_BRANCH}" >/dev/null 2>&1; then
                git checkout "$GIT_BRANCH" 2>/dev/null || git checkout -b "$GIT_BRANCH" "origin/${GIT_BRANCH}"
            else
                log_warning "远程分支不存在，使用本地分支: ${GIT_BRANCH}"
                git checkout "$GIT_BRANCH" 2>/dev/null || true
            fi

            if [ $? -eq 0 ]; then
                log_ok "✅ 已切换到分支: ${GIT_BRANCH}"
            else
                log_warning "⚠️  切换分支失败，继续使用当前分支"
            fi
        fi
    fi

    # 1. 预更新检查
    log_info "执行预更新检查..."
    check_current_health || {
        log_error "当前服务状态异常，无法更新"
        log_info "请先检查服务状态: docker compose ps"
        log_info "如需要，可使用 --force 强制更新"
        exit 1
    }

    # 2. 备份数据
    if [ "$SKIP_BACKUP" = false ]; then
        run_backup
    else
        log_warning "⚡ 跳过备份（--no-backup 模式）"
    fi

    # 3. 检查代码更新
    check_updates

    # 4. 应用代码更新
    apply_updates

    # 5. 执行数据库迁移
    if ! run_migrations; then
        if [ "$ROLLBACK_ENABLED" = true ]; then
            auto_rollback
        else
            emergency_exit "数据库迁移失败且回滚功能已禁用"
        fi
    fi

    # 6. 重新构建镜像（如需要）
    if ! rebuild_images; then
        if [ "$ROLLBACK_ENABLED" = true ]; then
            auto_rollback
        else
            emergency_exit "镜像构建失败且回滚功能已禁用"
        fi
    fi

    # 7. 重启服务
    restart_services

    # 8. 执行更新后脚本
    run_post_update_scripts

    # 9. 健康检查
    if ! post_update_health_check; then
        if [ "$ROLLBACK_ENABLED" = true ]; then
            auto_rollback
        else
            emergency_exit "更新后健康检查失败且回滚功能已禁用"
        fi
    fi

    # 10. 记录部署信息
    record_deployment "update" "更新到 ${LATEST_COMMIT:0:8}"

    # 11. 显示结果
    show_update_result
}

# 执行更新
update_deployment
