# FitLoop

> 面向高校学生的运动打卡与健康管理应用。项目包含 Flutter 移动端、Spring Boot 后端、MySQL、Redis 与 Docker Compose 部署配置。

![FitLoop 产品展示图](mobile/assets/ai_generated/readme_hero_mockup.png)

FitLoop 围绕校园运动打卡场景，提供多方式运动记录、健康数据统计、目标管理、提醒、好友激励、异常申诉和后台审核能力。仓库保存代码、测试、部署配置与必要工程说明；课程交付类文档、演示材料和其他本地工作稿不纳入 Git。

## 目录

- [功能概览](#功能概览)
- [技术栈](#技术栈)
- [项目结构](#项目结构)
- [快速开始](#快速开始)
- [配置说明](#配置说明)
- [测试与质量检查](#测试与质量检查)
- [部署](#部署)
- [项目状态](#项目状态)
- [文档索引](#文档索引)

## 功能概览

### 移动端

| 功能 | 说明 |
| --- | --- |
| 运动打卡 | 支持 GPS 实时定位、传感器计步、拍照打卡、手动输入 4 种方式 |
| 运动类型 | 支持跑步、骑行、健走、跳绳、自定义运动 |
| 卡路里估算 | 基于 `MET × 体重(kg) × 时长(h)` 估算消耗 |
| 离线同步 | 断网时本地缓存打卡数据，网络恢复后自动同步 |
| 数据统计 | 展示运动次数、时长、里程、卡路里与体重趋势 |
| 本地提醒 | 支持运动、久坐、喝水、睡眠提醒 |
| 社交激励 | 好友搜索、添加、列表与积分排行榜 |
| 账号资料 | 注册、登录、验证码登录、重置密码、头像上传 |
| 异常申诉 | 对异常运动记录提交申诉 |
| 启动引导 | Logo 启动页与 3 页引导轮播 |

### 后端

| 模块 | 说明 |
| --- | --- |
| 用户系统 | 注册、登录、JWT 鉴权、用户资料、头像上传 |
| 验证码 | 统一手机/邮箱验证码接口；内测可回显，生产禁用手机通道并推荐邮箱或短信服务 |
| 运动服务 | 支持 4 种打卡模式、轨迹校验、幂等结束与记录查询 |
| 目标管理 | 周/月目标创建、删除、进度追踪与自动更新 |
| 数据统计 | 聚合运动次数、时长、里程、消耗和健康数据 |
| 提醒配置 | 提供运动、久坐、喝水、睡眠提醒配置接口 |
| 社交激励 | 积分、等级、勋章、排行榜和好友关系 |
| 异常申诉 | 申诉提交与管理员审核 |

## 技术栈

| 层级 | 技术 |
| --- | --- |
| 移动端 | Flutter 3 / Dart、`http`、`geolocator`、`pedometer`、`image_picker`、`flutter_local_notifications`、`fl_chart` |
| 后端 | Java 17、Spring Boot 3.3、Spring Web、Spring Security、Spring Data JPA、Spring Data Redis、Spring Mail、Actuator |
| 数据与缓存 | MySQL 8.0、Redis 6.x |
| 部署 | Docker、Docker Compose、Nginx |
| 测试 | JUnit 5、Spring Boot Test、Flutter Test |

## 项目结构

```text
FitLoop/
├── backend/              # Spring Boot 后端服务
├── mobile/               # Flutter 移动端应用
├── deploy/               # Docker Compose、Nginx、APK 下载页和部署脚本
├── docs/                 # 部署、冒烟测试、交接和开发说明
├── .github/workflows/    # CI 配置
├── CONTRIBUTING.md       # 协作与提交规范
├── STATUS.md             # 当前项目状态
└── README.md
```

## 快速开始

### 1. 环境准备

本地开发建议准备：

- Java 17
- Maven 3.9+
- Flutter SDK 3.4+
- Docker Desktop 或本机 MySQL 8.0、Redis 6.x

如果使用 Docker 提供数据库和缓存，可以只启动依赖服务：

```powershell
cd D:\AIWorkspace\projects\FitLoop\deploy
copy .env.example .env
docker compose up -d mysql redis
```

### 2. 启动后端

```powershell
cd D:\AIWorkspace\projects\FitLoop\backend
mvn test
mvn spring-boot:run
```

默认地址：

- API: `http://localhost:8080/api`
- 健康检查: `http://localhost:8080/actuator/health`
- MySQL: `localhost:3306/fitloop`
- Redis: `localhost:6379`

### 3. 启动移动端

```powershell
cd D:\AIWorkspace\projects\FitLoop\mobile
flutter pub get
flutter analyze
flutter test
flutter run --dart-define=FITLOOP_API_BASE_URL=http://10.0.2.2:8080
```

API 地址说明：

- Android 模拟器访问电脑后端：`http://10.0.2.2:8080`
- 真机访问电脑后端：`http://<电脑局域网IP>:8080`
- 云服务器：`https://your-domain.com` 或 `http://<服务器IP>`

## 配置说明

后端配置位于 [backend/src/main/resources/application.yml](backend/src/main/resources/application.yml)，部署环境变量模板位于 [deploy/.env.example](deploy/.env.example)。

常用环境变量：

| 变量 | 默认值 | 说明 |
| --- | --- | --- |
| `SPRING_DATASOURCE_URL` | `jdbc:mysql://localhost:3306/fitloop...` | MySQL 连接地址 |
| `SPRING_DATASOURCE_USERNAME` | `fitloop` | MySQL 用户名 |
| `SPRING_DATASOURCE_PASSWORD` | `fitloop` | MySQL 密码 |
| `SPRING_REDIS_HOST` | `localhost` | Redis 主机 |
| `SPRING_REDIS_PORT` | `6379` | Redis 端口 |
| `SERVER_PORT` | `8080` | 后端服务端口 |
| `FITLOOP_JWT_SECRET` | 开发默认值 | JWT 签名密钥，生产必须替换 |
| `FITLOOP_ADMIN_KEY` | 开发默认值 | 管理员审核密钥，生产必须替换 |
| `FITLOOP_OTP_HASH_SECRET` | 继承 JWT 密钥 | 验证码哈希密钥，生产建议单独配置 |
| `FITLOOP_OTP_DEBUG_RETURN` | `false` | 是否在响应中返回内测验证码 |
| `FITLOOP_MAIL_*` | 见模板 | 邮箱验证码 SMTP 配置 |
| `FITLOOP_UPLOAD_PATH` | `./uploads` | 上传文件存储目录 |

移动端 API 地址由 `--dart-define=FITLOOP_API_BASE_URL=...` 控制，默认值定义在 [mobile/lib/api_config.dart](mobile/lib/api_config.dart)。

## 测试与质量检查

| 类型 | 命令 |
| --- | --- |
| 后端测试 | `cd backend && mvn test` |
| Flutter 静态分析 | `cd mobile && flutter analyze` |
| Flutter Widget 测试 | `cd mobile && flutter test` |

当前 Sprint B 状态记录显示：后端 15 个测试文件、89 个测试用例；移动端 9 个 Widget 测试用例。最新结果以本地命令和 CI 为准。

## 部署

### 本地 Docker Compose

```powershell
cd D:\AIWorkspace\projects\FitLoop\deploy
copy .env.example .env
docker compose up -d --build
docker compose ps
```

如果 Docker Hub 连接较慢，可以叠加国内镜像配置：

```powershell
docker compose -f docker-compose.yml -f docker-compose.cn.yml up -d --build
```

服务启动后验证：

```powershell
curl http://localhost/actuator/health
curl http://localhost:8080/actuator/health
```

### 生产部署

腾讯云 CVM、Docker、Nginx、备份、监控和 HTTPS 配置见 [docs/DEPLOY_QUICKSTART.md](docs/DEPLOY_QUICKSTART.md) 与 [docs/DEPLOYMENT.md](docs/DEPLOYMENT.md)。

构建生产 APK：

```powershell
cd D:\AIWorkspace\projects\FitLoop
powershell -ExecutionPolicy Bypass -File deploy/build-apk.ps1 -ApiBaseUrl http://<服务器IP>
```

产物位置：

```text
mobile/build/app/outputs/flutter-apk/app-release.apk
```

## 项目状态

- 阶段 1：4 种打卡方式、多运动类型、验证码体系已完成。
- Sprint A：内测稳定化已完成。
- Sprint B：账号与目标稳定化已完成，详见 [STATUS.md](STATUS.md)。
- 下一阶段重点：运动体验增强、设置与反馈闭环、腾讯云部署上线。

当前已知待办：

| 项 | 优先级 | 说明 |
| --- | --- | --- |
| GPS 地图轨迹展示 | P1 | 计划在后续 Sprint 补齐 |
| 拍照打卡文件校验复用 | P1 | 统一复用头像上传的文件头校验思路 |
| 邮箱 SMTP 生产配置 | P1 | 需要配置真实邮箱授权码 |
| iOS 构建 | 中 | 需要 macOS 与 Xcode 环境 |
| CI/CD pipeline 完善 | 中 | 已有基础 CI 配置 |

## 文档索引

| 文档 | 用途 |
| --- | --- |
| [STATUS.md](STATUS.md) | 当前进度、测试覆盖、未解决项 |
| [CONTRIBUTING.md](CONTRIBUTING.md) | 协作流程、提交规范、分支建议 |
| [docs/DEPLOY_QUICKSTART.md](docs/DEPLOY_QUICKSTART.md) | 腾讯云部署速查 |
| [docs/DEPLOYMENT.md](docs/DEPLOYMENT.md) | 部署细节与运维说明 |
| [docs/SMOKE_TEST_CHECKLIST.md](docs/SMOKE_TEST_CHECKLIST.md) | 真机冒烟测试清单 |
| [docs/AI_PROMPTS.md](docs/AI_PROMPTS.md) | AI 协作提示词 |
| [docs/GPT_GUIDE.md](docs/GPT_GUIDE.md) | GPT 协作指南 |

## Git 规则

- 每完成一个可运行、可测试、可回滚的小任务提交一次。
- 提交内容只包含代码、测试、部署配置和必要工程说明。
- 不提交 `.docx`、`.pptx`、`.xlsx`、`.pdf`、本地答辩材料或临时工作稿。
- 常用提交格式：
  - `feat(scope): add xxx feature`
  - `fix(scope): handle xxx edge case`
  - `test(scope): cover xxx logic`
  - `docs(scope): update xxx guide`
  - `chore(scope): adjust project config`

提交前建议执行：

```powershell
cd D:\AIWorkspace\projects\FitLoop\backend
mvn test

cd D:\AIWorkspace\projects\FitLoop\mobile
flutter analyze
flutter test
```
