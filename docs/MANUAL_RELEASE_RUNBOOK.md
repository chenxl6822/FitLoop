# FitLoop `0.1.6+7` 人工发布执行手册

本手册列出代码之外必须由项目负责人亲自完成的操作。按顺序执行，不要跳过备份、签名核对、真机冒烟或回滚准备。涉及密码、授权码、API Key 的位置只在交互提示、密码管理器或未跟踪的 `.env` 中填写，不要粘贴到 Git、聊天或终端命令历史。

当前发布边界：公开 APK 继续使用已发布版本的兼容证书；新建正式 keystore 只做离线备份和构建验证，不得用于本次公开 APK。

本文主体使用域名证书。若发布端点采用固定公网 IP
`43.139.72.25`，不要把 `--domain` 机械替换成 IP；使用
[固定公网 IP HTTPS 发布补充手册](IP_HTTPS_RELEASE_RUNBOOK.md)，并继续
执行本文中与备份、签名、三件套、真机、批准和回滚有关的全部门禁。

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
| 已核验旧版 APK | `fitloop-0.1.5-build.6.apk` | 现网发布记录或离线备份 |

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

首次迁移前必须在本地验证旧版 `0.1.5+6` APK。不要从当前公网地址重新下载
后直接把它当作信任锚；使用此前留存且来源已核验的发布件或离线备份：

```powershell
$LegacyApk = Read-Host '输入已核验的旧版 0.1.5+6 APK 路径'
if (-not (Test-Path -LiteralPath $LegacyApk -PathType Leaf)) {
  throw "Trusted legacy APK not found: $LegacyApk"
}

$SdkRoots = @($env:ANDROID_SDK_ROOT, $env:ANDROID_HOME) |
  Where-Object { $_ -and (Test-Path -LiteralPath $_) } |
  Select-Object -Unique
$ApkSigner = $SdkRoots |
  ForEach-Object {
    Get-ChildItem -LiteralPath (Join-Path $_ 'build-tools') `
      -Recurse -Filter apksigner.bat -ErrorAction SilentlyContinue
  } |
  Sort-Object FullName -Descending |
  Select-Object -First 1
if (-not $ApkSigner) {
  throw 'Android apksigner.bat was not found'
}

$ApkSignerPath = $ApkSigner.FullName
$SignerOutput = & $ApkSignerPath verify --print-certs $LegacyApk 2>&1
if ($LASTEXITCODE -ne 0) {
  throw 'Legacy APK signature verification failed'
}
$SignerMatch = $SignerOutput |
  Select-String -Pattern 'certificate SHA-256 digest:\s*([0-9a-fA-F]{64})' |
  Select-Object -First 1
if (-not $SignerMatch) {
  throw 'Legacy APK signer fingerprint was not found'
}
$LegacySignerSha256 =
  $SignerMatch.Matches[0].Groups[1].Value.ToLowerInvariant()
$ApprovedCompatibilitySigner =
  '69316bd8f5a1d79dad539415f88b3ecbaf43f3113831782e35499c0f55a47c2a'
if ($LegacySignerSha256 -cne $ApprovedCompatibilitySigner) {
  throw 'Legacy APK signer does not match the approved compatibility signer'
}

$LegacySha256 =
  (Get-FileHash -Algorithm SHA256 $LegacyApk).Hash.ToLowerInvariant()
Write-Host "Trusted legacy APK SHA-256: $LegacySha256"
Write-Host "Trusted legacy signer SHA-256: $LegacySignerSha256"
```

把这两个值写入发布记录。`$LegacySha256` 是首次 `--import-legacy` 的必填
信任锚；导入旧版并激活新候选后，它也是首次 managed previous rollback
的信任锚。不能在故障发生后从待回滚目录临时计算并替代。

服务器除了 Docker、Docker Compose、curl、openssl 和 bc，还必须提供
Python 3 与 `flock`。Ubuntu/Debian 可在首次执行本手册前安装：

```bash
sudo apt-get update
sudo apt-get install -y python3 util-linux
command -v python3
command -v flock
```

## 1. 推送分支、创建 PR、等待 CI、合并

```powershell
cd $Repo
git status --short --branch
git log -1 --oneline
$ReleaseBranch = (git branch --show-current).Trim()
if ([string]::IsNullOrWhiteSpace($ReleaseBranch) -or
    $ReleaseBranch -in @('main', 'master')) {
  throw '必须从已完成并验证的发布分支创建 PR'
}
$Dirty = @(git status --porcelain)
if ($Dirty.Count -ne 0) {
  throw '工作区不干净，停止发布流程'
}
git push -u origin $ReleaseBranch
```

工作区必须干净。安装了 GitHub CLI 时：

```powershell
gh auth status
gh pr view $ReleaseBranch
```

如果 PR 尚不存在：

```powershell
gh pr create `
  --draft `
  --base main `
  --head $ReleaseBranch `
  --title 'release: prepare FitLoop 0.1.6+7 production stability' `
  --body '认证续期、TLS/Agent 降级、APK 发布治理、移动端模块化、CI 和发布文档。不得在真机与生产验证前发布 APK。'
```

等待所有 CI：

```powershell
gh pr checks $ReleaseBranch --watch
```

所有必需检查全绿且人工审查通过后，先转为 Ready，再合并：

