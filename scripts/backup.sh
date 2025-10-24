#!/bin/bash

# WarpBean Backend 数据库备份脚本
# 用于数据库备份、恢复和管理

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
BACKUP_DIR="$APP_DIR/backups"
LOG_DIR="$APP_DIR/logs"

# 从环境变量读取数据库配置
if [ -f "$APP_DIR/.env" ]; then
    source "$APP_DIR/.env"
fi

# 数据库配置 (从环境变量或默认值)
DB_HOST="${DB_HOST:-localhost}"
DB_PORT="${DB_PORT:-5432}"
DB_NAME="${DB_NAME:-warpbean}"
DB_USER="${DB_USER:-postgres}"
DB_PASSWORD="${DB_PASSWORD:-password}"

# 备份配置
KEEP_DAYS=30                    # 保留备份天数
MAX_BACKUPS=50                  # 最大备份文件数
COMPRESS=true                   # 是否压缩备份
BACKUP_LOG="$LOG_DIR/backup.log"

# 日志函数
log_info() {
    local message="$1"
    echo -e "${BLUE}[INFO]${NC} $message"
    echo "$(date '+%Y-%m-%d %H:%M:%S') [INFO] $message" >> "$BACKUP_LOG"
}

log_success() {
    local message="$1"
    echo -e "${GREEN}[SUCCESS]${NC} $message"
    echo "$(date '+%Y-%m-%d %H:%M:%S') [SUCCESS] $message" >> "$BACKUP_LOG"
}

log_warning() {
    local message="$1"
    echo -e "${YELLOW}[WARNING]${NC} $message"
    echo "$(date '+%Y-%m-%d %H:%M:%S') [WARNING] $message" >> "$BACKUP_LOG"
}

log_error() {
    local message="$1"
    echo -e "${RED}[ERROR]${NC} $message"
    echo "$(date '+%Y-%m-%d %H:%M:%S') [ERROR] $message" >> "$BACKUP_LOG"
}

# 创建备份目录
create_backup_dirs() {
    mkdir -p "$BACKUP_DIR"
    mkdir -p "$LOG_DIR"
    log_info "备份目录已创建: $BACKUP_DIR"
}

# 检查数据库连接
check_db_connection() {
    log_info "检查数据库连接..."
    
    export PGPASSWORD="$DB_PASSWORD"
    
    if pg_isready -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" >/dev/null 2>&1; then
        log_success "数据库连接正常"
        return 0
    else
        log_error "无法连接到数据库 $DB_HOST:$DB_PORT/$DB_NAME"
        return 1
    fi
}

