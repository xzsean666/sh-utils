# SSH-Copy Advanced Transfer Guide

高级 SSH 文件传输工具，支持自动压缩、文件分割、断点续传和远程自动解压。

## ✨ 核心功能

### 1. **智能自动压缩**

- 检测输入是否为目录，自动进行压缩
- 使用一半 CPU 核心数进行并行压缩（`pigz` 或 `pbzip2`）
- 如果没有并行压缩工具，自动降级到 `gzip`

### 2. **大文件自动分割**

- 超过 500MB 的文件自动分割成多个块
- 每个块独立传输，支持断点续传
- 远程端自动合并和验证校验和

### 3. **断点续传**

- 使用 `rsync` 替代 `scp`，支持断点续传
- 传输中断可以从断点处继续
- 自动显示传输进度

### 4. **远程自动处理**

- 自动在远程端创建接收脚本
- 传输完成后自动合并分割文件
- 自动解压缩到目标目录
- 自动清理临时文件

### 5. **Tmux 后台运行**

- 所有任务在 tmux 会话中后台运行
- 立即返回任务 ID
- 可随时查看状态和日志

## 📋 系统要求

### 本地端

- `tmux` - 后台会话管理
- `rsync` - 文件传输
- `pigz` 或 `pbzip2` (可选) - 并行压缩
- `openssl` - 生成任务 ID

### 远程端

- `bash` - 执行接收脚本
- `rsync` - 接收文件
- `tar` - 解压文件
- `md5sum` - 验证校验和

### 安装依赖

```bash
# Ubuntu/Debian
sudo apt-get install tmux rsync pigz

# CentOS/RHEL
sudo yum install tmux rsync pigz

# macOS
brew install tmux rsync pigz
```

## 🚀 使用示例

### 基本用法：传输目录

```bash
# 自动压缩目录并传输
./ssh-copy.sh \
  --input /path/to/large-directory \
  --output /remote/destination/ \
  --ssh "user@192.168.1.100"

# 输出：task_20251016_143052_a1b2c3d4
```

**发生了什么？**

1. 检测到输入是目录
2. 使用一半 CPU 核心并行压缩（如有 16 核则用 8 核）
3. 如果压缩后超过 500MB，自动分割成多个块
4. 使用 rsync 传输所有文件块（支持断点续传）
5. 远程端自动合并、验证和解压
6. 清理所有临时文件

### 传输大文件

```bash
# 传输超大文件（自动分割）
./ssh-copy.sh \
  --input /data/backup-10GB.tar.gz \
  --output /backup/ \
  --ssh "ssh -i ~/.ssh/id_rsa -p 2222 user@host"

# 大文件会自动分割成 500MB 的块进行传输
```

### 带 SSH 密钥和端口

```bash
./ssh-copy.sh \
  --input /data/project \
  --output /var/www/html/ \
  --ssh "ssh -i ~/.ssh/deploy_key -p 2222 deploy@production.example.com"
```

### 查看任务状态

```bash
# 查看特定任务
./ssh-copy.sh --status task_20251016_143052_a1b2c3d4

# 输出：
# ==========================================
# Task Status: task_20251016_143052_a1b2c3d4
# ==========================================
# Source:      /data/large-directory
# Destination: user@192.168.1.100:/remote/destination/
# SSH Key:     N/A
# Port:        22
# Compression: Yes (8 threads)
# Split:       Yes (500M chunks)
# Created:     2025-10-16 14:30:52
#
# Status: Running
```

### 查看传输日志

```bash
# 实时查看完整日志
./ssh-copy.sh --logs task_20251016_143052_a1b2c3d4

# 输出会显示：
# - 压缩进度和大小
# - 分割信息
# - 每个块的传输进度
# - 远程合并和解压状态
```

### 列出所有任务

```bash
./ssh-copy.sh --list

# 显示所有任务的状态
```

### 附加到运行中的会话

```bash
# 实时查看传输进度
tmux attach -t ssh-copy-task_20251016_143052_a1b2c3d4

# 按 Ctrl+B 然后 D 分离会话
```

## 📊 传输流程详解

### 对于目录输入：

```
[1/5] 压缩目录
  ├─ 检测 CPU 核心数（例如：16 核）
  ├─ 使用一半核心压缩（8 线程 pigz）
  └─ 显示压缩后大小

[2/5] 检查文件大小
  ├─ 如果 > 500MB，分割成多个块
  ├─ 生成 MD5 校验和
  └─ 显示分块数量

[3/5] 准备远程端
  ├─ 创建目标目录
  ├─ 上传接收脚本
  └─ 设置执行权限

[4/5] 传输文件
  ├─ 使用 rsync 传输每个块
  ├─ 显示进度条
  └─ 支持断点续传

[5/5] 远程处理
  ├─ 合并文件块
  ├─ 验证 MD5 校验和
  ├─ 解压到目标目录
  └─ 清理临时文件
```

### 对于大文件输入：

```
[1/5] 跳过压缩（已是单个文件）

[2/5] 分割文件
  └─ 分割成 500MB 块

[3/5] 准备远程端

[4/5] 传输所有块（支持断点续传）

[5/5] 远程合并和清理
```

