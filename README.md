# FitLoop

> 面向高校学生的运动打卡与健康管理应用，也是一个用于求职展示的 Java + Spring + Agent 工程实践项目。仓库包含 Flutter 移动端、Spring Boot 后端、受控 Agent 服务、自动化测试与 Docker Compose 配置。

![FitLoop 产品展示图](mobile/assets/ai_generated/readme_hero_mockup.png)

当前仓库包含已部署的受控发布版本 `0.1.12+14`，重点展示 Java 业务建模、安全鉴权、异步 Agent 编排、工具权限、Human-in-the-loop 和工程化交付。公网部署是带日期的运行快照，不替代本地可复现测试；准确版本、产物哈希、回滚锚和限制见 [当前发布状态](docs/RELEASE_STATUS.md)。

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

最近一次发布与修复的精确测试证据记录在 [当前发布状态](docs/RELEASE_STATUS.md)。其中申诉确认修复的合并前源码树通过 203 项后端单元测试、4 项 Testcontainers 集成测试和 JaCoCo 门禁；该数字是对应提交的快照，不代表后续任意工作树自动通过。CI、生产部署和真机验收必须分别记录，不能相互替代。

## 可选部署能力

作品集演示可以全部在本地完成，不依赖公网。当前固定公网 IP 的 HTTPS
下载与 API 快照见 [当前发布状态](docs/RELEASE_STATUS.md)；新环境或下一次
发布仍须按 [部署与运维指南](docs/DEPLOYMENT.md) 重新核验 TLS、监控、备份
和回滚门禁。旧的固定 IP HTTPS 迁移过程保留在
[历史发布补充手册](docs/IP_HTTPS_RELEASE_RUNBOOK.md) 中，仅作参考。

APK 二进制不再进入 Git。发布产物必须附带 SHA-256，服务器通过 `deploy/install-apk.sh` 校验并原子替换，并保留上一版本用于回滚。本周期不改写 Git 历史。

## 当前状态与边界

- `0.1.12+14` 已通过服务器 `verify-only`、真机覆盖安装与激活前冒烟，并已原子激活为 HTTPS 公网下载产物；哈希、大小、服务器提交和回滚锚见 [当前发布状态](docs/RELEASE_STATUS.md)。
- Agent 申诉人工确认修复已合入并部署；真机确认不再误报“登录状态已过期”，申诉决策可成功落库。模型只提供结构化建议，最终写入仍由 Spring 鉴权、事务和人工确认控制。
- 地图细节、定位纠偏、配速展示和运动记录详情已进入 `0.1.12+14`；其长期定位精度和设备兼容性仍需持续真机采样，不能由一次冒烟概括。
- Release 默认使用 HTTPS，Android 生产 manifest 禁止任意明文流量。HTTP 兼容入口的最新开关未在本次文档更新中重新验证，不能据此宣称已经关闭。
- 生产备份和回滚锚已建立，但本次没有执行数据库恢复演练；任何恢复或回滚仍需单独授权。
- 正式 keystore 的创建、离线备份和签名切换尚未完成，不能宣称正式生产签名完成。
- 当前公开渠道是服务器 HTTPS 下载端点，尚未创建 Git tag、GitHub Release 或应用商店发布记录；仍不包含 iOS 正式构建。

## 文档

- [系统架构与 Agent 时序](docs/ARCHITECTURE.md)
- [当前生产发布状态（2026-09-07）](docs/RELEASE_STATUS.md)
- [部署与运维指南](docs/DEPLOYMENT.md)
- [Agent 可重复演示](docs/AGENT_DEMO.md)
- [历史：0.1.7+8 人工发布执行手册](docs/MANUAL_RELEASE_RUNBOOK.md)
- [历史：0.1.7+8 固定公网 IP HTTPS 补充手册](docs/IP_HTTPS_RELEASE_RUNBOOK.md)
- [历史：0.1.7+8 Android 真机冒烟清单](docs/SMOKE_TEST_CHECKLIST.md)
- [协作与提交规范](CONTRIBUTING.md)
