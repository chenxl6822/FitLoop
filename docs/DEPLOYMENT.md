# FitLoop 部署与运维指南

本文适用于生产稳定过渡版 `0.1.6+7`。任何 push、证书切换、生产部署或 APK 发布都必须在执行前单独确认。

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

- 已备案域名解析到服务器，安全组开放 `22`、`80`、`443`；不要开放 `3306`、`6379` 或 `8090`。
- 生产主机安装 Docker、Docker Compose、curl、openssl 和 bc。
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

证书路径和 Compose 组合需按实际环境调整。`deploy/monitor.sh --alert` 会在公网证书无法连接或剩余有效期不足 14 天时失败，建议每天执行。

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

版本固定为 `0.1.6+7`。本周期延续已发布 APK 的兼容证书，已知 SHA-256 指纹为：

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

服务器使用可信渠道取得 64 位 SHA-256，然后安装：

```bash
cd /root/FitLoop
bash deploy/install-apk.sh \
  https://artifacts.example.com/fitloop/0.1.6/app-release.apk \
  <EXPECTED_SHA256> \
  https://artifacts.example.com/fitloop/0.1.6/version.json
```

脚本先下载并校验，再原子替换；旧 APK 和元数据保存为 `.previous`。首次拉取“APK 不再由 Git 跟踪”的提交前，先将线上 APK 复制到仓库外备份目录，避免 `git pull` 删除唯一副本。

回滚时先核对 `.previous` 指纹和 SHA-256，再将其复制为新的临时文件并原子替换当前产物；同时恢复匹配的 `version.json.previous`。回滚只改变下载产物，不会回滚数据库或服务代码。

验证：

```bash
sha256sum deploy/apk/app-release.apk
curl -fsS https://app.example.com/apk/version.json
curl -I https://app.example.com/apk/app-release.apk
```

## 7. 发布顺序与观察

1. 部署 TLS 和保持旧接口兼容的后端。
2. 验证 Backend、HTTPS、邮件验证码和 Agent 独立降级。
3. 构建并校验兼容签名 APK，上传外部产物。
4. 服务器校验并原子安装 APK。
5. 完成 `docs/SMOKE_TEST_CHECKLIST.md` 的全部真机项目。
6. 观察健康状态、401/5xx、Agent 失败率和证书状态。
7. 满足 30 天兼容条件后，另行批准关闭明文 API。

本指南中的命令不会替代发布授权。当前代码完成不代表已经 push、部署、切换证书或发布 APK。
