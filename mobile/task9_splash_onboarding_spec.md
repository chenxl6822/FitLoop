# 任务 9：启动页 & 引导页 — Claude 执行规范

## 背景

FitLoop（Flutter/Android）当前直接从 `AuthGate` 进入登录或主界面，没有启动页/引导页。App 冷启动时有一段白屏等待期（Flutter 引擎初始化），需要加入品牌启动页来提升第一印象。

## 目标

1. **启动页**：App 冷启动时显示品牌 Logo + 渐入动画，持续 1.5s 后自然过渡
2. **引导页**：仅首次安装运行显示，3 页轮播介绍功能点，最后一页有"开始使用"按钮

## 无需后端改动，全部在 Flutter 端

---

## 步骤 1：创建新文件

### 1.1 `mobile/lib/splash_screen.dart` — 启动页

```dart
import 'package:flutter/material.dart';

/// 启动页
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key, required this.onComplete});
  final VoidCallback onComplete;

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _fadeAnim;
  late Animation<double> _scaleAnim;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
    _fadeAnim = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeIn),
    );
    _scaleAnim = Tween<double>(begin: 0.8, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOutBack),
    );
    _controller.forward();
    Future.delayed(const Duration(milliseconds: 1800), () {
      if (mounted) widget.onComplete();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.primary,
      body: Center(
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, child) => Opacity(
            opacity: _fadeAnim.value,
            child: Transform.scale(
              scale: _scaleAnim.value,
              child: child,
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Logo — 使用文字/icon 占位，后续可更换为资源图片
              Icon(
                Icons.directions_run,
                size: 80,
                color: Colors.white,
              ),
              const SizedBox(height: 16),
              Text(
                'FitLoop',
                style: Theme.of(context).textTheme.displayMedium?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '运动打卡 · 健康管理',
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  color: Colors.white70,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
```

**⚠️ 注意事项：**
- `Curves.easeOutBack` 会导致 Logo 先略微放大再弹回原位，不想弹跳可以改成 `Curves.easeOutCubic`
- 使用 `AnimatedBuilder` 而不是 `AnimatedWidget`，`AnimatedBuilder` 是标准做法、效率更高
- 启动页颜色取自主题色 `Theme.of(context).colorScheme.primary`（当前主题主色是 `#1F8A70`，墨绿）

### 1.2 `mobile/lib/onboarding_screen.dart` — 引导页

```dart
import 'package:flutter/material.dart';

/// 首次使用引导页（3 页轮播）
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key, required this.onComplete});
  final VoidCallback onComplete;

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  late PageController _pageController;
  int _currentPage = 0;

  final List<_OnboardingPage> _pages = const [
    _OnboardingPage(
      icon: Icons.directions_run,
      title: '运动打卡',
      description: '实时 GPS 记录运动轨迹，\n自动计算卡路里消耗',
    ),
    _OnboardingPage(
      icon: Icons.bar_chart,
      title: '数据统计',
      description: '查看每周运动趋势、\n体重变化曲线',
    ),
    _OnboardingPage(
      icon: Icons.people,
      title: '社交激励',
      description: '与好友PK排行榜、互相督促，\n让运动更有趣',
    ),
  ];

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _goNext() {
    if (_currentPage < _pages.length - 1) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    } else {
      widget.onComplete();
    }
  }

  @override
  Widget build(BuildContext context) {
    final isLast = _currentPage == _pages.length - 1;
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          children: [
            // 跳过按钮
            if (!isLast)
              Align(
                alignment: Alignment.topRight,
                child: TextButton(
                  onPressed: widget.onComplete,
                  child: const Text('跳过'),
                ),
              ),
            // 轮播页
            Expanded(
              child: PageView.builder(
                controller: _pageController,
                itemCount: _pages.length,
                onPageChanged: (i) => setState(() => _currentPage = i),
                itemBuilder: (context, index) {
                  final page = _pages[index];
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 40),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(page.icon, size: 100, color: const Color(0xFF1F8A70)),
                        const SizedBox(height: 32),
                        Text(
                          page.title,
                          style: Theme.of(context)
                              .textTheme
                              .headlineMedium
                              ?.copyWith(fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          page.description,
                          textAlign: TextAlign.center,
                          style: Theme.of(context)
                              .textTheme
                              .bodyLarge
                              ?.copyWith(color: Colors.grey[600]),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
            // 底部指示点 + 按钮
            Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                children: [
                  // 指示点
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(
                      _pages.length,
                      (i) => AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        margin: const EdgeInsets.symmetric(horizontal: 4),
                        width: _currentPage == i ? 24 : 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: _currentPage == i
                              ? const Color(0xFF1F8A70)
                              : Colors.grey[300],
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  // 按钮
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: ElevatedButton(
                      onPressed: _goNext,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF1F8A70),
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(24),
                        ),
                      ),
                      child: Text(isLast ? '开始使用' : '下一步'),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _OnboardingPage {
  const _OnboardingPage({
    required this.icon,
    required this.title,
    required this.description,
  });
  final IconData icon;
  final String title;
  final String description;
}
```

---

## 步骤 2：修改 main.dart

### 2.1 新增 import

```dart
import 'package:shared_preferences/shared_preferences.dart';
import 'splash_screen.dart';
import 'onboarding_screen.dart';
```

> `shared_preferences` 已经存在于 `pubspec.yaml` 中，不需要额外添加。

### 2.2 新增常量 key

在 `main()` 函数附近或文件顶部：

```dart
const _kOnboardingDoneKey = 'onboarding_done';
```

