# FitLoop 项目状态（2026-05-27 收盘）

## GitHub HEAD: `b903b09` — Task 9 启动页+引导页 完毕

### 全部 12 项原始任务状态

| # | 任务 | 状态 | Commit |
|---|------|------|--------|
| 1 | GPS 实时定位 | ✅ | f00d78f |
| 2 | 运动结果页 | ✅ | f00d78f |
| 3 | 本地缓存 + 离线同步 | ✅ | b263343 / 386f5aa |
| 4 | 本地通知 | ✅ | b4b0318 |
| 5 | 图表可视化 | ✅ | b4b0318 |
| 6 | 好友添加 UI | ✅ | b4b0318 |
| 7 | 申诉提交 UI | ✅ | b4b0318 |
| 8 | 头像上传 UI | ✅ | b12bdfc |
| 9 | 启动页 + 引导页 | ✅ | b903b09 |
| 10 | 依赖审查清理 | ✅ | 实际已完善，无 bloat 包 |
| 11 | Android/iOS 权限配置 | ✅ | 578297e |
| 12 | 后端集成测试补充 | 🔶 部分 | 47 tests / 9 files，缺 SportController + AvatarController |

### 测试覆盖率概况

**前端：** 9 widget tests，`flutter analyze` 0 issues ✅
**后端：** 47 @Test / 9 文件，`mvn test` 全通过 ✅

### 缺失项

| 缺失 | 影响 |
|------|------|
| SportController 控制器层测试 | 低（SportService 核心逻辑已由上游测试覆盖） |
| AvatarController 控制器层测试 | 低（文件上传测试需要 multipart 模拟，较复杂） |
| iOS 实际编译验证 | 中（当前无 macOS 构建环境，留待 CI/CD 阶段） |
| CI/CD pipeline | 中（已有 .github/workflows/ci.yml，需调整完善） |

## 领域架构快照

```
mobile/lib/
├── api_client.dart            # Api 接口抽象 + HttpFitLoopApi 实现
├── connectivity_service.dart  # 网络探测（纯 dart:io）
├── local_cache.dart           # Token + 数据缓存
├── main.dart                  # 入口、AuthGate、AppShell、5 个 Page
├── onboarding_screen.dart     # 引导页（3 页轮播）
├── reminder_scheduler.dart    # 本地通知调度
├── splash_screen.dart         # 启动页
├── stats_charts.dart          # 图表组件
└── sync_queue.dart            # 离线同步队列

backend/
├── appeal/     ✅ 2 tests
├── reminder/   ✅ 12 tests
├── social/     ✅ 8 tests
├── sport/      ⚠️ 2 tests（仅 CalorieCalculatorTest，缺 ApiController 测试）
├── stats/      ✅ 10 tests（StatsServiceTest + StatsHistoryTest）
├── target/     ✅ 1 test
├── user/       ✅ 11 tests
└── FitLoopApiIntegrationTest.java  ✅ 1 test
```

## 下一步建议

### 选项 A：补后端测试（推荐，1-2h）

SportController + AvatarController 的 controller 层集成测试，用 `@WebMvcTest` + MockMvc + `@MockBean` Service。

### 选项 B：CI/CD 完善（1h）

调整 `.github/workflows/ci.yml`，后端跑的 `mvn test` 需要 MySQL（H2 已配 test profile），前端 `flutter analyze/test` 需要 Flutter SDK（GitHub Actions 原生支持）。

### 选项 C：iOS 构建

需要 macOS 环境 + Xcode，当前不可行，建议上 CI 后自动构建。

### 选项 D：功能迭代

- 在线运动好友实时追踪
- 运动路线地图回放
- 社交动态流（Feed）

---

**建议：先选项 A（1h 搞定），然后项目从「功能开发」进入「运维完善」阶段。**
