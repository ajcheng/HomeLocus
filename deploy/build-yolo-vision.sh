#!/bin/bash
# 构建 homelocus-yolo-vision 镜像并在本机启动（需已导出 OpenVINO 模型）
set -e
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
YOLO_DIR="$(dirname "$SCRIPT_DIR")/services/yolo-vision"
MODELS="${YOLO_MODELS_HOST:-/home/aj/cursor/yolo-openvino/models}"

if [ ! -d "$MODELS/yolo11n_openvino_model" ] && [ ! -d "$MODELS" ]; then
  echo "警告: 未找到 OpenVINO 模型目录 $MODELS"
  echo "请先: cd /home/aj/cursor/yolo-openvino && python scripts/export_models.py --only yolo11"
fi

cd "$YOLO_DIR"
docker build -t homelocus-yolo-vision:latest .
docker compose up -d
echo "YOLO Vision: http://127.0.0.1:8765/health"
curl -sf http://127.0.0.1:8765/health && echo ""
