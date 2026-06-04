---

# 家庭物品管理系统 - 产品需求说明（PRD）

> **版本**：V1.1（与实现对齐）  
> **最后更新**：2026-06-04  
> **负责人**：ajcheng  
> **状态**：一期开发中（Android + API + Web 静态页）

---

## 1. 文档说明

### 1.1 文档目的
定义功能范围、业务流程、技术约束及验收标准；**本文档已按仓库实际实现修订**，接口路径与完成度以代码为准。

### 1.2 适用范围
- **一期（当前）**：Android App + FastAPI 后端 + Flutter Web 静态管理页
- **二期规划**：iOS、微信小程序、真实语音 ASR、FCM 推送、平面图 App 集成

### 1.3 术语表

| 术语 | 说明 |
|------|------|
| 物品 | 家庭中需要管理的实体 |
| 地点 (Location) | 物理空间，如主住宅、父母家 |
| 分区 (Zone) | 地点内区域，如客厅、主卧 |
| 储物模块 (Container) | 柜子、电视柜等 |
| 层级 (Slot) | 抽屉、层板等最小存放单元 |
| 快照 (ImageSnapshot) | 某层级在某时间点的照片记录 |

---

## 2. 产品概述

### 2.1 项目背景
（同 V1.0）家庭物品分散、难查找、设备忘充电、信息不互通。

### 2.2 产品定位
**家庭资产的空间化数字清单**——拍照/语音/手动录入，混合检索，充电与借出提醒。

### 2.3 核心价值主张
> **“别再问‘东西放哪了’——拍一张照，永远记得住。”**

---

## 3. 实现状态总览（2026-06-04）

| 模块 | PRD 优先级 | 实现状态 | 说明 |
|------|-----------|----------|------|
| 空间管理 | P0 | ✅ 基本完成 | 四级 CRUD；创建家庭时带模板；App 树形浏览 |
| **按层级浏览物品** | P0 | ✅ **本次完成** | `GET /items/slot/{id}` + App 展开显示 |
| 拍照 + AI 识别 | P0 | ✅ 可用 | FlowBar/kimi 视觉；约 60–100s；需配置 `AI_API_KEY` |
| OCR | P0 | ❌ 未启用 | PaddleOCR 未配置 |
| 语音录入 | P0 | ✅ 基本完成 | 真实录音 + Whisper ASR；文本 NLP 备用 |
| **手动录入** | P0 | ✅ **本次完成** | `POST /items/manual` + 空间页入口 |
| 确认 + 索引 | P0 | ✅ | 确认后写 Meilisearch；DB 回退搜索 |
| **category 分类** | P0 | ✅ **本次完成** | DB 字段 + 搜索索引 |
| **充电提醒自动创建** | P1 | ✅ **本次完成** | 确认/手动/语音添加时若需充电则建 Reminder |
| 文本/语义搜索 | P0/P1 | ⚠️ 部分 | hybrid + 语义扩展；无拼音 |
| 以图搜图 | P1 | ✅ | 后端 `POST /search/by-image`；App 搜索页已接 |
| 向量检索 | P1 | ❌ | Qdrant 已部署，未写入向量 |
| 充电/借出提醒 API | P1 | ✅ | Beat 扫描；**无 FCM 推送** |
| 借出标记 UI | P1 | ✅ | 空间页长按物品借出；提醒页可「已归位」 |
| 家庭组/邀请 | P2→已实现 | ✅ | 超前于原 PRD 二期 |
| 平面图 | P2 | ⚠️ API 有 | App 未集成 |
| 导入导出/回收站 | P2 | ❌ | 未做 |
| Web 管理后台 | 一期 | ⚠️ | 同 Flutter Web 静态资源，非独立后台 |

---

## 4. 功能需求（修订）

### 4.1 空间管理（P0）

