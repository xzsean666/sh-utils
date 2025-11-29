#!/bin/bash

#############################################################################
# Slack Message 高级使用示例
# 展示了在实际脚本中如何集成 Slack 通知
#############################################################################

# ==================== 配置 ====================
# 设置 Slack Webhook URL（必须）
export SLACK_WEBHOOK_URL="https://hooks.slack.com/services/YOUR/WEBHOOK/URL"

# 设置主机名（可选，消息会自动添加主机信息前缀）
export HOST_NAME="$(hostname)"

# 定义 Slack 脚本路径
SLACK_SCRIPT="/home/sean/git/node-utils/src/utils/sh/message/slack-message.sh"

# ==================== 示例 1: 简单通知 ====================
example_simple() {
    echo "Example 1: Simple notification"
    $SLACK_SCRIPT "📝 This is a simple message"
}

# ==================== 示例 2: 带错误处理的任务执行 ====================
example_task_with_error_handling() {
    echo "Example 2: Task with error handling"
    
    $SLACK_SCRIPT "🚀 Starting database backup..."
    
    # 模拟任务执行
    if perform_backup; then
        $SLACK_SCRIPT "✅ Database backup completed successfully"
        return 0
    else
        $SLACK_SCRIPT "❌ Database backup failed! Please check the logs."
        return 1
    fi
}

# 模拟备份函数
perform_backup() {
    # 这里放你的实际备份逻辑
    sleep 1
    return 0
}

# ==================== 示例 3: 多步骤任务进度通知 ====================
example_multi_step_task() {
    echo "Example 3: Multi-step task progress"
    
    $SLACK_SCRIPT "🔄 Starting deployment process..."
    
    # 步骤 1
    echo "Step 1: Building application..."
    if build_app; then
        $SLACK_SCRIPT "✅ Step 1/3: Build completed"
    else
        $SLACK_SCRIPT "❌ Step 1/3: Build failed!"
        return 1
    fi
    
    # 步骤 2
    echo "Step 2: Running tests..."
    if run_tests; then
        $SLACK_SCRIPT "✅ Step 2/3: Tests passed"
    else
        $SLACK_SCRIPT "❌ Step 2/3: Tests failed!"
        return 1
    fi
    
    # 步骤 3
    echo "Step 3: Deploying..."
    if deploy; then
        $SLACK_SCRIPT "🎉 Step 3/3: Deployment completed successfully!"
    else
        $SLACK_SCRIPT "❌ Step 3/3: Deployment failed!"
        return 1
    fi
}

# 模拟函数
build_app() { sleep 1; return 0; }
run_tests() { sleep 1; return 0; }
deploy() { sleep 1; return 0; }

# ==================== 示例 4: 定时任务通知（适合 cron） ====================
example_cron_task() {
    echo "Example 4: Cron task notification"
    
    local start_time=$(date +%s)
    $SLACK_SCRIPT "⏰ Daily report generation started at $(date '+%Y-%m-%d %H:%M:%S')"
    
    # 执行任务
    generate_report
    
    local end_time=$(date +%s)
    local duration=$((end_time - start_time))
    
    $SLACK_SCRIPT "📊 Daily report generated successfully\n⏱️ Duration: ${duration}s"
}

generate_report() {
    sleep 2
}

# ==================== 示例 5: 异常监控通知 ====================
example_monitoring() {
    echo "Example 5: Monitoring and alerting"
    
    # 检查磁盘使用率
    local disk_usage=$(df -h / | tail -1 | awk '{print $5}' | sed 's/%//')
    
    if [ "$disk_usage" -gt 80 ]; then
        $SLACK_SCRIPT "⚠️ WARNING: Disk usage is at ${disk_usage}%!\nPlease check the server."
    fi
    
    # 检查服务状态
    if ! systemctl is-active --quiet nginx; then
        $SLACK_SCRIPT "🔴 CRITICAL: Nginx service is down!"
    fi
}

# ==================== 示例 6: 源入脚本函数的高级用法 ====================
example_sourcing() {
    echo "Example 6: Using sourced functions"
    
    # 源入脚本函数
    source "$SLACK_SCRIPT"
    
    # 现在可以直接调用 send_message 函数
    local webhook="${SLACK_WEBHOOK_URL}"
    send_message "📱 Direct function call example" "$webhook"
}

# ==================== 示例 7: 格式化消息 ====================
example_formatted_message() {
    echo "Example 7: Formatted message"
    
    local version="v1.2.3"
    local commit="abc1234"
    local environment="production"
    
    local message="🚀 *Deployment Summary*
    
*Version:* $version
*Commit:* $commit
*Environment:* $environment
*Time:* $(date '+%Y-%m-%d %H:%M:%S')
*Status:* ✅ Success"
    
    $SLACK_SCRIPT "$message"
}

# ==================== 主函数 ====================
main() {
    # 检查 Webhook URL 是否配置
    if [[ "$SLACK_WEBHOOK_URL" == "https://hooks.slack.com/services/YOUR/WEBHOOK/URL" ]]; then
        echo "ERROR: Please configure SLACK_WEBHOOK_URL before running examples"
        exit 1
    fi
    
    echo "Running Slack Message Examples..."
    echo "=================================="
    echo ""
    
    # 运行各个示例
    # example_simple
    # example_task_with_error_handling
    # example_multi_step_task
    # example_cron_task
    # example_monitoring
    # example_sourcing
    # example_formatted_message
    
    # 取消注释上面的任一行来运行相应的示例
    echo "Please uncomment the example you want to run in the main() function"
}

# 执行主函数
main "$@"