```powershell
gh pr ready $ReleaseBranch
gh pr merge $ReleaseBranch --merge
git fetch origin
git switch main
git merge --ff-only origin/main
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

服务器可能仍运行旧提交中的不安全备份脚本。必须先从已经通过 CI 的本地
`main` 把当前 `deploy/backup.sh` 作为只读来源上传到服务器 `/tmp`，不得
先在服务器执行旧版 `deploy/backup.sh`。

在本地 PowerShell 执行：

```powershell
cd $Repo
if (@(git status --porcelain).Count -ne 0) {
  throw '本地工作区不干净，拒绝交付备份脚本'
}
$LocalBranch = (git branch --show-current).Trim()
if ($LocalBranch -cne 'main') {
  throw "当前本地分支不是 main: $LocalBranch"
}
$LocalMainCommit = (git rev-parse HEAD).Trim()
$RemoteMainCommit = (git rev-parse origin/main).Trim()
if ($LocalMainCommit -cne $RemoteMainCommit) {
  throw "本地 main 与 origin/main 不一致，拒绝交付备份脚本"
}

$SafeBackupStage = Join-Path `
  ([IO.Path]::GetTempPath()) `
  "fitloop-safe-backup-$RemoteMainCommit"
$SafeBackupArchive = "$SafeBackupStage.zip"
if ((Test-Path -LiteralPath $SafeBackupStage) -or
    (Test-Path -LiteralPath $SafeBackupArchive)) {
  throw "临时交付路径已存在，拒绝覆盖: $SafeBackupStage"
}

