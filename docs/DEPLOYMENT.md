# FitLoop 部署与运维指南

本文适用于短期受控 HTTP 过渡版 `0.1.7+8`。任何 push、证书切换、服务器部署或 APK 发布都必须在执行前单独确认。

需要从 PR、域名、密钥、证书一路执行到真机、发布和回滚时，直接使用 [人工发布执行手册](MANUAL_RELEASE_RUNBOOK.md)。

## 1. 服务拓扑与降级边界

| 服务 | 容器 | 对外入口 | 就绪条件 |
| --- | --- | --- | --- |
| MySQL 8 | `fitloop-mysql` | 仅宿主机 `127.0.0.1:3306` | `mysqladmin ping` |
| Redis 6.2 | `fitloop-redis` | 仅宿主机 `127.0.0.1:6379` | `redis-cli ping` |
| Spring Boot | `fitloop-backend` | `8080`，由 Nginx 代理 | `/actuator/health` |
| Agent | `fitloop-agent-service` | 仅宿主机 `127.0.0.1:8090` | 内部 `/ready` |
| Nginx | `fitloop-nginx` | `80/443` | 只依赖 Backend healthy |

Agent readiness 会检查 worker、Redis 和必要配置。Agent 或 DeepSeek 不可用时，核心登录、运动、管理接口和 APK 下载仍应工作；`/ready` 不通过 Nginx 暴露。

## 2. 生产前置条件

- 已备案域名解析到服务器，或已确认服务器使用长期固定的公网 IP；安全组开放
  `22`、`80`、`443`，不要开放 `3306`、`6379` 或 `8090`。固定公网 IP
  使用 [IP HTTPS 发布补充手册](IP_HTTPS_RELEASE_RUNBOOK.md)。
- 生产主机安装 Docker、Docker Compose、curl、openssl、bc、Python 3 和
  `flock`（通常由 `util-linux` 提供）。
- `.env`、SMTP 授权码、DeepSeek Key、JWT/OTP/Agent 密钥不进入 Git。
- TLS 证书和私钥只在生产主机或秘密系统中保存。
- APK、SHA-256 和 `version.json` 通过外部发布存储分发，不进入 Git。

初始化配置：

```bash
cd /root/FitLoop
bash deploy/gen-secrets.sh
cp deploy/.env.production .env
chmod 600 .env
```

至少核对以下变量：

```dotenv
FITLOOP_JWT_SECRET=<LONG_RANDOM_SECRET>
FITLOOP_OTP_HASH_SECRET=<DIFFERENT_LONG_RANDOM_SECRET>
FITLOOP_AGENT_SERVICE_KEY=<LONG_RANDOM_SERVICE_KEY>
FITLOOP_AGENT_DELEGATION_SECRET=<LONG_RANDOM_DELEGATION_SECRET>
FITLOOP_AGENT_ENABLED=true
DEEPSEEK_API_KEY=<SECRET>
FITLOOP_OTP_DEBUG_RETURN=false
FITLOOP_MAIL_PASSWORD=<SMTP_AUTHORIZATION_CODE>
```

如暂不启用 Agent，设置 `FITLOOP_AGENT_ENABLED=false`；核心服务仍可部署。

## 3. TLS 配置和 30 天兼容窗口

取得证书后配置：

```dotenv
FITLOOP_TLS_ENABLED=true
FITLOOP_HTTP_COMPAT_ENABLED=true
FITLOOP_TLS_CERT_FILE=/etc/letsencrypt/live/app.example.com/fullchain.pem
FITLOOP_TLS_KEY_FILE=/etc/letsencrypt/live/app.example.com/privkey.pem
FITLOOP_PUBLIC_BASE_URL=https://app.example.com
FITLOOP_TLS_CERT_MIN_VALID_SECONDS=1209600
```

`deploy/nginx.tls.conf` 只启用 TLS 1.2/1.3。端口 80 在兼容窗口内继续代理旧 `/api/` 请求，不对旧版 POST 做重定向；新 APK 必须使用 HTTPS。

