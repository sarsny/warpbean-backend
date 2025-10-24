#!/bin/bash

# WarpBean Backend - Environment Manager Script
# 环境管理脚本，用于管理不同环境的配置和切换

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 配置
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_DIR="$PROJECT_ROOT/environments"
BACKUP_DIR="$PROJECT_ROOT/backups/env"

# 创建必要的目录
mkdir -p "$ENV_DIR"
mkdir -p "$BACKUP_DIR"

# 日志函数
log() {
    echo -e "${GREEN}[$(date '+%Y-%m-%d %H:%M:%S')] $1${NC}"
}

warn() {
    echo -e "${YELLOW}[$(date '+%Y-%m-%d %H:%M:%S')] WARNING: $1${NC}"
}

error() {
    echo -e "${RED}[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: $1${NC}"
}

info() {
    echo -e "${BLUE}[$(date '+%Y-%m-%d %H:%M:%S')] INFO: $1${NC}"
}

# 显示帮助信息
show_help() {
    echo "WarpBean Backend - Environment Manager"
    echo ""
    echo "Usage: $0 [COMMAND] [OPTIONS]"
    echo ""
    echo "Commands:"
    echo "  list                    列出所有可用环境"
    echo "  current                 显示当前环境"
    echo "  switch <env>           切换到指定环境"
    echo "  create <env>           创建新环境配置"
    echo "  copy <from> <to>       复制环境配置"
    echo "  delete <env>           删除环境配置"
    echo "  backup [env]           备份环境配置"
    echo "  restore <backup>       恢复环境配置"
    echo "  validate [env]         验证环境配置"
    echo "  diff <env1> <env2>     比较两个环境配置"
    echo "  export <env>           导出环境配置"
    echo "  import <file>          导入环境配置"
    echo "  template               创建环境配置模板"
    echo "  help                   显示帮助信息"
    echo ""
    echo "Examples:"
    echo "  $0 list"
    echo "  $0 switch production"
    echo "  $0 create staging"
    echo "  $0 backup production"
    echo "  $0 validate development"
}

# 列出所有环境
list_environments() {
    log "可用环境列表："
    
    if [ ! -d "$ENV_DIR" ] || [ -z "$(ls -A "$ENV_DIR" 2>/dev/null)" ]; then
        warn "未找到任何环境配置文件"
        return 1
    fi
    
    current_env=$(get_current_environment)
    
    for env_file in "$ENV_DIR"/*.env; do
        if [ -f "$env_file" ]; then
            env_name=$(basename "$env_file" .env)
            if [ "$env_name" = "$current_env" ]; then
                echo -e "  ${GREEN}* $env_name (当前)${NC}"
            else
                echo "  $env_name"
            fi
        fi
    done
}

# 获取当前环境
get_current_environment() {
    if [ -f "$PROJECT_ROOT/.env" ]; then
        # 尝试从.env文件中读取环境标识
        if grep -q "^NODE_ENV=" "$PROJECT_ROOT/.env"; then
            grep "^NODE_ENV=" "$PROJECT_ROOT/.env" | cut -d'=' -f2 | tr -d '"'"'"
        else
            echo "unknown"
        fi
    else
        echo "none"
    fi
}

# 显示当前环境
show_current_environment() {
    current_env=$(get_current_environment)
    log "当前环境: $current_env"
    
    if [ -f "$PROJECT_ROOT/.env" ]; then
        info "当前.env文件内容："
        cat "$PROJECT_ROOT/.env"
    else
        warn "未找到.env文件"
    fi
}

# 切换环境
switch_environment() {
    local target_env="$1"
    
    if [ -z "$target_env" ]; then
        error "请指定要切换的环境名称"
        return 1
    fi
    
    local env_file="$ENV_DIR/$target_env.env"
    
    if [ ! -f "$env_file" ]; then
        error "环境配置文件不存在: $env_file"
        return 1
    fi
    
    # 备份当前.env文件
    if [ -f "$PROJECT_ROOT/.env" ]; then
        local backup_name="env_backup_$(date +%Y%m%d_%H%M%S).env"
        cp "$PROJECT_ROOT/.env" "$BACKUP_DIR/$backup_name"
        info "已备份当前.env文件到: $backup_name"
    fi
    
    # 复制新的环境配置
    cp "$env_file" "$PROJECT_ROOT/.env"
    
    # 确保NODE_ENV设置正确
    if ! grep -q "^NODE_ENV=" "$PROJECT_ROOT/.env"; then
        echo "NODE_ENV=$target_env" >> "$PROJECT_ROOT/.env"
    else
        sed -i.bak "s/^NODE_ENV=.*/NODE_ENV=$target_env/" "$PROJECT_ROOT/.env"
        rm -f "$PROJECT_ROOT/.env.bak"
    fi
    
    log "已切换到环境: $target_env"
    
    # 验证新环境
    validate_environment "$target_env"
}