try {
  New-Item -ItemType Directory -Path $SafeBackupStage `
    -ErrorAction Stop | Out-Null
  git `
    -c core.autocrlf=false `
    archive `
    --format=zip `
    "--output=$SafeBackupArchive" `
    $RemoteMainCommit `
    deploy/backup.sh
  if ($LASTEXITCODE -ne 0) {
    throw '无法从已验证的 origin/main Git 对象导出 backup.sh'
  }
  Expand-Archive `
    -LiteralPath $SafeBackupArchive `
    -DestinationPath $SafeBackupStage `
    -ErrorAction Stop

  $SafeBackupScript = Join-Path `
    $SafeBackupStage `
    'deploy\backup.sh'
  if (-not (Test-Path -LiteralPath $SafeBackupScript -PathType Leaf)) {
    throw '导出的 backup.sh 不存在'
  }
  $SafeBackupScriptSha256 = (
    Get-FileHash -Algorithm SHA256 $SafeBackupScript
  ).Hash.ToLowerInvariant()
  $RemoteSafeBackupScript =
    "/tmp/fitloop-backup-$SafeBackupScriptSha256.sh"

  scp $SafeBackupScript `
    "${SshTarget}:$RemoteSafeBackupScript"
  if ($LASTEXITCODE -ne 0) {
    throw '上传安全 backup.sh 失败'
  }

  Write-Host "Safe backup script: $RemoteSafeBackupScript"
  Write-Host "Safe backup script SHA-256: $SafeBackupScriptSha256"
}
finally {
  if (Test-Path -LiteralPath $SafeBackupArchive) {
    Remove-Item -LiteralPath $SafeBackupArchive -Force
  }
  if (Test-Path -LiteralPath $SafeBackupStage) {
    Remove-Item -LiteralPath $SafeBackupStage -Recurse -Force
  }
}
```

`git archive` 必须从已验证的 `origin/main` 提交导出脚本，并显式关闭
`core.autocrlf`，避免 Windows 工作树或归档过滤把 CRLF 换行带入 Linux
服务器。记录两个输出值。服务器必须在执行脚本前重新计算并匹配 SHA-256；
不要从服务器旧工作树复制或运行同名脚本。

登录服务器：

```powershell
ssh $SshTarget
```

先提升到 root；看到 root 提示符后，再完整执行下一段 fail-fast 代码块，不要逐行跳过失败：

```bash
sudo -i
```

```bash
LEGACY_APPROVED_SHA256='<粘贴第 0 节记录的旧版 APK SHA-256>'
SAFE_BACKUP_SCRIPT='<粘贴本节本地输出的 /tmp 路径>'
SAFE_BACKUP_SCRIPT_SHA256='<粘贴本节本地输出的脚本 SHA-256>'
export LEGACY_APPROVED_SHA256
export SAFE_BACKUP_SCRIPT
export SAFE_BACKUP_SCRIPT_SHA256

bash -euo pipefail <<'FITLOOP'
cd /root/FitLoop

BACKUP_DIR="/root/backups/fitloop-pre-016-$(date +%Y%m%d_%H%M%S)"
mkdir -p "${BACKUP_DIR}"
chmod 0700 "${BACKUP_DIR}"
install -d -m 0700 \
    "${BACKUP_DIR}/database" \
    "${BACKUP_DIR}/flat" \
    "${BACKUP_DIR}/config" \
    "${BACKUP_DIR}/history"

[[ "${LEGACY_APPROVED_SHA256}" =~ ^[0-9a-f]{64}$ ]]
[[ "${SAFE_BACKUP_SCRIPT_SHA256}" =~ ^[0-9a-f]{64}$ ]]
test -f "${SAFE_BACKUP_SCRIPT}"
test "$(
    sha256sum "${SAFE_BACKUP_SCRIPT}" |
        awk '{ print $1 }'
)" = "${SAFE_BACKUP_SCRIPT_SHA256}"
SAFE_BACKUP_RUNNER="${BACKUP_DIR}/config/backup.sh"
install -m 0700 -- \
    "${SAFE_BACKUP_SCRIPT}" \
    "${SAFE_BACKUP_RUNNER}"
test "$(
    sha256sum "${SAFE_BACKUP_RUNNER}" |
        awk '{ print $1 }'
)" = "${SAFE_BACKUP_SCRIPT_SHA256}"

APK_SOURCE=deploy/apk
if [ -d deploy/apk/active/current ]; then
    APK_SOURCE=deploy/apk/active/current
fi
test -f "${APK_SOURCE}/app-release.apk"
LEGACY_ACTUAL_SHA256="$(
    sha256sum "${APK_SOURCE}/app-release.apk" |
        awk '{ print $1 }'
)"
test "${LEGACY_ACTUAL_SHA256}" = "${LEGACY_APPROVED_SHA256}"
test -f "${APK_SOURCE}/version.json"
python3 -c \
  'import json,pathlib,sys; json.loads(pathlib.Path(sys.argv[1]).read_text(encoding="utf-8-sig"))' \
  "${APK_SOURCE}/version.json"

cp --preserve=mode,timestamps -- \
    "${APK_SOURCE}/app-release.apk" \
    "${APK_SOURCE}/version.json" \
    "${BACKUP_DIR}/flat/"
(
    cd "${BACKUP_DIR}/flat"
    sha256sum app-release.apk > app-release.apk.sha256
    sha256sum -c app-release.apk.sha256
)
if [ -f deploy/apk/fitloop-release.apk ]; then
    cp --preserve=mode,timestamps -- \
        deploy/apk/fitloop-release.apk \
        "${BACKUP_DIR}/flat/"
fi
test -f .env
install -m 0600 .env "${BACKUP_DIR}/config/.env"

mapfile -d '' -t HISTORY_FILES < <(
    find deploy \
        -type f \
        -name '*.bak.*' \
        -print0 |
      sort -z
)
for history_source in "${HISTORY_FILES[@]}"; do
    history_relative="${history_source#deploy/}"
    if ! [[ "${history_relative}" =~ ^(apk/(app-release|fitloop-release)\.apk|docker-compose\.yml|download\.html|nginx\.conf|\.env)\.bak\.([0-9]{14}|[0-9]{8}_[0-9]{6})$ ]]; then
        printf 'ERROR: unexpected historical backup path: %s\n' \
            "${history_source}" >&2
        exit 1
    fi
    history_real="$(realpath -- "${history_source}")"
    case "${history_real}" in
        /root/FitLoop/deploy/*) ;;
        *)
            printf 'ERROR: historical backup escaped deploy/: %s\n' \
                "${history_real}" >&2
            exit 1
            ;;
    esac
    history_destination="${BACKUP_DIR}/history/${history_relative}"
    install -D -m 0600 -- \
        "${history_source}" \
        "${history_destination}"
    cmp -s -- "${history_source}" "${history_destination}"
done

FITLOOP_BACKUP_DIR="${BACKUP_DIR}/database" \
FITLOOP_BACKUP_RETENTION_DAYS=36500 \
FITLOOP_ENV_FILE=/root/FitLoop/.env \
FITLOOP_MYSQL_CONTAINER=fitloop-mysql \
bash "${SAFE_BACKUP_RUNNER}"

mapfile -d '' -t DB_BACKUPS < <(
    find "${BACKUP_DIR}/database" \
        -maxdepth 1 \
        -type f \
        -name 'fitloop_*.sql.gz' \
        -print0
)
test "${#DB_BACKUPS[@]}" -eq 1
gzip -t "${DB_BACKUPS[0]}"
test -s "${DB_BACKUPS[0]}"

find "${BACKUP_DIR}" -type d -exec chmod 0700 -- {} +
find "${BACKUP_DIR}" -type f -exec chmod 0600 -- {} +
(
    cd "${BACKUP_DIR}"
    find flat config database history \
        -type f \
        ! -name SHA256SUMS \
        -print0 |
      sort -z |
      xargs -0 sha256sum > SHA256SUMS
    sha256sum -c SHA256SUMS
)

for history_source in "${HISTORY_FILES[@]}"; do
    history_relative="${history_source#deploy/}"
    history_destination="${BACKUP_DIR}/history/${history_relative}"
    cmp -s -- "${history_source}" "${history_destination}"
    rm -- "${history_source}"
done

printf 'Pre-upgrade backup: %s\n' "${BACKUP_DIR}"

if [ -n "$(git status --porcelain)" ]; then
    git status --short
    echo 'ERROR: tracked or untracked repository changes must be reviewed and archived outside the repository before update' >&2
    exit 1
fi
printf '%s\n' \
    'Protection phase complete.' \
    'STOP here until the code-update and deployment phase has separate approval.'
FITLOOP
```

上面的归档只接受列出的 APK、Nginx、Compose、下载页和 `.env` 历史备份命名，
并在安全目录中逐文件 `cmp`、生成并验证 `SHA256SUMS` 后，才从仓库迁出原文件。
恢复时按 `history/` 下的相对路径复制回 `/root/FitLoop/deploy/`。记录输出的
`Pre-upgrade backup` 绝对路径、数据库备份文件名和 `SHA256SUMS`；这就是
预升级保护阶段的停止点。没有单独的代码更新与部署批准时，不要执行下一块。

获得单独批准后，把上一块输出的绝对路径填入 `BACKUP_DIR`，再执行：

```bash
LEGACY_APPROVED_SHA256='<粘贴第 0 节记录的旧版 APK SHA-256>'
BACKUP_DIR='<粘贴上一块输出的 Pre-upgrade backup 绝对路径>'
export LEGACY_APPROVED_SHA256
export BACKUP_DIR

bash -euo pipefail <<'FITLOOP'
cd /root/FitLoop

[[ "${LEGACY_APPROVED_SHA256}" =~ ^[0-9a-f]{64}$ ]]
case "${BACKUP_DIR}" in
    /root/backups/fitloop-pre-016-*) ;;
    *)
        printf 'ERROR: unexpected pre-upgrade backup path: %s\n' \
            "${BACKUP_DIR}" >&2
        exit 1
        ;;
esac
test -d "${BACKUP_DIR}"
test ! -L "${BACKUP_DIR}"
(
    cd "${BACKUP_DIR}"
    sha256sum -c SHA256SUMS
)

git fetch origin
git switch main
git pull --ff-only origin main
test -z "$(git status --porcelain)"
git log -1 --oneline

if [ ! -L deploy/apk/active ]; then
    install -d -m 0755 deploy/apk
    install -m 0644 \
        "${BACKUP_DIR}/flat/app-release.apk" \
        deploy/apk/app-release.apk
    install -m 0644 \
        "${BACKUP_DIR}/flat/app-release.apk.sha256" \
        deploy/apk/app-release.apk.sha256
    install -m 0644 \
        "${BACKUP_DIR}/flat/version.json" \
        deploy/apk/version.json
    (
        cd deploy/apk
        sha256sum -c app-release.apk.sha256
    )
    bash deploy/install-apk.sh \
      --import-legacy "${LEGACY_APPROVED_SHA256}"
fi
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
FITLOOP
```

如果保护阶段检测不到 `deploy/apk/active/current` 而使用旧 flat 目录，
这就是首次迁移。必须在首次执行第 5 节新版 Nginx 部署前完成
`--import-legacy`。旧提交中的 flat 文件会被 pull 删除，
所以代码块先把它们备份到仓库外，再在 pull 后恢复为被新 `.gitignore`
忽略的 flat 三件套，然后执行可信导入。脚本用第 0 节的可信 SHA-256
校验旧 flat 三件套，创建只有旧版 `current` 的 managed active。导入失败或
`active/current` 哈希不匹配时立即停止，不得继续部署。此处先保留已备份
的 flat 三件套，让仍运行旧 root 配置的 Nginx 继续服务，避免下载中断；
第 5 节确认新版 Nginx 已从 managed active 提供同一旧版后再移走它们。

如果 `--import-legacy` 在 `active` rename 后收到 TERM 并返回 143，保留
本节原始 `LEGACY_APPROVED_SHA256`，不要生成新参数或手工改指针；观察
`readlink deploy/apk/active` 和 current 哈希后，原样重跑：

```bash
bash deploy/install-apk.sh \
  --import-legacy "${LEGACY_APPROVED_SHA256}"
```

原参数重跑会执行目录 `sync`，并完整复验 imported active/state、三件套、
哈希和 metadata schema。只有重跑返回 0 才能继续第 5 节；若 `sync` 或
完整验证失败，仍按导入失败处理，保留 flat 与现场证据并进入人工恢复。

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

首次迁移必须在切换新版 Nginx **之前**再次确认 managed active 就是第 0 节
记录的可信旧版；新版 Nginx 启动后，再证明公网三件套来自 managed active，
然后才移走 flat 三件套。下面先在当前 root Shell 设置非秘密变量，再完整执行
fail-fast 子 Shell：

```bash
cd /root/FitLoop
read -r -p '正式域名: ' DOMAIN
read -r -p '第 0 节记录的旧版 APK SHA-256: ' LEGACY_APPROVED_SHA256
export DOMAIN LEGACY_APPROVED_SHA256

bash -euo pipefail <<'FITLOOP'
cd /root/FitLoop
[[ "${DOMAIN}" =~ ^[A-Za-z0-9.-]+$ ]]
[[ "${DOMAIN}" == *.* ]]
[[ "${LEGACY_APPROVED_SHA256}" =~ ^[0-9a-f]{64}$ ]]
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

bash deploy/deploy.sh cn
curl -fsS http://localhost:8080/actuator/health
curl -fsS "http://${DOMAIN}/actuator/health"

curl -fsS "http://${DOMAIN}/apk/version.json" |
  python3 -c \
    'import json,sys; json.loads(sys.stdin.buffer.read().decode("utf-8-sig"))'
PUBLIC_CHECKSUM="$(
    curl -fsS "http://${DOMAIN}/apk/app-release.apk.sha256"
)"
test "${PUBLIC_CHECKSUM}" = \
  "${LEGACY_APPROVED_SHA256}  app-release.apk"
PUBLIC_SHA256="$(
    curl -fsS "http://${DOMAIN}/apk/app-release.apk" |
        sha256sum |
        awk '{ print $1 }'
)"
test "${PUBLIC_SHA256}" = "${LEGACY_APPROVED_SHA256}"

if [ -e deploy/apk/app-release.apk ] ||
   [ -e deploy/apk/app-release.apk.sha256 ] ||
   [ -e deploy/apk/version.json ]
then
    BACKUP_DIR="/root/backups/fitloop-legacy-retired-$(date +%Y%m%d_%H%M%S)"
    mkdir -p "${BACKUP_DIR}"
    chmod 0700 "${BACKUP_DIR}"
    for ARTIFACT in app-release.apk app-release.apk.sha256 version.json; do
        test -f "deploy/apk/${ARTIFACT}"
        mv -- "deploy/apk/${ARTIFACT}" "${BACKUP_DIR}/${ARTIFACT}"
        test ! -e "deploy/apk/${ARTIFACT}"
    done
    (
        cd "${BACKUP_DIR}"
        sha256sum -c app-release.apk.sha256
    )
    printf 'Retired flat bundle backup: %s\n' "${BACKUP_DIR}"
fi

curl -fsS "http://${DOMAIN}/apk/version.json" |
  python3 -c \
    'import json,sys; json.loads(sys.stdin.buffer.read().decode("utf-8-sig"))'
test "$(
    curl -fsS "http://${DOMAIN}/apk/app-release.apk.sha256"
)" = "${LEGACY_APPROVED_SHA256}  app-release.apk"
test "$(
    curl -fsS "http://${DOMAIN}/apk/app-release.apk" |
        sha256sum |
        awk '{ print $1 }'
)" = "${LEGACY_APPROVED_SHA256}"
FITLOOP
```

移走 flat 三件套后，三个 URL 必须仍为 200 且哈希保持不变；否则立即停止
后续步骤并保留本节 `BACKUP_DIR`，不要继续签发证书或安装新候选。

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
  Copy-Item deploy\apk\app-release.apk.sha256 `
    (Join-Path $KeyDir 'fitloop-0.1.6-official-signing-validation.apk.sha256')
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
$Checksum = Join-Path $Repo 'deploy\apk\app-release.apk.sha256'
$VersionJson = Join-Path $Repo 'deploy\apk\version.json'
$Sha256 = (Get-FileHash -Algorithm SHA256 $Apk).Hash.ToLowerInvariant()
$ChecksumLine = (Get-Content $Checksum -Raw -Encoding ASCII).Trim()
$Metadata = Get-Content $VersionJson -Raw -Encoding UTF8 | ConvertFrom-Json

if ($ChecksumLine -cne "$Sha256  app-release.apk") {
  throw 'Checksum file does not match the APK'
}
if ([string]$Metadata.sha256 -cne $Sha256) {
  throw 'version.json sha256 does not match the APK'
}
if ([string]$Metadata.version -cne '0.1.6' -or [int]$Metadata.versionCode -ne 7) {
  throw 'Unexpected version or versionCode'
}
if ([string]$Metadata.apiBaseUrl -cne "https://$Domain") {
  throw 'version.json API base URL does not match the approved HTTPS domain'
}
if ([string]$Metadata.signingMode -cne 'Compatibility') {
  throw 'Unexpected signing mode'
}
if ([string]$Metadata.signerSha256 -cne '69316bd8f5a1d79dad539415f88b3ecbaf43f3113831782e35499c0f55a47c2a') {
  throw 'Unexpected APK signer fingerprint'
}

$Sha256
$Metadata | ConvertTo-Json
```

上述命令必须无异常完成，并确认：

```text
version = 0.1.6
versionCode = 7
apiBaseUrl = https://<DOMAIN>
signingMode = Compatibility
signerSha256 = 69316bd8f5a1d79dad539415f88b3ecbaf43f3113831782e35499c0f55a47c2a
```

## 11. 通过 SCP 暂存并校验候选，不改变公网下载

本地 PowerShell：

```powershell
$RemoteStage = '/tmp/fitloop-0.1.6-build.7'
$ApprovedCandidateSha256 = (
  Read-Host '粘贴第 10 节本地验证并写入发布记录的 APK SHA-256'
).Trim().ToLowerInvariant()
if ($ApprovedCandidateSha256 -notmatch '^[0-9a-f]{64}$') {
  throw '发布记录中的 APK SHA-256 格式无效'
}
$LocalCandidateSha256 = (
  Get-FileHash -Algorithm SHA256 "$Repo\deploy\apk\app-release.apk"
).Hash.ToLowerInvariant()
if ($LocalCandidateSha256 -cne $ApprovedCandidateSha256) {
  throw '本地候选 APK 已与发布记录中的可信 SHA-256 不一致'
}

ssh $SshTarget "install -d -m 700 $RemoteStage"
scp "$Repo\deploy\apk\app-release.apk" "${SshTarget}:$RemoteStage/app-release.apk"
scp "$Repo\deploy\apk\app-release.apk.sha256" "${SshTarget}:$RemoteStage/app-release.apk.sha256"
scp "$Repo\deploy\apk\version.json" "${SshTarget}:$RemoteStage/version.json"
Write-Host "Server verification trust anchor: $ApprovedCandidateSha256"
```

登录服务器并提升到 root：

```bash
sudo -i
```

把上一段 PowerShell 输出的可信 SHA-256 原样粘贴到下面变量，然后完整执行
fail-fast 校验块。不得从服务器上传包自己的 checksum 文件反推信任锚：

```bash
EXPECTED_SHA256='<粘贴第 10 节本地验证并写入发布记录的 APK SHA-256>'
export EXPECTED_SHA256

bash -euo pipefail <<'FITLOOP'
cd /root/FitLoop
REMOTE_STAGE=/tmp/fitloop-0.1.6-build.7

[[ "${EXPECTED_SHA256}" =~ ^[0-9a-f]{64}$ ]]
test -f "${REMOTE_STAGE}/app-release.apk"
test -f "${REMOTE_STAGE}/app-release.apk.sha256"
test -f "${REMOTE_STAGE}/version.json"
printf '%s  app-release.apk\n' "${EXPECTED_SHA256}" |
  cmp -s - "${REMOTE_STAGE}/app-release.apk.sha256"
test "$(
    sha256sum "${REMOTE_STAGE}/app-release.apk" |
        awk '{ print $1 }'
)" = "${EXPECTED_SHA256}"
(
    cd "${REMOTE_STAGE}"
    sha256sum -c app-release.apk.sha256
)
python3 -c \
  'import json,pathlib,sys; json.loads(pathlib.Path(sys.argv[1]).read_text(encoding="utf-8-sig"))' \
  "${REMOTE_STAGE}/version.json"

ACTIVE_BEFORE="$(readlink deploy/apk/active 2>/dev/null || true)"
bash deploy/install-apk.sh --verify-only \
  "file://${REMOTE_STAGE}/app-release.apk" \
  "${EXPECTED_SHA256}" \
  "file://${REMOTE_STAGE}/version.json"
ACTIVE_AFTER="$(readlink deploy/apk/active 2>/dev/null || true)"
test "${ACTIVE_AFTER}" = "${ACTIVE_BEFORE}"
FITLOOP
```

`--verify-only` 必须返回成功且不得改变 `deploy/apk/active`。候选仍位于
非公开的 `/tmp`，Nginx 继续只读取已经导入的 `active/current`。若
`active/current` 不存在，三个下载入口会返回 404；立即停止并修复第 3 节
legacy 导入，绝不能依赖 flat 根文件。除此之外的 `/apk/` 路径也全部返回
404。

## 12. 真机升级、认证和降级冒烟

完整记录使用 [SMOKE_TEST_CHECKLIST.md](SMOKE_TEST_CHECKLIST.md)。激活候选
前先完成除公网三件套核验（#3）和 APK 回滚演练（#6）外的 31 项，并填写
实际结果。第 3 节已把可信旧版导入 managed current，所以候选激活后 #6
统一演练 managed previous；不再存在 legacy fallback 回滚路径。连接测试
手机后，本地 PowerShell 可执行：

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

这 31 项中任何一项未通过都必须停止；不要安装服务器候选、切换
`deploy/apk/active` 或发布 GitHub Release。

## 13. 31 项通过后创建 Draft、安装并完成最后两项

先在本地把三件套附加到 Draft GitHub Release。创建命令在上传全部资产前
不会公开 Release：

```powershell
cd $Repo
$ApprovedCandidateSha256 = (
  Read-Host '粘贴第 10 节本地验证并写入发布记录的 APK SHA-256'
).Trim().ToLowerInvariant()
if ($ApprovedCandidateSha256 -notmatch '^[0-9a-f]{64}$') {
  throw '发布记录中的 APK SHA-256 格式无效'
}

$Apk = Join-Path $Repo 'deploy\apk\app-release.apk'
$Checksum = Join-Path $Repo 'deploy\apk\app-release.apk.sha256'
$VersionJson = Join-Path $Repo 'deploy\apk\version.json'
$LocalCandidateSha256 = (
  Get-FileHash -Algorithm SHA256 $Apk
).Hash.ToLowerInvariant()
if ($LocalCandidateSha256 -cne $ApprovedCandidateSha256) {
  throw '当前本地 APK 已与发布记录中的可信 SHA-256 不一致'
}
$ExpectedChecksumText =
  "$ApprovedCandidateSha256  app-release.apk`n"
$ActualChecksumText = [System.IO.File]::ReadAllText(
  $Checksum,
  [System.Text.Encoding]::ASCII
)
if ($ActualChecksumText -cne $ExpectedChecksumText) {
  throw '本地 checksum 不是可信 SHA-256 的 canonical LF 记录'
}
$Metadata = Get-Content $VersionJson -Raw -Encoding UTF8 |
  ConvertFrom-Json
if ([string]$Metadata.sha256 -cne $ApprovedCandidateSha256) {
  throw '本地 version.json sha256 与发布记录不一致'
}

$Tag = 'v0.1.6-build.7'
$AssetNames = @(
  'app-release.apk',
  'app-release.apk.sha256',
  'version.json'
)

gh release create $Tag `
  deploy\apk\app-release.apk `
  deploy\apk\app-release.apk.sha256 `
  deploy\apk\version.json `
  --draft `
  --target main `
  --title 'FitLoop 0.1.6+7' `
  --notes '生产稳定过渡版：认证续期、HTTPS、Agent 降级与发布治理。继续使用兼容签名。'
if ($LASTEXITCODE -ne 0) {
  throw 'Draft Release creation or asset upload failed'
}

$ReleaseJson = gh release view $Tag --json isDraft,assets,targetCommitish
if ($LASTEXITCODE -ne 0) {
  throw 'Draft Release could not be read back'
}
$Release = $ReleaseJson | ConvertFrom-Json
if (-not $Release.isDraft) {
  throw 'Release was published before artifact verification'
}
$PublishedAssetNames = @($Release.assets | ForEach-Object { $_.name })
if (Compare-Object ($AssetNames | Sort-Object) ($PublishedAssetNames | Sort-Object)) {
  throw 'Draft Release asset set is incomplete or unexpected'
}

$ReleaseVerifyDir = Join-Path ([System.IO.Path]::GetTempPath()) `
  "fitloop-release-$([guid]::NewGuid().ToString('N'))"
New-Item -ItemType Directory -Path $ReleaseVerifyDir | Out-Null
gh release download $Tag --dir $ReleaseVerifyDir
if ($LASTEXITCODE -ne 0) {
  throw 'Draft Release asset download failed'
}

foreach ($AssetName in $AssetNames) {
  $LocalAsset = Join-Path $Repo "deploy\apk\$AssetName"
  $DownloadedAsset = Join-Path $ReleaseVerifyDir $AssetName
  $LocalHash = (Get-FileHash -Algorithm SHA256 $LocalAsset).Hash
  $DownloadedHash = (Get-FileHash -Algorithm SHA256 $DownloadedAsset).Hash
  if ($LocalHash -cne $DownloadedHash) {
    throw "Draft Release asset hash mismatch: $AssetName"
  }
}
if ((Get-FileHash -Algorithm SHA256 (
      Join-Path $ReleaseVerifyDir 'app-release.apk'
    )).Hash.ToLowerInvariant() -cne $ApprovedCandidateSha256) {
  throw 'Downloaded Draft APK does not match the trusted release record'
}
Write-Host "Draft Release assets verified in $ReleaseVerifyDir"
```

Draft 三件套校验通过并再次取得单独发布批准后，在服务器正式安装：

```bash
sudo -i
```

```bash
DOMAIN='<正式域名>'
REMOTE_STAGE=/tmp/fitloop-0.1.6-build.7
EXPECTED_SHA256='<粘贴第 10 节本地验证并写入发布记录的 APK SHA-256>'
export DOMAIN REMOTE_STAGE EXPECTED_SHA256

bash -euo pipefail <<'FITLOOP'
cd /root/FitLoop
[[ "${DOMAIN}" =~ ^[A-Za-z0-9.-]+$ ]]
[[ "${DOMAIN}" == *.* ]]
[[ "${EXPECTED_SHA256}" =~ ^[0-9a-f]{64}$ ]]
printf '%s  app-release.apk\n' "${EXPECTED_SHA256}" |
  cmp -s - "${REMOTE_STAGE}/app-release.apk.sha256"
test "$(
    sha256sum "${REMOTE_STAGE}/app-release.apk" |
        awk '{ print $1 }'
)" = "${EXPECTED_SHA256}"

