# HomeLocus 纯本地版（app_local）

数据全部存储在手机 SQLite，**不依赖 HomeLocus 主后端**。仅通过两个轻量网关 + 大模型 API 完成图像/语音识别。

## 架构

```
┌─────────────────────────────────────────┐
│  Flutter App（本工程）                    │
│  SQLite：空间 / 物品 / 标记 / 历史        │
│  本地文件：图片、录音                      │
└───────────┬─────────────┬───────────────┘
            │             │
            ▼             ▼
   media-gateway     asr-gateway
   POST /upload      POST /transcribe
   → 公网图片 URL     → 识别文本
            │             │
            ▼             ▼
   千问 VL API         Qwen3-ASR
   (qwen-vl-plus)      (PyTorch/OpenVINO)
```

## 首次配置（设置页）

| 配置项 | 示例 |
|--------|------|
| 图片网关 | `https://home.ajcheng.com:8443/media` |
| 视觉 API | `https://nfam-api.yst.com.cn/tenant/trans/call` |
| API Key | `sk-...` |
| Tenant ID | `ajcheng02` |
| 模型 | `qwen-vl-plus` |
| ASR 网关 | `https://home.ajcheng.com:8443/asr` |

## 运行

```bash
cd app_local
flutter pub get
flutter run
# 打包
flutter build apk --release --target-platform android-arm64
```

## 功能

- 四级空间浏览（本地种子数据）
- 拍照识别 → 上传网关 → 千问 VL → 确认入库
- 语音添加 → ASR 网关 → 文本入库
- 本地搜索、标记筛选、批量归档、历史记录
- 手动添加物品

## 与联网版区别

| | 联网版 `frontend/` | 本地版 `app_local/` |
|--|-------------------|---------------------|
| 数据 | PostgreSQL 服务端 | SQLite 手机 |
| 登录 | JWT | 无 |
| 家庭协作 | 有 | 无 |
| 识别 | Celery + YOLO/API | 直连网关 + 大模型 |
