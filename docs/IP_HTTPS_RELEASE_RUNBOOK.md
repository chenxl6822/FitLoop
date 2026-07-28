# FitLoop 固定公网 IP HTTPS 发布补充手册

本手册适用于把固定公网 IP `43.139.72.25` 作为 FitLoop `0.1.6+7`
的 HTTPS API、下载页和 APK 发布端点。它只替代
[人工发布执行手册](MANUAL_RELEASE_RUNBOOK.md) 中与域名、DNS 和域名证书
相关的步骤；备份、可信旧 APK、三件套、真机、原子激活和回滚门禁仍须
完整执行。

任何服务器写入、证书切换、标签、GitHub Release、APK 激活或公开发布都
必须在执行前取得对应的单独批准。不要在本文、Git 或命令历史中记录密码、
Token、SMTP 授权码或签名私钥。

## 0. 发布边界和停止条件

固定公网 IP 方案必须同时满足：

- 云厂商确认 `43.139.72.25` 是该服务器长期持有的公网 IP。
- 已确认服务器所在地、云厂商和应用公开访问所需的备案与合规要求；使用
  IP 不代表自动免除这些要求。
- 安全组开放 TCP `22`、`80`、`443`，不公开 `3306`、`6379`、`8080`
  或 `8090`。
- Certbot 版本不低于 `5.4`，支持 `--ip-address` 和 webroot。
- Let’s Encrypt IP 短证书自动续期和 Nginx reload hook 演练通过。
- `.env` 设置 `FITLOOP_TLS_CERT_MIN_VALID_SECONDS=172800`，即 48 小时。
- 可信旧版、数据库恢复、候选三件套和 31+2 项真机门禁全部有记录。

任一校验失败都停止。不要用 `curl -k`、关闭证书验证、放宽安装器校验、
手工改写 `deploy/apk/active` 或通过删除断言制造通过结果。

Let’s Encrypt IP 证书有效期约 160 小时。Certbot 对不超过 10 天的证书
会在剩余寿命低于一半时进入续期窗口。48 小时监控阈值用于在自动续期
本应完成后仍保留人工恢复时间：

- <https://letsencrypt.org/2026/03/11/shorter-certs-certbot>
- <https://eff-certbot.readthedocs.io/en/stable/using.html#renewing-certificates>

## 1. 本地和 GitHub 基线

在本地 PowerShell 执行：

```powershell
$Repo = 'D:\AIWorkspace\projects\FitLoop'
$ServerIp = '43.139.72.25'
$ApiBaseUrl = "https://$ServerIp"
$Gh = 'C:\Program Files\GitHub CLI\gh.exe'

cd $Repo
if (@(git status --porcelain).Count -ne 0) {
  throw '工作区不干净，停止发布'
}

git fetch origin
git switch main
git pull --ff-only origin main
git status --short --branch

$MainCommit = (git rev-parse HEAD).Trim()
$MainCommit
& $Gh run list `
  --repo chenxl6822/FitLoop `
  --branch main `
  --limit 3
```

必须确认：

- 本地 `main` 与 `origin/main` 一致。
- 工作区无修改和未跟踪文件。
- 候选提交的必需 CI 全绿。
- `deploy/apk` 中没有上一次构建遗留的未知产物。

## 2. 可信 SSH 主机指纹

先通过云厂商网页控制台、VNC 或串行控制台，在服务器读取可信指纹：

```bash
sudo ssh-keygen \
  -lf /etc/ssh/ssh_host_ed25519_key.pub \
  -E sha256
