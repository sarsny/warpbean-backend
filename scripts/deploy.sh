#!/bin/bash

# WarpBean Backend 部署脚本
# 用于自动化部署 Node.js 应用

set -e  # 遇到错误立即退出

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 配置变量
APP_NAME="warpbean-backend"
# 动态获取脚本所在目录的上级目录作为应用目录
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_DIR="$(dirname "$SCRIPT_DIR")"
NODE_ENV=${NODE_ENV:-production}
PORT=${PORT:-3000}
PM2_APP_NAME="warpbean-backend"

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

# 检查命令是否存在
check_command() {
    if ! command -v $1 &> /dev/null; then
        log_error "$1 未安装，请先安装 $1"
        exit 1
    fi
}

# 检查环境
check_environment() {
    log_info "检查部署环境..."
    
    # 检查 Node.js
    check_command "node"
    NODE_VERSION=$(node --version)
    log_info "Node.js 版本: $NODE_VERSION"
    
    # 检查 npm
    check_command "npm"
    NPM_VERSION=$(npm --version)
    log_info "npm 版本: $NPM_VERSION"
    
    # 检查 Git
    check_command "git"
    GIT_VERSION=$(git --version)
    log_info "Git 版本: $GIT_VERSION"
    
    # 检查 PM2 (可选)
    if command -v pm2 &> /dev/null; then
        PM2_VERSION=$(pm2 --version)
        log_info "PM2 版本: $PM2_VERSION"
        USE_PM2=true
    else
        log_warning "PM2 未安装，将使用 node 直接启动"
        USE_PM2=false
    fi
    
    # 检查数据库（可选/可禁用）
    if [ "$DB_DISABLED" = "true" ] || [ "$DB_DISABLED" = "1" ]; then
        log_info "数据库已禁用，跳过 MySQL 检查"
    else
        if command -v mysql &> /dev/null; then
            log_info "MySQL 已安装"
        else
            log_warning "MySQL 未检测到，请确保数据库服务正常运行"
        fi
    fi
}

# 备份当前版本
backup_current() {
    if [ -d "$APP_DIR" ]; then
        log_info "备份当前版本..."
        BACKUP_DIR="${APP_DIR}_backup_$(date +%Y%m%d_%H%M%S)"
        cp -r "$APP_DIR" "$BACKUP_DIR"
        log_success "备份完成: $BACKUP_DIR"
    fi
}

# 拉取最新代码
pull_latest_code() {
    log_info "拉取最新代码..."
    cd "$APP_DIR"
    
    # 检查是否是Git仓库
    if [ ! -d ".git" ]; then
        log_warning "当前目录不是Git仓库，跳过代码拉取"
        return 0
    fi
    
    # 检查是否有未提交的更改
    if ! git diff-index --quiet HEAD --; then
        log_warning "检测到未提交的更改，将暂存当前更改"
        git stash push -m "Auto stash before deployment $(date)"
    fi
    
    # 获取当前分支
    CURRENT_BRANCH=$(git branch --show-current)
    log_info "当前分支: $CURRENT_BRANCH"
    
    # 拉取最新代码
    if git pull origin "$CURRENT_BRANCH"; then
        log_success "代码拉取完成"
    else
        log_error "代码拉取失败"
        exit 1
    fi
    
    # 显示最新提交信息
    LATEST_COMMIT=$(git log -1 --pretty=format:"%h - %s (%an, %ar)")
    log_info "最新提交: $LATEST_COMMIT"
}

# 安装依赖
install_dependencies() {
    log_info "安装项目依赖..."
    cd "$APP_DIR"
    
    # 清理 node_modules (可选)
    if [ "$1" = "--clean" ]; then
        log_info "清理旧的依赖..."
        rm -rf node_modules package-lock.json
    fi
    
    npm ci --production
    log_success "依赖安装完成"
}

# 检查环境变量
check_env_file() {
    log_info "检查环境配置..."
    
    if [ ! -f "$APP_DIR/.env" ]; then
        if [ -f "$APP_DIR/.env.example" ]; then
            log_warning ".env 文件不存在，从 .env.example 创建"
            cp "$APP_DIR/.env.example" "$APP_DIR/.env"
            log_warning "请编辑 .env 文件配置正确的环境变量"
        else
            log_error ".env 和 .env.example 文件都不存在"
            exit 1
        fi
    fi
    
    # 检查关键环境变量
    source "$APP_DIR/.env"

    # 如果禁用数据库，只检查 JWT_SECRET；否则检查数据库相关配置
    if [ "$DB_DISABLED" = "true" ] || [ "$DB_DISABLED" = "1" ]; then
        if [ -z "$JWT_SECRET" ]; then
            log_error "JWT_SECRET 未配置，请检查 .env 文件"
            exit 1
        fi
    else
        if [ -z "$DB_HOST" ] || [ -z "$DB_NAME" ] || [ -z "$JWT_SECRET" ]; then
            log_error "关键环境变量未配置，请检查 .env 文件 (需要 DB_HOST, DB_NAME, JWT_SECRET)"
            exit 1
        fi
    fi
    
    log_success "环境配置检查通过"
}

# 数据库迁移
run_migration() {
    # 跳过迁移（禁用数据库）
    if [ "$DB_DISABLED" = "true" ] || [ "$DB_DISABLED" = "1" ]; then
        log_info "数据库已禁用，跳过数据库迁移"
        return 0
    fi

    log_info "执行数据库迁移..."
    cd "$APP_DIR"
    
    if npm run migrate; then
        log_success "数据库迁移完成"
    else
        log_warning "数据库迁移失败，请检查数据库连接"
    fi
}

