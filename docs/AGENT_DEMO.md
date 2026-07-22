# FitLoop Agent 可重复演示

本文用于在本地或面试现场验证 FitLoop 的两个真实 DeepSeek Agent：训练教练与申诉审批。演示不需要域名、SMTP、MySQL、Redis 或正在运行的 Spring Boot；它使用固定脱敏证据隔离外部依赖，真实执行模型调用、工具编排、结构化输出校验和安全护栏。

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

演示命令是模型层的可重复验证，不伪装成完整 E2E。完整链路还需要 MySQL、Redis、Spring Boot、Agent Worker、测试用户和申诉数据，适合在隔离测试环境中运行。

## 本次兼容性修复的面试讲法

OpenAI Agents SDK 默认把 Pydantic 输出类型转换成 OpenAI `json_schema` 响应格式，而 DeepSeek V4 当前只接受 `text` 或 `json_object`。真实调用因此返回 400。解决方案是在 provider 适配层将结构化请求转换为 `json_object`，把 schema 注入系统指令，同时保留 Runner 的原始 schema，让 Pydantic 在本地继续严格校验。这样没有绕过校验，也没有把供应商差异泄漏到业务工作流。

第二个问题是提示词虽然要求读取证据，模型仍可能随机跳过工具。最终方案不是继续堆提示词，而是由 Agents SDK 在首轮指定证据聚合工具；工具执行后 SDK 恢复自动选择，再允许模型输出结论。这个改动把关键业务约束从概率性提示词提升为确定性代码约束。
