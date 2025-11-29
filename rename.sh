#!/bin/bash

# 显示使用说明
show_usage() {
    echo "Usage: $0 --type <remove|replace> --search <pattern> [--new <pattern>] [--dir <directory>] [options]"
    echo ""
    echo "Required arguments:"
    echo "  --type <remove|replace>    Specify operation type: 'remove' to delete pattern, 'replace' to substitute"
    echo "  --search <pattern>         Pattern to search for"
    echo ""
    echo "Optional arguments:"
    echo "  --new <pattern>            New pattern to replace with (required for replace type)"
    echo "  --dir <directory>          Target directory (default: current directory)"
    echo "  --recursive                Process subdirectories recursively"
    echo "  --force                    Don't ask for confirmation"
    echo "  --dry-run                  Only show what would be done"
    echo "  --help                     Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0 --type replace --search 'old' --new 'new' --dir /path/to/dir"
    echo "  $0 --type remove --search 'old' --recursive"
    echo "  $0 --type replace --search 'old' --new 'new' --dry-run"
    exit 1
}

# 默认参数
recursive=false
force=false
dry_run=false
directory="."
operation_type=""
search_pattern=""
replace_pattern=""

# 解析命令行参数
while [[ $# -gt 0 ]]; do
    case $1 in
        --help)
            show_usage
            ;;
        --type)
            if [ -n "$2" ]; then
                if [ "$2" = "remove" ] || [ "$2" = "replace" ]; then
                    operation_type="$2"
                else
                    echo "Error: Invalid type. Use 'remove' or 'replace'"
                    exit 1
                fi
                shift 2
            else
                echo "Error: --type requires an argument"
                exit 1
            fi
            ;;
        --search)
            if [ -n "$2" ]; then
                search_pattern="$2"
                shift 2
            else
                echo "Error: --search requires an argument"
                exit 1
            fi
            ;;
        --new)
            if [ -n "$2" ]; then
                replace_pattern="$2"
                shift 2
            else
                echo "Error: --new requires an argument"
                exit 1
            fi
            ;;
        --dir)
            if [ -n "$2" ]; then
                directory="$2"
                shift 2
            else
                echo "Error: --dir requires an argument"
                exit 1
            fi
            ;;
        --recursive)
            recursive=true
            shift
            ;;
        --force)
            force=true
            shift
            ;;
        --dry-run)
            dry_run=true
            shift
            ;;
        *)
            echo "Error: Unknown option: $1"
            show_usage
            ;;
    esac
done

# 验证必需参数
if [ -z "$operation_type" ]; then
    echo "Error: --type is required"
    show_usage
fi

if [ -z "$search_pattern" ]; then
    echo "Error: --search is required"
    show_usage
fi

if [ "$operation_type" = "replace" ] && [ -z "$replace_pattern" ]; then
    echo "Error: --new is required when using --type replace"
    show_usage
fi

# 检查目录是否存在
if [ ! -d "$directory" ]; then
    echo "Error: Directory '$directory' does not exist"
    exit 1
fi

# 如果是remove类型，设置替换为空字符串
if [ "$operation_type" = "remove" ]; then
    replace_pattern=""
fi

# 设置查找命令
if $recursive; then
    find_cmd="find \"$directory\" -type f"
else
    find_cmd="find \"$directory\" -maxdepth 1 -type f"
fi

# 预览更改
echo "Operation type: $operation_type"
echo "Processing directory: $directory"
echo "Preview of changes:"
echo "----------------"
eval $find_cmd | while read -r file; do
    newname=$(echo "$file" | sed "s/${search_pattern}/${replace_pattern}/g")
    if [ "$file" != "$newname" ]; then
        echo "Will rename: $file -> $newname"
    fi
done
echo "----------------"

# 如果是dry-run模式，到此结束
if $dry_run; then
    exit 0
fi

# 询问确认（除非使用force选项）
if ! $force; then
    read -p "Do you want to proceed with renaming? (y/n) " answer
    if [ "$answer" != "y" ] && [ "$answer" != "Y" ]; then
        echo "Operation cancelled."
        exit 0
    fi
fi

# 执行重命名
eval $find_cmd | while read -r file; do
    newname=$(echo "$file" | sed "s/${search_pattern}/${replace_pattern}/g")
    if [ "$file" != "$newname" ]; then
        mv "$file" "$newname"
        echo "Renamed: $file -> $newname"
    fi
done
echo "Renaming completed."