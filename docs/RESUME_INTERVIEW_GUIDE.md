# FitLoop 简历项目面试准备文档

本文档用于准备把 FitLoop 写进简历后的项目追问。核心目标不是死背，而是做到：能讲清楚项目解决了什么问题、你做了什么、关键技术怎么实现、有哪些取舍和改进方向。

## 1. 简历项目定位

**项目名称：** FitLoop 校园运动打卡与健康管理 App

**一句话介绍：**  
FitLoop 是一个面向高校学生的运动打卡与健康管理 App，支持 GPS、计步、拍照、手动输入等多种打卡方式，并提供运动目标、健康统计、提醒、好友排行榜、异常申诉和后台管理等功能。

**技术栈：**

- 移动端：Flutter、Dart、Material 组件、Geolocator、Pedometer、Image Picker、SharedPreferences、flutter_local_notifications、fl_chart
- 后端：Spring Boot 3、Java 17、Spring Security、Spring Data JPA、Spring Validation、Spring Mail、Actuator
- 数据与部署：MySQL 8、Redis、Docker Compose、Nginx、GitHub Actions
- 测试：JUnit、Spring Boot Test、H2、Flutter Widget Test、Flutter Analyze

**你在简历里应该突出：**

- 这是一个完整的移动端 + 后端 + 部署 + 测试项目，不只是页面 Demo。
- 有真实业务链路：用户注册登录、运动会话开始、轨迹上传、结束结算、目标更新、积分奖励、统计展示。
- 有工程化内容：鉴权、验证码、文件上传、离线同步、容器化部署、CI、自动化测试。

## 2. 30 秒项目介绍

可以这样说：

> FitLoop 是我做的一个校园运动打卡与健康管理项目，前端用 Flutter，后端用 Spring Boot 3。它面向高校学生，支持 GPS 定位、计步、拍照、手动输入等打卡方式，并围绕运动目标、统计图表、好友排行榜、提醒和异常申诉形成完整闭环。我主要负责移动端核心页面、后端 REST API、登录鉴权、运动会话、目标统计、Docker 部署和测试。项目里比较有代表性的点是 GPS 轨迹处理、离线同步队列、基于 Token 的无状态鉴权、验证码安全策略，以及 GitHub Actions 自动跑后端和 Flutter 测试。

## 3. 2 分钟项目介绍

如果面试官让你详细介绍项目，可以按下面顺序讲：

> 这个项目的背景是高校学生运动打卡场景，传统打卡容易出现数据不完整、缺少目标激励、运动记录分散的问题，所以我设计了一个移动端 App，把打卡、目标、统计和社交激励串起来。
>
> 架构上，移动端使用 Flutter 开发，负责登录注册、运动打卡、数据统计、提醒设置、好友排行榜、个人中心等页面。后端使用 Spring Boot 3，按用户、运动、目标、统计、提醒、社交、反馈申诉、管理等模块拆分 Controller、Service、Repository，并通过 MySQL 保存业务数据。
>
> 核心链路是：用户登录后开始一次运动会话，App 根据 GPS 或手动输入收集运动数据，实时上传轨迹点；结束运动时后端计算时长、距离、热量，校验轨迹是否异常；如果记录有效，就自动更新用户目标进度，并给用户增加积分和等级。移动端如果结束打卡时网络失败，会把 finish 请求和未上传轨迹点保存到本地队列，网络恢复后再重放。
>
> 安全上，我做了 Spring Security 鉴权，登录后签发 HMAC 签名 Token，后续请求通过过滤器解析用户身份；验证码采用 HMAC 哈希存储、5 分钟过期、一次性使用、尝试次数限制和发送频率限制。工程化方面，我用 Docker Compose 编排 MySQL、Redis、后端和 Nginx，并配置 GitHub Actions 跑后端测试、Flutter analyze 和 Widget test。

## 4. 面试官高频问题与回答

### Q1：这个项目是做什么的？为什么做？

**回答要点：**

- 场景：高校学生运动打卡和健康管理。
- 痛点：运动记录分散、目标管理弱、缺少激励、打卡异常难处理。
- 方案：移动端采集 + 后端校验 + 目标统计 + 社交激励。

**示范回答：**

> 这是一个面向高校学生的运动打卡和健康管理 App。用户可以用 GPS、计步、拍照或手动方式完成运动记录，系统会统计运动次数、时长、距离、热量，并把这些数据和周/月目标、好友排行榜、提醒结合起来。我的设计重点是把一次运动从开始、轨迹采集、结束结算、目标更新到积分奖励做成完整闭环。

### Q2：你主要负责了哪些工作？

**回答要点：**

- 不要只说“我负责前后端”，要按模块说。
- 强调核心链路和工程化。

**示范回答：**

> 我主要负责 Flutter 移动端核心页面、后端业务接口和部署测试。移动端包括登录注册、运动打卡、统计图表、社交排行榜、个人中心、提醒设置等页面；后端包括用户、运动、目标、统计、提醒、社交、申诉和管理模块。工程上我做了 Token 鉴权、验证码、头像和照片上传、离线同步队列、Docker Compose 部署，以及 GitHub Actions 自动测试。

