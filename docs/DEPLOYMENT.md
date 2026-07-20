# FitLoop 部署与运维指南

本文是项目唯一的部署文档，覆盖本地构建、腾讯云 Ubuntu 服务器部署、APK 发布、验证、备份和常见故障处理。部署脚本与 Compose 配置以 `deploy/` 目录为准。

## 1. 部署结构

| 服务 | 容器 | 对外入口 |
| --- | --- | --- |
| MySQL 8 | `fitloop-mysql` | 仅宿主机 `127.0.0.1:3306` |
| Redis 6.2 | `fitloop-redis` | 仅宿主机 `127.0.0.1:6379` |
| Spring Boot | `fitloop-backend` | `8080`，由 Nginx 代理 |
| Nginx | `fitloop-nginx` | `80`，提供 API、上传文件和 APK 下载 |

生产仓库固定放在 `/root/FitLoop`，因为备份脚本从 `/root/FitLoop/.env` 读取配置。Ubuntu 默认用户登录后需要执行 `sudo -i`。

服务器安全组只需开放 `22`、`80`，配置域名和 HTTPS 后再开放 `443`。不要向公网开放 `3306` 和 `6379`。

## 2. 本地发布准备

发布前确保 Android `versionCode` 严格大于线上版本。例如线上为 `0.1.2+3`，下一版应使用 `0.1.3+4`：

```yaml
# mobile/pubspec.yaml
version: 0.1.3+4
```

在 Windows PowerShell 构建生产 APK：

```powershell
cd D:\AIWorkspace\projects\FitLoop
powershell -ExecutionPolicy Bypass -File deploy\build-apk.ps1 -ApiBaseUrl http://<SERVER_IP>
```

脚本会依次执行依赖安装、静态分析、Flutter 测试和 Release 构建，并更新：

- `deploy/apk/app-release.apk`
- `deploy/apk/version.json`

提交并推送源码、版本号、APK 和版本元数据：

```powershell
git add mobile/pubspec.yaml deploy/apk/app-release.apk deploy/apk/version.json
git commit -m "chore(release): publish Android <VERSION>"
git push origin main
```

## 3. 首次部署

### 3.1 初始化服务器

```bash
ssh ubuntu@<SERVER_IP>
sudo -i
apt update
apt install -y curl git openssl
timedatectl set-timezone Asia/Shanghai
curl -fsSL https://get.docker.com | sh
docker --version
docker compose version
```

拉取仓库：

```bash
cd /root
git clone https://github.com/chenxl6822/FitLoop.git
cd /root/FitLoop
```

国内服务器可以将仓库地址替换为可用的 GitHub 代理，但应确保 `origin/main` 指向同一个仓库。

### 3.2 配置生产环境变量

```bash
cd /root/FitLoop
bash deploy/gen-secrets.sh
cp deploy/.env.production .env
nano .env
```

必须替换 `.env` 中的占位符，至少包含：

```dotenv
MYSQL_DATABASE=fitloop
MYSQL_USER=fitloop
MYSQL_PASSWORD=<STRONG_PASSWORD>
MYSQL_ROOT_PASSWORD=<DIFFERENT_STRONG_PASSWORD>
FITLOOP_JWT_SECRET=<LONG_RANDOM_SECRET>
FITLOOP_ADMIN_KEY=<LONG_RANDOM_ADMIN_KEY>
FITLOOP_OTP_HASH_SECRET=<LONG_RANDOM_OTP_SECRET>
FITLOOP_OTP_DEBUG_RETURN=false
SERVER_PORT=8080
```

如果启用邮箱验证码，还需设置 `FITLOOP_MAIL_HOST`、`FITLOOP_MAIL_PORT`、`FITLOOP_MAIL_USERNAME`、`FITLOOP_MAIL_PASSWORD` 和 `FITLOOP_MAIL_FROM`。`.env` 已被 Git 忽略，禁止提交。

### 3.3 启动服务

国内服务器：

```bash
cd /root/FitLoop
bash deploy/deploy.sh cn
```

海外服务器：

```bash
cd /root/FitLoop
bash deploy/deploy.sh
```

## 4. 日常更新部署

本地先完成测试、发布提交和 `git push`。服务器执行：

