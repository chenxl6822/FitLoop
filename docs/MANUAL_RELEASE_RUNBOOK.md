# FitLoop `0.1.6+7` 人工发布执行手册

本手册列出代码之外必须由项目负责人亲自完成的操作。按顺序执行，不要跳过备份、签名核对、真机冒烟或回滚准备。涉及密码、授权码、API Key 的位置只在交互提示、密码管理器或未跟踪的 `.env` 中填写，不要粘贴到 Git、聊天或终端命令历史。

当前发布边界：公开 APK 继续使用已发布版本的兼容证书；新建正式 keystore 只做离线备份和构建验证，不得用于本次公开 APK。

## 0. 先准备这些信息

| 变量 | 示例 | 获取位置 |
| --- | --- | --- |
| `DOMAIN` | `app.example.com` | 已备案且完成 A 记录解析的域名 |
| `SERVER_IP` | `203.0.113.10` | 云服务器公网 IP |
| `SSH_USER` | `ubuntu` | 云服务器登录用户 |
| `LE_EMAIL` | `ops@example.com` | Let's Encrypt 到期通知邮箱 |
| `TEST_EMAIL` | `qa@example.com` | 接收验证码的测试邮箱 |
| SMTP 授权码 | 不在本文记录 | 邮箱服务商控制台 |
| DeepSeek API Key | 不在本文记录 | DeepSeek 控制台；可暂不启用 Agent |
| 离线备份盘路径 | `E:\FitLoopOfflineBackup` | 只由项目负责人保管 |

在本地 PowerShell 设置非秘密变量：

```powershell
$Repo = 'D:\AIWorkspace\projects\FitLoop'
$Domain = Read-Host '输入正式域名，例如 app.example.com'
$ServerIp = Read-Host '输入服务器公网 IP'
$SshUser = Read-Host '输入 SSH 用户名，例如 ubuntu'
$LeEmail = Read-Host '输入证书到期通知邮箱'
$TestEmail = Read-Host '输入验证码测试邮箱'
$SshTarget = "$SshUser@$ServerIp"
```

## 1. 推送分支、创建 PR、等待 CI、合并

```powershell
cd $Repo
git status --short --branch
git log -1 --oneline
git push -u origin codex/production-stability
```

工作区必须干净。安装了 GitHub CLI 时：

```powershell
gh auth status
gh pr view codex/production-stability
```

如果 PR 尚不存在：

```powershell
gh pr create `
  --base main `
  --head codex/production-stability `
  --title 'release: prepare FitLoop 0.1.6+7 production stability' `
  --body '认证续期、TLS/Agent 降级、APK 发布治理、移动端模块化、CI 和发布文档。不得在真机与生产验证前发布 APK。'
```

等待所有 CI：

```powershell
gh pr checks codex/production-stability --watch
```

人工审查通过后才合并：

```powershell
gh pr merge codex/production-stability --merge
git fetch origin
git log origin/main -1 --oneline
```

不要使用强制推送、rebase、`git reset --hard` 或绕过 CI 的管理员合并。

## 2. 域名、DNS 和安全组

在域名/DNS 控制台创建：

```text
记录类型: A
主机记录: app（根域名则填 @）
记录值: <SERVER_IP>
TTL: 600
```

在云安全组只开放 TCP `22`、`80`、`443`。不要开放 `3306`、`6379`、`8080`、`8090`。

本地验证 DNS：

```powershell
Resolve-DnsName $Domain -Type A
Test-NetConnection $Domain -Port 80
```

解析结果必须包含 `$ServerIp`。证书签发前，80 端口必须能从公网访问。

## 3. 服务器备份并更新代码

登录服务器：

```powershell
ssh $SshTarget
```

以下命令在服务器执行：

```bash
sudo -i
cd /root/FitLoop

BACKUP_DIR="/root/backups/fitloop-pre-016-$(date +%Y%m%d_%H%M%S)"
mkdir -p "${BACKUP_DIR}"
if [ -f deploy/apk/app-release.apk ]; then
    cp --preserve=mode,timestamps deploy/apk/app-release.apk "${BACKUP_DIR}/app-release.apk"
fi
if [ -f deploy/apk/version.json ]; then
    cp --preserve=mode,timestamps deploy/apk/version.json "${BACKUP_DIR}/version.json"
fi

bash deploy/backup.sh
git status --short
git fetch origin
git switch main
git pull --ff-only origin main
git status --short
git log -1 --oneline
```

