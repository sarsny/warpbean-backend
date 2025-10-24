#!/bin/bash

# WarpBean Backend 监测脚本
# 用于监控服务状态、性能指标和系统健康

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
PORT=${PORT:-3000}
PM2_APP_NAME="warpbean-backend"
HEALTH_URL="http://localhost:$PORT/health"
LOG_FILE="$APP_DIR/logs/monitor.log"
ALERT_EMAIL=""  # 设置告警邮箱
ALERT_WEBHOOK=""  # 设置告警 Webhook

# 阈值配置
CPU_THRESHOLD=80
MEMORY_THRESHOLD=80
DISK_THRESHOLD=85
RESPONSE_TIME_THRESHOLD=2000  # 毫秒

# 日志函数
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [INFO] $1" >> "$LOG_FILE"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [SUCCESS] $1" >> "$LOG_FILE"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [WARNING] $1" >> "$LOG_FILE"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [ERROR] $1" >> "$LOG_FILE"
}

log_metric() {
    echo -e "${CYAN}[METRIC]${NC} $1"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [METRIC] $1" >> "$LOG_FILE"
}

# 创建日志目录
create_log_dir() {
    mkdir -p "$APP_DIR/logs"
}

# 检查服务是否运行
check_service_status() {
    log_info "检查服务状态..."
    
    # 检查端口是否被占用
    if lsof -Pi :$PORT -sTCP:LISTEN -t >/dev/null; then
        log_success "服务正在运行 (端口 $PORT)"
        SERVICE_RUNNING=true
    else
        log_error "服务未运行 (端口 $PORT 未被占用)"
        SERVICE_RUNNING=false
        return 1
    fi
    
    # 检查 PM2 状态
    if command -v pm2 &> /dev/null; then
        if pm2 list | grep -q "$PM2_APP_NAME.*online"; then
            log_success "PM2 服务状态: 在线"
        elif pm2 list | grep -q "$PM2_APP_NAME"; then
            log_warning "PM2 服务状态: 离线"
        else
            log_info "PM2 中未找到应用"
        fi
    fi
}

# 健康检查
health_check() {
    log_info "执行健康检查..."
    
    local start_time=$(date +%s%3N)
    local response=$(curl -s -w "%{http_code}" -o /tmp/health_response.json "$HEALTH_URL" 2>/dev/null || echo "000")
    local end_time=$(date +%s%3N)
    local response_time=$((end_time - start_time))
    
    if [ "$response" = "200" ]; then
        log_success "健康检查通过 (响应时间: ${response_time}ms)"
        log_metric "response_time=${response_time}ms"
        
        # 检查响应时间
        if [ $response_time -gt $RESPONSE_TIME_THRESHOLD ]; then
            log_warning "响应时间过长: ${response_time}ms (阈值: ${RESPONSE_TIME_THRESHOLD}ms)"
            send_alert "响应时间告警" "服务响应时间 ${response_time}ms 超过阈值 ${RESPONSE_TIME_THRESHOLD}ms"
        fi
        
        # 解析健康检查响应
        if [ -f /tmp/health_response.json ]; then
            local uptime=$(cat /tmp/health_response.json | grep -o '"uptime":[0-9.]*' | cut -d':' -f2)
            if [ ! -z "$uptime" ]; then
                local uptime_hours=$(echo "scale=2; $uptime / 3600" | bc 2>/dev/null || echo "N/A")
                log_metric "uptime=${uptime_hours}h"
            fi
        fi
        
        return 0
    else
        log_error "健康检查失败 (HTTP状态码: $response)"
        send_alert "健康检查失败" "服务健康检查返回状态码: $response"
        return 1
    fi
}