bash deploy/install-apk.sh \
  "file://${REMOTE_STAGE}/app-release.apk" \
  "${EXPECTED_SHA256}" \
  "file://${REMOTE_STAGE}/version.json"

test -L deploy/apk/active
test -d deploy/apk/active/current
(
    cd deploy/apk/active/current
    sha256sum -c app-release.apk.sha256
)
python3 -c \
  'import json,pathlib,sys; json.loads(pathlib.Path(sys.argv[1]).read_text(encoding="utf-8-sig"))' \
  deploy/apk/active/current/version.json
test "$(
    sha256sum deploy/apk/active/current/app-release.apk |
        awk '{ print $1 }'
)" = "${EXPECTED_SHA256}"

readlink deploy/apk/active
readlink deploy/apk/active/current
curl -fsS "https://${DOMAIN}/apk/version.json" |
  python3 -c \
    'import json,sys; json.loads(sys.stdin.buffer.read().decode("utf-8-sig"))'
PUBLIC_CHECKSUM="$(
    curl -fsS "https://${DOMAIN}/apk/app-release.apk.sha256"
)"
test "${PUBLIC_CHECKSUM}" = "${EXPECTED_SHA256}  app-release.apk"
PUBLIC_SHA256="$(
    curl -fsS "https://${DOMAIN}/apk/app-release.apk" |
        sha256sum |
        awk '{ print $1 }'
)"
test "${PUBLIC_SHA256}" = "${EXPECTED_SHA256}"
FITLOOP
```

服务器安装器只校验受信 SHA-256 链路、三件套字节关系和固定 metadata
schema；它不会从 APK 本体重新解析签名证书或 API/SDK 信息。APK 本体的
真实性由前面的本地 `deploy/build-apk.ps1`、`apksigner` 和 `aapt`
（适用时）验证，并由人工把已验证的 `EXPECTED_SHA256` 准确复制到服务器
命令中建立信任锚。

如果安装命令返回 143，可能是 `active` 已完成原子 rename 后才收到
`SIGTERM`，不能据此断言激活失败。立即执行：

```bash
bash -euo pipefail <<'FITLOOP'
cd /root/FitLoop
readlink deploy/apk/active
readlink deploy/apk/active/current
ACTIVE_SHA256="$(
    sha256sum deploy/apk/active/current/app-release.apk |
        awk '{ print $1 }'
)"
test "${ACTIVE_SHA256}" = "${EXPECTED_SHA256}"

