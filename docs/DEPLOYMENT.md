# FitLoop 腾讯云部署指南

> 适用：腾讯云轻量应用服务器 (Ubuntu 22.04/24.04) · 2核4G · Docker 部署

---

## 目录

1. [服务器购买与初始化](#1-服务器购买与初始化)
2. [安装 Docker](#2-安装-docker)
3. [首次部署 FitLoop](#3-首次部署-fitloop)
4. [配置 HTTPS](#4-配置-https)
5. [配置 Flutter App](#5-配置-flutter-app)
6. [备份与监控](#6-备份与监控)
7. [常见问题](#7-常见问题)

---

## 1. 服务器购买与初始化

### 1.1 购买步骤

腾讯云 → 轻量应用服务器 → 新建：

| 字段 | 推荐值 | 说明 |
|------|--------|------|
| 镜像 | **Ubuntu 22.04** | 24.04 也可以 |
| 地域 | **广州** | 选离你最近的 |
| 套餐 | **2核4G 60GB SSD 200Mbps** | FitLoop 够用 |
| 登录方式 | **自动生成密码** | 或设置 SSH 密钥 |
| 购买时长 | **1个月 → 稳定后续费年付** | 首月试水 |

购买后 → 防火墙放行端口：
- `22` (SSH)
- `80` (HTTP)
- `443` (HTTPS) — 配域名时再开
- `3306`、`6379` → **不开**（Docker 内网访问）

### 1.2 SSH 登录

**Windows PowerShell：**
```powershell
ssh root@<你的服务器IP>
# 输入购买后收到的密码（第一次要求改密码）
```

**macOS / Linux Terminal：**
```bash
ssh root@<你的服务器IP>
```

> 💡 **小技巧：** 用 `ssh-copy-id` 配置密钥登录后就不需要每次都输密码了。

### 1.3 系统初始化

```bash
# 1. 更新系统
apt update && apt upgrade -y

# 2. 安装基础工具
apt install -y curl wget git htop net-tools unzip

# 3. 时区设置（重要：否则日志时间不对）
timedatectl set-timezone Asia/Shanghai
```

---

## 2. 安装 Docker

### 一键安装

```bash
curl -fsSL https://get.docker.com | sh
```

### 验证安装

```bash
docker --version
# 输出示例: Docker version 27.x.x

docker compose version
# 输出示例: Docker Compose version v2.x.x
```

> 海外服务器：安装无问题
> 国内服务器：可能出现 `get.docker.com` 下载慢，可改用：
> ```bash
> curl -fsSL https://get.docker.com | sed 's|https://download.docker.com|https://mirror.ccs.tencentyun.com/docker-ce|' | sh
> ```

### 配置国内镜像加速（国内服务器必做）

```bash
mkdir -p /etc/docker
cat > /etc/docker/daemon.json << 'EOF'
{
  "registry-mirrors": [
    "https://mirror.ccs.tencentyun.com",
    "https://docker.m.daocloud.io",
    "https://docker.1ms.run"
  ],
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "10m",
    "max-file": "3"
  }
}
EOF

systemctl restart docker
```

---

## 3. 首次部署 FitLoop

### 3.1 拉取代码

先在你的 Windows 本机推送最新代码：

```powershell
# Windows PowerShell
cd D:\AIWorkspace\projects\FitLoop
git push origin main
```

然后在服务器上拉取：

```bash
cd /root
git clone https://github.com/<你的GitHub用户名>/FitLoop.git
cd FitLoop
```

> **国内服务器 git clone 慢？** 用镜像：
> ```bash
> git clone https://gitclone.com/github.com/<你的用户名>/FitLoop.git
> ```

### 3.2 配置环境变量

```bash
# 生成密钥（需要 openssl，一般已安装）
bash deploy/gen-secrets.sh

# 复制输出结果，然后创建 .env 文件
nano .env
```

`.env` 文件内容（用上面生成的密钥替换 `***`）：

```ini
MYSQL_DATABASE=fitloop
MYSQL_USER=fitloop
MYSQL_PASSWORD=***           ← 来自 gen-secrets.sh
MYSQL_ROOT_PASSWORD=***      ← 来自 gen-secrets.sh
FITLOOP_JWT_SECRET=***       ← 来自 gen-secrets.sh
FITLOOP_ADMIN_KEY=***        ← 来自 gen-secrets.sh
SERVER_PORT=8080
```

> ⚠️ **安全提示：** 生产环境 `.env` 文件不要提交到 Git！`.gitignore` 已排除，确认：
> ```bash
> git status .env
> # 应显示 "nothing to commit" 或未跟踪
> ```

### 3.3 启动服务

**国内服务器（使用 Daocloud 镜像加速）：**

```bash
bash deploy/deploy.sh cn
```

**海外服务器（默认 Docker Hub）：**

```bash
bash deploy/deploy.sh
```

### 3.4 验证部署

```bash
# 查看所有容器状态
docker ps

# 输出应该类似：
# CONTAINER ID   IMAGE              STATUS         PORTS
# abc1234        fitloop-backend    Up 10 minutes  0.0.0.0:8080->8080
# def5678        mysql:8.0          Up 10 minutes  0.0.0.0:3306->3306
# ghi9012        redis:6.2-alpine   Up 10 minutes  0.0.0.0:6379->6379
# jkl3456        nginx:1.27-alpine  Up 10 minutes  0.0.0.0:80->80

# 测试 API
curl http://localhost:8080/actuator/health
# 期望输出: {"status":"UP"}

# 测试登录接口
curl -X POST http://localhost/api/auth/login \
  -H "Content-Type: application/json" \
  -d '{"phone":"13800138000","password":"test1234"}'
```

### 3.5 查看日志

```bash
# 查看所有服务日志
docker compose -f deploy/docker-compose.yml logs -f

# 只看后端日志
docker logs fitloop-backend -f

# 只看数据库日志
docker logs fitloop-mysql -f
```

### 3.6 停止/重启

```bash
# 停止所有服务
docker compose -f deploy/docker-compose.yml down

# 重启所有服务
docker compose -f deploy/docker-compose.yml restart

# 单独重启后端（热更新代码后）
docker compose -f deploy/docker-compose.yml restart backend
```

---

## 4. 配置 HTTPS

> ⚠️ **为什么必须做？** JWT token + 用户健康数据是敏感信息，HTTP 明文传输极不安全。

### 4.1 准备工作

你需要：
1. **一个域名**（推荐 `fitloop.cn` 或 `fitloop.yourname.cn`）
2. **域名 DNS 解析**指向服务器 IP

### 4.2 安装 Certbot（腾讯云上）

```bash
apt install -y nginx certbot python3-certbot-nginx
```

停掉 Docker Nginx（避免端口冲突）：

```bash
docker stop fitloop-nginx
docker rm fitloop-nginx
```

### 4.3 申请 SSL 证书

```bash
certbot --nginx -d your-domain.cn
```

> 交互式引导，按要求填写邮箱 + 同意协议即可。
> 证书有效期 90 天，certbot 会自动续期。

### 4.4 配置反向代理

编辑 Nginx 配置：

```bash
nano /etc/nginx/sites-available/fitloop
```

粘贴以下内容（替换 `your-domain.cn` 和证书路径）：

```nginx
server {
    listen 443 ssl http2;
    server_name your-domain.cn;

    ssl_certificate /etc/letsencrypt/live/your-domain.cn/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/your-domain.cn/privkey.pem;
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers HIGH:!aNULL:!MD5;

    # 头像上传目录（在宿主机上）
    location /uploads/ {
        alias /root/FitLoop/uploads/;
        expires 30d;
        add_header Cache-Control "public, immutable";
    }

    # API 反向代理到 Docker 后端
    location /api/ {
        proxy_pass http://localhost:8080/api/;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }

    # 健康检查
    location /actuator/health {
        proxy_pass http://localhost:8080/actuator/health;
    }

    access_log /var/log/nginx/fitloop-access.log;
    error_log /var/log/nginx/fitloop-error.log;
}

# HTTP → HTTPS 重定向
server {
    listen 80;
    server_name your-domain.cn;
    return 301 https://$host$request_uri;
}
```

启用配置并测试：

```bash
ln -s /etc/nginx/sites-available/fitloop /etc/nginx/sites-enabled/
nginx -t
systemctl reload nginx
```

### 4.5 验证 HTTPS

```bash
curl https://your-domain.cn/api/auth/health
# 应返回正常，且不会出现证书警告
```

---

## 5. 配置 Flutter App

### 5.1 修改 API 地址

打开 `mobile/lib/api_client.dart`，找到：

```dart
static const String baseUrl = 'http://10.0.2.2:8080/api';
```

改为：

```dart
static const String baseUrl = 'https://your-domain.cn/api';
```

### 5.2 重新构建 APK

```bash
cd D:\AIWorkspace\projects\FitLoop
powershell -ExecutionPolicy Bypass -File deploy/build-apk.ps1 -ApiBaseUrl http://43.139.72.25
```

APK 文件在 `mobile/build/app/outputs/flutter-apk/app-release.apk`

> 如果你本机没有 Flutter 环境，也可以在服务器的 Docker 里构建，但建议在本机构建（更快）。

---

## 6. 备份与监控

### 6.1 配置数据库自动备份

```bash
# 测试备份脚本
bash deploy/backup.sh

# 添加到 crontab（每天凌晨3点自动备份）
crontab -e
```

在 crontab 中添加：

```cron
# 每天凌晨 3:00 备份数据库
0 3 * * * /root/FitLoop/deploy/backup.sh >> /var/log/fitloop-backup.log 2>&1

# 每天上午 9:00 健康检查（超过阈值会告警）
0 9 * * * /root/FitLoop/deploy/monitor.sh --alert >> /var/log/fitloop-monitor.log 2>&1
```

备份文件位置：`/root/backups/fitloop/`（保留最近 7 天）

### 6.2 手动健康检查

```bash
bash deploy/monitor.sh
```

输出示例：
```
═══════════════════════════════════════════
  FitLoop 服务器健康检查 - 2026-05-30
═══════════════════════════════════════════
CPU 使用率:           12.5%
内存:                 1523MB / 3950MB (38.6%)
磁盘:                 8.5G / 58G (15%)

--- Docker 容器 ---
  fitloop-mysql:      ✅ Up 7 minutes
  fitloop-redis:      ✅ Up 7 minutes
  fitloop-backend:    ✅ Up 5 minutes
  fitloop-nginx:      ✅ Up 5 minutes

--- API 健康 ---
  端口 8080:          ✅ 响应 200
  端口 80:            ✅ 响应 200

--- 系统负载 ---
系统负载:             0.15, 0.08, 0.06 (核心数: 2)
═══════════════════════════════════════════
```

### 6.3 更新代码

当你在本地修改了代码并推送后，在服务器上执行：

```bash
cd /root/FitLoop
git pull
bash deploy/deploy.sh cn
```

`deploy.sh` 会自动：
1. 拉取最新代码
2. 重新构建 Docker 镜像
3. 滚动重启容器
4. 等待后端就绪

---

## 7. 日常运维速查

```bash
# 查看服务状态
docker ps

# 查看实时日志
docker logs fitloop-backend -f --tail 100

# 重启所有服务
cd /root/FitLoop && docker compose -f deploy/docker-compose.yml restart

# 完整重新部署
cd /root/FitLoop && git pull && bash deploy/deploy.sh cn

# 查看数据库数据量
docker exec fitloop-mysql mysql -uroot -p"$MYSQL_ROOT_PASSWORD" -e "SELECT COUNT(*) FROM fitloop.sport_session;"

# 查看备份文件
ls -lh /root/backups/fitloop/

# 检查磁盘空间
df -h

# 查看内存占用
free -h
```

---

## 附录：目录结构说明

```
/root/FitLoop/
├── deploy/
│   ├── .env.example        # 环境变量模板
│   ├── .env.production     # ⚠️ 生产环境配置（需手动修改）
│   ├── gen-secrets.sh      # 🔒 密钥生成器
│   ├── docker-compose.yml  # Docker Compose 主文件
│   ├── docker-compose.cn.yml      # 国内镜像版
│   ├── docker-compose.prebuilt.yml # 预构建版
│   ├── docker-compose.host.yml    # Docker Desktop 版
│   ├── nginx.conf          # Docker Nginx 配置（HTTP）
│   ├── nginx.ssl.conf      # SSL 反代配置（备用）
│   ├── nginx.host.conf     # Docker Desktop Nginx 配置
│   ├── deploy.sh           # 🚀 一键部署脚本
│   ├── backup.sh           # 💾 数据库备份脚本
│   └── monitor.sh          # 📊 健康监控脚本
├── backend/
│   ├── Dockerfile          # 多阶段构建
│   ├── Dockerfile.runtime  # 运行时镜像（需先 mvn package）
│   └── src/                # Java 源代码
├── mobile/                 # Flutter 前端
├── docs/                   # 文档
└── .env                    # ⚠️ 实际环境变量（已 gitignore）
```

---

## 快速翻墙：首次部署命令速查

从零到跑起来，5 分钟速查：

```bash
# 1. SSH 登录
ssh root@<服务器IP>

# 2. 装 Docker
curl -fsSL https://get.docker.com | sh

# 3. 拉代码
git clone https://github.com/<你>/FitLoop.git && cd FitLoop

# 4. 配密钥
bash deploy/gen-secrets.sh
nano .env   # 粘贴生成的密钥

# 5. 启动
bash deploy/deploy.sh cn

# 6. 验证
curl localhost:8080/actuator/health
```

---

> **有问题？** 查看日志 `docker logs fitloop-backend -f` 或直接问我。