```

本地 PowerShell 读取公网返回的指纹：

```powershell
$ScannedKey = ssh-keyscan -t ed25519 $ServerIp 2>$null
if (-not $ScannedKey) {
  throw '没有取得服务器 ED25519 公钥'
}
$ScannedKey | ssh-keygen -lf - -E sha256
```

两边 SHA-256 必须逐字符一致。然后：

```powershell
$SshUser = Read-Host '输入 SSH 用户名'
$SshTarget = "$SshUser@$ServerIp"
ssh -o StrictHostKeyChecking=ask $SshTarget
```

已有 `known_hosts` 记录突然变化时立即停止。不要在未确认服务器是否重装、
IP 是否重新分配或主机密钥是否轮换前执行 `ssh-keygen -R`。

记录服务器 IP、SSH 用户、ED25519 SHA-256、核验来源、日期和核验人。

## 3. 可信旧版 APK 和兼容签名

优先使用此前留存且来源已核验的 `0.1.5+6` APK。不得把当前公网重新下载的
文件直接作为唯一信任锚。

如果没有离线副本，可以从已知发布提交 `2d1cf6f` 导出候选旧包，再由项目
负责人结合发布记录确认其可信来源：

```powershell
$LegacyDir = Join-Path ([System.IO.Path]::GetTempPath()) `
  "fitloop-legacy-$([guid]::NewGuid().ToString('N'))"
$LegacyArchive = Join-Path $LegacyDir 'legacy.zip'
New-Item -ItemType Directory -Path $LegacyDir | Out-Null

git archive `
  --format=zip `
  -o $LegacyArchive `
  2d1cf6f `
  deploy/apk/app-release.apk

Expand-Archive `
  -LiteralPath $LegacyArchive `
  -DestinationPath $LegacyDir

$LegacyApk = Join-Path $LegacyDir 'deploy\apk\app-release.apk'
if (-not (Test-Path -LiteralPath $LegacyApk -PathType Leaf)) {
  throw '未从已知提交导出旧 APK'
}
```

计算旧 APK 信任锚：

```powershell
$LegacySha256 = (
  Get-FileHash -Algorithm SHA256 $LegacyApk
).Hash.ToLowerInvariant()
$LegacySha256
```

定位并执行 `apksigner`：

```powershell
$SdkRoots = @($env:ANDROID_SDK_ROOT, $env:ANDROID_HOME) |
  Where-Object { $_ -and (Test-Path -LiteralPath $_) }

$ApkSigner = $SdkRoots |
  ForEach-Object {
    Get-ChildItem -LiteralPath (Join-Path $_ 'build-tools') `
      -Recurse -Filter apksigner.bat -ErrorAction SilentlyContinue
  } |
  Sort-Object FullName -Descending |
  Select-Object -First 1

if (-not $ApkSigner) {
  throw '未找到 apksigner.bat'
}

$SignerOutput = & $ApkSigner.FullName verify --print-certs $LegacyApk 2>&1
if ($LASTEXITCODE -ne 0) {
  throw '旧 APK 签名验证失败'
}
$SignerOutput
```

签名证书 SHA-256 必须是：

```text
69316bd8f5a1d79dad539415f88b3ecbaf43f3113831782e35499c0f55a47c2a
```

2026-07-28 的本地复核结果可作为待批准证据：

```text
commit: 2d1cf6f
APK SHA-256: 7c36b21a8c4c0898921e6c509d7df882e1418968b1fbcace2c6ecc869b531f2b
certificate DN: C=US, O=Android, CN=Android Debug
certificate SHA-256:
69316bd8f5a1d79dad539415f88b3ecbaf43f3113831782e35499c0f55a47c2a
```

这证明该 Git 对象与预期兼容签名一致，但不能代替项目负责人对旧发布来源
的信任批准。证书 DN 明确是 Android Debug，只能作为已有安装的兼容升级
约束，不能宣称已经完成正式生产签名。

将旧 APK SHA-256、签名指纹、来源、版本和核验日期写入发布记录。找不到
对应兼容签名私钥时，不能构建覆盖升级包，也不能改用新 keystore 冒充
兼容升级。

## 4. 生产数据库备份和隔离恢复

取得服务器备份/临时容器写入授权后：

```bash
sudo -i
cd /root/FitLoop
bash deploy/backup.sh
ls -lh /root/backups/fitloop/
```

从脚本输出复制本次准确文件名：

```bash
BACKUP_FILE='/root/backups/fitloop/fitloop_YYYYMMDD_HHMMSS.sql.gz'
test -f "${BACKUP_FILE}"
test -s "${BACKUP_FILE}"
gzip -t "${BACKUP_FILE}"
sha256sum "${BACKUP_FILE}"
docker inspect fitloop-mysql --format '{{.Config.Image}}'
```

恢复演练必须使用独立 MySQL 8 容器，不挂载生产数据卷，不连接生产网络：

```bash
RESTORE_NAME='fitloop-restore-drill-YYYYMMDD-01'
RESTORE_IMAGE='mysql:8.0'

