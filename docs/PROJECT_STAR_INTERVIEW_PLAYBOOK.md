# FitLoop 项目全景、STAR 面试与实战手册

> 快照日期：2026-08-04
> 代码基线：main，HEAD 8104038
> 目标：让读者能从零讲清楚、复现、测试、排障并继续演进 FitLoop，而不是只背一段项目介绍。

## 0. 先读这一页：证据边界

“覆盖所有情况”在真实软件里没有字面上的终点。本手册覆盖当前仓库能够证明的实现、主要失败模式和高频面试追问，并把事实分成五类：

- **[已实现]**：当前代码中存在，可以沿文中的文件路径检查。
- **[本轮验证]**：2026-08-04 在当前工作区实际执行过。
- **[仓库记录]**：README、运行手册或既有测试记录中的结论，本轮未必重跑。
- **[代码审查风险]**：由调用链或状态机推导出的风险，尚未通过故障注入稳定复现，不能说成已确认线上 Bug。
- **[建议]**：生产化或面试延伸方案，不代表仓库已经实现。

必须诚实说明的当前边界：

1. 当前 main 的移动端版本是 0.1.7+8；README 记录的公开包仍是更早的 0.1.5+6 HTTP 过渡版。这个公开状态本轮没有联网复核，因此不能说 main 已上线。
2. 本轮 Java 单元/切片测试、JaCoCo 门禁和 Python Agent 测试通过；Docker 不可访问，2 个 MySQL Testcontainers 用例被配置为跳过；Flutter SDK 锁文件无权限，本轮没有跑 Flutter analyze/test。
3. 没有调用真实 DeepSeek、没有使用真实用户数据、没有做服务器连接、部署、发布、推送或 PR。
4. 既有 INTERVIEW_GUIDE 的两处历史描述已过时：访问令牌当前是手写 HS256 JWT，不是“自定义点号 token”；轨迹当前优先写 sport_track_point 表，只在兼容旧数据时回退 trackJson。

## 1. 一句话、30 秒、2 分钟怎样介绍

### 1.1 一句话

FitLoop 是一个面向校园运动打卡和健康管理的端云一体项目：Flutter 负责移动交互与弱网续传，Spring Boot 负责身份、运动结算和业务一致性，MySQL 是事实源，Redis 提供队列与排行榜投影，Python Agents SDK + DeepSeek 提供“有证据、可审计、需确认”的训练建议与申诉预审。

### 1.2 30 秒版

> 我做的不是一个只有 CRUD 的运动 App，而是围绕“运动数据如何可信结算、弱网如何不重复、AI 如何不越权、发布如何可回滚”做了一套闭环。移动端采集 GPS/步数/照片并支持离线补偿；后端通过会话状态、行锁、幂等记录、事务事件和 Outbox 保证一次结算；积分榜允许 Redis 降级到 MySQL；AI 只拿短时、最小权限的委派令牌读取白名单数据，结构化输出 proposal，用户或管理员确认后才写业务。测试覆盖认证重放、并发结算、Agent 状态机、模型适配、移动端异常和部署脚本。

### 1.3 2 分钟 STAR 主叙事

**S — Situation**

校园运动打卡同时有四类难题：手机网络和定位不稳定；客户端数据可能重复或不可信；排行榜、目标、积分涉及跨模块一致性；AI 建议和申诉预审涉及健康与权限风险。

**T — Task**

目标不是“接口能返回 200”，而是建立一条可恢复、可审计、可降级的链路：

- 一次运动最多结算一次；
- MySQL 永远是业务事实源；
- Redis、模型、网络短暂不可用时核心业务仍可用；
- AI 只能看当前 run 授权的数据，不能直接改业务；
- 关键写操作需要人确认；
- 构建、发布、回滚都有可验证门禁。

**A — Action**

我把系统拆成 Flutter、Spring Boot、MySQL、Redis 和独立 Python Worker。运动完成使用会话状态 + 数据库行锁 + 可选 Idempotency-Key；同事务更新目标与积分，并写 Outbox，再异步投影 Redis 排行榜。认证使用短时 JWT 和旋转 refresh token，旧 refresh 被重放时吊销整族。Agent 使用 Redis Streams 解耦，run 状态写 MySQL，Worker 用短时 scoped JWT 调内部只读工具，第一轮强制取证，Pydantic 校验结构，guardrail 拦截危险建议，最终只生成 proposal，由用户或管理员确认。

**R — Result**

[本轮验证] 后端 Surefire 155 个测试通过，0 失败、0 跳过；JaCoCo 行覆盖 83.73%、分支覆盖 65.93%，门禁通过。另有 2 个 Failsafe/MySQL Testcontainers IT 因 Docker 无权限而跳过。Agent 18 个 pytest 通过。并发测试验证 20 个线程同时结束同一运动时只生成 1 条运动记录、1 条 Outbox 和 1 次积分。Docker IT 与 Flutter 本轮受环境阻塞，必须明确列为未验证，不能包装成“全绿”。

### 1.4 面试中最重要的表达习惯

- 不说“用了 Redis 保证一致性”；应说“MySQL 保证事实一致性，Redis 是可重建投影”。
- 不说“AI 决策”；应说“AI 汇总证据并生成结构化建议，业务确认和写入仍在 Spring 事务中”。
- 不说“幂等就是前端防抖”；应说“防抖改善体验，服务端状态、唯一约束、行锁和请求指纹才是可靠边界”。
- 不说“测试都过了”；应列出跑过什么、跳过什么、为什么。
- 不说“绝对安全”；应说明威胁模型、已做控制和剩余风险。

## 2. 产品边界与角色

### 2.1 用户侧能力

- 密码注册/登录、邮箱或手机验证码注册/登录/重置；
- access token + refresh token 会话恢复；
- GPS、步数、拍照、手工录入多种运动；
- 周/月目标、统计、健康数据、提醒；
- 好友、积分、排行榜；
- 训练教练 Agent：根据目标、运动、健康和负荷生成计划 proposal；
- 申诉提交与进度查看。

### 2.2 管理侧能力

- 反馈处理；
- 申诉列表、审核和审计日志；
- 申诉预审 Agent；
- 必须由管理员确认或拒绝 Agent proposal。

### 2.3 非目标

- 不是医疗诊断系统，Agent 不能替代医生；
- 不是专业反作弊系统，GPS 异常规则只是基础风控；
- 不是多地域高可用生产集群；
- 不是“Agent 自主执行一切”的自动化平台；
- 当前仓库没有证明正式应用商店发布、正式签名密钥治理或大规模线上 SLO。

## 3. 总体架构：先掌握边界，再看代码

~~~mermaid
flowchart LR
    U["Flutter App"] -->|"Bearer JWT / REST"| N["Nginx"]
    N --> B["Spring Boot API"]
    B --> M[("MySQL 事实源")]
    B --> R[("Redis")]
    B --> F["上传文件"]
    B -->|"after commit: runId/type/traceId"| S["Redis Stream"]
    S --> W["Python Agent Worker"]
    W -->|"service key 换短时 scoped JWT"| B
    W -->|"受限只读 tools"| B
    W -->|"结构化推理"| L["DeepSeek API"]
    W -->|"message/proposal/result"| B
    B -->|"用户或管理员确认"| M
    B --> O["Actuator / Prometheus / OTel"]
~~~

### 3.1 为什么这样拆

| 决策 | 原因 | 得到什么 | 代价 |
|---|---|---|---|
| Flutter 单端多平台 | 一套 UI/业务状态可覆盖 Android 等终端 | 开发快、组件复用 | 原生能力和后台限制仍需平台适配 |
| Spring Boot 作为业务中心 | 事务、鉴权、数据访问、运维生态成熟 | 业务不变量集中 | Java 服务相对重 |
| Python 独立跑 Agent | Agents SDK、模型适配和评测生态更直接 | AI 快速迭代，不污染核心进程 | 多语言、多服务、一致性更复杂 |
| MySQL 为事实源 | 交易型状态需要事务、唯一约束和锁 | 可恢复、可审计 | 高并发要做索引和分库规划 |
| Redis 只做队列/投影 | Redis 快，但不是业务最终真相 | 故障时可降级、可重建 | 需要 Outbox、补偿和幂等 |
| Nginx 作为边缘入口 | 统一路由、TLS、限流入口 | 隐藏内部拓扑 | 配置错误会扩大攻击面 |

### 3.2 三条硬边界

1. **业务写边界**：只有 Spring Service + MySQL 事务能改变业务事实。
2. **Agent 权限边界**：Worker 不直连 MySQL；模型不直连 Spring；每个 run 只有短时、窄 scope、绑定主体的工具权限。
3. **发布授权边界**：CI 绿不等于允许部署。发布、服务器变更和公网验证必须由人显式授权。

## 4. 技术栈与“为什么不用别的”

| 层 | 当前技术 | 项目里的职责 | 面试追问与回答 |
|---|---|---|---|
| Mobile | Flutter 3 / Dart | 页面、状态、定位、步数、通知、图表、弱网队列 | “为什么 Flutter？”：团队规模下优先统一业务层；定位/通知仍封装平台权限和生命周期 |
| API | Java 21 / Spring Boot 4.1 | REST、事务、鉴权、领域编排 | “为什么不是 Node？”：运动结算和审核强调事务、类型与成熟数据生态；不是说 Node 做不到 |
| Security | Spring Security / BCrypt / HMAC / JWT | RBAC、密码哈希、access/refresh 生命周期、Agent 委派 | “JWT 是否无状态？”：access 校验无状态，refresh 与撤销状态在数据库 |
| Persistence | Spring Data JPA / Flyway | 聚合持久化、版本迁移、乐观版本字段 | JPA 省样板，但热点 SQL、锁和批量场景仍需显式设计 |
| Database | MySQL 8 | 用户、运动、目标、审核、Agent run 等事实 | ACID、唯一约束、行锁是核心一致性手段 |
| Cache/Queue | Redis 6.2 / Streams / Lua | Agent 队列、排行榜物化视图、去重 | 不是拿 Redis 替代数据库；丢失后应可从 MySQL 恢复 |
| Agent | Python 3.12 / FastAPI / OpenAI Agents SDK / DeepSeek | Worker、tools、guardrail、结构化输出、readiness | SDK 是编排层，供应商差异由 provider adapter 隔离 |
| Infra | Docker Compose / Nginx / TLS | 本地编排、边缘代理、Agent overlay | Compose 适合单机与作品集，不等于 K8s 高可用 |
| Observability | Actuator / Micrometer / Prometheus / OTel | 健康、指标、链路、JSON 日志 | liveness 只看进程；readiness 看依赖和 worker |
| Test | JUnit 5 / Mockito / Testcontainers / pytest / Flutter Test / JaCoCo | 分层验证 | 测试数量不等于质量，要把不变量映射到用例 |

