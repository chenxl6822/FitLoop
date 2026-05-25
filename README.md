# FitLoop 运动打卡与健康管理应用

FitLoop 是一个面向高校学生的运动打卡与健康管理项目，定位为中型偏大型课程工程。项目采用 Flutter 移动端、Spring Boot 后端、MySQL 8.0、Redis 6.0 和 Docker Compose 部署方案，围绕运动打卡、健康档案、目标管理、数据统计、智能提醒、校园社交激励、异常申诉等功能展开。

本仓库只保存代码、测试、部署配置和必要的工程说明。需求文档、概要设计、详细设计、测试报告成品、答辩材料等课程交付文件保留在本地，不提交到 Git。

## 项目结构

```text
FitLoop/
├── backend/              # Spring Boot 模块化单体后端
├── mobile/               # Flutter 移动端应用
├── deploy/               # Docker Compose、Nginx、环境变量模板
├── .github/workflows/    # CI 检查
├── .vscode/              # VS Code 推荐扩展和任务
├── FitLoop.code-workspace # 推荐打开的 VS Code 工作区
└── README.md             # 项目说明
```

## 已实现功能

- 用户注册、登录、JWT 鉴权、个人资料修改。
- 运动打卡 session：开始打卡、轨迹点上传、结束打卡、历史记录查询。
- GPS 轨迹基础校验：定位精度过滤、速度异常标记、重复结束请求幂等处理。
- 卡路里估算：采用 `MET × 体重(kg) × 时长(h)`。
- 目标管理：周/月目标创建、当前目标查询、打卡后自动更新进度。
- 健康统计：健康数据录入、运动次数/时长/里程/消耗汇总。
- 提醒配置：运动、久坐、喝水、睡眠等提醒配置接口。
- 校园激励：积分、等级、勋章、排行榜、好友添加。
- 异常申诉：用户提交异常记录申诉，管理员审核通过或驳回。
- 移动端基础界面：登录入口、底部导航、首页、运动、统计、社交、我的。
- 部署骨架：MySQL、Redis、后端服务、Nginx 的 Docker Compose 编排。

## 后端运行

本地需要 Java 17 和 Maven。

```powershell
cd "D:\code\Sports and Health\FitLoop\backend"
mvn test
mvn spring-boot:run
```

默认配置读取本机 MySQL 和 Redis：

```text
MySQL: localhost:3306 / fitloop
Redis: localhost:6379
后端端口: 8080
```

可通过环境变量覆盖数据库、Redis、JWT 密钥和管理员密钥。生产环境必须替换 `FITLOOP_JWT_SECRET` 和 `FITLOOP_ADMIN_KEY`。

如果 Maven 中央仓库连接失败，可以在本机 `~/.m2/settings.xml` 配置国内镜像。

## 移动端运行

本地需要 Flutter SDK。

```powershell
cd "D:\code\Sports and Health\FitLoop\mobile"
flutter pub get
flutter analyze
flutter test
flutter run
```

当前移动端为 MVP 交互骨架，后续会继续接入真实后端 API、本地缓存、权限引导、通知和图表。

## Docker 部署

你已经确认 Docker Desktop 的 `desktop-linux` context 可用。请从部署目录运行：

```powershell
cd "D:\code\Sports and Health\FitLoop\deploy"
copy .env.example .env
docker compose up -d --build
docker compose ps
```

如果 Docker Hub 的 `auth.docker.io` 连接超时，可以使用国内镜像 override：

```powershell
cd "D:\code\Sports and Health\FitLoop\deploy"
docker compose -f docker-compose.yml -f docker-compose.cn.yml up -d --build
docker compose -f docker-compose.yml -f docker-compose.cn.yml ps
```

如果之后需要关闭这套服务，也要带上同样的 `-f` 参数：

```powershell
docker compose -f docker-compose.yml -f docker-compose.cn.yml down
```

如果后端基础镜像仍然拉取失败，可以先使用“宿主机后端 + Docker 数据库”的开发模式：

```powershell
cd "D:\code\Sports and Health\FitLoop\deploy"
docker compose -f docker-compose.host.yml up -d
docker compose -f docker-compose.host.yml ps

cd "D:\code\Sports and Health\FitLoop\backend"
.\run-local.ps1
```

这种模式下，MySQL、Redis、Nginx 运行在 Docker，Spring Boot 后端运行在本机 `8080` 端口。Nginx 会通过 `host.docker.internal:8080` 转发到本机后端。

服务启动后可以检查：

```powershell
curl http://localhost/actuator/health
curl http://localhost:8080/actuator/health
```

服务器部署默认方案：

- Ubuntu 22.04 或同类 Linux 发行版。
- Docker + Docker Compose。
- Nginx 反向代理 `/api/` 到后端服务。
- 正式环境启用 HTTPS，并替换所有默认密码、JWT 密钥和管理员密钥。

## 测试计划

- 后端单元测试：Service 层、卡路里计算、目标进度、积分规则、申诉审核。
- 后端集成测试：注册、登录、开始打卡、轨迹上传、结束打卡、统计查询。
- 移动端测试：Widget 测试、状态管理测试、后续集成测试。
- 验收场景：
  - 密码登录成功。
  - GPS 跑步打卡生成有效运动记录。
  - 打卡中断网后恢复同步且不重复。
  - 班级/好友排行榜排序和分页正确。
  - 异常记录可提交申诉并被管理员审核。

## VS Code 打开方式

推荐直接打开仓库中的工作区文件：

```powershell
code "D:\code\Sports and Health\FitLoop\FitLoop.code-workspace"
```

不要只把 `backend/` 或 `mobile/` 单独拖进 VS Code，否则 Java、Maven、Flutter 插件可能无法正确识别多模块项目。

建议安装以下扩展：

- Extension Pack for Java
- Maven for Java
- Dart
- Flutter
- YAML

本仓库提供了 VS Code 任务，可以通过 `Terminal: Run Task` 运行：

- `backend: test`
- `backend: run`
- `mobile: pub get`
- `mobile: test`
- `deploy: compose up`

如果打开后仍然看到大量依赖报错，优先在普通 PowerShell 中完成 Maven 和 Flutter 的本地初始化，再回到 VS Code 执行：

```text
Developer: Reload Window
Java: Clean Java Language Server Workspace
Maven: Reload Project
Dart: Restart Analysis Server
```

## Git 规则

- 每完成一个可运行、可测试、可回滚的小任务就提交一次。
- 提交内容只包含代码、测试、部署配置和必要工程说明。
- 不提交 `.docx`、`.pptx`、`.xlsx`、`.pdf`、测试报告成品和答辩材料。
- 常用提交格式：
  - `feat: add sport session start api`
  - `test: cover calorie calculation`
  - `fix: handle duplicate sport finish request`
  - `chore: add docker compose deployment`

## 当前本地环境检查

已确认可用：

- Git
- Java 17
- Maven
- Docker Desktop / Docker Server
- Dart SDK 本体

仍需注意：

- Maven 依赖下载需要本机能访问 Maven 仓库。
- Flutter 命令如果卡住，通常是缓存锁或残留 Dart 进程导致，需要清理 `D:\Environment\flutter\bin\cache\lockfile` 和 `flutter.bat.lock`。
- GitHub HTTPS 推送需要本机凭据或改用 SSH remote。