### Q3：项目整体架构是什么？

**回答要点：**

- Flutter App 调用 Spring Boot REST API。
- Spring Boot 分层：Controller -> Service -> Repository -> MySQL。
- Redis、Nginx、Docker Compose 的位置。

**示范回答：**

> 整体是典型的移动端 + REST 后端架构。Flutter App 通过 HTTP 调用 Spring Boot 提供的 API；后端按 Controller、Service、Repository 分层，Controller 做参数入口，Service 处理业务逻辑，Repository 通过 JPA 访问 MySQL。Nginx 用于反向代理和静态资源分发，Docker Compose 编排 MySQL、Redis、后端和 Nginx。Redis 当前主要用于排行榜缓存失效和后续扩展预留，核心业务数据还是落 MySQL。

### Q4：Flutter 端怎么组织代码？

**回答要点：**

- 主要页面：Auth、Dashboard、SportSession、Stats、Social、Profile、Settings、Admin。
- API 统一封装在 api_client.dart。
- 本地缓存和离线队列独立成 local_cache.dart、sync_queue.dart。
- 可以诚实说当前仍有 main.dart 偏大的问题，后续可拆分。

**示范回答：**

> Flutter 端按功能拆了一部分文件，比如 API 调用在 api_client.dart，本地缓存和离线同步分别在 local_cache.dart、sync_queue.dart，图表组件在 stats_charts.dart，本地提醒在 reminder_scheduler.dart。页面上主要有登录注册、首页、运动会话、统计、社交、个人中心、设置和管理页。当前为了快速完成 Demo，部分页面还集中在 main.dart，后续如果继续迭代，我会按 feature 拆成 auth、sport、stats、social 等目录，并引入更明确的状态管理。

### Q5：为什么 Flutter 端没有用 Provider、Bloc 或 Riverpod？

**回答要点：**

- 当前项目规模和状态复杂度可控。
- 使用 StatefulWidget + FutureBuilder + API service 足够支撑。
- 但能说出后续什么时候需要状态管理。

**示范回答：**

> 这个版本主要是课程/作品集型项目，状态集中在页面级，例如登录态、当前运动会话、统计刷新、提醒配置等，所以我先用 StatefulWidget、FutureBuilder 和统一 API service 实现。这样开发速度快，也减少引入额外框架的复杂度。如果后续用户状态、运动会话、离线同步和通知状态变得更复杂，我会考虑引入 Riverpod 或 Bloc，把全局状态、异步状态和副作用管理拆清楚。

### Q6：GPS 打卡的完整流程是什么？

**回答要点：**

1. 用户选择运动类型和 GPS 打卡方式。
2. App 请求定位权限。
3. 调用后端 start 接口创建 sessionId。
4. App 监听位置流，过滤低精度点。
5. 上传轨迹点。
6. 用户结束运动，调用 finish 接口。
7. 后端计算距离、热量、异常状态。
8. 有效记录更新目标和积分。

**示范回答：**

> GPS 打卡开始时，App 先申请定位权限，然后调用后端 start 接口创建一次运动 session。运动过程中，App 监听位置流，拿到经纬度、精度和时间戳，精度太差的点会先在端上忽略，合格的轨迹点上传到后端。结束时调用 finish 接口，后端根据轨迹点计算距离，根据运动类型、体重和时长估算热量，同时检查速度是否异常。如果记录有效，后端会更新目标进度，并给用户发放积分。

### Q7：你是怎么计算 GPS 距离的？

**回答要点：**

- 后端按时间排序轨迹点。
- 过滤 accuracy 大于 100m 的点。
- 相邻点用 Haversine 公式计算球面距离。
- 汇总距离，换算公里。

**示范回答：**

> 后端会先读取这次 session 的轨迹 JSON，把点转换成经纬度、精度和时间戳对象。然后过滤精度大于 100 米的点，并按时间排序。相邻两个点之间用 Haversine 公式计算球面距离，最后汇总成公里数。这个算法适合移动端 GPS 场景，比简单的平面距离更合理。

### Q8：怎么判断运动轨迹异常？

**回答要点：**

- 根据相邻点距离和时间差计算速度。
- 如果速度超过阈值，认为轨迹跳变或速度异常。
- 当前阈值是 8m/s。
- 异常记录不参与目标和积分。

**示范回答：**

> 我主要做了一个轻量级规则：对相邻轨迹点计算距离和时间差，得到瞬时速度，如果速度超过 8m/s，就标记为异常，原因是速度异常或轨迹跳变过大。异常记录会保存下来，但不会直接更新目标和积分，用户可以通过异常申诉入口说明情况。这个规则比较简单，但能覆盖 GPS 漂移、轨迹跳点这类常见问题。

**可补充改进：**