if docker inspect "${RESTORE_NAME}" >/dev/null 2>&1; then
    echo 'ERROR: 临时容器名称已存在' >&2
    exit 1
fi

RESTORE_ENV="$(mktemp /tmp/fitloop-restore-env.XXXXXX)"
RESTORE_CLIENT_CONFIG="$(
  mktemp /tmp/fitloop-restore-client.XXXXXX.cnf
)"
chmod 600 "${RESTORE_ENV}" "${RESTORE_CLIENT_CONFIG}"

RESTORE_PASSWORD="$(openssl rand -hex 32)"
printf 'MYSQL_ROOT_PASSWORD=%s\n' "${RESTORE_PASSWORD}" \
  > "${RESTORE_ENV}"
{
    printf '[client]\n'
    printf 'user=root\n'
    printf 'password=%s\n' "${RESTORE_PASSWORD}"
} > "${RESTORE_CLIENT_CONFIG}"
unset RESTORE_PASSWORD

docker run -d \
  --name "${RESTORE_NAME}" \
  --network none \
  --env-file "${RESTORE_ENV}" \
  -v "${RESTORE_CLIENT_CONFIG}:/run/secrets/restore-client.cnf:ro" \
  "${RESTORE_IMAGE}"

RESTORE_READY=false
for i in $(seq 1 60); do
    if docker exec "${RESTORE_NAME}" \
        mysqladmin \
        --defaults-extra-file=/run/secrets/restore-client.cnf \
        ping --silent
    then
        RESTORE_READY=true
        break
    fi
    sleep 2
done
test "${RESTORE_READY}" = true

gzip -cd "${BACKUP_FILE}" |
  docker exec -i "${RESTORE_NAME}" \
    mysql --defaults-extra-file=/run/secrets/restore-client.cnf

TABLE_COUNT="$(
  docker exec "${RESTORE_NAME}" \
    mysql \
    --defaults-extra-file=/run/secrets/restore-client.cnf \
    --batch \
    --skip-column-names \
    -e "
      SELECT COUNT(*)
      FROM information_schema.tables
      WHERE table_schema = 'fitloop';
    "
)"
printf 'Restored table count: %s\n' "${TABLE_COUNT}"
test "${TABLE_COUNT}" -gt 0

docker exec "${RESTORE_NAME}" \
  mysql \
  --defaults-extra-file=/run/secrets/restore-client.cnf \
  -e "
    SELECT installed_rank, version, description, success
    FROM fitloop.flyway_schema_history
    ORDER BY installed_rank;
  "
```

如果生产 `MYSQL_DATABASE` 不是 `fitloop`，先读取实际非秘密数据库名并调整
查询；不要猜测。任一恢复检查失败都停止发布并保留临时容器、日志和备份，
但仍需妥善保护两个 `0600` 临时凭据文件。临时容器的环境配置在容器删除前
可由具有 Docker 管理权限的人读取，因此该随机密码只用于本次隔离演练。

全部成功且证据已记录后，先确认清理目标：

```bash
printf '准备删除临时恢复容器：%s\n' "${RESTORE_NAME}"
docker inspect "${RESTORE_NAME}" \
  --format 'name={{.Name}} image={{.Config.Image}}'