如果 `git status --short` 在拉取前显示被跟踪文件有改动，立即停止；不要 reset、stash 或覆盖。先把准确文件和用途查清。

## 4. 生成和填写生产 `.env`

仅在服务器不存在 `.env` 时生成：

```bash
cd /root/FitLoop
if [ ! -f .env ]; then
    bash deploy/gen-secrets.sh deploy/.env.production
    cp --preserve=mode,timestamps deploy/.env.production .env
fi
chmod 600 .env
nano .env
```

在编辑器中填写或核对：

```dotenv
FITLOOP_AGENT_ENABLED=false
DEEPSEEK_API_KEY=
FITLOOP_OTP_DEBUG_RETURN=false
FITLOOP_MAIL_HOST=smtp.qq.com
FITLOOP_MAIL_PORT=465
FITLOOP_MAIL_USERNAME=<发件邮箱>
FITLOOP_MAIL_PASSWORD=<SMTP授权码，不是登录密码>
FITLOOP_MAIL_FROM=<发件邮箱>
FITLOOP_TLS_ENABLED=false
FITLOOP_HTTP_COMPAT_ENABLED=true
FITLOOP_TLS_CERT_FILE=
FITLOOP_TLS_KEY_FILE=
FITLOOP_PUBLIC_BASE_URL=
```

首次上线先保持 Agent 和 TLS 关闭。验证不存在占位值，不输出秘密内容：

```bash
if grep -Eq 'replace-with|your-domain\.example' .env; then
    echo 'ERROR: .env 仍包含占位值'
    exit 1
fi
grep -q '^FITLOOP_OTP_DEBUG_RETURN=false$' .env
test "$(stat -c '%a' .env)" = '600'
```

## 5. 先启动 HTTP 核心服务，验证 ACME webroot

```bash
cd /root/FitLoop
read -r -p '正式域名: ' DOMAIN
export DOMAIN
bash deploy/deploy.sh cn
curl -fsS http://localhost:8080/actuator/health
curl -fsS "http://${DOMAIN}/actuator/health"
```

验证 ACME challenge：

```bash
CHALLENGE_DIR=/root/FitLoop/deploy/certbot-www/.well-known/acme-challenge
mkdir -p "${CHALLENGE_DIR}"
printf 'fitloop-acme-ok' > "${CHALLENGE_DIR}/healthcheck"
curl -fsS "http://${DOMAIN}/.well-known/acme-challenge/healthcheck"
rm -f -- "${CHALLENGE_DIR}/healthcheck"
```

返回 `fitloop-acme-ok` 后才能签发证书。

## 6. 签发证书、启用 HTTPS 和自动续期

```bash
apt-get update
apt-get install -y certbot
read -r -p '证书通知邮箱: ' LE_EMAIL

certbot certonly \
  --webroot \
  --webroot-path /root/FitLoop/deploy/certbot-www \
  --domain "${DOMAIN}" \
  --email "${LE_EMAIL}" \
  --agree-tos \
  --no-eff-email
```

编辑 `.env`：

```bash
nano /root/FitLoop/.env
```

设置：

```dotenv
FITLOOP_TLS_ENABLED=true
FITLOOP_HTTP_COMPAT_ENABLED=true
FITLOOP_TLS_CERT_FILE=/etc/letsencrypt/live/<DOMAIN>/fullchain.pem
FITLOOP_TLS_KEY_FILE=/etc/letsencrypt/live/<DOMAIN>/privkey.pem
FITLOOP_PUBLIC_BASE_URL=https://<DOMAIN>
```

将 `<DOMAIN>` 替换为真实域名。验证并部署：

```bash
CERT_FILE="/etc/letsencrypt/live/${DOMAIN}/fullchain.pem"
KEY_FILE="/etc/letsencrypt/live/${DOMAIN}/privkey.pem"
test -r "${CERT_FILE}"
test -r "${KEY_FILE}"
openssl x509 -in "${CERT_FILE}" -noout -subject -issuer -dates

cd /root/FitLoop
docker compose --env-file .env \
  -f deploy/docker-compose.yml \
  -f deploy/docker-compose.cn.yml \
  -f deploy/docker-compose.tls.yml \
  config --quiet
bash deploy/deploy.sh cn

curl -fsS "https://${DOMAIN}/actuator/health"
curl -I "https://${DOMAIN}/"
echo | openssl s_client -connect "${DOMAIN}:443" -servername "${DOMAIN}" 2>/dev/null \
  | openssl x509 -noout -subject -issuer -dates
```

