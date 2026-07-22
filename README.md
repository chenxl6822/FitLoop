# FitLoop

> 面向高校学生的运动打卡与健康管理应用。仓库包含 Flutter 移动端、Spring Boot 后端、受控 Agent 服务、自动化测试与 Docker Compose 部署配置。

![FitLoop 产品展示图](mobile/assets/ai_generated/readme_hero_mockup.png)

当前开发目标是生产稳定过渡版 `0.1.6+7`。代码已具备账号、运动、目标、统计、提醒、社交、申诉、后台审核和 Agent 审核闭环；该版本尚未执行公网发布或生产部署。

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

移动端：

```powershell
cd mobile
flutter pub get
flutter analyze
flutter test
flutter run --dart-define=FITLOOP_API_BASE_URL=http://10.0.2.2:8080
```

生产 APK 必须注入 HTTPS 地址。兼容签名只用于本周期延续现有安装链，不能当作正式生产签名：

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
- Flutter analyze、test 和 Android release 编译。
- Shell 语法与基础/TLS Compose 配置校验。
- Pull Request 高危依赖审查。

当前本地基线：后端 152 项测试通过、JaCoCo 行覆盖率 82.9%；Agent 7 项测试通过；Flutter 31 项测试和静态分析通过。Docker/Testcontainers 仍以 CI 结果为准。

## 部署与发布

详见 [部署与运维指南](docs/DEPLOYMENT.md)。发布顺序固定为：TLS 与兼容后端 → 验证核心服务和 Agent 降级 → 构建并校验 APK → 安装外部产物 → 真机冒烟 → 观察指标。

APK 二进制不再进入 Git。发布产物必须附带 SHA-256，服务器通过 `deploy/install-apk.sh` 校验并原子替换，并保留上一版本用于回滚。本周期不改写 Git 历史。

## 当前状态与边界

- `0.1.6+7` 为待发布候选版本；线上仍是 `0.1.5+6`，未执行 push、TLS 切换、部署或 APK 发布。
- TLS、证书到期监控和 Agent 降级配置已准备好；实际域名、证书和自动续期需要在生产主机配置后验证。
- 正式 keystore 的创建、离线备份和签名切换尚未完成，不能宣称正式生产签名完成。
- 本周期不包含普通用户 AI 教练 UI、iOS 正式构建、数据库重构、验证码重做或 Git 历史重写。

## 文档

- [部署与运维指南](docs/DEPLOYMENT.md)
- [Android 真机冒烟清单](docs/SMOKE_TEST_CHECKLIST.md)
- [协作与提交规范](CONTRIBUTING.md)
