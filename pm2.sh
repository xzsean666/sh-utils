#!/bin/bash

set -e

# -----------------------------
# 全局变量
# -----------------------------
CURRENT_DIR=$(pwd)
DIR_NAME=$(basename "$CURRENT_DIR")
APP_NAME_FILE="app.name"
APP_PATH="dist/main.js"
BUILD_FLAG=false
COMMAND=""

# -----------------------------
# 安全读取 .env 文件
# -----------------------------
read_env_vars() {
    if [ -f ".env" ]; then
        echo "正在读取 .env 配置..."
        # 安全地读取环境变量，避免代码注入
        while IFS='=' read -r key value; do
            # 跳过注释和空行
            [[ $key =~ ^[[:space:]]*# ]] && continue
            [[ -z $key ]] && continue
            
            # 去除引号和空格
            key=$(echo "$key" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
            value=$(echo "$value" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//;s/^"\(.*\)"$/\1/;s/^'"'"'\(.*\)'"'"'$/\1/')
            
            # 导出有效的环境变量
            if [[ $key =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]]; then
                export "$key"="$value"
            fi
        done < .env
    fi
    
    # 设置默认值
    export PORT="${PORT:-3000}"
    export PM2_INSTANCES="${PM2_INSTANCES:-1}"
    export NODE_ENV="${NODE_ENV:-production}"
    export PM2_MAX_MEMORY="${PM2_MAX_MEMORY:-4096M}"
    export PM2_LOG_FILE="${PM2_LOG_FILE:-}"
    export PM2_ERROR_FILE="${PM2_ERROR_FILE:-}"
    export PM2_OUT_FILE="${PM2_OUT_FILE:-}"
    
    # 验证配置
    [[ "$PORT" =~ ^[0-9]+$ ]] || { echo "❌ 错误：无效的端口号 '$PORT'"; exit 1; }
    [[ "$PM2_INSTANCES" =~ ^([0-9]+|max)$ ]] || { echo "❌ 错误：无效的 PM2_INSTANCES 值 '$PM2_INSTANCES'"; exit 1; }
    
    echo "✅ 配置加载完成："
    echo "   PORT: $PORT"
    echo "   PM2_INSTANCES: $PM2_INSTANCES" 
    echo "   NODE_ENV: $NODE_ENV"
    echo "   PM2_MAX_MEMORY: $PM2_MAX_MEMORY"
}

# -----------------------------
# 检查并安装 pm2
# -----------------------------
check_and_install_pm2() {
    if ! command -v pm2 &> /dev/null; then
        echo "🔧 pm2 未安装，正在尝试安装..."
        
        # 按优先级尝试安装
        for manager in npm yarn pnpm; do
            if command -v "$manager" &> /dev/null; then
                echo "使用 $manager 安装 pm2..."
                case "$manager" in
                    npm) npm install -g pm2 ;;
                    yarn) yarn global add pm2 ;;
                    pnpm) /usr/local/bin/pnpm install -g pm2 || pnpm install -g pm2 ;;
                esac
                break
            fi
        done
        
        # 验证安装结果
        if ! command -v pm2 &> /dev/null; then
            echo "❌ pm2 安装失败，请手动安装：npm install -g pm2"
            exit 1
        fi
        echo "✅ pm2 安装成功！"
    fi
}

# -----------------------------
# 构建 pm2 启动命令
# -----------------------------
build_pm2_command() {
    local app_name="$1"
    local app_path="$2"
    local cmd=(pm2 start "$app_path" --name "$app_name")

    # 实例模式配置
    if [ "$PM2_INSTANCES" != "1" ]; then
        cmd+=(-i "$PM2_INSTANCES")
        echo "🚀 使用 Cluster 模式 ($PM2_INSTANCES 个实例)"
    else
        echo "🚀 使用 Fork 模式 (单实例)"
    fi

    # Node.js 参数
    cmd+=(--node-args="--max-old-space-size=${PM2_MAX_MEMORY%M}")
    
    # 环境变量
    cmd+=(--env NODE_ENV="$NODE_ENV",PORT="$PORT")
    
    # 日志配置
    [ -n "$PM2_LOG_FILE" ] && cmd+=(--log "$PM2_LOG_FILE")
    [ -n "$PM2_ERROR_FILE" ] && cmd+=(--error "$PM2_ERROR_FILE") 
    [ -n "$PM2_OUT_FILE" ] && cmd+=(--output "$PM2_OUT_FILE")

    echo "${cmd[@]}"
}

# -----------------------------
# 管理 pm2 开机自启
# -----------------------------
manage_pm2_startup() {
    local action="$1"  # save 或 delete
    
    # 确保 pm2 startup 已配置
    if ! pm2 startup | grep -q "PM2 resurrection"; then
        echo "🔧 配置 pm2 开机自启..."
        pm2 startup systemd -u "$(whoami)" --hp "$HOME" 2>/dev/null || {
            echo "⚠️  警告：无法自动配置开机自启，请手动执行以下命令："
            pm2 startup
            return 1
        }
    fi
    
    case "$action" in
        save)
            echo "💾 保存当前 pm2 进程列表到启动配置..."
            pm2 save
            echo "✅ pm2 开机自启已更新"
            ;;
        delete)
            echo "🗑️  清理 pm2 启动配置..."
            pm2 save --force
            echo "✅ pm2 开机自启已清理"
            ;;
    esac
}

