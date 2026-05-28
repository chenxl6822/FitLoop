# 任务 11：Android/iOS 权限配置 — Claude 执行规范

## 背景

FitLoop 是一个 Flutter 运动打卡 App（Spring Boot 后端）。刚在 `pubspec.yaml` 中加入了 `image_picker: ^1.1.2`（头像上传），但 AndroidManifest.xml 缺少必需的相机/存储权限，且 `mobile/ios/` 目录**完全缺失**。

## 目标

确保 `image_picker` 在 Android 真机上能正常工作（拍照/选图不 crash），并为未来 iOS 构建做准备。

---

## 步骤 1：Android 权限 — AndroidManifest.xml

**文件：** `mobile/android/app/src/main/AndroidManifest.xml`

在现有的 `<manifest>` 内、`<application>` 之前已有的 `<uses-permission>` 下方添加：

```xml
<!-- image_picker 拍摄照片所需 -->
<uses-permission android:name="android.permission.CAMERA" />

<!-- Android 12 及以下：读取媒体文件 -->
<uses-permission
    android:name="android.permission.READ_EXTERNAL_STORAGE"
    android:maxSdkVersion="32" />

<!-- Android 13+：细粒度媒体权限（取代 READ_EXTERNAL_STORAGE） -->
<uses-permission android:name="android.permission.READ_MEDIA_IMAGES" />
```

**⚠️ 安全规则：**

- `READ_EXTERNAL_STORAGE` 必须加 `android:maxSdkVersion="32"`（Android 13+ 不再需要，且 Google Play 会警告）
- `READ_MEDIA_IMAGES` 只对 API 33+ 生效（不设 maxSdkVersion，更老系统会自动忽略）
- 不要添加 `WRITE_EXTERNAL_STORAGE` — `image_picker` 不需要，且 Google Play 2024 起对 targetSdk 30+ 限制严格

**最终板块结构：**

```xml
<uses-permission android:name="android.permission.ACCESS_FINE_LOCATION" />
<uses-permission android:name="android.permission.ACCESS_COARSE_LOCATION" />
<uses-permission android:name="android.permission.POST_NOTIFICATIONS" />
<uses-permission android:name="android.permission.RECEIVE_BOOT_COMPLETED" />
<uses-permission android:name="android.permission.CAMERA" />
<uses-permission
    android:name="android.permission.READ_EXTERNAL_STORAGE"
    android:maxSdkVersion="32" />
<uses-permission android:name="android.permission.READ_MEDIA_IMAGES" />
```

---

## 步骤 2：iOS 目录 — 从零创建

### 2.1 在项目根目录运行

```bash
flutter create --platforms=ios --project-name fitloop .
```

这会生成 `mobile/ios/` 目录。**但是**原项目的 `android/`、`lib/`、`test/`、`pubspec.yaml` 不会被覆盖（`flutter create` 不会覆盖已存在的根文件）。

### 2.2 生成后的 Info.plist 路径

`mobile/ios/Runner/Info.plist`

### 2.3 在 Info.plist 中添加权限描述

在 `<plist><dict>` 块中，添加以下 key-value：

```xml
<key>NSCameraUsageDescription</key>
<string>FitLoop 需要使用相机拍摄头像</string>
<key>NSPhotoLibraryUsageDescription</key>
<string>FitLoop 需要访问您的相册来选择头像</string>
<key>NSLocationWhenInUseUsageDescription</key>
<string>FitLoop 需要在运动时获取您的实时位置来记录运动轨迹</string>
```

---

## 步骤 3：验证

### 3.1 编译验证

```bash
cd mobile
flutter analyze
flutter test
```

### 3.2 确认权限生效

Android 端已在 main.dart 中通过 `image_picker` 内部自动请求权限（0.8.7+ 版本自带权限请求），不需要手动写 `permission_handler` 代码。`permission_handler` 不需要添加为依赖。

---

## 范围边界（不做的事）

- ❌ 不要修改 Flutter dart 代码（main.dart、api_client.dart 等）
- ❌ 不要添加 `permission_handler` 依赖
- ❌ 不要修改 build.gradle、podfile 等其他构建文件
- ❌ 不要改动 `android/app/build.gradle` 中的 targetSdk 或 compileSdk
- ❌ 不需要写测试
- ❌ 不需要写启动页/引导页（那是任务 9）

---

## 验收标准

| 条目 | 检查方式 |
|------|---------|
| AndroidManifest.xml 包含 CAMERA 权限 | `grep "CAMERA" AndroidManifest.xml` |
| READ_EXTERNAL_STORAGE 带 maxSdkVersion=32 | 需确认文件中该行正确 |
| READ_MEDIA_IMAGES 存在 | `grep "READ_MEDIA_IMAGES"` |
| iOS Info.plist 有 NSCameraUsageDescription | `grep "NSCameraUsageDescription" Info.plist` |
| iOS Info.plist 有 NSPhotoLibraryUsageDescription | 同上 |
| `flutter analyze` 0 issues | 运行验证 |
| `flutter test` 全部通过 | 运行验证 |

---

## 额外说明

### 关于 iOS 目录

当前 `mobile/ios/` 目录不存在。如果运行 `flutter create --platforms=ios` 后你不想保留 `.git` 和 `.idea` 等生成物，可以删除它们：

```bash
rm -rf mobile/ios/.git mobile/ios/.idea mobile/ios/.gitignore
```

或者直接用 `flutter build ios` 也自动生成了 macOS 才需要的东西（但跑这个需要 macOS + Xcode）。如果当前不是 macOS 环境，创建目录但无法真机编译 iOS 是正常的，留到有 macOS 构建机时再完成。

### 关于现有权限

当前 AndroidManifest.xml 已有：
- `ACCESS_FINE_LOCATION` ✅
- `ACCESS_COARSE_LOCATION` ✅
- `POST_NOTIFICATIONS` ✅
- `RECEIVE_BOOT_COMPLETED` ✅

这些不需要改动。
