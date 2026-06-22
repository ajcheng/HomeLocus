#!/bin/bash
# 部署 media-gateway 到生产；ASR 在本机 deploy/build-asr-gateway.sh
set -e

TARGET="nginx"
DEPLOY_DIR="/root/HomeLocus"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

echo "=== 1. 构建 media-gateway 镜像 ==="
sudo docker build -t homelocus-media-gateway:latest "$PROJECT_DIR/services/media-gateway"

echo "=== 2. 导出镜像 ==="
mkdir -p /tmp/homelocus-images
sudo docker save homelocus-media-gateway:latest -o /tmp/homelocus-images/homelocus-media.tar
sudo chown "$(whoami):$(whoami)" /tmp/homelocus-images/homelocus-media.tar

echo "=== 3. 传输到生产 ==="
scp /tmp/homelocus-images/homelocus-media.tar "$TARGET:/tmp/"
scp "$PROJECT_DIR/docker/docker-compose.media-gateway.yml" "$TARGET:$DEPLOY_DIR/docker/"
ssh "$TARGET" "sudo mkdir -p /data/HomeLocus/media-gateway"

echo "=== 4. 启动 media-gateway ==="
ssh "$TARGET" bash -s <<'REMOTE'
set -e
sudo docker load -i /tmp/homelocus-media.tar
cd /root/HomeLocus
sudo docker compose -f docker/docker-compose.media-gateway.yml up -d --force-recreate
sudo docker compose -f docker/docker-compose.media-gateway.yml ps
curl -sf http://127.0.0.1:8780/health && echo " media-gateway OK"
REMOTE

echo "=== 5. 更新 Nginx 配置 ==="
NGINX_SRC="$PROJECT_DIR/deploy/nginx-home.conf.local"
if [ -f "$NGINX_SRC" ]; then
  echo "  使用本地覆盖配置: nginx-home.conf.local"
else
  NGINX_SRC="$PROJECT_DIR/deploy/nginx-home.conf"
  echo "  使用模板配置（部署后请检查 server_name 与 SSL 路径）"
fi
scp "$NGINX_SRC" "$TARGET:/opt/openresty/nginx/conf/conf.d/home.conf"
ssh "$TARGET" "sudo nginx -t && sudo systemctl reload nginx"

echo ""
echo "✅ media-gateway 已部署，Nginx 已更新（/media/ + /asr/→WG）"
echo "   请在本机执行: bash deploy/build-asr-gateway.sh"
