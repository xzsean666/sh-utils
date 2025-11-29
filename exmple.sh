#!/bin/bash

TASK_NAME="rpc-monitor-service-Day"

LOG_FILE="/app/command/$TASK_NAME.log"

echo "$(date): 开始执行 $TASK_NAME 脚本" >> $LOG_FILE

cd /app/common/rpc-monitor-service

YARN_PATH="/usr/local/bin/yarn"
NODE_PATH="/usr/local/bin/node"

$NODE_PATH main/src/index.js --type day >> $LOG_FILE 2>&1

echo "$(date): $TASK_NAME 脚本执行完成" >> $LOG_FILE