bash deploy/install-apk.sh \
  "file://${REMOTE_STAGE}/app-release.apk" \
  "${EXPECTED_SHA256}" \
  "file://${REMOTE_STAGE}/version.json"
FITLOOP
```

必须使用上述原 URL、`EXPECTED_SHA256` 和 metadata URL 原样重跑；重跑会
执行目录 `sync`，并完整复验 active/state 布局、current 三件套、哈希和
metadata schema，同时核对可选 previous 指针关系。只有重跑返回 0 才确认耐久收敛。即使
`readlink`/哈希看似正确，只要重跑的 `sync` 或完整验证失败，仍按安装失败
处理，保留现场证据并进入人工恢复，不得继续 #3、发布 Draft 或手工改指针。

上述公网版本、元数据和哈希检查通过后，才能在清单中把 #3 标记为通过。
此时 Draft 仍不得发布。立即按第 14 节执行 APK 回滚演练 #6，使用发布
记录中的可信 SHA-256 回滚到 managed previous。首次迁移的 previous 就是
第 3 节导入的可信旧版。再使用
`/tmp` 中已经校验的候选三件套重新调用安装脚本，恢复本次候选：

```bash
bash -euo pipefail <<'FITLOOP'
cd /root/FitLoop
[[ "${EXPECTED_SHA256}" =~ ^[0-9a-f]{64}$ ]]
printf '%s  app-release.apk\n' "${EXPECTED_SHA256}" |
  cmp -s - "${REMOTE_STAGE}/app-release.apk.sha256"
