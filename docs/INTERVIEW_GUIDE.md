# FitLoop 面试指南

这份文档用于把 FitLoop 作为简历项目进行讲解。内容以当前代码为准，重点是讲清业务闭环、技术实现、工程取舍和改进方向，而不是背诵固定答案。

## 1. 简历项目描述

**FitLoop 校园运动打卡与健康管理 App**

基于 Flutter 与 Spring Boot 4.1 实现移动端、REST API 和后台管理，支持 GPS、传感器、拍照、手动输入四种打卡方式，以及目标、统计、提醒、好友排行榜、异常申诉等业务。实现标准 JWT、refresh token 轮换、安全存储、验证码安全控制、弱网离线补偿、轨迹异常检测、Agent 审核、Docker Compose 部署和自动化测试，并通过 Nginx 提供 API 与 Android Release 下载。

**技术栈：** Flutter / Dart、Spring Boot 4.1 / Java 21、Spring Security、JWT、JPA、Flyway、MySQL、Redis、FastAPI、OpenAI Agents SDK、Docker Compose、Nginx、GitHub Actions、JUnit、pytest、Flutter Test。

简历中只写自己能够从代码、测试和部署三个层面解释的内容。不要声称正式 HTTPS 部署和正式生产签名已经完成，也不要声称 Redis 已承担全部排行榜查询。

## 2. 项目介绍模板

### 30 秒版本

> FitLoop 是一个校园运动打卡与健康管理项目，移动端使用 Flutter，后端使用 Spring Boot。用户可以通过 GPS、计步、拍照或手动输入记录运动，系统会完成轨迹校验、热量计算、目标更新和积分奖励，并提供统计、提醒、好友排行榜和异常申诉。我重点实现了完整运动链路、弱网离线补偿、鉴权与验证码安全、Docker 部署和自动化测试。

### 2 分钟版本

按“场景—架构—核心链路—难点—工程化—不足”讲：

1. 高校运动打卡存在记录分散、弱网丢数据、缺少目标反馈和异常处理的问题。
2. Flutter App 调用 Spring Boot REST API；后端按 Controller、Service、Repository 分层，MySQL 保存业务数据，Redis用于排行榜缓存失效，Nginx统一代理和分发 APK。
3. 用户开始运动后获得 `sessionId`，App采集并上传轨迹，结束时后端计算时长、距离和热量，判定异常，再更新目标与积分。
4. 结束请求失败时，移动端将请求和轨迹放入本地队列，恢复网络后重放；后端依靠 `sessionId` 和记录状态保证重复 finish 不重复结算。
5. 工程上使用 Spring Security、标准 JWT、refresh token 轮换、验证码限流、文件校验、Docker Compose、健康检查和自动化测试。
6. 当前不足是生产域名与证书尚未切换、正式 keystore 尚未启用、轨迹仍存 JSON、Redis 缓存能力有限。

## 3. 架构与核心链路

### 系统结构

```text
Flutter App
  ├─ 页面状态、权限、定位、传感器、本地通知
  ├─ API Client
  └─ SharedPreferences 离线队列
          │ HTTP / Authorization
          ▼
Nginx ── Spring Security Filter
          │
          ▼
Controller → Service → Repository → MySQL
                    └─────────────→ Redis（缓存失效）
```

### 一次运动

```text
登录 → start 创建草稿记录 → 采集/上传轨迹 → finish
     → 过滤低精度点 → Haversine 距离 → 速度异常判断
     → MET 热量 → valid/abnormal
     → valid 时更新目标与积分 → 返回统计结果
```

### 登录鉴权

```text
账号密码/验证码 → 登录接口 → 签发 userId.expiresAt.signature
→ App 保存 Token → Authorization 请求头
→ JwtAuthenticationFilter 验签与检查过期时间
→ SecurityContext → AuthSupport 获取当前 userId
```

当前 Token 使用 HMAC-SHA256 签名，但不是 JOSE 标准的 JWT。改进方案是使用 JJWT 或 Nimbus，加入标准 claims、密钥轮换和刷新令牌。

### 离线补偿

```text
finish 失败 → 保存 sessionId、时长、体重、轨迹等
→ 网络恢复 → 先补传轨迹 → 重放 finish
→ 成功删除队列项 / 失败继续保留
```

后端查询 `sessionId + userId`；如果记录已不是 draft，直接返回已有结果，因此重复请求不会再次更新目标和积分。

## 4. 关键实现问答

### GPS 距离与异常如何计算？

