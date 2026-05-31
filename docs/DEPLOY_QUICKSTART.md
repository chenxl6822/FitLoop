--------------------------3442b41d4d3b4455
Content-Disposition: form-data; name="text"

# FitLoop 腾讯云部署速查

> **服务器：** Ubuntu 24.04 LTS · 2核4G · 5Mbps · CVM
> **预估耗时：** 首次 20-30 分钟 · 后续更新 1 分钟

---

## 第 1 步：初始化服务器

```bash
# SSH 登录
ssh root@<你的服务器IP>

# 1.1 更新系统
apt update && apt upgrade -y

# 1.2 安装基础工具
apt install -y curl wget git htop

# 1.3 设置时区
timedatectl set-timezone Asia/Shanghai

# 1.4 防火墙放行端口（如果是腾讯云自带的 ufw）
ufw allow 22/tcp
ufw allow 80/tcp
ufw allow 8080/tcp
ufw --force enable
```

---

## 第 2 步：安装 Docker

```bash
# 一键安装
curl -fsSL https://get.docker.com | sh

# 验证
docker --version    # 应显示 Docker 26.x
docker compose version

# 配置国内镜像加速（不配的话拉 MySQL 镜像很慢）
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

## 第 3 步：拉取代码

```bash
cd /root

# GitHub 国内加速拉取
git clone https://gh-proxy.com/https://github.com/chenxl6822/FitLoop.git
# 或者直连（如果网络好）:
# git clone https://github.com/chenxl6822/FitLoop.git

cd FitLoop

# 切换到 main 分支
git checkout main
```

---

## 第 4 步：配置密钥

```bash
# 生成 JWT 密钥和数据库密码
bash deploy/gen-secrets.sh

# 会输出类似:
# FITLOOP_JWT_SECRET=***
# MYSQL_PASSWORD=***
# MYSQL_ROOT_PASSWORD=***
# FITLOOP_ADMIN_KEY=***

# 创建 .env 文件
cp deploy/.env.production .env

# 编辑 .env，把上面生成的值填进去
nano .env
```

`.env` 文件内容如下，只需把 `***` 替换成上面生成的值：

```
MYSQL_DATABASE=fitloop
MYSQL_USER=fitloop
MYSQL_PASSWORD=<gen-secrets.sh 生成的值>
MYSQL_ROOT_PASSWORD=<gen-secrets.sh 生成的值>
SERVER_PORT=8080
FITLOOP_JWT_SECRET=<gen-secrets.sh 生成的值>
FITLOOP_ADMIN_KEY=<gen-secrets.sh 生成的值>
FITLOOP_JWT_TTL_SECONDS=604800
```

---

## 第 5 步：一键启动

```bash
# 国内服务器，用 DaoCloud 镜像加速
bash deploy/deploy.sh cn
```

这个命令会自动：
1. 构建 Docker 镜像（Maven 编译 Java → 打包 JAR → 生成镜像）
2. 启动 MySQL + Redis + Spring Boot + Nginx
3. 等待后端就绪

**首次构建耗时：** 2核4G 上约 3-5 分钟（Maven 下载依赖较慢，后续更新只需几秒）

---

## 第 6 步：验证

```bash
# 1. 检查容器全部在运行
docker ps

# 应该看到 4 个容器：
# fitloop-mysql    Up (healthy)
# fitloop-redis    Up (healthy)
# fitloop-backend  Up (healthy)
# fitloop-nginx    Up (healthy)

# 2. 测试 API
curl http://localhost:8080/actuator/health

# 返回: {"status":"UP"}  表示成功！

# 3. 通过 Nginx 访问
curl http://localhost/api/actuator/health

# 4. 查看日志（可选）
docker compose -f deploy/docker-compose.yml logs -f backend
```

---

## 第 7 步：让 App 连接服务器

编辑 Flutter 项目中的 `mobile/lib/api_client.dart`，找到：

```dart
static const String baseUrl = 'http://10.0.2.2:8080/api';
```

改为你的服务器 IP：

```dart
static const String baseUrl = 'http://<你的服务器IP>/api';
```

然后重新打包 APK：

```bash
cd D:\AIWorkspace\projects\FitLoop
powershell -ExecutionPolicy Bypass -File deploy/build-apk.ps1 -ApiBaseUrl http://43.139.72.25
```

APK 位置：`mobile/build/app/outputs/flutter-apk/app-release.apk`

---

## 日常维护

```bash
# 查看容器状态
docker ps

# 查看后端日志
docker logs fitloop-backend -f --tail 50

# 查看数据库日志
docker logs fitloop-mysql -f --tail 50

# 健康检查
bash deploy/monitor.sh

# 数据库备份
bash deploy/backup.sh
# 备份文件在 /root/backups/fitloop/

# 更新代码后重新部署
cd /root/FitLoop && git pull && bash deploy/deploy.sh cn
```

---

## 配置 crontab（自动备份 + 监控）

```bash
crontab -e
```

粘贴：

```cron
# 每天凌晨 3:00 备份数据库
0 3 * * * /root/FitLoop/deploy/backup.sh >> /var/log/fitloop-backup.log 2>&1

# 每天上午 9:00 健康检查
0 9 * * * /root/FitLoop/deploy/monitor.sh >> /var/log/fitloop-monitor.log 2>&1
```

---

## 有域名后配置 HTTPS

当你有域名并备案完成后：

```bash
# 安装 Nginx + Certbot
apt install -y nginx certbot python3-certbot-nginx

# 申请 SSL 证书
certbot --nginx -d your-domain.cn

# 编辑 Nginx 配置
# 参考 deploy/nginx.ssl.conf 中的 SSL 配置块
```

---

## 端口速查

| 端口 | 用途 | 是否开放 |
|------|------|---------|
| 22 | SSH | ✅ 必须 |
| 80 | HTTP（Nginx） | ✅ 必须 |
| 443 | HTTPS | ❌ 有域名再开 |
| 8080 | Spring Boot（Docker 内） | ❌ 不开，走 Nginx 代理 |
| 3306 | MySQL（Docker 内） | ❌ 不开 |
| 6379 | Redis（Docker 内） | ❌ 不开 |

---

## 常见问题

**Q: git clone 太慢怎么办？**
```bash
# 用 GH Proxy 镜像
git clone https://gh-proxy.com/https://github.com/chenxl6822/FitLoop.git
```

**Q: Docker pull 镜像慢？**
→ 第 2 步已配好国内镜像加速，如果还慢：
```bash
# 手工拉取
docker pull docker.m.daocloud.io/library/mysql:8.0
docker tag docker.m.daocloud.io/library/mysql:8.0 mysql:8.0
```

**Q: 启动后 curl 连不上？**
```bash
# 检查防火墙
ufw status

# 先关掉防火墙测试
ufw disable
curl http://localhost:8080/actuator/health
# 如果能通，说明是防火墙问题，重新配置 ufw
ufw --force enable
ufw allow 22,80,8080/tcp
```

**Q: 部署脚本报错 "Docker Compose 未安装"？**
```bash
# Ubuntu 24.04 可能用 docker compose（空格）不是 docker-compose（横杠）
# 脚本会自动检测，如果还不行：
apt install -y docker-compose-plugin
```

---

> **搞定！** 有问题随时问我。

--------------------------3442b41d4d3b4455--