test "$(
    sha256sum "${REMOTE_STAGE}/app-release.apk" |
        awk '{ print $1 }'
)" = "${EXPECTED_SHA256}"
bash deploy/install-apk.sh \
  "file://${REMOTE_STAGE}/app-release.apk" \
  "${EXPECTED_SHA256}" \
  "file://${REMOTE_STAGE}/version.json"
(
    cd deploy/apk/active/current
    sha256sum -c app-release.apk.sha256
)
test "$(
    sha256sum deploy/apk/active/current/app-release.apk |
        awk '{ print $1 }'
)" = "${EXPECTED_SHA256}"
curl -fsS "https://${DOMAIN}/apk/version.json" |
  python3 -c \
    'import json,sys; json.loads(sys.stdin.buffer.read().decode("utf-8-sig"))'
test "$(
    curl -fsS "https://${DOMAIN}/apk/app-release.apk.sha256"
)" = "${EXPECTED_SHA256}  app-release.apk"
test "$(
    curl -fsS "https://${DOMAIN}/apk/app-release.apk" |
        sha256sum |
        awk '{ print $1 }'
)" = "${EXPECTED_SHA256}"
FITLOOP
```

#3 或 #6 任一失败时必须立即回滚，保留现场证据，并停止后续发布。只有
两项都通过、候选已恢复为 `active/current`，才允许继续。

安装脚本把三件套保存到按 SHA-256 内容寻址且写保护的
`deploy/apk/releases/<apk-sha256>`，创建包含 `current` 和 `previous`
链接的写保护 `deploy/apk/states/<state-id>`，最后在 `flock` 保护下
原子切换 `deploy/apk/active`。release/state 目录权限为 `0555`，release
普通文件为 `0444`；这不是无法绕过的强制不可改写保证，同一部署用户或 `root`
仍可先 `chmod`，所以禁止原地改写。安装器会拒绝 release/state 额外成员、
release 硬链接和未知 metadata 字段。Nginx 只精确公开三件套 URL，并且
只读取 `active/current`；任一目标文件缺失都单独返回 404，其他 `/apk/`
路径也全部返回 404。第 5 节确认新版 Nginx 从 managed active 提供旧版后，
flat 根三件套已经备份并移出站点目录，不能作为回滚路径。

服务器全部验证通过后，回到本地 PowerShell 发布已经核验的 Draft：

```powershell
gh release edit $Tag --draft=false
$Release = gh release view $Tag --json isDraft,assets,url | ConvertFrom-Json
if ($Release.isDraft) {
  throw 'Release is still a draft'
}
$Release.url
```

如果仓库是私有仓库，服务器下载不能依赖匿名 GitHub Release URL；继续
使用已通过 SCP 校验的 `/tmp` 候选，或改用有访问控制的对象存储。

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

若 `--rollback` 在 `active` rename 后收到 TERM 并返回 143，不要根据当前
指针改算信任锚。保留发布记录中的原始 `EXPECTED_PREVIOUS_SHA256`，观察
现场后原样重跑同一 `--rollback` 命令。重跑会执行目录 `sync`，并完整
复验 rollback active/state 布局、current 三件套、哈希和 metadata schema，
同时核对可选 previous 指针关系；只有返回 0 才确认回滚耐久完成。`sync` 或完整验证失败仍是回滚
失败，必须保留证据并进入人工恢复，不能继续重装候选。

```bash
DOMAIN='<正式域名>'
EXPECTED_PREVIOUS_SHA256='<粘贴发布记录中目标回滚版本的 SHA-256>'
export DOMAIN EXPECTED_PREVIOUS_SHA256