# -----------------------------
# 构建项目
# -----------------------------
build_project() {
    echo "🔨 正在构建项目..."
    
    # 检查是否有构建命令
    if [ -f "package.json" ]; then
        if grep -q '"build"' package.json; then
            npm run build
        else
            echo "⚠️  package.json 中未找到 build 脚本"
            return 1
        fi
    else
        echo "❌ 未找到 package.json 文件"
        return 1
    fi
    
    if [ $? -eq 0 ]; then
        echo "✅ 项目构建完成"
    else
        echo "❌ 项目构建失败"
        exit 1
    fi
}

# -----------------------------
# 获取应用名称
# -----------------------------
get_app_name() {
    if [ ! -f "$APP_NAME_FILE" ]; then
        echo "❌ 找不到应用名称文件 ($APP_NAME_FILE)"
        echo "   应用可能未通过此脚本启动"
        return 1
    fi
    cat "$APP_NAME_FILE"
}

# -----------------------------
# 检查端口占用
# -----------------------------
check_port_available() {
    if command -v lsof &> /dev/null && lsof -i:"$PORT" &>/dev/null; then
        echo "❌ 端口 $PORT 已被占用"
        echo "   请先停止现有服务或使用其他端口"
        lsof -i:"$PORT"
        return 1
    fi
}

# -----------------------------
# 解析命令行参数
# -----------------------------
parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --start|--stop|--restart|--status|--logs)
                COMMAND="$1"
                shift
                ;;
            --build)
                BUILD_FLAG=true
                shift
                ;;
            --path)
                if [[ -n "$2" && "$2" != --* ]]; then
                    APP_PATH="$2"
                    shift 2
                else
                    echo "❌ --path 参数需要指定路径值"
                    exit 1
                fi
                ;;
            --help|-h)
                show_help
                exit 0
                ;;
            *)
                echo "❌ 未知参数: $1"
                show_help
                exit 1
                ;;
        esac
    done

    if [ -z "$COMMAND" ]; then
        echo "❌ 请提供操作命令"
        show_help
        exit 1
    fi
}

# -----------------------------
# 显示帮助信息
# -----------------------------
show_help() {
    cat << EOF
🚀 PM2 Nest.js 应用管理脚本

用法:
  $0 [命令] [选项]

命令:
  --start                    启动应用
  --stop                     停止应用并清理启动项
  --restart                  重启应用
  --status                   查看应用状态
  --logs                     查看应用日志

选项:
  --build                    执行构建操作
  --path <文件路径>           指定应用文件路径 (默认: dist/main.js)
  --help, -h                 显示帮助信息

示例:
  $0 --start                              # 启动应用
  $0 --start --build                      # 构建并启动应用
  $0 --start --path src/main.ts           # 启动指定文件
  $0 --restart --build                    # 重新构建并重启
  $0 --stop                               # 停止应用
  $0 --logs                               # 查看日志

支持的 .env 配置:
  PORT=3000                    应用端口
  PM2_INSTANCES=1              PM2 实例数 (数字或 'max')
  NODE_ENV=production          运行环境
  PM2_MAX_MEMORY=4096M         最大内存限制
  PM2_LOG_FILE=logs/app.log    日志文件路径
  PM2_ERROR_FILE=logs/error.log 错误日志文件路径
  PM2_OUT_FILE=logs/out.log    输出日志文件路径
EOF
}