Compose 会把 `deploy/certbot-www` 作为 ACME webroot 挂载到 Nginx。使用 Certbot 时采用 webroot 模式，不需要停止线上 Nginx：

```bash
certbot certonly --webroot \
  --webroot-path /root/FitLoop/deploy/certbot-www \
  --domain app.example.com \
  --email ops@example.com \
  --agree-tos --no-eff-email

systemctl enable --now certbot.timer
cat >/etc/letsencrypt/renewal-hooks/deploy/fitloop-nginx.sh <<'HOOK'
#!/bin/sh
cd /root/FitLoop
bash deploy/reload-nginx.sh cn
HOOK
chmod 700 /etc/letsencrypt/renewal-hooks/deploy/fitloop-nginx.sh
certbot renew --dry-run
```

固定公网 IP 的 Let’s Encrypt 证书使用不同的 Certbot 参数和短证书监控阈值，
不要把上述域名命令直接替换成 IP。完整步骤见
[IP HTTPS 发布补充手册](IP_HTTPS_RELEASE_RUNBOOK.md)。

证书路径和 Compose 组合需按实际环境调整。`deploy/monitor.sh --alert` 会在
公网证书无法连接，或剩余有效期低于
`FITLOOP_TLS_CERT_MIN_VALID_SECONDS` 时失败。域名证书默认使用
`1209600` 秒（14 天）；160 小时的 IP 短证书使用 `172800` 秒（48 小时）。
阈值必须是 1 到 31536000 的整数秒数。

记录 HTTPS 启用日期。TLS 日志会记录 `transport=80/443`；在至少 30 天且确认旧客户端退出后，经单独批准把 `FITLOOP_HTTP_COMPAT_ENABLED` 改为 `false`。部署脚本将启用 `nginx.https-only.conf`，明文 `/api/` 返回 426。

## 4. 部署核心服务

部署前先备份数据库并确认仓库没有未提交修改：

```bash
cd /root/FitLoop
bash deploy/backup.sh
git status --short
git pull --ff-only origin main
bash deploy/deploy.sh cn
```

`deploy/deploy.sh` 会校验证书路径、HTTPS 公网地址和 Agent 必要密钥。TLS 已启用时自动叠加 `docker-compose.tls.yml`。

验证：

```bash
docker compose -f deploy/docker-compose.yml -f deploy/docker-compose.cn.yml -f deploy/docker-compose.tls.yml --env-file .env ps
curl -fsS http://localhost:8080/actuator/health
curl -fsS https://app.example.com/actuator/health
curl -fsS http://127.0.0.1:8090/ready
bash deploy/monitor.sh --alert
```

Agent readiness 失败应单独告警，但不得判定核心 API 发布失败。停止 Agent 后再次验证登录、运动 API 和 `/apk/` 仍正常。

## 5. Android 构建与签名

版本固定为 `0.1.7+8`。本周期延续已发布 APK 的兼容证书，已知 SHA-256 指纹为：

```text
69316bd8f5a1d79dad539415f88b3ecbaf43f3113831782e35499c0f55a47c2a
```

兼容构建：

```powershell
cd D:\AIWorkspace\projects\FitLoop
powershell -ExecutionPolicy Bypass -File deploy\build-apk.ps1 `
  -ApiBaseUrl https://app.example.com `
  -SigningMode Compatibility
