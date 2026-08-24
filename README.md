# FitLoop

> 面向高校学生的运动打卡与健康管理应用，也是一个用于求职展示的 Java + Spring + Agent 工程实践项目。仓库包含 Flutter 移动端、Spring Boot 后端、受控 Agent 服务、自动化测试与 Docker Compose 配置。

![FitLoop 产品展示图](mobile/assets/ai_generated/readme_hero_mockup.png)

当前定位是“可本地运行、可自动验证、可现场演示”的作品集版本 `0.1.7+8`，重点展示 Java 业务建模、安全鉴权、异步 Agent 编排、工具权限、Human-in-the-loop 和工程化交付。公网域名、备案、正式证书与应用商店发布不是完成本项目演示的前置条件。

## 技术栈

| 层级 | 技术 |
| --- | --- |
| 移动端 | Flutter 3 / Dart、`http`、`flutter_secure_storage`、`geolocator`、`pedometer`、`image_picker`、`flutter_local_notifications`、`fl_chart` |
| 后端 | Java 21、Spring Boot 4.1、Spring Security、JWT、Spring Data JPA/Redis、Flyway、Actuator、Micrometer |
| Agent | Python 3.12、FastAPI、OpenAI Agents SDK、DeepSeek、Redis Streams |
| 数据 | MySQL 8.0、Redis 6.2 |
| 部署 | Docker Compose、Nginx、TLS 1.2/1.3 |
| 测试 | JUnit 5、Testcontainers、pytest、Flutter Test、JaCoCo |

## 主要能力

- 密码或验证码登录、刷新令牌轮换、安全存储、主动刷新与并发 401 单次重放。
- GPS、计步、拍照和手动运动打卡，离线结束队列与异常记录申诉。
- 周/月目标、健康数据、统计趋势、本地提醒、好友与排行榜。
- 管理员用户、反馈、申诉、审计和 Agent 审核链路。
- DeepSeek 教练与申诉审批双 Agent：强制读取结构化证据、Pydantic 本地校验、风险护栏和人工确认。
- Agent 独立 readiness 与可降级部署；Agent 故障不阻塞核心 API 和 APK 下载。

## 项目结构

```text
FitLoop/
├── backend/              # Java 21 / Spring Boot API
├── mobile/               # Flutter Android 应用
│   └── lib/features/     # 认证、首页、运动、统计、社交、AI 教练、个人中心、后台管理
├── agent-service/        # Python Agent worker 与内部健康检查
├── deploy/               # Compose、Nginx、TLS、发布与监控脚本
├── docs/                 # 架构、演示、部署与验证文档
└── .github/workflows/    # CI 门禁
```

## 本地开发

环境要求：Java 21、Maven 3.9+、Flutter stable、Python 3.12；运行容器集成测试和完整 Compose 时还需要 Docker。

后端：

```powershell
cd backend
mvn --batch-mode --settings ../.github/maven-settings.xml verify
mvn spring-boot:run
```

Agent：

```powershell
cd agent-service
python -m pip install -e ".[test]"
python -m compileall -q src tests
python -m pytest
```

真实 DeepSeek 演示（会消耗少量 API 额度，不会输出密钥）：

```powershell
cd ..
$env:PYTHONUTF8="1"
$env:PYTHONPATH=(Resolve-Path .\agent-service\src).Path
python -m fitloop_agent.demo --env-file .env --mode all --confirm-live-api
```

该命令分别执行教练和申诉审批工作流，并校验模型确实调用了必要证据工具。完整说明见 [Agent 可重复演示](docs/AGENT_DEMO.md)。

完整容器 E2E（不读取 `.env`、不调用真实 DeepSeek、不修改现有本地数据）：

```powershell
cd D:\AIWorkspace\projects\FitLoop
powershell -ExecutionPolicy Bypass -File .\scripts\run-agent-e2e.ps1
```

该命令启动独立 MySQL、Redis、Spring Boot、Agent Worker 和 OpenAI Chat Completions 兼容模型桩，真实验证 Redis Stream、委托令牌、内部工具审计、教练用户确认、申诉管理员确认与最终领域数据变更，结束后自动删除隔离容器和数据卷。

移动端：

```powershell
cd mobile
flutter pub get
flutter analyze
flutter test
flutter run --dart-define=FITLOOP_API_BASE_URL=http://10.0.2.2:8080
```

Release 默认 API 为 `https://43.139.72.25`；生产 Android manifest 默认禁止任意明文流量。本地调试仍可用 `http://10.0.2.2` / 局域网 IP；仅经明确批准的短期 HTTP 过渡包才可使用 `deploy/build-apk.ps1 -AllowInsecureHttpTransitionRelease`。

如需演示 Android Release 构建，可使用以下命令。公网发布时 API 必须使用 HTTPS；本地求职演示不要求注册域名：

