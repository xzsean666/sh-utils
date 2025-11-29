#!/bin/bash

# SSH-Copy 使用示例

# 示例1：传输目录（自动压缩）
echo "示例1：传输目录到远程服务器"
echo "命令："
echo "./ssh-copy.sh --input /data/myproject --output /var/www/html/ --ssh 'user@192.168.1.100'"
echo ""
echo "发生的事情："
echo "1. 检测到输入是目录"
echo "2. 使用一半CPU核心并行压缩（例如：8核中的4核）"
echo "3. 如果压缩后 > 500MB，自动分割成多个块"
echo "4. 使用 rsync 传输（支持断点续传）"
echo "5. 远程端自动合并、验证和解压"
echo "6. 返回任务ID: task_20251016_143052_a1b2c3d4"
echo ""
echo "----------------------------------------"
echo ""

# 示例2：传输大文件（自动分割）
echo "示例2：传输10GB的大文件"
echo "命令："
echo "./ssh-copy.sh --input /data/backup-10GB.tar.gz --output /backup/ --ssh 'user@host'"
echo ""
echo "发生的事情："
echo "1. 检测文件大小超过500MB"
echo "2. 自动分割成20个500MB的块"
echo "3. 生成MD5校验和"
echo "4. 逐个传输所有块"
echo "5. 远程端自动合并并验证完整性"
echo ""
echo "----------------------------------------"
echo ""

# 示例3：使用SSH密钥和自定义端口
echo "示例3：使用SSH密钥和自定义端口"
echo "命令："
echo "./ssh-copy.sh --input /data/project --output /deploy/ --ssh 'ssh -i ~/.ssh/deploy_key -p 2222 user@host'"
echo ""
echo "----------------------------------------"
echo ""

# 示例4：查看任务状态
echo "示例4：查看任务状态"
echo "命令："
echo "./ssh-copy.sh --status task_20251016_143052_a1b2c3d4"
echo ""
echo "输出："
echo "Source:      /data/myproject"
echo "Destination: user@192.168.1.100:/var/www/html/"
echo "Compression: Yes (8 threads)"
echo "Split:       Yes (500M chunks)"
echo "Status:      Running / Completed / Failed"
echo ""
echo "----------------------------------------"
echo ""

# 示例5：查看传输日志
echo "示例5：查看实时传输日志"
echo "命令："
echo "./ssh-copy.sh --logs task_20251016_143052_a1b2c3d4"
echo ""
echo "----------------------------------------"
echo ""

# 示例6：列出所有任务
echo "示例6：列出所有任务"
echo "命令："
echo "./ssh-copy.sh --list"
echo ""
echo "----------------------------------------"
echo ""

# 示例7：附加到运行中的会话
echo "示例7：实时查看传输进度"
echo "命令："
echo "tmux attach -t ssh-copy-task_20251016_143052_a1b2c3d4"
echo ""
echo "提示：按 Ctrl+B 然后 D 可以分离会话"
echo ""
echo "----------------------------------------"
echo ""

# 实际使用模板
echo "=== 快速使用模板 ==="
echo ""
echo "1. 基本使用："
echo "   task_id=\$(./ssh-copy.sh --input <源路径> --output <目标路径> --ssh 'user@host')"
echo "   echo \"任务ID: \$task_id\""
echo ""
echo "2. 检查状态："
echo "   ./ssh-copy.sh --status \$task_id"
echo ""
echo "3. 查看日志："
echo "   ./ssh-copy.sh --logs \$task_id"
echo ""
echo "4. 实时监控："
echo "   tmux attach -t ssh-copy-\$task_id"
echo ""

# CPU核心和压缩信息
echo "=== 系统信息 ==="
cpu_cores=$(nproc 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null || echo "未知")
compress_threads=$((cpu_cores / 2))
[ "$compress_threads" -lt 1 ] && compress_threads=1

echo "CPU核心数: $cpu_cores"
echo "用于压缩的线程数: $compress_threads"
echo ""

if command -v pigz &> /dev/null; then
    echo "✓ pigz 已安装（多线程压缩）"
elif command -v pbzip2 &> /dev/null; then
    echo "✓ pbzip2 已安装（多线程压缩）"
else
    echo "⚠ 建议安装 pigz 以获得更快的压缩速度"
    echo "  Ubuntu/Debian: sudo apt-get install pigz"
    echo "  CentOS/RHEL:   sudo yum install pigz"
    echo "  macOS:         brew install pigz"
fi

if command -v rsync &> /dev/null; then
    echo "✓ rsync 已安装（支持断点续传）"
else
    echo "✗ rsync 未安装（必需）"
    echo "  Ubuntu/Debian: sudo apt-get install rsync"
    echo "  CentOS/RHEL:   sudo yum install rsync"
fi

if command -v tmux &> /dev/null; then
    echo "✓ tmux 已安装（后台任务管理）"
else
    echo "✗ tmux 未安装（必需）"
    echo "  Ubuntu/Debian: sudo apt-get install tmux"
    echo "  CentOS/RHEL:   sudo yum install tmux"
    echo "  macOS:         brew install tmux"
fi

