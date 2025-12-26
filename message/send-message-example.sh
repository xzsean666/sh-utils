#!/bin/bash

# Define the path to the send-message script
# Assuming it's in the same directory or a known location
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SEND_MESSAGE_SCRIPT="$SCRIPT_DIR/send-message.sh"

# Load configuration from .env file if it exists
if [ -f "$SCRIPT_DIR/send-message.env" ]; then
    source "$SCRIPT_DIR/send-message.env"
else
    # Or set environment variables directly here for testing
    export SLACK_WEBHOOK_URL=""
    export DING_WEBHOOK_URL=""
    export DING_WEBHOOK_SECRET=""
    export FEISHU_WEBHOOK_URL=""
    export FEISHU_WEBHOOK_SECRET=""
    export HOST_NAME="test-server"
    export REPEAT_COUNT=1
    export REPEAT_INTERVAL=10
fi

# Check if the script exists
if [ ! -f "$SEND_MESSAGE_SCRIPT" ]; then
    echo "Error: send-message.sh not found at $SEND_MESSAGE_SCRIPT"
    exit 1
fi

# Example 1: Simple notification
echo "Sending start notification..."
"$SEND_MESSAGE_SCRIPT" "🚀 Backup task started..."

# Example 2: Simulate a task
echo "Running task..."
sleep 2

# Simulate success or failure
if [ $? -eq 0 ]; then
    echo "Task completed."
    "$SEND_MESSAGE_SCRIPT" "✅ Backup task completed successfully."
else
    echo "Task failed."
    "$SEND_MESSAGE_SCRIPT" "❌ Backup task failed! Please check logs."
fi