## 5. 从数据库理解业务：表、所有权与不变量

### 5.1 Flyway 演进

| 迁移 | 新增/变化 | 设计意图 |
|---|---|---|
| V1 baseline | user_info、sport_record、sport_target、user_friend、health_data、reminder_config、appeal、feedback、target_reminder_read、验证码表 | 建立核心业务 |
| V2 auth | role、refresh_token | 从单一登录升级为 RBAC + 可轮换会话 |
| V3 workout core | version、sport_track_point、idempotency_record、outbox_event | 把轨迹规范化，补齐幂等与可靠事件 |
| V4 agent | agent_run、agent_message、agent_tool_audit、agent_action_proposal、training_plan | Agent 成为可审计领域，而非一次 HTTP 调模型 |
| V5 admin audit | proposal decision note、admin_audit_log | 管理确认留下责任链 |

### 5.2 关键表不变量

| 表/数据 | 谁能写 | 核心不变量 | 怎样测 |
|---|---|---|---|
| user_info | 用户服务/管理初始化 | 登录标识规范化、密码只存 BCrypt、role 受控 | 注册重复、错误密码、角色越权 |
| refresh_token | 认证服务 | 原 token 不落库；只存 SHA-256；同族可整体撤销 | 轮换、旧 token 重放、退出、过期 |
| verification_code | 验证码服务 | purpose/channel/target 隔离；一次性；次数/时间受限 | 过期、错码 5 次、重发/小时/日限额 |
| sport_record | 运动服务 | 同 session 只完成一次；仅 VALID 参与结算 | 重复 finish、异常轨迹、并发 20 次 |
| sport_track_point | 运动服务 | (record_id, sequence_no) 唯一；坐标和序号合法 | 批次重复、跨批重复、500 条边界 |
| idempotency_record | 运动服务 | 同 key + 同请求可重放；同 key + 不同请求拒绝 | 请求指纹冲突 |
| sport_target | 目标服务 | 只改自己的目标；完成度与指标单位一致 | 周/月边界、四类指标、越权 |
| outbox_event | 业务事务/投影处理器 | 与业务提交同生共死；消费可重试 | 回滚无事件、重复消费不重复计分 |
| appeal/feedback | 用户/管理员服务 | 所有权与管理角色隔离；状态迁移受控 | 非管理员 403、非法迁移、审计记录 |
| agent_run | Agent Gateway | 显式状态机；重试上限；绑定 owner/type | 非法转换、超时、重试终态 |
| agent_tool_audit | 内部工具层 | 每次调用记录 run/tool/主体/结果 | 越 scope、超 8 次、跨 run |
| agent_action_proposal | Agent + 确认服务 | 只能由对应主体确认；一次决策；可过期 | owner/admin 边界、重复确认、24h 过期 |
| training_plan | proposal 确认事务 | 只有已确认的训练 proposal 能落地 | 直接写、他人确认、回滚 |

### 5.3 当前数据模型的真实短板

- [已实现] Agent 相关表具有较清晰的关联和生命周期。
- [代码审查风险] 早期业务表较少使用数据库外键，删除/异常脚本可能制造孤儿数据。JPA 关系不等于数据库约束。
- [建议] 先统计孤儿和删除语义，再逐表补外键或显式软删除；不能直接在大表上“顺手加 FK”。
- [建议] 对高增长表规划归档、分区和冷热策略：轨迹点、工具审计、管理审计、Outbox 最先增长。

## 6. 核心链路一：认证、验证码与会话

### 6.1 access token

[已实现] JwtService 手工构造三段式 HS256 JWT：

- header 固定 alg=HS256、typ=JWT；
- claims 包含 iss、sub、role、iat、exp、jti；
- HMAC-SHA256 签名，常量时间比较；
- 校验算法、发行者、过期时间和角色；
- 默认 access 有效期 15 分钟，secret 至少 32 字节。

这是真正的紧凑 JWT 格式，但没有使用成熟 JOSE 库。它当前没有 aud、kid、密钥轮换或时钟偏差策略。面试时应说“最小可用的 JWT 实现”，不要说“完整企业级身份平台”。

### 6.2 refresh rotation 和 replay detection

~~~mermaid
sequenceDiagram
    participant A as App
    participant B as Auth API
    participant D as MySQL
    A->>B: login
    B->>D: 保存 SHA-256(refresh)，familyId
    B-->>A: access + raw refresh
    A->>B: refresh(old)
    B->>D: 找到 hash，撤销 old，链接 replacement
    B->>D: 保存 new hash
    B-->>A: new access + new refresh
    A->>B: 再次使用 old
    B->>D: 识别 replay，撤销整个 family
    B-->>A: 拒绝
~~~

为什么只存 refresh 哈希：数据库泄露时，攻击者不能直接拿存储值换会话。为什么要 family：单点轮换链里，旧 token 重放说明令牌可能被盗，吊销整族比只拒绝旧值更安全。

移动端：

- 完整 v2 session 存 flutter_secure_storage；
- 清理 SharedPreferences 中的旧 token；
- access 到期前 30 秒主动刷新；
- 同一 API 实例用 single-flight 合并并发刷新；
- 401 时最多刷新一次、重放一次，避免无限循环；
- 网络离线保留会话，服务端明确拒绝 refresh 才清理。

### 6.3 验证码

- 6 位 SecureRandom；
- 存 HMAC-SHA256(channel + purpose + target + code)，不存明文；
- 5 分钟过期、一次性、最多尝试 5 次；
- 目标维度 60 秒重发、5 次/小时、20 次/日；
- IP HMAC 维度 60 次/小时；
- debug code 只允许 local/test/demo/staging 开关；
- 生产手机通道未配置时引导使用邮箱。

### 6.4 认证失败场景与处理

| 场景 | 当前处理 | 原理/注意 |
|---|---|---|
| access 过期 | refresh 后重放一次 | 重放必须受次数限制 |
| 手机同时发多个请求 | 客户端 single-flight | 只保护同一进程实例 |
| refresh 被重放 | 吊销 family | 把“异常使用”视为凭据泄露 |
| 离线刷新失败 | 保留本地会话 | 网络错误不等于令牌非法 |
| 本地 session 损坏 | fail closed，清理 | 不猜测/拼接半个身份 |
| 管理员验证码登录 | 禁止 | 降低弱通道拿高权限 |

### 6.5 认证剩余风险

- **[代码审查风险]** 服务端 refresh 查询/轮换没有显式行锁；两个设备同时使用同一 refresh，可能各自产生新 token。客户端 single-flight 不能保护跨设备。应做 SELECT FOR UPDATE 或版本号 compare-and-set，并做并发压力测试。
- **[已确认设计缺口]** 密码 DTO 主要是非空校验，缺少长度、泄露密码和强度策略；管理员也没有 MFA。
- **[已确认设计缺口]** access JWT 不能单独撤销，只能依赖短 TTL 和 refresh 撤销。
- **[建议]** 用成熟 JOSE 库、aud、kid、多密钥验证窗口和轮换 runbook；把管理员账号接入 MFA/组织 IdP。
- **[建议]** IP 限流必须配可信代理链；只看请求头会被伪造。数据库 count 限流在并发/多实例下也应改为 Redis 原子桶或数据库锁。

## 7. 核心链路二：运动采集、幂等结算与弱网

### 7.1 状态和数据流

~~~mermaid
sequenceDiagram
    participant A as Flutter
    participant S as SportService
    participant D as MySQL
    participant R as Redis
    A->>S: start(mode)
    S->>D: 创建 DRAFT session
    A->>S: 分批上传 track points
    S->>D: 唯一键去重并保存
    A->>S: finish(session, summary, legacy 可选 / V1 必填 Idempotency-Key)
    S->>D: 按 session+user 加行锁
    S->>D: 校验/计算并写 VALID 或 ABNORMAL
    S->>D: 同事务更新目标、积分、写 outbox
    D-->>S: commit
    S-->>A: 返回同一条结果
    S->>R: 异步投影排行榜
~~~

### 7.2 轨迹验证和计算

- 每批最多 500 个点；
- sequence 必须非负，请求内不能重复；
- 纬度 [-90, 90]、经度 [-180, 180]；
- 数据库唯一键防止跨请求重复 sequence；
- 过滤精度误差大于 100m 的点；
- 按时间排序，使用 Haversine 计算球面距离，地球半径 6,371,000m；
- 相邻段速度超过 8m/s 标为异常；
- 热量采用 MET × 体重 kg × 小时，缺少体重时默认 60kg；
- 当前轨迹优先来自 sport_track_point；历史数据才回退 trackJson。

为什么不用客户端算出的距离直接当真：客户端处在不可信边界，可能有版本差异、浮点误差、重复点或伪造。当前代码仍允许部分模式传入 distance/calorie，以支持手工运动；对 GPS 模式也没有完全收紧，这是生产化时应优先区分的信任策略。

### 7.3 三层幂等

1. **会话状态**：已经不是 DRAFT，再次 finish 返回既有结果。
2. **数据库行锁**：并发 finish 串行看到同一状态。
3. **Idempotency-Key + 请求指纹**：V1 finish 强制请求头，旧 finish 兼容入口允许缺省；同 key 同请求可安全重放，同 key 不同请求拒绝。

再加两层副作用保护：

- 同一业务事务只生成一个 Outbox；
- Redis Lua 用 processed set 去重，再原子更新 ZSET/HASH。

[本轮代码事实] Flutter 当前调用旧 /api/sport/session/finish，且没有发送 Idempotency-Key；/api/v1/workouts/{sessionId}/finish 则要求该请求头。即使走旧入口，会话状态 + 行锁仍保护同一 session 的重复结算；但跨请求追踪、明确冲突语义和客户端持久重试会更弱。建议在 start 时生成并持久化 key，迁移到 V1，并在重试全程复用。

### 7.4 事务内与事务外

SportService 完成 VALID 运动时：

- BEFORE_COMMIT 事件更新目标进度；
- BEFORE_COMMIT 事件增加积分；
- 同事务写 Outbox；
- 任何一步抛错，运动完成和这些副作用一起回滚；
- Redis 排行榜更新在提交后异步做，失败不回滚已确认的运动。