bash -euo pipefail <<'FITLOOP'
cd /root/FitLoop
CURRENT_DIR=deploy/apk/active/current
[[ "${DOMAIN}" =~ ^[A-Za-z0-9.-]+$ ]]
[[ "${DOMAIN}" == *.* ]]
[[ "${EXPECTED_PREVIOUS_SHA256}" =~ ^[0-9a-f]{64}$ ]]

ROLLBACK_BACKUP="/root/backups/fitloop-apk-failed-$(date +%Y%m%d_%H%M%S)"
mkdir -p "${ROLLBACK_BACKUP}"
chmod 0700 "${ROLLBACK_BACKUP}"
for ARTIFACT in app-release.apk app-release.apk.sha256 version.json; do
    if [ -f "${CURRENT_DIR}/${ARTIFACT}" ]; then
        cp --preserve=mode,timestamps \
            "${CURRENT_DIR}/${ARTIFACT}" \
            "${ROLLBACK_BACKUP}/${ARTIFACT}"
    fi
done
printf 'Failed candidate backup: %s\n' "${ROLLBACK_BACKUP}"

bash deploy/install-apk.sh --rollback "${EXPECTED_PREVIOUS_SHA256}"

ROLLBACK_DIR=deploy/apk/active/current
test -f "${ROLLBACK_DIR}/app-release.apk"
test -f "${ROLLBACK_DIR}/app-release.apk.sha256"
test -f "${ROLLBACK_DIR}/version.json"
(
    cd "${ROLLBACK_DIR}"
    sha256sum -c app-release.apk.sha256
)
python3 -c \
  'import json,pathlib,sys; json.loads(pathlib.Path(sys.argv[1]).read_text(encoding="utf-8-sig"))' \
  "${ROLLBACK_DIR}/version.json"
