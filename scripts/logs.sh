#!/bin/bash

# WarpBean Backend 日志管理脚本
# 用于日志查看、分析、清理和轮转

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
PM2_APP_NAME="warpbean-backend"

# 日志文件路径
APP_LOG="$LOG_DIR/app.log"
ERROR_LOG="$LOG_DIR/error.log"
ACCESS_LOG="$LOG_DIR/access.log"
MONITOR_LOG="$LOG_DIR/monitor.log"

# 配置参数
MAX_LOG_SIZE="100M"  # 单个日志文件最大大小
KEEP_DAYS=30         # 保留日志天数
ARCHIVE_DIR="$LOG_DIR/archive"

# 日志函数
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# 创建日志目录
create_log_dirs() {
    mkdir -p "$LOG_DIR"
    mkdir -p "$ARCHIVE_DIR"
    log_info "日志目录已创建: $LOG_DIR"
}

# 查看实时日志
tail_logs() {
    local log_type="${1:-all}"
    local lines="${2:-50}"
    
    case $log_type in
        app)
            if [ -f "$APP_LOG" ]; then
                log_info "查看应用日志 (最新 $lines 行)..."
                tail -n "$lines" -f "$APP_LOG"
            else
                log_warning "应用日志文件不存在: $APP_LOG"
            fi
            ;;
        error)
            if [ -f "$ERROR_LOG" ]; then
                log_info "查看错误日志 (最新 $lines 行)..."
                tail -n "$lines" -f "$ERROR_LOG"
            else
                log_warning "错误日志文件不存在: $ERROR_LOG"
            fi
            ;;
        access)
            if [ -f "$ACCESS_LOG" ]; then
                log_info "查看访问日志 (最新 $lines 行)..."
                tail -n "$lines" -f "$ACCESS_LOG"
            else
                log_warning "访问日志文件不存在: $ACCESS_LOG"
            fi
            ;;
        pm2)
            if command -v pm2 &> /dev/null; then
                log_info "查看 PM2 日志..."
                pm2 logs "$PM2_APP_NAME" --lines "$lines"
            else
                log_warning "PM2 未安装"
            fi
            ;;
        all|*)
            log_info "查看所有日志 (最新 $lines 行)..."
            echo -e "${CYAN}=== 应用日志 ===${NC}"
            [ -f "$APP_LOG" ] && tail -n "$lines" "$APP_LOG" || echo "文件不存在"
            echo -e "\n${CYAN}=== 错误日志 ===${NC}"
            [ -f "$ERROR_LOG" ] && tail -n "$lines" "$ERROR_LOG" || echo "文件不存在"
            echo -e "\n${CYAN}=== 访问日志 ===${NC}"
            [ -f "$ACCESS_LOG" ] && tail -n "$lines" "$ACCESS_LOG" || echo "文件不存在"
            ;;
    esac
}

# 搜索日志
search_logs() {
    local pattern="$1"
    local log_type="${2:-all}"
    local time_range="${3:-1d}"
    
    if [ -z "$pattern" ]; then
        log_error "请提供搜索模式"
        return 1
    fi
    
    log_info "搜索日志: '$pattern' (时间范围: $time_range)"
    
    local find_args=""
    case $time_range in
        1h) find_args="-mmin -60" ;;
        6h) find_args="-mmin -360" ;;
        1d) find_args="-mtime -1" ;;
        7d) find_args="-mtime -7" ;;
        30d) find_args="-mtime -30" ;;
    esac
    
    case $log_type in
        app)
            [ -f "$APP_LOG" ] && grep -n "$pattern" "$APP_LOG" | head -100
            ;;
        error)
            [ -f "$ERROR_LOG" ] && grep -n "$pattern" "$ERROR_LOG" | head -100
            ;;
        access)
            [ -f "$ACCESS_LOG" ] && grep -n "$pattern" "$ACCESS_LOG" | head -100
            ;;
        all|*)
            echo -e "${CYAN}=== 应用日志搜索结果 ===${NC}"
            [ -f "$APP_LOG" ] && grep -n "$pattern" "$APP_LOG" | head -50
            echo -e "\n${CYAN}=== 错误日志搜索结果 ===${NC}"
            [ -f "$ERROR_LOG" ] && grep -n "$pattern" "$ERROR_LOG" | head -50
            echo -e "\n${CYAN}=== 访问日志搜索结果 ===${NC}"
            [ -f "$ACCESS_LOG" ] && grep -n "$pattern" "$ACCESS_LOG" | head -50
            ;;
    esac
}

