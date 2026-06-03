# FitLoop 项目状态（2026-06-03）

## GitHub HEAD: `989a240` — Sprint B 账号与目标稳定化进行中

### Sprint B 进展

| 任务 | 状态 |
|------|------|
| ✅ 验证码策略收口（内测回显/邮箱真实发送/生产手机禁用） | ✅ 已完成 |
| ✅ 目标删除（软删除 + 权限保护） | ✅ 已完成 |
| ✅ 目标创建体验整理 | ✅ 已完成 |
| ✅ 头像更换 .jpg/.jpeg 识别修正（文件头校验） | ✅ 已完成 |
| ✅ 注册/登录/验证码登录/重置密码提示文案 | ✅ 已完成 |
| ✅ 后端测试补充（TargetService + AvatarController） | ✅ 已完成 |
| ✅ 文档状态同步 | ✅ 已完成 |

### 验证码策略说明

- **手机验证码：** 当前无真实短信服务，采用"内测验证码回显"方案。
  - local/test/demo/staging 环境：开启 `FITLOOP_OTP_DEBUG_RETURN=true`，接口返回 `debugCode`，App 显示"内测验证码：xxxxxx"。
  - 生产环境：`FITLOOP_OTP_DEBUG_RETURN=false`，手机通道返回明确错误"手机短信通道暂未开放，请使用邮箱验证码"。
  - 验证码仍是随机生成、5 分钟过期、一次性使用、有频率限制，不是固定万能码。
- **邮箱验证码：** 通过 SMTP 真实发送，需配置 `spring.mail.*` 环境变量。未配置时返回"邮箱服务未配置"。
- **未来扩展：** 接入腾讯云短信/阿里云短信后，替换 `PhoneVerificationCodeSender` 实现即可。

### 头像上传说明

- 后端通过文件头（magic bytes）识别图片类型：JPEG 识别 `FF D8 FF`，PNG 识别 `89 50 4E 47`。
- 不单独依赖 MIME 类型或文件扩展名，避免 Android 相册返回空 MIME 或非标准 MIME 导致误判。
- 支持 `.jpg`、`.jpeg`、`.png` 格式。
- 合法 `.jpg` 文件不会被误报"请上传图片文件"。
- 伪装扩展名的非图片文件（如 `.txt` 改 `.jpg`）会被拒绝。

### Git 概况

| 项目 | 值 |
|------|-----|
| **Commit 总数** | 50 |
| **远程同步** | ✅ `origin/main` 已同步 |
| **当前分支** | `main` |

### 项目结构

```
FitLoop/
├── backend/              # Spring Boot 模块化单体后端
│   └── src/test/java/com/fitloop/  15 个测试文件
│       ├── FitLoopApiIntegrationTest.java
│       ├── appeal/AppealServiceTest.java
│       ├── reminder/ReminderServiceTest.java
│       ├── social/SocialServiceTest.java
│       ├── sport/CalorieCalculatorTest.java
│       ├── sport/SportServiceTest.java
│       ├── stats/StatsHistoryTest.java
│       ├── stats/StatsServiceTest.java
│       ├── target/TargetServiceTest.java          ← 删除测试
│       ├── user/AvatarControllerTest.java          ← 新增（头像上传测试）
│       ├── user/SmsServiceTest.java
│       ├── user/UserControllerTest.java
│       ├── user/UserServiceTest.java
│       ├── user/VerificationCodeServiceTest.java
│       └── user/VerificationControllerTest.java    ← 更新（消息文案）
├── mobile/               # Flutter 移动端应用
│   └── test/widget_test.dart  (9 widget tests)
├── deploy/               # Docker Compose、Nginx、环境变量模板
├── .github/workflows/    # CI 配置
```

### 后端模块

| 模块 | 测试数 | 状态 |
|------|--------|------|
| sport/ | 2 files | ✅ CalorieCalculator + SportService |
| stats/ | 2 files | ✅ StatsService + StatsHistory |
| user/ | 6 files | ✅ UserService + SmsService + UserController + VerificationCodeService + VerificationController + AvatarController |
| reminder/ | 1 file | ✅ 12 tests |
| social/ | 1 file | ✅ 8 tests |
| appeal/ | 1 file | ✅ 2 tests |
| target/ | 1 file | ✅ 7 tests（含删除） |
| integration | 1 file | ✅ 1 test |
| **合计** | **15 files（89 测试）** | ✅ |

### 前端模块

```
mobile/lib/
├── api_client.dart            # 20+ API 封装（含 deleteTarget、_delete 方法）
├── connectivity_service.dart  # 网络探针
├── local_cache.dart           # Token + 数据缓存
├── main.dart                  # 入口、AuthGate、AppShell、所有页面（目标删除、验证码文案）
├── onboarding_screen.dart     # 3 页引导轮播
├── reminder_scheduler.dart    # 4 类本地通知
├── splash_screen.dart         # Logo 淡入启动页
├── stats_charts.dart          # 4 面板图表
└── sync_queue.dart            # 离线同步队列
```

### 未解决项

| 项 | 优先级 | 说明 |
|----|--------|------|
| GPS 地图轨迹展示 | P1 | Sprint C 计划 |
| 拍照打卡文件校验复用 | P1 | Sprint C 计划 |
| 邮箱 SMTP 生产配置 | P1 | 需配置授权码 |
| iOS 构建 | 中 | 需 macOS + Xcode |
| CI/CD pipeline 完善 | 中 | `.github/workflows/ci.yml` 已存在 |

### 下一步建议

| 选项 | 工时 | 说明 |
|------|------|------|
| **Sprint C：运动体验增强** | ~5-7h | GPS 地图轨迹、拍照校验 |
| **Sprint D：设置与反馈闭环** | ~3-5h | 反馈入口、注销、设置整理 |
| **阶段 2：腾讯云部署** | ~5h | CVM + Docker Compose + HTTPS |

---

*文档版本 2026-06-03 — HEAD `989a240`，Sprint B 进行中，15 后端测试文件，89 测试全通过*
