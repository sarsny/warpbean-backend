#!/bin/bash

# WarpBean Backend 健康检查脚本
# 用于检查应用、数据库、系统资源等健康状态

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# 配置变量
APP_NAME="warpbean-backend"
APP_DIR="/Users/sarsny/AIworkspace/cursor/cobean-ios-2/iosapp/warpbean-backend"
LOG_DIR="$APP_DIR/logs"
HEALTH_LOG="$LOG_DIR/health-check.log"

# 从环境变量读取配置
if [ -f "$APP_DIR/.env" ]; then
    source "$APP_DIR/.env"
fi

# 应用配置
APP_PORT="${PORT:-3000}"
APP_HOST="${HOST:-localhost}"
APP_URL="http://$APP_HOST:$APP_PORT"

# 数据库配置
DB_HOST="${DB_HOST:-localhost}"
DB_PORT="${DB_PORT:-5432}"
DB_NAME="${DB_NAME:-warpbean}"
DB_USER="${DB_USER:-postgres}"
DB_PASSWORD="${DB_PASSWORD:-password}"

# PM2配置
PM2_APP_NAME="warpbean-backend"

# 健康检查阈值
CPU_THRESHOLD=80          # CPU使用率阈值 (%)
MEMORY_THRESHOLD=80       # 内存使用率阈值 (%)
DISK_THRESHOLD=85         # 磁盘使用率阈值 (%)
RESPONSE_TIME_THRESHOLD=5000  # 响应时间阈值 (ms)

# 检查结果
HEALTH_STATUS="HEALTHY"
ISSUES=()

# 日志函数
log_info() {
    local message="$1"
    echo -e "${BLUE}[INFO]${NC} $message"
    echo "$(date '+%Y-%m-%d %H:%M:%S') [INFO] $message" >> "$HEALTH_LOG"
}

log_success() {
    local message="$1"
    echo -e "${GREEN}[SUCCESS]${NC} $message"
    echo "$(date '+%Y-%m-%d %H:%M:%S') [SUCCESS] $message" >> "$HEALTH_LOG"
}

log_warning() {
    local message="$1"
    echo -e "${YELLOW}[WARNING]${NC} $message"
    echo "$(date '+%Y-%m-%d %H:%M:%S') [WARNING] $message" >> "$HEALTH_LOG"
    ISSUES+=("WARNING: $message")
    if [ "$HEALTH_STATUS" = "HEALTHY" ]; then
        HEALTH_STATUS="WARNING"
    fi
}

log_error() {
    local message="$1"
    echo -e "${RED}[ERROR]${NC} $message"
    echo "$(date '+%Y-%m-%d %H:%M:%S') [ERROR] $message" >> "$HEALTH_LOG"
    ISSUES+=("ERROR: $message")
    HEALTH_STATUS="CRITICAL"
}

# 创建日志目录
create_log_dir() {
    mkdir -p "$LOG_DIR"
}

# 检查应用进程
check_app_process() {
    log_info "检查应用进程..."
    
    # 检查PM2进程
    if command -v pm2 &> /dev/null; then
        if pm2 list | grep -q "$PM2_APP_NAME.*online"; then
            log_success "PM2应用进程运行正常"
            
            # 获取PM2进程详细信息
            local pm2_info=$(pm2 show "$PM2_APP_NAME" 2>/dev/null)
            if echo "$pm2_info" | grep -q "status.*online"; then
                local cpu_usage=$(echo "$pm2_info" | grep "cpu" | awk '{print $3}' | sed 's/%//')
                local memory_usage=$(echo "$pm2_info" | grep "memory" | awk '{print $3}')
                log_info "PM2进程 - CPU: ${cpu_usage}%, 内存: ${memory_usage}"
            fi
        else
            log_error "PM2应用进程未运行"
        fi
    else
        # 检查Node.js进程
        if pgrep -f "node.*app.js\|node.*src/app.js" > /dev/null; then
            log_success "Node.js应用进程运行正常"
        else
            log_error "应用进程未运行"
        fi
    fi
}

# 检查应用端口
check_app_port() {
    log_info "检查应用端口 $APP_PORT..."
    
    if lsof -i :$APP_PORT > /dev/null 2>&1; then
        log_success "端口 $APP_PORT 正在监听"
    else
        log_error "端口 $APP_PORT 未被监听"
    fi
}

