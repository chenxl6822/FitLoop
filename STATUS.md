# FitLoop 项目状态（2026-05-31）

## GitHub HEAD: `3c3c654` — Sprint A 内测稳定化进行中

### Sprint A 进展

| 任务 | 状态 |
|------|------|
| ✅ `GET /api/user/profile` 端点 | ✅ 新增 Controller + Service + 测试 |
| ✅ Nginx `/uploads/` 代理 | ✅ nginx.conf / nginx.ssl.conf |
| ✅ Docker uploads volume | ✅ docker-compose.yml + application.yml |
| ✅ 端口安全（127.0.0.1 绑定） | ✅ MySQL/Redis ports 加固 |
| 🚀 真机冒烟测试 | 待验证 |
| 🚀 下载页版本号 | 待补充 |

### 阶段 1 完成清单（补全打卡方式 + 多运动类型 + 验证码）

### 阶段 1 完成清单（补全打卡方式 + 多运动类型 + 验证码）

| 需求 | 状态 | Commit |
|------|------|--------|
| ✅ GPS 打卡 | ✅ 已有 | `ad121b5` |
| ✅ **传感器打卡（计步/跳绳）** | ✅ 新增 | `318125f` |
| ✅ **拍照打卡** | ✅ 新增 | `764efb8` |
| ✅ **手动打卡** | ✅ 新增 | `507ddf5` |
| ✅ 5 种运动类型（跑步/骑行/健走/跳绳/自定义） | ✅ 新增 | `f85ffd0` |
| ✅ **手机验证码注册** | ✅ 新增 | `8fad57b` + `bc27195` |
| ✅ 阶段 1 测试补充 | ✅ 新增 | `bc27195` |

### Git 概况

| 项目 | 值 |
|------|-----|
| **Commit 总数** | 36（原始 11 + 阶段 1 新增 24 + Sprint A 新增 1） |
| **远程同步** | ✅ `origin/main` 已同步 |
| **未提交修改** | ✅ 无 |
| **跟踪文件数** | 163 |
| **仓库清理** | ✅ 删除 8 个非项目文件，`.gitignore` 加固 |

### 项目结构

```
FitLoop/
├── backend/              # Spring Boot 模块化单体后端
│   └── src/test/java/com/fitloop/  11 个测试文件
│       ├── FitLoopApiIntegrationTest.java
│       ├── appeal/AppealServiceTest.java
│       ├── reminder/ReminderServiceTest.java
│       ├── social/SocialServiceTest.java
│       ├── sport/CalorieCalculatorTest.java
│       ├── sport/SportServiceTest.java          ← 新增（传感器/手动打卡测试）
│       ├── stats/StatsHistoryTest.java
│       ├── stats/StatsServiceTest.java
│       ├── target/TargetServiceTest.java
│       ├── user/SmsServiceTest.java             ← 新增（验证码测试）
│       ├── user/UserControllerTest.java          ← 新增（Sprint A Controller 测试）
│       └── user/UserServiceTest.java
├── mobile/               # Flutter 移动端应用
│   └── test/widget_test.dart  (9 widget tests)
├── deploy/               # Docker Compose、Nginx、环境变量模板
├── .github/workflows/    # CI 配置
```

### 后端模块

| 模块 | 测试数 | 状态 |
|------|--------|------|
| sport/ | 2 files | ✅ CalorieCalculator + SportService（含新打卡模式） |
| stats/ | 2 files | ✅ StatsService + StatsHistory |
| user/ | 3 files | ✅ UserService + SmsService + UserController（Sprint A 新增） |
| reminder/ | 1 file | ✅ 12 tests |
| social/ | 1 file | ✅ 8 tests |
| appeal/ | 1 file | ✅ 2 tests |
| target/ | 1 file | ✅ 1 test |
| integration | 1 file | ✅ 1 test |
| **合计** | **12 files** | ✅ |

### 前端模块

```
mobile/lib/
├── api_client.dart            # 20+ API 封装（含 sms/send, sport/photo, 多运动类型）
├── connectivity_service.dart  # 网络探针
├── local_cache.dart           # Token + 数据缓存
├── main.dart                  # 入口、AuthGate、AppShell、所有页面（含多运动选择、4 种打卡）
├── onboarding_screen.dart     # 3 页引导轮播
├── reminder_scheduler.dart    # 4 类本地通知
├── splash_screen.dart         # Logo 淡入启动页
├── stats_charts.dart          # 4 面板图表
└── sync_queue.dart            # 离线同步队列（字段修复）
```

### 未解决项

| 项 | 优先级 | 说明 |
|----|--------|------|
| SportController 控制器层测试 | 低 | 核心逻辑已被 SportServiceTest 覆盖 |
| AvatarController 控制器层测试 | 低 | 文件上传测试需模拟 multipart |
| iOS 构建 | 中 | 需 macOS + Xcode，建议 CI 后处理 |
| CI/CD pipeline 完善 | 中 | `.github/workflows/ci.yml` 已存在，需调整 |

### 下一步建议

| 选项 | 工时 | 说明 |
|------|------|------|
| **阶段 2：腾讯云部署** | ~5h | CVM + Docker Compose + HTTPS，上线可用 |
| 补 Controller 测试 | ~1-2h | `@WebMvcTest` + `MockMvc` |
| 阶段 3：社交增强 | ~10h | 排行榜维度、挑战、动态 Feed |

---

*文档版本 2026-05-31 — HEAD `3c3c654`，Sprint A 进行中，12 后端测试文件，60 测试全通过*