安装自动续期部署钩子：

```bash
install -d -m 700 /etc/letsencrypt/renewal-hooks/deploy
cat > /etc/letsencrypt/renewal-hooks/deploy/fitloop-nginx.sh <<'HOOK'
#!/bin/sh
set -eu
cd /root/FitLoop
bash deploy/reload-nginx.sh cn
HOOK
chmod 700 /etc/letsencrypt/renewal-hooks/deploy/fitloop-nginx.sh

systemctl enable --now certbot.timer
certbot renew --dry-run
systemctl status certbot.timer --no-pager
```

## 7. 验证真实 SMTP 邮件验证码

先在邮箱服务商控制台启用 SMTP，生成独立授权码。不要使用邮箱登录密码。把发件邮箱和授权码写入服务器 `.env` 后重建服务：

```bash
cd /root/FitLoop
nano .env
grep -q '^FITLOOP_OTP_DEBUG_RETURN=false$' .env
bash deploy/deploy.sh cn
```

触发一封注册验证码邮件：

```bash
read -r -p '接收验证码的测试邮箱: ' TEST_EMAIL
curl -fsS -X POST "https://${DOMAIN}/api/verification/send" \
  -H 'Content-Type: application/json' \
  --data "{\"channel\":\"email\",\"target\":\"${TEST_EMAIL}\",\"purpose\":\"register\"}"
```

检查邮件确实收到；接口响应中的 `debugCode` 必须缺失或为 `null`，不得包含验证码明文。随后在 App 中完成注册、验证码登录和重置密码三条链路。

## 8. 可选启用 Agent，并验证独立降级

取得 DeepSeek Key 后编辑 `.env`：

```dotenv
FITLOOP_AGENT_ENABLED=true
DEEPSEEK_API_KEY=<只写入服务器.env>
```

部署和验证：

```bash
cd /root/FitLoop
nano .env
bash deploy/deploy.sh cn
curl -fsS http://127.0.0.1:8090/ready
curl -fsS http://127.0.0.1:8090/metrics | head
```

降级演练：

```bash
docker stop fitloop-agent-service
curl -fsS "https://${DOMAIN}/actuator/health"
curl -I "https://${DOMAIN}/"
docker start fitloop-agent-service
```

停止 Agent 期间核心健康检查和 APK 站点必须仍可用。恢复后再次检查 `/ready`。

## 9. 创建正式 keystore，只做验证和离线备份

以下命令在本地 PowerShell 执行。密钥目录必须位于仓库之外：

```powershell
$KeyDir = Read-Host '输入仓库外密钥目录，例如 D:\FitLoopSecrets'
$OfflineBackupDir = Read-Host '输入离线备份盘目录，例如 E:\FitLoopOfflineBackup'
$Keystore = Join-Path $KeyDir 'fitloop-release.p12'
$Alias = 'fitloop-release'

New-Item -ItemType Directory -Force -Path $KeyDir | Out-Null
if (Test-Path $Keystore) { throw "拒绝覆盖已有 keystore: $Keystore" }

$Keytool = (Get-Command keytool.exe -ErrorAction Stop).Source
& $Keytool -genkeypair -v `
  -storetype PKCS12 `
  -keystore $Keystore `
  -alias $Alias `
  -keyalg RSA `
  -keysize 4096 `
  -validity 3650
```

按交互提示输入强密码和证书主体。把密码保存到密码管理器，不要保存为脚本或文本文件。

验证并离线备份：

```powershell
& $Keytool -list -v -keystore $Keystore -alias $Alias
New-Item -ItemType Directory -Force -Path $OfflineBackupDir | Out-Null
Copy-Item -LiteralPath $Keystore -Destination (Join-Path $OfflineBackupDir 'fitloop-release.p12')
Get-FileHash -Algorithm SHA256 $Keystore
Get-FileHash -Algorithm SHA256 (Join-Path $OfflineBackupDir 'fitloop-release.p12')
```

两份 SHA-256 必须一致。然后只做正式签名构建验证：