```

脚本会执行 Flutter analyze/test、release 构建、APK 签名指纹校验，并生成 APK、SHA-256 和版本元数据。指纹不一致时发布会停止。

正式签名构建必须从秘密存储注入以下变量：

```text
FITLOOP_RELEASE_STORE_FILE
FITLOOP_RELEASE_STORE_PASSWORD
FITLOOP_RELEASE_KEY_ALIAS
FITLOOP_RELEASE_KEY_PASSWORD
```

缺少变量时正式构建会失败。正式 keystore 本周期尚未创建和离线备份，也不会用于公开 APK；后续切换必须单独验证并公告卸载重装影响。

## 6. 外部 APK 发布、安装与回滚

将以下三个文件上传到受控发布存储：

- `deploy/apk/app-release.apk`
- `deploy/apk/app-release.apk.sha256`
- `deploy/apk/version.json`

安装脚本使用 Python 3 校验 JSON 元数据，使用 `flock` 串行化发布。服务器
上的 APK 目录按以下结构保存按 SHA-256 内容寻址且写保护的发布，以及
写保护的可回滚状态：

```text
deploy/apk/
├── releases/<apk-sha256>/
│   ├── app-release.apk
│   ├── app-release.apk.sha256
│   └── version.json
├── states/<state-id>/
│   ├── current -> ../../releases/<current-sha256>
│   └── previous -> ../../releases/<previous-sha256>
└── active -> states/<state-id>
```

安装器把 release/state 目录设为 `0555`，把 release 普通文件设为
`0444`。这是权限级写保护而不是无法绕过的强制不可改写保证：同一部署用户（尤其是
`root`）技术上仍可先 `chmod` 再修改，所以运维规则禁止原地改写
`releases/` 或 `states/`。安装器会拒绝 release/state 的额外成员、
release 硬链接、非预期权限/所有者，以及 `version.json` 的未知字段。

服务器安装器只建立受信 SHA-256 到三件套的校验链，并校验固定的 metadata
schema；它不会从 APK 本体重新解析签名证书或 API/SDK 信息。APK 本体的
真实性必须先由本地 `deploy/build-apk.ps1` 以及 `apksigner`、`aapt`
（适用时）完成验证，再由操作人员把已验证的 SHA-256 准确复制到服务器
命令中，建立服务器侧信任锚。

新状态完整建立后，脚本才原子切换 `active`。Nginx 只精确公开
`/apk/app-release.apk`、`/apk/app-release.apk.sha256` 和
`/apk/version.json`，且每个入口只读取
`/usr/share/nginx/html/apk/active/current`；目标文件不存在时返回 404，
绝不逐文件回退到根目录，避免新旧三件套混用。其他 `/apk/` 路径也一律
返回 404，因此不会公开候选目录、`releases/`、`states/` 或
`active/previous`。

首次部署这套 Nginx 配置前，必须先把已验证的旧根三件套导入受管状态：

```bash
cd /root/FitLoop
LEGACY_APPROVED_SHA256='<粘贴迁移前已验证的旧 APK SHA-256>'
[[ "${LEGACY_APPROVED_SHA256}" =~ ^[0-9a-f]{64}$ ]]
bash deploy/install-apk.sh --import-legacy "${LEGACY_APPROVED_SHA256}"
test -L deploy/apk/active
test "$(
    sha256sum deploy/apk/active/current/app-release.apk |
        awk '{ print $1 }'
)" = "${LEGACY_APPROVED_SHA256}"
```

`--import-legacy` 以该受信 SHA-256 校验旧 flat 三件套，创建内容寻址 release
和只有 `current` 的 managed state，再原子建立 `active`。导入成功并核对
`active/current` 后先保留已备份的 flat 三件套，让旧 Nginx 配置继续服务；
部署新版 Nginx 并确认三个公网 URL 都返回与信任锚一致的 managed active
旧版后，再把 flat 三件套移到站点目录外的备份位置，并重复公网三 URL
校验。这样切换期间没有下载空窗。不得让新版 Nginx 在没有 managed active
的状态下上线。后续候选激活会自然把已导入的旧版保存为 managed previous。

真机验证前只把候选三件套放入服务器 `/tmp`，并执行只读校验：

```bash
cd /root/FitLoop
bash deploy/install-apk.sh --verify-only \
  https://artifacts.example.com/fitloop/0.1.7/app-release.apk \
  <EXPECTED_SHA256> \
  https://artifacts.example.com/fitloop/0.1.7/version.json