后端读取轨迹 JSON，过滤精度大于 100 米的点，按时间排序；相邻点使用 Haversine 公式计算球面距离并累加。相邻点速度超过 8m/s 时标记轨迹异常。异常记录保留用于申诉，但不更新目标和积分。

可改进为按跑步、骑行设置不同阈值，并加入连续异常比例、轨迹平滑、最小时长和地图匹配。

### 热量如何估算？

使用 `MET × 体重(kg) × 时长(h)`。不同运动类型对应不同 MET。这适合作为产品估算值，但不是医疗级结果；后续可结合年龄、性别、心率和配速。

### 为什么轨迹存 JSON？

当前规模下轨迹主要随一次运动整体写入和读取，JSON 能减少表关联和开发成本。缺点是数据量大后难以按点查询、分页和分析。规模扩大后应拆成轨迹点表，或将原始轨迹存对象存储、数据库只留摘要和索引。

### 目标进度如何更新？

有效运动完成后，目标服务查找用户当前周/月的 active 目标，按指标增加次数、时长、里程或热量；达到目标值后改为 completed。更新和运动结算处在事务业务链路中，异常记录不会触发。

### 积分和排行榜怎么做？

有效运动按 `round(calorie / 10)` 奖励积分，至少 1 分；等级为 `points / 100 + 1`。排行榜当前从有效运动记录聚合距离排序。奖励后尝试删除 Redis 排行榜缓存键；Redis 异常被隔离，不影响运动主事务。

### 验证码有哪些安全措施？

- 支持 phone/email 与 register/login/reset_password 三种用途；
- 生成 6 位随机码，数据库只存 HMAC 哈希；
- 5 分钟过期、一次性使用、最多尝试 5 次；
- 同目标 60 秒限发、每小时 5 次、每天 20 次、单 IP 每小时 60 次；
- debug code 只允许 local/test/demo/staging 且显式开启；
- 生产环境未接短信时拒绝手机通道并提示使用邮箱。

### 密码和文件上传如何保护？

密码使用 BCrypt 哈希，登录时通过 `matches` 校验，不保存或解密明文。头像使用文件头识别 JPEG/PNG，避免只信扩展名或 MIME；运动照片限制 content-type 和 10MB 大小。生产环境还应接入对象存储、病毒扫描、压缩和内容审核。

### 提醒功能的服务端与本地端如何协作？

后端保存提醒类型、时间、周期和开关；Android/iOS由 `flutter_local_notifications` 调度一次、每日或每周通知。保存流程先更新本地通知，再写服务器；本地失败不会误改服务器，服务器失败会恢复原本通知。

Android Release 曾因 R8 删除 Gson `TypeToken` 泛型签名而出现 `Missing type parameter`。修复包括 ProGuard保留规则、互不重叠的通知 ID、旧 ID 迁移和错误回滚。这是适合面试展开的真实故障案例：现象、定位、根因、修复、测试、Release 验证都完整。

### Flutter 为什么暂时没有 Provider/Bloc/Riverpod？

当前页面状态主要是局部异步状态，用 `StatefulWidget`、`FutureBuilder` 和可注入的 service 能完成闭环，也便于快速验证。随着登录态、运动会话、离线同步和通知状态增长，应引入 Riverpod 或 Bloc，并按 `auth/sport/stats/social/profile` 拆分功能目录。

### 后台管理如何鉴权？

当前管理接口使用包含角色声明的 JWT，通过管理员账号、RBAC 和审计日志控制访问；历史 `X-Admin-Key` 不再作为移动端管理链路。高风险操作仍应继续完善二次确认和更细粒度权限。

## 5. 工程化问题

### Docker Compose 中各组件的作用

- MySQL：业务持久化；
- Redis：排行榜缓存失效与扩展能力；
- Backend：Spring Boot API 与健康检查；
- Agent：消费审核任务并调用模型，readiness 失败时独立降级；
- Nginx：统一入口、API/上传代理、下载页和 APK；
- named volumes：保存数据库和上传文件，容器重建不丢数据。

发布流程是：本地测试 → 提升 Android versionCode → 构建并校验 Release APK → 上传带 SHA-256 的外部产物 → 服务器备份和拉取代码 → Compose 重建 → 校验并原子安装 APK → 健康检查和真机冒烟。APK 二进制不再提交到 Git。

### 测试覆盖什么？

后端测试覆盖用户、验证码、运动、目标、统计、提醒、社交、申诉、头像和集成链路；移动端 Widget 测试覆盖登录注册、目标、健康数据、定位边界、离线队列和提醒保存事务。CI运行 Maven 测试、Flutter analyze 和 Flutter test。