### 对于小文件输入：

```
[1/5] 跳过压缩
[2/5] 跳过分割（< 500MB）
[3/5] 准备远程端
[4/5] 直接传输（支持断点续传）
[5/5] 清理临时文件
```

## ⚙️ 配置选项

脚本顶部可修改的配置：

```bash
# 文件分割阈值（默认 500MB）
SPLIT_SIZE="500M"

# CPU 核心使用（默认一半）
COMPRESS_THREADS=$((CPU_CORES / 2))

# 任务存储目录
TASK_DIR="/tmp/ssh-copy-tasks"
TEMP_DIR="/tmp/ssh-copy-temp"
```

## 🔍 断点续传示例

```bash
# 启动传输
task_id=$(./ssh-copy.sh --input /data/10GB-file.tar.gz --output /backup/ --ssh "user@host")

# 假设传输到 60% 时网络中断...

# 重新运行相同命令
./ssh-copy.sh --input /data/10GB-file.tar.gz --output /backup/ --ssh "user@host"

# rsync 会自动从断点继续传输
```

## 📝 传输日志示例

```
==========================================
Advanced SSH File Transfer
==========================================
Task ID:     task_20251016_143052_a1b2c3d4
Source:      /data/myproject
Destination: user@192.168.1.100:/var/www/html/
Compression: Yes (8 threads)
Split:       Yes (500M chunks)
==========================================

Started at: 2025-10-16 14:30:52

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
Using rsync for resumable transfer...

Transferring part.00...
  2.3G 100%  125.32MB/s    0:00:18
Transferring part.01...
  2.3G 100%  126.15MB/s    0:00:17
...

✓ Transfer completed

[5/5] Extracting on remote server...
Merging split files...
Verifying checksum...
✓ Checksum verified
Cleaning up split files...
Extracting archive...
Cleaning up archive...
✓ Extraction completed successfully!

✓ Remote extraction completed

Cleaning up local temporary files...

==========================================
Completed at: 2025-10-16 14:35:28
✓ Transfer completed successfully!
==========================================
```

## 🛠️ 故障排查

### 压缩很慢

```bash
# 安装 pigz 加速压缩（多线程）
sudo apt-get install pigz

# 或 pbzip2（bzip2 多线程版本）
sudo apt-get install pbzip2
```

### 传输中断

```bash
# 不用担心！只需重新运行相同命令
# rsync 会自动从断点继续
./ssh-copy.sh --input <same> --output <same> --ssh <same>
```

### 查看实时进度

```bash
# 方法1：查看日志
./ssh-copy.sh --logs <task_id>

# 方法2：附加到 tmux 会话
tmux attach -t ssh-copy-<task_id>
```

### 远程磁盘空间不足

```bash
# 传输前检查远程空间
ssh user@host "df -h /target/path"

# 调整分块大小（需要修改脚本）
SPLIT_SIZE="200M"  # 使用更小的块
```

## 🔐 安全建议

1. **使用 SSH 密钥认证**

   ```bash
   ./ssh-copy.sh --ssh "ssh -i ~/.ssh/id_rsa user@host"
   ```

2. **指定非标准端口**

   ```bash
   ./ssh-copy.sh --ssh "ssh -p 2222 user@host"
   ```

3. **临时文件加密**（如需）
   - 修改压缩命令添加加密：`tar -czf - | openssl enc -aes-256-cbc`

## 🎯 高级技巧

### 1. 批量传输

```bash
for dir in /data/project-*; do
    task_id=$(./ssh-copy.sh --input "$dir" --output /backup/ --ssh "user@host")
    echo "Started $dir: $task_id"
done
```

### 2. 自定义压缩级别

```bash
# 修改脚本中的压缩命令
compress_cmd="pigz -p $COMPRESS_THREADS -9"  # 最大压缩
compress_cmd="pigz -p $COMPRESS_THREADS -1"  # 最快速度
```

### 3. 监控所有任务

```bash
# 创建监控脚本
watch -n 5 './ssh-copy.sh --list'
```

## 📈 性能优化

1. **使用 pigz 而不是 gzip**

   - pigz 可以利用多核心，速度提升 3-8 倍

2. **调整分块大小**

   - 网络不稳定：使用较小分块（100M-200M）
   - 网络稳定：使用较大分块（1G-2G）

3. **增加 rsync 性能**
   - 添加 `--compress-level=0` 如果已压缩
   - 使用 `-W` 禁用增量传输（新文件）

## ⚠️ 注意事项

1. **磁盘空间**：本地和远程都需要额外空间存储临时文件
2. **压缩开销**：CPU 使用率会短暂升高
3. **校验和验证**：大文件校验可能需要几分钟
4. **临时文件**：存储在 `/tmp`，重启后会丢失

## 📞 支持

如有问题，检查任务日志：

```bash
./ssh-copy.sh --logs <task_id>
```

或附加到会话查看实时输出：

```bash
tmux attach -t ssh-copy-<task_id>
```