```

确认它是本次隔离恢复容器后：

```bash
docker rm -f -- "${RESTORE_NAME}"
rm -f -- "${RESTORE_ENV}" "${RESTORE_CLIENT_CONFIG}"
```

不要删除生产备份。

## 5. 更新服务器代码并导入旧版 managed release

严格执行
[人工发布执行手册第 3 节](MANUAL_RELEASE_RUNBOOK.md#3-服务器备份并更新代码)
的 fail-fast 代码块，并把第 3 节记录的 `$LegacySha256` 作为
`LEGACY_APPROVED_SHA256`。

关键约束：

- 拉取前 `git status --porcelain` 必须为空。
- 只允许 `git pull --ff-only origin main`。
- 新版 Nginx 启动前必须完成 `--import-legacy`。
- 导入后 `deploy/apk/active/current` 的实际 APK 哈希必须等于可信旧 SHA。
- 在新版 Nginx 已从 managed active 提供同一旧版之前，保留已备份的 flat
  三件套。

导入后的核心校验：

```bash
cd /root/FitLoop
test -L deploy/apk/active
test -d deploy/apk/active/current
(
  cd deploy/apk/active/current
  sha256sum -c app-release.apk.sha256
)
test "$(
  sha256sum deploy/apk/active/current/app-release.apk |
    awk '{ print $1 }'
)" = "${LEGACY_APPROVED_SHA256}"
```

## 6. 申请固定公网 IP 短证书

检查版本：

```bash
certbot --version
```

Certbot 必须不低于 `5.4`。低于该版本时先停止，根据服务器操作系统使用
Certbot 官方支持的安装方式升级；不要同时混用 apt、snap 和手工 Python
安装。

验证 ACME webroot：

```bash
CHALLENGE_DIR=/root/FitLoop/deploy/certbot-www/.well-known/acme-challenge
mkdir -p "${CHALLENGE_DIR}"
printf 'fitloop-ip-acme-ok' > "${CHALLENGE_DIR}/healthcheck"
curl -fsS \
  'http://43.139.72.25/.well-known/acme-challenge/healthcheck'
rm -f -- "${CHALLENGE_DIR}/healthcheck"
```

返回必须是 `fitloop-ip-acme-ok`。

先使用 staging，且使用独立证书名，绝不配置到 Nginx：

```bash
read -r -p '证书通知邮箱: ' LE_EMAIL

certbot certonly \
  --staging \
  --cert-name fitloop-ip-staging \
  --preferred-profile shortlived \
  --webroot \
  --webroot-path /root/FitLoop/deploy/certbot-www \
  --ip-address 43.139.72.25 \
  --email "${LE_EMAIL}" \
  --agree-tos \
  --no-eff-email
```

staging 成功后申请生产证书：

```bash
certbot certonly \
  --cert-name fitloop-ip \
  --preferred-profile shortlived \
  --webroot \
  --webroot-path /root/FitLoop/deploy/certbot-www \
  --ip-address 43.139.72.25 \
  --email "${LE_EMAIL}" \
  --agree-tos \
  --no-eff-email
```

核验证书：

```bash
CERT_FILE=/etc/letsencrypt/live/fitloop-ip/fullchain.pem
KEY_FILE=/etc/letsencrypt/live/fitloop-ip/privkey.pem

test -r "${CERT_FILE}"
test -r "${KEY_FILE}"
openssl x509 \
  -in "${CERT_FILE}" \
  -noout \
  -subject \
  -issuer \
  -dates \
  -fingerprint \
  -sha256
openssl x509 -in "${CERT_FILE}" -noout -text |
  grep -A1 'Subject Alternative Name'
