# FitLoop 完整项目规划 v2.0 — 2026-05-27

> 基于三份官方文档（需求分析 → 概要设计 → 详细设计）+ 代码库现状检查，
> 面向**腾讯云部署**的中型 Android/iOS 移动应用。

---

## 1. 项目全景

```
FitLoop ── 运动打卡与健康管理平台
├── Frontend: Flutter (Android 8.0+ / iOS 13.0+)
├── Backend: Spring Boot 3.x (Java 17)
├── Database: MySQL 8.0 + Redis 6.0
├── Gateway: Nginx
├── Deployment: Docker Compose → Tencent Cloud CVM
└── CI/CD: GitHub Actions → 自动打包推送
```

---

## 2. 当前状态（已实现）

### ✅ 功能完成度 65%

| 领域 | 已实现 | 状态 |
|------|--------|------|
| **用户系统** | 手机号注册/登录、JWT 鉴权、头像上传、密码加密 | ✅ |
| **运动打卡** | GPS 轨迹打卡（跑步）、session 管理、卡路里 MET 计算 | ✅ |
| **目标管理** | 周/月目标创建、进度自动更新 | ✅ |
| **健康数据** | 体重录入、睡眠录入、饮食录入（UI 有，接口有） | ✅ |
| **数据统计** | 运动次数/时长/里程/卡路里图表、体重趋势、历史查询 | ✅ |
| **提醒通知** | 运动/久坐/喝水/睡眠提醒、本地推送 | ✅ |
| **社交基础** | 好友搜索/添加、好友列表、勋章、排行榜 | ✅ |
| **申诉系统** | 异常记录申诉、管理员审核 | ✅ |
| **用户体验** | 启动页、引导页、头像设置 | ✅ |
| **离线支持** | Token 缓存、本地缓存、离线打卡队列、自动同步 | ✅ |
| **权限配置** | CAMERA/STORAGE/LOCATION/NOTIFICATION | ✅ |

### ❌ 待实现

| 领域 | 缺失项 | 优先级 |
|------|--------|--------|
| **多打卡方式** | 传感器打卡（计步/跳绳）、拍照打卡、手动打卡 | **P0** |
| **多运动类型** | 骑行、健走、跳绳、自定义运动 | **P0** |
| **第三方登录** | 微信、QQ 登录 | **P1** |
| **社交进阶** | 班级/宿舍排行榜、运动挑战、动态 Feed | **P1** |
| **验证码系统** | 短信/邮箱验证码注册、验证码登录 | **P1** |
| **报告导出** | 个人周报/月报 PDF/Excel | P2 |
| **智能建议** | 基于运动画像的健康贴士推送 | P2 |
| **管理后台** | Web 管理面板（公告、数据、配置） | P2 |
| **WebSocket** | 排行榜/动态实时更新 | P3 |
| **iOS 构建** | 在 macOS 上完成 iOS 打包 | P3 |

---

## 3. 需求 vs 实现差距矩阵

参考需求文档中功能追踪矩阵 FR-01 ~ FR-08 逐一核验：

| 需求编号 | 需求名称 | 实现度 | 差距说明 |
|----------|---------|--------|---------|
| FR-01 | 账号注册登录 | 60% | 缺验证码流程、缺微信/QQ 第三方登录 |
| FR-02 | GPS 运动打卡 | 70% | 仅支持跑步，缺骑行/健走；缺传感器/拍照/手动三种打卡方式 |
| FR-03 | 传感器打卡 | 0% | 完全未实现 |
| FR-04 | 目标管理 | 100% | ✅ |
| FR-05 | 健康档案 | 80% | 数据录入有但缺周报/月报导出 |
| FR-06 | 智能提醒 | 90% | 本地提醒有，缺智能个性化建议推送（基于数据分析的 tips） |
| FR-07 | 校园激励 | 60% | 好友/勋章/排行榜有，缺班级/宿舍维度和挑战功能、缺社交动态流 |
| FR-08 | 异常申诉 | 100% | ✅ |
| — | 离线同步 | 100% | ✅（详设 TC-SPORT-002 场景已实现）|
| — | 启动页/引导页 | 100% | ✅ |

---

## 4. 腾讯云部署规划

### 4.1 推荐配置

