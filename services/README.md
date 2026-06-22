# HomeLocus 轻量识别网关

供 **app_local** 纯本地 App 使用，与主 `backend/` 解耦。

## media-gateway（Flask）

将 App 上传的图片存到服务器，返回公网 URL 供千问 `imageFileUrls` 使用。

```bash
curl -X POST "https://home.example.com:8443/media/upload" \
  -H "Authorization: Bearer <key>" \
  -F "file=@/path/to/photo.jpg"
# → {"success":true,"url":"https://home.example.com:8443/media/files/2026/06/08/abc.jpg"}
```

环境变量：

| 变量 | 说明 |
|------|------|
| `PUBLIC_BASE_URL` | 返回给大模型的图片根 URL |
| `MEDIA_GATEWAY_API_KEY` | 可选鉴权 |
| `UPLOAD_DIR` | 存储目录 |

## asr-gateway（FastAPI）

接收音频，调用 Qwen3-ASR 返回文本。

```bash
curl -X POST "https://home.example.com:8443/asr/transcribe" \
  -F "file=@audio.wav" -F "language=zh"
```

启用真实识别（生产机需约 4GB+ 内存）：

```env
ASR_BACKEND=qwen_pytorch
# pip install qwen-asr torch
```

OpenVINO 优化方案见用户文档，可在宿主机直接部署后把网关指向该服务。

## 部署

```bash
bash deploy/deploy-gateways.sh
# Nginx 追加 deploy/nginx-media-asr.conf 后 reload
```