> 如果继续优化，我会结合运动类型设置不同速度阈值，比如跑步和骑行不同；还可以加入连续异常点比例、最短运动时长、轨迹平滑、地图匹配等策略。

### Q9：热量是怎么计算的？

**回答要点：**

- 使用 MET 估算。
- 公式：MET * 体重 kg * 时长 h。
- 不同运动类型对应不同 MET。

**示范回答：**

> 热量估算用了比较常见的 MET 公式：MET 乘以体重再乘以运动时长小时数。比如跑步 MET 设为 8.0，骑行 6.8，健走 3.8，跳绳 11.0。这个不是医疗级精确算法，但对运动打卡 App 的估算展示是够用的。后续可以根据用户性别、年龄、心率、配速等进一步优化。

### Q10：离线同步是怎么做的？

**回答要点：**

- 结束运动失败时，把 finish 请求保存到 SharedPreferences。
- 保存 token、sessionId、durationSeconds、weightKg、trackPoints。
- 网络恢复或重新进入时调用 SyncProcessor 重放。
- 成功移除，失败保留。

**示范回答：**

> 离线同步主要针对结束运动这个关键操作。如果用户结束打卡时网络失败，App 不会直接丢数据，而是把这次 finish 请求和可能未上传的轨迹点序列化保存到 SharedPreferences 队列里。后续 SyncProcessor 会逐条重放，先补传轨迹点，再调用 finishSport。成功后从队列删除，失败就保留等待下次同步。

### Q11：离线同步怎么保证不会重复结算？

**回答要点：**

- 后端 sessionId 唯一。
- finish 接口检查记录状态。
- 如果不是 draft，直接返回已有记录。
- 这是接口幂等性的基础。

**示范回答：**

> 后端的运动记录有唯一 sessionId，并且状态从 draft 到 valid/abnormal。finish 接口会先根据 sessionId 和 userId 找记录，如果记录已经不是 draft，说明已经结算过，就直接返回已有记录，不会重复计算目标和积分。这样即使移动端因为网络问题重复提交 finish，也能保证结果基本幂等。

### Q12：登录鉴权怎么做？

**回答要点：**

- Spring Security 关闭 session，使用无状态 Token。
- 登录成功后签发 token。
- 后续请求带 Authorization。
- JwtAuthenticationFilter 验证 token 后写入安全上下文。
- 注意：当前实现更接近 HMAC 签名 Token，不是完整 JOSE 标准 JWT。

**示范回答：**

> 后端使用 Spring Security 做无状态鉴权，关闭 session。用户登录成功后，后端签发一个带 userId 和过期时间的 HMAC 签名 Token；后续请求在 Authorization 里携带 Token。过滤器验证签名和过期时间，通过后把用户身份放入当前请求上下文，业务代码再通过 AuthSupport 获取当前 userId。
>
> 严格来说，当前实现更像一个轻量级 HMAC Token，命名用了 JWT 思路，但没有使用标准 JWT 的 header、payload、signature 三段 JSON 结构。生产环境我会使用 jjwt 或 Nimbus JOSE + JWT 这类成熟库，支持标准 claims、密钥轮换和更完整的安全能力。

### Q13：验证码功能怎么保证安全？

**回答要点：**

- 渠道：phone、email。
- 用途：register、login、reset_password。
- 6 位随机码。
- 数据库存 HMAC 哈希，不存明文。
- 5 分钟过期、一次性使用、最多尝试 5 次。
- 发送频率限制：60 秒、1 小时、1 天、IP 维度。
- 本地/测试环境可返回 debugCode，生产关闭。

**示范回答：**

> 验证码这块我做了几个安全控制。验证码是 6 位随机数，数据库里不存明文，而是用 HMAC 结合渠道、用途、目标账号和验证码生成哈希。验证码 5 分钟过期、一次性使用，并限制最多尝试 5 次。发送频率上也做了目标账号和 IP 维度限制，比如 60 秒内不能重复发送、1 小时和 1 天有上限。本地和测试环境可以返回 debugCode 方便调试，但生产环境会关闭。

### Q14：密码是怎么存的？

**回答要点：**

- 用 BCryptPasswordEncoder。
- 不保存明文密码。
- 登录时用 matches 校验。

**示范回答：**

> 密码通过 Spring Security 提供的 BCryptPasswordEncoder 加密保存，数据库只存 passwordHash。登录时不会解密密码，而是用 encoder.matches 对用户输入和哈希做校验。BCrypt 自带盐，并且计算成本可调，比自己写 MD5 或 SHA 哈希安全很多。

### Q15：头像上传和照片上传怎么处理？

**回答要点：**

- MultipartFile 接收文件。
- 限制图片类型和大小。
- 头像做 magic bytes 校验更稳。
- 文件保存到 uploads 目录。
- 静态资源映射到 /uploads/avatars 或 /uploads/photos。

**示范回答：**

