#!/bin/bash

# ============================================================================
# 日志工具函数
# ============================================================================

# 日志级别
declare -A LOG_LEVELS=(
    ["DEBUG"]=0
    ["INFO"]=1
    ["SUCCESS"]=2
    ["WARNING"]=3
    ["ERROR"]=4
    ["CRITICAL"]=5
)

# 当前日志级别（从环境变量读取，默认 INFO）
CURRENT_LOG_LEVEL="${LOG_LEVEL:-INFO}"

# 颜色定义
declare -A COLORS=(
    ["DEBUG"]="\033[36m"      # 青色
    ["INFO"]="\033[0m"        # 默认
    ["SUCCESS"]="\033[32m"    # 绿色
    ["WARNING"]="\033[33m"    # 黄色
    ["ERROR"]="\033[31m"      # 红色
    ["CRITICAL"]="\033[35m"   # 紫色
    ["RESET"]="\033[0m"       # 重置
)

# 获取时间戳
get_timestamp() {
    date "+%Y-%m-%d %H:%M:%S"
}

# 检查是否应该输出日志
should_log() {
    local level="$1"
    local current_level="${LOG_LEVELS[$CURRENT_LOG_LEVEL]}"
    local target_level="${LOG_LEVELS[$level]}"

    [ "$target_level" -ge "$current_level" ]
}

# 通用日志函数
_log() {
    local level="$1"
    shift
    local message="$*"

    if should_log "$level"; then
        local color="${COLORS[$level]}"
        local timestamp=$(get_timestamp)
        echo -e "${color}[${timestamp}] [${level}] ${message}${COLORS[RESET]}"
    fi

    # 写入日志文件（如果配置了日志目录）
    if [ -n "$LOG_DIR" ] && [ -d "$LOG_DIR" ]; then
        local timestamp=$(get_timestamp)
        echo "[${timestamp}] [${level}] ${message}" >> "${LOG_DIR}/deploy.log" 2>/dev/null || true
    fi
}

# DEBUG 日志
log_debug() {
    _log "DEBUG" "$@"
}

# INFO 日志
log_info() {
    _log "INFO" "$@"
}

# SUCCESS 日志
log_success() {
    _log "SUCCESS" "$@"
}

# WARNING 日志
log_warning() {
    _log "WARNING" "$@" >&2
}

# ERROR 日志
log_error() {
    _log "ERROR" "$@" >&2
}

# CRITICAL 日志
log_critical() {
    _log "CRITICAL" "$@" >&2
}

# 简化的 OK/ERROR 标记
log_ok() {
    local message="$*"
    echo -e "\033[32m✅ ${message}\033[0m"
}

log_fail() {
    local message="$*"
    echo -e "\033[31m❌ ${message}\033[0m"
}

log_section() {
    local title="$*"
    local width=80
    local pad=$(( (width - ${#title}) / 2 - 2 ))

    echo ""
    printf "%.*s\n" "$width" | tr ' ' '='
    printf "%*s%s%*s\n" "$pad" '' "$title" "$pad" ''
    printf "%.*s\n" "$width" | tr ' ' '='
    echo ""
}

# 带进度的日志
log_progress() {
    local current=$1
    local total=$2
    local message="${3:-Processing}"
    local percent=$((current * 100 / total))

    printf "\r\033[36m${message}:\033[0m [%-50s] %d%%" \
        "$(printf '#%.0s' $(seq 1 $((percent / 2))))" "$percent"

    if [ "$current" -eq "$total" ]; then
        echo ""
    fi
}

# 记录命令执行
log_command() {
    local cmd="$*"
    log_debug "执行命令: $cmd"
}

# 清除进度条
clear_progress() {
    printf "\r\033[K"
}

# 创建日志目录
init_log_dir() {
    if [ -n "$LOG_DIR" ]; then
        mkdir -p "$LOG_DIR"
    fi
}

# 导出函数供其他脚本使用
export -f log_debug
export -f log_info
export -f log_success
export -f log_warning
export -f log_error
export -f log_critical
export -f log_ok
export -f log_fail
export -f log_section
export -f log_progress
export -f clear_progress
export -f log_command
export -f init_log_dir