```powershell
powershell -ExecutionPolicy Bypass -File deploy/build-apk.ps1 `
  -ApiBaseUrl https://your-domain.example `
  -SigningMode Compatibility
```

## 配置与秘密

部署变量模板位于 `deploy/.env.example`。JWT、验证码哈希、SMTP 授权码、DeepSeek Key、Agent 服务密钥和 Android 签名材料只能通过未跟踪的环境变量或秘密存储提供。

移动端正式签名需要以下四个变量，缺少任何一个时正式构建都会失败：

- `FITLOOP_RELEASE_STORE_FILE`
- `FITLOOP_RELEASE_STORE_PASSWORD`
- `FITLOOP_RELEASE_KEY_ALIAS`
- `FITLOOP_RELEASE_KEY_PASSWORD`

正式 keystore 尚未启用。本周期公开 APK 如获批准，只能在签名证书与已发布 APK 指纹一致时继续兼容升级；任何正式签名切换都需要单独的卸载重装方案和公告。

## 测试与 CI

CI 执行以下门禁：

- 后端 `verify`、JaCoCo 覆盖率门禁及 Docker/Testcontainers 集成测试。
- Agent 包编译和 pytest。
- 隔离容器内的教练与申诉审批系统 E2E。
- Flutter analyze、test 和 Android release 编译。
- Shell 语法与基础/TLS/Agent E2E Compose 配置校验。
- Pull Request 高危依赖审查。

`origin/main` @ `3e48671`（合并 PR #29）的 GitHub Actions 快照：后端 Surefire 188 项、Failsafe 4 项，全部通过且 JaCoCo 门禁通过；Agent pytest 36 项通过；Flutter 63 项通过；隔离容器 Agent E2E 通过。测试声明数量与最近一次实际执行结果应分开记录，避免把历史基线误报为本次全部通过。教练与申诉审批已使用真实 DeepSeek V4 模型完成模型层演示。

## 可选部署能力

作品集演示可以全部在本地完成，不需要域名。若以后决定公网展示，再按
[部署与运维指南](docs/DEPLOYMENT.md) 配置域名或固定公网 IP、TLS、监控与
发布流程；固定公网 IP 使用
[IP HTTPS 发布补充手册](docs/IP_HTTPS_RELEASE_RUNBOOK.md)。

APK 二进制不再进入 Git。发布产物必须附带 SHA-256，服务器通过 `deploy/install-apk.sh` 校验并原子替换，并保留上一版本用于回滚。本周期不改写 Git 历史。

## 当前状态与边界

- `0.1.7+8` 仍是作品集候选版本。Gate 0B 相关安全修复已合入 `main`（PR #23–#29）：生产占位密钥 fail-closed 与 backend loopback、Release 默认 HTTPS / 禁止任意 cleartext、密码最小长度、可信代理下的 `X-Forwarded-For`、运动照片魔数校验、Agent 409 等价复用，以及 OTP 失败尝试在回滚后仍可持久计数。
- AI 教练训练计划确认后查看、计划列表与详情已在更早 PR 合入；Agent 真实模型演示使用固定脱敏证据；隔离容器 E2E 覆盖 Spring、Redis、Worker、工具审计和人工确认。
- 仓库代码侧 Release 路径默认走 HTTPS；仅显式授权的 HTTP 过渡构建可临时放行明文。公网是否已完成证书挂载、Backend/APK 是否已与当前 `main` 对齐，必须以服务器与发布记录复核为准，不能用仓库默认值代替部署证据。
- Gate 0C 发布证据尚未完成：正式签名、兼容升级、真机冒烟、备份/恢复与原子回滚、HTTPS 或书面锁定的 HTTP 过渡结束条件，均需按 [人工发布执行手册](docs/MANUAL_RELEASE_RUNBOOK.md) 留存脱敏证据后，才能称为发布候选或已上线。
- 正式 keystore 的创建、离线备份和签名切换尚未完成，不能宣称正式生产签名完成。
- 当前已包含普通用户 AI 教练 UI 与训练计划确认/拒绝流程；仍不包含 iOS 正式构建、数据库重构或 Git 历史重写。Gate 0 完成前不扩展社交展示类功能。

## 文档

- [系统架构与 Agent 时序](docs/ARCHITECTURE.md)
- [部署与运维指南](docs/DEPLOYMENT.md)
- [固定公网 IP HTTPS 发布补充手册](docs/IP_HTTPS_RELEASE_RUNBOOK.md)
- [Agent 可重复演示](docs/AGENT_DEMO.md)
- [0.1.7+8 人工发布执行手册](docs/MANUAL_RELEASE_RUNBOOK.md)
- [Android 真机冒烟清单](docs/SMOKE_TEST_CHECKLIST.md)
- [协作与提交规范](CONTRIBUTING.md)