ROLLED_BACK_SHA256="$(
    sha256sum "${ROLLBACK_DIR}/app-release.apk" |
        awk '{ print $1 }'
)"
test "${ROLLED_BACK_SHA256}" = "${EXPECTED_PREVIOUS_SHA256}"

curl -fsS "https://${DOMAIN}/apk/version.json" |
  python3 -c \
    'import json,sys; json.loads(sys.stdin.buffer.read().decode("utf-8-sig"))'
PUBLIC_CHECKSUM="$(
    curl -fsS "https://${DOMAIN}/apk/app-release.apk.sha256"
)"
test "${PUBLIC_CHECKSUM}" = "${ROLLED_BACK_SHA256}  app-release.apk"
PUBLIC_SHA256="$(
    curl -fsS "https://${DOMAIN}/apk/app-release.apk" |
        sha256sum |
        awk '{ print $1 }'
)"
test "${PUBLIC_SHA256}" = "${ROLLED_BACK_SHA256}"
FITLOOP
```

不要手工改写 `active`、`current`、`previous` 或内容寻址且写保护的
`releases/` 内容。`--rollback` 会忽略可能损坏的 current，要求 managed
previous 实际 APK 哈希与命令行信任锚一致，严格校验三件套后原子建立
回滚 state。若不存在 managed previous，命令必须失败并保持 `active`
不变；不会撤下 `active`，也不会读取已移出站点目录的 flat 三件套。回滚
schema 校验不受面向新安装的 `0.1.6+7` policy 限制。不要在故障发生后从
待回滚目录临时计算信任锚。

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
