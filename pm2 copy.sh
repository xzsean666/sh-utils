#!/bin/bash

# Function to check and install pm2
check_and_install_pm2() {
    if ! command -v pm2 &> /dev/null; then
        echo "pm2 未安装。尝试使用 npm 进行全局安装..."
        if command -v npm &> /dev/null; then
            npm install pm2 -g
            if [ $? -ne 0 ]; then
                echo "npm 安装 pm2 失败。尝试使用 yarn..."
                if command -v yarn &> /dev/null; then
                    yarn global add pm2
                    if [ $? -ne 0 ]; then
                        echo "yarn 安装 pm2 失败。尝试使用 pnpm..."
                        if command -v pnpm &> /dev/null; then
                            pnpm install pm2 -g
                            if [ $? -ne 0 ]; then
                                echo "pnpm 安装 pm2 失败。请手动安装 pm2 (npm install -g pm2, yarn global add pm2, 或 pnpm install -g pm2)。"
                                exit 1
                            fi
                        else
                            echo "未找到 pnpm 命令。请手动安装 pm2。"
                            exit 1
                        fi
                    fi
                else
                    echo "未找到 yarn 命令。请手动安装 pm2。"
                    exit 1
                fi
            fi
        else
            echo "未找到 npm 命令。请手动安装 pm2。"
            exit 1
        fi
        # 再次检查是否安装成功
        if ! command -v pm2 &> /dev/null; then
            echo "pm2 安装失败，请手动安装。"
            exit 1
        fi
        echo "pm2 安装成功！"
    fi
}

# Function to read environment variables from .env file
read_env_vars() {
    if [ -f ".env" ]; then
        # Read PORT
        PORT=$(grep "^PORT=" .env 2>/dev/null | cut -d '=' -f2 | tr -d '"' | tr -d "'")
        
        # Read PM2_INSTANCES (for -i parameter)
        PM2_INSTANCES=$(grep "^PM2_INSTANCES=" .env 2>/dev/null | cut -d '=' -f2 | tr -d '"' | tr -d "'")
        
        # Read NODE_ENV
        NODE_ENV=$(grep "^NODE_ENV=" .env 2>/dev/null | cut -d '=' -f2 | tr -d '"' | tr -d "'")
        
        # Read other PM2 related configurations
        PM2_MAX_MEMORY=$(grep "^PM2_MAX_MEMORY=" .env 2>/dev/null | cut -d '=' -f2 | tr -d '"' | tr -d "'")
        PM2_LOG_FILE=$(grep "^PM2_LOG_FILE=" .env 2>/dev/null | cut -d '=' -f2 | tr -d '"' | tr -d "'")
        PM2_ERROR_FILE=$(grep "^PM2_ERROR_FILE=" .env 2>/dev/null | cut -d '=' -f2 | tr -d '"' | tr -d "'")
        PM2_OUT_FILE=$(grep "^PM2_OUT_FILE=" .env 2>/dev/null | cut -d '=' -f2 | tr -d '"' | tr -d "'")
    fi
    
    # Set defaults if not found
    if [ -z "$PORT" ]; then
        PORT="3000"
        echo "未找到 PORT 环境变量，使用默认端口: $PORT"
    fi
    
    if [ -z "$PM2_INSTANCES" ]; then
        PM2_INSTANCES="1"
        echo "未找到 PM2_INSTANCES 环境变量，使用默认实例数: $PM2_INSTANCES"
    fi
    
    if [ -z "$NODE_ENV" ]; then
        NODE_ENV="production"
        echo "未找到 NODE_ENV 环境变量，使用默认环境: $NODE_ENV"
    fi
    
    if [ -z "$PM2_MAX_MEMORY" ]; then
        PM2_MAX_MEMORY="4096M"
    fi
    
    # Validate PORT
    if ! [[ "$PORT" =~ ^[0-9]+$ ]]; then
        echo "错误：无效的端口号 '$PORT'"
        exit 1
    fi
    
    # Validate PM2_INSTANCES
    if ! [[ "$PM2_INSTANCES" =~ ^[0-9]+$|^max$ ]]; then
        echo "错误：无效的 PM2_INSTANCES 值 '$PM2_INSTANCES'，应该是数字或 'max'"
        exit 1
    fi
    
    echo "配置信息："
    echo "  PORT: $PORT"
    echo "  PM2_INSTANCES: $PM2_INSTANCES"
    echo "  NODE_ENV: $NODE_ENV"
    echo "  PM2_MAX_MEMORY: $PM2_MAX_MEMORY"
}

