#!/bin/bash

WEBHOOK_URL="https://hooks.slack.com/services/XXX/YYY/ZZZ"
CPU_THRESHOLD=90
MEM_THRESHOLD=85
CHECK_INTERVAL=10  # 秒
TRIGGER_COUNT=3
COOLDOWN=600  # 秒

cpu_alert_count=0
mem_alert_count=0
last_alert_time=0

while true; do
  CPU_USAGE=$(top -bn1 | grep "Cpu(s)" | awk '{print 100 - $8}')
  MEM_USAGE=$(free | awk '/Mem/{printf "%.0f", $3/$2 * 100}')
  NOW=$(date +%s)

  # CPU 检查
  if (( $(echo "$CPU_USAGE > $CPU_THRESHOLD" | bc -l) )); then
    ((cpu_alert_count++))
  else
    cpu_alert_count=0
  fi

  # MEM 检查
  if (( MEM_USAGE > MEM_THRESHOLD )); then
    ((mem_alert_count++))
  else
    mem_alert_count=0
  fi

  # 是否推送
  if (( cpu_alert_count >= TRIGGER_COUNT || mem_alert_count >= TRIGGER_COUNT )); then
    if (( NOW - last_alert_time > COOLDOWN )); then
      curl -X POST -H 'Content-type: application/json' --data "{
        \"text\": \"🚨 *资源超载警报*\n主机: $(hostname)\n时间: $(date '+%F %T')\nCPU: ${CPU_USAGE}%\n内存: ${MEM_USAGE}%\"
      }" $WEBHOOK_URL
      last_alert_time=$NOW
    fi
    cpu_alert_count=0
    mem_alert_count=0
  fi

  sleep $CHECK_INTERVAL
done