这叫“强一致核心 + 最终一致投影”。不能把发 Redis 和数据库事务绑成伪分布式事务；否则 Redis 短暂故障会让用户连运动都保存不了。

### 7.5 排行榜

- 当前周按 Asia/Shanghai 计算；
- 全局周榜优先 Redis；
- 个人/好友范围从 MySQL 聚合；
- Redis 不可用时回退 MySQL；
- Outbox 处理器每次拉取最多 100 条；
- 失败后指数退避，最多约 60 秒；
- Lua 一次完成去重、分数/卡路里更新和 15 天 TTL；
- 投影可从 MySQL 重建。

为什么 Redis 不能做唯一事实源：缓存丢失、过期、主从切换或错误重建时，业务积分不应消失。Redis 的价值是低延迟排序，不是最终审计。

### 7.6 当前弱网队列：优点与必须承认的问题

[已实现] App 会在 finish 失败时将待同步记录放入 SharedPreferences，稍后重试；widget 用例覆盖排队和失败路径。

[已确认设计缺口] PendingFinishRecord 当前把 access token 和 GPS 轨迹一起以 JSON 明文放入 SharedPreferences。这绕开了 flutter_secure_storage，令牌和精确位置都属于敏感数据。

[建议] 重做为：

- 加密数据库或平台安全存储，只保留 payload、ownerId、idempotencyKey、状态，不保存 raw access token；
- 重放时使用当前会话获取 access；
- 队列项绑定用户，切换账号时不能串数据；
- 记录批次上传 ack，支持断点续传；
- 内容校验、最大容量、过期清理和坏数据隔离；
- finish 与轨迹批次共享持久化 idempotency 语义；
- 网络恢复采用指数退避 + jitter，避免惊群。

另一个取舍：当前轨迹批次上传失败可能被吞掉后继续 finish，保证“至少保住一条运动”，但会低估路径距离。产品上要明确是“保存摘要优先”还是“轨迹完整性优先”，并在 UI 标记数据不完整，不能静默装作完整。

## 8. 核心链路三：双 Agent 的受控自治

### 8.1 两个 Agent

| Agent | 输入证据 | 输出 | 谁确认 |
|---|---|---|---|
| Coach | 目标、近期运动、30 天健康趋势、完成度、28 天训练负荷 | CREATE_TRAINING_PLAN proposal 或 NEED_MORE_INFO | 运动者本人 |
| Appeal Reviewer | 申诉、运动记录、异常原因、规则证据 | REVIEW_APPEAL proposal 或 NEED_MORE_INFO | 管理员 |

训练负荷规则目前是确定性的：急性分钟数大于 420 为 HIGH，大于 180 为 MODERATE，否则 LOW。模型看到的是后端聚合证据，不是自行查询数据库。

### 8.2 一次 run 的完整状态机

~~~mermaid
stateDiagram-v2
    [*] --> QUEUED
    QUEUED --> RUNNING: worker claim
    RUNNING --> NEED_MORE_INFO: 缺证据
    RUNNING --> PENDING_CONFIRMATION: proposal
    RUNNING --> COMPLETED: 无动作结果
    RUNNING --> FAILED_RETRYABLE: 临时错误
    FAILED_RETRYABLE --> QUEUED: recovery republish
    FAILED_RETRYABLE --> FAILED_FINAL: retries exhausted
    PENDING_CONFIRMATION --> COMPLETED: owner/admin confirm or reject
    QUEUED --> EXPIRED: timeout/recovery
    RUNNING --> EXPIRED: timeout/recovery
~~~

MySQL 保存 run 真相；Redis Stream 只传 runId、type、traceId。创建 run 的事务提交后才 XADD，发布失败不会伪造“已提交失败”，而由 30 秒恢复任务重发 QUEUED/FAILED_RETRYABLE。

### 8.3 权限模型

Worker 先用服务密钥换一个短时 Agent delegation JWT：

- HS256；
- issuer、audience、subject、scope；
- 绑定 runId、业务 userId、resourceId、run type；
- TTL 限制在 30～300 秒；
- 每个内部工具请求再次检查当前 run 必须存在、类型/主体匹配且为 RUNNING；
- scope 必须包含 agent.internal；
- 单 run 最多 8 次工具调用；
- 所有工具调用写 agent_tool_audit。

即使 token 泄露，攻击窗口、可访问主体和能力也被压缩。服务密钥交换端点虽然在 SecurityConfig 中 permitAll，但控制器自行校验 service key；生产仍必须通过网络 ACL/Nginx 限制，不能只依赖“路径看起来内部”。

### 8.4 为什么第一轮强制 tool

只在 prompt 写“请先查证”并不可靠，模型可能直接回答。当前 provider 在第一轮通过 tool_choice 强制调用聚合工具：

- Coach 必须先调用 aggregate_coach_context；
- Appeal 必须先调用 aggregate_appeal_evidence；
- max turns 和工具上限都不超过 8；
- 整体模型超时不超过 45 秒；
- 未知 tool 名直接拒绝。

这体现一个通用原则：**必须发生的安全动作放进代码约束，不放在自然语言愿望里。**

### 8.5 结构化输出和 DeepSeek 适配

Agents SDK 发出的 json_schema 曾被 DeepSeek 兼容接口拒绝为 HTTP 400。适配层做了三件事：

1. 将 response_format 从 json_schema 转为 json_object；
2. 把所需 schema 注入 system instructions；
3. 仍由 Runner/Pydantic 在本地做最终类型校验。

不能只把格式改成 json_object 就结束：那只保证“像 JSON”，不保证字段和枚举正确。本地强类型验证才是最终契约。

Coach 与 Appeal 使用不同 Pydantic 输出模型、prompt version 和业务动作枚举，避免一个万能 prompt 把权限和语义混在一起。

### 8.6 Guardrail

- 输入侧正则拦截常见 prompt injection；
- 系统指令把业务证据标为 untrusted data；
- 输出侧拦截危险健康建议；
- proposal 类型采用白名单；
- 最终写操作在 Spring 再次做角色、所有权、状态和过期校验。

正则不能“解决提示注入”。它只是低成本一层；真正的边界是工具白名单、最小权限、数据/指令分离、结构化输出、业务端二次验证和人工确认。

### 8.7 重试、降级和就绪

可重试：

- 超时、网络错误、429、5xx；
- AgentRun 重试次数小于 3 时进入 FAILED_RETRYABLE。

不可盲目重试：

- 大多数永久 4xx；
- guardrail 拒绝；
- 权限或契约错误。

健康：

- /health 只表示进程存活；
- /ready 要求可用 worker、非空模型 key/服务 key、Redis ping；
- Worker 明确禁用时 readiness 返回 UP/DISABLED，而不是误报故障；
- 指标包含 run、失败、token/cost、延迟；
- JSON 日志可携带 traceId，OTel 可选。

模型不可用时，核心运动/目标/排行仍工作；Agent API 返回可理解的 unavailable/queued 状态。这是“非核心能力可降级”，不是吞错。

### 8.8 HITL：为什么不让 Agent 直接改

Coach proposal 不需要管理员，但必须由本人确认；Appeal proposal 必须由管理员确认。proposal 默认 24 小时过期，一次决策，写入 decision note 和审计。

Agents SDK 自带 Human-in-the-loop 暂停/恢复能力，但 FitLoop 采用数据库领域 proposal：

- 审批跨进程、跨会话，不能依赖 Worker 内存；
- 审批可能等几小时，需要持久化；
- 真正业务写入必须进入 Spring 事务；
- 角色、所有权和审计属于领域规则，不应交给模型运行时。

### 8.9 Agent 数据怎样测

| 维度 | 样例 | 断言 |
|---|---|---|
| 正常完整 | 有目标、4 周运动、健康趋势 | 必须先取证，输出 schema 合法 |
| 最小数据 | 新用户无运动 | NEED_MORE_INFO，不编造计划 |
| 边界负荷 | 180、181、420、421 分钟 | 风险分级边界准确 |
| 矛盾数据 | 目标要求高强度但健康风险高 | 输出保守，不能绕过 guardrail |
| 恶意数据 | 申诉文本含“忽略指令” | 数据不能变成 system instruction |
| 权限 | token 的 user/run/type 不匹配 | 401/403，不返回任何证据 |
| 调用预算 | 第 9 次工具调用 | 拒绝并审计 |
| schema | 少字段、错 enum、额外动作 | 本地验证失败，不生成 proposal |
| 临时故障 | 429、timeout、Redis 短断 | retryable + 恢复重发 |
| 永久故障 | 400、未知工具、guardrail | 不盲重试 |
| 人工确认 | 本人/他人/管理员、过期、重复 | 只有正确主体第一次能生效 |
| 可观测 | 同一 traceId 跨队列/工具/回调 | 可串起完整 run |

模型质量还需要离线评测集：

- 固定、脱敏、版本化证据集；
- 每类场景的必备事实、禁止动作、风险标签；
- schema pass rate、tool-use rate、groundedness、拒答准确率、proposal 接受率；
- prompt/model/provider 版本分桶；
- 先离线回归，再小流量影子/灰度；不能用真实健康数据随意喂第三方模型。

### 8.10 尚未证实但重要的 Agent 风险

**[代码审查风险] 回调非原子。** Worker 依次发 message、proposal、result，它们是三个 HTTP 事务。如果 proposal 已成功而 result 更新失败，重试可能遇到“proposal 已存在”的 409；当前 Worker 对部分 400/404/409 会丢弃并 ACK，run 可能暂留 RUNNING，再被恢复任务处理。这个风险需要在 proposal 成功后强制让 result 失败的故障注入实验，不能直接称为已复现 Bug。

[建议] 将回调设计为：

- 一个幂等 completion endpoint，一次提交 message + optional proposal + result；
- 或每一步有唯一 idempotency key 和可恢复 step 状态；
- “already exists” 返回既有资源并继续，而不是把整个 run 丢弃；
- 增加 callback-after-proposal 故障测试。

## 9. 测试体系：不是报数字，而是证明不变量

### 9.1 本轮结果

