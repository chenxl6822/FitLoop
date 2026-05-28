# FitLoop — Claude 上下文速览

> 写给 Claude Code 的全局上下文，让 AI 能安全、独立地完成任务 9（启动页）和任务 11（权限配置）。

## 项目摘要

FitLoop 是面向高校学生的运动打卡与健康管理 App。

- **后端**：Spring Boot 3.x + JPA + MySQL 8.0 + JWT 鉴权
- **前端**：Flutter + Material 3，纯 dart:io HttpClient，无 Provider/Riverpod
- **仓库**：`https://github.com/chenxl6822/FitLoop`（main 分支）
- **原型**：8 个 commits，全部功能已推送到 `origin/main`

## 架构关键点

### 依赖注入（简朴手写，无框架）

`main.dart` 顶部：

```dart
class FitLoopApp extends StatelessWidget {
  FitLoopApp({
    required this.api,
    required this.locationService,
    required this.reminderScheduler,
    required this.connectivityService,
  });
```

所有依赖**通过构造函数注入**。`main()` 中用默认工厂创建：

```dart
void main() => runApp(FitLoopApp(
  api: HttpFitLoopApi(),
  locationService: GeolocatorLocationService(),
  reminderScheduler: LocalReminderScheduler(),
  connectivityService: ConnectivityService(),
));
```

### 页面路由（本页式，无命名路由）

所有页面在 `main.dart` 中定义为 StatefulWidget，通过 `_AppShellState._index` 用 BottomNavigationBar 切换（5 个 tab）。

### 状态管理（setState，无 Provider/Bloc）

所有页面级状态用 `setState` 管理。全局状态（session/connectivity）从父 Widget 层层传参。

### API 客户端

```
abstract class FitLoopApi { ... }        // 抽象接口（位于 api_client.dart 顶部）
class HttpFitLoopApi implements FitLoopApi { ... }  // 真实实现（也位于 api_client.dart）
```

所有网络请求通过 `_get()` / `_post()` 方法走 `dart:io HttpClient`（不是 `package:http`）。只在 `uploadAvatar` 一个地方用了 `http.MultipartRequest`（因为 dart:io 写 multipart 太麻烦）。

### 数据库

- 后端不跑时 App 无法登录/使用（没有本地数据库）
- 离线支持只在运动打卡 finish 时有效（SyncQueue 缓存待提交记录）
- 缓存 token + JSON 数据通过 `LocalCache`（SharedPreferences 封装）

## 你需要在修改前知道的红线

### 🔴 文件红线

| 不应修改 | 原因 |
|----------|------|
| `api_client.dart` 中已有的模型类 | 其它地方依赖它们 |
| `local_cache.dart` | 稳定的公共库 |
| `connectivity_service.dart` | 稳定的公共库 |
| `sync_queue.dart` | 稳定的公共库 |
| `reminder_scheduler.dart` | 稳定的公共库 |
| `stats_charts.dart` | 稳定的公共库 |
| `widget_test.dart` 中已存在的 mock 实现 | 8 个测试依赖它们 |
| `pubspec.yaml`（除非任务明确要求） | 需审查后修改 |
| 后端任何 `.java` 文件 | 仅在 Flutter 端工作 |
| `PLAN.md` | 项目规划文档 |

### 🔴 代码红线

- **不要删除、重命名或修改现有类/方法的签名**（只做增量添加）
- **不要引入 Provider/Riverpod/GetX 等状态管理框架**
- **不要修改 `AuthGate` 的构造函数参数**
- **不要在 `initState` 或 `build` 中调用 `setState` 异步操作后不检查 `mounted`**
- **所有用户可见文本用简体中文**
- **主题主色 `Color(0xFF1F8A70)`，不做额外配色方案**
- **所有新增 Widget 用 `const` 构造（只要可能）**

### 🔴 测试红线

- 修改 `widget_test.dart` 中的 `_MockApi` 时，只添加方法不删除/修改现有方法
- 运行 `flutter analyze` 确保 0 issue
- 运行 `flutter test` 确保 8/8 pass
- 不要修改 `backend/` 下的测试文件

## 工具分配关系

| 任务 | 你的产出来源 |
|------|------------|
| 任务 11 | `/tmp/FitLoop/task11_permissions_spec.md`（权限配置规范） |
| 任务 9 | `/tmp/FitLoop/task9_splash_onboarding_spec.md`（启动页+引导页规范）|

按顺序：先任务 11（15 分钟） → 再任务 9（~1 小时）。

## 测试命令

```bash
cd mobile
flutter pub get          # 首次或改 pubspec.yaml 后
flutter analyze           # 0 issues 是硬性要求
flutter test              # 8/8 pass 是硬性要求
```

## 提交流程

```bash
git add -A
git commit -m "feat: add splash screen and onboarding pages"
git push origin main
```
