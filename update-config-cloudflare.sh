#!/bin/bash

# Exit immediately if a command exits with a non-zero status.
set -e

# 检查 .gitignore 文件中是否包含 'env/'，如果没有则添加
if ! grep -q '^env/$' .gitignore && ! grep -q '^env$' .gitignore; then
    echo "env/" >> .gitignore
    echo "Added env/ to .gitignore"
fi

# 检查 env/config.json 是否存在，如果不存在则创建空的 JSON 数组
if [ ! -f env/config.json ]; then
    echo "[]" > env/config.json
    echo "Created empty env/config.json"
fi

# 读取 env/config.json 文件内容并转换为紧凑的JSON字符串
CONFIG_CONTENT=$(cat env/config.json | tr -d '\n' | tr -d '\t')

# 使用 awk 来更新 wrangler.jsonc 中的 CONFIG 值
# awk 更好地处理JSON字符串的转义
awk -v config="$CONFIG_CONTENT" '
BEGIN {
    found_config = 0
    found_vars = 0
    in_vars = 0
}
/"vars":/ {
    found_vars = 1
    in_vars = 1
    print
    next
}
in_vars && /}/ && !/},$/ {
    in_vars = 0
}
/"CONFIG":/ {
    if (in_vars) {
        found_config = 1
        # 转义JSON字符串中的双引号
        gsub(/"/, "\\\"", config)
        # 找到 CONFIG 行，用新内容替换
        print "\t\t\"CONFIG\": \"" config "\""
        next
    }
}
in_vars && !found_config && /}/ {
    # 如果在 vars 对象中但没有找到 CONFIG，在结束前添加 CONFIG
    gsub(/"/, "\\\"", config)
    print "\t\t\"CONFIG\": \"" config "\""
    found_config = 1
}
{ print }
END {
    # 如果没有找到 vars 对象，需要在文件中添加
    if (!found_vars) {
        print "Warning: No vars object found. You may need to add it manually." > "/dev/stderr"
    }
}
' wrangler.jsonc > wrangler.jsonc.tmp && mv wrangler.jsonc.tmp wrangler.jsonc

echo "✅ CONFIG 环境变量已更新到 wrangler.jsonc"
echo "CONFIG = $CONFIG_CONTENT"

# 检查 worker-configuration.d.ts 文件中 Env 接口是否包含 CONFIG 属性，如果没有则添加
if grep -q 'interface Env {' worker-configuration.d.ts; then
    if ! grep -q 'CONFIG: string;' worker-configuration.d.ts; then
        sed -i '/interface Env {/a\\tCONFIG: string;' worker-configuration.d.ts
        echo "Added CONFIG: string; to Env interface in worker-configuration.d.ts"
    fi
else
    echo "Warning: Could not find 'interface Env {' in worker-configuration.d.ts. Please add CONFIG: string; manually." > "/dev/stderr"
fi