--------------------------570afb4ecf6aa0a2
Content-Disposition: form-data; name="text"

# FitLoop 腾讯云部署 — GPT 教学版

> **说明：** 把本文档发给任意 AI（ChatGPT/DeepSeek 等），让 AI 一步步带你操作。
> **用户服务器：** 43.139.72.25 · Ubuntu 24.04 · 2核4G
> **操作方法：** 全部在腾讯云网页控制台的 Web 终端里执行，不需要装任何软件

---

## 准备工作

打开浏览器：
1. 登录腾讯云官网 https://console.cloud.tencent.com
2. 进入「控制台」→「云服务器」→「实例列表」
3. 找到 IP 为 `43.139.72.25` 的服务器
4. 点击右侧「登录」按钮 → 在弹出的 Web 终端中输入账号 `root` 和密码
5. 看到 `root@...:~#` 提示符，说明已连接到服务器

**提示 AI：** 告诉 AI "我已连接到服务器，接下来怎么做？"

以下是 AI 可以按照顺序执行的步骤（AI 每次说一句，用户复制执行）：

---

## Step 1: 更新系统

```bash
apt update && apt upgrade -y
```
> 等待 1-2 分钟完成

## Step 2: 安装基础工具

```bash
apt install -y curl wget git htop
```

## Step 3: 设置时区

```bash
timedatectl set-timezone Asia/Shanghai
```

## Step 4: 安装 Docker

```bash
curl -fsSL https://get.docker.com | sh
```

验证安装：
```bash
docker --version
docker compose version
```

## Step 5: 配置 Docker 国内镜像加速

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

## Step 6: 拉取 FitLoop 代码

```bash
cd /root
git clone https://gh-proxy.com/https://github.com/chenxl6822/FitLoop.git
cd FitLoop
git checkout main
```

> 如果这个镜像地址太慢，告诉 AI，它会给你替代方案

## Step 7: 生成密钥

```bash
bash deploy/gen-secrets.sh
```

> 会输出 4 行，每行一个 KEY=值。告诉 AI 输出结果，AI 会帮你确认。

## Step 8: 创建配置文件

```bash
cp deploy/.env.production .env
nano .env
```

> 此时会进入编辑器。AI 会告诉你具体怎么操作（按方向键移动，修改 `***` 为第 7 步生成的值）

**nano 编辑器使用说明：**
- 方向键移动光标
- 修改 `***` 为实际密钥值
- `Ctrl+X` → `Y` → `Enter` 保存退出

## Step 9: 一键部署

```bash
bash deploy/deploy.sh cn
```

> 首次部署约 3-5 分钟（Maven 下载 Java 依赖 + 构建 Docker 镜像）
> 等待期间把输出内容复制给 AI，AI 会告诉你是否正常

## Step 10: 验证

```bash
docker ps
```

应看到 4 个容器都在运行：
- fitloop-mysql (Up)
- fitloop-redis (Up)
- fitloop-backend (Up)
- fitloop-nginx (Up)

```bash
curl http://localhost:8080/actuator/health
```

应返回：`{"status":"UP"}`

## Step 11: 使用

你的 Flutter App 修改 `api_client.dart` 中的地址为：

```dart
static const String baseUrl = 'http://43.139.72.25/api';
```

重新打包 APK 即可连接。

---

## 日常维护命令（以后用）

```bash
# 查看运行状态
docker ps

# 看后端日志
docker logs fitloop-backend -f --tail 50

# 重新部署（代码更新后）
cd /root/FitLoop && git pull && bash deploy/deploy.sh cn

# 备份数据库
bash deploy/backup.sh

# 健康检查
bash deploy/monitor.sh
```

---

## 如果卡住了

把终端里的**报错信息截图或复制**发给 AI，描述你执行到哪一步了，AI 会帮你解决。

---

> **准备好了？** 把这份文档发给你的 AI 助手，告诉它："开始教我部署 FitLoop，我已连接服务器"。

--------------------------570afb4ecf6aa0a2--