# 创建新环境
create_environment() {
    local env_name="$1"
    
    if [ -z "$env_name" ]; then
        error "请指定环境名称"
        return 1
    fi
    
    local env_file="$ENV_DIR/$env_name.env"
    
    if [ -f "$env_file" ]; then
        error "环境配置已存在: $env_name"
        return 1
    fi
    
    # 基于.env.example创建新环境
    if [ -f "$PROJECT_ROOT/.env.example" ]; then
        cp "$PROJECT_ROOT/.env.example" "$env_file"
    else
        # 创建基本模板
        create_template > "$env_file"
    fi
    
    # 设置NODE_ENV
    echo "NODE_ENV=$env_name" >> "$env_file"
    
    log "已创建环境配置: $env_name"
    info "请编辑文件进行配置: $env_file"
}

# 复制环境配置
copy_environment() {
    local from_env="$1"
    local to_env="$2"
    
    if [ -z "$from_env" ] || [ -z "$to_env" ]; then
        error "请指定源环境和目标环境名称"
        return 1
    fi
    
    local from_file="$ENV_DIR/$from_env.env"
    local to_file="$ENV_DIR/$to_env.env"
    
    if [ ! -f "$from_file" ]; then
        error "源环境配置不存在: $from_env"
        return 1
    fi
    
    if [ -f "$to_file" ]; then
        error "目标环境配置已存在: $to_env"
        return 1
    fi
    
    cp "$from_file" "$to_file"
    
    # 更新NODE_ENV
    sed -i.bak "s/^NODE_ENV=.*/NODE_ENV=$to_env/" "$to_file"
    rm -f "$to_file.bak"
    
    log "已复制环境配置: $from_env -> $to_env"
}

# 删除环境配置
delete_environment() {
    local env_name="$1"
    
    if [ -z "$env_name" ]; then
        error "请指定要删除的环境名称"
        return 1
    fi
    
    local env_file="$ENV_DIR/$env_name.env"
    
    if [ ! -f "$env_file" ]; then
        error "环境配置不存在: $env_name"
        return 1
    fi
    
    # 确认删除
    read -p "确定要删除环境配置 '$env_name' 吗? (y/N): " confirm
    if [ "$confirm" != "y" ] && [ "$confirm" != "Y" ]; then
        info "操作已取消"
        return 0
    fi
    
    # 备份后删除
    local backup_name="deleted_${env_name}_$(date +%Y%m%d_%H%M%S).env"
    cp "$env_file" "$BACKUP_DIR/$backup_name"
    rm "$env_file"
    
    log "已删除环境配置: $env_name"
    info "备份文件: $backup_name"
}