# 创建数据库备份
create_backup() {
    local backup_type="${1:-full}"
    local custom_name="$2"
    
    if ! check_db_connection; then
        return 1
    fi
    
    local timestamp=$(date +%Y%m%d_%H%M%S)
    local backup_name
    
    if [ -n "$custom_name" ]; then
        backup_name="${custom_name}_${timestamp}"
    else
        backup_name="${DB_NAME}_${backup_type}_${timestamp}"
    fi
    
    local backup_file="$BACKUP_DIR/${backup_name}.sql"
    
    log_info "开始创建数据库备份: $backup_name"
    
    export PGPASSWORD="$DB_PASSWORD"
    
    case $backup_type in
        full)
            # 完整备份
            if pg_dump -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" \
                --verbose --clean --if-exists --create \
                --format=plain --encoding=UTF8 \
                > "$backup_file" 2>>"$BACKUP_LOG"; then
                log_success "完整备份创建成功"
            else
                log_error "完整备份创建失败"
                return 1
            fi
            ;;
        schema)
            # 仅结构备份
            if pg_dump -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" \
                --verbose --clean --if-exists --create \
                --schema-only --format=plain --encoding=UTF8 \
                > "$backup_file" 2>>"$BACKUP_LOG"; then
                log_success "结构备份创建成功"
            else
                log_error "结构备份创建失败"
                return 1
            fi
            ;;
        data)
            # 仅数据备份
            if pg_dump -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" \
                --verbose --data-only --format=plain --encoding=UTF8 \
                > "$backup_file" 2>>"$BACKUP_LOG"; then
                log_success "数据备份创建成功"
            else
                log_error "数据备份创建失败"
                return 1
            fi
            ;;
        custom)
            # 自定义格式备份
            backup_file="$BACKUP_DIR/${backup_name}.dump"
            if pg_dump -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" \
                --verbose --clean --if-exists --create \
                --format=custom --encoding=UTF8 \
                --file="$backup_file" 2>>"$BACKUP_LOG"; then
                log_success "自定义格式备份创建成功"
            else
                log_error "自定义格式备份创建失败"
                return 1
            fi
            ;;
        *)
            log_error "不支持的备份类型: $backup_type"
            return 1
            ;;
    esac
    
    # 获取备份文件大小
    local file_size=$(ls -lh "$backup_file" | awk '{print $5}')
    log_info "备份文件大小: $file_size"
    
    # 压缩备份文件
    if [ "$COMPRESS" = "true" ] && [[ "$backup_file" == *.sql ]]; then
        log_info "压缩备份文件..."
        if gzip "$backup_file"; then
            backup_file="${backup_file}.gz"
            local compressed_size=$(ls -lh "$backup_file" | awk '{print $5}')
            log_success "备份文件已压缩: $compressed_size"
        else
            log_warning "备份文件压缩失败"
        fi
    fi
    
    # 验证备份文件
    if [ -f "$backup_file" ] && [ -s "$backup_file" ]; then
        log_success "备份创建完成: $backup_file"
        
        # 记录备份信息
        echo "$(date '+%Y-%m-%d %H:%M:%S')|$backup_type|$backup_file|$file_size" >> "$BACKUP_DIR/backup_history.log"
        
        return 0
    else
        log_error "备份文件创建失败或为空"
        return 1
    fi
}