不要只报测试数量。面试中应举一个具体案例，例如：本地通知调度失败时断言后端不被调用，后端保存失败时断言旧本地通知被恢复。

### 如何排查线上问题？

先分层：公网/Nginx、Backend 健康、容器依赖、业务日志、客户端版本。使用 `/actuator/health`、`docker ps`、容器日志、APK `version.json` 和 Git commit 建立证据链。部署前先备份数据库；遇到服务器本地修改时先复制备份，不能直接 `reset --hard`。

## 6. 项目亮点表达

选择 2～3 个深入讲，不要罗列所有功能：

1. **运动闭环：** session、轨迹、结算、异常、目标、积分在一条链路中协作。
2. **弱网可靠性：** 客户端持久化补偿 + 服务端幂等，解决“结束运动但网络断开”。
3. **安全意识：** BCrypt、JWT 与 refresh token 轮换、安全存储、验证码哈希/限流、文件头校验、生产调试开关隔离。
4. **真实故障治理：** Android R8 通知崩溃从混淆栈定位到 ProGuard规则、事务顺序和回归测试。
5. **交付能力：** Docker Compose、Nginx、备份、监控、版本化 APK 和真机冒烟。

推荐使用 STAR：场景与影响（S/T）→ 你的定位方法和改动（A）→ 测试、构建、线上验证结果（R）。

## 7. 诚实说明不足

| 当前取舍 | 影响 | 改进方向 |
| --- | --- | --- |
| feature 仍通过 Dart `part` 共享顶层库 | 模块边界不够强 | 稳定后逐步转为独立库并明确依赖方向 |
| 轨迹存 JSON | 大数据量查询困难 | 轨迹点表或对象存储 |
| 排行榜主要查 MySQL | 数据规模大时成本高 | Redis ZSet + 定期对账 |
| 正式 keystore 尚未启用 | 暂时延续旧兼容签名 | 离线备份后单独规划签名切换 |
| 线上仍是 HTTP 演示地址 | 敏感数据明文风险 | 域名备案、证书部署和 HTTPS 观察窗口 |

## 8. 高频追问速答

- **为什么用 Flutter？** 单代码库覆盖 Android/iOS，组件体系和插件生态适合快速完成定位、图片、通知和图表场景。
- **为什么用 Spring Boot？** 分层、校验、安全、JPA、事务和测试生态成熟，适合业务型 REST 服务。
- **为什么 Redis 失败不让打卡失败？** 缓存是辅助能力，记录、目标和积分是核心；应隔离非关键依赖故障。
- **为什么需要事务？** 运动结算、目标、积分必须保持业务一致性，避免只完成一半。
- **如何防重复提交？** 以 `sessionId` 为业务幂等键，已结算记录直接返回。
- **如何保护隐私？** 最小化采集、HTTPS、密码哈希、敏感配置不进 Git、上传校验、日志脱敏和数据删除能力。
- **如何扩展到高并发？** 无状态后端横向扩容、对象存储、异步轨迹处理、Redis ZSet、数据库索引/读写优化和可观测性。

## 9. 面试前自测

不看文档完成以下任务：

1. 画出 Flutter、Nginx、Backend、MySQL、Redis 的架构图。
2. 从 `start` 讲到 `finish`，说明异常、目标和积分在哪里发生。
3. 手写 Haversine 的变量含义，并解释 100m 精度和 8m/s 阈值。
4. 解释离线队列与服务端幂等为什么缺一不可。
5. 解释验证码为何存 HMAC、为什么还需要限流和尝试次数。
6. 说明 access token、refresh token 轮换、并发刷新锁和撤销机制。
7. 讲清本地提醒崩溃的 R8 根因和事务修复。
8. 说出至少三个当前不足及可落地改进。
9. 从零写出测试、构建、部署、健康检查和回滚思路。

## 10. 七天准备计划

| 天 | 目标 | 输出 |
| --- | --- | --- |
| 1 | 跑通项目并读 README | 30 秒、2 分钟介绍 |
| 2 | 跟踪一次运动链路 | 架构图与时序图 |
| 3 | 复习鉴权、验证码、上传 | 安全问题答题卡 |
| 4 | 复习 GPS、离线与幂等 | 两个 STAR 难点案例 |
| 5 | 复习数据库、事务、Redis | 数据模型和取舍说明 |
| 6 | 复习测试与部署 | 发布流程和排障清单 |
| 7 | 模拟面试并录音复盘 | 精简答案、补证据 |

最终目标是能从代码指出实现位置、从测试证明边界、从部署说明交付，而不是只描述页面功能。