| 资源 | 规格 | 预估月费 |
|------|------|----------|
| **CVM 云服务器** | 2核4G / 系统盘 50GB SSD / Ubuntu 22.04 | ≈ ¥120 |
| **MySQL 数据库** | 可选自建（省 ¥）或云数据库 1核1G 20GB | 自建¥0 / 云¥60 |
| **Redis** | 可选自建或云 Redis 256MB | 自建¥0 / 云¥30 |
| **CDN + COS** | 头像/打卡图片静态资源 | ≈ ¥10 |
| **域名** | .club / .cn 首年 | ≈ ¥30 |

**总额推荐：** 自建 MySQL+Redis ≈ **¥130/月**，上云数据库 ≈ **¥220/月**

### 4.2 架构拓扑

```
用户手机 ── HTTPS ──→ 腾讯云 CVM ──→ Docker Compose 集群
                          │
                    ┌─────┼─────────┐
                    │     │         │
                    ▼     ▼         ▼
                 Nginx  Backend   Static Files
                 :443   :8080     (COS/CDN)
                    │
                    ├── MySQL :3306 (Docker 内)
                    └── Redis :6379 (Docker 内)
```

### 4.3 部署步骤

| 步骤 | 动作 | 预计耗时 |
|------|------|----------|
| 1 | 腾讯云买 CVM，选 Ubuntu 22.04 LTS | 10 min |
| 2 | 安全组开放 22(SSH), 80(HTTP), 443(HTTPS), 8080(内网) | 5 min |
| 3 | SSH 登录，安装 Docker + Docker Compose | 10 min |
| 4 | git clone FitLoop 到服务器 | 2 min |
| 5 | 配置 .env 环境变量（JWT_SECRET, ADMIN_KEY, MySQL密码） | 5 min |
| 6 | docker compose up -d 启动所有服务 | 5 min |
| 7 | 配置 Nginx SSL（Let's Encrypt 免费证书） | 15 min |
| 8 | 域名 DNS 解析 → 服务器 IP | 5 min |
| 9 | 配置 COS/CDN 用于图片存储（可选） | 20 min |

**关键配置 .env：**

```bash
MYSQL_ROOT_PASSWORD=<strong-password>
MYSQL_PASSWORD=<strong-password>
FITLOOP_JWT_SECRET=<64-char-random-hex>
FITLOOP_ADMIN_KEY=<uuid>
SERVER_PORT=8080
```

### 4.4 额外部署注意事项

- **HTTPS 必须配置**（生产环境下，HTTP 明文传输 JWT token 和健康数据属于安全违规）
- **MySQL 数据持久化**：Docker volume 映射到宿主机路径，避免容器删除丢数据
- **日志轮转**：Docker 日志默认无限增长，需配置 logrotate 或 Docker 的 `--log-opt max-size=10m`
- **定期备份**：MySQL 每日 crontab dump 到 COS，保留最近 7 天
- **监控报警**：腾讯云自带的云监控（CPU > 80%、磁盘 > 90% 触发告警）

---

## 5. 分阶段开发路线图

### 阶段 1 — 补全核心打卡功能（P0，2-3 天）

| # | 任务 | 领域 | 工时 | 依赖 |
|---|------|------|------|------|
| 1.1 | 传感器打卡：集成 `sensor_plus` / `pedometer` 计步 + 跳绳检测 | Flutter | 4h | — |
| 1.2 | 多运动类型：骑行/健走/跳绳 UI + 后端接口兼容 | Flutter+Backend | 2h | 1.1 |
| 1.3 | 拍照打卡：运动时拍照上传 | Flutter | 2h | — |
| 1.4 | 手动打卡：手动填写运动数据 | Flutter | 1h | — |
| 1.5 | 验证码功能：SMS/邮箱验证码接口（先用邮箱模拟） | Backend+Flutter | 3h | — |

**验证：** flutter analyze / flutter test 通过 + 模拟器跑通四种打卡方式

### 阶段 2 — 校园社交增强（P1，2 天）

| # | 任务 | 领域 | 工时 |
|---|------|------|------|
| 2.1 | 班级/宿舍/社团排行榜维度 | Backend | 2h |
| 2.2 | 运动挑战功能（发起/加入/进度/奖励） | Backend+Flutter | 4h |
| 2.3 | 好友动态 Feed | Backend+Flutter | 3h |

