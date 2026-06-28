--------------------------749cd6ee8f554bc8
Content-Disposition: form-data; name="file"; filename="content.txt"
Content-Type: text/plain

# FitLoop v2.0 开发规划

> 生成日期：2026-06-03 | 基于 Sprint A 稳定版 + 用户 7 项新需求

---

## 📌 状态快照

| 指标 | 值 |
|---|---|
| 当前版本 | v1.0.0 (APK 已入库) |
| 提交数 | 49 commits on main |
| 测试 | Flutter 9/9 ✅ · Backend 7 模块 ✅ |
| 服务器 | 腾讯云 CVM 43.139.72.25 · Ubuntu 24.04 |
| Sprint A | ✅ 内测稳定化完成（profile API + Nginx uploads + Docker volume + 端口安全） |

---

## 🎯 用户新需求（7 项）

### 1. 验证码系统增强

**需求**：邮箱发送验证码 + 手机号登录注册使用验证码（6位随机码，足够安全）

**实现要点**：
- 后端：新增 `EmailController`（`POST /api/auth/send-email-code`）
- 安全：6 位数字码 + 5 分钟过期 + 同一邮箱/手机 60 秒冷却 + 失败 5 次锁定 15 分钟
- 前端：注册/登录页增加「邮箱验证码」选项，与手机验证码并列
- 新增 `EmailCode` 实体（与 `SmsCode` 共用 `VerificationCode` 抽象）

**文件**：`backend/.../user/EmailController.java` · `backend/.../user/EmailService.java` · `mobile/lib/main.dart`（AuthPage 邮箱区）

---

### 2. 运动目标 CRUD + 实时刷新

**需求**：创建多个目标（如「本周运动 3 次」「本周运动 6 次」「本周运动 30 分钟」）→ 全部显示 → 可删除 → 切换指标时默认推荐值跟着切换

**实现要点**：
- 后端：`TargetController` 增加 `POST /api/targets`（创建）、`GET /api/targets`（列表）、`DELETE /api/targets/{id}`（删除）
- 目标类型：`times_per_week`（次数）、`duration_minutes`（时长）、`calories`（卡路里）、`distance_km`（里程）
- 切换类型时默认值：次数→3次、时长→30分钟、卡路里→500、里程→5km
- 前端：目标列表实时刷新（创建/删除成功后即刻更新 UI），不要刷新整个页面
- 每个目标卡片有删除按钮（`×` 或滑动删除）

**文件**：`backend/.../target/TargetController.java` · `backend/.../target/TargetService.java` · `mobile/lib/main.dart`（TargetSection）

---

### 3. 拍照打卡优化 — 接受 .jpg + 运动识别

**需求**：从手机相册选择 .jpg 文件 → 自动识别是否运动照片 → 提取运动数据（如有）

**实现要点**：
- 前端：`image_picker` 从相册选 .jpg，限制 type 为 `image/jpeg`
- 上传后后端做简单图像校验（分辨率 > 480p、文件头 `FF D8 FF` 校验）
- 基础元数据提取：EXIF 日期/时间作为打卡时间参考
- ⚠️ **AI 运动识别**（阶段 C 功能）：当前版本先做文件格式校验 + 基础元数据提取，运动内容识别标记为「未来迭代」
- 用户可手动补充运动类型/时长

**文件**：`mobile/lib/main.dart`（SportPhotoPicker）· `backend/.../sport/SportPhotoController.java`

---

### 4. GPS 跑步 — 真实地图 + 运动轨迹

**需求**：跑步选择 GPS 定位时，显示当前区域真实地图和运动轨迹

**实现要点**：
- 前端：集成 `flutter_map`（OpenStreetMap 瓦片，免费无需 API Key）替代当前纯文字 GPS
- 运动开始：地图上显示当前位置标记（蓝点）
- 运动中：实时绘制轨迹线（`flutter_map PolylineLayer`），定期（每 5 秒）记录坐标点
- 运动结束：展示完整轨迹 + 起点/终点标记 + 总里程/平均配速
- 后端：`SportService` 增加轨迹点存储（`track_points` JSON 字段），统计接口返回轨迹数据

**文件**：`mobile/lib/main.dart`（SportMapView）· `pubspec.yaml`（+ flutter_map + latlong2）

---

### 5. 头像上传 — 支持手机 .jpg 文件

**需求**：更换头像时也能从手机相册选 .jpg 文件

**实现要点**：
- 修改 `AvatarController.uploadAvatar()` 的 Flutter 端，从 `image_picker` 选图（已实现拍照/相册）
- 增加文件类型限制（仅 `image/jpeg`）
- 压缩至 512x512 以内（服务端缩略或客户端 `package:image` 压缩）
- 确认 Nginx `/uploads/avatars/` 路径可访问

**文件**：`mobile/lib/main.dart`（AvatarPicker）· `mobile/lib/api_client.dart`（uploadAvatar）