# Function to build PM2 start command
build_pm2_command() {
    local app_name="$1"
    local cmd="pm2 start dist/main.js --name \"$app_name\""
    
    # Add instances parameter (-i)
    cmd="$cmd -i $PM2_INSTANCES"
    
    # Add node arguments
    cmd="$cmd --node-args=\"--max-old-space-size=${PM2_MAX_MEMORY%M}\""
    
    # Add environment variables
    cmd="$cmd --env NODE_ENV=$NODE_ENV,PORT=$PORT"
    
    # Add log files if specified
    if [ -n "$PM2_LOG_FILE" ]; then
        cmd="$cmd --log \"$PM2_LOG_FILE\""
    fi
    
    if [ -n "$PM2_ERROR_FILE" ]; then
        cmd="$cmd --error \"$PM2_ERROR_FILE\""
    fi
    
    if [ -n "$PM2_OUT_FILE" ]; then
        cmd="$cmd --output \"$PM2_OUT_FILE\""
    fi
    
    echo "$cmd"
}

# Check if parameters are provided
if [ $# -eq 0 ]; then
    echo "请提供参数: --start 或 --stop 或 --restart 或 --status"
    echo ""
    echo "用法:"
    echo "  $0 --start    启动应用"
    echo "  $0 --stop     停止应用"
    echo "  $0 --restart  重启应用"
    echo "  $0 --status   查看应用状态"
    echo ""
    echo "支持的 .env 配置:"
    echo "  PORT=3000                    # 应用端口"
    echo "  PM2_INSTANCES=1              # PM2 实例数 (数字或 'max')"
    echo "  NODE_ENV=production          # 运行环境"
    echo "  PM2_MAX_MEMORY=4096M         # 最大内存限制"
    echo "  PM2_LOG_FILE=logs/app.log    # 日志文件路径"
    echo "  PM2_ERROR_FILE=logs/error.log # 错误日志文件路径"
    echo "  PM2_OUT_FILE=logs/out.log    # 输出日志文件路径"
    exit 1
fi

# Get current directory name
CURRENT_DIR=$(pwd)
DIR_NAME=$(basename "$CURRENT_DIR")
APP_NAME_FILE="app.name"

# Read environment variables
read_env_vars

case "$1" in
    --start)
        # Check and install pm2
        check_and_install_pm2

        # Check if port is occupied
        if lsof -i:$PORT > /dev/null 2>&1; then
            echo "端口 $PORT 已被占用，请先停止现有服务或检查是否已有同名 pm2 进程。"
            # Check if the existing process is the one we expect
            if [ -f "$APP_NAME_FILE" ]; then
                 EXISTING_NAME=$(cat "$APP_NAME_FILE")
                 if pm2 list | grep -q "$EXISTING_NAME"; then
                     echo "检测到正在运行的同名 pm2 进程: $EXISTING_NAME"
                     echo "使用 '$0 --stop' 停止现有进程，或使用 '$0 --restart' 重启"
                 fi
            fi
            exit 1
        fi

        # Check if app is already running
        if [ -f "$APP_NAME_FILE" ]; then
            EXISTING_NAME=$(cat "$APP_NAME_FILE")
            if pm2 list | grep -q "$EXISTING_NAME"; then
                echo "应用 $EXISTING_NAME 已在运行中。"
                echo "使用 '$0 --stop' 停止，或使用 '$0 --restart' 重启"
                exit 1
            fi
        fi

        # Run build command
        echo "运行 npm run build..."
        npm run build
        if [ $? -ne 0 ]; then
            echo "构建失败，启动终止。"
            exit 1
        fi
        echo "构建完成。"

        # Check if dist/main.js exists
        if [ ! -f "dist/main.js" ]; then
            echo "错误：找不到 dist/main.js 文件，请确保构建成功。"
            exit 1
        fi

        # Generate dynamic name and save it
        TIMESTAMP=$(date '+%Y%m%d%H%M%S')
        APP_NAME="${DIR_NAME}-${TIMESTAMP}"
        echo "$APP_NAME" > "$APP_NAME_FILE"
        echo "应用名称已记录到 $APP_NAME_FILE: $APP_NAME"

        # Build and execute PM2 command
        PM2_CMD=$(build_pm2_command "$APP_NAME")
        echo "执行命令: $PM2_CMD"
        eval "$PM2_CMD"
        
        if [ $? -eq 0 ]; then
            echo "Nest.js 应用已使用 pm2 启动："
            echo "  名称: $APP_NAME"
            echo "  端口: $PORT"
            echo "  实例数: $PM2_INSTANCES"
            echo "  环境: $NODE_ENV"
            echo ""
            pm2 list
        else
            echo "pm2 启动应用失败。"
            rm "$APP_NAME_FILE" # Clean up name file if start fails
            exit 1
        fi
        ;;

    --stop)
        # Check if name file exists
        if [ ! -f "$APP_NAME_FILE" ]; then
            echo "找不到应用名称文件 ($APP_NAME_FILE)。"
            echo "请手动查找并停止 pm2 进程:"
            echo "  pm2 list"
            echo "  pm2 stop <name|id>"
            echo "  pm2 delete <name|id>"
            exit 1
        fi

        # Read application name from file
        APP_NAME=$(cat "$APP_NAME_FILE")

        # Check if the process exists in pm2 list
        if ! pm2 list | grep -q "$APP_NAME"; then
            echo "警告：pm2 列表中找不到名为 $APP_NAME 的进程。"
            echo "可能已经被手动停止，清理名称文件..."
            rm "$APP_NAME_FILE"
            exit 0
        fi

        # Stop application with pm2
        echo "正在停止 pm2 应用: $APP_NAME..."
        pm2 stop "$APP_NAME"
        pm2 delete "$APP_NAME" # Delete from pm2 list after stopping

        # Remove name file
        rm "$APP_NAME_FILE"
        echo "pm2 应用 $APP_NAME 已停止并从 pm2 列表中移除。"
        ;;

    --restart)
        # Check if name file exists
        if [ ! -f "$APP_NAME_FILE" ]; then
            echo "找不到应用名称文件 ($APP_NAME_FILE)。无法确定要重启哪个 pm2 进程。"
            echo "请使用 '$0 --start' 启动新的应用实例。"
            exit 1
        fi

        # Read application name from file
        APP_NAME=$(cat "$APP_NAME_FILE")

        # Check if the process is still in the pm2 list
        if ! pm2 list | grep -q "$APP_NAME"; then
             echo "pm2 列表中找不到名为 $APP_NAME 的进程。"
             echo "应用可能已被手动停止，请使用 '$0 --start' 重新启动。"
             rm "$APP_NAME_FILE"
             exit 1
        fi

        # Run build command
        echo "运行 npm run build..."
        npm run build
        if [ $? -ne 0 ]; then
            echo "构建失败，重启终止。"
            exit 1
        fi
        echo "构建完成。"

        # Check if dist/main.js exists
        if [ ! -f "dist/main.js" ]; then
            echo "错误：找不到 dist/main.js 文件，请确保构建成功。"
            exit 1
        fi

        # Restart application with pm2
        echo "正在重启 pm2 应用: $APP_NAME..."
        pm2 restart "$APP_NAME" --update-env

        if [ $? -eq 0 ]; then
            echo "pm2 应用 $APP_NAME 已重启。"
            echo ""
            pm2 list
        else
            echo "pm2 重启应用失败。"
            exit 1
        fi
        ;;

    --status)
        if [ -f "$APP_NAME_FILE" ]; then
            APP_NAME=$(cat "$APP_NAME_FILE")
            echo "当前应用名称: $APP_NAME"
            echo ""
            if pm2 list | grep -q "$APP_NAME"; then
                echo "应用状态:"
                pm2 show "$APP_NAME"
            else
                echo "应用未在 pm2 中运行。"
            fi
        else
            echo "未找到应用名称文件，可能没有通过此脚本启动的应用。"
            echo ""
            echo "所有 pm2 进程:"
            pm2 list
        fi
        ;;

    *)
        echo "无效的参数。请使用 --start 或 --stop 或 --restart 或 --status"
        exit 1
        ;;
esac