| 检查 | 结果 | 证据边界 |
|---|---|---|
| Maven integration profile / Surefire | 155 tests，0 failures，0 errors，0 skipped | [本轮验证] JDK 21 |
| Failsafe / MySQL Testcontainers | 2 个 IT 被发现，但 Docker pipe 无权限，配置 disabledWithoutDocker 后跳过 | [本轮未验证] 不能说通过 |
| JaCoCo | 行 2115/2526 = 83.73%；分支 505/766 = 65.93%；门禁通过 | [本轮验证] |
| Python Agent pytest | 18 passed，19.15s | [本轮验证] Python 3.12.13 venv |
| Python compileall | 成功 | [本轮验证] Python 3.12.6 |
| Flutter 测试声明 | 静态计数 29 widget + 18 unit = 47 | 只是声明数量，不是执行结果 |
| Flutter analyze/test | Flutter cache lockfile 无权限 | [本轮未验证] |
| Docker Agent E2E | Docker engine 不可访问 | [本轮未验证] |
| 真实 DeepSeek | 未调用 | 需要 key、成本和显式 live 确认 |
| 真机/公网/部署 | 未执行 | 不在本任务授权范围 |

README 当前还写着 154 个后端测试、46 个 Flutter 测试，已落后于本轮静态/运行统计；面试时优先报“某日期、某命令”的快照。

### 9.2 测试金字塔和职责

| 层 | 项目例子 | 能证明 | 不能证明 |
|---|---|---|---|
| 纯单元 | JWT、验证码、模型 provider、guardrail | 边界算法和契约 | 框架装配/真实数据库 |
| Service + Mock | Sport、Agent 状态机、Appeal | 业务分支、交互次数 | SQL 锁/索引行为 |
| Spring slice/API | Security、Controller、Agent Gateway | 鉴权、序列化、HTTP 状态 | 完整外部依赖 |
| H2 集成 | 多数 repository/service 流程 | 事务和基本映射 | MySQL 方言、真实锁 |
| MySQL Testcontainers | Flyway、生产 schema 映射 | MySQL 兼容和迁移 | 公网、真实数据规模 |
| 并发测试 | 20 次并发 finish | exactly-once 业务不变量 | 多节点/长时压力 |
| Agent mock/model stub | 完整 Coach/Appeal 协议 | 状态、tools、schema、回调 | 真实模型漂移 |
| Docker 隔离 E2E | MySQL+Redis+Backend+Worker+stub | 跨服务协议 | 真实 DeepSeek |
| Flutter unit/widget | session、API、页面、异常 UI | 客户端逻辑和交互 | 真机传感器/厂商后台 |
| Release build | Android release APK、R8 | release-only 问题 | 安装、系统权限、签名链 |
| Manual smoke | 36 项运行清单 | 真实部署/设备体验 | 自动回归速度 |

### 9.3 后端覆盖的关键问题

- 注册、密码/验证码登录、重置、管理员边界；
- JWT 篡改、过期、角色；
- refresh 轮换、重放吊销、退出；
- 头像 JPEG/PNG 魔数、MIME 不一致、大小；
- 运动模式、空轨迹、批次去重、finish 幂等；
- 20 线程并发 finish 最终 1 record、1 outbox、24 points；
- 目标所有权、周/月和 count/duration/distance/calorie；
- 排行榜范围、Redis 失败回退；
- 反馈、申诉、管理审计；
- Agent 状态机、队列发布、恢复、工具权限、调用上限、proposal 确认；
- 模块无环依赖、API 集成、Flyway classpath、MySQL 容器映射。

### 9.4 Agent 18 个测试覆盖的关键问题

- DeepSeek json_schema 到 json_object 的兼容转换；
- 第一轮强制 tool choice；
- backend client 把凭据放请求头而不是 body；
- Coach、Appeal、NEED_MORE_INFO、retry/readiness/credential；
- input injection 与危险健康建议 guardrails；
- demo 要求必需工具、拒绝未知工具；
- model stub 的强制 tool、schema 输出和未知 tool 拒绝。

### 9.5 Flutter 当前测试面

- secure session：保存/恢复/清理/旧格式失败关闭；
- auth API：到期刷新、401 refresh-replay、并发 single-flight、离线与拒绝；
- coach API：run/proposal/poll/confirm；
- 管理 API 和角色页面；
- 登录/注册/验证码/重置；
- dashboard、目标、健康、排行、申诉、提醒；
- 定位权限拒绝、低精度点过滤、最后一点补采；
- 传感器流错误、最终定位失败、finish 失败入队；
- Coach 明确确认、已保存计划、超时/过期/锁定/不可用状态。

还应该补：

- SyncQueue 敏感数据不落明文；
- 队列损坏、容量、过期、账号切换；
- Idempotency-Key 在重试中保持不变；
- 轨迹分批上传部分成功后的恢复；
- 真机权限、息屏、杀进程、时区/DST、电量优化；
- 多设备 refresh 并发。

### 9.6 “各种数据怎样测”的通用六面体

对每个输入，不要只测一条 happy path：

1. **等价类**：正常、缺失、格式错误、权限错误。
2. **边界值**：0/1/上限/上限+1，刚过期/刚未过期。
3. **状态迁移**：每个合法边、每个非法边、重复操作。
4. **并发/重放**：相同请求同时发、乱序、超时后重试。
5. **故障注入**：数据库提交前后、Redis 断开、模型 429、回调半成功。
6. **可观测性**：错误码、日志、指标、trace 和审计是否足够定位。

以 finish 为例，最小矩阵至少包含：

- 0/1/2/500/501 个轨迹点；
- 同批/跨批重复 sequence；
- 经纬度边界、时间乱序、100m 精度边界、8m/s 速度边界；
- 无/相同/冲突 Idempotency-Key；
- 两次顺序 finish、20 次并发 finish；
- 目标更新失败、Outbox 写失败、Redis 消费失败；
- 合法用户和其他用户；
- 手工模式与 GPS 模式的不同信任策略。

## 10. 安全设计与风险台账

### 10.1 威胁模型

资产：

- 账号、refresh/access token；
- GPS、健康、好友、申诉文本；
- 管理员权限和审核结果；
- Agent service key、模型 key；
- APK、签名身份和发布指针。

信任边界：

- 手机客户端不可信；
- 公网/Nginx 到后端；
- 后端到 Redis/MySQL；
- Spring 到 Python Worker；
- Worker 到第三方模型；
- CI/部署机到服务器和发布目录。

攻击者：

- 普通用户越权；
- token/设备被盗；
- 自动化验证码滥用；
- 上传恶意文件；
- prompt injection；
- 内部服务凭据泄露；
- 供应链或发布包被替换；
- 运维误操作。

### 10.2 已有控制

| 风险 | 当前控制 | 剩余边界 |
|---|---|---|
| 密码泄露 | BCrypt | 缺强度、MFA、泄露密码检查 |
| refresh 泄露 | 只存 hash、rotation、family replay revoke | 跨设备并发轮换待验证 |
| RBAC/IDOR | Spring Security + Service 所有权校验 | 每个新接口仍需负向用例 |
| 验证码爆破 | HMAC 存储、过期、次数和频率 | 分布式原子性、可信 IP |
| 重复运动结算 | 行锁、状态、幂等、唯一约束、Outbox | 客户端未发送 key |
| Redis 丢失 | MySQL 事实源、fallback/rebuild | 重建工具和告警需演练 |
| Agent 越权 | scoped 短时 JWT、run 绑定、工具白名单、审计 | service key 轮换和网络隔离 |
| 提示注入 | 数据/指令分离、输入/输出 guardrail、结构 schema、HITL | 正则可绕过，仍需红队评测 |
| 文件路径穿越 | 服务端生成文件名 | 内容安全仍不足 |
| APK 替换 | SHA-256、签名哈希、不可变目录、原子 current/previous | 正式 keystore 治理未完成 |
| 部署秘密泄露 | 生成脚本、权限 600、日志避免正文 | 应接入 secrets manager |

### 10.3 上传安全：头像与运动照片不是同一强度

- 头像：最大 5MB，检查 JPEG/PNG 魔数，并与 MIME 交叉验证，服务器 UUID 文件名。
- 运动照片：最大 10MB，当前主要检查 Content-Type 以 image 开头，扩展名可回退 .img。

所以不能笼统说“上传都做了文件头校验”。运动照片仍应补：

- 魔数 + 解码验证；
- 重新编码剥离 EXIF/GPS；
- 病毒/恶意 payload 扫描；
- 尺寸/像素炸弹限制；
- 私有对象存储 + 鉴权下载/短时签名 URL；
- X-Content-Type-Options: nosniff 和正确缓存策略。

当前 /uploads 是公开路由，照片与隐私策略必须在生产重新评估。

### 10.4 网络与配置风险

- Android network_security_config 仅给服务器 IP、localhost、模拟器地址放行明文 HTTP；这是过渡兼容，不是 TLS。
- TLS Nginx overlay 支持 TLS 1.2/1.3 和 HSTS，但 HSTS 时间当前较短，安全响应头仍不完整。
- 基础 Compose 的 backend 8080 可能绑定所有接口；MySQL、Redis、Agent 则更偏向 loopback。生产应让后端只在内部网络/127.0.0.1，由 Nginx 暴露。
- Swagger/OpenAPI 当前默认可访问；生产应关闭或认证。
- application/Compose 有占位默认 secret，长度可能仍满足启动校验。生产 profile 必须对已知占位值 fail fast，而不只是“长度够”。
- CSRF 对无 Cookie 的 Bearer API 关闭是合理的；如果以后引入 Cookie 登录，必须重新评估 SameSite、CSRF token 和 CORS。

### 10.5 P0/P1/P2 风险排序

**P0：上线前**

1. SyncQueue 不再明文保存 access token/GPS；
2. 强制 HTTPS，后端不直接暴露公网；
3. 所有占位 secret 在生产启动失败，模型/service key 进 secrets manager；
4. 运动照片做真实内容验证与隐私访问控制；
5. 正式 release keystore、签名审批和备份；
6. 管理员 MFA/强密码；
7. 给 client finish 接入持久 Idempotency-Key。

**P1：规模化前**

1. refresh 轮换数据库并发控制；
2. Agent completion 回调原子/幂等；
3. 验证码限流原子化；
4. Agent eval、红队和隐私脱敏；
5. Redis 重建/Outbox 积压演练；
6. 数据保留、删除、导出和审计策略。

**P2：持续演进**

1. JWT kid/轮换与组织 IdP；
2. 轨迹反作弊、设备证明与异常模型；
3. 多实例调度、分区和容量测试；
4. 更完整 CSP/安全头/WAF/上传扫描；
5. SLO、告警预算和灾难恢复演练。

## 11. CI、发布、回滚与运维

### 11.1 CI 实际检查

GitHub Actions 当前包含：