---

### 6. 设置模块增强

**需求**：意见反馈渠道 + 验证码重置密码 + 注销账号

**实现要点**：

**6a. 意见反馈**
- 后端：`POST /api/feedback`（提交内容 + 截图可选）
- 前端：设置页新增「意见反馈」入口 → 反馈页面（输入框 + 截图上传）
- 数据存数据库，管理后台可查看（阶段 D）

**6b. 验证码重置密码**
- 后端：`POST /api/auth/reset-password`（手机/邮箱 + 验证码 + 新密码）
- 前端：登录页增加「忘记密码」→ 输入手机/邮箱 → 验证码 → 新密码

**6c. 注销账号**
- 后端：`DELETE /api/user/account`（需验证码确认，30 天冷静期才真正删除）
- 前端：设置页「注销账号」→ 二次确认弹窗 → 验证码确认

**文件**：`backend/.../user/FeedbackController.java` · `backend/.../user/AccountController.java` · `mobile/lib/main.dart`（SettingsPage）

---

### 7. UI 审计 — 冗余按钮/色块检测

**需求**：检查所有页面是否有冗余按钮或色块

**实现要点**：
- 全面走查所有页面（登录/注册/首页/运动/统计/社交/设置）
- 原则：每个按钮应有明确触发行为，每个色块应有视觉意义
- 建议修改清单：

| 页面 | 检查项 | 处理 |
|------|--------|------|
| 首页 | 4 个统计卡片 → 点击是否有用？ | 无点击跳转的卡片改为纯信息展示 |
| 运动页 | 打卡方式切换 UI | 4 种方式用 tab 或卡片选择，避免堆积 |
| 社交页 | 排行榜/好友列表 | 合并列表样式，去重复色块 |
| 设置页 | 条目过多 | 分组折叠（账号/偏好/关于） |
| 个人资料 | 头像+信息布局 | 确保头像+字段对齐合理 |

**文件**：`mobile/lib/main.dart`（UI Audit Pass）

---

## 📋 Sprint 拆分（优先级排序）

### Sprint B：验证码 + 目标 CRUD + 头像优化（3-4h）

| 任务 | 预估 |
|------|------|
| 1. 邮箱验证码后端 (EmailController + EmailService + EmailCode 实体) | 1h |
| 2. 前端注册/登录增加邮箱验证码选项 | 1h |
| 3. 目标 CRUD 后端 (POST/GET/DELETE) + 默认值切换 | 1h |
| 4. 目标列表前端实时刷新 + 删除按钮 | 0.5h |
| 5. 头像支持 .jpg + 压缩 | 0.5h |

### Sprint C：GPS 地图轨迹 + 拍照优化（4-5h）

| 任务 | 预估 |
|------|------|
| 1. flutter_map 集成 + OpenStreetMap 瓦片 | 1h |
| 2. 实时位置标记 + 5s 轨迹点记录 | 1.5h |
| 3. 运动结束轨迹展示 + 配速统计 | 1h |
| 4. 后端轨迹点存储 + 统计接口扩展 | 1h |
| 5. 拍照 .jpg 校验 + EXIF 提取 | 0.5h |

### Sprint D：设置增强（3-4h）

| 任务 | 预估 |
|------|------|
| 1. 意见反馈后端 + 前端 | 1h |
| 2. 验证码重置密码全链路 | 1.5h |
| 3. 注销账号（软删除 + 冷静期） | 1h |
| 4. 设置页结构重整 | 0.5h |

### Sprint E：UI 审计 + 部署上线（2-3h）

| 任务 | 预估 |
|------|------|
| 1. 全页面 UI 走查 + 修复清单 | 1h |
| 2. 前端修改（精简冗余） | 1h |
| 3. `.env` 配置 + `docker compose up` | 0.5h |
| 4. 真机冒烟测试 12 项 | 0.5h |

---

## ⏱ 总预估工时

| Sprint | 工时 | 状态 |
|--------|------|------|
| Sprint A（已有） | 已完成 | ✅ |
| Sprint B（验证码+目标+头像） | 3-4h | ⏳ 下一轮 |
| Sprint C（GPS地图+拍照） | 4-5h | ❄️ |
| Sprint D（设置增强） | 3-4h | ❄️ |
| Sprint E（UI审计+部署） | 2-3h | ❄️ |
| **总计（新增）** | **12-16h** | |

---

## 📁 文档清单

| 文档 | 说明 | 位置 |
|------|------|------|
| FitLoop_v2_DEV_PLAN.md | 本规划 | paste.rs |
| FITLOOP_IMPLEMENT_SPEC.md | 阶段 1 实施规格书 | paste.rs |
| PROJECT_PLAN_v2.md | 原始 7 阶段规划 | paste.rs/tPUL8 |
| deploy/apk/app-release.apk | APK v1.0.0 | 仓库内 |

--------------------------749cd6ee8f554bc8--
