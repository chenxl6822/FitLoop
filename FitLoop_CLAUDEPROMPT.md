--------------------------dacf844693e66f45
Content-Disposition: form-data; name="file"; filename="FitLoop_CLAUDEPROMPT.md"
Content-Type: application/octet-stream

# FitLoop — Claude 实施提示文档（Sprint A 内测稳定版）

> 发送给 Claude Desktop 或任何 Cline/Aider 等 AI 编码工具。本文档聚焦 **Sprint A** 优先任务。

---

## 📋 任务概述

FitLoop 是一个校园运动打卡与健康管理应用（Flutter + Spring Boot）。已完成阶段 1（4种打卡+5种运动类型+验证码系统），当前处于**部署上线前的稳定化阶段**。

**当前 HEAD**：`3c3c654`（分支 `main`，已全部推送 origin）

本期 Sprint A 目标是：**将项目从"本地能跑"推进到"10分钟内测闭环"**。

---

## 🚨 优先级 P0（阻塞内测）

### 1. 补齐 `GET /api/user/profile`

- **问题**：移动端调用 `GET /api/user/profile`，但后端无对应 Controller
- **后端文件**：需要新增 Controller 方法或确认返回的 JSON 结构
- **预期响应**：
  ```json
  {
    "code": 200,
    "data": {
      "id": 1,
      "phone": "138****1234",
      "nickname": "小明",
      "avatar": "/uploads/avatars/xxx.jpg",
      "createdAt": "2026-05-30T10:00:00"
    }
  }
  ```
- **需要**：新增 Java Controller 方法 + Controller 测试

### 2. Nginx 增加 `/uploads/` 代理

- **文件**：`deploy/nginx.conf` 和 `deploy/nginx.ssl.conf`
- **当前**：只代理 `/api/` 和 `/actuator/health`
- **需要增加**：
  ```nginx
  location /uploads/ {
      proxy_pass http://backend:8080/uploads/;
      proxy_set_header Host $host;
      proxy_set_header X-Real-IP $remote_addr;
      expires 7d;
      add_header Cache-Control "public, immutable";
  }
  ```

### 3. Docker 上传 volume

- **文件**：`deploy/docker-compose.yml`
- **需要增加**：
  ```yaml
  services:
    backend:
      volumes:
        - uploads_data:/app/uploads
  volumes:
    uploads_data:
  ```
- **同时**：在 backend 的 `application.yml` 中配置上传路径为 `/app/uploads`

### 4. 端口安全

- Docker Compose 的 MySQL(`3306`) 和 Redis(`6379`) 不应暴露到宿主机公网
- `docker-compose.yml` 中确认 MySQL/Redis 的 ports 改为仅 `127.0.0.1:3306:3306` 或不暴露
- 后端 `8080` 只用于 Docker 内网，由 Nginx 反代

---

## 🟡 优先级 P1（质量保障）

### 5. 真机冒烟测试清单

生成一份测试清单并手动验证：

| # | 测试项 | 预期结果 |
|---|---|---|
| 1 | 下载 APK 安装 | 安装成功 |
| 2 | 注册新账号（测试验证码） | 注册成功，自动登录 |
| 3 | 退出 → 重新打开 | 回到登录页 |
| 4 | GPS 运动打卡 | Session 记录成功 |
| 5 | 拍照打卡 | 图片上传成功 |
| 6 | 头像上传 | 头像显示更新 |
| 7 | 手动打卡 | 数据保存成功 |
| 8 | 设置 → 退出 | 退出登录成功 |

### 6. 文档同步

- `STATUS.md`：更新为 `HEAD: 3c3c654`，标注阶段 1 ✅/阶段 2 🚀
- `README.md`：更新提交数、测试状态、安装步骤
- 删除不再需要的 `docs/CLAUDE_CONTEXT.md` etc（如之前已清理的）

### 7. 下载页补充

- `deploy/apk/app-release.apk` 放入真实 APK（如已构建）
- 下载页 `deploy/html/download.html` 自动显示版本号

---

## 🔧 技术约束（Don't Break）

1. **无状态管理框架** — 不用 Provider/Riverpod/GetX，纯 setState + 构造注入
2. **所有页面在 main.dart** — 暂时不拆分（Sprint E 再做），本次只修 bug
3. **dart:io HttpClient** — 除 uploadAvatar 用 `http.MultipartRequest` 外，都用 `_get()/_post()` 封装
4. **后端 @DataJpaTest 不用 @SpringBootTest** — 不需要 MySQL，用 H2 内存数据库
5. **禁止修改的稳定模块：** `api_client.dart` models / `local_cache.dart` / `connectivity_service.dart` / `sync_queue.dart` / `stats_charts.dart` / `reminder_scheduler.dart`

---

## ✅ 完成验收标准

本次 Sprint 完成后应满足：

- [ ] 新用户从下载页安装 APK → 10 分钟内可完成注册→登录→一次打卡→看统计
- [ ] 退出登录后重新打开 App → 回到登录页
- [ ] 头像和拍照打卡图片在公网可访问（`/uploads/` 通）
- [ ] `mvn test` 全部通过（后端 11+ 个测试文件）
- [ ] `flutter analyze` + `flutter test` 全部通过
- [ ] Docker 部署后端口安全（仅 80/443 暴露）
- [ ] 无提交私密配置/API Key/个人路径

---

## 📂 重要文件路径

| 文件 | 路径 |
|---|---|
| 后端 Controller | `backend/src/main/java/com/fitloop/...` |
| Nginx 配置 | `deploy/nginx.conf`, `deploy/nginx.ssl.conf` |
| Docker Compose | `deploy/docker-compose.yml` |
| Flutter main.dart | `mobile/lib/main.dart` |
| Flutter API client | `mobile/lib/api_client.dart` |
| CI 配置 | `.github/workflows/ci.yml` |
| 下载页 | `deploy/html/download.html` |
| 部署文档 | `docs/DEPLOY_QUICKSTART.md` |
| 当前状态 | `STATUS.md` |
| 完整开发计划 | `PROJECT_PLAN_v2.md` |

## 📝 提交规范

```
格式: feat(scope): 简短描述 (scope: mobile/backend/deploy)
提交前: flutter analyze && flutter test（前端）或 mvn test（后端）
每 Sprint 完成: git push
```

--------------------------dacf844693e66f45--