- Backend：JDK 21、Maven integration profile verify、JaCoCo 报告；
- Agent：compileall、pytest、隔离 Agent E2E；
- Mobile：pub get、锁文件不得漂移、analyze、test、release APK；
- Deploy：Bash 语法、PowerShell AST、备份/健康/监控/APK/runbook 合同测试；
- Compose：base、Agent、TLS、HTTPS 多种配置展开；
- PR：高严重度 dependency review。

为什么要构建 release APK：debug 正常不代表 R8/资源压缩/签名配置正常。仓库历史中的通知泛型 TypeToken 问题就是典型 release-only 风险：优化器看不见运行时反射需求。

### 11.2 健康检查分层

| 层 | 问题 | 示例 |
|---|---|---|
| Liveness | 进程活着吗 | Spring /actuator/health、Agent /health |
| Readiness | 现在能接流量吗 | DB/Redis、可用 Worker、key 配置 |
| Dependency | 外部依赖是否健康 | MySQL、Redis、模型接口 |
| Business smoke | 真业务能走通吗 | 登录→运动→积分、run→proposal→确认 |
| Release integrity | 用户拿到的是批准的包吗 | SHA、签名哈希、current 指针 |

只看 HTTP 200 不够。Agent 进程活着但无 worker、Redis 断开、key 为空时，不能标 ready。

### 11.3 APK 原子发布

install-apk.sh 的安全思路：

- 校验 SHA-256；
- 校验签名模式和批准的 signer hash；
- 每个 release 使用不可变目录；
- current/previous 用原子符号链接切换；
- lock/flock 防并发发布；
- 对文件和目录做 durable/fsync 确认；
- 失败时保留 previous 供回滚；
- HTTP 过渡包必须显式允许精确 URL。

这里“原子”指用户看到旧包或新包，不看到复制一半的文件；“durable”指成功响应前尽量确认元数据和内容落盘。二者不是同一个概念。

### 11.4 秘密、备份和监控

- secret 生成脚本使用强随机、拒绝覆盖、文件权限 600；
- Agent 默认关闭，启用时部署脚本检查模型 key 和 service key；
- MySQL 备份使用临时 client config，权限 600，trap 清理；
- 监控区分核心 readiness 与 Agent readiness；
- TLS 证书有效期纳入监控；
- 日志中不能出现密码、JWT、模型 key、真实健康/GPS 数据。

### 11.5 正确的发布权限语义

以下动作完全不同：

1. CI 通过：说明指定检查通过；
2. 构建产物：说明生成了文件；
3. 上传服务器：改变外部状态；
4. 激活 current：切换用户流量；
5. 发布 Release/商店：对外传播；
6. 回滚：也是服务器变更。

后四类必须显式授权。当前 Agent-only 部署历史处于暂停边界，本次文档工作没有恢复它，也没有连接服务器。

## 12. Vibe Coding：怎样用 AI，而不是被 AI 带着跑

### 12.1 仓库能证明什么

- mobile/assets/ai_generated 存在 AI 生成视觉资产；
- 提交历史以小步 PR、测试和运行手册为主；
- CONTRIBUTING 和提交模板明确不把 AI 上下文/任务草稿当产品文件提交；
- 仓库没有足够审计证据量化“多少代码由哪一个模型生成”。

因此面试中不能编造“80% 都是某模型写的”。可以诚实说 AI 用于探索、生成候选实现/测试、对抗审查和文档，但需求、架构、验收、秘密、发布权限由人负责。

### 12.2 适用于本项目的闭环

~~~mermaid
flowchart LR
    A["任务合同：范围/不变量/验收"] --> B["让 Agent 定位代码与风险"]
    B --> C["先复现或写失败测试"]
    C --> D["生成最小候选修改"]
    D --> E["人工审 diff/权限/数据边界"]
    E --> F["相关测试 + 构建"]
    F --> G{"证据充分?"}
    G -->|"否"| B
    G -->|"是"| H["小提交/CI"]
    H --> I["人工发布门禁"]
~~~

每一步的提问模板：

1. **任务合同**：“只修改 X；Y/Z 禁止改；成功标准是 A/B；先只读检查。”
2. **取证**：“给出调用链、现有测试、可复现步骤；把事实与假设分开。”
3. **实现**：“保持公开接口，最小 diff；不要升级依赖和全局格式化。”
4. **对抗审查**：“检查重放、并发、越权、事务边界、隐私、日志和回滚。”
5. **验证**：“列出实际运行命令、通过/跳过/失败数字；不要用 README 数字代替。”
6. **发布**：“CI 绿后停止，等待部署/推送的单独授权。”

### 12.3 哪些适合交给 AI

- 跨文件搜索和调用链地图；
- 为已知不变量生成边界/参数化测试；
- 生成 provider adapter、DTO、脚本合同的候选实现；
- 比较文档与当前代码，发现陈旧描述；
- 对 diff 做安全、并发、错误处理审查；
- 将日志/测试结果整理为可复核报告。

不应直接交给 AI 自主决定：

- 生产密钥、真实患者/健康/GPS 数据；
- 数据库删除、历史重写、部署和发布；
- 医疗建议、管理员最终审核；
- 高影响架构/依赖升级；
- 无证据情况下“随机改到不报错”。

### 12.4 一个好回答

> 我把 Vibe Coding 当成证据驱动的结对编程，不是自然语言抽奖。比如 DeepSeek 对 json_schema 返回 400，我先保留原始错误和最小复现，再让 Agent 比较 SDK 请求契约，提出 provider adapter；适配后用单测验证 response_format 转换、schema 注入和 Pydantic 校验，再用固定脱敏 demo 验证真实模型。AI 缩短搜索和样板时间，但“什么算正确”、权限边界和上线决定仍由我负责。

### 12.5 AI 生成代码的常见事故

| 事故 | 在 FitLoop 应怎样防 |
|---|---|
| 幻觉出不存在 API | 先从源码/官方文档检索，编译和契约测试 |
| 把 prompt 当权限控制 | 后端 RBAC、scope、状态和 schema 二次校验 |
| 修改范围扩散 | 路径白名单、先看 git status、逐文件 diff |
| 为了过测试弱化断言 | 修复前失败、修复后通过，审查断言语义 |
| 暴露 secret/真实数据 | 假数据、脱敏固定夹具、扫描 staged diff |
| 只跑 debug | CI 同时跑 release build、R8 和部署合同 |
| 自动部署 | CI/发布权限分离，人工批准 |

## 13. 八个可直接用于面试的 STAR 故事

### 13.1 弱网下运动不能重复结算

**S**：用户结束跑步时可能断网，客户端重试；服务端也可能同时收到多次 finish。
**T**：不能丢记录，也不能重复加目标、积分和排行榜。
**A**：以 session 为聚合键；finish 对 session+user 行锁；非 DRAFT 返回既有结果；可选 Idempotency-Key 保存请求哈希；目标和积分在提交前同事务更新；Outbox 同事务写，Redis 用 Lua 去重投影。
**R**：[已实现/测试] 20 个并发请求最终只有 1 条 record、1 条 outbox、24 points。
**继续追问**：“Redis 在提交后挂了？”——运动已完成，Outbox 保留并重试，排行榜可回退/重建。
**主动承认**：移动端尚未发送 Idempotency-Key，弱网队列还明文保存敏感数据，这是 P0。

### 13.2 让 AI 有用但不越权

**S**：训练建议涉及健康，申诉涉及管理员权限；模型会幻觉，也会受输入攻击。
**T**：Agent 必须基于真实证据、不能跨用户、不能直接写业务。
**A**：Worker 不接数据库；按 run 签发短时 scoped JWT；强制第一轮聚合工具；8 次调用预算；Pydantic 输出、危险建议 guardrail；只生成 proposal，Spring 由本人/管理员确认；所有工具/决策审计。
**R**：18 个 Agent 测试验证 provider、工具、guardrail、retry；仓库有隔离 E2E，但本轮 Docker 阻塞，没有冒充通过。
**继续追问**：“HITL 会不会只是一个按钮？”——确认端重新检查角色、所有权、run/proposal 状态、类型和过期，并在事务中写结果和审计。

### 13.3 解决模型供应商兼容差异

**S**：Agents SDK 的 json_schema 请求被 DeepSeek 兼容端点以 400 拒绝。
**T**：既要兼容供应商，又不能丢掉结构化输出保证。
**A**：provider adapter 将 json_schema 转 json_object，把 schema 注入系统指令，Runner 仍用 Pydantic 本地验证；同时通过 tool_choice 强制第一轮取证。
**R**：provider/model-stub 测试固定了转换和错误行为。
**原理延伸**：把编排协议和供应商协议隔离；adapter 是 anti-corruption layer，避免业务代码到处写 if provider。

### 13.4 Refresh rotation 与重放

**S**：长会话需要 refresh，但长期 token 被窃取后风险大。
**T**：数据库泄露不能直接换会话；被用过的 token 再出现要能发现。
**A**：只存 SHA-256，refresh 一次一换，记录 family 和 replacement；旧 token 重放时撤销整族；客户端 single-flight 避免同进程风暴。
**R**：轮换、replay、logout、expire 测试覆盖。
**主动承认**：跨设备并发轮换仍需 DB 锁/CAS 测试；single-flight 不是服务器并发控制。

### 13.5 Redis 排行榜既快又不绑架核心业务

**S**：周榜需要低延迟排序，但 Redis 可能丢数据或短暂不可用。
**T**：用户运动不能因为排行榜故障失败，排名也要能恢复。
**A**：MySQL 记录事实；同事务写 Outbox；异步 Lua 原子去重更新；读侧失败回退 MySQL；投影可重建。
**R**：Redis 正常/失败路径和 Outbox 唯一性有测试。
**原理延伸**：这是 CQRS 的轻量形态——写模型是关系数据，读模型是可丢弃投影。

### 13.6 Release-only 崩溃与测试策略

**S**：Flutter debug 正常，但 R8 会删除只通过反射使用的泛型签名，release 通知调度可能崩。
**T**：不能把 debug 绿当生产可用。
**A**：保留需要的 Signature/TypeToken 元数据；通知保存采用事务式替换，平台调用失败时恢复旧配置；CI 构建 release APK，手工清单验证安装/提醒。
**R**：把“release 构建”和“真机 smoke”变成正式门禁，而不是上线前临时点一点。
**原理延伸**：测试要贴近最终编译器、优化器、签名和运行环境。

### 13.7 APK 不完整上传和可回滚发布

