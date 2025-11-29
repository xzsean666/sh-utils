# SSH-Copy - 高级文件传输工具

智能 SSH 文件传输工具，支持自动压缩、分割、断点续传和远程自动解压。

## 🚀 快速开始

```bash
# 传输目录（自动压缩）
./ssh-copy.sh --input /data/myproject --output /remote/path/ --ssh "user@host"
# 返回: task_20251016_143052_a1b2c3d4

# 查看状态
./ssh-copy.sh --status task_20251016_143052_a1b2c3d4

# 查看日志
./ssh-copy.sh --logs task_20251016_143052_a1b2c3d4

# 列出所有任务
./ssh-copy.sh --list
```

## ✨ 核心特性

| 功能            | 说明                                  |
| --------------- | ------------------------------------- |
| 🗜️ **自动压缩** | 目录自动压缩，使用一半CPU核心并行压缩 |
| ✂️ **智能分割** | 超过500MB自动分割，支持超大文件传输   |
| 🔄 **断点续传** | 使用rsync，传输中断可从断点继续       |
| 📦 **自动解压** | 远程端自动合并、验证和解压            |
| 🔐 **校验验证** | MD5校验确保文件完整性                 |
| 📊 **实时监控** | tmux后台运行，可随时查看进度          |

## 📦 工作流程

```
输入目录
  → 并行压缩 (使用50%的CPU核心)
  → 检查大小 (>500MB则分割)
  → rsync传输 (支持断点续传)
  → 远程合并
  → 自动解压
  → 清理临时文件
  → 完成 ✓
```

## 📋 系统要求

### 自动安装（推荐）

脚本会自动检测并安装缺失的依赖：

```bash
# 使用 --auto-install 参数自动安装所有依赖
./ssh-copy.sh --input /data --output /remote --ssh "user@host" --auto-install
```

支持的操作系统：

- ✅ Ubuntu/Debian
- ✅ CentOS/RHEL/Rocky/AlmaLinux
- ✅ Fedora
- ✅ Arch/Manjaro
- ✅ macOS (需要Homebrew)

### 手动安装

```bash
# Ubuntu/Debian
sudo apt-get install tmux rsync tar coreutils openssl

# CentOS/RHEL/Rocky/AlmaLinux
sudo yum install tmux rsync tar coreutils openssl

# Arch/Manjaro
sudo pacman -S tmux rsync tar coreutils openssl

# macOS
brew install tmux rsync coreutils openssl

# 推荐：安装多线程压缩工具（加速3-8倍）
# Ubuntu/Debian
sudo apt-get install pigz

# CentOS/RHEL
sudo yum install pigz

# macOS
brew install pigz
```

## 💡 使用示例

### 传输大目录

```bash
./ssh-copy.sh \
  --input /var/www/mysite \
  --output /backup/ \
  --ssh "user@192.168.1.100"
```

**自动执行：**

- ✓ 检测到目录，使用8核心压缩
- ✓ 压缩后2.3GB，分割成5个块
- ✓ 使用rsync传输，显示进度
- ✓ 远程合并和解压
- ✓ 返回任务ID

### 使用SSH密钥

```bash
./ssh-copy.sh \
  --input /data/backup.tar.gz \
  --output /restore/ \
  --ssh "ssh -i ~/.ssh/id_rsa -p 2222 user@host"
```

### 监控任务

```bash
# 查看状态
./ssh-copy.sh --status <task_id>

# 实时日志
./ssh-copy.sh --logs <task_id>

# 附加到会话
tmux attach -t ssh-copy-<task_id>
```

## ⚙️ 配置

脚本顶部可修改：

```bash
SPLIT_SIZE="500M"              # 分割阈值
COMPRESS_THREADS=$((CPU/2))    # 压缩线程数
```

## 🎯 性能优化

### CPU核心使用

- 16核系统 → 使用8核压缩
- 8核系统 → 使用4核压缩
- 4核系统 → 使用2核压缩

