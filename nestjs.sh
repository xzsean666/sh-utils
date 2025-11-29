#!/bin/bash

# 检查并安装 lsof
if ! command -v lsof &> /dev/null; then
    echo "正在安装必要的工具 lsof..."
    apt-get update && apt-get install -y lsof
fi

# 检查是否提供了参数
if [ $# -eq 0 ]; then
    echo "请提供参数: --start 或 --stop 或 --restart"
    exit 1
fi

# 获取当前目录路径
CURRENT_DIR=$(pwd)
DIR_NAME=$(basename "$CURRENT_DIR")

# 获取端口号，如果没有设置则使用默认值 3000
PORT=$(grep "^PORT=" .env 2>/dev/null | cut -d '=' -f2)
if [ -z "$PORT" ]; then
    PORT="3000"
    echo "未找到 PORT 环境变量，使用默认端口: $PORT"
fi

# 检查端口号是否为有效数字
if ! [[ "$PORT" =~ ^[0-9]+$ ]]; then
    echo "错误：无效的端口号 '$PORT'"
    exit 1
fi

# 在脚本开始处添加创建日志目录的代码
if [ ! -d "./logs" ]; then
    mkdir -p ./logs
    echo "创建日志目录 ./logs"
fi

# 添加守护进程函数
monitor_app() {
    local APP_DIR="$1"
    local APP_PID="$2"
    while true; do
        if ! ps -p $APP_PID > /dev/null; then
            echo "$(date '+%Y-%m-%d %H:%M:%S') 检测到应用停止运行，正在重新启动..." >> ./logs/keeper.log
            # 使用 exec -a 来设置进程名称包含目录名
            nohup node dist/main.js --app-dir="$APP_DIR" > ./logs/app.log 2>&1 &
            NEW_PID=$!
            echo $NEW_PID > app.pid
            echo "应用已重新启动，新的进程ID为 $NEW_PID" >> ./logs/keeper.log
            return $NEW_PID
        fi
        sleep 10
    done
}

case "$1" in
    --start)
        # 检查端口是否已被占用
        if lsof -i:$PORT > /dev/null; then
            echo "端口 $PORT 已被占用，请先停止现有服务"
            exit 1
        fi

        # 如果存在旧的日志文件，则进行备份
        if [ -f "./logs/app.log" ]; then
            BACKUP_DATE=$(date '+%Y%m%d_%H%M%S')
            mv ./logs/app.log "./logs/app_${BACKUP_DATE}.log"
            echo "已将原有日志文件备份为 logs/app_${BACKUP_DATE}.log"
        fi

        # 运行构建命令
        npm run build

        # 使用 node 直接启动主文件，添加目录信息作为参数
        nohup node --max-old-space-size=4096 dist/main.js --app-dir="$DIR_NAME:$CURRENT_DIR" > ./logs/app.log 2>&1 &

        # 获取进程ID并保存到文件
        PID=$!
        echo $PID > app.pid

        echo "正在启动 Nest.js 应用..."
        echo "Nest.js 应用已启动,端口为 $PORT，进程ID为 $PID"
        
        # 如果指定了keeper参数，启动守护进程
        if [ "$2" = "--keeper" ]; then
            echo "正在启动守护进程..."
            nohup bash -c "$(declare -f monitor_app); monitor_app \"$DIR_NAME:$CURRENT_DIR\" $PID" > ./logs/keeper.log 2>&1 &
            KEEPER_PID=$!
            echo $KEEPER_PID > keeper.pid
            echo "守护进程已启动，进程ID为 $KEEPER_PID"
        fi
        ;;
    
    --stop)
        # 先停止守护进程（如果存在）
        if [ -f keeper.pid ]; then
            KEEPER_PID=$(cat keeper.pid)
            kill $KEEPER_PID 2>/dev/null
            rm keeper.pid
            echo "守护进程已停止"
        fi

        # 检查 PID 文件是否存在
        if [ ! -f app.pid ]; then
            echo "找不到 app.pid 文件"
            exit 1
        fi

        # 从文件中读取进程ID
        PID=$(cat app.pid)

        # 使用 kill 命令终止进程
        kill $PID 2>/dev/null

        # 确保使用 pkill 来终止所有相关进程
        pkill -f "node dist/main.js"

        # 等待进程完全终止
        sleep 2

        # 再次检查端口是否还在使用
        if lsof -i:"$PORT" > /dev/null 2>&1; then
            echo "警告：端口 $PORT 仍在使用，尝试强制终止进程..."
            kill -9 "$PID" 2>/dev/null
            lsof -t -i:"$PORT" | xargs -r kill -9
        fi
        
        # 删除 PID 文件
        rm app.pid
        echo "Nest.js 应用已关闭"
        ;;
    
    --restart)
        # 先停止应用
        echo "正在重启 Nest.js 应用..."
        
        # 检查是否有守护进程
        KEEPER_MODE=false
        if [ -f keeper.pid ]; then
            KEEPER_MODE=true
        fi
        
        # 先停止守护进程（如果存在）
        if [ -f keeper.pid ]; then
            KEEPER_PID=$(cat keeper.pid)
            kill $KEEPER_PID 2>/dev/null
            rm keeper.pid
            echo "守护进程已停止"
        fi

        # 检查 PID 文件是否存在
        if [ -f app.pid ]; then
            PID=$(cat app.pid)
            kill $PID 2>/dev/null
            pkill -f "node dist/main.js"
            sleep 2
            
            # 再次检查端口是否还在使用
            if lsof -i:"$PORT" > /dev/null 2>&1; then
                echo "警告：端口 $PORT 仍在使用，尝试强制终止进程..."
                kill -9 "$PID" 2>/dev/null
                lsof -t -i:"$PORT" | xargs -r kill -9
            fi
            
            rm app.pid
            echo "Nest.js 应用已停止"
        else
            echo "找不到运行中的应用"
        fi
        
        # 如果存在旧的日志文件，则进行备份
        if [ -f "./logs/app.log" ]; then
            BACKUP_DATE=$(date '+%Y%m%d_%H%M%S')
            mv ./logs/app.log "./logs/app_${BACKUP_DATE}.log"
            echo "已将原有日志文件备份为 logs/app_${BACKUP_DATE}.log"
        fi

        # 运行构建命令
        npm run build

        # 使用 node 直接启动主文件，添加目录信息作为参数
        nohup /usr/local/bin/node --max-old-space-size=4096 dist/main.js --app-dir="$DIR_NAME:$CURRENT_DIR" > ./logs/app.log 2>&1 &

        # 获取进程ID并保存到文件
        PID=$!
        echo $PID > app.pid

        echo "Nest.js 应用已重新启动，端口为 $PORT，进程ID为 $PID"
        
        # 如果之前有keeper或者指定了keeper参数，启动守护进程
        if [ "$KEEPER_MODE" = "true" ] || [ "$2" = "--keeper" ]; then
            echo "正在启动守护进程..."
            nohup bash -c "$(declare -f monitor_app); monitor_app \"$DIR_NAME:$CURRENT_DIR\" $PID" > ./logs/keeper.log 2>&1 &
            KEEPER_PID=$!
            echo $KEEPER_PID > keeper.pid
            echo "守护进程已启动，进程ID为 $KEEPER_PID"
        fi
        ;;
    
    *)
        echo "无效的参数。请使用 --start [--keeper] 或 --stop 或 --restart [--keeper]"
        exit 1
        ;;
esac