> 上传接口用 MultipartFile 接收文件。头像上传时不只看文件后缀，还通过文件头 magic bytes 判断 JPEG/PNG，避免用户把非图片改后缀上传。文件保存到服务端 uploads 目录，并通过静态资源映射暴露为 /uploads/avatars 下的 URL。运动照片上传也做了 content-type 和大小限制。生产环境还可以进一步接对象存储、图片压缩和内容审核。

### Q16：数据库表大概怎么设计？

**回答要点：**

- UserInfo：用户资料、密码哈希、积分、等级。
- VerificationCode：验证码哈希、渠道、用途、过期时间、使用状态、尝试次数。
- SportRecord：运动 session、类型、方式、时长、距离、热量、轨迹 JSON、状态。
- SportTarget：周/月目标、指标、目标值、完成值、周期。
- HealthData：体重、睡眠、饮食、日期。
- ReminderConfig：提醒类型、时间、周期、启用状态。
- UserFriend：好友关系。
- Feedback/Appeal/Admin：反馈、申诉、管理端。

**示范回答：**

> 核心表是用户、运动记录、目标、健康数据、提醒和好友关系。运动记录表用 sessionId 标识一次打卡，记录 sportType、checkinMode、duration、distance、calorie、trackJson、status 等字段。目标表记录用户的周/月目标、目标指标和完成值；每次有效运动结束后，后端会根据运动记录自动更新目标完成值。用户表除了账号资料，还保存积分和等级，用于排行榜和徽章。

### Q17：为什么轨迹点用 JSON 存在 SportRecord 里，而不是单独建表？

**回答要点：**

- 当前项目规模和 Demo 场景下简化实现。
- 一次运动的轨迹主要随记录整体读取。
- 减少表和关联复杂度。
- 生产环境会拆成 track_point 表或对象存储。

**示范回答：**

> 当前版本为了简化实现，把一次运动的轨迹点作为 JSON 存在 SportRecord 里，因为主要使用场景是一次运动结束时整体读取轨迹并计算距离，查询维度比较简单。这样可以减少额外表和关联逻辑。缺点是轨迹点很多时 JSON 字段会变大，也不方便按点查询。生产环境我会把轨迹点拆到 track_point 表，或者把大轨迹文件放到对象存储，数据库只保存索引和摘要。

### Q18：目标进度是怎么更新的？

**回答要点：**

- finish 成功且记录有效时调用 TargetService.applySportRecord。
- 查当前周期 active 目标。
- 根据 metric 增加 count、duration、distance、calorie。
- 达到目标值后标记 completed。

**示范回答：**

> 后端在运动 finish 时，如果轨迹没有被判异常，会调用目标服务。目标服务会查用户当前周期内 active 的目标，比如本周或本月，然后根据目标指标更新完成值。如果指标是次数就加 1，如果是时长就加运动分钟数，如果是里程就加 distanceKm，如果是热量就加 calorie。完成值达到目标值后，目标状态会变成 completed。

### Q19：积分和排行榜怎么做？

**回答要点：**

- 有效运动才奖励。
- 积分按 calorie / 10 估算，至少 1 分。
- 等级 = points / 100 + 1。
- 排行榜按有效运动累计距离排序。
- Redis 失败不影响主流程。

**示范回答：**

> 积分只对有效运动发放，异常记录不会加分。现在的规则是按热量除以 10 取整，至少给 1 分，等级按积分每 100 分升一级。排行榜当前按有效运动记录聚合距离排序。Redis 这块我做了排行榜缓存失效的预留，打卡奖励时会尝试删除相关缓存 key，但即使 Redis 不可用，也不会让已经完成的打卡失败，因为积分和记录才是主链路。

### Q20：统计图表怎么做？

**回答要点：**

- 后端按周/月聚合运动记录。
- 移动端用 fl_chart 展示里程、热量、体重趋势。
- 健康数据支持体重、睡眠、饮食。

**示范回答：**

> 统计分两类：运动统计和健康统计。运动统计从有效的 SportRecord 聚合出次数、时长、里程、热量，并支持按周或月返回历史点。健康统计由用户录入体重、睡眠、饮食，后端返回体重历史。移动端用 fl_chart 画里程/热量趋势和体重趋势。

### Q21：提醒功能怎么做？

**回答要点：**

- 后端保存提醒配置。
- 移动端使用 flutter_local_notifications 调度本地通知。
- 支持运动、久坐、喝水、睡眠等类型。
- 支持一次、每日、每周。

**示范回答：**

> 提醒分成服务端配置和移动端本地调度。后端保存用户的提醒类型、提醒时间、周期和启用状态。移动端拿到配置后，用 flutter_local_notifications 创建本地通知，支持一次、每日和每周提醒。这样即使 App 不一直在线，也能依赖系统通知触发提醒。

### Q22：后台管理做了什么？

**回答要点：**

- 管理统计、用户列表、用户详情、反馈处理、申诉审核。
- 通过 X-Admin-Key 做简单管理鉴权。
- 生产要改成角色权限系统。

**示范回答：**