```

SAN 必须包含 `IP Address:43.139.72.25`。

确认生产证书正常后，可列出并精确删除不受信的 staging lineage：

```bash
certbot certificates
```

只有在输出确认目标名为 `fitloop-ip-staging` 后才执行：

```bash
certbot delete --cert-name fitloop-ip-staging
```

## 7. 配置 HTTPS、短证书监控和自动续期

编辑服务器 `/root/FitLoop/.env`：

```dotenv
FITLOOP_TLS_ENABLED=true
FITLOOP_HTTP_COMPAT_ENABLED=true
FITLOOP_TLS_CERT_FILE=/etc/letsencrypt/live/fitloop-ip/fullchain.pem
FITLOOP_TLS_KEY_FILE=/etc/letsencrypt/live/fitloop-ip/privkey.pem
FITLOOP_PUBLIC_BASE_URL=https://43.139.72.25
FITLOOP_TLS_CERT_MIN_VALID_SECONDS=172800
```

保持 `FITLOOP_HTTP_COMPAT_ENABLED=true`，让旧版 `0.1.5+6` 的 HTTP POST
在兼容窗口内继续工作。

验证 Compose 并部署：

```bash
cd /root/FitLoop
docker compose --env-file .env \
  -f deploy/docker-compose.yml \
  -f deploy/docker-compose.cn.yml \
  -f deploy/docker-compose.tls.yml \
  config --quiet
bash deploy/deploy.sh cn
```

禁止使用 `curl -k`：

```bash
curl -fsS 'https://43.139.72.25/actuator/health'
curl -I 'https://43.139.72.25/'
curl -I 'https://43.139.72.25/apk/app-release.apk'
echo |
  openssl s_client \
    -connect 43.139.72.25:443 \
    -servername 43.139.72.25 2>/dev/null |
  openssl x509 -noout -subject -issuer -dates
```

安装续期部署钩子：

```bash
install -d -m 700 /etc/letsencrypt/renewal-hooks/deploy
cat > /etc/letsencrypt/renewal-hooks/deploy/fitloop-nginx.sh <<'HOOK'
#!/bin/sh
set -eu
cd /root/FitLoop
bash deploy/reload-nginx.sh cn
HOOK
chmod 700 /etc/letsencrypt/renewal-hooks/deploy/fitloop-nginx.sh
```

精确启用当前安装来源提供的续期定时器：

```bash
if systemctl cat certbot.timer >/dev/null 2>&1; then
    systemctl enable --now certbot.timer
    CERTBOT_TIMER=certbot.timer
elif systemctl cat snap.certbot.renew.timer >/dev/null 2>&1; then
    systemctl enable --now snap.certbot.renew.timer
    CERTBOT_TIMER=snap.certbot.renew.timer
else
    echo 'ERROR: 未找到 Certbot systemd 续期定时器' >&2
    exit 1
fi

systemctl status "${CERTBOT_TIMER}" --no-pager
systemctl list-timers --all "${CERTBOT_TIMER}"
```

然后只对本次 IP 证书执行续期演练：

```bash
certbot renew \
  --cert-name fitloop-ip \
  --dry-run \
  --run-deploy-hooks
docker exec fitloop-nginx nginx -t
curl -fsS 'https://43.139.72.25/actuator/health'
cd /root/FitLoop
bash deploy/monitor.sh --alert
```

必须保存 dry-run、部署钩子、Nginx 语法、HTTPS health 和监控通过证据。

## 8. 验证 SMTP 和 Agent 降级

按 [人工发布执行手册第 7 节](MANUAL_RELEASE_RUNBOOK.md#7-验证真实-smtp-邮件验证码)
验证真实邮件注册、验证码登录和重置密码。接口响应不得包含验证码明文。

Agent 可以在核心服务首次部署时保持关闭。发布清单仍须完成：

- Agent readiness 正常时的提案、确认/拒绝和审计验证。
- 停止 Agent 或使模型不可用时，登录、运动、管理和 APK 下载保持正常。

不要把 SMTP 授权码、模型 Key 或测试验证码写入本文、Git 或聊天。

## 9. 构建并核验新 APK 三件套

服务器 HTTPS 和续期演练通过后，在干净的远端 `main` 构建：

```powershell
cd $Repo
if (@(git status --porcelain).Count -ne 0) {
  throw '工作区不干净，停止构建'
}
git fetch origin
git switch main
git pull --ff-only origin main
$MainCommit = (git rev-parse HEAD).Trim()