**S**：直接覆盖固定 APK 文件，下载者可能拿到半文件；失败后也没有稳定回滚点。
**T**：发布切换必须原子、完整、可审计。
**A**：不可变 release 目录、SHA 和签名哈希、锁、fsync、current/previous 原子链接；激活与上传分离。
**R**：部署脚本合同测试验证拒绝错误包和回滚指针。
**主动承认**：正式 keystore 和真实服务器演练仍是生产前置条件。

### 13.8 用真实 MySQL 防止“测试数据库幻觉”

**S**：H2 能通过的实体映射、方言、索引或锁，在 MySQL 可能失败。
**T**：上线前让迁移脚本和生产 schema 真实装配。
**A**：Flyway 管版本；Testcontainers 启 MySQL，验证迁移和 JPA schema；CI 用 integration profile。
**R**：仓库有 2 个 MySQL IT。本轮 Docker 权限导致跳过，所以只报告“用例存在且被发现”，不说本轮通过。
**原理延伸**：mock/内存数据库回答“业务代码大致怎样”，真实容器回答“生产依赖真的怎样”。

## 14. 高频面试题库：问题、短答、深挖

### 14.1 架构与领域

**Q1：为什么不做一个 Spring 接口直接调用模型？**
A：同步调用会把模型延迟/故障传给核心请求，也缺持久状态、重试、审批和审计。当前 run 落 MySQL，Redis Stream 解耦，Worker 可独立扩缩，核心业务不依赖模型存活。

**Q2：Redis Stream 消息为什么只放 ID？**
A：避免复制敏感和易变业务数据；Worker 用 ID + 短时权限回源，读到当前事实。大 payload 还会增加重试、泄露和版本兼容成本。

**Q3：为什么 MySQL 是 Agent 状态真相，不是 Redis？**
A：run/proposal/审批需要事务、审计和长期恢复；Stream 只负责调度，丢失后可由恢复扫描重发。

**Q4：这是不是微服务？**
A：是模块化 Spring 核心 + 独立 Agent 服务，不应夸成完整微服务平台。业务模块仍在一个后端进程，共享 MySQL；拆 Agent 是因为运行时、故障域和迭代节奏不同。

**Q5：目标、积分为什么同事务，排行榜为什么不同事务？**
A：目标/积分是用户业务真相，必须和运动完成一致；排行榜是可重建读模型，异步能隔离 Redis 故障。

### 14.2 一致性、并发和数据

**Q6：乐观锁和悲观锁怎样选？**
A：finish 是短临界区且冲突代价高，用行锁串行更直观；普通低冲突更新可用 @Version 检测丢失更新。不能只加 @Version 却不处理重试。

**Q7：Idempotency-Key 存什么？**
A：scope/user/key、请求规范化哈希、结果资源标识和生命周期。同 key 同 hash 返回既有结果；不同 hash 是冲突。不要永久缓存完整敏感响应。

**Q8：Outbox 会不会重复？**
A：会，所以消费者必须幂等。当前发布表与业务同事务，Redis Lua processed set 做消费去重；数据库唯一性还保护一个 session 只生成一份核心副作用。

**Q9：事务事件为什么用 BEFORE_COMMIT？**
A：目标和积分失败时希望运动也失败，它们属于同一强一致边界。外部 Redis 不能放 BEFORE_COMMIT，否则外部调用不可回滚。

**Q10：时间边界怎样测？**
A：把 Clock/ZoneId 注入；测周/月第一毫秒、最后毫秒、跨年、闰日、Asia/Shanghai；若扩展国际用户再明确用户时区与存储 UTC。

### 14.3 安全

**Q11：JWT 最大问题是什么？**
A：不是“会不会签名”，而是撤销、密钥轮换、audience、泄露窗口和客户端存储。当前短 access + 有状态 refresh 缓解，仍应补 kid/轮换和管理员强认证。

**Q12：CSRF 为什么关？**
A：当前 API 用 Authorization Bearer，不依赖浏览器自动携带 Cookie，典型 CSRF 前提较弱；若以后用 Cookie，要重新启用防护。XSS/令牌泄露是另一类问题。

**Q13：怎样防 IDOR？**
A：不能只靠 URL 隐藏和前端按钮。Service 查询要带 currentUserId，管理接口校验角色；测试他人 ID 必须 403/404，且日志不能泄露资源细节。

**Q14：上传只检查扩展名够吗？**
A：不够。服务端生成文件名防路径穿越，魔数/解码防伪类型，重新编码/EXIF 清理防隐私，像素/大小限制防资源耗尽，私有存储防未授权访问。

**Q15：Prompt injection 怎样防？**
A：输入正则只能降噪；根本是数据与指令分离、工具白名单、scope、调用预算、结构化输出、业务端二次校验、HITL 和审计。

**Q16：模型供应商能看到什么？**
A：只应发送完成任务所需的最小脱敏聚合证据，不发 token、联系方式、精确 GPS 或无关历史；配置留存/地区/合规策略，并记录版本但不记录敏感 prompt 正文。

### 14.4 Agent

**Q17：为什么不用一个万能 Agent？**
A：Coach 与 Appeal 的主体、证据、动作和审批人不同。分模型/schema/tool 集合能缩小权限和测试空间，也便于独立版本、指标和降级。

**Q18：强制 tool_choice 有什么代价？**
A：保证取证，但可能多一次调用和延迟。对高风险决策值得；普通闲聊可以 auto。关键是按风险选择，不是全局强制。

**Q19：怎样评价 Agent 好不好？**
A：不能只看“回答像不像”。至少测 tool-use、schema pass、事实 groundedness、危险建议率、权限违规率、拒答准确率、proposal 接受/修改率、延迟和成本，并按 prompt/model 版本回归。

**Q20：HITL 为什么不是万能安全？**
A：审批人会疲劳、可能盲点确认。UI 要展示证据、差异、风险和不可逆影响；高风险动作分级，默认拒绝/过期，审计并抽样复核。

**Q21：怎样防 Agent 无限循环和烧钱？**
A：max turns、工具次数 8、45s timeout、token/成本指标、重试分类、每 run 预算和全局熔断。

**Q22：模型返回半截 JSON 怎么办？**
A：本地 schema validation 失败，按错误类别决定有限重试；永远不把部分对象直接写 proposal。记录 provider/status/trace，不记录敏感正文。

### 14.5 测试与质量

**Q23：覆盖率 83% 说明安全吗？**
A：不说明。覆盖率只是被执行；关键是不变量、负向权限、并发和故障测试。低价值 getter 可以拉高数字，高风险分支一条没测仍危险。

**Q24：为什么 H2 还要 Testcontainers？**
A：H2 快，适合多数测试；MySQL 容器覆盖方言、迁移、锁和 schema 差异。两者互补。

**Q25：真实模型测试为什么不能每次 CI 跑？**
A：非确定、成本、速率限制和数据合规。CI 用 stub 固定协议，周期性/发布前用固定脱敏集跑 live eval，记录 model/prompt 版本和容差。

**Q26：怎样测并发？**
A：先定义最终不变量，再用 barrier 让请求尽量同时进入，等待全部 future，查询数据库最终状态；重复多轮。还需在真实 MySQL、多节点和故障点做压力/线性化验证。

**Q27：测试失败但像环境问题，能直接跳过吗？**
A：不能说通过。先确认命令、版本、依赖和基线；若确属环境，报告被跳过的具体用例和风险。本轮就是这样报告 Docker/Flutter。

### 14.6 Flutter 与体验

**Q28：为什么客户端重试还要服务端幂等？**
A：客户端可被杀、篡改或存在多个设备；网络响应丢失时它不知道服务端是否成功。可靠性边界必须在服务端。

**Q29：定位精度差怎么办？**
A：过滤高误差点、补最后一点、异常速度标记；UI 告知数据质量。不能仅用一条阈值当专业反作弊。

**Q30：通知保存失败为什么要回滚配置？**
A：数据库/本地显示“已开启”但系统没排程会欺骗用户。先保留旧配置，平台调用失败恢复，保持 UI 状态与系统效果一致。

**Q31：为什么 release 模式单独测？**
A：R8、资源压缩、ABI、签名、网络安全配置只在 release 暴露；debug 测试覆盖不到。

### 14.7 运维与排障

**Q32：接口慢先看什么？**
A：按 trace 分段：Nginx、Spring controller/service、SQL、Redis、队列等待、模型延迟；看 p50/p95/p99、错误率和饱和度，不能先猜数据库。

**Q33：Redis 挂了怎样恢复？**
A：核心写继续进 MySQL/Outbox；读回退 MySQL；恢复 Redis 后按 Outbox 或事实表重建，比较校验和/总分，再切回。

**Q34：Agent 队列堆积怎么办？**
A：看 pending、oldest age、worker heartbeat、claim 失败、429/5xx；先止损/限流，再扩 worker 或修依赖。不能无脑重复发布制造更多消息。

**Q35：如何零停机迁移？**
A：expand-contract：先加兼容列/表，双读或回填，发布读新结构，验证，再删除旧结构。V3 的规范化轨迹 + legacy fallback 就是过渡思路。

**Q36：回滚应用是否也回滚数据库？**
A：通常优先前向兼容，不自动反向执行破坏性迁移。应用回滚要求新 schema 对旧应用兼容；数据库回滚需单独备份/恢复决策。

## 15. 与市面产品和大厂能力的相似处

这里谈的是**业务形态或工程模式相似**，不代表 FitLoop 达到对方规模、算法质量、合规或可用性。