# 备份环境配置
backup_environment() {
    local env_name="$1"
    
    if [ -z "$env_name" ]; then
        # 备份所有环境
        local backup_file="$BACKUP_DIR/all_environments_$(date +%Y%m%d_%H%M%S).tar.gz"
        tar -czf "$backup_file" -C "$ENV_DIR" .
        log "已备份所有环境配置到: $(basename "$backup_file")"
    else
        # 备份指定环境
        local env_file="$ENV_DIR/$env_name.env"
        
        if [ ! -f "$env_file" ]; then
            error "环境配置不存在: $env_name"
            return 1
        fi
        
        local backup_name="${env_name}_$(date +%Y%m%d_%H%M%S).env"
        cp "$env_file" "$BACKUP_DIR/$backup_name"
        log "已备份环境配置: $env_name -> $backup_name"
    fi
}

# 恢复环境配置
restore_environment() {
    local backup_file="$1"
    
    if [ -z "$backup_file" ]; then
        error "请指定备份文件名"
        return 1
    fi
    
    local full_backup_path="$BACKUP_DIR/$backup_file"
    
    if [ ! -f "$full_backup_path" ]; then
        error "备份文件不存在: $backup_file"
        return 1
    fi
    
    # 确认恢复
    read -p "确定要恢复备份 '$backup_file' 吗? 这将覆盖现有配置 (y/N): " confirm
    if [ "$confirm" != "y" ] && [ "$confirm" != "Y" ]; then
        info "操作已取消"
        return 0
    fi
    
    if [[ "$backup_file" == *.tar.gz ]]; then
        # 恢复所有环境
        tar -xzf "$full_backup_path" -C "$ENV_DIR"
        log "已恢复所有环境配置"
    else
        # 恢复单个环境
        local env_name=$(echo "$backup_file" | sed 's/_[0-9]*_[0-9]*.env$//')
        cp "$full_backup_path" "$ENV_DIR/$env_name.env"
        log "已恢复环境配置: $env_name"
    fi
}

