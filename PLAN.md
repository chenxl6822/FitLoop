# FitLoop 项目开发计划

> 项目：运动打卡与健康管理（Android/iOS）
> 仓库：https://github.com/chenxl6822/FitLoop.git
> 本地：D:\code\Sports and Health\FitLoop
> 创建时间：2026-05-25
> 工作流：遵循 dev-workflow 五阶段（需求→规划→编码→测试→提交）

---

## 需求概述

FitLoop 是面向高校学生的运动打卡与健康管理移动应用，后端 Spring Boot + 移动端 Flutter，配套 MySQL 8.0 + Redis 6.0 + Docker Compose 部署。

### 已实现（README + 代码确认）
- [x] 后端：用户注册/登录/JWT鉴权/资料修改
- [x] 后端：运动打卡session（开始/轨迹上传/结束/历史查询）
- [x] 后端：GPS轨迹基础校验、卡路里计算（MET公式）
- [x] 后端：目标管理（周/月目标创建、进度自动更新）
- [x] 后端：健康数据统计（次数/时长/里程/消耗）
- [x] 后端：提醒配置接口
- [x] 后端：校园激励（积分/等级/勋章/排行榜/好友）
- [x] 后端：异常申诉（用户提交/管理员审核）
- [x] 移动端：HttpFitLoopApi 真实后端API对接（非Mock）
- [x] 移动端：登录/注册UI、底部导航、Dashboard/运动/统计/社交/我的 五个页面
- [x] 移动端：目标创建/刷新、健康数据录入、勋章/排行榜展示

---

## 待完成功能（按优先级排序）

### P0 - 核心功能缺失（阻塞MVP上线）

- [x] **任务1**：运动页面接入真实GPS定位，替换_sampleTrackPoint假数据
  - 状态：✅ 已完成（commit f00d78f）
  - 验收标准：
    - [ ] 使用 `geolocator` 包获取实时GPS坐标
    - [ ] 运动时持续上传轨迹点（timer 定时触发 uploadTrackPoint）
    - [ ] GPS精度过滤（accuracy > 50m 抛弃）
    - [ ] 权限请求流程（首次使用时请求定位权限）
    - [ ] 模拟器环境降级为模拟数据（不crash）

- [x] **任务2**：运动打卡结束后展示真实结果（替代写死的 _lastRecord）
  - 状态：✅ 已完成（commit f00d78f）
  - 验收标准：
    - [ ] 结束打卡后跳转结果页，展示时长/里程/卡路里
    - [ ] 结果页可分享截图

### P1 - 本地缓存与离线支持

- [ ] **任务3**：接入本地缓存（SharedPreferences 或 Hive）
  - 状态：部分完成（token 持久化已完成，离线数据缓存/同步待做）
  - 验收标准：
    - [x] 用户token持久化（重启App自动登录）
    - [ ] 目标和统计数据缓存（离线可查看上次数据）
    - [ ] 网络恢复后自动同步打卡记录

### P2 - 通知与提醒

- [x] **任务4**：接入本地通知（flutter_local_notifications）
  - 状态：已完成（提醒设置保存后注册/取消本地每日通知）
  - 验收标准：
    - [x] 提醒配置页（我的页面→提醒设置）
    - [x] 运动提醒、久坐提醒、喝水提醒、睡眠提醒可配置
    - [x] 通知权限引导（首次触发时请求权限）

### P3 - 图表与可视化

- [x] **任务5**：统计页面接入图表（fl_chart 或 syncfusion_flutter_charts）
  - 状态：已完成（基于当前汇总数据生成 MVP 趋势图，历史统计接口待后续扩展）
  - 验收标准：
    - [x] 本周/本月运动次数柱状图
    - [x] 体重趋势折线图（来自健康数据）
    - [x] 运动里程/卡路里趋势图

### P4 - 社交功能完善

- [x] **任务6**：好友添加UI与接口对接
  - 状态：已完成
  - 验收标准：
    - [x] 社交页面可搜索用户并发送好友请求
    - [x] 好友列表展示

- [x] **任务7**：申诉提交UI
  - 状态：已完成
  - 验收标准：
    - [x] 运动记录页可发起申诉
    - [x] 申诉历史查看

### P5 - 用户体验优化

- [ ] **任务8**：头像上传与展示
  - 状态：待执行
  - 验收标准：
    - [ ] 我的页面展示头像（默认占位图）
    - [ ] 支持从相册/拍照更换头像
    - [ ] 头像上传API对接

- [ ] **任务9**：启动页/引导页
  - 状态：待执行
  - 验收标准：
    - [ ] App启动页（Logo + 渐入动画）
    - [ ] 首次使用引导页（功能介绍轮播）

---

## 技术债务与优化

- [ ] **任务10**：pubspec.yaml 补全依赖包
  - 当前依赖仅有 `flutter` 和 `cupertino_icons`，需添加：
    - `geolocator`, `geolocator_android`, `geolocator_ios`
    - `http`（或确认HttpClient已满足需求）
    - `shared_preferences` 或 `hive`
    - `flutter_local_notifications`
    - `fl_chart`
    - `image_picker`
    - `permission_handler`

- [ ] **任务11**：Android/iOS 权限配置文件更新
  - AndroidManifest.xml 添加定位、相机、通知权限
  - Info.plist 添加定位权限描述

- [ ] **任务12**：后端集成测试补充
  - 当前有 AppealServiceTest、CalorieCalculatorTest、TargetServiceTest、FitLoopApiIntegrationTest
  - 需补充：社交接口集成测试、健康数据接口测试、权限异常测试

---

## 开发顺序建议

**第一批（P0，本周完成）**：任务1 → 任务2
> 理由：GPS定位是运动打卡的核心，没有真实GPS数据整个应用价值大打折扣

**第二批（P1，下周完成）**：任务3
> 理由：本地缓存是用户体验的基础，没有缓存每次打开App都要重新加载

**第三批（P2-P3，后续迭代）**：任务4 → 任务5
> 理由：通知和图表是提升用户留存的关键功能

**第四批（P4-P5，长期迭代）**：任务6 → 任务7 → 任务8 → 任务9
> 理由：社交和UX优化可以在核心功能稳定后逐步完善

---

## 工具分配策略

| 任务类型 | 使用工具 | 理由 |
|---------|---------|------|
| Flutter UI + 逻辑 | Claude Code | UI代码需要审美和交互细节，Claude Code更强 |
| 后端Java测试补充 | Codex | 测试代码模式固定，Codex速度快 |
| 配置文件修改 | Codex | 简单直接 |
| 依赖包管理 | 手动 | pubspec.yaml修改需要谨慎 |

---

## 提交策略

- 每完成一个任务立即提交，格式：`feat(mobile): 任务N - 功能描述`
- 提交前跑 `flutter analyze` 和 `flutter test`
- 提交后立即 push 到 GitHub（让用户能看到进度）
- 每天工作结束前确保 main 分支始终可编译

---

## 当前进度

- 总任务数：12
- 已完成：0
- 进行中：0
- 待执行：12

---

## 备注

- 后端已大部分完成，主要工作集中在Flutter移动端
- `HttpFitLoopApi` 已对接真实后端，不需要写Mock数据
- 本地后端默认地址 `http://localhost:8080`，需确保后端正在运行
- Android 测试建议用真机（GPS模拟器不准确）
