# FitLoop 运动打卡与健康管理应用

FitLoop 是一个面向高校学生的运动打卡与健康管理项目。采用 Flutter 移动端、Spring Boot 后端、MySQL 8.0、Redis 6.0 和 Docker Compose 部署方案，围绕运动打卡、健康档案、目标管理、数据统计、智能提醒、校园社交激励、异常申诉等功能展开。

本仓库只保存代码、测试、部署配置和必要的工程说明。需求文档、概要设计、详细设计、测试报告成品、答辩材料等课程交付文件保留在本地，不提交到 Git。

## 项目结构

```text
FitLoop/
├── backend/              # Spring Boot 模块化单体后端（Java 17）
├── mobile/               # Flutter 移动端应用
├── deploy/               # Docker Compose、Nginx、环境变量模板
├── .github/workflows/    # CI 配置
└── STATUS.md             # 实时项目状态
```

## 已实现功能

### 📱 移动端

| 功能 | 说明 |
|------|------|
| **4 种打卡方式** | GPS 实时定位 / 传感器计步 / 拍照打卡 / 手动输入 |
| **5 种运动类型** | 跑步 / 骑行 / 健走 / 跳绳 / 自定义 |
| **卡路里估算** | `MET × 体重(kg) × 时长(h)` |
| **离线打卡** | 断网时本地缓存，恢复后自动同步 |
| **本地通知** | 运动、久坐、喝水、睡眠 4 类提醒 |
| **数据统计** | 时长/里程/卡路里/体重趋势图表 |
| **好友系统** | 搜索、添加、好友列表 |
| **排行榜** | 积分排名 |
| **头像上传** | 拍照/相册选择 |
| **异常申诉** | 运动异常记录提交 |
| **启动引导** | Logo 动画 → 3 页引导轮播 |
| **多运动选择** | 打卡前选择运动类型和方式 |

### 🖥️ 后端

| 模块 | 功能 |
|------|------|
| **用户系统** | 注册、登录、JWT 鉴权、手机验证码、头像上传 |
| **运动服务** | GPS/传感器/拍照/手动 4 种模式，轨迹校验，幂等结束 |
| **目标管理** | 周/月目标创建、进度追踪、自动更新 |
| **数据统计** | 运动次数/时长/里程/消耗聚合，健康数据录入 |
| **提醒配置** | 运动、久坐、喝水、睡眠提醒接口 |
| **社交激励** | 积分、等级、勋章、排行榜、好友 |
| **异常申诉** | 申诉提交/审核 |

### 🐳 部署

- MySQL + Redis + 后端服务 + Nginx 的 Docker Compose 编排
- 支持 HTTPS 反向代理
- 生产/开发环境配置分离

## 当前进度

**最新 HEAD：** `6b46e32`（35 commits）
**阶段 1（补全 4 种打卡 + 多种运动 + 验证码）：** ✅ 已完成
**阶段 2（腾讯云部署）：** ❌ 未开始

查看 [`STATUS.md`](STATUS.md) 获取实时状态详情。

## 后端运行

本地需要 **Java 17** 和 **Maven**。

```powershell
cd D:\AIWorkspace\projects\FitLoop\backend
mvn test
mvn spring-boot:run
```

默认配置：

```text
MySQL: localhost:3306 / fitloop
Redis: localhost:6379
后端端口: 8080
```

可通过环境变量覆盖数据库、Redis、JWT 密钥和管理员密钥。生产环境必须替换 `FITLOOP_JWT_SECRET` 和 `FITLOOP_ADMIN_KEY`。

## 移动端运行

本地需要 **Flutter SDK**。

```powershell
cd D:\AIWorkspace\projects\FitLoop\mobile
flutter pub get
flutter analyze
flutter test
flutter run
```

## Docker 部署

```powershell
cd D:\AIWorkspace\projects\FitLoop\deploy
copy .env.example .env
docker compose up -d --build
docker compose ps
```

如果 Docker Hub 连接超时，使用国内镜像：

```powershell
docker compose -f docker-compose.yml -f docker-compose.cn.yml up -d --build
```

服务启动后检查：

```powershell
curl http://localhost/actuator/health
curl http://localhost:8080/actuator/health
```

## 测试

| 类型 | 数量 | 命令 |
|------|------|------|
| 后端单元测试 | 11 个文件 | `mvn test` |
| 前端 Widget 测试 | 9 个用例 | `flutter test` |
| 代码分析 | 0 issues | `flutter analyze` |

## Git 规则

- 每完成一个可运行、可测试、可回滚的小任务就提交一次。
- 提交内容只包含代码、测试、部署配置和必要工程说明。
- 不提交 `.docx`、`.pptx`、`.xlsx`、`.pdf`、AI 工作文档。
- 常用格式：
  - `feat(scope): add xxx feature`
  - `test(scope): cover xxx logic`
  - `fix: handle xxx edge case`
  - `chore: add docker compose deployment`
- 提交前：`flutter analyze && flutter test`（前端）/ `mvn test`（后端）

## VS Code 打开方式

```powershell
code D:\AIWorkspace\projects\FitLoop
```

建议安装：Extension Pack for Java、Maven for Java、Dart、Flutter、YAML。

## 路线图

| 阶段 | 内容 | 工时 | 状态 |
|------|------|------|------|
| **1** | 4 种打卡 + 5 种运动 + 验证码 | 12h | ✅ 完成 |
| **2** | 腾讯云部署上线 | 5h | ⏳ 下一个 |
| 3 | 社交增强（排行维度/挑战/动态） | 10h | |
| 4 | 第三方登录（微信/QQ） | 8h | |
| 5 | 附加功能（报告/建议/WebSocket） | 10.5h | |
| 6 | Web 管理后台 | 6h | |
| 7 | iOS 构建 | 3.5h | |
| | **总计** | **~55h** | **~22% 完成** |