# 列出备份文件
list_backups() {
    local filter="$1"
    
    log_info "列出备份文件..."
    
    if [ ! -d "$BACKUP_DIR" ] || [ -z "$(ls -A "$BACKUP_DIR" 2>/dev/null)" ]; then
        log_warning "备份目录为空"
        return 0
    fi
    
    echo -e "${CYAN}=== 备份文件列表 ===${NC}"
    printf "%-30s %-15s %-20s %-10s\n" "文件名" "类型" "创建时间" "大小"
    echo "--------------------------------------------------------------------------------"
    
    for backup_file in "$BACKUP_DIR"/*.{sql,sql.gz,dump} 2>/dev/null; do
        if [ -f "$backup_file" ]; then
            local filename=$(basename "$backup_file")
            
            # 应用过滤器
            if [ -n "$filter" ] && [[ "$filename" != *"$filter"* ]]; then
                continue
            fi
            
            local file_size=$(ls -lh "$backup_file" | awk '{print $5}')
            local file_time=$(ls -l "$backup_file" | awk '{print $6, $7, $8}')
            
            # 确定备份类型
            local backup_type="unknown"
            if [[ "$filename" == *"_full_"* ]]; then
                backup_type="full"
            elif [[ "$filename" == *"_schema_"* ]]; then
                backup_type="schema"
            elif [[ "$filename" == *"_data_"* ]]; then
                backup_type="data"
            elif [[ "$filename" == *".dump" ]]; then
                backup_type="custom"
            fi
            
            printf "%-30s %-15s %-20s %-10s\n" "$filename" "$backup_type" "$file_time" "$file_size"
        fi
    done
    
    # 显示备份历史统计
    if [ -f "$BACKUP_DIR/backup_history.log" ]; then
        echo -e "\n${CYAN}=== 备份统计 ===${NC}"
        local total_backups=$(wc -l < "$BACKUP_DIR/backup_history.log")
        local today_backups=$(grep "$(date '+%Y-%m-%d')" "$BACKUP_DIR/backup_history.log" | wc -l)
        echo "总备份数: $total_backups"
        echo "今日备份数: $today_backups"
    fi
}

# 恢复数据库
restore_backup() {
    local backup_file="$1"
    local target_db="${2:-$DB_NAME}"
    local confirm="${3:-false}"
    
    if [ -z "$backup_file" ]; then
        log_error "请指定备份文件"
        return 1
    fi
    
    # 检查备份文件是否存在
    if [ ! -f "$backup_file" ]; then
        # 尝试在备份目录中查找
        if [ -f "$BACKUP_DIR/$backup_file" ]; then
            backup_file="$BACKUP_DIR/$backup_file"
        else
            log_error "备份文件不存在: $backup_file"
            return 1
        fi
    fi
    
    if [ "$confirm" != "true" ]; then
        echo -e "${YELLOW}警告: 此操作将覆盖数据库 '$target_db' 的所有数据！${NC}"
        echo -e "备份文件: $backup_file"
        echo -e "目标数据库: $target_db"
        read -p "确认继续? (yes/no): " confirmation
        if [ "$confirmation" != "yes" ]; then
            log_info "恢复操作已取消"
            return 0
        fi
    fi
    
    if ! check_db_connection; then
        return 1
    fi
    
    log_info "开始恢复数据库: $target_db"
    log_info "使用备份文件: $backup_file"
    
    export PGPASSWORD="$DB_PASSWORD"
    
    # 根据文件扩展名选择恢复方法
    if [[ "$backup_file" == *.gz ]]; then
        # 压缩的SQL文件
        if gunzip -c "$backup_file" | psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$target_db" \
            -v ON_ERROR_STOP=1 2>>"$BACKUP_LOG"; then
            log_success "数据库恢复成功"
        else
            log_error "数据库恢复失败"
            return 1
        fi
    elif [[ "$backup_file" == *.sql ]]; then
        # 普通SQL文件
        if psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$target_db" \
            -f "$backup_file" -v ON_ERROR_STOP=1 2>>"$BACKUP_LOG"; then
            log_success "数据库恢复成功"
        else
            log_error "数据库恢复失败"
            return 1
        fi
    elif [[ "$backup_file" == *.dump ]]; then
        # 自定义格式文件
        if pg_restore -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$target_db" \
            --verbose --clean --if-exists --create \
            "$backup_file" 2>>"$BACKUP_LOG"; then
            log_success "数据库恢复成功"
        else
            log_error "数据库恢复失败"
            return 1
        fi
    else
        log_error "不支持的备份文件格式"
        return 1
    fi
    
    # 记录恢复操作
    echo "$(date '+%Y-%m-%d %H:%M:%S')|RESTORE|$backup_file|$target_db" >> "$BACKUP_DIR/restore_history.log"
}

# 清理旧备份
clean_backups() {
    local days="${1:-$KEEP_DAYS}"
    local max_files="${2:-$MAX_BACKUPS}"
    local dry_run="${3:-false}"
    
    log_info "清理备份文件 (保留 $days 天, 最多 $max_files 个文件)..."
    
    if [ "$dry_run" = "true" ]; then
        log_info "预览模式 - 将要删除的文件:"
        
        # 按时间清理
        find "$BACKUP_DIR" -name "*.sql*" -o -name "*.dump" -type f -mtime +$days -ls 2>/dev/null || echo "无过期文件"
        
        # 按数量清理
        local file_count=$(find "$BACKUP_DIR" -name "*.sql*" -o -name "*.dump" -type f | wc -l)
        if [ $file_count -gt $max_files ]; then
            local excess=$((file_count - max_files))
            echo "超出数量限制，需要删除最旧的 $excess 个文件:"
            find "$BACKUP_DIR" -name "*.sql*" -o -name "*.dump" -type f -printf '%T@ %p\n' | sort -n | head -n $excess | cut -d' ' -f2-
        fi
    else
        local deleted_count=0
        
        # 按时间删除旧文件
        while IFS= read -r -d '' file; do
            rm -f "$file"
            ((deleted_count++))
            log_info "已删除过期备份: $(basename "$file")"
        done < <(find "$BACKUP_DIR" -name "*.sql*" -o -name "*.dump" -type f -mtime +$days -print0 2>/dev/null)
        
        # 按数量删除多余文件
        local file_count=$(find "$BACKUP_DIR" -name "*.sql*" -o -name "*.dump" -type f | wc -l)
        if [ $file_count -gt $max_files ]; then
            local excess=$((file_count - max_files))
            log_info "删除多余的备份文件 ($excess 个)..."
            
            find "$BACKUP_DIR" -name "*.sql*" -o -name "*.dump" -type f -printf '%T@ %p\n' | \
            sort -n | head -n $excess | cut -d' ' -f2- | \
            while read file; do
                rm -f "$file"
                ((deleted_count++))
                log_info "已删除多余备份: $(basename "$file")"
            done
        fi
        
        log_success "清理完成，删除了 $deleted_count 个备份文件"
    fi
}

# 验证备份文件
verify_backup() {
    local backup_file="$1"
    
    if [ -z "$backup_file" ]; then
        log_error "请指定备份文件"
        return 1
    fi
    
    if [ ! -f "$backup_file" ]; then
        if [ -f "$BACKUP_DIR/$backup_file" ]; then
            backup_file="$BACKUP_DIR/$backup_file"
        else
            log_error "备份文件不存在: $backup_file"
            return 1
        fi
    fi
    
    log_info "验证备份文件: $backup_file"
    
    # 检查文件大小
    if [ ! -s "$backup_file" ]; then
        log_error "备份文件为空"
        return 1
    fi
    
    local file_size=$(ls -lh "$backup_file" | awk '{print $5}')
    log_info "文件大小: $file_size"
    
    # 根据文件类型进行验证
    if [[ "$backup_file" == *.gz ]]; then
        # 验证压缩文件
        if gunzip -t "$backup_file" 2>/dev/null; then
            log_success "压缩文件完整性验证通过"
        else
            log_error "压缩文件损坏"
            return 1
        fi
        
        # 验证SQL内容
        if gunzip -c "$backup_file" | head -10 | grep -q "PostgreSQL database dump"; then
            log_success "SQL备份格式验证通过"
        else
            log_warning "无法确认SQL备份格式"
        fi
        
    elif [[ "$backup_file" == *.sql ]]; then
        # 验证SQL文件
        if head -10 "$backup_file" | grep -q "PostgreSQL database dump"; then
            log_success "SQL备份格式验证通过"
        else
            log_warning "无法确认SQL备份格式"
        fi
        
    elif [[ "$backup_file" == *.dump ]]; then
        # 验证自定义格式文件
        if file "$backup_file" | grep -q "PostgreSQL custom database dump"; then
            log_success "自定义格式备份验证通过"
        else
            log_warning "无法确认自定义格式备份"
        fi
    fi
    
    # 显示备份文件信息
    echo -e "\n${CYAN}=== 备份文件信息 ===${NC}"
    echo "文件路径: $backup_file"
    echo "文件大小: $file_size"
    echo "修改时间: $(ls -l "$backup_file" | awk '{print $6, $7, $8}')"
    echo "文件类型: $(file -b "$backup_file")"
    
    log_success "备份文件验证完成"
}

# 自动备份
auto_backup() {
    local backup_type="${1:-full}"
    
    log_info "执行自动备份..."
    
    # 创建备份
    if create_backup "$backup_type" "auto"; then
        log_success "自动备份完成"
        
        # 自动清理旧备份
        clean_backups "$KEEP_DAYS" "$MAX_BACKUPS"
        
        return 0
    else
        log_error "自动备份失败"
        return 1
    fi
}

# 显示备份统计
show_stats() {
    log_info "备份统计信息..."
    
    echo -e "${CYAN}=== 备份目录信息 ===${NC}"
    if [ -d "$BACKUP_DIR" ]; then
        echo "备份目录: $BACKUP_DIR"
        echo "目录大小: $(du -sh "$BACKUP_DIR" | cut -f1)"
        echo "文件数量: $(find "$BACKUP_DIR" -name "*.sql*" -o -name "*.dump" -type f | wc -l)"
    else
        echo "备份目录不存在"
    fi
    
    echo -e "\n${CYAN}=== 最近备份 ===${NC}"
    if [ -f "$BACKUP_DIR/backup_history.log" ]; then
        tail -10 "$BACKUP_DIR/backup_history.log" | while IFS='|' read -r timestamp type file size; do
            echo "$timestamp - $type - $(basename "$file") - $size"
        done
    else
        echo "无备份历史记录"
    fi
    
    echo -e "\n${CYAN}=== 数据库信息 ===${NC}"
    if check_db_connection >/dev/null 2>&1; then
        export PGPASSWORD="$DB_PASSWORD"
        echo "数据库: $DB_NAME"
        echo "主机: $DB_HOST:$DB_PORT"
        echo "用户: $DB_USER"
        
        # 获取数据库大小
        local db_size=$(psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" \
            -t -c "SELECT pg_size_pretty(pg_database_size('$DB_NAME'));" 2>/dev/null | xargs)
        echo "数据库大小: ${db_size:-未知}"
        
        # 获取表数量
        local table_count=$(psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" \
            -t -c "SELECT count(*) FROM information_schema.tables WHERE table_schema = 'public';" 2>/dev/null | xargs)
        echo "表数量: ${table_count:-未知}"
    else
        echo "无法连接到数据库"
    fi
}

# 显示帮助信息
show_help() {
    echo "WarpBean Backend 数据库备份脚本"
    echo ""
    echo "用法: $0 [命令] [选项]"
    echo ""
    echo "命令:"
    echo "  backup [type] [name]    创建数据库备份"
    echo "    type: full|schema|data|custom (默认: full)"
    echo "    name: 自定义备份名称前缀"
    echo "  list [filter]           列出备份文件"
    echo "  restore <file> [db]     恢复数据库备份"
    echo "  verify <file>           验证备份文件完整性"
    echo "  clean [days] [max] [--dry]  清理旧备份"
    echo "  auto [type]             执行自动备份和清理"
    echo "  stats                   显示备份统计信息"
    echo "  help                    显示此帮助信息"
    echo ""
    echo "环境变量:"
    echo "  DB_HOST                 数据库主机 (默认: localhost)"
    echo "  DB_PORT                 数据库端口 (默认: 5432)"
    echo "  DB_NAME                 数据库名称 (默认: warpbean)"
    echo "  DB_USER                 数据库用户 (默认: postgres)"
    echo "  DB_PASSWORD             数据库密码 (默认: password)"
    echo ""
    echo "示例:"
    echo "  $0 backup full          创建完整备份"
    echo "  $0 backup schema prod   创建结构备份，名称包含'prod'"
    echo "  $0 list full            列出所有完整备份"
    echo "  $0 restore backup.sql   恢复指定备份"
    echo "  $0 clean 7 20 --dry     预览清理7天前的备份，保留最多20个"
    echo "  $0 auto                 执行自动备份"
    echo ""
}

# 主函数
main() {
    create_backup_dirs
    
    case "${1:-help}" in
        backup)
            create_backup "$2" "$3"
            ;;
        list)
            list_backups "$2"
            ;;
        restore)
            restore_backup "$2" "$3" "$4"
            ;;
        verify)
            verify_backup "$2"
            ;;
        clean)
            local dry_run="false"
            if [ "$4" = "--dry" ]; then
                dry_run="true"
            fi
            clean_backups "$2" "$3" "$dry_run"
            ;;
        auto)
            auto_backup "$2"
            ;;
        stats)
            show_stats
            ;;
        help|*)
            show_help
            ;;
    esac
}

# 执行主函数
main "$@"