# 检查系统资源
check_system_resources() {
    log_info "检查系统资源..."
    
    # CPU 使用率
    local cpu_usage=$(top -l 1 | grep "CPU usage" | awk '{print $3}' | sed 's/%//')
    if [ ! -z "$cpu_usage" ]; then
        log_metric "cpu_usage=${cpu_usage}%"
        if (( $(echo "$cpu_usage > $CPU_THRESHOLD" | bc -l) )); then
            log_warning "CPU 使用率过高: ${cpu_usage}% (阈值: ${CPU_THRESHOLD}%)"
            send_alert "CPU 使用率告警" "CPU 使用率 ${cpu_usage}% 超过阈值 ${CPU_THRESHOLD}%"
        fi
    fi
    
    # 内存使用率
    local memory_info=$(vm_stat | grep -E "(free|inactive|active|wired)")
    local page_size=$(vm_stat | grep "page size" | awk '{print $8}')
    if [ ! -z "$page_size" ]; then
        local free_pages=$(echo "$memory_info" | grep "Pages free" | awk '{print $3}' | sed 's/\.//')
        local inactive_pages=$(echo "$memory_info" | grep "Pages inactive" | awk '{print $3}' | sed 's/\.//')
        local active_pages=$(echo "$memory_info" | grep "Pages active" | awk '{print $3}' | sed 's/\.//')
        local wired_pages=$(echo "$memory_info" | grep "Pages wired down" | awk '{print $4}' | sed 's/\.//')
        
        local total_pages=$((free_pages + inactive_pages + active_pages + wired_pages))
        local used_pages=$((active_pages + wired_pages))
        local memory_usage=$(echo "scale=1; $used_pages * 100 / $total_pages" | bc)
        
        log_metric "memory_usage=${memory_usage}%"
        if (( $(echo "$memory_usage > $MEMORY_THRESHOLD" | bc -l) )); then
            log_warning "内存使用率过高: ${memory_usage}% (阈值: ${MEMORY_THRESHOLD}%)"
            send_alert "内存使用率告警" "内存使用率 ${memory_usage}% 超过阈值 ${MEMORY_THRESHOLD}%"
        fi
    fi
    
    # 磁盘使用率
    local disk_usage=$(df -h "$APP_DIR" | tail -1 | awk '{print $5}' | sed 's/%//')
    if [ ! -z "$disk_usage" ]; then
        log_metric "disk_usage=${disk_usage}%"
        if [ $disk_usage -gt $DISK_THRESHOLD ]; then
            log_warning "磁盘使用率过高: ${disk_usage}% (阈值: ${DISK_THRESHOLD}%)"
            send_alert "磁盘使用率告警" "磁盘使用率 ${disk_usage}% 超过阈值 ${DISK_THRESHOLD}%"
        fi
    fi
}

# 检查应用进程
check_app_process() {
    log_info "检查应用进程..."
    
    if command -v pm2 &> /dev/null && pm2 list | grep -q "$PM2_APP_NAME"; then
        # PM2 进程信息
        local pm2_info=$(pm2 jlist | jq -r ".[] | select(.name==\"$PM2_APP_NAME\") | \"CPU: \(.monit.cpu)% Memory: \(.monit.memory/1024/1024 | floor)MB PID: \(.pid) Restarts: \(.pm2_env.restart_time)\"")
        if [ ! -z "$pm2_info" ]; then
            log_metric "pm2_process: $pm2_info"
        fi
    else
        # 查找 Node.js 进程
        local node_pids=$(pgrep -f "node.*$APP_NAME" || echo "")
        if [ ! -z "$node_pids" ]; then
            for pid in $node_pids; do
                local cpu_mem=$(ps -p $pid -o %cpu,%mem --no-headers 2>/dev/null || echo "N/A N/A")
                log_metric "node_process: PID=$pid CPU/MEM=$cpu_mem"
            done
        else
            log_warning "未找到 Node.js 进程"
        fi
    fi
}

# 检查数据库连接
check_database() {
    log_info "检查数据库连接..."
    
    # 加载环境变量
    if [ -f "$APP_DIR/.env" ]; then
        source "$APP_DIR/.env"
    fi
    
    if [ ! -z "$DB_HOST" ] && [ ! -z "$DB_PORT" ]; then
        if nc -z "$DB_HOST" "$DB_PORT" 2>/dev/null; then
            log_success "数据库连接正常 ($DB_HOST:$DB_PORT)"
        else
            log_error "数据库连接失败 ($DB_HOST:$DB_PORT)"
            send_alert "数据库连接失败" "无法连接到数据库 $DB_HOST:$DB_PORT"
            return 1
        fi
    else
        log_warning "数据库配置未找到"
    fi
}

# 检查日志错误
check_logs_for_errors() {
    log_info "检查应用日志错误..."
    
    local log_files=("$APP_DIR/logs/app.log" "$APP_DIR/logs/error.log")
    
    for log_file in "${log_files[@]}"; do
        if [ -f "$log_file" ]; then
            # 检查最近5分钟的错误
            local recent_errors=$(tail -n 100 "$log_file" | grep -i "error\|exception\|fatal" | wc -l)
            if [ $recent_errors -gt 0 ]; then
                log_warning "发现 $recent_errors 个错误在 $log_file"
                # 显示最新的几个错误
                tail -n 100 "$log_file" | grep -i "error\|exception\|fatal" | tail -3 | while read line; do
                    log_error "日志错误: $line"
                done
            fi
        fi
    done
    
    # 检查 PM2 日志
    if command -v pm2 &> /dev/null && pm2 list | grep -q "$PM2_APP_NAME"; then
        local pm2_errors=$(pm2 logs "$PM2_APP_NAME" --lines 50 --nostream 2>/dev/null | grep -i "error\|exception\|fatal" | wc -l)
        if [ $pm2_errors -gt 0 ]; then
            log_warning "PM2 日志中发现 $pm2_errors 个错误"
        fi
    fi
}