> 后台管理主要用于查看统计、用户列表、用户详情，以及处理反馈和异常申诉。现在管理接口使用 X-Admin-Key 做简单保护，适合 Demo 和内测。生产环境我不会这样做，会改成管理员账号、角色权限、操作审计和更细粒度的接口授权。

### Q23：Docker Compose 部署结构是什么？

**回答要点：**

- mysql：业务数据。
- redis：缓存/扩展。
- backend：Spring Boot 服务。
- nginx：反向代理、下载页、静态资源。
- healthcheck 保证启动顺序。

**示范回答：**

> Docker Compose 里主要有 MySQL、Redis、backend 和 Nginx。MySQL 保存业务数据，Redis 用于缓存和扩展，backend 是 Spring Boot 服务，Nginx 对外提供 HTTP 入口和 APK 下载页。Compose 里配置了 depends_on 和 healthcheck，确保 MySQL、Redis 健康后再启动后端，后端健康后再启动 Nginx。

### Q24：CI 做了什么？

**回答要点：**

- 后端：setup-java + Maven test。
- 移动端：Flutter pub get、flutter analyze、flutter test。
- push main/develop 和 PR 触发。

**示范回答：**

> GitHub Actions 分成 backend 和 mobile 两个 job。后端 job 安装 Java 17 并跑 Maven test；移动端 job 安装 Flutter，然后执行 flutter pub get、flutter analyze 和 flutter test。这样每次 push 或 PR 都能自动检查后端测试和 Flutter 静态分析/Widget 测试，减少回归。

### Q25：测试覆盖了哪些内容？

**回答要点：**

- 后端 100+ JUnit 测试。
- 覆盖用户、验证码、运动、目标、统计、提醒、社交、反馈、申诉、头像上传等。
- 移动端 12 个 Widget Test。
- 覆盖注册登录、目标创建、统计录入、GPS 异常、离线队列等。

**示范回答：**

> 后端有 100 多个 JUnit 测试，覆盖用户、验证码、运动、目标、统计、提醒、社交、反馈、申诉和头像上传等核心逻辑。移动端有 12 个 Widget Test，覆盖登录注册、验证码、目标创建、健康数据提交、GPS 权限拒绝、GPS 精度不足、结束失败进入离线同步队列等场景。测试重点不是追求覆盖率数字，而是保证核心业务链路不容易被改坏。

### Q26：你遇到过最大的难点是什么？

**回答思路：选一个真实且技术含量高的点。推荐讲 GPS + 离线同步。**

**示范回答：**

> 最大的难点是运动打卡链路不只是一个表单提交，而是一个持续会话。GPS 可能权限被拒、精度不足、轨迹跳变，网络也可能在结束运动时失败。我做了几层处理：端上过滤低精度点，后端再根据速度阈值判断异常；运动结束失败时，端上把 finish 请求和轨迹点写入本地队列，后续再重放；后端 finish 接口用 sessionId 和状态判断保证重复提交不会重复结算。这个过程让我更多考虑了移动端网络不稳定和接口幂等性。

### Q27：如果让你继续优化这个项目，你会做什么？

**回答要点：**

- 代码结构：Flutter 拆 feature，引入状态管理。
- 安全：标准 JWT/OAuth2、刷新 token、RBAC、审计。
- 数据：轨迹点拆表、索引优化、缓存排行榜。
- 体验：地图轨迹、更多异常规则、消息推送。
- 部署：HTTPS、日志监控、蓝绿/灰度。

**示范回答：**

> 我会从四个方向优化。第一是移动端架构，把 main.dart 里较大的页面拆成 feature 模块，并引入 Riverpod 或 Bloc。第二是安全，把当前轻量 Token 改成标准 JWT 或 OAuth2，并做 refresh token、管理员 RBAC 和操作审计。第三是数据，把轨迹点从 JSON 拆成独立表或对象存储，并给排行榜做真正的 Redis 缓存。第四是体验和运维，加地图轨迹展示、更多异常识别规则、HTTPS、日志监控和部署流水线。

### Q28：这个项目有什么不足？

**回答要点：**

- 要主动、诚实、有改进方案。
- 不要说“没什么不足”。

**示范回答：**

> 当前项目已经覆盖了主要业务闭环，但还有几个不足。Flutter 端部分页面集中在 main.dart，模块拆分还不够理想；Token 实现是轻量级 HMAC Token，不是完整标准 JWT；轨迹点用 JSON 存在运动记录里，数据量大时不够扩展；Redis 目前更多是预留和缓存失效，还没有把排行榜完整缓存起来。这些都是我后续会优先优化的点。

### Q29：为什么选择 Spring Boot？

**回答要点：**

- 快速构建 REST API。
- 生态成熟：Security、JPA、Validation、Mail、Actuator、Test。
- 适合模块化单体。

**示范回答：**

> Spring Boot 适合这个项目，因为它能快速搭建 REST API，并且安全、数据访问、参数校验、邮件、健康检查和测试生态都比较完整。FitLoop 当前业务规模适合模块化单体，先按用户、运动、目标等模块拆清楚，后续如果访问量或团队规模上来，再考虑拆服务。