| 功能点 | 状态 |
|--------|------|
| 创建/切换地点 | ✅ `GET/POST /api/v1/space/locations` |
| 分区/储物模块/层级 | ✅ zones、containers、slots |
| 标准化模板 | ✅ 创建家庭时生成客厅/主卧等（`FAMILY_SPACE_TEMPLATE`） |
| 单独地点一键模板 | ❌ 待做 |
| 删除地点迁移物品 | ❌ 当前级联删除 |

**验收：** 30 秒内完成四级创建 —— 熟练用户可达。

---

### 4.2 物品录入（P0）

| 功能点 | 状态 |
|--------|------|
| 拍照上传 | ✅ `POST /api/v1/items/upload` → `task-status/{task_id}` |
| AI 识别（名称+框） | ✅ Celery + OpenAI 兼容 Vision |
| OCR | ❌ 跳过 |
| 用户确认/修正 | ✅ `PUT /api/v1/items/confirm/{item_id}` |
| 手动录入 | ✅ `POST /api/v1/items/manual` |
| 物品属性 category | ✅ 字段 `items.category` |
| 需充电标记 | ✅ 确认时可选；**自动创建充电提醒** |

**性能说明（实测）：** Vision 识别 P95 约 **60–100s**（依赖云端 API），高于原 PRD「5 秒」目标，App 轮询最长约 3 分钟。

---

### 4.3 检索与浏览（P0）

| 功能点 | 状态 |
|--------|------|
| 关键词搜索 | ✅ `POST /api/v1/search/hybrid` |
| 最近物品（搜索页） | ✅ `GET /api/v1/search/recent` |
| 空间路径面包屑 | ✅ 搜索结果含 breadcrumb |
| 按层级浏览物品 | ✅ `GET /api/v1/items/slot/{slot_id}` |
| 拼音匹配 | ❌ |
| 以图搜图 App | ✅ 搜索栏图片按钮 |
| 按分类筛选 UI | ✅ 搜索页分类 FilterChip |
| 搜索跳转空间 | ✅ 结果/最近物品点击 → 空间 Tab 展开层级 |

---

### 4.4 提醒与生命周期（P1）

| 功能点 | 状态 |
|--------|------|
| 充电提醒周期 | ✅ `charge_cycle_days` + Reminder 表 |
| 确认后自动排期 | ✅ **本次完成** |
| 已充电顺延 | ✅ `POST /reminders/charge/complete` |
| App 提醒列表 | ✅ 提醒 Tab |
| 推送通知 | ⚠️ 部分 | FCM 后端 + Token 注册；需配置 `FCM_SERVER_KEY` |
| 借出标记入口 | ✅ 空间页长按物品 |
| 24h 未处理再提醒 | ❌ |

---

### 4.5 多成员协同

| 功能点 | 状态 |
|--------|------|
| 家庭组/邀请/角色 | ✅ `/api/v1/families` + App |
| 操作审计 | ✅ API 有，App 无 |

---

## 5. 实际接口定义（与代码一致）

### 5.1 空间

| 方法 | 路径 | 说明 |
|------|------|------|
| POST | `/api/v1/space/locations` | 创建地点 |
| GET | `/api/v1/space/locations` | 地点列表 |
| GET | `/api/v1/space/zones?location_id=` | 分区 |
| POST | `/api/v1/space/containers` | 储物模块（可带 slots） |
| POST | `/api/v1/space/containers/{id}/slots` | 添加层级 |
| GET | `/api/v1/space/slots/{slot_id}/path` | 层级路径（跳转空间用） |
| POST | `/api/v1/space/locations/{id}/apply-template` | 为已有地点应用标准模板 |

### 5.2 物品

| 方法 | 路径 | 说明 |
|------|------|------|
| POST | `/api/v1/items/upload` | 上传照片，返回 `task_id` |
| GET | `/api/v1/items/task-status/{task_id}` | 轮询识别结果 |
| PUT | `/api/v1/items/confirm/{item_id}` | 确认物品（含 category、slot_id） |
| POST | `/api/v1/items/manual` | 手动添加 |
| GET | `/api/v1/items/slot/{slot_id}` | 层级内物品列表 |
| GET | `/api/v1/items/history/{slot_id}` | 历史快照 |

