# FitLoop 当前发布状态

> 本页是截至 2026-09-07 的时间点快照。版本、提交、证书、服务健康和公网
> 产物都可能在后续操作中变化；再次发布或排障前必须重新核验，不能把本页
> 当作永久在线证明。

## 已验证的生产状态

| 项目 | 已验证值 |
| --- | --- |
| 服务器 Git 提交 | `020c6f70b7ec382d2240ae6c9e6900697b15703f` |
| 后端变更 | `fix(agent): persist appeal review decisions (#45)` |
| 数据库迁移 | Flyway V11 已应用；`appeal.review_note` 为 `text` |
| Android 版本 | `0.1.12+14` |
| APK SHA-256 | `d3fecaeb8840584fdad78da2395da3fc05ba6e016830ba358a2063491ccd6480` |
| APK 大小 | `73505254` 字节 |
| API 地址 | `https://43.139.72.25` |
| 签名模式 | `Compatibility` |
| 签名证书 SHA-256 | `69316bd8f5a1d79dad539415f88b3ecbaf43f3113831782e35499c0f55a47c2a` |
| 公网 APK | `https://43.139.72.25/apk/app-release.apk` |
| 公网元数据 | `https://43.139.72.25/apk/version.json` |

服务器上的受管 APK 指针已原子切换到状态
`states/20260907T113946Z-d3fecaeb8840-1782428-24872`，其
`current` 指向上述 `0.1.12+14` 哈希，`previous` 指向
`0e8a9ec481b15f36468ab75700d551d2959131a2e198124aacaa216b6ee448c5`
（`0.1.10+12`）。受管 release 目录为 `0555`，APK 为 `0444`。

激活后已核对公网 `version.json`、SHA-256、APK `Content-Length` 和 HTTPS
健康端点；Spring Boot、Agent Service、Campus Auth、MySQL、Redis 处于
healthy，Nginx 正常运行。管理员在真机上对一个
`WAITING_APPROVAL` 申诉只点击一次“人工确认执行”，确认不再误报
“登录状态已过期”，且申诉决策成功落库。

## 发布与恢复锚点

- 部署前数据库备份：
  `/root/backups/fitloop/fitloop_20260907_161149.sql.gz`
- 备份 SHA-256：
  `744586063d274c9469fbbede08add40e27abd6ed241aef2b30c173ab59c5db35`
- 后端回滚镜像：`fitloop-rollback/backend:3b63dd4-20260907-161149`
- APK 回滚信任锚：
  `0e8a9ec481b15f36468ab75700d551d2959131a2e198124aacaa216b6ee448c5`

这些值用于定位已核验的恢复对象，不授权自动回滚。数据库恢复、镜像切换、
APK 回滚和任何服务器写操作仍需单独批准并先复核现场状态。

## 验证证据边界

- Agent 申诉修复在合并前的准确源码树上通过 203 项后端单元测试、4 项
  Testcontainers 集成测试和全部 JaCoCo 门禁；0 失败、0 错误、0 跳过。
- 对应 PR #45 的 CI 已通过并合并，生产服务器随后更新到 squash 提交
  `020c6f70`。
- `0.1.12+14` 候选在激活前通过服务器 `--verify-only`，并完成真机覆盖安装
  与激活前冒烟；激活后公网产物校验通过。
- 上述结果只证明对应提交、产物和当次环境。它们不替代下一次改动的 CI、
  真机测试或部署检查。

## 仍存在的限制

- 当前 APK 使用兼容签名，尚未完成正式生产 keystore 的创建、离线备份和
  签名迁移；不能称为正式生产签名。
- 当前公开渠道是服务器 HTTPS 下载端点；尚未创建 Git tag、GitHub Release
  或应用商店发布记录。
- HTTP 兼容入口此前曾保持启用，但本快照没有在最新部署后重新验证其开关；
  关闭明文兼容必须单独检查旧客户端占比并取得授权。
- 本次验证不是数据库恢复演练，也不代表持续可用性、证书自动续期或所有
  Android 设备兼容性已经永久得到保证。

## 下一次发布前

1. 核对目标提交、干净工作树、数据库备份和恢复锚。
2. 运行当前 CI 等价门禁及相关真机清单，不复用本页的历史测试结果。
3. 对候选三件套执行 `deploy/install-apk.sh --verify-only`。
4. 分别取得服务器写入、APK 激活、回滚演练和外部发布授权。
5. 发布完成后更新本页的日期、提交、哈希、健康和回滚证据。
