# FitLoop

> 面向高校学生的运动打卡与健康管理应用，也是一个用于求职展示的 Java + Spring + Agent 工程实践项目。仓库包含 Flutter 移动端、Spring Boot 后端、受控 Agent 服务、自动化测试与 Docker Compose 配置。

![FitLoop 产品展示图](mobile/assets/ai_generated/readme_hero_mockup.png)

当前定位是“可本地运行、可自动验证、可现场演示”的作品集版本 `0.1.6+7`，重点展示 Java 业务建模、安全鉴权、异步 Agent 编排、工具权限、Human-in-the-loop 和工程化交付。公网域名、备案、正式证书与应用商店发布不是完成本项目演示的前置条件。

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
│   └── lib/features/     # 认证、首页、运动、统计、社交、个人中心、后台管理
├── agent-service/        # Python Agent worker 与内部健康检查
├── deploy/               # Compose、Nginx、TLS、发布与监控脚本
├── docs/                 # 部署和真机冒烟清单
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

当前基线：后端 154 项单元/切片测试和 2 项 MySQL/Testcontainers 集成测试通过，JaCoCo 覆盖率门禁通过；Agent 18 项测试通过；Flutter 31 项测试和静态分析通过。教练与申诉审批已使用真实 DeepSeek V4 模型完成模型层演示，且两条完整应用链路已通过隔离容器 E2E。

## 可选部署能力

作品集演示可以全部在本地完成，不需要域名。若以后决定公网展示，再按 [部署与运维指南](docs/DEPLOYMENT.md) 配置域名、TLS、监控与发布流程。

APK 二进制不再进入 Git。发布产物必须附带 SHA-256，服务器通过 `deploy/install-apk.sh` 校验并原子替换，并保留上一版本用于回滚。本周期不改写 Git 历史。

## 当前状态与边界

- `0.1.6+7` 作为作品集候选版本继续开发；本次开发没有执行 push、部署或 APK 发布。
- Agent 真实模型演示使用固定脱敏证据验证模型、工具调用、结构化输出和护栏；隔离容器 E2E 验证 Spring、Redis、Worker、工具审计和人工确认的完整链路。
- TLS、证书到期监控和 Agent 降级配置保留为工程能力展示；只有公网部署时才需要实际域名和证书。
- 正式 keystore 的创建、离线备份和签名切换尚未完成，不能宣称正式生产签名完成。
- 当前不包含普通用户 AI 教练 UI、iOS 正式构建、数据库重构、验证码重做或 Git 历史重写。

## 文档

- [部署与运维指南](docs/DEPLOYMENT.md)
- [Agent 可重复演示](docs/AGENT_DEMO.md)
- [面试讲解指南](docs/INTERVIEW_GUIDE.md)
- [0.1.6+7 人工发布执行手册](docs/MANUAL_RELEASE_RUNBOOK.md)
- [Android 真机冒烟清单](docs/SMOKE_TEST_CHECKLIST.md)
- [协作与提交规范](CONTRIBUTING.md)
