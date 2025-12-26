#!/bin/bash

#############################################################################
# Multi-App Message Sender
# Purpose: Send notifications to multiple platforms (Slack, DingTalk, Feishu) simultaneously.
#
# Usage:
#   export SLACK_WEBHOOK_URL="..."
#   export DING_WEBHOOK_URL="..."
#   export DING_WEBHOOK_SECRET="..." (Optional)
#   export FEISHU_WEBHOOK_URL="..."
#   ./send-message.sh "Your message here"
#
#############################################################################

# ==================== Configuration ====================
# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# ==================== Helper Functions ====================
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
}

urlencode() {
    # Use python3 for robust url encoding if available
    if command -v python3 &> /dev/null; then
        python3 -c "import urllib.parse, sys; print(urllib.parse.quote(sys.argv[1]))" "$1"
    else
        # Simple fallback for basic characters, might not cover all edge cases
        local string="${1}"
        local strlen=${#string}
        local encoded=""
        local pos c o

        for (( pos=0 ; pos<strlen ; pos++ )); do
            c=${string:$pos:1}
            case "$c" in
                [-_.~a-zA-Z0-9] ) o="${c}" ;;
                * )               printf -v o '%%%02x' "'$c"
            esac
            encoded+="${o}"
        done
        echo "${encoded}"
    fi
}

json_escape() {
    # Escape backslashes, quotes, and newlines for JSON
    echo "$1" | sed 's/\\/\\\\/g' | sed 's/"/\\"/g' | sed ':a;N;$!ba;s/\n/\\n/g'
}

# ==================== Main Logic ====================

# Check for background worker flag
if [[ "$1" == "--background-worker" ]]; then
    IS_WORKER=true
    shift
else
    IS_WORKER=false
fi

MESSAGE="$1"

if [ -z "$MESSAGE" ]; then
    log_error "Usage: $0 <message>"
    exit 1
fi

REPEAT_COUNT="${REPEAT_COUNT:-1}"
REPEAT_INTERVAL="${REPEAT_INTERVAL:-10}"

if [ "$IS_WORKER" = false ]; then
    nohup "$0" --background-worker "$MESSAGE" > /dev/null 2>&1 &
    log_info "Task started in background (PID: $!). Repeating $REPEAT_COUNT times."
    exit 0
fi

for ((i=1; i<=REPEAT_COUNT; i++)); do
    # Prepend Hostname if set
    CURRENT_MESSAGE="$MESSAGE"
    if [[ -n "$HOST_NAME" ]]; then
        CURRENT_MESSAGE="[Host: $HOST_NAME] $CURRENT_MESSAGE"
    fi
    
    SAFE_MESSAGE=$(json_escape "$CURRENT_MESSAGE")
    SENT_ANY=false

# --- Slack ---
if [ -n "$SLACK_WEBHOOK_URL" ]; then
    log_info "Sending to Slack..."
    RESPONSE=$(curl -s -X POST -H 'Content-type: application/json' --data "{\"text\": \"$SAFE_MESSAGE\"}" "$SLACK_WEBHOOK_URL")
    if [[ "$RESPONSE" == "ok" ]]; then
        log_info "Slack message sent successfully."
    else
        log_warn "Slack response: $RESPONSE"
    fi
    SENT_ANY=true
fi

# --- DingTalk ---
if [ -n "$DING_WEBHOOK_URL" ]; then
    log_info "Sending to DingTalk..."
    DING_URL="$DING_WEBHOOK_URL"
    
    # Handle Signature if Secret is provided
    if [ -n "$DING_WEBHOOK_SECRET" ]; then
        TIMESTAMP=$(date +%s%3N)
        STRING_TO_SIGN="${TIMESTAMP}\n${DING_WEBHOOK_SECRET}"
        
        # Calculate HMAC-SHA256 signature
        if command -v openssl &> /dev/null; then
            SIGN=$(echo -ne "$STRING_TO_SIGN" | openssl dgst -sha256 -hmac "$DING_WEBHOOK_SECRET" -binary | base64)
            SIGN_ENCODED=$(urlencode "$SIGN")
            DING_URL="${DING_URL}&timestamp=${TIMESTAMP}&sign=${SIGN_ENCODED}"
        else
            log_warn "openssl not found. Skipping DingTalk signature calculation. Message might fail if security settings require it."
        fi
    fi

    RESPONSE=$(curl -s -X POST -H 'Content-type: application/json' \
        --data "{\"msgtype\": \"text\", \"text\": {\"content\": \"$SAFE_MESSAGE\"}}" \
        "$DING_URL")
    
    # Simple check for success (DingTalk returns errcode: 0)
    if echo "$RESPONSE" | grep -q '"errcode":0'; then
        log_info "DingTalk message sent successfully."
    else
        log_warn "DingTalk response: $RESPONSE"
    fi
    SENT_ANY=true
fi

# --- Feishu (Lark) ---
if [ -n "$FEISHU_WEBHOOK_URL" ]; then
    log_info "Sending to Feishu..."
    
    FEISHU_JSON_BODY="{\"msg_type\": \"text\", \"content\": {\"text\": \"$SAFE_MESSAGE\"}}"

    # Handle Signature if Secret is provided
    if [ -n "$FEISHU_WEBHOOK_SECRET" ]; then
        TIMESTAMP=$(date +%s)
        # Feishu signature: HMAC-SHA256(key=timestamp+"\n"+secret, msg="")
        # Note: The key contains a newline.
        
        if command -v python3 &> /dev/null; then
            SIGN=$(python3 -c "
import hmac, hashlib, base64
timestamp = '$TIMESTAMP'
secret = '$FEISHU_WEBHOOK_SECRET'
string_to_sign = '{}\n{}'.format(timestamp, secret)
hmac_code = hmac.new(string_to_sign.encode('utf-8'), b'', digestmod=hashlib.sha256).digest()
print(base64.b64encode(hmac_code).decode('utf-8'))
")
            # Add timestamp and sign to JSON body
            # We need to insert them into the JSON object. 
            # A simple string replacement or reconstruction is easiest here since we control the JSON structure.
            FEISHU_JSON_BODY="{\"timestamp\": \"$TIMESTAMP\", \"sign\": \"$SIGN\", \"msg_type\": \"text\", \"content\": {\"text\": \"$SAFE_MESSAGE\"}}"
        else
             log_warn "python3 not found. Skipping Feishu signature calculation. Message might fail if security settings require it."
        fi
    fi

    RESPONSE=$(curl -s -X POST -H 'Content-type: application/json' \
        --data "$FEISHU_JSON_BODY" \
        "$FEISHU_WEBHOOK_URL")
    
    # Simple check for success (Feishu returns StatusCode: 0 or code: 0)
    if echo "$RESPONSE" | grep -q '"code":0' || echo "$RESPONSE" | grep -q '"StatusCode":0'; then
        log_info "Feishu message sent successfully."
    else
        log_warn "Feishu response: $RESPONSE"
    fi
    SENT_ANY=true
fi

    if [ "$SENT_ANY" = false ]; then
        log_warn "No webhook URLs configured (SLACK_WEBHOOK_URL, DING_WEBHOOK_URL, FEISHU_WEBHOOK_URL). Message not sent."
        exit 1
    fi

    if [ $i -lt $REPEAT_COUNT ]; then
        log_info "Waiting $REPEAT_INTERVAL seconds before next send..."
        sleep "$REPEAT_INTERVAL"
    fi
done
