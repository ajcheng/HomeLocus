#!/bin/bash
# 仅更新 backend + celery-worker 镜像（生产已有 postgres/redis 等）
# 用法: sudo su - root -c '/home/aj/HomeLocus/deploy/deploy-backend-only.sh'

set -e

echo "本机公网 IP（需在跳板机防火墙放行 22222）: $(curl -s --max-time 5 ifconfig.me || echo unknown)"
echo ""

TARGET="nginx"
DEPLOY_DIR="/root/HomeLocus"
IMAGES_DIR="/tmp/homelocus-images"
IMAGE_TAR="$IMAGES_DIR/homelocus-backend.tar"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

echo "=== 1. 构建镜像（若尚未构建）==="
if ! sudo docker image inspect homelocus-backend:latest &>/dev/null; then
  sudo docker build -t homelocus-backend:latest "$PROJECT_DIR/backend"
fi

echo "=== 2. 导出 backend 镜像 ==="
mkdir -p "$IMAGES_DIR"
sudo docker save homelocus-backend:latest -o "$IMAGE_TAR"
echo "镜像大小: $(ls -lh "$IMAGE_TAR" | awk '{print $5}')"

echo "=== 3. 传输到生产 nginx ==="
scp "$IMAGE_TAR" "$TARGET:/tmp/homelocus-backend.tar"
scp "$PROJECT_DIR/docker/docker-compose.prod.yml" "$TARGET:$DEPLOY_DIR/docker/docker-compose.yml"
scp "$PROJECT_DIR/docker/.env" "$TARGET:$DEPLOY_DIR/docker/.env"

echo "=== 4. 加载镜像并重启服务 ==="
ssh "$TARGET" bash -s <<'REMOTE'
set -e
sudo docker load -i /tmp/homelocus-backend.tar
cd /root/HomeLocus
sudo docker compose -f docker/docker-compose.yml up -d --force-recreate backend celery-worker celery-beat
sudo docker compose -f docker/docker-compose.yml ps
curl -sf http://127.0.0.1:8000/health && echo " backend health OK"
REMOTE

echo ""
echo "✅ 生产 backend/celery 已更新"
