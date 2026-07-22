# FitLoop Agent 可重复演示

本文用于在本地或面试现场验证 FitLoop 的训练教练与申诉审批 Agent。仓库提供三个互补层次：无外部副作用的跨模块测试、使用固定脱敏证据的真实 DeepSeek 模型演示，以及隔离 MySQL/Redis 的完整容器 E2E。三者分别验证代码契约、模型行为和系统集成，不能相互冒充。

## 演示验证了什么

- DeepSeek `deepseek-v4-flash` 教练模型和 `deepseek-v4-pro` 审批模型可访问。
- Agents SDK 首轮强制调用证据聚合工具，不能跳过业务证据直接生成答案。
- 教练工具读取目标、近期运动、健康趋势、目标完成率和 Java 侧确定性训练负荷。
- 审批工具同时读取申诉证据与异常规则；模型只给建议，管理员保留最终决定权。
- DeepSeek 的 `json_object` 模式负责保证合法 JSON，本地 Pydantic schema 继续验证字段、枚举和数值边界。
- 演示后检查必要工具调用清单；缺少任何核心证据时命令以非零状态退出。

固定证据只替代 Java 内部工具接口的数据来源。模型、提示词、工具调度、输入/输出护栏和 schema 校验均使用生产代码。

## Windows PowerShell 完整步骤

在仓库根目录执行：

```powershell
cd D:\AIWorkspace\projects\FitLoop

py -3.12 -m venv .\agent-service\.venv
& .\agent-service\.venv\Scripts\python.exe -m pip install --upgrade pip
& .\agent-service\.venv\Scripts\python.exe -m pip install -e ".\agent-service[test]"
```

确认仓库根目录未跟踪的 `.env` 至少包含：

```dotenv
DEEPSEEK_API_KEY=你的真实Key
DEEPSEEK_BASE_URL=https://api.deepseek.com
DEEPSEEK_COACH_MODEL=deepseek-v4-flash
DEEPSEEK_APPEAL_MODEL=deepseek-v4-pro
```

不要把 `.env`、Key 或命令输出中的秘密提交到 Git。运行双 Agent：

```powershell
$env:PYTHONUTF8="1"
& .\agent-service\.venv\Scripts\fitloop-agent-demo.exe `
  --env-file .\.env `
  --mode all `
  --confirm-live-api
```

也可以只运行一个工作流：

```powershell
& .\agent-service\.venv\Scripts\fitloop-agent-demo.exe --env-file .\.env --mode coach --confirm-live-api
& .\agent-service\.venv\Scripts\fitloop-agent-demo.exe --env-file .\.env --mode appeal --confirm-live-api
```

`--confirm-live-api` 是显式费用确认开关；缺少该参数时命令拒绝调用外部模型。

## 成功判定

输出首行应为：

```text
live-agent-demo=SUCCESS
```

教练结果的 `tools` 至少包含：

```text
get_user_goals
get_recent_workouts
calculate_training_load
```

审批结果的 `tools` 必须包含：

```text
get_appeal_evidence
get_anomaly_rules
```

结果还会输出模型名、输入/输出 token 数和通过 Pydantic 校验后的业务 JSON，但不会输出 API Key。

## 一键验证 Java + Spring + Agent

以下命令不会启动 Docker，不连接现有 MySQL，也不会修改本地业务数据。它会运行 Spring Agent 状态机、Redis Stream 消息契约、委托令牌/人工确认边界、Python Worker、供应商适配层和护栏测试：

```powershell
cd D:\AIWorkspace\projects\FitLoop
powershell -ExecutionPolicy Bypass -File .\scripts\verify-agent-stack.ps1
```

加入真实 DeepSeek 教练与审批演示：

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\verify-agent-stack.ps1 `
  -Live `
  -EnvFile .\.env
```

脚本自动查找仓库现有 Python 3.12 虚拟环境和常见安装位置中的 JDK 21。找不到时可显式指定：

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\verify-agent-stack.ps1 `
  -JavaHome "C:\Program Files\Java\jdk-21.0.11" `
  -PythonExecutable .\.tmp-agent-venv\Scripts\python.exe
