#!/bin/bash

set -e

echo "🔧 正在优化 SSH 登录速度..."

# 1. 修改 /etc/ssh/sshd_config
SSHD_CONFIG="/etc/ssh/sshd_config"
SSHD_BAK="${SSHD_CONFIG}.bak.$(date +%Y%m%d%H%M%S)"
echo "📦 备份 $SSHD_CONFIG 到 $SSHD_BAK"
cp "$SSHD_CONFIG" "$SSHD_BAK"

update_sshd_config() {
    local key="$1"
    local value="$2"
    if grep -q "^#\?\s*${key}" "$SSHD_CONFIG"; then
        sed -i "s/^#\?\s*${key}.*/${key} ${value}/" "$SSHD_CONFIG"
    else
        echo "${key} ${value}" >> "$SSHD_CONFIG"
    fi
}

echo "✅ 更新 sshd_config 配置..."
update_sshd_config "UseDNS" "no"
update_sshd_config "GSSAPIAuthentication" "no"
update_sshd_config "IgnoreRhosts" "yes"

# 2. 修改 /etc/nsswitch.conf
NSSWITCH_CONF="/etc/nsswitch.conf"
NSSWITCH_BAK="${NSSWITCH_CONF}.bak.$(date +%Y%m%d%H%M%S)"
echo "📦 备份 $NSSWITCH_CONF 到 $NSSWITCH_BAK"
cp "$NSSWITCH_CONF" "$NSSWITCH_BAK"

echo "✅ 修改 hosts 行为，仅保留 files（如有需要保留 DNS，请手动修改）"
sed -i 's/^hosts:.*/hosts: files/' "$NSSWITCH_CONF"

# 3. 重启 SSH 服务
echo "🔁 重启 SSH 服务..."
if command -v systemctl >/dev/null && pgrep systemd >/dev/null; then
    systemctl restart sshd && echo "✅ SSH 服务已通过 systemctl 重启"
elif command -v service >/dev/null; then
    service ssh restart || service sshd restart && echo "✅ SSH 服务已通过 service 重启"
else
    echo "⚠️ 无法自动重启 SSH 服务，请手动执行以下命令之一："
    echo "    sudo systemctl restart sshd"
    echo "    sudo service ssh restart"
fi

echo "🎉 SSH 登录优化完成！"
