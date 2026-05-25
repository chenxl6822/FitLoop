# FitLoop 运动打卡与健康管理应用

FitLoop 是一个面向高校学生的运动打卡与健康管理项目，定位为中型偏大型课程工程。项目采用 Flutter 移动端、Spring Boot 后端、MySQL 8.0、Redis 6.0 和 Docker Compose 部署方案，围绕运动打卡、健康档案、目标管理、数据统计、智能提醒、校园社交激励等功能展开。

本仓库只保存代码、测试、部署配置和必要的工程说明。需求文档、概要设计、详细设计、测试报告成品、答辩材料等课程交付文件保留在本地，不提交到 Git。

## 项目结构

```text
FitLoop/
├── backend/              # Spring Boot 模块化单体后端
├── mobile/               # Flutter 移动端应用
├── deploy/               # Docker Compose、Nginx、环境变量模板
├── .github/workflows/    # CI 检查
├── .gitignore            # 忽略本地文档与构建产物
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
- 移动端基础界面：登录入口、底部导航、首页、运动、统计、社交、我的。
- 部署骨架：MySQL、Redis、后端服务、Nginx 的 Docker Compose 编排。

## 后端运行

本地需要 Java 17 和 Maven。

```powershell
cd backend
mvn test
mvn spring-boot:run
```

默认配置读取本机 MySQL 和 Redis：

```text
MySQL: localhost:3306 / fitloop
Redis: localhost:6379
后端端口: 8080
```

可通过环境变量覆盖数据库、Redis 和 JWT 密钥，生产环境必须替换 `FITLOOP_JWT_SECRET`。

## 移动端运行

本地需要 Flutter SDK。

```powershell
cd mobile
flutter pub get
flutter analyze
flutter test
flutter run
```

当前移动端为 MVP 交互骨架，后续会继续接入真实后端 API、本地缓存、权限引导、通知和图表。

## Docker 部署

```powershell
cd deploy
copy .env.example .env
docker compose up -d --build
```

服务器部署默认方案：

- Ubuntu 22.04 或同类 Linux 发行版。
- Docker + Docker Compose。
- Nginx 反向代理 `/api/` 到后端服务。
- 正式环境启用 HTTPS，并替换所有默认密码和 JWT 密钥。

## 测试计划

- 后端单元测试：Service 层、卡路里计算、目标进度、积分规则。
- 后端集成测试：注册、登录、开始打卡、轨迹上传、结束打卡、统计查询。
- 移动端测试：Widget 测试、状态管理测试、后续集成测试。
- 验收场景：
  - 验证码或密码登录成功。
  - GPS 跑步打卡生成有效运动记录。
  - 打卡中断网后恢复同步且不重复。
  - 班级/好友排行榜排序和分页正确。

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
- Flutter SDK 路径存在
- Docker CLI

仍需注意：

- Maven 依赖下载在受限沙箱中可能需要联网权限。
- Flutter 命令在当前终端检查中超时，需要在普通 PowerShell 中再次确认。
- Docker daemon 当前不可访问，需启动 Docker Desktop 或以有权限的用户运行。

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

如果打开后仍然看到大量依赖报错，优先在普通 PowerShell 中完成 Maven 和 Flutter 的本地初始化，再回到 VS Code 执行：

```powershell
Developer: Reload Window
Java: Clean Java Language Server Workspace
Dart: Restart Analysis Server
```
