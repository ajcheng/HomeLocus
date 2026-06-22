# HomeLocus YOLO Vision API

OpenVINO + YOLO11 本地检测服务，输出与 HomeLocus `ai_recognition.analyze_image` 兼容的 JSON（中文类名、百分比边界框、充电提醒分类）。

## 接口

| 方法 | 路径 | 说明 |
|------|------|------|
| GET | `/health` | 健康检查 |
| GET | `/v1/config` | 当前默认模型/设备 |
| POST | `/v1/analyze` | **HomeLocus 主接口**（multipart 字段 `file`） |
| POST | `/v1/detect` | 原始检测 + homelocus 映射 |

可选请求头：`X-API-Key`（与 `API_KEY` 环境变量一致时启用）

表单参数：`model`（yolo11/worldv2/both）、`device`、`conf`、`lang`（zh/en）

## 构建与运行

```bash
cd services/yolo-vision
docker build -t homelocus-yolo-vision:latest .
docker compose up -d
curl http://127.0.0.1:8765/health
```

模型目录挂载自 `~/cursor/yolo-openvino/models`（需先执行 `export_models.py`）。

## WireGuard + Nginx（生产调用本机）

1. 本机 WG IP：`192.168.100.19`，服务监听 `8765`
2. 生产 Nginx 增加 `deploy/nginx-yolo-api.conf` 中 `location /yolo-api/`
3. HomeLocus `docker/.env`：

```env
RECOGNITION_PROVIDER=yolo
YOLO_API_URL=http://192.168.100.19:8765
YOLO_MODEL=yolo11
```

若经 Nginx 反代（仅用于外网调试，Celery 建议直连 WG IP）：

```env
YOLO_API_URL=https://home.example.com:8443/yolo-api
```

## 响应示例

```json
{
  "items": [{
    "label": "笔记本电脑",
    "label_en": "laptop",
    "category": "electronics",
    "bounding_box": {"x": 10, "y": 20, "w": 30, "h": 25},
    "is_chargeable": true,
    "confidence": 0.91
  }],
  "summary": "检测到 3 个物品：笔记本电脑、键盘、鼠标",
  "provider": "yolo",
  "detections_zh": [...]
}
```
