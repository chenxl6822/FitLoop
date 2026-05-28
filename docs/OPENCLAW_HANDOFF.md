# FitLoop OpenClaw 交接文档

## 当前状态

仓库：`D:\AIWorkspace\projects\FitLoop`

分支：`feature/charts`

本次提交目标：实现移动端统计图表、本地提醒通知，并同步项目文档状态。

## 本次已完成

- 移动端统计页新增三类图表：
  - 本周运动次数柱状图
  - 里程 / 热量趋势折线图
  - 体重趋势折线图
- 图表使用 `fl_chart`，当前后端没有历史统计接口，所以 MVP 先基于 `/api/stat/sport` 的汇总数据生成周内分布示意。
- 体重趋势来自本次运行中用户录入的健康数据；没有体重数据时显示“暂无趋势数据”。
- 移动端提醒设置保存后会同步注册或取消本地每日通知。
- 本地通知使用 `flutter_local_notifications` 和 `timezone`。
- Android 已补充：
  - `POST_NOTIFICATIONS`
  - `RECEIVE_BOOT_COMPLETED`
  - 本地通知 scheduled receiver
  - boot receiver
  - core library desugaring
- 工程整理：
  - `mobile/lib/stats_charts.dart`：统计图表组件
  - `mobile/lib/reminder_scheduler.dart`：本地通知调度服务
- 文档同步：
  - `README.md` 更新已实现功能
  - `PLAN.md` 更新任务 3/4/5/6/7 的真实进度

## 关键文件

- `mobile/lib/main.dart`
  - 注入 `ReminderScheduler`
  - 统计页引用图表组件
  - 健康数据录入后更新体重趋势
  - 提醒保存后调用本地通知调度
- `mobile/lib/stats_charts.dart`
  - `WorkoutCountChartCard`
  - `DistanceCalorieChartCard`
  - `WeightTrendChartCard`
- `mobile/lib/reminder_scheduler.dart`
  - `ReminderScheduler`
  - `LocalReminderScheduler`
- `mobile/pubspec.yaml`
  - 新增 `fl_chart`
  - 新增 `flutter_local_notifications`
  - 新增 `timezone`
- `mobile/android/app/src/main/AndroidManifest.xml`
  - 通知权限与通知 receiver
- `mobile/android/app/build.gradle.kts`
  - 启用 desugaring
- `mobile/test/widget_test.dart`
  - 增加统计页图表和体重趋势空状态测试断言

## 推荐测试步骤

在 PowerShell 中运行：

```powershell
cd "D:\AIWorkspace\projects\FitLoop\mobile"
flutter pub get
flutter analyze
flutter test
```

如果要测试 Android 真机或模拟器：

```powershell
cd "D:\AIWorkspace\projects\FitLoop\mobile"
flutter run
```

手工验收路径：

1. 登录 App。
2. 进入“统计”页。
3. 确认能看到：
   - “本周运动次数”
   - “里程 / 热量趋势”
   - “体重趋势”
4. 在“统计”页点击“记录健康数据”。
5. 输入体重，例如 `62.5`，保存。
6. 确认“最近健康记录”出现，体重趋势不再显示“暂无趋势数据”。
7. 进入“我的”页。
8. 打开任意提醒，例如运动/喝水提醒。
9. 开启提醒并保存。
10. Android 13+ 首次保存时应触发通知权限请求；保存成功后系统会注册每日通知。

## 当前验证结果

已通过：

```powershell
git diff --check
```

用户本机已确认：

```powershell
flutter pub get
```

可以正常完成并更新依赖。

用户本机首次运行 `flutter analyze` 发现 3 个 info：

- `sort_child_properties_last`
- 2 处 `withOpacity` deprecated

这些已经在当前工作区修复：

- `DistanceCalorieChartCard` 的 `child` 参数已移到最后。
- `withOpacity(0.4)` 已替换为 `withValues(alpha: 0.4)`。

用户本机首次运行 `flutter test` 发现统计页测试找不到“里程 / 热量趋势”。原因是该图表位于 `ListView` 下方，测试没有滚动到对应子项。当前工作区已修复测试：

- 通过 `tester.scrollUntilVisible` 滚动到“里程 / 热量趋势”和“体重趋势”后再断言。
- 保存健康数据后再次滚动到“体重趋势”，确认空状态消失。

Codex 沙箱中仍未能完成：

```powershell
flutter analyze
flutter test
dart --version
flutter --version
```

原因：当前 Codex 环境中 Flutter/Dart 命令会长时间卡住并超时，甚至 `dart --version` 和 `flutter --version` 也无法正常返回。

OpenClaw 接手后应优先在正常本机 Flutter 环境重新运行：

```powershell
cd "D:\AIWorkspace\projects\FitLoop\mobile"
flutter analyze
flutter test
```

## 后续建议

1. 优先修复或确认本机 Flutter SDK 卡住问题，然后跑完整移动端测试。
2. 如果图表需要真实历史趋势，后端新增历史统计接口，而不是继续用汇总数据推导。
3. 本地通知建议真机验证，尤其是 Android 13+ 权限弹窗和重启后的通知恢复。
4. 后续再继续拆分 `main.dart`，建议按页面逐步拆，不要和功能改动混在一个提交里。
5. 仍未完成的产品项：
   - 目标/统计离线缓存
   - 断网打卡同步队列
   - 头像上传
   - 启动页/引导页
