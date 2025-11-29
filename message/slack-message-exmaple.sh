#!/bin/bash

# 定义 Slack 脚本路径
SLACK_SCRIPT="/home/sean/git/node-utils/src/utils/sh/message/slack-message.sh"

# 设置 Slack Webhook URL（必须）
export SLACK_WEBHOOK_URL="https://hooks.slack.com/services/YOUR/WEBHOOK/URL"

# 设置主机名（可选）
export HOST_NAME="prod-server-01"

# 脚本开始
echo "[$(date)] Task starting..."
$SLACK_SCRIPT "🚀 Task starting..."

# 执行你的任务
if your_command; then
    echo "[$(date)] Task completed successfully"
    $SLACK_SCRIPT "✅ Task completed successfully"
    exit 0
else
    echo "[$(date)] Task failed"
    $SLACK_SCRIPT "❌ Task failed! Please check the logs."
    exit 1
fi