powershell -ExecutionPolicy Bypass -File deploy\build-apk.ps1 `
  -ApiBaseUrl $ApiBaseUrl `
  -SigningMode Compatibility
```

产生：

```text
deploy/apk/app-release.apk
deploy/apk/app-release.apk.sha256
deploy/apk/version.json
```

这些文件不进入 Git。执行一致性校验：

```powershell
$Apk = Join-Path $Repo 'deploy\apk\app-release.apk'
$Checksum = Join-Path $Repo 'deploy\apk\app-release.apk.sha256'
$VersionJson = Join-Path $Repo 'deploy\apk\version.json'
$CandidateSha256 = (
  Get-FileHash -Algorithm SHA256 $Apk
).Hash.ToLowerInvariant()
$ChecksumText = (
  Get-Content $Checksum -Raw -Encoding ASCII
).Trim()
$Metadata = Get-Content $VersionJson -Raw -Encoding UTF8 |
  ConvertFrom-Json

if ($ChecksumText -cne "$CandidateSha256  app-release.apk") {
  throw 'checksum 与 APK 不一致'
}
if ([string]$Metadata.sha256 -cne $CandidateSha256) {
  throw 'version.json sha256 与 APK 不一致'
}
if ([string]$Metadata.version -cne '0.1.6' -or
    [int]$Metadata.versionCode -ne 7) {
  throw '版本号错误'
}
if ([string]$Metadata.apiBaseUrl -cne $ApiBaseUrl) {
  throw 'API 地址错误'
}
if ([string]$Metadata.signingMode -cne 'Compatibility') {
  throw '签名模式错误'
}
if ([string]$Metadata.signerSha256 -cne
    '69316bd8f5a1d79dad539415f88b3ecbaf43f3113831782e35499c0f55a47c2a') {
  throw '签名指纹错误'
}

$CandidateSha256
$Metadata | ConvertTo-Json
```

把候选 SHA-256 写入发布记录。

## 10. 非公开暂存和只读验证

本地 PowerShell：

```powershell
$RemoteStage = '/tmp/fitloop-0.1.6-build.7'
ssh $SshTarget "install -d -m 700 $RemoteStage"
scp "$Repo\deploy\apk\app-release.apk" `
  "${SshTarget}:$RemoteStage/app-release.apk"
scp "$Repo\deploy\apk\app-release.apk.sha256" `
  "${SshTarget}:$RemoteStage/app-release.apk.sha256"
scp "$Repo\deploy\apk\version.json" `
  "${SshTarget}:$RemoteStage/version.json"
```

服务器：

```bash
cd /root/FitLoop
ACTIVE_BEFORE="$(readlink deploy/apk/active)"
bash deploy/install-apk.sh --verify-only \
  file:///tmp/fitloop-0.1.6-build.7/app-release.apk \
  '<本地发布记录中的候选 APK SHA-256>' \
  file:///tmp/fitloop-0.1.6-build.7/version.json
ACTIVE_AFTER="$(readlink deploy/apk/active)"
test "${ACTIVE_AFTER}" = "${ACTIVE_BEFORE}"
```

`--verify-only` 必须返回 0，且不得改变公网 active。

## 11. 激活前 31 项真机验证

使用 [Android 真机冒烟清单](SMOKE_TEST_CHECKLIST.md)。第 1 项按 IP 端点
验证：证书链可信、IP SAN 匹配 `43.139.72.25`，只接受 TLS 1.2/1.3。

先在安装了旧 `0.1.5+6` 的专用测试设备验证覆盖升级：

```powershell
adb devices
adb install -r "$Repo\deploy\apk\app-release.apk"
adb shell dumpsys package com.fitloop.fitloop |
  Select-String 'versionName|versionCode'
```

