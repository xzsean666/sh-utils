#!/bin/bash

# GitHub 更新检查脚本 - 支持私有仓库

# 获取 GitHub Token 和更新后操作脚本相关参数

# 如果环境变量中没有 GITHUB_TOKEN，尝试从当前目录的 .env 中加载
if [ -z "$GITHUB_TOKEN" ] && [ -f ".env" ]; then
    set -a
    # shellcheck disable=SC1091
    . ./.env
    set +a
fi

if [ -n "$GITHUB_TOKEN" ]; then
    TOKEN="$GITHUB_TOKEN"
elif [ -n "$1" ] && [[ "$1" != /* ]]; then
    TOKEN="$1"
    shift  # 移除第一个参数
else
    TOKEN=""
fi

# 所有剩余的参数都将作为更新命令字符串
if [ $# -gt 0 ]; then
    POST_UPDATE_COMMAND="$*"  # 将所有剩余参数组合成一个命令字符串
fi

# 输出时间戳
echo "开始检查更新: $(date '+%Y-%m-%d %H:%M:%S')"

# 配置Git安全设置（防止Docker权限问题）
git config --global --add safe.directory "$(pwd)" 2>/dev/null || true
git config --global --add safe.directory /app 2>/dev/null || true

# 配置Git网络设置（解决HTTP/2问题）
git config --global http.version HTTP/1.1
git config --global http.postBuffer 1048576000
git config --global http.lowSpeedLimit 0
git config --global http.lowSpeedTime 999999

# 检查是否在Git仓库中
if [ ! -d ".git" ]; then
    echo "错误：当前目录不是Git仓库"
    exit 1
fi

# 获取远程仓库 URL
REPO_URL=$(git config --get remote.origin.url)

# 如果有token，配置凭证
if [ -n "$TOKEN" ]; then
    git config credential.helper '!f() { echo "username=oauth2"; echo "password='$TOKEN'"; }; f'
fi

# 获取当前分支名
BRANCH=$(git rev-parse --abbrev-ref HEAD)

# 保存当前的 commit hash
CURRENT_HASH=$(git rev-parse HEAD)

# 获取远程更新
git fetch origin "$BRANCH"

# 获取最新的 commit hash
LATEST_HASH=$(git rev-parse origin/"$BRANCH")

# 定义更新后执行的函数
post_update_actions() {
    echo -e "\n开始执行更新后的操作..."
    if [ -n "$POST_UPDATE_COMMAND" ]; then
        echo "执行自定义更新命令: $POST_UPDATE_COMMAND"
        eval "$POST_UPDATE_COMMAND"
    else
        echo "未指定更新后操作命令"
    fi
    echo "更新后操作执行完成"
}

if [ "$CURRENT_HASH" = "$LATEST_HASH" ]; then
    echo "仓库已是最新状态"
else
    echo "发现更新，正在拉取..."
    
    # 检查是否有本地修改
    if [ -n "$(git status --porcelain)" ]; then
        echo "检测到本地修改，正在执行 git stash 保存修改..."
        git stash push -m "自动保存的修改 $(date '+%Y-%m-%d %H:%M:%S')"
        STASHED=true
    else
        STASHED=false
    fi
    
    # 拉取更新
    if git pull origin "$BRANCH"; then
        echo "更新完成！"
        
        # 不再恢复本地修改，仅提示用户
        if [ "$STASHED" = true ]; then
            echo "本地修改已存储在 stash 中，未恢复"
        fi
        
        # 显示更新内容
        echo -e "\n更新内容如下："
        git --no-pager log --oneline "$CURRENT_HASH..$LATEST_HASH"
        
        # 调用更新后的操作函数
        post_update_actions
    else
        echo "更新失败！检测到合并冲突，尝试通过 stash 解决..."
        # 保存任何未提交的更改（包括合并冲突）
        git reset --hard HEAD
        git clean -fd
        
        # 重新尝试拉取更新
        if git pull origin "$BRANCH"; then
            echo "冲突已解决，更新完成！"
            
            # 显示更新内容
            echo -e "\n更新内容如下："
            git --no-pager log --oneline "$CURRENT_HASH..$LATEST_HASH"
            
            # 调用更新后的操作函数
            post_update_actions
        else
            echo "错误：解决冲突后仍然无法更新，可能需要手动干预。"
        fi
    fi
fi

# 清理凭证配置
if [ -n "$TOKEN" ]; then
    git config --unset credential.helper 2>/dev/null || true
fi

echo -e "\n检查完成: $(date '+%Y-%m-%d %H:%M:%S')"