### 压缩工具

1. **pigz** (推荐) - 多线程gzip，速度快3-8倍
2. **pbzip2** - 多线程bzip2，压缩率更高
3. **gzip** - 单线程，兜底方案

### 传输优化

- ✓ rsync增量传输
- ✓ 支持断点续传
- ✓ 实时进度显示
- ✓ 自动重试机制

## 📊 传输日志示例

```
==========================================
Advanced SSH File Transfer
==========================================
Task ID:     task_20251016_143052_a1b2c3d4
Source:      /data/myproject
Destination: user@host:/var/www/html/
Compression: Yes (8 threads)
Split:       Yes (500M chunks)
==========================================

[1/5] Compressing directory...
Using 8 CPU cores for compression
Compressed size: 2.3G
✓ Compression completed

[2/5] Splitting file into chunks...
Split into 5 parts
✓ Splitting completed

[3/5] Preparing remote destination...
✓ Remote preparation completed

[4/5] Transferring files...
  part.00  2.3G 100%  125MB/s
  part.01  2.3G 100%  126MB/s
  part.02  2.3G 100%  124MB/s
  part.03  2.3G 100%  127MB/s
  part.04  1.8G 100%  125MB/s
✓ Transfer completed

[5/5] Extracting on remote server...
Merging split files...
Verifying checksum... ✓
Extracting archive...
✓ Remote extraction completed

==========================================
✓ Transfer completed successfully!
==========================================
```

## 🔍 命令参考

```bash
# 传输模式
./ssh-copy.sh --input <源> --output <目标> --ssh <连接字符串>

# 状态查询
./ssh-copy.sh --status <task_id>

# 日志查看
./ssh-copy.sh --logs <task_id>

# 列出所有任务
./ssh-copy.sh --list

# 帮助信息
./ssh-copy.sh --help
```

## 🛠️ 故障排查

### 传输中断

```bash
# 重新运行相同命令，rsync会从断点继续
./ssh-copy.sh --input <same> --output <same> --ssh <same>
```

### 查看实时进度

```bash
# 方法1：查看日志
./ssh-copy.sh --logs <task_id>

# 方法2：附加会话
tmux attach -t ssh-copy-<task_id>
# 按Ctrl+B然后D分离
```

### 压缩很慢

```bash
# 安装pigz加速（推荐）
sudo apt-get install pigz

# 检查是否已安装
which pigz
```

## 📈 使用场景

- ✅ 传输大型项目目录到服务器
- ✅ 备份和恢复数据库
- ✅ 跨服务器迁移网站
- ✅ 部署大型应用
- ✅ 传输超大文件（>10GB）
- ✅ 不稳定网络环境下的可靠传输

## 🔐 安全建议

1. 使用SSH密钥认证
2. 指定非标准SSH端口
3. 定期检查传输日志
4. 验证远程文件完整性

## 📚 更多文档

- [完整使用指南](./SSH-COPY-ADVANCED-GUIDE.md) - 详细功能说明和高级用法
- [使用示例](./ssh-copy-example.sh) - 运行查看各种使用场景

## 🎓 快速参考

```bash
# 一行命令传输
task_id=$(./ssh-copy.sh --input /data --output /backup --ssh "user@host")

# 等待完成（可选）
while ./ssh-copy.sh --status $task_id | grep -q "Running"; do
  sleep 10
done

# 检查结果
./ssh-copy.sh --status $task_id
```

## ⚠️ 注意事项

1. 确保远程有足够磁盘空间（至少2倍源文件大小）
2. 大文件压缩需要时间和CPU资源
3. 临时文件存储在 `/tmp`，重启后丢失
4. 首次使用建议用小文件测试

## 📞 获取帮助

```bash
# 查看帮助
./ssh-copy.sh --help

# 查看示例
./ssh-copy-example.sh

# 查看任务日志
./ssh-copy.sh --logs <task_id>
```