# 检查应用HTTP响应
check_app_http() {
    log_info "检查应用HTTP响应..."
    
    # 检查健康检查端点
    local health_url="$APP_URL/health"
    local start_time=$(date +%s%3N)
    
    if curl -s -f --max-time 10 "$health_url" > /dev/null 2>&1; then
        local end_time=$(date +%s%3N)
        local response_time=$((end_time - start_time))
        
        log_success "健康检查端点响应正常 (${response_time}ms)"
        
        if [ $response_time -gt $RESPONSE_TIME_THRESHOLD ]; then
            log_warning "响应时间过长: ${response_time}ms (阈值: ${RESPONSE_TIME_THRESHOLD}ms)"
        fi
    else
        log_error "健康检查端点无响应: $health_url"
    fi
    
    # 检查API端点
    local api_url="$APP_URL/api/auth/health"
    if curl -s -f --max-time 10 "$api_url" > /dev/null 2>&1; then
        log_success "API端点响应正常"
    else
        log_warning "API端点无响应: $api_url"
    fi
}

# 检查数据库连接
check_database() {
    # 如禁用数据库，则直接跳过检查并返回成功
    if [ "$DB_DISABLED" = "true" ] || [ "$DB_DISABLED" = "1" ]; then
        log_info "数据库已禁用，跳过数据库检查"
        return 0
    fi

    log_info "检查数据库连接..."
    
    export PGPASSWORD="$DB_PASSWORD"
    
    if pg_isready -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" >/dev/null 2>&1; then
        log_success "数据库连接正常"
        
        # 检查数据库性能
        local db_size=$(psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" \
            -t -c "SELECT pg_size_pretty(pg_database_size('$DB_NAME'));" 2>/dev/null | xargs)
        log_info "数据库大小: ${db_size:-未知}"
        
        # 检查活跃连接数
        local active_connections=$(psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" \
            -t -c "SELECT count(*) FROM pg_stat_activity WHERE state = 'active';" 2>/dev/null | xargs)
        log_info "活跃连接数: ${active_connections:-未知}"
        
        # 检查长时间运行的查询
        local long_queries=$(psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" \
            -t -c "SELECT count(*) FROM pg_stat_activity WHERE state = 'active' AND now() - query_start > interval '5 minutes';" 2>/dev/null | xargs)
        if [ "${long_queries:-0}" -gt 0 ]; then
            log_warning "发现 $long_queries 个长时间运行的查询"
        fi
        
    else
        log_error "数据库连接失败: $DB_HOST:$DB_PORT/$DB_NAME"
    fi
}

# 检查系统资源
check_system_resources() {
    log_info "检查系统资源..."
    
    # 检查CPU使用率
    local cpu_usage=$(top -l 1 -n 0 | grep "CPU usage" | awk '{print $3}' | sed 's/%//')
    if [ -n "$cpu_usage" ]; then
        log_info "CPU使用率: ${cpu_usage}%"
        if (( $(echo "$cpu_usage > $CPU_THRESHOLD" | bc -l) )); then
            log_warning "CPU使用率过高: ${cpu_usage}% (阈值: ${CPU_THRESHOLD}%)"
        fi
    fi
    
    # 检查内存使用率
    local memory_info=$(vm_stat | grep -E "Pages (free|active|inactive|speculative|wired down)")
    if [ -n "$memory_info" ]; then
        local page_size=4096
        local free_pages=$(echo "$memory_info" | grep "Pages free" | awk '{print $3}' | sed 's/\.//')
        local active_pages=$(echo "$memory_info" | grep "Pages active" | awk '{print $3}' | sed 's/\.//')
        local inactive_pages=$(echo "$memory_info" | grep "Pages inactive" | awk '{print $3}' | sed 's/\.//')
        local wired_pages=$(echo "$memory_info" | grep "Pages wired down" | awk '{print $4}' | sed 's/\.//')
        
        local total_pages=$((free_pages + active_pages + inactive_pages + wired_pages))
        local used_pages=$((active_pages + inactive_pages + wired_pages))
        local memory_usage=$((used_pages * 100 / total_pages))
        
        log_info "内存使用率: ${memory_usage}%"
        if [ $memory_usage -gt $MEMORY_THRESHOLD ]; then
            log_warning "内存使用率过高: ${memory_usage}% (阈值: ${MEMORY_THRESHOLD}%)"
        fi
    fi
    
    # 检查磁盘使用率
    local disk_usage=$(df -h "$APP_DIR" | tail -1 | awk '{print $5}' | sed 's/%//')
    if [ -n "$disk_usage" ]; then
        log_info "磁盘使用率: ${disk_usage}%"
        if [ $disk_usage -gt $DISK_THRESHOLD ]; then
            log_warning "磁盘使用率过高: ${disk_usage}% (阈值: ${DISK_THRESHOLD}%)"
        fi
    fi
    
    # 检查负载平均值
    local load_avg=$(uptime | awk -F'load averages:' '{print $2}' | xargs)
    log_info "系统负载: $load_avg"
}

# 检查日志文件
check_log_files() {
    log_info "检查日志文件..."
    
    local log_files=("$LOG_DIR/app.log" "$LOG_DIR/error.log" "$LOG_DIR/access.log")
    
    for log_file in "${log_files[@]}"; do
        if [ -f "$log_file" ]; then
            local file_size=$(ls -lh "$log_file" | awk '{print $5}')
            log_info "日志文件 $(basename "$log_file"): $file_size"
            
            # 检查最近的错误
            local recent_errors=$(tail -100 "$log_file" | grep -i "error\|exception\|fatal" | wc -l | xargs)
            if [ $recent_errors -gt 0 ]; then
                log_warning "日志文件 $(basename "$log_file") 中发现 $recent_errors 个最近错误"
            fi
        else
            log_warning "日志文件不存在: $log_file"
        fi
    done
}

# 检查依赖服务
check_dependencies() {
    log_info "检查依赖服务..."
    
    # 检查Redis (如果使用)
    if [ -n "$REDIS_URL" ] || [ -n "$REDIS_HOST" ]; then
        local redis_host="${REDIS_HOST:-localhost}"
        local redis_port="${REDIS_PORT:-6379}"
        
        if command -v redis-cli &> /dev/null; then
            if redis-cli -h "$redis_host" -p "$redis_port" ping > /dev/null 2>&1; then
                log_success "Redis连接正常"
            else
                log_error "Redis连接失败: $redis_host:$redis_port"
            fi
        else
            log_warning "Redis客户端未安装，无法检查Redis连接"
        fi
    fi
    
    # 检查外部API (DeepSeek)
    if [ -n "$DEEPSEEK_API_KEY" ]; then
        local deepseek_url="https://api.deepseek.com/v1/models"
        if curl -s -f --max-time 10 -H "Authorization: Bearer $DEEPSEEK_API_KEY" "$deepseek_url" > /dev/null 2>&1; then
            log_success "DeepSeek API连接正常"
        else
            log_warning "DeepSeek API连接异常"
        fi
    fi
}

# 检查安全性
check_security() {
    log_info "检查安全配置..."
    
    # 检查环境变量文件权限
    if [ -f "$APP_DIR/.env" ]; then
        local env_perms=$(ls -l "$APP_DIR/.env" | awk '{print $1}')
        if [[ "$env_perms" == *"r--"* ]] && [[ "$env_perms" != *"rw-rw-"* ]]; then
            log_success ".env文件权限安全"
        else
            log_warning ".env文件权限过于宽松: $env_perms"
        fi
    fi
    
    # 检查JWT密钥
    if [ -z "$JWT_SECRET" ] || [ ${#JWT_SECRET} -lt 32 ]; then
        log_warning "JWT密钥过短或未设置"
    else
        log_success "JWT密钥配置正常"
    fi
    
    # 检查CORS配置
    if [ -n "$CORS_ORIGIN" ] && [ "$CORS_ORIGIN" != "*" ]; then
        log_success "CORS配置安全"
    else
        log_warning "CORS配置可能不安全"
    fi
}

# 性能测试
performance_test() {
    log_info "执行性能测试..."
    
    local test_url="$APP_URL/health"
    local total_requests=10
    local concurrent_requests=3
    
    if command -v ab &> /dev/null; then
        log_info "使用Apache Bench进行性能测试..."
        local ab_result=$(ab -n $total_requests -c $concurrent_requests "$test_url" 2>/dev/null)
        
        if [ $? -eq 0 ]; then
            local avg_time=$(echo "$ab_result" | grep "Time per request" | head -1 | awk '{print $4}')
            local requests_per_sec=$(echo "$ab_result" | grep "Requests per second" | awk '{print $4}')
            
            log_info "平均响应时间: ${avg_time}ms"
            log_info "每秒请求数: $requests_per_sec"
            
            if (( $(echo "$avg_time > 1000" | bc -l) )); then
                log_warning "平均响应时间过长: ${avg_time}ms"
            fi
        else
            log_warning "性能测试失败"
        fi
    else
        log_warning "Apache Bench未安装，跳过性能测试"
    fi
}

# 生成健康报告
generate_report() {
    local output_file="${1:-$LOG_DIR/health-report-$(date +%Y%m%d_%H%M%S).json}"
    
    log_info "生成健康报告..."
    
    local timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    local hostname=$(hostname)
    
    cat > "$output_file" << EOF
{
  "timestamp": "$timestamp",
  "hostname": "$hostname",
  "application": "$APP_NAME",
  "status": "$HEALTH_STATUS",
  "checks": {
    "process": "$(check_app_process >/dev/null 2>&1 && echo "PASS" || echo "FAIL")",
    "port": "$(check_app_port >/dev/null 2>&1 && echo "PASS" || echo "FAIL")",
    "http": "$(check_app_http >/dev/null 2>&1 && echo "PASS" || echo "FAIL")",
    "database": "$(check_database >/dev/null 2>&1 && echo "PASS" || echo "FAIL")",
    "resources": "$(check_system_resources >/dev/null 2>&1 && echo "PASS" || echo "FAIL")"
  },
  "issues": [
EOF
    
    # 添加问题列表
    local first=true
    for issue in "${ISSUES[@]}"; do
        if [ "$first" = true ]; then
            first=false
        else
            echo "," >> "$output_file"
        fi
        echo "    \"$issue\"" >> "$output_file"
    done
    
    cat >> "$output_file" << EOF
  ],
  "metrics": {
    "response_time_threshold": $RESPONSE_TIME_THRESHOLD,
    "cpu_threshold": $CPU_THRESHOLD,
    "memory_threshold": $MEMORY_THRESHOLD,
    "disk_threshold": $DISK_THRESHOLD
  }
}
EOF
    
    log_success "健康报告已生成: $output_file"
}

# 快速检查
quick_check() {
    log_info "执行快速健康检查..."
    
    check_app_process
    check_app_port
    check_database
    
    echo -e "\n${CYAN}=== 快速检查结果 ===${NC}"
    echo "状态: $HEALTH_STATUS"
    if [ ${#ISSUES[@]} -gt 0 ]; then
        echo "发现问题:"
        for issue in "${ISSUES[@]}"; do
            echo "  - $issue"
        done
    else
        echo "未发现问题"
    fi
}

# 完整检查
full_check() {
    log_info "执行完整健康检查..."
    
    check_app_process
    check_app_port
    check_app_http
    check_database
    check_system_resources
    check_log_files
    check_dependencies
    check_security
    
    echo -e "\n${CYAN}=== 完整检查结果 ===${NC}"
    echo "状态: $HEALTH_STATUS"
    echo "检查时间: $(date)"
    
    if [ ${#ISSUES[@]} -gt 0 ]; then
        echo -e "\n发现的问题:"
        for issue in "${ISSUES[@]}"; do
            echo "  - $issue"
        done
    else
        echo -e "\n${GREEN}所有检查项目正常${NC}"
    fi
}

# 监控模式
monitor_mode() {
    local interval="${1:-60}"
    
    log_info "启动监控模式 (间隔: ${interval}秒, 按Ctrl+C退出)..."
    
    while true; do
        echo -e "\n${CYAN}=== $(date) ===${NC}"
        
        # 重置状态
        HEALTH_STATUS="HEALTHY"
        ISSUES=()
        
        # 执行快速检查
        quick_check
        
        # 等待下一次检查
        sleep "$interval"
    done
}

# 显示帮助信息
show_help() {
    echo "WarpBean Backend 健康检查脚本"
    echo ""
    echo "用法: $0 [命令] [选项]"
    echo ""
    echo "命令:"
    echo "  quick                   执行快速健康检查"
    echo "  full                    执行完整健康检查"
    echo "  monitor [interval]      监控模式 (默认间隔: 60秒)"
    echo "  performance             执行性能测试"
    echo "  report [file]           生成健康报告"
    echo "  help                    显示此帮助信息"
    echo ""
    echo "检查项目:"
    echo "  - 应用进程状态"
    echo "  - 端口监听状态"
    echo "  - HTTP响应检查"
    echo "  - 数据库连接"
    echo "  - 系统资源使用"
    echo "  - 日志文件状态"
    echo "  - 依赖服务连接"
    echo "  - 安全配置检查"
    echo ""
    echo "示例:"
    echo "  $0 quick                快速检查"
    echo "  $0 full                 完整检查"
    echo "  $0 monitor 30           每30秒监控一次"
    echo "  $0 report health.json   生成JSON格式报告"
    echo ""
}

# 主函数
main() {
    create_log_dir
    
    case "${1:-quick}" in
        quick)
            quick_check
            ;;
        full)
            full_check
            ;;
        monitor)
            monitor_mode "$2"
            ;;
        performance)
            performance_test
            ;;
        report)
            generate_report "$2"
            ;;
        help|*)
            show_help
            ;;
    esac
    
    # 返回适当的退出码
    case "$HEALTH_STATUS" in
        HEALTHY)
            exit 0
            ;;
        WARNING)
            exit 1
            ;;
        CRITICAL)
            exit 2
            ;;
    esac
}

# 执行主函数
main "$@"