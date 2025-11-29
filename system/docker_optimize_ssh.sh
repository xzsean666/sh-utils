#!/bin/bash

set -e

echo "🔧 正在优化 SSH 登录速度..."

# 修改 /etc/ssh/sshd_config
SSHD_CONFIG="/etc/ssh/sshd_config"

backup_file="${SSHD_CONFIG}.bak.$(date +%Y%m%d%H%M%S)"
echo "📦 备份 $SSHD_CONFIG 到 $backup_file"
cp "$SSHD_CONFIG" "$backup_file"

echo "✅ 更新 sshd_config 配置..."

sed -i '/^#\?UseDNS/s/.*/UseDNS no/' "$SSHD_CONFIG" || echo "UseDNS no" >> "$SSHD_CONFIG"
sed -i '/^#\?GSSAPIAuthentication/s/.*/GSSAPIAuthentication no/' "$SSHD_CONFIG" || echo "GSSAPIAuthentication no" >> "$SSHD_CONFIG"
sed -i '/^#\?IgnoreRhosts/s/.*/IgnoreRhosts yes/' "$SSHD_CONFIG" || echo "IgnoreRhosts yes" >> "$SSHD_CONFIG"

# 修改 /etc/nsswitch.conf
NSSWITCH_CONF="/etc/nsswitch.conf"
nsswitch_backup="${NSSWITCH_CONF}.bak.$(date +%Y%m%d%H%M%S)"
echo "📦 备份 $NSSWITCH_CONF 到 $nsswitch_backup"
cp "$NSSWITCH_CONF" "$nsswitch_backup"

echo "✅ 修改 hosts 行为，仅保留 files"
sed -i 's/^hosts:.*/hosts: files/' "$NSSWITCH_CONF"

# 重启 ssh 服务
echo "🔁 重启 ssh 服务..."
if command -v systemctl >/dev/null; then
    systemctl restart sshd
else
    service ssh restart
fi

echo "🎉 SSH 优化完成！"