### Q30：为什么选择 Flutter？

**回答要点：**

- 一套代码覆盖 Android/iOS。
- UI 开发效率高。
- 插件生态满足定位、计步、通知、图片选择。

**示范回答：**

> 因为这个项目需要移动端能力，比如定位、计步、通知、图片选择，同时希望开发效率高。Flutter 一套代码可以覆盖 Android 和 iOS，Material 组件和插件生态也比较适合快速做出完整 App。对课程项目或作品集来说，Flutter 能让我把更多时间放在业务闭环和工程能力上。

## 5. 必须掌握的知识点清单

### 5.1 项目业务必须讲清楚

- 用户如何注册、登录、重置密码。
- 验证码有哪些渠道和用途。
- 一次运动从开始到结束的数据流。
- GPS 轨迹如何采集、上传、过滤和结算。
- 目标进度如何被运动记录更新。
- 积分、等级、排行榜如何计算。
- 离线同步队列保存了什么，什么时候重试。
- 异常申诉和后台审核的作用。

### 5.2 Flutter 必须掌握

- StatefulWidget 的生命周期：initState、setState、dispose。
- FutureBuilder 的使用场景。
- NavigationBar 和页面切换。
- http 请求封装和错误处理。
- SharedPreferences 的本地持久化。
- Geolocator 权限申请、位置流监听、精度字段。
- Image Picker 的拍照/相册选择。
- flutter_local_notifications 的本地通知调度。
- fl_chart 基本图表数据结构。
- Widget Test 的基本写法：pumpWidget、tap、enterText、expect。

### 5.3 Spring Boot 必须掌握

- Controller、Service、Repository 分层职责。
- @RestController、@GetMapping、@PostMapping、@PutMapping、@DeleteMapping。
- @Transactional 的作用，什么时候读写事务。
- Spring Data JPA Repository 的基本查询方法命名。
- Entity、@Id、@GeneratedValue、@Column、@Lob、@PrePersist、@PreUpdate。
- 全局异常处理和统一 ApiResponse。
- MultipartFile 文件上传。
- application.yml 和环境变量配置。
- Actuator healthcheck。

### 5.4 安全必须掌握

- BCrypt 为什么适合存密码。
- Token 鉴权和 Session 鉴权的区别。
- Spring Security FilterChain 的大致流程。
- HMAC 签名的基本原理。
- Token 过期时间为什么必要。
- 验证码为什么不能明文存储。
- 验证码频率限制、过期、一次性使用、尝试次数限制。
- 管理端 X-Admin-Key 的局限性。

### 5.5 数据库必须掌握

- 用户表、运动记录表、目标表、健康数据表、提醒表、好友关系表的核心字段。
- 为什么 userId 是业务关联关键字段。
- sessionId 为什么要唯一。
- status 字段如何表达运动记录和目标状态。
- 周目标/月目标的 startDate、endDate 如何计算。
- trackJson 的优缺点。
- 如果数据量变大，哪些字段需要索引：userId、sessionId、status、startedAt、targetId、dataDate。

### 5.6 算法和业务规则必须掌握

- Haversine 公式用于根据经纬度计算距离。
- MET 热量估算公式：MET * weightKg * durationHours。
- GPS accuracy 的含义。
- 异常速度阈值为什么能识别轨迹跳变。
- 目标进度计算规则：次数、时长、里程、热量。
- 积分规则：根据热量折算，等级根据积分区间计算。

### 5.7 测试和部署必须掌握

- Maven test 跑哪些后端测试。
- H2 在测试中的作用。
- Flutter analyze 和 flutter test 的区别。
- Widget Test 适合测什么，不适合测什么。
- Docker Compose 里每个服务的职责。
- healthcheck 和 depends_on 的作用。
- Nginx 在项目里的角色。
- GitHub Actions 的触发条件和 job 内容。

## 6. 项目亮点怎么讲

### 亮点 1：运动打卡链路完整

**表达：**

> 我不是只做了一个“提交运动记录”的表单，而是做了完整会话：start 创建 session，track 上传轨迹，finish 结算运动，后端再更新目标和积分。

### 亮点 2：考虑移动端弱网

**表达：**

> 移动端网络不稳定是常见问题，所以我对结束打卡做了离线队列。失败时先本地保存，之后再补传轨迹和 finish 请求。

### 亮点 3：验证码有安全设计

**表达：**

> 验证码没有明文入库，而是 HMAC 哈希，并做了过期、一次性使用、尝试次数和频率限制。

### 亮点 4：有自动化测试和 CI

**表达：**

> 我给核心业务补了后端测试和 Flutter Widget Test，并接入 GitHub Actions，避免每次修改后靠手动点页面验证。

### 亮点 5：能诚实说明取舍

**表达：**

> 当前版本为了快速完成闭环，轨迹点用 JSON 存储，Token 是轻量 HMAC 方案，Flutter 状态管理也比较直接。它们适合现阶段，但我知道生产环境应该如何演进。

