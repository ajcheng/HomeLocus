#!/bin/bash
# 在本机构建并启动 Qwen3-ASR 网关（供生产 Nginx 经 WG 反代）
set -e
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ASR_DIR="$(dirname "$SCRIPT_DIR")/services/asr-gateway"
MODEL_DIR="${ASR_MODEL_HOST_DIR:-/home/aj/models/Qwen3-ASR-0.6B}"

if [ ! -f "$MODEL_DIR/model.safetensors" ]; then
  echo "=== 预下载 Qwen3-ASR-0.6B 模型（ModelScope，约 1.8GB）==="
  mkdir -p "$(dirname "$MODEL_DIR")"
  pip3 install -q modelscope
  modelscope download --model Qwen/Qwen3-ASR-0.6B --local_dir "$MODEL_DIR"
fi

export ASR_MODEL_HOST_DIR="$MODEL_DIR"

echo "=== 构建 Qwen ASR 镜像（含 torch + qwen-asr，首次较慢）==="
cd "$ASR_DIR"
sudo docker compose build --no-cache
sudo docker compose up -d --force-recreate

echo "=== 等待模型加载（首次会下载 Qwen3-ASR-0.6B）==="
for i in $(seq 1 60); do
  if curl -sf http://127.0.0.1:8781/health | grep -q '"model_loaded":true'; then
    curl -sf http://127.0.0.1:8781/health
    echo ""
    echo "✅ ASR 网关已就绪: http://192.168.100.19:8781"
    exit 0
  fi
  echo "等待模型加载... ($i/60)"
  sleep 10
done

echo "⚠️ 模型尚未加载完成，查看日志:"
sudo docker compose logs --tail 30
curl -sf http://127.0.0.1:8781/health || true
