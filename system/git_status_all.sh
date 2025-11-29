#!/bin/bash

# Git Status All Script
# 功能：遍历指定目录下的所有git项目并执行git status
# 用法：./git_status_all.sh <path>

# 颜色定义
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 显示使用说明
show_usage() {
    echo "用法: $0 <目录路径>"
    echo "示例: $0 /home/user/projects"
    echo "功能: 遍历指定目录下的所有git项目并执行git status"
    exit 1
}

# 检查参数
if [ $# -eq 0 ]; then
    echo -e "${RED}错误：请提供目录路径${NC}"
    show_usage
fi

# 获取目录路径
TARGET_DIR="$1"

# 检查目录是否存在
if [ ! -d "$TARGET_DIR" ]; then
    echo -e "${RED}错误：目录 '$TARGET_DIR' 不存在${NC}"
    exit 1
fi

# 转换为绝对路径
TARGET_DIR=$(realpath "$TARGET_DIR")

echo -e "${BLUE}开始在目录 '$TARGET_DIR' 中查找git项目...${NC}"
echo ""

# 计数器
total_repos=0
clean_repos=0
dirty_repos=0
failed_count=0

# 查找所有包含.git目录的文件夹
while IFS= read -r -d '' git_dir; do
    # 获取项目目录（.git的父目录）
    project_dir=$(dirname "$git_dir")
    project_name=$(basename "$project_dir")
    
    echo -e "${YELLOW}正在处理项目：${NC}$project_name"
    echo -e "${BLUE}路径：${NC}$project_dir"
    
    # 进入项目目录
    cd "$project_dir" || {
        echo -e "${RED}  ✗ 无法进入目录${NC}"
        ((failed_count++))
        echo ""
        continue
    }
    
    # 检查是否有remote (可选，git status不需要remote)
    # if ! git remote >/dev/null 2>&1; then
    #     echo -e "${YELLOW}  ⚠ 没有配置remote，跳过${NC}"
    #     echo ""
    #     continue
    # fi
    
    # 执行git status
    echo "  执行git status..."
    output=$(git status --porcelain 2>/dev/null)
    
    if [ -z "$output" ]; then
        echo -e "${GREEN}  ✓ 仓库干净 (无更改)${NC}"
        ((clean_repos++))
    else
        echo -e "${YELLOW}  ⚠ 仓库不干净 (有更改)${NC}"
        echo "$output" # 显示git status的详细输出
        ((dirty_repos++))
    fi
    
    ((total_repos++))
    echo ""
    
done < <(find "$TARGET_DIR" -name ".git" -type d -print0 2>/dev/null)

# 显示汇总信息
echo -e "${BLUE}========== 执行完成 ==========${NC}"
echo -e "总共找到的git项目: ${BLUE}$total_repos${NC}"
echo -e "干净的仓库: ${GREEN}$clean_repos${NC}"
echo -e "有更改的仓库: ${YELLOW}$dirty_repos${NC}"
echo -e "处理失败的项目: ${RED}$failed_count${NC}"

if [ $dirty_repos -eq 0 ] && [ $failed_count -eq 0 ]; then
    echo -e "${GREEN}所有项目都已检查，并且没有发现未提交的更改！${NC}"
    exit 0
else
    echo -e "${YELLOW}部分项目有未提交的更改或处理失败，请检查上面的信息${NC}"
    exit 1
fi