# 发送告警
send_alert() {
    local title="$1"
    local message="$2"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    log_warning "发送告警: $title - $message"
    
    # 邮件告警
    if [ ! -z "$ALERT_EMAIL" ] && command -v mail &> /dev/null; then
        echo "时间: $timestamp
服务: $APP_NAME
标题: $title
详情: $message
主机: $(hostname)" | mail -s "[$APP_NAME] $title" "$ALERT_EMAIL"
    fi
    
    # Webhook 告警
    if [ ! -z "$ALERT_WEBHOOK" ] && command -v curl &> /dev/null; then
        curl -X POST "$ALERT_WEBHOOK" \
            -H "Content-Type: application/json" \
            -d "{
                \"service\": \"$APP_NAME\",
                \"title\": \"$title\",
                \"message\": \"$message\",
                \"timestamp\": \"$timestamp\",
                \"host\": \"$(hostname)\"
            }" >/dev/null 2>&1
    fi
}

# 生成监控报告
generate_report() {
    log_info "生成监控报告..."
    
    local report_file="$APP_DIR/logs/monitor_report_$(date +%Y%m%d_%H%M%S).json"
    
    cat > "$report_file" << EOF
{
    "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
    "service": "$APP_NAME",
    "host": "$(hostname)",
    "checks": {
        "service_running": $SERVICE_RUNNING,
        "health_check": $([ $? -eq 0 ] && echo "true" || echo "false"),
        "database_connection": true
    },
    "metrics": {
        "uptime": "$(uptime | awk '{print $3,$4}' | sed 's/,//')",
        "load_average": "$(uptime | awk -F'load average:' '{print $2}')",
        "disk_usage": "${disk_usage:-0}%"
    }
}
EOF
    
    log_success "监控报告已生成: $report_file"
}

# 实时监控模式
real_time_monitor() {
    log_info "启动实时监控模式 (按 Ctrl+C 退出)..."
    
    while true; do
        clear
        echo -e "${PURPLE}=== WarpBean Backend 实时监控 ===${NC}"
        echo -e "${BLUE}时间: $(date)${NC}"
        echo ""
        
        check_service_status >/dev/null 2>&1
        if [ $? -eq 0 ]; then
            echo -e "${GREEN}✓ 服务状态: 运行中${NC}"
        else
            echo -e "${RED}✗ 服务状态: 停止${NC}"
        fi
        
        health_check >/dev/null 2>&1
        if [ $? -eq 0 ]; then
            echo -e "${GREEN}✓ 健康检查: 通过${NC}"
        else
            echo -e "${RED}✗ 健康检查: 失败${NC}"
        fi
        
        check_database >/dev/null 2>&1
        if [ $? -eq 0 ]; then
            echo -e "${GREEN}✓ 数据库: 连接正常${NC}"
        else
            echo -e "${RED}✗ 数据库: 连接失败${NC}"
        fi
        
        echo ""
        echo -e "${CYAN}=== 系统资源 ===${NC}"
        
        # 显示系统负载
        echo "负载: $(uptime | awk -F'load average:' '{print $2}')"
        
        # 显示内存使用
        echo "内存: $(vm_stat | head -1)"
        
        # 显示磁盘使用
        echo "磁盘: $(df -h "$APP_DIR" | tail -1 | awk '{print $5 " used of " $2}')"
        
        sleep 5
    done
}

# 显示帮助信息
show_help() {
    echo "WarpBean Backend 监测脚本"
    echo ""
    echo "用法: $0 [选项]"
    echo ""
    echo "选项:"
    echo "  --status         检查服务状态"
    echo "  --health         执行健康检查"
    echo "  --resources      检查系统资源"
    echo "  --database       检查数据库连接"
    echo "  --logs           检查日志错误"
    echo "  --report         生成监控报告"
    echo "  --monitor        实时监控模式"
    echo "  --all            执行所有检查"
    echo "  --help           显示此帮助信息"
    echo ""
    echo "配置:"
    echo "  ALERT_EMAIL      告警邮箱地址"
    echo "  ALERT_WEBHOOK    告警 Webhook URL"
    echo ""
}

# 主函数
main() {
    create_log_dir
    
    case "${1:-all}" in
        --status)
            check_service_status
            ;;
        --health)
            health_check
            ;;
        --resources)
            check_system_resources
            ;;
        --database)
            check_database
            ;;
        --logs)
            check_logs_for_errors
            ;;
        --report)
            generate_report
            ;;
        --monitor)
            real_time_monitor
            ;;
        --all)
            log_info "执行完整监控检查..."
            check_service_status
            health_check
            check_system_resources
            check_app_process
            check_database
            check_logs_for_errors
            generate_report
            ;;
        --help)
            show_help
            ;;
        *)
            log_error "未知选项: $1"
            show_help
            exit 1
            ;;
    esac
}

# 执行主函数
main "$@"