| FitLoop 能力 | 相似产品/能力 | 相似点 | 关键差距 |
|---|---|---|---|
| 运动记录、目标、好友和排行 | [Strava 订阅功能](https://support.strava.com/en-us/articles/15402044-strava-subscription-features)、[Strava 社区](https://support.strava.com/en-us/collections/19657598-clubs-challenges-and-community) | 自定义目标、排行榜、挑战和社区互动 | Strava 的设备生态、路线/Segment、反作弊、全球规模远更成熟 |
| 训练计划与引导 | [Nike Run Club 训练计划](https://www.nike.com/help/a/nrc-plan)、[NRC App](https://www.nike.com/nrc-app) | 计划、教练引导、挑战 | FitLoop 是文本 proposal；NRC 有内容体系、音频引导和品牌教练 |
| 健康指标、目标和奖励 | [Apple Fitness](https://www.apple.com/apple-fitness-plus/)、[Apple 自定义计划](https://support.apple.com/en-us/108761) | 运动指标、活动闭环、奖励、个性计划 | Apple 有 Watch 传感器、设备端体验和健康平台整合 |
| 多运动类型、健康报告和跑步计划 | [华为运动健康](https://consumer.huawei.com/cn/mobileservices/health/)、[智能跑步计划](https://consumer.huawei.com/cn/support/content/zh-cn15850729/) | 多运动、指标、报告、适应性计划 | 华为有穿戴设备、传感器算法和大规模用户数据 |
| Agent tools/guardrails/HITL | [OpenAI Agents SDK](https://openai.github.io/openai-agents-python/)、[HITL 文档](https://openai.github.io/openai-agents-python/human_in_the_loop/) | tool、guardrail、结构输出、人工批准 | FitLoop 增加了 Spring/MySQL 的跨进程领域 proposal；不是照搬 SDK 内存状态 |
| 申诉预审 | 电商退款、内容审核、保险理赔预审的通用模式 | AI 汇总证据，人做最终决定，记录审计 | 未声称任何特定大厂使用相同内部实现；规则、合规和量级不同 |
| Outbox 排行榜 | 电商订单后积分/库存投影、内容计数器 | 事务事实 + 异步读模型 | FitLoop 是单库/单 Redis 的简化实现 |
| 原子 APK 激活 | CDN 静态资产版本化、蓝绿发布 | 不可变版本、原子指针、快速回滚 | 缺多节点/CDN 缓存失效和全量发布平台 |

如何在面试里回答：

> FitLoop 的表面功能类似 Strava/NRC/Apple Fitness/华为运动健康的一小部分，但我更想强调背后的可迁移能力：运动 finish 类似订单结算；Outbox 排行类似订单事件驱动的积分投影；Coach proposal 类似推荐草案；Appeal Agent 类似风控/客服预审。业务换了，幂等、权限、审计、HITL、降级和回滚这些工程原则仍然成立。

## 16. 这些技术在其他业务怎样复用

| FitLoop 技术 | 可迁移业务 | 映射 |
|---|---|---|
| session + 行锁 + 幂等 | 支付回调、订单提交、优惠券核销 | session→order/payment，积分→库存/余额 |
| Outbox + Redis 投影 | 消息未读数、热榜、库存看板 | MySQL 事实→Redis 读模型 |
| refresh rotation | SaaS、移动银行、管理后台 | 会话族、重放检测、设备管理 |
| 短时 scoped delegation JWT | RAG、自动化运维、客服 Agent | 每任务最小权限，不共享主凭据 |
| proposal + 人工确认 | 退款、封禁、理赔、合同审批 | AI 只准备动作，领域服务提交 |
| provider adapter | 多云短信、支付、LLM | 业务契约不被供应商差异污染 |
| model stub + live eval | 任何 LLM 产品 | CI 测协议，周期测真实质量 |
| 不可变产物 + 原子指针 | Web 静态发布、模型版本、配置发布 | build once，activate/rollback 分离 |
| readiness 分层 | 微服务和异步 Worker | 活着不等于可接业务 |

## 17. 把它当成自己手搓项目：建议的重建顺序

不要一上来复制所有模块。每一步都要能运行、能解释、能测试。

### 第 1 步：定义不变量和 API

先写：

- 用户只能读写自己的运动/目标；
- 同一 sport session 最多结算一次；
- 只有 VALID 运动产生目标、积分和排行事件；
- Agent 不能直接写业务；
- 管理动作必须审计。

建立最小 OpenAPI/DTO 与错误语义。此时先不用 Redis/AI。

**验收**：Controller 负向权限用例先存在；重复 finish 的预期返回确定。

### 第 2 步：认证

实现 BCrypt、短 access、refresh hash/rotation/family、SecurityFilterChain 和 current user 上下文。

**必测**：

- 错密码、篡改/过期 JWT；
- user/admin 交叉越权；
- refresh 一次轮换、旧值重放、logout；
- 两线程同 refresh 的并发测试。

### 第 3 步：运动聚合

先做 start→batch points→finish：

- 服务端生成 session；
- 唯一 (record, sequence)；
- 行锁和状态机；
- Haversine/异常速度；
- 可选请求指纹幂等。

**必测**：边界点、乱序、重复、越权、顺序/并发重复 finish。

### 第 4 步：同事务副作用

增加目标和积分，明确什么必须强一致。先在同一个 Spring 事务完成，不要提前上 MQ。

**必测**：目标更新抛错时运动也回滚；同一运动只加一次积分。

### 第 5 步：Outbox 与排行榜

业务事务只写 outbox_event；独立 processor 更新 Redis；读侧支持 MySQL fallback 和 rebuild。

**必测**：

- 提交失败无 outbox；
- 同事件重复消费不重复；
- Redis down 时核心写成功；
- 恢复后投影等于 MySQL 聚合。

### 第 6 步：移动端与离线

UI 状态先从纯状态机开始，再接定位/传感器：

- 权限 denied/deniedForever；
- 应用前后台/杀进程；
- 轨迹批次与 ack；
- 加密离线队列；
- owner + idempotencyKey；
- 当前会话重放。

**必测**：账号切换、token 过期、队列损坏、部分批次成功、finish 响应丢失。

### 第 7 步：Agent run，不接真实模型

先实现：

- AgentRun 状态机；
- Redis Stream 消息只放 ID；
- after-commit 发布与 recovery；
- model stub；
- message/proposal/result 回调；
- owner/admin confirm。

**必测**：非法状态、重复消息、发布失败、Worker 崩溃、proposal 过期和重复确认。

### 第 8 步：工具权限和真实编排

再加短时 scoped JWT、工具白名单、审计、调用预算、强制 first tool、Pydantic schema 和 guardrail。

**必测**：跨 run/user/type、token 过期、超预算、恶意证据、未知工具、坏 JSON。

### 第 9 步：Provider 与评测

先用 stub 固定协议，然后小规模接 DeepSeek：

- adapter 隔离格式差异；
- 固定脱敏 eval set；
- prompt/model/provider 版本；
- cost/latency/quality 指标；
- 自动回滚或 feature flag。

**必测**：429/5xx/timeout、400 永久错误、schema 漂移、供应商返回半截。

### 第 10 步：生产门禁

- TLS 和内部端口；
- placeholder secret fail fast；
- 上传隐私；
- 正式签名；
- 备份恢复；
- readiness/SLO/告警；
- 不可变产物、原子激活、回滚演练。

**验收**：CI、容器 E2E、release APK、真机 smoke、备份恢复、Redis rebuild、Agent 降级分别有证据；发布仍需人工授权。

## 18. 实际开发故障处置手册

原则：先判定影响面和事实，再止损；不要通过重启/重试抹掉证据。

### 18.1 登录突然大量 401

1. 看开始时间、版本、端点、access 还是 refresh；
2. 核对服务器时间、JWT issuer/secret 是否误变；
3. 看 refresh family replay 是否异常增长；
4. 检查客户端是否形成 refresh 风暴；
5. 若密钥泄露，按事件响应轮换并吊销；不要把日志中的 token 发到群里。

### 18.2 同一运动加了两次积分

1. 用 sessionId 查 sport_record、outbox_event 和积分变更；
2. 区分业务重复结算、重复 Outbox、Redis 投影重复；
3. 核对行锁查询、唯一键、状态和 Lua processed set；
4. 先冻结错误投影/补偿，不直接删事实；
5. 写能重现该竞态的 barrier 测试，再修最小边界；
6. 对受影响数据用审计脚本计算修复，不手改一条就宣布结束。

### 18.3 排行榜与 MySQL 不一致

1. 比较 period/scope/timezone，先排除查询语义不同；
2. 看 Outbox pending/failed/oldest age；
3. 查 Redis key TTL 和 processed set；
4. 用 MySQL 聚合生成只读差异报告；
5. 暂时走 fallback；
6. 清晰定义重建目标 key，再原子替换；不可用宽泛通配符删除 Redis。

### 18.4 Agent run 一直 RUNNING

1. 查 run 的更新时间、retry count、traceId；
2. 查 Stream pending、consumer、worker heartbeat；
3. 查 agent_tool_audit 到哪一步；
4. 查 message/proposal/result 是否部分成功；
5. 判断临时依赖故障、永久契约错误或回调幂等缺陷；
6. 只对确认可重试的 run 重发；不得批量重发所有历史消息。

### 18.5 模型成本或延迟突增

1. 按 model/prompt version/run type 分桶；
2. 看 tool loops、turn count、输入证据大小和重试；
3. 降低非必要上下文、缓存确定性聚合；
4. 限制 per-run/global budget，必要时关闭 Agent feature flag；
5. 用固定 eval 比较质量，不能只为便宜砍到危险建议增加。

### 18.6 Flutter 只在 release 崩

1. 获取设备型号、Android 版本、ABI、堆栈和符号；
2. 本地/CI 复现相同 release、R8、签名配置；
3. 检查反射、泛型 Signature、资源 shrink、平台权限；
4. 写/扩展 release smoke；
5. 不要用“禁用 R8”永久掩盖，除非明确评估体积和攻击面且只是短时止损。

### 18.7 上传目录出现可疑文件

1. 暂停公开访问或隔离具体对象；
2. 保留元数据和 hash 供调查，不直接打开；
3. 查上传主体、MIME、魔数、解码和访问日志；
4. 扫描同类文件和响应头；
5. 修内容验证/私有访问，再按隐私事件流程通知；
6. 不把样本提交 Git 或发给无关人员。

### 18.8 发布后核心健康但 Agent 不工作

1. 核心和 Agent readiness 分开判断；
2. 看 AGENT_ENABLED、worker heartbeat、Redis、service/model key；
3. 看 Stream backlog 和模型 429/401；
4. 核心业务正常时保持 Agent 降级，不要回滚整个系统；
5. 若发布涉及 Agent 协议不兼容，再回滚 Agent 或关闭 feature。

## 19. 代码导航：阅读顺序和关键入口

### 19.1 API 面地图

项目同时保留早期 /api 路径与较规范的 /api/v1 路径；继续演进时应兼容迁移，不能一次删除旧端点。

| 域 | 主要端点 | 权限/用途 |
|---|---|---|
| 用户与旧登录 | POST /api/user/register、/api/auth/login、/api/auth/password/reset；GET /api/user/profile；PUT /api/user/update | 注册公开；资料需本人 |
| V1 会话 | POST /api/v1/auth/login、/refresh、/logout | login/refresh 公开；logout 撤销会话 |
| 验证码/特性 | POST /api/verification/send；GET /api/config/features | 公开但受目的/频率控制 |
| 运动旧接口 | POST /api/sport/session/start、/track、/finish、/photo；GET /api/sport/list | 本人运动；finish 是兼容入口 |
| V1 运动 | POST /api/v1/workouts/{sessionId}/track-points:batch、/finish；GET /api/v1/workouts | batch/cursor/idempotency 语义 |
| 目标 | POST /api/targets；GET /api/targets/current；PUT/DELETE /api/targets/{id} | 所有权校验；保留旧 add/info alias |
| 统计/健康 | GET /api/stat/sport、/sport/history、/health/history；POST /api/stat/health | 本人数据 |
| 社交 | GET /api/social/ranking、/medal、/friends、/friends/search；POST /api/social/friend | 排行 scope + 好友关系 |
| 提醒 | GET /api/reminders、/targets；PUT /api/reminders/{id}、/targets/{targetId}/read | 配置和目标提醒已读 |
| 申诉/反馈 | POST/GET /api/appeals、/api/feedback | 用户提交和查看自己的数据 |
| 管理 | /api/admin/users、stats、appeals、feedback；/api/v1/admin/appeals；/api/v1/admin/audit-logs | ADMIN |
| Coach Agent | POST /api/v1/agent/coach/runs；GET /runs/{id}、/events、/training-plans；POST /actions/{id}/confirm或reject | 用户本人 |
| Appeal Agent | POST /api/v1/admin/appeals/{id}/agent-review；GET /api/v1/admin/agent/runs、/{id}/audit | ADMIN |
| Agent 内部回调 | /internal/v1/agent/runs/{id}/delegation-token、claim、messages、proposals、result | service key 换 token或 scoped Agent token |
| Agent tools | /internal/v1/agent-tools/coach/*、/appeals/{id}/evidence、/rules | agent.internal + run 上下文 |

返回设计时要保持三层错误：

- 400：输入/状态/幂等冲突等调用者可修正问题；
- 401/403：未认证与已认证但无权限；
- 404：资源不存在或为避免 IDOR 泄露而不暴露；
- 409：重复 proposal、状态竞争等资源冲突；
- 5xx/503：服务端或依赖临时故障，可按策略重试。

具体状态以 ControllerAdvice 和对应测试为准，不要仅凭上表给所有端点硬套同一个错误码。

### 19.2 先读文档/配置

1. README.md：能力、版本和快速启动；
2. docs/ARCHITECTURE.md：模块边界；
3. docs/AGENT_DEMO.md：mock、真实模型、容器 E2E 的严格分层；
4. .github/workflows/ci.yml：真实 CI 命令；
5. backend/pom.xml、agent-service/pyproject.toml、mobile/pubspec.yaml；
6. deploy/docker-compose*.yml、DEPLOYMENT.md 和 smoke checklist。

### 19.3 认证

- backend/src/main/java/com/fitloop/security/JwtService.java
- backend/src/main/java/com/fitloop/security/SecurityConfig.java
- backend/src/main/java/com/fitloop/security/RefreshToken.java
- backend/src/main/java/com/fitloop/user/VerificationCodeService.java
- mobile/lib/auth_session.dart
- mobile/lib/api_services.dart

### 19.4 运动/目标/排行

- backend/src/main/java/com/fitloop/sport/SportService.java
- backend/src/main/java/com/fitloop/sport/V1SportController.java
- backend/src/main/java/com/fitloop/social/RankingOutboxProcessor.java
- backend/src/main/java/com/fitloop/common/DomainEventOutbox.java
- backend/src/main/resources/db/migration/V3__workout_core_and_outbox.sql
- mobile/lib/sync_queue.dart

### 19.5 Agent

- backend/src/main/java/com/fitloop/agent/AgentGatewayService.java
- backend/src/main/java/com/fitloop/agent/AgentRun.java
- backend/src/main/java/com/fitloop/agent/AgentDelegationTokenService.java
- backend/src/main/java/com/fitloop/agent/AgentToolController.java
- agent-service/src/fitloop_agent/worker.py
- agent-service/src/fitloop_agent/workflows.py
- agent-service/src/fitloop_agent/provider.py
- agent-service/src/fitloop_agent/backend.py
- backend/src/main/resources/db/migration/V4__agent_gateway.sql

### 19.6 测试入口

- backend/src/test/java/com/fitloop/sport/SportServiceTest.java
- backend/src/test/java/com/fitloop/security/JwtServiceTest.java
- backend/src/test/java/com/fitloop/agent/AgentGatewayIntegrationTest.java
- agent-service/tests/test_worker.py
- agent-service/tests/test_provider.py
- agent-service/tests/test_guardrails.py
- mobile/test/widget_test.dart
- mobile/test/auth_session_api_test.dart

## 20. 本地验证命令和环境要求

从仓库根目录执行。不要把 secret 放命令行历史。

### Backend

PowerShell 临时指定 JDK 21：

    $env:JAVA_HOME = 'C:\Program Files\Java\jdk-21.0.11'
    $env:Path = "$env:JAVA_HOME\bin;$env:Path"
    Set-Location backend
    mvn --batch-mode --settings ..\.github\maven-settings.xml -U -Pintegration-tests verify

注意：Testcontainers 需要可访问的 Docker engine。看到 BUILD SUCCESS 仍要检查 failsafe 的 skipped 数字。

### Agent

    python -m compileall -q agent-service\src agent-service\tests
    python -m pytest agent-service

若使用仓库已有隔离 venv，应先确认 Python/依赖版本；不要在文档任务中擅自安装全局包。真实模型 demo 还需要显式确认、临时 key、固定脱敏证据，完成后清理。

### Mobile

    Set-Location mobile
    flutter pub get
    flutter analyze
    flutter test
    flutter build apk --release

本轮当前机器的 Flutter SDK cache lockfile 无权限，以上命令未成功执行。修复方式应是让 SDK 位于当前用户可写目录或修正准确目录权限，不应递归修改整个磁盘权限。

### Docker E2E

使用 docs/AGENT_DEMO.md 中的仓库命令和 deploy/docker-compose.agent-e2e.yml。隔离 E2E 使用 model stub，不等于真实 DeepSeek；真实 demo 也不等于跨模块 E2E。

## 21. 面试现场的“不能说”和“应该说”

| 不要说 | 应该说 |
|---|---|
| “项目已经生产上线” | “main 是 0.1.7+8；README 记录公开包更旧，本轮未做线上验证” |
| “所有测试都通过” | “Java 155 和 Agent 18 本轮通过；Docker IT 跳过、Flutter 环境阻塞” |
| “JWT 很安全” | “HS256、短 TTL、refresh rotation 已做；aud/kid/MFA/并发轮换仍需补” |
| “Redis 保证一致性” | “MySQL 事务保证核心一致性，Redis 投影幂等、可降级、可重建” |
| “AI 自动审核” | “AI 预审并生成 proposal，管理员做最终确认” |
| “用正则防 prompt injection” | “正则只是外层；真正边界是工具权限、schema、二次校验和 HITL” |
| “客户端做了幂等” | “服务端会话/锁/请求指纹保证；客户端还需传 Idempotency-Key” |
| “上传文件都校验了文件头” | “头像做了魔数；运动照片目前主要是 MIME，仍需加固” |
| “Vibe Coding 提高了十倍效率” | “AI 缩短搜索/样板/测试草拟；我用失败复现、diff 和测试证据约束质量” |
| “没有 Bug” | “列出已验证不变量、未验证环境和风险优先级” |

## 22. 5 分钟白板讲解顺序

1. 画 Flutter→Spring→MySQL，强调业务事实源；
2. 在右侧加 Redis 投影和 Outbox，讲一次结算；
3. 再加 Stream→Worker→tools/model，讲 Agent 不直连数据库；
4. 画 proposal→本人/管理员确认，讲 HITL；
5. 用一条红线圈出公网/内部/模型三个信任边界；
6. 最后报测试证据和一个诚实缺口。

推荐收尾：

> 这个项目最有价值的不是用了多少框架，而是我为每个不可靠边界指定了责任：客户端可以重试但服务端必须幂等；Redis 可以丢但 MySQL 能重建；模型可以犯错但不能越权写；CI 可以全绿但不能替人做发布决定。下一步我会优先修离线队列敏感数据、refresh 并发和 Agent 回调原子性，再做真实容器、真机和模型评测。

## 23. 自测题

如果能不看文档回答下面问题，才算真正掌握：

1. 为什么 sport finish 需要行锁，@Version 不够吗？
2. Idempotency-Key 和 session 状态分别解决什么？
3. Outbox 在哪一个事务中写，Redis 在什么时候更新？
4. Redis 丢库后怎样证明重建结果正确？
5. 为什么 refresh 存哈希，为什么要 family？
6. 客户端 single-flight 为什么不能修复跨设备并发？
7. Coach 第一轮为什么强制工具？最多几次？
8. Agent delegation token 绑定了哪些上下文？
9. proposal 确认时后端要重查什么？
10. json_object 和 schema validation 的差别是什么？
11. model stub E2E、真实模型 demo、完整 E2E 各证明什么？
12. 本轮哪些测试实际通过，哪些没有？
13. 头像与运动照片的校验差异是什么？
14. SyncQueue 当前泄露了什么，怎样改？
15. 为什么 Agent readiness 不能等同于 /health？
16. APK 原子切换和 durable 写入分别解决什么？
17. 如果 proposal 成功而 result 回调失败，会发生什么？怎样验证？
18. 为什么 FitLoop 可以类比订单结算、退款预审和读模型投影？

## 24. 术语速查

- **ACID**：数据库事务的原子性、一致性、隔离性、持久性。
- **幂等**：重复执行同一语义请求，最终业务效果与一次相同。
- **Outbox**：在业务事务里写待发布事件，提交后异步投递。
- **CQRS 读模型**：写入事实与为查询优化的投影分离。
- **HITL**：Human in the Loop，人处在高风险动作确认环。
- **Guardrail**：对输入、工具、输出或动作施加的运行时约束。
- **Scoped token**：只允许特定主体、资源、动作和短时间窗口的凭据。
- **Replay**：攻击者或客户端再次使用已经消费的凭据/请求。
- **Liveness/Readiness**：进程是否活着/是否适合接收流量。
- **Golden dataset**：固定、版本化、可重复的评测数据集。
- **Fault injection**：主动让依赖或某一步失败，验证恢复语义。
- **Atomic activation**：用一个原子指针让流量从完整旧版本切到完整新版本。

---

本手册是 2026-08-04 的代码快照。以后每次改认证、finish、Agent 状态机、数据库迁移或发布流程，都应同时更新对应不变量、测试证据、风险台账和面试表述；否则文档会比代码更快失真。