```

最终成功标志为 `agent-stack-verification=SUCCESS`。其中 Redis Stream 使用 mock 锁定 Java 发布给 Python Worker 的 `runId`、`type`、`traceId` 字段契约；该命令是无数据库副作用的跨模块验证，不冒充容器级 E2E。

## 完整容器 E2E（推荐的面试主演示）

前置条件只有 Docker Desktop 正常运行。命令不读取仓库 `.env`，不需要 DeepSeek Key、SMTP 或域名，也不会连接现有 MySQL/Redis。Compose 使用独立项目名、`127.0.0.1:18080/18090` 端口和专用数据卷：

```powershell
cd D:\AIWorkspace\projects\FitLoop
docker version
powershell -ExecutionPolicy Bypass -File .\scripts\run-agent-e2e.ps1
```

脚本执行以下真实链路：

1. 从空 MySQL 库执行 Flyway，并通过 `agent-e2e` Profile 写入隔离测试用户、运动、健康、目标和待审申诉。
2. 用户登录后创建教练 run；Spring 发布 Redis Stream，Python Worker 交换短期委托令牌并通过 Agents SDK 强制读取五类 Spring 证据。
3. 检查工具审计后，确认 run 停在 `WAITING_APPROVAL`；只有所属用户确认后才创建训练计划。
4. 管理员创建申诉审核 run；Worker 读取申诉证据和确定性异常规则；只有管理员确认后才更新申诉状态。
5. 输出不含令牌的摘要，并自动删除该 Compose 项目的容器、网络和数据卷。

成功输出包含：

```text
"status": "SUCCESS"
"coachToolCalls": 5
"appealToolCalls": 2
agent-container-e2e=SUCCESS
```

如需在成功后检查容器和 API，可保留隔离栈：

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\run-agent-e2e.ps1 -KeepRunning
docker compose --project-name fitloop-agent-e2e --file .\deploy\docker-compose.agent-e2e.yml ps
```

检查结束后必须清理同一个隔离项目：

```powershell
docker compose --project-name fitloop-agent-e2e `
  --file .\deploy\docker-compose.agent-e2e.yml `
  down --volumes --remove-orphans
```

E2E 使用确定性的 OpenAI Chat Completions 兼容模型桩，因此不会产生模型费用；但 Agent、Runner、function tools、Redis 消费、Spring 权限和业务写入都走生产代码。需要验证 DeepSeek 供应商兼容性时，再单独运行前文带 `--confirm-live-api` 的真实模型演示。

## 完整应用中的真实链路

```text
用户/管理员 REST 请求
  -> Spring Boot 创建 AgentRun 并写入 Redis Stream
  -> Python Worker 领取任务并交换短期委托令牌
  -> 强制证据聚合工具调用 Spring 内部只读接口
  -> DeepSeek 生成 CoachOutput / AppealDecision
  -> Worker 回写消息、审计、token 用量和 ActionProposal
  -> 教练方案由用户确认；审批建议由管理员确认
```

公开入口：

- 教练：`POST /api/v1/agent/coach/runs`
- 申诉审批：`POST /api/v1/admin/appeals/{appealId}/agent-review`
- Agent 存活：`GET http://127.0.0.1:8090/health`
- Agent 就绪：`GET http://127.0.0.1:8090/ready`

真实 DeepSeek 演示是模型层的可重复验证；`run-agent-e2e.ps1` 才是包含 MySQL、Redis、Spring Boot、Agent Worker、测试用户和申诉数据的完整隔离链路。两者在 CI 和面试讲解中应分别陈述。

## 本次兼容性修复的面试讲法

OpenAI Agents SDK 默认把 Pydantic 输出类型转换成 OpenAI `json_schema` 响应格式，而 DeepSeek V4 当前只接受 `text` 或 `json_object`。真实调用因此返回 400。解决方案是在 provider 适配层将结构化请求转换为 `json_object`，把 schema 注入系统指令，同时保留 Runner 的原始 schema，让 Pydantic 在本地继续严格校验。这样没有绕过校验，也没有把供应商差异泄漏到业务工作流。

第二个问题是提示词虽然要求读取证据，模型仍可能随机跳过工具。最终方案不是继续堆提示词，而是由 Agents SDK 在首轮指定证据聚合工具；工具执行后 SDK 恢复自动选择，再允许模型输出结论。这个改动把关键业务约束从概率性提示词提升为确定性代码约束。