```powershell
$StoreSecret = Read-Host '输入 keystore 密码' -AsSecureString
$StorePassword = [System.Net.NetworkCredential]::new('', $StoreSecret).Password

try {
  $env:FITLOOP_RELEASE_STORE_FILE = $Keystore
  $env:FITLOOP_RELEASE_STORE_PASSWORD = $StorePassword
  $env:FITLOOP_RELEASE_KEY_ALIAS = $Alias
  $env:FITLOOP_RELEASE_KEY_PASSWORD = $StorePassword

  cd $Repo
  powershell -ExecutionPolicy Bypass -File deploy\build-apk.ps1 `
    -ApiBaseUrl "https://$Domain" `
    -SigningMode Official

  Copy-Item deploy\apk\app-release.apk `
    (Join-Path $KeyDir 'fitloop-0.1.6-official-signing-validation.apk')
  Copy-Item deploy\apk\version.json `
    (Join-Path $KeyDir 'fitloop-0.1.6-official-signing-validation.json')
}
finally {
  'FITLOOP_RELEASE_STORE_FILE',
  'FITLOOP_RELEASE_STORE_PASSWORD',
  'FITLOOP_RELEASE_KEY_ALIAS',
  'FITLOOP_RELEASE_KEY_PASSWORD' | ForEach-Object {
    Remove-Item "Env:$_" -ErrorAction SilentlyContinue
  }
  $StorePassword = $null
  $StoreSecret = $null
}
```

这份正式签名验证 APK 不得上传或公开。下一步兼容构建会覆盖 `deploy/apk/` 中的验证产物。

## 10. 构建本周期兼容签名 APK

```powershell
cd $Repo
git fetch origin
git switch main
git pull --ff-only origin main
git status --short

powershell -ExecutionPolicy Bypass -File deploy\build-apk.ps1 `
  -ApiBaseUrl "https://$Domain" `
  -SigningMode Compatibility

$Apk = Join-Path $Repo 'deploy\apk\app-release.apk'
$VersionJson = Join-Path $Repo 'deploy\apk\version.json'
$Sha256 = (Get-FileHash -Algorithm SHA256 $Apk).Hash.ToLowerInvariant()
$Sha256
Get-Content $VersionJson -Encoding UTF8
```

必须确认：

```text
version = 0.1.6
versionCode = 7
apiBaseUrl = https://<DOMAIN>
signingMode = Compatibility
signerSha256 = 69316bd8f5a1d79dad539415f88b3ecbaf43f3113831782e35499c0f55a47c2a
```

## 11. 先通过 SCP 安装候选 APK，不急着公开 Release

本地 PowerShell：

```powershell
$RemoteStage = '/tmp/fitloop-0.1.6-build.7'
ssh $SshTarget "mkdir -p $RemoteStage"
scp "$Repo\deploy\apk\app-release.apk" "${SshTarget}:$RemoteStage/app-release.apk"
scp "$Repo\deploy\apk\version.json" "${SshTarget}:$RemoteStage/version.json"
```

登录服务器后执行：

```bash
sudo -i
cd /root/FitLoop
REMOTE_STAGE=/tmp/fitloop-0.1.6-build.7
EXPECTED_SHA256='<粘贴本地 PowerShell 输出的 64 位 SHA-256>'

sha256sum "${REMOTE_STAGE}/app-release.apk"
bash deploy/install-apk.sh \
  "file://${REMOTE_STAGE}/app-release.apk" \
  "${EXPECTED_SHA256}" \
  "file://${REMOTE_STAGE}/version.json"

sha256sum deploy/apk/app-release.apk
curl -fsS "https://${DOMAIN}/apk/version.json"
curl -I "https://${DOMAIN}/apk/app-release.apk"
```

服务器哈希必须与本地完全一致。

## 12. 真机升级、认证和降级冒烟

完整记录使用 [SMOKE_TEST_CHECKLIST.md](SMOKE_TEST_CHECKLIST.md)。连接测试手机后，本地 PowerShell 可执行：

```powershell
adb devices
adb install -r "$Repo\deploy\apk\app-release.apk"
adb shell dumpsys package com.fitloop.fitloop | Select-String 'versionName|versionCode'
```

先完成 `0.1.5+6 → 0.1.6+7` 覆盖升级测试。全新安装会删除本地数据，只能在升级测试完成后使用测试设备执行：

```powershell
adb uninstall com.fitloop.fitloop
adb install "$Repo\deploy\apk\app-release.apk"
```

认证专项至少执行：

