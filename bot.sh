#!/bin/bash

# Check if command is provided
if [ $# -eq 0 ]; then
    echo "Error: Please provide command parameters"
    echo "Usage: ./bot.sh <command>"
    echo "Example: ./bot.sh 'main/src/index.js --type day --param1 value1'"
    exit 1
fi

COMMAND="$*"  # Get all parameters as one string

# Create lock file name based on command (replace spaces and special chars with underscores)
LOCK_FILE="/tmp/bot_lock_$(echo "$COMMAND" | sed 's/[^a-zA-Z0-9]/_/g').lock"
LOG_FILE="./logs/bot/$(echo "$COMMAND" | sed 's/[^a-zA-Z0-9]/_/g').log"

# Create the log directory if it doesn't exist
mkdir -p "$(dirname "$LOG_FILE")"

# Function to cleanup lock file
cleanup() {
    rm -f "$LOCK_FILE"
    echo "$(date): $COMMAND 脚本清理锁文件" >> "$LOG_FILE"
}

# Set trap to cleanup on script exit or interruption
trap cleanup EXIT INT TERM

# Check if script is already running
if [ -f "$LOCK_FILE" ]; then
    echo "$(date): $COMMAND 脚本正在执行中，跳过本次执行" >> "$LOG_FILE"
    echo "脚本正在执行中，跳过本次执行"
    exit 0
fi

# Create lock file with current PID
echo $$ > "$LOCK_FILE"

echo "$(date): 开始执行 $COMMAND 脚本" >> "$LOG_FILE"

NODE_PATH="/root/.nvm/versions/node/v24.2.0/bin/node"

# Extract the script path and arguments
SCRIPT_PATH=$(echo "$COMMAND" | awk '{print $1}')
SCRIPT_ARGS=$(echo "$COMMAND" | cut -d' ' -f2-)

echo "$(date): NODE_PATH (from script): $(which node)" >> "$LOG_FILE"
echo "$(date): NODE_PATH: $NODE_PATH" >> "$LOG_FILE"
echo "$(date): SCRIPT_PATH: $SCRIPT_PATH" >> "$LOG_FILE"
echo "$(date): SCRIPT_ARGS: $SCRIPT_ARGS" >> "$LOG_FILE"

"$NODE_PATH" "$SCRIPT_PATH" "$SCRIPT_ARGS" >> "$LOG_FILE" 2>&1
EXIT_CODE=$?

echo "$(date): $COMMAND 脚本执行完成，退出码: $EXIT_CODE" >> "$LOG_FILE"

# Exit with the same code as the Node.js process
exit $EXIT_CODE