# -----------------------------
# 主逻辑
# -----------------------------
main() {
    parse_arguments "$@"
    read_env_vars
    check_and_install_pm2

    case "$COMMAND" in
        --start)
            echo "🚀 启动应用..."
            
            # 检查是否已有应用在运行
            if [ -f "$APP_NAME_FILE" ]; then
                EXISTING_NAME=$(cat "$APP_NAME_FILE")
                if pm2 list 2>/dev/null | grep -q "$EXISTING_NAME"; then
                    echo "⚠️  应用 $EXISTING_NAME 已在运行"
                    echo "   使用 '$0 --restart' 重启或 '$0 --stop' 停止"
                    exit 1
                else
                    # 清理过期的名称文件
                    rm -f "$APP_NAME_FILE"
                fi
            fi
            
            # 检查端口
            check_port_available || exit 1
            
            # 构建项目
            [ "$BUILD_FLAG" = true ] && build_project
            
            # 检查应用文件
            if [ ! -f "$APP_PATH" ]; then
                echo "❌ 找不到应用文件: $APP_PATH"
                if [ "$BUILD_FLAG" != true ]; then
                    echo "   提示：使用 --build 参数先构建项目"
                fi
                exit 1
            fi

            # 生成应用名称
            TIMESTAMP=$(date '+%Y%m%d%H%M%S')
            APP_NAME="${DIR_NAME}-${TIMESTAMP}"
            echo "$APP_NAME" > "$APP_NAME_FILE"

            # 启动应用
            PM2_CMD=($(build_pm2_command "$APP_NAME" "$APP_PATH"))
            echo "📋 执行命令: ${PM2_CMD[*]}"
            
            if "${PM2_CMD[@]}"; then
                echo ""
                echo "✅ 应用启动成功！"
                echo "   名称: $APP_NAME"
                echo "   文件: $APP_PATH"
                echo "   端口: $PORT"
                echo "   环境: $NODE_ENV"
                echo ""
                pm2 list
                manage_pm2_startup save
            else
                echo "❌ 应用启动失败"
                rm -f "$APP_NAME_FILE"
                exit 1
            fi
            ;;

        --stop)
            echo "🛑 停止应用..."
            
            if ! APP_NAME=$(get_app_name); then
                echo "   尝试查找并停止所有相关进程..."
                pm2 list 2>/dev/null | grep -E "${DIR_NAME}-[0-9]+" | awk '{print $2}' | while read -r name; do
                    [ -n "$name" ] && pm2 delete "$name" 2>/dev/null && echo "   已停止: $name"
                done
                manage_pm2_startup delete
                exit 0
            fi

            if pm2 list 2>/dev/null | grep -q "$APP_NAME"; then
                pm2 stop "$APP_NAME" 2>/dev/null
                pm2 delete "$APP_NAME" 2>/dev/null
                echo "✅ 应用 $APP_NAME 已停止"
            else
                echo "⚠️  应用 $APP_NAME 未在 pm2 中运行"
            fi
            
            rm -f "$APP_NAME_FILE"
            manage_pm2_startup delete
            ;;

        --restart)
            echo "🔄 重启应用..."
            
            if ! APP_NAME=$(get_app_name); then
                echo "   请先使用 '$0 --start' 启动应用"
                exit 1
            fi

            if ! pm2 list 2>/dev/null | grep -q "$APP_NAME"; then
                echo "❌ 应用 $APP_NAME 未在 pm2 中运行"
                echo "   请使用 '$0 --start' 重新启动"
                rm -f "$APP_NAME_FILE"
                exit 1
            fi

            # 构建项目
            [ "$BUILD_FLAG" = true ] && build_project
            
            # 检查应用文件
            if [ ! -f "$APP_PATH" ]; then
                echo "❌ 找不到应用文件: $APP_PATH"
                if [ "$BUILD_FLAG" != true ]; then
                    echo "   提示：使用 --build 参数重新构建项目"
                fi
                exit 1
            fi

            if pm2 restart "$APP_NAME" --update-env 2>/dev/null; then
                echo "✅ 应用 $APP_NAME 已重启"
                [ "$BUILD_FLAG" = true ] && echo "   已执行构建"
                echo ""
                pm2 list
                manage_pm2_startup save
            else
                echo "❌ 应用重启失败"
                exit 1
            fi
            ;;

        --status)
            echo "📊 应用状态："
            echo ""
            
            if [ -f "$APP_NAME_FILE" ]; then
                APP_NAME=$(cat "$APP_NAME_FILE")
                echo "当前记录的应用名称: $APP_NAME"
                echo ""
                
                if pm2 list 2>/dev/null | grep -q "$APP_NAME"; then
                    pm2 show "$APP_NAME" 2>/dev/null || pm2 list
                else
                    echo "⚠️  应用 $APP_NAME 未在 pm2 中运行"
                    echo ""
                    echo "所有 pm2 进程："
                    pm2 list
                fi
            else
                echo "未找到应用名称文件"
                echo ""
                echo "所有 pm2 进程："
                pm2 list
            fi
            ;;

        --logs)
            if ! APP_NAME=$(get_app_name 2>/dev/null); then
                echo "📋 显示所有 pm2 日志："
                pm2 logs
            else
                echo "📋 显示 $APP_NAME 的日志："
                pm2 logs "$APP_NAME"
            fi
            ;;

        *)
            echo "❌ 无效的命令: $COMMAND"
            show_help
            exit 1
            ;;
    esac
}

# 执行主函数
main "$@"
