# Slack Message Script

简单的 Slack Webhook 消息发送脚本。

## 安装

1. 获取你的 Slack Webhook URL：
   - 访问 https://api.slack.com/apps
   - 创建或选择现有应用
   - 启用 `Incoming Webhooks`
   - 创建新的 Webhook URL

2. 配置 Webhook URL（三种方式，选其一）：

   **方式一：环境变量（推荐）**
   ```bash
   export SLACK_WEBHOOK_URL="https://hooks.slack.com/services/YOUR/WEBHOOK/URL"
   ```
   
   **方式二：在脚本中配置默认值**
   ```bash
   # 编辑 slack-message.sh，修改 DEFAULT_WEBHOOK_URL
   DEFAULT_WEBHOOK_URL="https://hooks.slack.com/services/YOUR/WEBHOOK/URL"
   ```
   
   **方式三：临时设置（推荐用于测试）**
   ```bash
   SLACK_WEBHOOK_URL="https://hooks.slack.com/services/xxx" ./slack-message.sh "Test message"
   ```

3. 给脚本添加执行权限：
   ```bash
   chmod +x slack-message.sh
   ```

## 使用

### 基础用法
```bash
# 设置环境变量后使用
export SLACK_WEBHOOK_URL="https://hooks.slack.com/services/YOUR/WEBHOOK/URL"
./slack-message.sh "你的消息内容"
```

### 示例

```bash
# 方式 1: 先设置环境变量
export SLACK_WEBHOOK_URL="https://hooks.slack.com/services/xxx"
./slack-message.sh "Server started successfully!"

# 方式 2: 临时设置（适合一次性使用）
SLACK_WEBHOOK_URL="https://hooks.slack.com/services/xxx" ./slack-message.sh "Test message"

# 发送包含特殊字符和换行的消息
./slack-message.sh "🚀 Deployment complete\nVersion: v1.2.3\nStatus: Active"

# 在脚本中使用
MESSAGE="Task completed at $(date)"
./slack-message.sh "$MESSAGE"
```

## 环境变量

- `HOST_NAME`: （可选）主机名，如果设置，消息会自动添加主机信息前缀

例如：
```bash
export HOST_NAME="prod-server-01"
./slack-message.sh "Database backup completed"
```

输出消息：`📍 *Host:* prod-server-01\nDatabase backup completed`

## 在 Cron 任务中使用

```bash
# 在 crontab 中添加（需要先设置环境变量）
SLACK_WEBHOOK_URL=https://hooks.slack.com/services/xxx
0 2 * * * /home/sean/git/node-utils/src/utils/sh/message/slack-message.sh "Daily backup completed"
```

## 在其他脚本中使用

### 方式一：直接调用（推荐）

```bash
#!/bin/bash

# 设置 Webhook URL
export SLACK_WEBHOOK_URL="https://hooks.slack.com/services/YOUR/WEBHOOK/URL"

# 定义脚本路径
SLACK_SCRIPT="/home/sean/git/node-utils/src/utils/sh/message/slack-message.sh"

# 脚本逻辑
echo "Starting task..."
$SLACK_SCRIPT "🚀 Task started"

# 执行任务
if run_your_task; then
    $SLACK_SCRIPT "✅ Task completed successfully"
else
    $SLACK_SCRIPT "❌ Task failed!"
fi
```

### 方式二：源入脚本函数（高级用法）

```bash
#!/bin/bash

# 设置 Webhook URL
export SLACK_WEBHOOK_URL="https://hooks.slack.com/services/YOUR/WEBHOOK/URL"

# 源入脚本函数
source /home/sean/git/node-utils/src/utils/sh/message/slack-message.sh

# 现在可以直接调用 send_message 函数
send_message "Application started" "$SLACK_WEBHOOK_URL"
```

### 完整示例（数据库备份脚本）

```bash
#!/bin/bash

# Slack 配置
export SLACK_WEBHOOK_URL="https://hooks.slack.com/services/YOUR/WEBHOOK/URL"
export HOST_NAME="db-server-01"
SLACK_SCRIPT="/home/sean/git/node-utils/src/utils/sh/message/slack-message.sh"

# 开始备份
$SLACK_SCRIPT "🔄 Database backup starting..."

# 执行备份
if pg_dump mydatabase > backup_$(date +%Y%m%d).sql; then
    $SLACK_SCRIPT "✅ Database backup completed successfully"
    exit 0
else
    $SLACK_SCRIPT "❌ Database backup failed! Please check logs."
    exit 1
fi
```