1. 登录后等待超过 15 分钟，再进入首页、统计和排行榜，确认自动续期且不返回登录页。
2. 断网重启 App，再恢复网络，确认可刷新会话没有被误删。
3. 使用重置密码流程撤销该账号全部 refresh token；等待 access token 过期后，确认 App 清理会话并回登录页。
4. 主动退出并重启，确认不会自动登录。
5. 快速切换多个需要 API 的页面，观察没有重复登录、无限刷新或请求风暴。

收集日志：

```powershell
adb logcat -c
adb logcat | Select-String 'FitLoop|AndroidRuntime|FATAL EXCEPTION'
```

## 13. 通过真机冒烟后发布 GitHub Release

```powershell
cd $Repo
gh release create 'v0.1.6-build.7' `
  --target main `
  --title 'FitLoop 0.1.6+7' `
  --notes '生产稳定过渡版：认证续期、HTTPS、Agent 降级与发布治理。继续使用兼容签名。'

gh release upload 'v0.1.6-build.7' `
  deploy\apk\app-release.apk `
  deploy\apk\app-release.apk.sha256 `
  deploy\apk\version.json

gh release view 'v0.1.6-build.7'
```

如果仓库是私有仓库，服务器下载不能依赖匿名 GitHub Release URL；继续保留服务器已通过 SCP 校验安装的产物，或改用有访问控制的对象存储。

## 14. 观察、告警和 APK 回滚

服务器观察：

```bash
cd /root/FitLoop
bash deploy/monitor.sh --alert
docker logs --since 1h fitloop-backend 2>&1 | tail -n 200
docker logs --since 1h fitloop-agent-service 2>&1 | tail -n 200
curl -fsS http://localhost:8080/actuator/prometheus \
  | grep -E 'http_server_requests_seconds_count|fitloop_outbox_pending' \
  | head -n 50
curl -fsS http://127.0.0.1:8090/metrics \
  | grep -E 'agent|model|tool' \
  | head -n 50
```

只回滚 APK 下载产物：

```bash
cd /root/FitLoop
test -f deploy/apk/app-release.apk.previous
test -f deploy/apk/version.json.previous

ROLLBACK_BACKUP="/root/backups/fitloop-apk-failed-$(date +%Y%m%d_%H%M%S)"
mkdir -p "${ROLLBACK_BACKUP}"
cp --preserve=mode,timestamps deploy/apk/app-release.apk "${ROLLBACK_BACKUP}/"
cp --preserve=mode,timestamps deploy/apk/version.json "${ROLLBACK_BACKUP}/"

cp deploy/apk/app-release.apk.previous deploy/apk/app-release.apk.rollback-new
cp deploy/apk/version.json.previous deploy/apk/version.json.rollback-new
sha256sum deploy/apk/app-release.apk.rollback-new
mv -f deploy/apk/app-release.apk.rollback-new deploy/apk/app-release.apk
mv -f deploy/apk/version.json.rollback-new deploy/apk/version.json

curl -fsS "https://${DOMAIN}/apk/version.json"
curl -I "https://${DOMAIN}/apk/app-release.apk"
```

不要用 `git reset --hard` 回滚代码。代码回滚应在新分支执行 `git revert <merge-commit>`、重新走 PR/CI，并先评估 Flyway 向前迁移兼容性。

## 15. 满 30 天后关闭明文 API

TLS Nginx 日志包含 `transport=80` 或 `transport=443`。每天统计最近 24 小时的旧 HTTP API 请求：

```bash
docker logs --since 24h fitloop-nginx 2>&1 \
  | grep 'transport=80' \
  | grep -c ' /api/' || true
```

只有兼容窗口至少 30 天、持续确认旧版客户端退出、且获得单独发布批准后，才编辑：

```bash
cd /root/FitLoop
cp --preserve=mode,timestamps .env ".env.before-http-close-$(date +%Y%m%d_%H%M%S)"
nano .env
```

修改：

```dotenv
FITLOOP_HTTP_COMPAT_ENABLED=false
```

部署并验证：

```bash
bash deploy/deploy.sh cn

HTTP_STATUS=$(curl -sS -o /dev/null -w '%{http_code}' \
  -X POST "http://${DOMAIN}/api/verification/send" \
  -H 'Content-Type: application/json' \
  --data '{}')
test "${HTTP_STATUS}" = '426'
curl -fsS "https://${DOMAIN}/actuator/health"
```

需要临时重新开放兼容窗口时，将变量改回 `true`，再次执行 `bash deploy/deploy.sh cn`。不要关闭 HTTPS或降低 TLS 版本。