```

`--verify-only` 可能创建安装锁和受管工作目录，但不会创建 release、
state 或切换 `active`，因此不会改变公网下载内容。先完成
`docs/SMOKE_TEST_CHECKLIST.md` 中的 AI 教练专项 3 项，以及除公网三件套核验（#3）和 APK 回滚演练
（#6）外的 31 项。由于首次迁移已先导入旧版，候选激活后 #6 统一演练
managed previous。取得单独发布批准后，才使用同样的三个必填参数执行
正式安装。正式安装会校验候选三件套，写入
`releases/<apk-sha256>`，建立新的 `states/<state-id>`，再原子切换
`active`。随后立即完成 #3 和 #6；任一失败都必须回滚，且 Draft
GitHub Release 不得发布。

forward 安装、`--import-legacy` 和 `--rollback` 都会原子 rename
`active`。若 rename 后收到 `SIGTERM`，命令可能返回 143，且指针可能已经
生效，但 143 绝不代表耐久成功。不要手工改链接，也不要换算新参数：保留
该次命令的原始 URL、SHA-256 和模式参数，先用 `readlink`/哈希观察现场，
再原样重跑同一命令。重跑会对已到达的目标状态执行目录 `sync`，并完整
复验 active/state 布局、current/previous 关系、三件套、哈希和 metadata
schema；只有重跑返回 0 才确认耐久收敛。重跑的 `sync` 或任一完整验证
失败仍按发布失败处理：停止后续操作、保留证据并进入人工恢复，不能仅凭
当前 `readlink` 或哈希看似正确就继续。

回滚统一执行
`bash deploy/install-apk.sh --rollback <EXPECTED_PREVIOUS_SHA256>`。这个
哈希必须来自迁移前或发布时已经核验的发布记录，不能在故障发生后从待
回滚目录临时计算。脚本不依赖可能损坏的 current，要求 managed previous
实际 APK 哈希与信任锚一致，严格校验三件套后原子建立回滚 state；回滚
完整性校验不受面向新版本的 `0.1.7+8` forward policy 限制。若不存在
managed previous，回滚必须失败且保持 `active` 不变；不会撤下 `active`
或回退到 flat 根文件。不要直接改写 `active` 或单独移动其中一个文件。
回滚只改变下载产物，不会回滚数据库或服务代码。

验证：

```bash
cd /root/FitLoop
(
    cd deploy/apk/active/current
    sha256sum -c app-release.apk.sha256
)
python3 -c \
  'import json,pathlib,sys; json.loads(pathlib.Path(sys.argv[1]).read_text(encoding="utf-8-sig"))' \
  deploy/apk/active/current/version.json
readlink deploy/apk/active
readlink deploy/apk/active/current
curl -fsS https://app.example.com/apk/version.json
curl -fsS https://app.example.com/apk/app-release.apk.sha256
curl -I https://app.example.com/apk/app-release.apk
```

## 7. 发布顺序与观察

1. 首次迁移先验证旧 APK 信任锚，执行 `--import-legacy` 并核对 managed
   `active/current`；保留已备份的 flat 根三件套直到新版 Nginx 上线。
2. 部署 TLS 和保持旧接口兼容的后端。
3. 验证新版 Nginx 公网三件套均来自 managed active 且旧哈希不变，再把
   flat 根三件套移到站点目录外，并重复三 URL 校验。
4. 验证 Backend、HTTPS、邮件验证码和 Agent 独立降级。
5. 构建兼容签名 APK，把三件套放入非公开候选目录并执行
   `--verify-only`。
6. 使用本地候选 APK 完成 AI 教练专项 3 项及检查清单中除 #3 和 #6 外的 31 项；首次迁移
   必须已经用 `--import-legacy` 建立旧版 managed current。
7. 创建包含三件套的 Draft GitHub Release 并核对资产和哈希，但不发布。
8. 取得单独发布批准后，正式安装候选并原子切换 `active`。
9. 完成公网三件套核验 #3 和 managed previous 回滚演练 #6；失败立即
   回滚，Draft 保持未发布。
10. #3 和 #6 通过后发布 Draft。
11. 观察健康状态、401/5xx、Agent 失败率和证书状态。
12. 满足 30 天兼容条件后，另行批准关闭明文 API。

本指南中的命令不会替代发布授权。当前代码完成不代表已经 push、部署、切换证书或发布 APK。
