# Firebase 推送配置

## 后端

在 `docker/.env` 或生产环境配置：

```env
FCM_SERVER_KEY=<Firebase 控制台 → 项目设置 → 云消息传递 → 服务器密钥>
```

## Android App

1. 在 [Firebase Console](https://console.firebase.google.com/) 创建项目，添加 Android 应用  
   - 包名：`com.homelocus.homelocus`
2. 下载 `google-services.json`，放到：

   `frontend/android/app/google-services.json`

3. 重新打包 APK。应用启动后会自动获取 FCM Token 并注册到后端。

未放置 `google-services.json` 时仍可编译运行，需在 App **设置 → 推送通知** 中手动粘贴 Token。