# 运行测试
run_tests() {
    if [ "$NODE_ENV" != "production" ]; then
        log_info "运行测试..."
        cd "$APP_DIR"
        
        if npm test; then
            log_success "测试通过"
        else
            log_error "测试失败，部署中止"
            exit 1
        fi
    fi
}

# 停止现有服务
stop_service() {
    log_info "停止现有服务..."
    
    if [ "$USE_PM2" = true ]; then
        if pm2 list | grep -q "$PM2_APP_NAME"; then
            pm2 stop "$PM2_APP_NAME"
            log_success "PM2 服务已停止"
        fi
    else
        # 查找并停止 Node.js 进程
        PID=$(lsof -ti:$PORT)
        if [ ! -z "$PID" ]; then
            kill -TERM $PID
            sleep 2
            if kill -0 $PID 2>/dev/null; then
                kill -KILL $PID
            fi
            log_success "Node.js 进程已停止"
        fi
    fi
}

# 启动服务
start_service() {
    log_info "启动服务..."
    cd "$APP_DIR"
    
    if [ "$USE_PM2" = true ]; then
        # 使用 PM2 启动
        if pm2 list | grep -q "$PM2_APP_NAME"; then
            pm2 restart "$PM2_APP_NAME"
        else
            pm2 start src/app.js --name "$PM2_APP_NAME" --env "$NODE_ENV"
        fi
        pm2 save
        log_success "PM2 服务已启动"
    else
        # 直接启动 (后台运行)
        nohup npm start > logs/app.log 2>&1 &
        echo $! > app.pid
        log_success "Node.js 服务已启动"
    fi
    
    # 等待服务启动
    sleep 3
    
    # 健康检查
    if curl -f http://localhost:$PORT/health > /dev/null 2>&1; then
        log_success "服务健康检查通过"
    else
        log_error "服务启动失败，请检查日志"
        exit 1
    fi
}

# 清理函数
cleanup() {
    log_info "清理临时文件..."
    # 这里可以添加清理逻辑
}

# 显示帮助信息
show_help() {
    echo "WarpBean Backend 部署脚本"
    echo ""
    echo "用法: $0 [选项]"
    echo ""
    echo "选项:"
    echo "  --clean          清理 node_modules 后重新安装"
    echo "  --skip-tests     跳过测试"
    echo "  --skip-migration 跳过数据库迁移"
    echo "  --skip-git       跳过Git代码拉取"
    echo "  --no-db          不使用数据库：跳过数据库检查和迁移"
    echo "  --backup         部署前备份当前版本"
    echo "  --check-env      仅检查环境配置"
    echo "  --help           显示此帮助信息"
    echo ""
    echo "环境变量:"
    echo "  NODE_ENV         运行环境 (development/production)"
    echo "  PORT             服务端口 (默认: 3000)"
    echo "  DB_DISABLED      设置为 1 或 true 时禁用数据库相关步骤"
    echo ""
}

# 主函数
main() {
    local CLEAN_INSTALL=false
    local SKIP_TESTS=false
    local SKIP_MIGRATION=false
    local SKIP_GIT=false
    local DO_BACKUP=false
    local CHECK_ENV_ONLY=false
    
    # 解析命令行参数
    while [[ $# -gt 0 ]]; do
        case $1 in
            --clean)
                CLEAN_INSTALL=true
                shift
                ;;
            --skip-tests)
                SKIP_TESTS=true
                shift
                ;;
            --skip-migration)
                SKIP_MIGRATION=true
                shift
                ;;
            --skip-git)
                SKIP_GIT=true
                shift
                ;;
            --no-db)
                DB_DISABLED=true
                SKIP_MIGRATION=true
                shift
                ;;
            --backup)
                DO_BACKUP=true
                shift
                ;;
            --check-env)
                CHECK_ENV_ONLY=true
                shift
                ;;
            --help)
                show_help
                exit 0
                ;;
            *)
                log_error "未知参数: $1"
                show_help
                exit 1
                ;;
        esac
    done
    
    # 如果只是检查环境配置
    if [ "$CHECK_ENV_ONLY" = true ]; then
        log_info "检查环境配置..."
        check_environment
        check_env_file
        log_success "环境配置检查完成！"
        exit 0
    fi
    
    log_info "开始部署 $APP_NAME..."
    log_info "环境: $NODE_ENV"
    log_info "端口: $PORT"
    
    # 执行部署步骤
    check_environment
    
    if [ "$DO_BACKUP" = true ]; then
        backup_current
    fi
    
    if [ "$SKIP_GIT" = false ]; then
        pull_latest_code
    fi
    
    check_env_file
    
    if [ "$CLEAN_INSTALL" = true ]; then
        install_dependencies --clean
    else
        install_dependencies
    fi
    
    if [ "$SKIP_MIGRATION" = false ]; then
        run_migration
    fi
    
    if [ "$SKIP_TESTS" = false ]; then
        run_tests
    fi
    
    stop_service
    start_service
    cleanup
    
    log_success "部署完成！"
    log_info "服务地址: http://localhost:$PORT"
    log_info "健康检查: http://localhost:$PORT/health"
    
    if [ "$USE_PM2" = true ]; then
        log_info "查看日志: pm2 logs $PM2_APP_NAME"
        log_info "监控服务: pm2 monit"
    else
        log_info "查看日志: tail -f logs/app.log"
        log_info "停止服务: kill \$(cat app.pid)"
    fi
}

# 捕获退出信号
trap cleanup EXIT

# 执行主函数
main "$@"