# 验证环境配置
validate_environment() {
    local env_name="$1"
    local env_file
    
    if [ -z "$env_name" ]; then
        env_file="$PROJECT_ROOT/.env"
        env_name="current"
    else
        env_file="$ENV_DIR/$env_name.env"
    fi
    
    if [ ! -f "$env_file" ]; then
        error "环境配置文件不存在: $env_file"
        return 1
    fi
    
    log "验证环境配置: $env_name"
    
    local errors=0
    
    # 检查必需的环境变量
    local required_vars=("PORT" "DB_HOST" "DB_PORT" "DB_NAME" "DB_USER" "DB_PASSWORD" "JWT_SECRET")
    
    for var in "${required_vars[@]}"; do
        if ! grep -q "^$var=" "$env_file"; then
            error "缺少必需的环境变量: $var"
            ((errors++))
        fi
    done
    
    # 检查端口号格式
    if grep -q "^PORT=" "$env_file"; then
        local port=$(grep "^PORT=" "$env_file" | cut -d'=' -f2)
        if ! [[ "$port" =~ ^[0-9]+$ ]] || [ "$port" -lt 1 ] || [ "$port" -gt 65535 ]; then
            error "无效的端口号: $port"
            ((errors++))
        fi
    fi
    
    # 检查数据库端口
    if grep -q "^DB_PORT=" "$env_file"; then
        local db_port=$(grep "^DB_PORT=" "$env_file" | cut -d'=' -f2)
        if ! [[ "$db_port" =~ ^[0-9]+$ ]] || [ "$db_port" -lt 1 ] || [ "$db_port" -gt 65535 ]; then
            error "无效的数据库端口号: $db_port"
            ((errors++))
        fi
    fi
    
    # 检查JWT密钥长度
    if grep -q "^JWT_SECRET=" "$env_file"; then
        local jwt_secret=$(grep "^JWT_SECRET=" "$env_file" | cut -d'=' -f2)
        if [ ${#jwt_secret} -lt 32 ]; then
            warn "JWT密钥长度过短，建议至少32个字符"
        fi
    fi
    
    if [ $errors -eq 0 ]; then
        log "环境配置验证通过"
        return 0
    else
        error "环境配置验证失败，发现 $errors 个错误"
        return 1
    fi
}

# 比较环境配置
diff_environments() {
    local env1="$1"
    local env2="$2"
    
    if [ -z "$env1" ] || [ -z "$env2" ]; then
        error "请指定两个要比较的环境名称"
        return 1
    fi
    
    local file1="$ENV_DIR/$env1.env"
    local file2="$ENV_DIR/$env2.env"
    
    if [ ! -f "$file1" ]; then
        error "环境配置不存在: $env1"
        return 1
    fi
    
    if [ ! -f "$file2" ]; then
        error "环境配置不存在: $env2"
        return 1
    fi
    
    log "比较环境配置: $env1 vs $env2"
    
    if command -v colordiff >/dev/null 2>&1; then
        colordiff -u "$file1" "$file2"
    else
        diff -u "$file1" "$file2"
    fi
}

# 导出环境配置
export_environment() {
    local env_name="$1"
    
    if [ -z "$env_name" ]; then
        error "请指定要导出的环境名称"
        return 1
    fi
    
    local env_file="$ENV_DIR/$env_name.env"
    
    if [ ! -f "$env_file" ]; then
        error "环境配置不存在: $env_name"
        return 1
    fi
    
    local export_file="${env_name}_export_$(date +%Y%m%d_%H%M%S).env"
    cp "$env_file" "$export_file"
    
    log "已导出环境配置: $export_file"
}

# 导入环境配置
import_environment() {
    local import_file="$1"
    
    if [ -z "$import_file" ]; then
        error "请指定要导入的文件"
        return 1
    fi
    
    if [ ! -f "$import_file" ]; then
        error "导入文件不存在: $import_file"
        return 1
    fi
    
    # 提取环境名称
    local env_name=$(basename "$import_file" .env | sed 's/_export_[0-9]*_[0-9]*$//')
    local env_file="$ENV_DIR/$env_name.env"
    
    if [ -f "$env_file" ]; then
        read -p "环境配置 '$env_name' 已存在，是否覆盖? (y/N): " confirm
        if [ "$confirm" != "y" ] && [ "$confirm" != "Y" ]; then
            info "操作已取消"
            return 0
        fi
    fi
    
    cp "$import_file" "$env_file"
    log "已导入环境配置: $env_name"
}

# 创建环境配置模板
create_template() {
    cat << 'EOF'
# WarpBean Backend Environment Configuration

# Server Configuration
PORT=3000
NODE_ENV=development

# Database Configuration
DB_HOST=localhost
DB_PORT=5432
DB_NAME=warpbean
DB_USER=postgres
DB_PASSWORD=your_password

# JWT Configuration
JWT_SECRET=your_jwt_secret_key_here_at_least_32_characters
JWT_EXPIRES_IN=24h

# DeepSeek API Configuration
DEEPSEEK_API_KEY=your_deepseek_api_key
DEEPSEEK_BASE_URL=https://api.deepseek.com

# Rate Limiting
RATE_LIMIT_WINDOW_MS=900000
RATE_LIMIT_MAX_REQUESTS=100

# CORS Configuration
CORS_ORIGIN=http://localhost:3000

# Logging
LOG_LEVEL=info
EOF
}

# 主函数
main() {
    case "$1" in
        "list")
            list_environments
            ;;
        "current")
            show_current_environment
            ;;
        "switch")
            switch_environment "$2"
            ;;
        "create")
            create_environment "$2"
            ;;
        "copy")
            copy_environment "$2" "$3"
            ;;
        "delete")
            delete_environment "$2"
            ;;
        "backup")
            backup_environment "$2"
            ;;
        "restore")
            restore_environment "$2"
            ;;
        "validate")
            validate_environment "$2"
            ;;
        "diff")
            diff_environments "$2" "$3"
            ;;
        "export")
            export_environment "$2"
            ;;
        "import")
            import_environment "$2"
            ;;
        "template")
            create_template
            ;;
        "help"|"--help"|"-h"|"")
            show_help
            ;;
        *)
            error "未知命令: $1"
            show_help
            exit 1
            ;;
    esac
}

# 执行主函数
main "$@"