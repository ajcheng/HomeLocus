#!/bin/bash
# HomeLocus Deployment Script
# Transfers Docker images and deploys to target machine via SSH jump host

set -e

TARGET="nginx"          # SSH host (defined in ~/.ssh/config, jumps via sx)
DEPLOY_DIR="/root/HomeLocus"
IMAGES_DIR="/tmp/homelocus-images"

echo "=== 1. Save Docker images ==="
mkdir -p "$IMAGES_DIR"
sudo docker save \
    homelocus-backend:latest \
    postgres:16-alpine \
    redis:7-alpine \
    getmeili/meilisearch:v1.13 \
    qdrant/qdrant:latest \
    -o "$IMAGES_DIR/homelocus-all.tar"

echo "Images saved: $(ls -lh $IMAGES_DIR/homelocus-all.tar | awk '{print $5}')"

echo ""
echo "=== 2. Transfer images to target ==="
scp "$IMAGES_DIR/homelocus-all.tar" "$TARGET:/tmp/"

echo ""
echo "=== 3. Transfer project files ==="
ssh "$TARGET" "mkdir -p $DEPLOY_DIR/docker"
scp docker/docker-compose.prod.yml "$TARGET:$DEPLOY_DIR/docker/docker-compose.yml"
scp docker/.env "$TARGET:$DEPLOY_DIR/docker/.env"
scp -r backend/alembic "$TARGET:$DEPLOY_DIR/backend/"
scp backend/alembic.ini "$TARGET:$DEPLOY_DIR/backend/"

echo ""
echo "=== 4. Load images on target ==="
ssh "$TARGET" "sudo docker load -i /tmp/homelocus-all.tar"

echo ""
echo "=== 5. Create storage directory ==="
ssh "$TARGET" "sudo mkdir -p /data/HomeLocus/uploads"

echo ""
echo "=== 6. Start services ==="
ssh "$TARGET" "cd $DEPLOY_DIR && sudo docker compose -f docker/docker-compose.yml up -d"

echo ""
echo "=== 7. Run database migration ==="
ssh "$TARGET" "cd $DEPLOY_DIR && sudo docker compose -f docker/docker-compose.yml exec -T backend alembic upgrade head"

echo ""
echo "=== 8. Install nginx config ==="
scp deploy/nginx-your-domain.com.conf "$TARGET:/etc/nginx/conf.d/home.conf"
ssh "$TARGET" "sudo nginx -t && sudo systemctl reload nginx"

echo ""
echo "=== 9. Verify ==="
sleep 5
ssh "$TARGET" "cd $DEPLOY_DIR && sudo docker compose -f docker/docker-compose.yml ps"
echo ""
curl -s http://your-domain.com/health || echo "Health check via domain failed, trying local..."
ssh "$TARGET" "curl -s http://127.0.0.1:8000/health"

echo ""
echo "✅ Deployment complete! Visit: https://your-domain.com"