确认无签名冲突、测试数据和预期会话状态符合设计后，才可在专用测试设备
验证全新安装：

```powershell
adb uninstall com.fitloop.fitloop
adb install "$Repo\deploy\apk\app-release.apk"
```

`adb uninstall` 会删除该测试设备上的 App 数据。不要在个人主设备或含真实
用户数据的设备执行。

除激活后的公网三件套核验 #3 和 managed rollback #6 外，其余 31 项必须
全部通过并记录实际结果。任一失败都不得创建标签、激活 APK 或公开 Release。

## 12. 四个独立批准点

### A. 构建和非公开验证

```text
允许从远端 main 构建 0.1.6+7 Compatibility APK 三件套，上传至服务器
/tmp/fitloop-0.1.6-build.7 并执行 --verify-only；禁止切换 active、创建
标签或公开发布。
```

### B. Draft Release 和标签

```text
31 项激活前检查全部通过。允许创建标签 v0.1.6-build.7 和 Draft GitHub
Release，上传并回下载核验三件套；禁止激活服务器 APK 或公开 Release。
```

取得批准 B 后，本地 PowerShell：

```powershell
$Tag = 'v0.1.6-build.7'
$AssetNames = @(
  'app-release.apk',
  'app-release.apk.sha256',
  'version.json'
)

& $Gh release create $Tag `
  deploy\apk\app-release.apk `
  deploy\apk\app-release.apk.sha256 `
  deploy\apk\version.json `
  --repo chenxl6822/FitLoop `
  --draft `
  --target $MainCommit `
  --title 'FitLoop 0.1.6+7' `
  --notes '固定公网 IP HTTPS 过渡版；继续使用兼容签名。'
if ($LASTEXITCODE -ne 0) {
  throw 'Draft Release 创建或资产上传失败'
}

$Release = & $Gh release view $Tag `
  --repo chenxl6822/FitLoop `
  --json isDraft,assets,targetCommitish |
  ConvertFrom-Json
if (-not $Release.isDraft) {
  throw '资产核验前 Release 已被公开'
}
if ([string]$Release.targetCommitish -cne $MainCommit) {
  throw 'Draft Release 未固定到本次已验证的 main commit'
}
$PublishedAssetNames = @(
  $Release.assets | ForEach-Object { $_.name }
)
if (Compare-Object `
      ($AssetNames | Sort-Object) `
      ($PublishedAssetNames | Sort-Object)) {
  throw 'Draft Release 资产集合不完整或包含未知文件'
}

$ReleaseVerifyDir = Join-Path ([System.IO.Path]::GetTempPath()) `
  "fitloop-release-$([guid]::NewGuid().ToString('N'))"
New-Item -ItemType Directory -Path $ReleaseVerifyDir | Out-Null
& $Gh release download $Tag `
  --repo chenxl6822/FitLoop `
  --dir $ReleaseVerifyDir
if ($LASTEXITCODE -ne 0) {
  throw 'Draft Release 资产回下载失败'
}