## 7. 面试官可能深挖的技术点

### 7.1 Haversine 公式

你不需要完整背公式，但要能说清楚：

- 经纬度不能直接用普通平面距离计算。
- 地球近似球体，Haversine 用球面两点距离。
- 输入是两个点的 lat/lng。
- 输出是米或公里。

简短回答：

> Haversine 是根据两个经纬度点计算球面距离的公式。GPS 轨迹由很多点组成，我对相邻点计算距离再累加，得到整次运动的里程。

### 7.2 @Transactional

要能说清楚：

- finish 里更新运动记录、目标进度、积分奖励应该在事务里。
- 如果中间数据库操作失败，应整体回滚。
- Redis 缓存失效失败不应该导致主事务失败，所以捕获异常。

简短回答：

> 运动结束不仅更新 SportRecord，还会更新 Target 和 UserInfo 积分，所以我把它放在事务里。这样数据库主链路要么都成功，要么回滚。Redis 只是缓存相关，失败不会影响主链路。

### 7.3 接口幂等性

要能说清楚：

- start 不幂等，每次创建新 session。
- track 可以追加轨迹点，但重复上传同一个点当前没有严格去重。
- finish 通过状态判断实现基本幂等。

简短回答：

> finish 是最需要幂等的接口，因为移动端可能失败重试。后端通过 sessionId 找记录，如果状态已经不是 draft，就直接返回，不重复结算目标和积分。

### 7.4 Redis 的真实作用

不要夸大。

正确说法：

> 这个版本 Redis 不是主存储，主数据都在 MySQL。Redis 当前主要用于排行榜缓存失效和后续扩展预留。打卡奖励时会尝试删除 ranking 相关 key，但 Redis 异常不会影响主流程。

如果被问“那为什么不用 Redis 真正缓存排行榜？”

> 当前数据量小，直接从 MySQL 聚合可以接受；我先把缓存失效点留出来。后续可以把排行榜结果缓存到 Redis ZSet 或 String JSON，并设置 TTL，运动记录更新时删除或更新缓存。

### 7.5 标准 JWT 与当前 Token 的区别

必须诚实。

正确说法：

> 当前 JwtService 的实现是 userId、过期时间和 HMAC 签名组成的轻量无状态 Token，不是完整标准 JWT。标准 JWT 一般有 header、payload、signature 三段 Base64Url JSON，并包含 iss、sub、exp 等 claims。生产环境我会换成熟 JWT 库。

## 8. 常见追问速答

**问：这个项目几个人做的？**  
答：如果是你独立完成，就说“主要由我独立完成，覆盖移动端、后端、部署和测试”。如果有协作，要说清楚你负责的模块。

**问：接口大概有多少？**  
答：后端有 40+ 个 REST 接口，覆盖用户、运动、目标、统计、提醒、社交、反馈申诉和后台管理。

**问：测试有多少？**  
答：后端有 100+ 个 JUnit 测试，移动端有 12 个 Widget Test，并在 CI 中自动执行。

**问：有没有上线？**  
答：可以说“项目支持 Docker Compose 部署，包含 MySQL、Redis、后端和 Nginx，也准备了 APK 下载页；如果部署到云服务器，只需要配置生产环境变量、域名、HTTPS 和邮件/短信服务。”

**问：MySQL 和 Redis 分别存什么？**  
答：MySQL 存用户、运动记录、目标、健康数据、提醒、好友等主业务数据；Redis 当前用于排行榜缓存失效和后续缓存扩展，不作为主数据源。

**问：为什么异常记录不直接删除？**  
答：异常记录仍然是用户行为证据，保留后可以申诉和审核；只是暂时不参与目标和积分，避免作弊或错误轨迹影响结果。

**问：如何防止用户伪造 GPS？**  
答：当前做了速度阈值、精度过滤和异常申诉，能处理一部分明显异常。更强的防作弊需要设备完整性校验、服务端轨迹规则、运动传感器交叉验证、定位模拟检测和风控模型。

**问：为什么用 Docker Compose？**  
答：项目依赖 MySQL、Redis、后端和 Nginx，Compose 可以一键拉起完整环境，适合开发、测试和小规模部署。

**问：这个项目最能体现你能力的地方是什么？**  
答：不是单点功能，而是把移动端采集、后端校验、数据存储、目标积分、离线同步、部署和测试串成完整闭环。

## 9. 你可以主动讲的项目难点

### 难点 A：移动端定位不稳定

可以这样讲：

> GPS 数据本身不稳定，可能精度差、点跳变、权限被拒，所以我在端上过滤精度不足的位置，在后端再用速度阈值判断异常。这样可以降低错误轨迹对运动距离、目标和积分的影响。

### 难点 B：结束打卡不能丢数据

可以这样讲：

> 运动结束是关键操作，如果网络失败，用户会觉得整次运动丢了。我用 SharedPreferences 做一个轻量离线队列，把 finish 请求和轨迹点保存下来，后续再重试，并且后端 finish 做幂等处理。