# 分析日志统计
analyze_logs() {
    local time_range="${1:-1d}"
    
    log_info "分析日志统计 (时间范围: $time_range)..."
    
    echo -e "${CYAN}=== 日志文件大小 ===${NC}"
    if [ -d "$LOG_DIR" ]; then
        du -sh "$LOG_DIR"/* 2>/dev/null | sort -hr || echo "无日志文件"
    fi
    
    echo -e "\n${CYAN}=== 错误统计 ===${NC}"
    if [ -f "$APP_LOG" ]; then
        local error_count=$(grep -c -i "error\|exception\|fatal" "$APP_LOG" 2>/dev/null || echo "0")
        echo "应用日志错误数: $error_count"
    fi
    
    if [ -f "$ERROR_LOG" ]; then
        local error_lines=$(wc -l < "$ERROR_LOG" 2>/dev/null || echo "0")
        echo "错误日志行数: $error_lines"
    fi
    
    echo -e "\n${CYAN}=== 访问统计 ===${NC}"
    if [ -f "$ACCESS_LOG" ]; then
        echo "总请求数: $(wc -l < "$ACCESS_LOG" 2>/dev/null || echo "0")"
        echo "状态码统计:"
        grep -o '"[0-9][0-9][0-9]"' "$ACCESS_LOG" 2>/dev/null | sort | uniq -c | sort -nr | head -10 || echo "无数据"
        echo "热门路径:"
        grep -o '"[A-Z]* [^"]*"' "$ACCESS_LOG" 2>/dev/null | sort | uniq -c | sort -nr | head -10 || echo "无数据"
    fi
    
    echo -e "\n${CYAN}=== 系统资源日志 ===${NC}"
    if [ -f "$MONITOR_LOG" ]; then
        echo "监控记录数: $(wc -l < "$MONITOR_LOG" 2>/dev/null || echo "0")"
        echo "最新资源使用:"
        tail -5 "$MONITOR_LOG" 2>/dev/null | grep "METRIC" || echo "无数据"
    fi
}

# 清理旧日志
clean_logs() {
    local days="${1:-$KEEP_DAYS}"
    local dry_run="${2:-false}"
    
    log_info "清理 $days 天前的日志文件..."
    
    if [ "$dry_run" = "true" ]; then
        log_info "预览模式 - 将要删除的文件:"
        find "$LOG_DIR" -name "*.log*" -type f -mtime +$days -ls 2>/dev/null || echo "无文件需要清理"
        find "$ARCHIVE_DIR" -name "*.gz" -type f -mtime +$days -ls 2>/dev/null || echo "无归档文件需要清理"
    else
        local deleted_count=0
        
        # 删除旧的日志文件
        while IFS= read -r -d '' file; do
            rm -f "$file"
            ((deleted_count++))
            log_info "已删除: $file"
        done < <(find "$LOG_DIR" -name "*.log.*" -type f -mtime +$days -print0 2>/dev/null)
        
        # 删除旧的归档文件
        while IFS= read -r -d '' file; do
            rm -f "$file"
            ((deleted_count++))
            log_info "已删除: $file"
        done < <(find "$ARCHIVE_DIR" -name "*.gz" -type f -mtime +$days -print0 2>/dev/null)
        
        log_success "清理完成，删除了 $deleted_count 个文件"
    fi
}

# 日志轮转
rotate_logs() {
    log_info "执行日志轮转..."
    
    local timestamp=$(date +%Y%m%d_%H%M%S)
    
    # 轮转应用日志
    if [ -f "$APP_LOG" ] && [ -s "$APP_LOG" ]; then
        local size=$(stat -f%z "$APP_LOG" 2>/dev/null || echo "0")
        if [ $size -gt 104857600 ]; then  # 100MB
            mv "$APP_LOG" "$ARCHIVE_DIR/app_${timestamp}.log"
            touch "$APP_LOG"
            gzip "$ARCHIVE_DIR/app_${timestamp}.log"
            log_success "应用日志已轮转: app_${timestamp}.log.gz"
        fi
    fi
    
    # 轮转错误日志
    if [ -f "$ERROR_LOG" ] && [ -s "$ERROR_LOG" ]; then
        local size=$(stat -f%z "$ERROR_LOG" 2>/dev/null || echo "0")
        if [ $size -gt 104857600 ]; then  # 100MB
            mv "$ERROR_LOG" "$ARCHIVE_DIR/error_${timestamp}.log"
            touch "$ERROR_LOG"
            gzip "$ARCHIVE_DIR/error_${timestamp}.log"
            log_success "错误日志已轮转: error_${timestamp}.log.gz"
        fi
    fi
    
    # 轮转访问日志
    if [ -f "$ACCESS_LOG" ] && [ -s "$ACCESS_LOG" ]; then
        local size=$(stat -f%z "$ACCESS_LOG" 2>/dev/null || echo "0")
        if [ $size -gt 104857600 ]; then  # 100MB
            mv "$ACCESS_LOG" "$ARCHIVE_DIR/access_${timestamp}.log"
            touch "$ACCESS_LOG"
            gzip "$ARCHIVE_DIR/access_${timestamp}.log"
            log_success "访问日志已轮转: access_${timestamp}.log.gz"
        fi
    fi
    
    # 重启应用以重新打开日志文件
    if command -v pm2 &> /dev/null && pm2 list | grep -q "$PM2_APP_NAME"; then
        pm2 reload "$PM2_APP_NAME"
        log_info "PM2 应用已重载"
    fi
}

# 导出日志
export_logs() {
    local start_date="$1"
    local end_date="$2"
    local output_file="$3"
    
    if [ -z "$start_date" ] || [ -z "$end_date" ]; then
        log_error "请提供开始和结束日期 (格式: YYYY-MM-DD)"
        return 1
    fi
    
    if [ -z "$output_file" ]; then
        output_file="$LOG_DIR/export_${start_date}_to_${end_date}.tar.gz"
    fi
    
    log_info "导出日志: $start_date 到 $end_date"
    
    local temp_dir=$(mktemp -d)
    
    # 复制指定日期范围的日志
    find "$LOG_DIR" -name "*.log*" -type f -newermt "$start_date" ! -newermt "$end_date 23:59:59" -exec cp {} "$temp_dir/" \;
    find "$ARCHIVE_DIR" -name "*.gz" -type f -newermt "$start_date" ! -newermt "$end_date 23:59:59" -exec cp {} "$temp_dir/" \;
    
    # 创建压缩包
    if [ "$(ls -A $temp_dir)" ]; then
        tar -czf "$output_file" -C "$temp_dir" .
        log_success "日志已导出到: $output_file"
    else
        log_warning "指定日期范围内无日志文件"
    fi
    
    # 清理临时目录
    rm -rf "$temp_dir"
}

# 实时日志监控
live_monitor() {
    log_info "启动实时日志监控 (按 Ctrl+C 退出)..."
    
    # 创建命名管道
    local fifo=$(mktemp -u)
    mkfifo "$fifo"
    
    # 启动多个 tail 进程
    if [ -f "$APP_LOG" ]; then
        tail -f "$APP_LOG" | sed 's/^/[APP] /' > "$fifo" &
    fi
    
    if [ -f "$ERROR_LOG" ]; then
        tail -f "$ERROR_LOG" | sed 's/^/[ERROR] /' > "$fifo" &
    fi
    
    if [ -f "$ACCESS_LOG" ]; then
        tail -f "$ACCESS_LOG" | sed 's/^/[ACCESS] /' > "$fifo" &
    fi
    
    # 读取并显示日志
    while read line; do
        case "$line" in
            *ERROR*|*error*|*Exception*|*Fatal*)
                echo -e "${RED}$line${NC}"
                ;;
            *WARN*|*warn*)
                echo -e "${YELLOW}$line${NC}"
                ;;
            *INFO*|*info*)
                echo -e "${BLUE}$line${NC}"
                ;;
            *SUCCESS*|*success*)
                echo -e "${GREEN}$line${NC}"
                ;;
            *)
                echo "$line"
                ;;
        esac
    done < "$fifo"
    
    # 清理
    rm -f "$fifo"
}

# 生成日志报告
generate_report() {
    local output_file="${1:-$LOG_DIR/log_report_$(date +%Y%m%d_%H%M%S).html}"
    
    log_info "生成日志报告..."
    
    cat > "$output_file" << EOF
<!DOCTYPE html>
<html>
<head>
    <title>WarpBean Backend 日志报告</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 20px; }
        .header { background: #f0f0f0; padding: 10px; border-radius: 5px; }
        .section { margin: 20px 0; }
        .error { color: red; }
        .warning { color: orange; }
        .info { color: blue; }
        table { border-collapse: collapse; width: 100%; }
        th, td { border: 1px solid #ddd; padding: 8px; text-align: left; }
        th { background-color: #f2f2f2; }
    </style>
</head>
<body>
    <div class="header">
        <h1>WarpBean Backend 日志报告</h1>
        <p>生成时间: $(date)</p>
        <p>服务器: $(hostname)</p>
    </div>
    
    <div class="section">
        <h2>日志文件概览</h2>
        <table>
            <tr><th>文件</th><th>大小</th><th>修改时间</th></tr>
EOF
    
    # 添加日志文件信息
    for log_file in "$APP_LOG" "$ERROR_LOG" "$ACCESS_LOG" "$MONITOR_LOG"; do
        if [ -f "$log_file" ]; then
            local size=$(ls -lh "$log_file" | awk '{print $5}')
            local mtime=$(ls -l "$log_file" | awk '{print $6, $7, $8}')
            echo "            <tr><td>$(basename "$log_file")</td><td>$size</td><td>$mtime</td></tr>" >> "$output_file"
        fi
    done
    
    cat >> "$output_file" << EOF
        </table>
    </div>
    
    <div class="section">
        <h2>错误统计</h2>
        <p>最近24小时错误数: $(grep -c "$(date -d '1 day ago' '+%Y-%m-%d')" "$ERROR_LOG" 2>/dev/null || echo "0")</p>
    </div>
    
    <div class="section">
        <h2>最新错误日志</h2>
        <pre>
$(tail -20 "$ERROR_LOG" 2>/dev/null | sed 's/</\&lt;/g; s/>/\&gt;/g' || echo "无错误日志")
        </pre>
    </div>
</body>
</html>
EOF
    
    log_success "日志报告已生成: $output_file"
}

# 显示帮助信息
show_help() {
    echo "WarpBean Backend 日志管理脚本"
    echo ""
    echo "用法: $0 [命令] [选项]"
    echo ""
    echo "命令:"
    echo "  tail [type] [lines]     查看实时日志 (type: app|error|access|pm2|all, 默认: all)"
    echo "  search <pattern> [type] 搜索日志内容"
    echo "  analyze [time]          分析日志统计 (time: 1h|6h|1d|7d|30d)"
    echo "  clean [days] [--dry]    清理旧日志 (默认: $KEEP_DAYS 天)"
    echo "  rotate                  执行日志轮转"
    echo "  export <start> <end>    导出指定日期范围的日志"
    echo "  monitor                 实时日志监控"
    echo "  report [file]           生成日志报告"
    echo "  help                    显示此帮助信息"
    echo ""
    echo "示例:"
    echo "  $0 tail app 100         查看应用日志最新100行"
    echo "  $0 search \"error\" app   在应用日志中搜索错误"
    echo "  $0 clean 7 --dry        预览7天前的日志清理"
    echo "  $0 export 2024-01-01 2024-01-31  导出1月份日志"
    echo ""
}

# 主函数
main() {
    create_log_dirs
    
    case "${1:-help}" in
        tail)
            tail_logs "$2" "$3"
            ;;
        search)
            search_logs "$2" "$3" "$4"
            ;;
        analyze)
            analyze_logs "$2"
            ;;
        clean)
            local dry_run="false"
            if [ "$3" = "--dry" ]; then
                dry_run="true"
            fi
            clean_logs "$2" "$dry_run"
            ;;
        rotate)
            rotate_logs
            ;;
        export)
            export_logs "$2" "$3" "$4"
            ;;
        monitor)
            live_monitor
            ;;
        report)
            generate_report "$2"
            ;;
        help|*)
            show_help
            ;;
    esac
}

# 执行主函数
main "$@"