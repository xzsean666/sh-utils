# rclone_helper.sh 使用说明

脚本位置：`system/syncdata/rclone_helper.sh`  
作用：按 `config.env` 中的任务配置调用 rclone，把指定本地目录同步/复制到远端（S3 兼容、B2、R2、预先配置的 rclone remote、SFTP/SSH）。

## 快速开始
1) 安装 rclone 并保证在 PATH 中：`rclone version`  
2) 复制示例配置：`cp system/syncdata/config.env.example system/syncdata/config.env`  
3) 填好 `config.env` 里的任务、密钥、路径。  
4) 运行：
```bash
bash system/syncdata/rclone_helper.sh --delete         # 所有任务，强制 sync（删除多余）
bash system/syncdata/rclone_helper.sh --no-delete      # 所有任务，强制 copy（不删）
bash system/syncdata/rclone_helper.sh --jobs JOB1,JOB2 # 只跑指定任务
bash system/syncdata/rclone_helper.sh --dry-run        # 预览
```

## 配置字段说明（摘）
- `BACKUP_JOBS=(JOB1 JOB2 ...)` 定义任务名（只允许字母/数字/下划线）。
- `JOBX_TYPE`：`S3` | `SSH` (或 `SFTP`) | `REMOTE`。  
- `JOBX_SRC`：本地源目录。  
- 任务删除策略：`JOBX_DELETE=true|false`（可被 `--delete` / `--no-delete` 覆盖）。  
- 额外 flags：`JOBX_RCLONE_FLAGS="--transfers 8 ..."`, 全局：`RCLONE_GLOBAL_FLAGS="..."`。  
- `REMOTE` 类型：`JOBX_DESTINATION="myremote:/path"`（使用你已有的 rclone remote）。  
- S3/R2/B2 特定字段见示例；SSH/SFTP 需 `JOBX_SSH_HOST`、`JOBX_SSH_PATH`，可选 `JOBX_SSH_USER`、`JOBX_SSH_PORT`、`JOBX_SSH_KEY_FILE`。

## S3 兼容示例（AWS S3）
```bash
BACKUP_JOBS=(AWS_S3)

AWS_S3_TYPE=S3
AWS_S3_SRC="/data/photos"
AWS_S3_S3_PROVIDER=AWS
AWS_S3_S3_BUCKET="my-bucket"
AWS_S3_S3_PATH="photos"
AWS_S3_S3_REGION="us-east-1"
AWS_S3_S3_ACCESS_KEY="AKIA..."
AWS_S3_S3_SECRET_KEY="SECRET..."
# 可选：AWS_S3_S3_STORAGE_CLASS="STANDARD_IA"
AWS_S3_DELETE=true
```

## Backblaze B2 示例
```bash
BACKUP_JOBS=(B2_DOCS)

B2_DOCS_TYPE=S3
B2_DOCS_SRC="/data/docs"
B2_DOCS_S3_PROVIDER=Backblaze
B2_DOCS_S3_ENDPOINT="https://s3.us-west-002.backblazeb2.com"
B2_DOCS_S3_BUCKET="my-b2-bucket"
B2_DOCS_S3_PATH="docs"
B2_DOCS_S3_REGION="us-west-002"
B2_DOCS_S3_ACCESS_KEY="keyId"
B2_DOCS_S3_SECRET_KEY="appKey"
B2_DOCS_DELETE=false
```

## Cloudflare R2 示例
```bash
BACKUP_JOBS=(R2_STATIC)

R2_STATIC_TYPE=S3
R2_STATIC_SRC="/data/static"
R2_STATIC_S3_PROVIDER=Cloudflare
R2_STATIC_S3_ENDPOINT="https://<account_id>.r2.cloudflarestorage.com"
R2_STATIC_S3_BUCKET="my-r2-bucket"
R2_STATIC_S3_PATH="static"
R2_STATIC_S3_REGION="auto"
R2_STATIC_S3_ACCESS_KEY="r2-access-key"
R2_STATIC_S3_SECRET_KEY="r2-secret-key"
R2_STATIC_DELETE=true
```

## SFTP / SSH 示例
```bash
BACKUP_JOBS=(SFTP_MEDIA)

SFTP_MEDIA_TYPE=SSH
SFTP_MEDIA_SRC="/data/media"
SFTP_MEDIA_SSH_HOST="backup.example.com"
SFTP_MEDIA_SSH_USER="root"
SFTP_MEDIA_SSH_PORT=22
SFTP_MEDIA_SSH_PATH="/srv/backups/media"
# 可选：SFTP_MEDIA_SSH_KEY_FILE="~/.ssh/id_ed25519"
SFTP_MEDIA_DELETE=false
```

## 预配置 remote 示例
你已有 rclone remote `nas:`:
```bash
BACKUP_JOBS=(NAS_MISC)

NAS_MISC_TYPE=REMOTE
NAS_MISC_SRC="/data/misc"
NAS_MISC_DESTINATION="nas:/backups/misc"
NAS_MISC_DELETE=true
```

## 同时多端示例（远程1、远程2、R2、B2 一起）
```bash
BACKUP_JOBS=(REMOTE1 REMOTE2 R2_ALL B2_ALL)

REMOTE1_TYPE=SSH
REMOTE1_SRC="/data/share"
REMOTE1_SSH_HOST="srv1.example.com"
REMOTE1_SSH_USER="root"
REMOTE1_SSH_PATH="/srv/backups/share"
REMOTE1_DELETE=true

REMOTE2_TYPE=SSH
REMOTE2_SRC="/data/share"
REMOTE2_SSH_HOST="srv2.example.com"
REMOTE2_SSH_USER="root"
REMOTE2_SSH_PATH="/srv/backups/share"
REMOTE2_DELETE=true

R2_ALL_TYPE=S3
R2_ALL_SRC="/data/share"
R2_ALL_S3_PROVIDER=Cloudflare
R2_ALL_S3_ENDPOINT="https://<account_id>.r2.cloudflarestorage.com"
R2_ALL_S3_BUCKET="my-r2-bucket"
R2_ALL_S3_PATH="share"
R2_ALL_S3_REGION="auto"
R2_ALL_S3_ACCESS_KEY="r2-access"
R2_ALL_S3_SECRET_KEY="r2-secret"
R2_ALL_DELETE=true

B2_ALL_TYPE=S3
B2_ALL_SRC="/data/share"
B2_ALL_S3_PROVIDER=Backblaze
B2_ALL_S3_ENDPOINT="https://s3.us-west-002.backblazeb2.com"
B2_ALL_S3_BUCKET="my-b2-bucket"
B2_ALL_S3_PATH="share"
B2_ALL_S3_REGION="us-west-002"
B2_ALL_S3_ACCESS_KEY="b2-key-id"
B2_ALL_S3_SECRET_KEY="b2-app-key"
B2_ALL_DELETE=true
```

运行命令示例：
```bash
# 全部任务并删除多余（sync）
bash system/syncdata/rclone_helper.sh --delete

# 只跑 R2 和 B2，预览
bash system/syncdata/rclone_helper.sh --jobs R2_ALL,B2_ALL --dry-run
```
