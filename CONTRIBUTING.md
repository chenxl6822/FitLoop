# FitLoop 贡献指南

## Commit 规范

### 格式

```
<type>(<scope>): <short summary>

<body> (optional, wrap at 72 chars)
```

### 类型 (type)

| 类型 | 说明 | 示例 |
|------|------|------|
| `feat` | 新功能 | `feat(backend): add SMS verification code entity and service` |
| `fix` | 修复 | `fix(mobile): correct offline sync queue field name` |
| `refactor` | 重构（不增功能、不修 bug） | `refactor(backend): extract MET calculation into CalorieCalculator` |
| `test` | 添加或修改测试 | `test(backend): add unit tests for CalorieCalculator` |
| `docs` | 文档改动 | `docs: update STATUS.md and README.md` |
| `style` | 代码格式调整（空格、分号等，不影响逻辑） | `style(mobile): format main.dart with dart format` |
| `chore` | 杂项（依赖、构建工具、配置） | `chore(mobile): add pedometer dependency to pubspec.yaml` |

### 范围 (scope)

| 范围 | 适用 |
|------|------|
| `backend` | Spring Boot 后端（Java） |
| `mobile` | Flutter 前端（Dart） |
| `deploy` | Docker、Nginx、CI、部署配置 |
| `docs` | 项目文档（不涉及 src） |

### 核心规则

#### 1. 每笔 commit 只做一件事

```
❌ 坏例子：80 文件混在一起
   0717458 chore: commit all Phase 1 implementation changes

✅ 好例子：拆成 5 个独立 commit
   feat(backend): add SMS verification code entity and service
   feat(backend): add sport photo upload endpoint
   feat(backend): handle sensor/manual checkin mode in SportService
   feat(mobile): add pedometer dependency and pedometer service
   feat(mobile): add multi-sport type and multi-mode checkin support
```

#### 2. 测试随代码走

```
❌ 坏例子：先写功能，再单独另起一笔 commit 补测试
   feat(backend): add SMS verification code
   test(backend): add tests for SMS verification code  ← 看这行，应该合在上面的 feat 里

✅ 好例子：功能 + 测试在同一 commit
   feat(backend): add SMS verification code entity, service, and tests
```

#### 3. 不进版本库的文件

以下文件**永远不 commit**：
- `CLAUDE_CONTEXT.md` 及其任何变体
- `task*_spec.md` — AI 任务规范
- 跨项目文档（如 `Table-Miku挂在docker待办.md`）
- 你的个人笔记
- `.env`、`.env.local`（含 API 密钥）

已通过 `.gitignore` 阻止，但请自行留意。

#### 4. 不要混后端和前端

```
❌ 混在一起：一次性改动 backend + mobile 多个文件
   feat: add avatar upload  ← 同时改了 api_client.dart（前端）和 AvatarController.java（后端）

✅ 分开提交：
   feat(backend): add avatar upload endpoint
   feat(mobile): add avatar upload UI with image_picker
```

#### 5. 提交前必须通过测试

```powershell
# 前端
cd D:\AIWorkspace\projects\FitLoop\mobile
flutter analyze
flutter test

# 后端
cd D:\AIWorkspace\projects\FitLoop\backend
mvn test

# 或一起（在项目根目录有脚本时）
```

### 标题规范

- **≤ 50 字符**（GitHub 截断线）
- **首字母小写**（英文规范）
- **不用句号结尾**
- 中文项目名/词汇可用中文

### 正文规范（可选）

- **wrap at 72 字符**（`git log` 默认宽度）
- 解释"为什么做这个改动"，而非"做了什么"（改了啥看 diff 就知道）
- 空一行分隔标题和正文

```
✅ 好例子

feat(backend): add SMS verification code system

Add SmsCode entity, repository, and service layer for
phone verification. Verification codes expire after 5 minutes.
This enables SMS-based registration and login as required
by the product spec (Section 3.2).
```

### Git 提交示例

```powershell
# 1. 登录功能
git add backend/src/main/java/com/fitloop/user/SmsCode.java
git add backend/src/main/java/com/fitloop/user/SmsCodeRepository.java
git add backend/src/main/java/com/fitloop/user/SmsService.java
git add backend/src/main/java/com/fitloop/user/UserController.java
git add backend/src/test/java/com/fitloop/user/SmsServiceTest.java
git commit -m "feat(backend): add SMS verification code entity and service"

# 2. 前端计步器
git add mobile/pubspec.yaml
git add mobile/lib/pedometer_service.dart
git commit -m "feat(mobile): add pedometer dependency and service"

# 3. 多运动类型
git add mobile/lib/api_client.dart
git add mobile/lib/main.dart
git commit -m "feat(mobile): add multi-sport type and checkin mode support"
```

## 分支策略

- `main` — 稳定分支，经过测试才能合入
- 当前项目较小，所有开发直接在 main 上 commit
- 如果多人协作，应使用 `feature/xxx` 分支

## 发布流程

1. 确保 `main` 测试全绿
2. 更新 `STATUS.md` 和 `README.md`
3. 创建 tag：`git tag v0.1.0`
4. 推送 tag：`git push origin v0.1.0`
5. GitHub Releases 页面创建 Release