### 5.3 检索

| 方法 | 路径 | 说明 |
|------|------|------|
| POST | `/api/v1/search/hybrid` | 混合检索 |
| GET | `/api/v1/search/recent` | 最近物品 |
| POST | `/api/v1/search/by-image` | 以图搜图（后端） |
| GET | `/api/v1/search/categories` | 分类列表（筛选） |
| POST | `/api/v1/notifications/device-token` | 注册 FCM 设备 Token |
| POST | `/api/v1/search/reindex` | 重建索引 |

### 5.4 语音

| 方法 | 路径 | 说明 |
|------|------|------|
| POST | `/api/v1/speech/add-item-text` | JSON 文本解析 |
| POST | `/api/v1/speech/add-item` | 音频（ASR 待完善） |
| POST | `/api/v1/speech/add-item/confirm` | 确认入库 |

---

## 6. 数据模型（Item 关键字段）

| 字段 | 类型 | 说明 |
|------|------|------|
| id | string | `item_xxxxxxxx` |
| slot_id | string | 所属层级 |
| label | string | 名称 |
| brand | string? | 品牌 |
| **category** | string? | 分类（electronics/clothing/…） |
| is_chargeable | bool | 是否需充电 |
| charge_cycle_days | int | 默认 90 |
| thumbnail_path | string? | 切片图路径 |

---

## 7. 技术栈与部署

| 层 | 选型 |
|----|------|
| 后端 | Python 3.12 + FastAPI + Celery |
| 数据库 | PostgreSQL 16 |
| 搜索 | Meilisearch + DB 回退 |
| 向量 | Qdrant（未写入） |
| AI | OpenAI 兼容 API（如 ai.shxybar.com + kimi-k2.5） |
| 移动端 | Flutter，当前 **minSdk 33** |
| 部署 | Docker Compose，`deploy/deploy-backend-only.sh` |

环境变量（生产必配）：`AI_API_KEY`、`AI_BASE_URL`、`AI_VISION_MODEL`、`DATABASE_URL`、`DATABASE_URL_SYNC`（Celery 落库）。

---

## 8. 验收标准（修订）

| 编号 | 验收项 | 当前 |
|------|--------|------|
| AC-01 | 空间创建 | ✅ |
| AC-02 | 拍照确认后可搜索 | ✅（需索引/新 App） |
| AC-03 | 文本搜索 + 路径 | ✅；拼音 ❌ |
| AC-04 | 充电提醒到期推送 | ⚠️ 提醒入库 ✅，推送 ❌ |
| AC-05 | 借出 24h 提醒 | ❌ |
| AC-06 | 空间页查看层级物品 | ✅ **本次** |
| AC-07 | 手动添加物品 | ✅ **本次** |

---

## 9. 版本规划（修订）

| 版本 | 目标 | 内容 |
|------|------|------|
| **V1.0.12+（当前）** | 生产可用 | 识别/搜索/空间浏览；以图搜图、搜索跳转、地点切换、借出 UI、应用模板 |
| V1.1 | 体验 | 真实语音 ASR、FCM 推送、拼音/向量检索 |
| V1.2 | 协同增强 | 平面图 App、拼音、向量检索、导入导出 |
| V2.0 | 生态 | iOS/小程序、离线、智能盘点 |

---

## 10. 待办优先级（研发 backlog）

### P0（下一迭代）
1. App 集成 `firebase_messaging` 自动获取 FCM Token
2. 配置生产环境 `FCM_SERVER_KEY`

### P1
3. PaddleOCR
4. 24h 未处理再提醒

### P2
9. 向量检索（CLIP embedding）
10. 数据导入导出、回收站
11. 平面图 App

---

**文档结束**