### 难点 C：验证码要兼顾开发调试和生产安全

可以这样讲：

> 本地和测试环境返回 debugCode 方便调试，但生产环境关闭；数据库保存验证码哈希，配合过期、一次性使用、尝试次数和频率限制，避免明文泄漏和暴力尝试。

## 10. 不建议这样回答

**不要说：**“我用了 JWT，所以很安全。”  
**应该说：**“我做了无状态 Token 鉴权，当前是轻量 HMAC 实现，生产会换标准 JWT 库，并补充刷新 Token、密钥轮换和权限模型。”

**不要说：**“Redis 用来做排行榜。”  
**应该说：**“当前主数据在 MySQL，Redis 主要用于排行榜缓存失效和扩展预留，后续可以用 ZSet 做真正排行榜缓存。”

**不要说：**“GPS 很准确。”  
**应该说：**“GPS 有误差，所以我做了精度过滤和异常速度判断，生产环境还要加入更多风控规则。”

**不要说：**“项目没什么问题。”  
**应该说：**“当前版本完成了闭环，但 Flutter 模块拆分、标准 JWT、轨迹点存储、Redis 缓存和运维监控都有优化空间。”

## 11. 如果被要求现场画架构图

可以按这个结构画：

```text
Flutter App
  |-- Auth / Dashboard / Sport / Stats / Social / Profile
  |-- Local Cache / Offline Sync Queue / Local Notification
  |
  | HTTP REST + Token
  v
Nginx
  |
  v
Spring Boot Backend
  |-- Controller
  |-- Service
  |-- Repository
  |-- Security Filter
  |
  +--> MySQL: users, sport_records, targets, health_data, reminders, friends
  |
  +--> Redis: ranking cache invalidation / cache extension
  |
  +--> uploads: avatars, sport photos
```

如果口头解释：

> Flutter App 负责页面、采集和本地能力；Nginx 负责入口和静态资源；Spring Boot 提供业务 API；MySQL 存主业务数据；Redis 用于缓存扩展；uploads 保存头像和运动照片。

## 12. 如果被要求讲一次运动的数据流

可以按这个流程讲：

```text
选择运动类型和打卡方式
  -> 请求定位权限
  -> POST /api/sport/session/start 创建 session
  -> 监听 GPS 位置流
  -> 过滤低精度点
  -> POST /api/sport/session/track 上传轨迹点
  -> 用户点击结束
  -> POST /api/sport/session/finish
  -> 后端计算距离、热量、异常状态
  -> 有效记录更新目标进度
  -> 有效记录增加积分和等级
  -> 统计页和排行榜展示结果
```

一句话总结：

> 运动打卡不是一次提交，而是一个有状态 session，从 start 到 track 再到 finish，最后触发目标和积分的后续业务。

## 13. 如果被要求讲一次登录的数据流

```text
用户输入账号密码
  -> POST /api/auth/login
  -> 后端查用户
  -> BCrypt 校验密码
  -> 签发 HMAC Token
  -> App 保存 token 和用户信息
  -> 后续请求带 Authorization
  -> JwtAuthenticationFilter 校验 token
  -> AuthSupport 获取当前 userId
```

如果是验证码登录：

```text
发送验证码
  -> 生成 6 位验证码
  -> HMAC 哈希入库
  -> 邮箱或短信发送
  -> 用户输入验证码
  -> 校验渠道、用途、目标、过期、次数、哈希
  -> 校验通过后登录或注册
```

## 14. 面试前自测题

你应该能不看代码回答下面问题：

- FitLoop 的核心用户是谁？
- 这个项目解决了什么问题？
- 你具体负责了哪些模块？
- 一次 GPS 打卡从开始到结束经过哪些接口？
- sessionId 有什么作用？
- finish 接口为什么要做幂等？
- GPS 距离怎么算？
- 为什么要过滤 accuracy？
- 热量估算公式是什么？
- 异常记录为什么不参与目标和积分？
- 目标进度怎么更新？
- 积分和等级怎么计算？
- Token 鉴权流程是什么？
- 当前 Token 和标准 JWT 有什么区别？
- 验证码为什么要哈希存储？
- 验证码有哪些频率限制？
- 密码为什么用 BCrypt？
- 头像上传如何防止伪造后缀？
- 离线同步队列保存什么？
- Redis 在项目里真实做了什么？
- Docker Compose 有哪些服务？
- CI 跑了哪些命令？
- 当前项目有哪些不足？
- 如果继续优化，你会先做哪三件事？

## 15. 面试结尾可以这样总结

> 这个项目对我来说最大的价值，是我完整走了一遍移动端产品从功能设计、前端实现、后端接口、数据建模、安全鉴权、离线处理、测试到部署的过程。它不是最复杂的系统，但覆盖了一个真实 App 里常见的工程问题，比如弱网、权限、鉴权、文件上传、数据一致性、测试和部署。后续我会重点优化移动端模块化、标准 JWT、轨迹存储和 Redis 排行榜缓存。