### 2.3 包装 home 入口

在 `MaterialApp` 的 `home` 参数处，将原本直接指向 `AuthGate(...)` 改为 `_AppEntry()`：

```dart
home: const _AppEntry(),
```

### 2.4 新建 `_AppEntry` widget（放置在任何合适位置，比如 `FitLoopApp` 类之前）

```dart
/// 应用入口：启动页 → 引导页（首次）→ AuthGate
class _AppEntry extends StatefulWidget {
  const _AppEntry();

  @override
  State<_AppEntry> createState() => _AppEntryState();
}

class _AppEntryState extends State<_AppEntry> {
  bool _showSplash = true;
  bool? _onboardingDone;

  @override
  void initState() {
    super.initState();
    _checkOnboarding();
  }

  Future<void> _checkOnboarding() async {
    final prefs = await SharedPreferences.getInstance();
    final done = prefs.getBool(_kOnboardingDoneKey) ?? false;
    if (mounted) setState(() => _onboardingDone = done);
  }

  void _onSplashDone() {
    if (mounted) setState(() => _showSplash = false);
  }

  void _onOnboardingDone() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kOnboardingDoneKey, true);
    if (mounted) setState(() => _onboardingDone = true);
  }

  @override
  Widget build(BuildContext context) {
    // 步骤 1：启动页
    if (_showSplash) {
      return SplashScreen(onComplete: _onSplashDone);
    }
    // 步骤 2：如果尚未确定引导状态，返回透明占位
    if (_onboardingDone == null) {
      return const SizedBox.shrink();
    }
    // 步骤 3：首次使用 → 引导页；否则 → AuthGate
    if (!_onboardingDone!) {
      return OnboardingScreen(onComplete: _onOnboardingDone);
    }
    // 这里需要能拿到 api/locationService/reminderScheduler/connectivityService
    // …见下方「参数传递」章节
    // 暂时先返回一个 Container，后续实际构建时数据从 FitLoopApp 往下传
    return const SizedBox.shrink();
  }
}
```

### 2.5 解决依赖注入问题

⚠️ **这里有一个架构难点**：`FitLoopApp` 通过构造函数接收 `FitLoopApi api`、`ConnectivityService` 等实例。`_AppEntry` 也需要它们，因为在引导页结束后要传参给 `AuthGate`。

**推荐方案 A（最简单，推荐）：** 把 `_AppEntry` 放到 `FitLoopApp.build()` 内部，作为 `home` 的 wrapper：

```dart
class FitLoopApp extends StatelessWidget {
  // 现有构造函数不变...

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'FitLoop',
      theme: ThemeData(...),
      home: _AppEntry(/* 把 api/connectivityService 等传进来 */),
    );
  }
}
```

修改 `_AppEntry` 使其接受依赖：

```dart
class _AppEntry extends StatefulWidget {
  const _AppEntry({
    required this.api,
    required this.locationService,
    required this.reminderScheduler,
    required this.connectivityService,
  });

  final FitLoopApi api;
  final LocationService locationService;
  final ReminderScheduler reminderScheduler;
  final ConnectivityService connectivityService;

  @override
  State<_AppEntry> createState() => _AppEntryState();
}
```

然后在引导页结束后的返回值中，构建 `AuthGate`：

```dart
// !_onboardingDone → 继续显示引导页
// _onboardingDone == true → 返回 AuthGate
return AuthGate(
  api: widget.api,
  locationService: widget.locationService,
  reminderScheduler: widget.reminderScheduler,
  connectivityService: widget.connectivityService,
);
```

方案 B：使用 `InheritedWidget` / Provider，涉及较大重构，不推荐。

---

## 步骤 3：验证

```bash
cd mobile
flutter analyze
flutter test
```

---

## 范围边界（不做的事）

- ❌ 不要删除或修改 `widget_test.dart` 中现有的 mock API 类 — 只在新 Widget 会破坏现有测试时按需添加 import
- ❌ 不要修改测试文件，除非现有 8 个 test 编译报错
- ❌ 不要添加第三方依赖（启动页/引导页全部用 Flutter 标准库 + Material 实现）
- ❌ 不要修改 `pubspec.yaml`
- ❌ 不要修改后端代码
- ❌ 不要改动 `AuthGate` 的构造函数签名

---

## 验收标准

| 条目 | 检查方式 |
|------|---------|
| 启动页亮屏显示品牌 Logo + 副标题 | 运行 App（模拟器/真机）|
| Logo 有渐入+缩放动画 | 观察启动过程 |
| 约 1.8s 后自动跳转 | 计时观察 |
| 首次安装显示 3 页引导 | 运行观察 |
| 引导页可滑动、指示点跟随 | 滑动测试 |
| 最后一页按钮文字为"开始使用" | 文字核对 |
| 点击"开始使用"后进入主界面 | 运行测试 |
| 重启 App 不再显示引导页（只显示启动页 → 主界面）| 关闭重启 |
| `flutter analyze` 0 issues | 命令 |
| `flutter test` 8/8 passed | 命令 |

---

## 项目结构变更

```
mobile/lib/
├── main.dart                    # 修改（home → _AppEntry wrapper）
├── splash_screen.dart           # 新增
├── onboarding_screen.dart       # 新增
├── api_client.dart              # 不变
├── connectivity_service.dart    # 不变
├── local_cache.dart             # 不变
├── reminder_scheduler.dart      # 不变
├── stats_charts.dart            # 不变
└── sync_queue.dart              # 不变
```