### 阶段 3 — 第三方登录（P1，1 天）

| # | 任务 | 领域 | 工时 |
|---|------|------|------|
| 3.1 | 微信登录 SDK + OAuth 流程（需微信开放平台账号） | Flutter+Backend | 4h |
| 3.2 | QQ 登录 SDK + OAuth 流程 | Flutter+Backend | 3h |
| 3.3 | 多账号绑定 + 统一 User 模型 | Backend | 1h |

### 阶段 4 — 腾讯云部署 + DevOps（P1，1 天）

| # | 任务 | 领域 | 工时 |
|---|------|------|------|
| 4.1 | 购买 CVM + 配置 Docker 环境 | Ops | 0.5h |
| 4.2 | 配置 .env + docker compose up | Ops | 0.5h |
| 4.3 | 域名 + HTTPS + Nginx SSL | Ops | 1h |
| 4.4 | CI/CD：GitHub Actions 自动构建 Docker 镜像 + 推送 | Ops | 2h |
| 4.5 | 图片存储切换到 COS（取代本地文件系统） | Backend+Ops | 1h |

### 阶段 5 — iOS 构建 + 发布准备（P2，1 天）

| # | 任务 | 领域 | 工时 |
|---|------|------|------|
| 5.1 | macOS 上 flutter build ios 验证 | Build | 1h |
| 5.2 | iOS 证书 + App Store Connect 配置 | Ops | 2h |
| 5.3 | Android APK 签名 + Release 模式构建 | Build | 0.5h |

### 阶段 6 — 附加功能 + 质量提升（P2-P3，3 天）

| # | 任务 | 领域 | 工时 |
|---|------|------|------|
| 6.1 | 个人运动周报/月报生成 + PDF 导出 | Backend+Flutter | 3h |
| 6.2 | 智能健康建议（根据运动频率/体重的规则引擎） | Backend | 2h |
| 6.3 | WebSocket 实时排行/动态推送 | Backend+Flutter | 3h |
| 6.4 | 后端集成测试补充（SportController + AvatarController） | Backend | 0.5h |
| 6.5 | 错误边界完善 + 弱网体验优化 | Flutter | 2h |

### 阶段 7 — Web 管理后台（P2，2 天）

| # | 任务 | 领域 | 工时 |
|---|------|------|------|
| 7.1 | 管理员登录 + JWT 角色鉴权 | Backend | 1h |
| 7.2 | 用户管理列表 + 数据统计面板 | Backend | 2h |
| 7.3 | 公告发布 + 系统配置页面 | Backend | 2h |
| 7.4 | 异常记录审查 + 处理 | Backend | 1h |

---

## 6. 项目资源估算

### 6.1 整体工时预估

| 阶段 | 工时 | 主要工作 |
|------|------|---------|
| 1 — 核心打卡补全 | 12h | 传感器/拍照/手动打卡 + 多运动类型 + 验证码 |
| 2 — 社交增强 | 10h | 班级排行/挑战/动态 |
| 3 — 第三方登录 | 8h | 微信 + QQ SDK |
| 4 — 腾讯云部署 | 5h | CVM + Docker + HTTPS + CDN + CI/CD |
| 5 — iOS 构建 | 3.5h | macOS 构建 + 证书 |
| 6 — 功能附加 | 10.5h | 报告/建议/WebSocket/测试/优化 |
| 7 — 管理后台 | 6h | Web 管理面板 |
| **总计** | **~55h** | |

### 6.2 月份投入建议

| 周次 | 阶段 | 每日建议 |
|------|------|----------|
| 第 1 周 | 阶段 1（核心打卡） | 2h/天 ≈ 10h |
| 第 2 周 | 阶段 2（社交增强） | 2h/天 ≈ 10h |
| 第 3 周 | 阶段 3+4（登录+部署） | 2h/天 ≈ 10h |
| 第 4 周 | 阶段 5+6+7（收尾完善） | 2h/天 ≈ 10h |

---

## 7. 数据库变更计划

MySQL 当前表已覆盖需求，但以下扩展需要：