foreach ($AssetName in $AssetNames) {
  $LocalAsset = Join-Path $Repo "deploy\apk\$AssetName"
  $DownloadedAsset = Join-Path $ReleaseVerifyDir $AssetName
  $LocalHash = (
    Get-FileHash -Algorithm SHA256 $LocalAsset
  ).Hash
  $DownloadedHash = (
    Get-FileHash -Algorithm SHA256 $DownloadedAsset
  ).Hash
  if ($LocalHash -cne $DownloadedHash) {
    throw "Draft Release 资产哈希不一致: $AssetName"
  }
}
if ((Get-FileHash -Algorithm SHA256 (
      Join-Path $ReleaseVerifyDir 'app-release.apk'
    )).Hash.ToLowerInvariant() -cne $CandidateSha256) {
  throw '回下载 APK 与发布记录中的可信 SHA-256 不一致'
}
```

### C. 正式激活和回滚演练

```text
Draft 三件套核验通过。允许使用发布记录中的候选 SHA-256 在服务器执行
install-apk.sh 原子切换 active，并立即完成公网一致性检查和 managed
rollback 演练。任一失败立即回滚，禁止公开 Release。
```

### D. 公开发布

```text
公网三件套 #3 和 managed rollback #6 均通过，候选已恢复为
active/current。允许将 v0.1.6-build.7 Draft Release 转为公开；禁止执行
其他服务器、数据库或代码变更。
```

批准不得提前合并，也不得用 CI 全绿替代实际批准。

## 13. 原子激活、最后两项和公开 Release

取得批准 C 后：

```bash
cd /root/FitLoop
bash deploy/install-apk.sh \
  file:///tmp/fitloop-0.1.6-build.7/app-release.apk \
  '<本地发布记录中的候选 APK SHA-256>' \
  file:///tmp/fitloop-0.1.6-build.7/version.json
```

立即完成 #3：

```bash
curl -fsS 'https://43.139.72.25/apk/version.json'
curl -fsS 'https://43.139.72.25/apk/app-release.apk.sha256'
curl -fsS 'https://43.139.72.25/apk/app-release.apk' |
  sha256sum
```

哈希、版本、versionCode、API 地址和签名元数据必须与发布记录一致。

完成 #6，使用发布前记录的可信旧 SHA：

```bash
cd /root/FitLoop
bash deploy/install-apk.sh \
  --rollback '<可信旧版 APK SHA-256>'
```

确认旧版恢复后，再使用同一个 `/tmp` 候选三件套重新执行 forward 安装，
恢复 `0.1.6+7`。#3 或 #6 任一失败都停止并保持 Draft 未公开。

两项都通过并取得批准 D 后，本地 PowerShell：

```powershell
$Tag = 'v0.1.6-build.7'
& $Gh release edit $Tag `
  --repo chenxl6822/FitLoop `
  --draft=false
$Release = & $Gh release view $Tag `
  --repo chenxl6822/FitLoop `
  --json isDraft,assets,url |
  ConvertFrom-Json
if ($Release.isDraft) {
  throw 'Release 仍是 Draft'
}
$Release.url
```

Draft 创建、资产回下载核验和完整激活恢复命令继续使用
[人工发布执行手册第 13 节](MANUAL_RELEASE_RUNBOOK.md#13-31-项通过后创建-draft安装并完成最后两项)
的 fail-fast 代码块。

## 14. 上线观察和紧急回滚

```bash
cd /root/FitLoop
bash deploy/monitor.sh --alert
docker logs --since 1h fitloop-backend 2>&1 | tail -n 200
docker logs --since 1h fitloop-agent-service 2>&1 | tail -n 200
curl -fsS 'https://43.139.72.25/actuator/health'
```

APK 异常时只使用发布记录中的可信 previous SHA：

```bash
bash deploy/install-apk.sh \
  --rollback '<发布记录中的目标 previous APK SHA-256>'
```

不要手工修改 `active`、`states/` 或 `releases/`。代码回滚通过新分支、
`git revert`、PR 和 CI 完成，禁止 `git reset --hard`。

## 15. 完成证据清单

公开 Release 前，发布记录必须包含：

- 远端 `main` commit 和成功 CI URL。
- SSH ED25519 SHA-256 及可信核验来源。
- 数据库备份文件路径、大小、SHA-256 和隔离恢复结果。
- 旧 APK 来源、SHA-256 和兼容签名指纹。
- IP 证书 SAN、有效期、Certbot 版本、renew dry-run 和 reload hook 结果。
- 候选 APK、checksum、metadata、签名指纹和发布记录 SHA-256。
- `--verify-only` 前后 active 不变的证据。
- 31 项激活前和 2 项激活后真机记录。
- Draft 资产回下载哈希。
- 四个独立批准记录。
- 激活、回滚、候选恢复、监控和最终 Release URL。