```bash
ssh ubuntu@<SERVER_IP>
sudo -i
cd /root/FitLoop
bash deploy/backup.sh
git status --short
git fetch origin
git checkout main
git pull --ff-only origin main
bash deploy/deploy.sh cn
```

正常情况下服务器仓库不应存在已跟踪文件的本地修改。生产差异应放在被忽略的 `.env`，不要直接修改 `deploy/nginx.conf`。

如果历史部署已经修改了已跟踪文件，先备份再拉取，禁止直接执行 `git reset --hard`：

```bash
cd /root/FitLoop
BACKUP_DIR="/root/fitloop-server-local-$(date +%Y%m%d_%H%M%S)"
mkdir -p "$BACKUP_DIR"
cp deploy/nginx.conf "$BACKUP_DIR/nginx.conf"
cp deploy/apk/app-release.apk "$BACKUP_DIR/app-release.apk"
cp deploy/apk/version.json "$BACKUP_DIR/version.json"
git restore deploy/nginx.conf deploy/apk/app-release.apk deploy/apk/version.json
git pull --ff-only origin main
```

只在确认确有服务器专用规则时恢复 `nginx.conf`；不要恢复旧 APK 和旧 `version.json`。恢复了跟踪文件会导致下次拉取再次冲突，应尽快将必要差异正式纳入仓库配置。

## 5. 部署验证

```bash
docker ps
curl -fsS http://localhost:8080/actuator/health
curl -fsS http://localhost/actuator/health
curl -fsS http://localhost/apk/version.json
curl -I http://localhost/apk/app-release.apk
docker logs --tail 100 fitloop-backend
```

期望结果：

- MySQL、Redis、Backend 均为 `healthy`；
- 两个健康检查均返回 `{"status":"UP"}`；
- APK 返回 HTTP 200；
- `version.json` 与 `mobile/pubspec.yaml` 的版本一致；
- APK `Last-Modified` 是本次发布时间。

公网验证：

```powershell
curl.exe http://<SERVER_IP>/actuator/health
curl.exe http://<SERVER_IP>/apk/version.json
curl.exe -I http://<SERVER_IP>/apk/app-release.apk
```

## 6. 备份、监控与日志

手动备份数据库：

```bash
cd /root/FitLoop
bash deploy/backup.sh
ls -lh /root/backups/fitloop/
```

健康监控：

```bash
cd /root/FitLoop
bash deploy/monitor.sh
```

建议的定时任务：

```cron
0 3 * * * /root/FitLoop/deploy/backup.sh >> /var/log/fitloop-backup.log 2>&1
0 9 * * * /root/FitLoop/deploy/monitor.sh --alert >> /var/log/fitloop-monitor.log 2>&1
```

常用日志命令：

```bash
docker logs -f --tail 100 fitloop-backend
docker logs -f --tail 100 fitloop-mysql
docker compose -f deploy/docker-compose.yml -f deploy/docker-compose.cn.yml --env-file .env ps
```

## 7. HTTPS

正式处理账号、JWT 和健康数据时应使用 HTTPS。准备已备案域名并解析到服务器后，参考 `deploy/nginx.ssl.conf` 配置证书和反向代理。不要同时让宿主机 Nginx和 Docker Nginx占用相同的 `80/443` 端口。

申请证书前确认域名解析生效，然后使用 Certbot 或腾讯云证书服务。切换 HTTPS 后重新构建 APK：

```powershell
powershell -ExecutionPolicy Bypass -File deploy\build-apk.ps1 -ApiBaseUrl https://<DOMAIN>
```

## 8. 故障定位

| 现象 | 处理 |
| --- | --- |
| `cd /root/FitLoop: Permission denied` | 使用 `ubuntu` 登录后执行 `sudo -i` |
| `git pull` 提示本地修改会被覆盖 | 按第 4 节先备份，再恢复跟踪文件后拉取 |
| Backend 非 healthy | 查看 `docker logs --tail 200 fitloop-backend` |
| APK 仍是旧版本 | 检查 Git 提交、`version.json`、APK 修改时间和 Nginx 挂载目录 |
| 手机无法覆盖安装 | 提升 `mobile/pubspec.yaml` 中的 `versionCode` |
| 数据库或 Redis 连接失败 | 检查 `.env`、容器健康状态和 Compose 网络 |
| 邮箱验证码失败 | 检查 SMTP 环境变量、授权码和后端日志 |