| 新表/修改 | 用途 | 所属阶段 |
|-----------|------|---------|
| `user_friend` 增加 `group_type` 字段 | 班级/宿舍分组 | 阶段 2 |
| `sport_challenge` 新表 | 挑战活动 | 阶段 2 |
| `challenge_participant` 新表 | 挑战参与记录 | 阶段 2 |
| `user_dynamic` 新表 | 好友动态流 | 阶段 2 |
| `sport_ranking` 增加 `scope_type` 字段 | 排行榜维度扩展 | 阶段 2 |
| `user_info` 增加 `openid_wechat` / `openid_qq` 字段 | 第三方登录 | 阶段 3 |
| `health_data` 增加 `image_url` 字段 | 健康数据附加图片 | 阶段 6 |
| `announcement` 新表 | 系统公告 | 阶段 7 |

---

## 8. 技术风险与应对

| 风险 | 概率 | 影响 | 应对 |
|------|------|------|------|
| 微信/QQ 登录需企业认证 | 高 | 高 | 先做邮箱验证码登录替代，第三方登录视为可裁剪特性 |
| iOS 构建需 macOS + 99$ 开发者账号 | 高 | 中 | 优先打包 Android APK，iOS 用 TestFlight 邀请测试 |
| 传感器计步精度不够 | 中 | 中 | 降级为粗略步数统计+手动校准 |
| 腾讯云部署被攻击 | 低 | 高 | 最小端口开放、fail2ban、WAF（Web 应用防火墙） |
| 需求文档中的班级/宿舍功能需后端修改 | 中 | 低 | 当前社交模块设计已预留扩展点 |

---

## 9. 提交策略

```
格式: feat(scope): 简短描述
scope: mobile / backend / deploy
示例:
  feat(mobile): add step counter sensor check-in
  feat(backend): add class ranking dimension
  fix(mobile): handle weak GPS accuracy gracefully
  feat(deploy): add docker compose for Tencent Cloud
```

**规范：**
- 每次提交前必须跑 `flutter analyze && flutter test`（前端）或 `mvn test`（后端）
- 每个阶段完成一次 git push
- 推送前确认 CI 通过（GitHub Actions 自动跑）

---

## 10. 推荐的下一步执行顺序

### 🔥 立即开干（从今天开始）

```mermaid
graph LR
    A[阶段1: 多打卡方式] --> B[阶段4: 腾讯云部署]
    B --> C[阶段2: 社交增强]
    C --> D[阶段3: 第三方登录]
    D --> E[阶段6: 附加功能]
    E --> F[阶段7: 管理后台]
    F --> G[阶段5: iOS构建]
```

**理由：** 多打卡方式是需求文档的核心功能（FR-02 包括四种打卡方式），当前只实现了 GPS 一种，是最大的功能性缺口。腾讯云部署早做可以提前暴露线上问题。

---

## 附录 A：项目文件目录

```
FitLoop/
├── .github/workflows/ci.yml          # CI/CD
├── backend/
│   ├── Dockerfile                     # 后端容器化
│   ├── pom.xml
│   └── src/main/java/com/fitloop/
│       ├── appeal/                    # 申诉模块
│       ├── common/                    # 通用（ApiResponse）
│       ├── security/                  # JWT + SecurityConfig
│       ├── social/                    # 社交模块
│       ├── sport/                     # 运动打卡核心
│       ├── stats/                     # 统计 + 健康数据
│       ├── target/                    # 目标管理
│       └── user/                      # 用户 + 头像
├── deploy/
│   ├── docker-compose.yml            # 生产部署
│   ├── nginx.conf                    # Nginx 配置
│   └── .env.example                  # 环境变量模板
├── mobile/
│   ├── lib/
│   │   ├── main.dart                 # 入口 + 所有页面
│   │   ├── api_client.dart           # API 接口层
│   │   ├── connectivity_service.dart # 网络探测
│   │   ├── local_cache.dart          # 本地缓存
│   │   ├── onbording_screen.dart     # 引导页
│   │   ├── reminder_scheduler.dart   # 通知调度
│   │   ├── splash_screen.dart        # 启动页
│   │   ├── stats_charts.dart         # 图表组件
│   │   └── sync_queue.dart           # 离线同步队列
│   ├── test/widget_test.dart         # 9 tests
│   └── pubspec.yaml
├── task8_avatar_ui_spec.md
├── task9_splash_onboarding_spec.md
├── task11_permissions_spec.md
├── task12_backend_tests_spec.md
├── STATUS.md
├── CLAUDE_CONTEXT.md
└── PLAN.md
```
