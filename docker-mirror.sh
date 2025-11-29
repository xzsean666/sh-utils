#!/bin/bash
# 使用: ./mirror.sh <源镜像>:<tag> <目标镜像>:<tag>
# 例如: ./mirror.sh nginx:latest myusername/mynginx:latest

set -e

if [ $# -ne 2 ]; then
  echo "用法: $0 <源镜像>:<tag> <目标镜像>:<tag>"
  exit 1
fi

SRC_IMAGE=$1
DEST_IMAGE=$2

echo ">>> 拉取源镜像: $SRC_IMAGE"
docker pull "$SRC_IMAGE"

echo ">>> 打标签: $SRC_IMAGE -> $DEST_IMAGE"
docker tag "$SRC_IMAGE" "$DEST_IMAGE"

echo ">>> 推送到目标仓库: $DEST_IMAGE"
docker push "$DEST_IMAGE"

echo ">>> 完成 ✅"
