import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';
import 'package:pedometer/pedometer.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api_client.dart';
import 'fitloop_assets.dart';
import 'onboarding_screen.dart';
import 'reminder_scheduler.dart';
import 'splash_screen.dart';
import 'stats_charts.dart';
import 'sync_queue.dart';

const _kOnboardingDoneKey = 'onboarding_done';

const _sportTypes = {
  'running': '跑步',
  'cycling': '骑行',
  'walking': '健走',
  'rope_skipping': '跳绳',
  'custom': '自定义',
};

/// 将各类异常转换为用户可读的错误消息
String friendlyErrorMsg(dynamic error) {
  final msg = error.toString();
  // 网络连接类错误
  if (msg.contains('SocketException') ||
      msg.contains('Connection refused') ||
      msg.contains('Connection failed') ||
      msg.contains('Connection reset') ||
      msg.contains('Network is unreachable') ||
      msg.contains('No route to host') ||
      msg.contains('Software caused connection abort') ||
      msg.contains('Operation not permitted')) {
    return '服务器连接失败，请检查网络或稍后重试';
  }
  // 超时类
  if (msg.contains('Timeout') ||
      msg.contains('timed out') ||
      msg.contains('Time out')) {
    return '请求超时，请检查网络后重试';
  }
  // DNS 解析失败
  if (msg.contains('No address associated with hostname') ||
      msg.contains('nodename nor servname') ||
      msg.contains('Service not available')) {
    return '无法解析服务器地址，请检查网络配置';
  }
  // TLS/证书错误
  if (msg.contains('TLS') || msg.contains('SSL') || msg.contains('Certificate')) {
    return '安全连接失败，请稍后重试';
  }
  // 认证相关（非网络）
  if (msg.contains('401') || msg.contains('403')) {
    return '登录状态已过期，请重新登录';
  }
  if (msg.contains('500')) {
    return '服务器开小差了，请稍后重试';
  }
  // 去除 ApiException: 前缀，展示后端返回的原始消息
  if (msg.startsWith('ApiException: ')) {
    return msg.substring(14);
  }
  return msg;
}

void main() {
  runApp(FitLoopApp());
}

class FitLoopApp extends StatelessWidget {
  FitLoopApp({
    super.key,
    FitLoopApi? api,
    LocationService? locationService,
    ReminderScheduler? reminderScheduler,
  })  : api = api ?? const _ApiFactory().create(),
        locationService = locationService ?? GeolocatorLocationService(),
        reminderScheduler = reminderScheduler ?? LocalReminderScheduler();

  final FitLoopApi api;
  final LocationService locationService;
  final ReminderScheduler reminderScheduler;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'FitLoop',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF1F8A70)),
        useMaterial3: true,
      ),
      home: _AppEntry(
        api: api,
        locationService: locationService,
        reminderScheduler: reminderScheduler,
      ),
    );
  }
}

class _AppEntry extends StatefulWidget {
  const _AppEntry({
    required this.api,
    required this.locationService,
    required this.reminderScheduler,
  });

  final FitLoopApi api;
  final LocationService locationService;
  final ReminderScheduler reminderScheduler;

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
    if (_showSplash) {
      return SplashScreen(onComplete: _onSplashDone);
    }
    if (_onboardingDone == null) {
      return const SizedBox.shrink();
    }
    if (!_onboardingDone!) {
      return OnboardingScreen(onComplete: _onOnboardingDone);
    }
    return AuthGate(
      api: widget.api,
      locationService: widget.locationService,
      reminderScheduler: widget.reminderScheduler,
    );
  }
}

class _ApiFactory {
  const _ApiFactory();

  FitLoopApi create() => HttpFitLoopApi();
}

abstract class LocationService {
  Future<LocationPermission> checkPermission();

  Future<LocationPermission> requestPermission();

  Future<Position> getCurrentPosition();

  Stream<Position> getPositionStream({required LocationSettings settings});
}

class GeolocatorLocationService implements LocationService {
  @override
  Future<LocationPermission> checkPermission() {
    return Geolocator.checkPermission();
  }

  @override
  Future<Position> getCurrentPosition() {
    return Geolocator.getCurrentPosition();
  }

  @override
  Stream<Position> getPositionStream({required LocationSettings settings}) {
    return Geolocator.getPositionStream(locationSettings: settings);
  }

  @override
  Future<LocationPermission> requestPermission() {
    return Geolocator.requestPermission();
  }
}

abstract class PedometerService {
  Stream<int> get stepCountStream;

  Future<int> get currentStepCount;

  void dispose();
}

class AndroidPedometerService implements PedometerService {
  AndroidPedometerService();

  int _initialSteps = 0;
  bool _initialized = false;
  StreamSubscription<StepCount>? _subscription;
  final StreamController<int> _stepController =
      StreamController<int>.broadcast();

  @override
  Future<int> get currentStepCount async {
    return 0;
  }

  @override
  Stream<int> get stepCountStream {
    _subscription = Pedometer.stepCountStream.listen((event) {
      final steps = event.steps;
      if (!_initialized) {
        _initialSteps = steps;
        _initialized = true;
        _stepController.add(0);
        return;
      }
      _stepController.add(steps - _initialSteps);
    });
    return _stepController.stream;
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _stepController.close();
  }
}

class AuthGate extends StatefulWidget {
  const AuthGate({
    super.key,
    required this.api,
    required this.locationService,
    required this.reminderScheduler,
  });

  final FitLoopApi api;
  final LocationService locationService;
  final ReminderScheduler reminderScheduler;

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  UserSession? _session;

  @override
  void initState() {
    super.initState();
    _tryAutoLogin();
  }

  Future<void> _tryAutoLogin() async {
    final data = await TokenStorage.load();
    if (data != null && mounted) {
      final prefs = await SharedPreferences.getInstance();
      final userId = data['userId'] as int;
      final avatarUrl = prefs.getString('avatarUrl_$userId');
      setState(() => _session = UserSession(
          token: data['token'] as String,
          userId: userId,
          nickname: data['nickname'] as String,
          avatarUrl: avatarUrl));
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = _session;
    if (session != null) {
      return AppShell(
        api: widget.api,
        locationService: widget.locationService,
        reminderScheduler: widget.reminderScheduler,
        session: session,
        onLogout: () => setState(() => _session = null),
      );
    }
    return AuthPage(
      api: widget.api,
      onSignedIn: (session) => setState(() => _session = session),
    );
  }
}

class AuthPage extends StatefulWidget {
  const AuthPage({super.key, required this.api, required this.onSignedIn});

  final FitLoopApi api;
  final ValueChanged<UserSession> onSignedIn;

  @override
  State<AuthPage> createState() => _AuthPageState();
}

class _AuthPageState extends State<AuthPage> {
  final _account = TextEditingController();
  final _password = TextEditingController();
  final _confirmPassword = TextEditingController();
  final _nickname = TextEditingController();
  final _code = TextEditingController();
  final _accountFocus = FocusNode();
  bool _registerMode = false;
  bool _resetPasswordMode = false;
  bool _busy = false;
  String? _message;
  bool _messageIsSuccess = false;
  String _loginTab = 'password';
  int _countdown = 0;
  bool _rememberMe = true;
  Timer? _countdownTimer;
  FeatureFlags? _features;

  bool get _smsAvailable => _features?.smsEnabled ?? false;

  @override
  void initState() {
    super.initState();
    _loadSavedAccount();
    _fetchFeatures();
  }

  Future<void> _loadSavedAccount() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString('saved_account');
    if (saved != null && saved.isNotEmpty) {
      _account.text = saved;
    }
  }

  Future<void> _fetchFeatures() async {
    try {
      final features = await widget.api.fetchFeatureFlags();
      if (mounted) setState(() => _features = features);
    } catch (_) {
      // 获取失败时使用默认值（SMS 不可用）
    }
  }

  @override
  void dispose() {
    _account.dispose();
    _password.dispose();
    _confirmPassword.dispose();
    _nickname.dispose();
    _code.dispose();
    _accountFocus.dispose();
    _countdownTimer?.cancel();
    super.dispose();
  }

  String _friendlyError(dynamic error) => friendlyErrorMsg(error);

  bool _isPhoneAccount(String value) => RegExp(r'^1\d{10}$').hasMatch(value);
  bool _isEmailAccount(String value) =>
      RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(value);
  bool _isValidAccount(String value) =>
      _isPhoneAccount(value) || _isEmailAccount(value);
  String _channelForAccount(String value) =>
      _isEmailAccount(value) ? 'email' : 'phone';
  String _verificationPurpose() {
    if (_resetPasswordMode) return 'reset_password';
    if (_registerMode) return 'register';
    return 'login';
  }

  Future<void> _sendCode() async {
    final account = _account.text.trim();
    if (account.isEmpty) {
      setState(() {
        _message = '请输入手机号或邮箱';
        _messageIsSuccess = false;
      });
      return;
    }
    if (!_isValidAccount(account)) {
      setState(() {
        _message = '请输入正确的手机号或邮箱';
        _messageIsSuccess = false;
      });
      return;
    }
    final channel = _channelForAccount(account);
    if (channel == 'phone' && !_smsAvailable) {
      setState(() {
        _message = '手机验证码暂未开放，请使用邮箱验证码';
        _messageIsSuccess = false;
      });
      return;
    }
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      final result = await widget.api.sendVerificationCode(
        channel: channel,
        target: account,
        purpose: _verificationPurpose(),
      );
      if (!mounted) return;
      final debugCode = result['debugCode'];
      final serverMessage = result['message'] ?? '验证码已发送';
      setState(() {
        _countdown = 60;
        if (debugCode != null && channel == 'phone' && _smsAvailable) {
          _message = '内测验证码：$debugCode';
        } else if (debugCode != null) {
          _message = '调试验证码：$debugCode';
        } else {
          _message = serverMessage;
        }
        _messageIsSuccess = true;
      });
      _startCountdown();
    } catch (error) {
      setState(() {
        _message = _friendlyError(error);
        _messageIsSuccess = false;
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _startCountdown() {
    _countdownTimer?.cancel();
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      setState(() => _countdown = _countdown > 0 ? _countdown - 1 : 0);
      if (_countdown <= 0) {
        timer.cancel();
      }
    });
  }

  Future<void> _submit() async {
    final account = _account.text.trim();
    if (account.isEmpty) {
      setState(() {
        _message = '请输入手机号或邮箱';
        _messageIsSuccess = false;
      });
      return;
    }
    if (!_isValidAccount(account)) {
      setState(() {
        _message = '请输入正确的手机号或邮箱';
        _messageIsSuccess = false;
      });
      return;
    }
    if (_resetPasswordMode) {
      if (_code.text.trim().isEmpty) {
        setState(() {
          _message = '请输入验证码';
          _messageIsSuccess = false;
        });
        return;
      }
      if (_password.text.isEmpty) {
        setState(() {
          _message = '请输入新密码';
          _messageIsSuccess = false;
        });
        return;
      }
      if (_password.text != _confirmPassword.text) {
        setState(() {
          _message = '两次输入的密码不一致';
          _messageIsSuccess = false;
        });
        return;
      }
    }
    if (_registerMode) {
      if (_password.text.isEmpty) {
        setState(() {
          _message = '请输入密码';
          _messageIsSuccess = false;
        });
        return;
      }
      if (_password.text != _confirmPassword.text) {
        setState(() {
          _message = '两次输入的密码不一致';
          _messageIsSuccess = false;
        });
        return;
      }
      if (_code.text.trim().isEmpty) {
        setState(() {
          _message = '请输入验证码';
          _messageIsSuccess = false;
        });
        return;
      }
    } else if (_loginTab == 'code') {
      final code = _code.text.trim();
      if (code.isEmpty) {
        setState(() {
          _message = '请输入验证码';
          _messageIsSuccess = false;
        });
        return;
      }
    }

    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      if (_resetPasswordMode) {
        await widget.api.resetPassword(
          account: account,
          code: _code.text.trim(),
          newPassword: _password.text,
        );
        if (!mounted) return;
        setState(() {
          _resetPasswordMode = false;
          _registerMode = false;
          _password.clear();
          _confirmPassword.clear();
          _code.clear();
          _message = '密码已重置，请使用新密码登录';
          _messageIsSuccess = true;
        });
        return;
      }
      if (_registerMode) {
        await widget.api.register(
          account: account,
          password: _password.text,
          nickname: _nickname.text.trim().isEmpty
              ? 'FitLoop 用户'
              : _nickname.text.trim(),
          code: _code.text.trim(),
        );
      }
      final loginType = _loginTab == 'code' && !_registerMode ? 'code' : 'password';
      final session = await widget.api.login(
        account: account,
        password: loginType == 'password' ? _password.text : null,
        code: loginType == 'code' ? _code.text.trim() : null,
        loginType: loginType,
      );
      await TokenStorage.save(session.token, session.userId, session.nickname);
      final prefs = await SharedPreferences.getInstance();
      if (_rememberMe) {
        await prefs.setString('saved_account', account);
      } else {
        await prefs.remove('saved_account');
      }
      if (mounted) widget.onSignedIn(session);
    } catch (error) {
      if (mounted) {
        setState(() {
          _message = _friendlyError(error);
          _messageIsSuccess = false;
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isCodeLogin = _loginTab == 'code';
    final showCodeInput = _resetPasswordMode ||
        (!_registerMode && isCodeLogin) ||
        _registerMode;
    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            const SizedBox(height: 32),
            Text(
              'FitLoop',
              style: Theme.of(context)
                  .textTheme
                  .displaySmall
                  ?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            Text(
                _resetPasswordMode
                    ? '找回账号密码'
                    : (_registerMode ? '创建账号' : '校园运动打卡与健康管理'),
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 24),
            // Login mode: show password/code toggle
            if (!_registerMode && !_resetPasswordMode)
              Row(
                children: [
                  Expanded(
                    child: ChoiceChip(
                      label: const Text('密码登录'),
                      selected: _loginTab == 'password',
                      onSelected: _busy
                          ? null
                          : (_) => setState(() => _loginTab = 'password'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ChoiceChip(
                      label: const Text('验证码登录'),
                      selected: _loginTab == 'code',
                      onSelected: _busy
                          ? null
                          : (_) => setState(() => _loginTab = 'code'),
                    ),
                  ),
                ],
              ),
            if (!_registerMode) const SizedBox(height: 16),
            // Account input
            TextField(
              controller: _account,
              focusNode: _accountFocus,
              autofocus: true,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.phone_android),
                  labelText: '手机号或邮箱'),
            ),
            // 手机验证码未开放提示
            if (isCodeLogin &&
                _isPhoneAccount(_account.text.trim()) &&
                !_smsAvailable) ...[
              const SizedBox(height: 8),
              Text(
                '手机验证码暂未开放，请使用邮箱',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.error,
                  fontSize: 12,
                ),
              ),
            ],
            // Password login: password field only
            if (!_registerMode && !_resetPasswordMode && !isCodeLogin) ...[
              const SizedBox(height: 12),
              TextField(
                controller: _password,
                obscureText: true,
                decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.lock_outline), labelText: '密码'),
              ),
            ],
            // Register mode: password + confirm + nickname
            if (_registerMode || _resetPasswordMode) ...[
              const SizedBox(height: 12),
              TextField(
                controller: _password,
                obscureText: true,
                decoration: InputDecoration(
                    prefixIcon: const Icon(Icons.lock_outline),
                    labelText: _resetPasswordMode ? '新密码' : '密码'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _confirmPassword,
                obscureText: true,
                decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.lock_outline), labelText: '确认密码'),
              ),
              if (_registerMode) ...[
                const SizedBox(height: 12),
                TextField(
                  controller: _nickname,
                  decoration: const InputDecoration(
                      prefixIcon: Icon(Icons.badge_outlined), labelText: '昵称'),
                ),
              ],
            ],
            // Verification code input + send button
            if (showCodeInput) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _code,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                          prefixIcon: Icon(Icons.pin_outlined),
                          labelText: '验证码'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  FilledButton.tonal(
                    onPressed: (_busy || _countdown > 0) ? null : _sendCode,
                    child: Text(_countdown > 0 ? '${_countdown}s' : '获取验证码'),
                  ),
                ],
              ),
            ],
            // Message
            if (_message != null) ...[
              const SizedBox(height: 12),
              Text(
                _message!,
                style: TextStyle(
                  color: _messageIsSuccess
                      ? Theme.of(context).colorScheme.primary
                      : Theme.of(context).colorScheme.error,
                  fontSize: 13,
                ),
              ),
            ],
            const SizedBox(height: 20),
            // Remember me
            if (!_registerMode && !_resetPasswordMode)
              CheckboxListTile(
                value: _rememberMe,
                onChanged: _busy
                    ? null
                    : (v) => setState(() => _rememberMe = v ?? true),
                title: const Text('记住账号', style: TextStyle(fontSize: 14)),
                controlAffinity: ListTileControlAffinity.leading,
                dense: true,
                contentPadding: EdgeInsets.zero,
              ),
            // Submit button
            FilledButton.icon(
              onPressed: _busy ? null : _submit,
              icon: _busy
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : Icon(_resetPasswordMode
                      ? Icons.lock_reset
                      : (_registerMode ? Icons.person_add_alt : Icons.login)),
              label: Text(_resetPasswordMode
                  ? '重置密码'
                  : (_registerMode ? '注册并进入' : '登录')),
            ),
            if (!_registerMode && !_resetPasswordMode)
              TextButton(
                onPressed: _busy
                    ? null
                    : () => setState(() {
                          _resetPasswordMode = true;
                          _message = null;
                          _code.clear();
                          _password.clear();
                          _confirmPassword.clear();
                        }),
                child: const Text('忘记密码'),
              ),
            // Toggle register/login
            TextButton(
              onPressed: _busy
                  ? null
                  : () => setState(() {
                        if (_resetPasswordMode) {
                          _resetPasswordMode = false;
                          _registerMode = false;
                        } else {
                          _registerMode = !_registerMode;
                        }
                        _message = null;
                        _code.clear();
                      }),
              child: Text(_resetPasswordMode
                  ? '返回登录'
                  : (_registerMode ? '已有账号，去登录' : '没有账号，创建账号')),
            ),
          ],
        ),
      ),
    );
  }
}

class AppShell extends StatefulWidget {
  const AppShell({
    super.key,
    required this.api,
    required this.locationService,
    required this.reminderScheduler,
    required this.session,
    this.onLogout,
  });

  final FitLoopApi api;
  final LocationService locationService;
  final ReminderScheduler reminderScheduler;
  final UserSession session;
  final VoidCallback? onLogout;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _index = 0;
  bool _isSportActive = false;
  late final List<Widget> _pages;

  @override
  void initState() {
    super.initState();
    _pages = [
      DashboardPage(
        api: widget.api,
        session: widget.session,
        onNavigateToTab: (index) => setState(() => _index = index),
      ),
      SportSessionPage(
        api: widget.api,
        locationService: widget.locationService,
        session: widget.session,
        onSportActiveChanged: (active) {
          if (mounted) setState(() => _isSportActive = active);
        },
      ),
      StatsPage(api: widget.api, session: widget.session),
      SocialPage(api: widget.api, session: widget.session),
      ProfilePage(
        api: widget.api,
        reminderScheduler: widget.reminderScheduler,
        session: widget.session,
        onLogout: () => _handleLogout(),
      ),
    ];
  }

  void _handleLogout() async {
    await TokenStorage.clear();
    widget.onLogout?.call();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: IndexedStack(index: _index, children: _pages),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (value) => setState(() => _index = value),
        destinations: [
          const NavigationDestination(
              icon: Icon(Icons.home_outlined),
              selectedIcon: Icon(Icons.home),
              label: '首页'),
          NavigationDestination(
              icon: _isSportActive
                  ? const Badge(child: Icon(Icons.directions_run_outlined))
                  : const Icon(Icons.directions_run_outlined),
              selectedIcon: _isSportActive
                  ? const Badge(child: Icon(Icons.directions_run))
                  : const Icon(Icons.directions_run),
              label: '运动'),
          const NavigationDestination(
              icon: Icon(Icons.bar_chart_outlined),
              selectedIcon: Icon(Icons.bar_chart),
              label: '统计'),
          const NavigationDestination(
              icon: Icon(Icons.groups_outlined),
              selectedIcon: Icon(Icons.groups),
              label: '社交'),
          const NavigationDestination(
              icon: Icon(Icons.person_outline),
              selectedIcon: Icon(Icons.person),
              label: '我的'),
        ],
      ),
    );
  }
}

class DashboardPage extends StatefulWidget {
  const DashboardPage({
    super.key,
    required this.api,
    required this.session,
    this.onNavigateToTab,
  });

  final FitLoopApi api;
  final UserSession session;
  final ValueChanged<int>? onNavigateToTab;

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  Future<List<SportTarget>>? _future;
  Future<TargetReminderListResponse>? _reminderFuture;
  Future<SportHistoryResponse>? _historyFuture;
  Future<SportStats>? _statsFuture;

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  void _loadAll() {
    _future = _loadTargets();
    _reminderFuture = _loadReminders();
    _historyFuture =
        widget.api.sportHistory(token: widget.session.token, period: 'week');
    _statsFuture = widget.api.sportStats(token: widget.session.token);
  }

  void _refreshAll() {
    setState(() => _loadAll());
  }

  Future<List<SportTarget>> _loadTargets() {
    return widget.api.currentTargets(token: widget.session.token);
  }

  Future<TargetReminderListResponse> _loadReminders() {
    return widget.api.targetReminders(token: widget.session.token);
  }

  Future<void> _deleteTarget(SportTarget target) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('确认删除'),
        content: Text('确定要删除目标"${_metricLabel(target.metric)} ${_formatNumber(target.targetValue)}"吗？此操作不可恢复。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await widget.api.deleteTarget(
        token: widget.session.token,
        targetId: target.targetId,
      );
      if (mounted) _refreshAll();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(friendlyErrorMsg(error))),
      );
    }
  }

  Future<void> _showCreateTargetSheet() async {
    final created = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (context) {
        return _TargetFormSheet(
          api: widget.api,
          token: widget.session.token,
        );
      },
    );
    if (created == true && mounted) {
      _refreshAll();
    }
  }

  Future<void> _showEditTargetSheet(SportTarget target) async {
    final updated = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (context) {
        return _TargetFormSheet(
          api: widget.api,
          token: widget.session.token,
          existingTarget: target,
        );
      },
    );
    if (updated == true && mounted) {
      _refreshAll();
    }
  }

  String _todayString() {
    final now = DateTime.now();
    final month = now.month.toString().padLeft(2, '0');
    final day = now.day.toString().padLeft(2, '0');
    return '${now.year}-$month-$day';
  }

  @override
  Widget build(BuildContext context) {
    final today = _todayString();
    return _PageScaffold(
      title: 'FitLoop',
      children: [
        // Welcome card
        _MetricCard(
            label: '欢迎回来',
            value: widget.session.nickname,
            icon: Icons.waving_hand_outlined),
        // Reminder banners
        FutureBuilder<TargetReminderListResponse>(
          future: _reminderFuture,
          builder: (context, snapshot) {
            final reminders =
                snapshot.data?.targets ?? const <TargetReminderResponse>[];
            final dueItems = reminders.where((r) => r.due).toList();
            if (dueItems.isEmpty) return const SizedBox.shrink();
            return _ReminderBannerCard(
              reminders: dueItems,
              onDismiss: (targetId) async {
                await widget.api.acknowledgeTargetReminder(
                  token: widget.session.token,
                  targetId: targetId,
                );
                if (mounted) _refreshAll();
              },
            );
          },
        ),
        // Today's exercise overview
        FutureBuilder<SportHistoryResponse>(
          future: _historyFuture,
          builder: (context, snapshot) {
            final points = snapshot.data?.points ?? [];
            final todayPoint =
                points.where((p) => p.date == today).firstOrNull;
            final hasData = todayPoint != null && todayPoint.count > 0;
            return Card(
              margin: const EdgeInsets.only(bottom: 12),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.today_outlined, size: 20),
                        const SizedBox(width: 8),
                        Text('今日运动概览',
                            style: Theme.of(context)
                                .textTheme
                                .titleSmall
                                ?.copyWith(fontWeight: FontWeight.w600)),
                      ],
                    ),
                    const SizedBox(height: 12),
                    if (!hasData)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 8),
                        child: Text('今天还没有运动记录',
                            style: TextStyle(color: Colors.grey)),
                      )
                    else
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceAround,
                        children: [
                          _OverviewItem(
                              icon: Icons.repeat,
                              label: '次数',
                              value: '${todayPoint.count} 次'),
                          _OverviewItem(
                              icon: Icons.timer_outlined,
                              label: '时长',
                              value:
                                  '${(todayPoint.durationSeconds / 60).round()} 分钟'),
                          _OverviewItem(
                              icon: Icons.route_outlined,
                              label: '里程',
                              value:
                                  '${todayPoint.distanceKm.toStringAsFixed(1)} km'),
                          _OverviewItem(
                              icon: Icons.bolt_outlined,
                              label: '热量',
                              value:
                                  '${todayPoint.calorie.toStringAsFixed(0)} kcal'),
                        ],
                      ),
                  ],
                ),
              ),
            );
          },
        ),
        // Weekly calendar
        FutureBuilder<SportHistoryResponse>(
          future: _historyFuture,
          builder: (context, snapshot) {
            final points = snapshot.data?.points ?? [];
            return Card(
              margin: const EdgeInsets.only(bottom: 12),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.calendar_month_outlined, size: 20),
                        const SizedBox(width: 8),
                        Text('本周运动日历',
                            style: Theme.of(context)
                                .textTheme
                                .titleSmall
                                ?.copyWith(fontWeight: FontWeight.w600)),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: points.map((p) {
                        final hasActivity = p.count > 0;
                        final date = DateTime.tryParse(p.date);
                        final dayLabel = date != null
                            ? '${date.month}/${date.day}'
                            : p.date;
                        final isToday = p.date == today;
                        return Column(
                          children: [
                            Text(dayLabel,
                                style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: isToday
                                        ? FontWeight.w700
                                        : FontWeight.normal,
                                    color: isToday
                                        ? Theme.of(context).colorScheme.primary
                                        : null)),
                            const SizedBox(height: 6),
                            Container(
                              width: 32,
                              height: 32,
                              decoration: BoxDecoration(
                                color: hasActivity
                                    ? Theme.of(context).colorScheme.primary
                                    : Colors.grey.shade200,
                                shape: BoxShape.circle,
                              ),
                              child: hasActivity
                                  ? const Icon(Icons.check,
                                      size: 16, color: Colors.white)
                                  : null,
                            ),
                          ],
                        );
                      }).toList(),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
        // Latest stats summary
        FutureBuilder<SportStats>(
          future: _statsFuture,
          builder: (context, snapshot) {
            final stats = snapshot.data;
            return _MetricCard(
              label: '累计统计',
              value: stats != null
                  ? '${stats.checkinCount} 次 / ${(stats.durationSeconds / 3600).toStringAsFixed(1)} 小时 / ${stats.distanceKm.toStringAsFixed(1)} km'
                  : '加载中',
              icon: Icons.bar_chart_outlined,
            );
          },
        ),
        // Quick actions
        Card(
          margin: const EdgeInsets.only(bottom: 12),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.flash_on_outlined, size: 20),
                    const SizedBox(width: 8),
                    Text('快捷入口',
                        style: Theme.of(context)
                            .textTheme
                            .titleSmall
                            ?.copyWith(fontWeight: FontWeight.w600)),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: _QuickAction(
                        icon: Icons.directions_run,
                        label: '开始打卡',
                        onTap: () =>
                            widget.onNavigateToTab?.call(1),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _QuickAction(
                        icon: Icons.bar_chart,
                        label: '查看统计',
                        onTap: () =>
                            widget.onNavigateToTab?.call(2),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        // Target card
        FutureBuilder<List<SportTarget>>(
          future: _future,
          builder: (context, snapshot) {
            final targets = snapshot.data ?? const <SportTarget>[];
            return _TargetSummaryCard(
              loading: snapshot.connectionState == ConnectionState.waiting,
              error: snapshot.error,
              targets: targets,
              onRefresh: _refreshAll,
              onCreate: _showCreateTargetSheet,
              onEdit: _showEditTargetSheet,
              onDelete: (t) => _deleteTarget(t),
            );
          },
        ),
      ],
    );
  }
}

class _OverviewItem extends StatelessWidget {
  const _OverviewItem({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Icon(icon, size: 22, color: Theme.of(context).colorScheme.primary),
        const SizedBox(height: 4),
        Text(value,
            style: Theme.of(context)
                .textTheme
                .bodyMedium
                ?.copyWith(fontWeight: FontWeight.w600)),
        Text(label, style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }
}

class _QuickAction extends StatelessWidget {
  const _QuickAction({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return FilledButton.tonalIcon(
      onPressed: onTap,
      icon: Icon(icon, size: 18),
      label: Text(label),
    );
  }
}

class _ReminderBannerCard extends StatefulWidget {
  const _ReminderBannerCard({
    required this.reminders,
    required this.onDismiss,
  });

  final List<TargetReminderResponse> reminders;
  final Future<void> Function(int targetId) onDismiss;

  @override
  State<_ReminderBannerCard> createState() => _ReminderBannerCardState();
}

class _ReminderBannerCardState extends State<_ReminderBannerCard> {
  final Set<int> _dismissing = {};

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      color: Theme.of(context).colorScheme.errorContainer,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Row(
              children: [
                Icon(Icons.notifications_active_outlined,
                    color: Theme.of(context).colorScheme.onErrorContainer,
                    size: 20),
                const SizedBox(width: 8),
                Text('目标提醒',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          color: Theme.of(context).colorScheme.onErrorContainer,
                        )),
                if (widget.reminders.length > 1)
                  Text(
                    '（${widget.reminders.length} 项）',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onErrorContainer,
                        ),
                  ),
              ],
            ),
          ),
          ...widget.reminders.take(3).map(
                (r) => ListTile(
                  dense: true,
                  leading: Icon(
                    _reminderIcon(r.metric),
                    color: Theme.of(context).colorScheme.onErrorContainer,
                  ),
                  title: Text(r.message,
                      style: TextStyle(
                        fontSize: 13,
                        color: Theme.of(context).colorScheme.onErrorContainer,
                      )),
                  trailing: _dismissing.contains(r.targetId)
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : IconButton(
                          icon: const Icon(Icons.close, size: 18),
                          onPressed: () async {
                            setState(() => _dismissing.add(r.targetId));
                            await widget.onDismiss(r.targetId);
                            if (mounted) {
                              setState(() => _dismissing.remove(r.targetId));
                            }
                          },
                        ),
                ),
              ),
        ],
      ),
    );
  }
}

IconData _reminderIcon(String metric) {
  switch (metric) {
    case 'duration':
      return Icons.timer_outlined;
    case 'distance':
      return Icons.route_outlined;
    case 'calorie':
      return Icons.bolt_outlined;
    default:
      return Icons.repeat_outlined;
  }
}

class _TargetSummaryCard extends StatelessWidget {
  const _TargetSummaryCard({
    required this.loading,
    required this.error,
    required this.targets,
    required this.onRefresh,
    required this.onCreate,
    required this.onEdit,
    required this.onDelete,
  });

  final bool loading;
  final Object? error;
  final List<SportTarget> targets;
  final VoidCallback onRefresh;
  final VoidCallback onCreate;
  final void Function(SportTarget)? onEdit;
  final Future<void> Function(SportTarget)? onDelete;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Column(
        children: [
          ListTile(
            leading: const Icon(Icons.flag_outlined),
            title: const Text('运动目标'),
            subtitle: loading
                ? const Text('加载中')
                : error != null
                    ? Text(friendlyErrorMsg(error))
                    : targets.isEmpty
                        ? const Text('暂无进行中目标')
                        : null,
          ),
          if (!loading && error == null)
            ...targets.map((target) => _TargetTile(
                  target: target,
                  onEdit: onEdit != null ? () => onEdit!(target) : null,
                  onDelete: onDelete != null ? () => onDelete!(target) : null,
                )),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: onRefresh,
                    icon: const Icon(Icons.refresh),
                    label: const Text('刷新'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: onCreate,
                    icon: const Icon(Icons.add),
                    label: const Text('创建目标'),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TargetTile extends StatelessWidget {
  const _TargetTile({
    required this.target,
    this.onEdit,
    this.onDelete,
  });

  final SportTarget target;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final value =
        '${_periodLabel(target.periodType)} ${_metricLabel(target.metric)}：'
        '${_formatNumber(target.completedValue)} / ${_formatNumber(target.targetValue)}，'
        '进度 ${target.progress.toStringAsFixed(1)}%';
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Card(
        margin: const EdgeInsets.only(bottom: 8),
        child: ListTile(
          dense: true,
          title: Text(value, style: const TextStyle(fontSize: 13)),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (onEdit != null)
                IconButton(
                  icon: const Icon(Icons.edit_outlined, size: 18),
                  onPressed: onEdit,
                  tooltip: '编辑',
                ),
              if (onDelete != null)
                IconButton(
                  icon: Icon(Icons.delete_outline, size: 18,
                      color: Theme.of(context).colorScheme.error),
                  onPressed: onDelete,
                  tooltip: '删除',
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TargetFormSheet extends StatefulWidget {
  const _TargetFormSheet({
    required this.api,
    required this.token,
    this.existingTarget,
  });

  final FitLoopApi api;
  final String token;
  final SportTarget? existingTarget;

  @override
  State<_TargetFormSheet> createState() => _TargetFormSheetState();
}

class _TargetFormSheetState extends State<_TargetFormSheet> {
  late final TextEditingController _value;
  late String _periodType;
  late String _metric;
  bool _busy = false;
  String? _message;

  bool get _isEditMode => widget.existingTarget != null;

  @override
  void initState() {
    super.initState();
    final t = widget.existingTarget;
    _periodType = t?.periodType ?? 'week';
    _metric = t?.metric ?? 'count';
    _value = TextEditingController(
      text: t != null ? _formatNumber(t.targetValue) : '3',
    );
  }

  @override
  void dispose() {
    _value.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final targetValue = double.tryParse(_value.text.trim());
    if (targetValue == null || targetValue <= 0) {
      setState(() => _message = '目标值必须大于 0');
      return;
    }
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      if (_isEditMode) {
        await widget.api.editTarget(
          token: widget.token,
          targetId: widget.existingTarget!.targetId,
          periodType: _periodType,
          metric: _metric,
          targetValue: targetValue,
        );
      } else {
        await widget.api.createTarget(
          token: widget.token,
          periodType: _periodType,
          metric: _metric,
          targetValue: targetValue,
        );
      }
      if (mounted) {
        Navigator.of(context).pop(true);
      }
    } catch (error) {
      setState(() => _message = friendlyErrorMsg(error));
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(20, 20, 20, 20 + bottomInset),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              _isEditMode ? '编辑运动目标' : '创建运动目标',
              style: Theme.of(context)
                  .textTheme
                  .titleLarge
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              initialValue: _periodType,
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.calendar_month_outlined),
                labelText: '周期',
              ),
              items: const [
                DropdownMenuItem(value: 'week', child: Text('本周')),
                DropdownMenuItem(value: 'month', child: Text('本月')),
              ],
              onChanged: _busy
                  ? null
                  : (value) => setState(() => _periodType = value ?? 'week'),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _metric,
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.tune_outlined),
                labelText: '指标',
              ),
              items: const [
                DropdownMenuItem(value: 'count', child: Text('运动次数')),
                DropdownMenuItem(value: 'duration', child: Text('运动时长(分钟)')),
                DropdownMenuItem(value: 'distance', child: Text('运动里程(km)')),
                DropdownMenuItem(value: 'calorie', child: Text('消耗热量(kcal)')),
              ],
              onChanged: _busy
                  ? null
                  : (value) => setState(() => _metric = value ?? 'count'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _value,
              enabled: !_busy,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.track_changes_outlined),
                labelText: '目标值',
              ),
            ),
            if (_message != null) ...[
              const SizedBox(height: 12),
              Text(_message!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ],
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _busy ? null : _submit,
              icon: _busy
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.check),
              label: Text(_isEditMode ? '更新目标' : '保存目标'),
            ),
          ],
        ),
      ),
    );
  }
}

String _checkinModeLabel(String mode) {
  return switch (mode) {
    'gps' => 'GPS 定位打卡',
    'sensor' => '传感器打卡',
    'photo' => '拍照打卡',
    'manual' => '手动打卡',
    _ => mode,
  };
}

String _periodLabel(String periodType) {
  return switch (periodType.toLowerCase()) {
    'month' => '本月',
    _ => '本周',
  };
}

String _metricLabel(String metric) {
  return switch (metric.toLowerCase()) {
    'duration' => '运动时长(分钟)',
    'distance' => '运动里程(km)',
    'calorie' => '消耗热量(kcal)',
    _ => '运动次数',
  };
}

String _formatNumber(double value) {
  if (value == value.roundToDouble()) {
    return value.toStringAsFixed(0);
  }
  return value.toStringAsFixed(1);
}

class SportSessionPage extends StatefulWidget {
  const SportSessionPage({
    super.key,
    required this.api,
    required this.locationService,
    required this.session,
    this.onSportActiveChanged,
  });

  final FitLoopApi api;
  final LocationService locationService;
  final UserSession session;
  final ValueChanged<bool>? onSportActiveChanged;

  @override
  State<SportSessionPage> createState() => _SportSessionPageState();
}

class _SportSessionPageState extends State<SportSessionPage> {
  static const _maxAcceptedAccuracyMeters = 50.0;
  static const int _statusAbnormal = 2;

  String? _sessionId;
  SportRecord? _lastRecord;
  bool _busy = false;
  String _status = '未开始';
  DateTime? _startedAt;
  StreamSubscription<Position>? _positionSubscription;
  int _trackPointCount = 0;
  int _trackingGeneration = 0;
  // GPS 实时状态
  double? _currentLat;
  double? _currentLng;
  double? _currentAccuracy;
  double _totalDistanceKm = 0;
  double? _lastLat;
  double? _lastLng;
  double? _currentSpeedMs;
  bool _isPaused = false;
  Timer? _elapsedTimer;
  int _activeSeconds = 0;
  Future<AppealListResponse>? _appealFuture;

  String _selectedSportType = 'running';
  String _selectedCheckinMode = 'gps';
  int _stepCount = 0;
  PedometerService? _pedometerService;
  StreamSubscription<int>? _stepSubscription;
  String? _photoUrl;
  bool _photoUploading = false;

  @override
  void dispose() {
    widget.onSportActiveChanged?.call(false);
    _trackingGeneration++;
    _positionSubscription?.cancel();
    _stepSubscription?.cancel();
    _pedometerService?.dispose();
    _elapsedTimer?.cancel();
    _durationController.dispose();
    _distanceController.dispose();
    _calorieController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  bool _isOutdoorSport(String type) {
    return {'running', 'cycling', 'walking'}.contains(type);
  }

  Future<String?> _chooseCheckinMode() {
    final outdoor = _isOutdoorSport(_selectedSportType);
    return showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          if (outdoor)
            ListTile(
              leading: const Icon(Icons.location_on),
              title: const Text('GPS 定位打卡'),
              subtitle: const Text('实时定位追踪轨迹'),
              onTap: () => Navigator.pop(ctx, 'gps'),
            ),
          ListTile(
            leading: const Icon(Icons.timer_outlined),
            title: const Text('计时打卡'),
            subtitle: const Text('记录运动时长'),
            onTap: () => Navigator.pop(ctx, 'timer'),
          ),
          if (!outdoor)
            ListTile(
              leading: const Icon(Icons.fitness_center),
              title: const Text('次数打卡'),
              subtitle: const Text('记录运动次数/组数'),
              onTap: () => Navigator.pop(ctx, 'count'),
            ),
          if (!outdoor)
            ListTile(
              leading: const Icon(Icons.local_fire_department),
              title: const Text('热量估算'),
              subtitle: const Text('根据运动类型估算消耗'),
              onTap: () => Navigator.pop(ctx, 'calorie'),
            ),
          ListTile(
            leading: const Icon(Icons.edit),
            title: const Text('手动打卡'),
            subtitle: const Text('自行输入运动数据'),
            onTap: () => Navigator.pop(ctx, 'manual'),
          ),
        ]),
      ),
    );
  }

  Future<void> _toggle() async {
    if (_sessionId == null) {
      final mode = await _chooseCheckinMode();
      if (mode == null || !mounted) return;
      _selectedCheckinMode = mode;

      switch (mode) {
        case 'gps':
          await _startGpsCheckin();
        case 'sensor':
          await _startSensorCheckin();
        case 'photo':
          await _startPhotoCheckin();
        case 'manual':
          await _startManualCheckin();
      }
    } else {
      await _finishCheckin();
    }
  }

  Future<void> _startGpsCheckin() async {
    final canUseLocation = await _ensureLocationPermission();
    if (!canUseLocation) return;

    setState(() => _busy = true);
    try {
      await _stopGpsTracking();
      final start = await widget.api.startSport(
        token: widget.session.token,
        sportType: _selectedSportType,
        checkinMode: 'gps',
      );
      final startedAt = DateTime.now();
      setState(() {
        _sessionId = start.sessionId;
        _startedAt = startedAt;
        _trackPointCount = 0;
        _totalDistanceKm = 0;
        _lastLat = null;
        _lastLng = null;
        _currentSpeedMs = null;
        _currentLat = null;
        _currentLng = null;
        _currentAccuracy = null;
        _isPaused = false;
        _activeSeconds = 0;
        _status = 'GPS 打卡进行中，正在获取位置...';
        _busy = false;
      });
      widget.onSportActiveChanged?.call(true);
      _startGpsTracking(start.sessionId);
      _startElapsedTimer();
    } catch (error) {
      setState(() {
        _status = friendlyErrorMsg(error);
        _busy = false;
      });
    }
  }

  Future<void> _startSensorCheckin() async {
    setState(() => _busy = true);
    try {
      final start = await widget.api.startSport(
        token: widget.session.token,
        sportType: _selectedSportType,
        checkinMode: 'sensor',
      );
      final startedAt = DateTime.now();
      _stepCount = 0;
      _pedometerService = AndroidPedometerService();
      _stepSubscription = _pedometerService!.stepCountStream.listen((steps) {
        if (mounted) {
          setState(() {
            _stepCount = steps;
            _status = '传感器打卡进行中，当前步数：$steps';
          });
        }
      });
      setState(() {
        _sessionId = start.sessionId;
        _startedAt = startedAt;
        _status = '传感器打卡进行中，正在记录步数...';
        _busy = false;
      });
      widget.onSportActiveChanged?.call(true);
    } catch (error) {
      setState(() {
        _status = friendlyErrorMsg(error);
        _busy = false;
      });
    }
  }

  Future<void> _startPhotoCheckin() async {
    setState(() => _busy = true);
    try {
      final picker = ImagePicker();
      final xFile = await picker.pickImage(
        source: ImageSource.camera,
        maxWidth: 1920,
        imageQuality: 85,
      );
      if (xFile == null) {
        setState(() {
          _busy = false;
          _status = '未选择照片，已取消';
        });
        return;
      }
      if (!mounted) return;
      setState(() => _photoUploading = true);
      final photoUrl = await widget.api.uploadSportPhoto(
        token: widget.session.token,
        imagePath: xFile.path,
      );
      if (!mounted) return;
      _photoUrl = photoUrl;
      final start = await widget.api.startSport(
        token: widget.session.token,
        sportType: _selectedSportType,
        checkinMode: 'photo',
      );
      final startedAt = DateTime.now();
      setState(() {
        _sessionId = start.sessionId;
        _startedAt = startedAt;
        _status = '拍照打卡进行中，照片已上传';
        _busy = false;
        _photoUploading = false;
      });
      widget.onSportActiveChanged?.call(true);
    } catch (error) {
      final msg = error.toString();
      if (msg.contains('denied') || msg.contains('permission') || msg.contains('camera')) {
        setState(() {
          _status = '无法访问相机，请检查权限设置';
          _busy = false;
          _photoUploading = false;
        });
      } else {
        setState(() {
          _status = friendlyErrorMsg(error);
          _busy = false;
          _photoUploading = false;
        });
      }
    }
  }

  Future<void> _startManualCheckin() async {
    final data = await _showManualCheckinForm();
    if (data == null || !mounted) return;

    setState(() => _busy = true);
    try {
      final start = await widget.api.startSport(
        token: widget.session.token,
        sportType: _selectedSportType,
        checkinMode: 'manual',
      );
      final durationMinutes = data['durationMinutes'] as int;
      final distanceKm = data['distanceKm'] as double?;
      final calorie = data['calorie'] as double?;
      final note = data['note'] as String?;

      final record = await widget.api.finishSport(
        token: widget.session.token,
        sessionId: start.sessionId,
        durationSeconds: durationMinutes * 60,
        weightKg: 60,
        distanceKm: distanceKm,
        calorie: calorie,
        note: note,
      );
      setState(() {
        _lastRecord = record;
        _status = '已保存手动打卡记录 #${record.recordId}';
        _busy = false;
      });
    } catch (error) {
      setState(() {
        _status = friendlyErrorMsg(error);
        _busy = false;
      });
    }
  }

  Future<void> _finishCheckin() async {
    setState(() => _busy = true);
    try {
      if (_selectedCheckinMode == 'gps') {
        await _stopGpsTracking();

        Position? lastPosition;
        try {
          lastPosition = await widget.locationService.getCurrentPosition();
        } catch (_) {}

        if (lastPosition != null &&
            await _uploadTrackPoint(_sessionId!, lastPosition)) {
          _trackPointCount++;
        }
      }

      if (_selectedCheckinMode == 'sensor') {
        _stepSubscription?.cancel();
        _pedometerService?.dispose();
      }

      final duration = DateTime.now()
          .difference(_startedAt ?? DateTime.now())
          .inSeconds
          .clamp(1, 24 * 3600)
          .toInt();

      double? distanceKm;
      if (_selectedCheckinMode == 'sensor' && _stepCount > 0) {
        distanceKm = _stepCount * 0.7 / 1000.0;
      }

      final record = await widget.api.finishSport(
        token: widget.session.token,
        sessionId: _sessionId!,
        durationSeconds: duration,
        weightKg: 60,
        distanceKm: distanceKm,
        photoUrl: _photoUrl,
      );

      var statusMsg = '已保存记录 #${record.recordId}';
      if (_selectedCheckinMode == 'gps') {
        statusMsg += '，共上传 $_trackPointCount 个轨迹点';
      } else if (_selectedCheckinMode == 'sensor') {
        statusMsg +=
            '，步数 $_stepCount，距离 ${distanceKm?.toStringAsFixed(2) ?? "0"} km';
      }

      _elapsedTimer?.cancel();
      _elapsedTimer = null;
      setState(() {
        _sessionId = null;
        _startedAt = null;
        _trackPointCount = 0;
        _stepCount = 0;
        _photoUrl = null;
        _isPaused = false;
        _activeSeconds = 0;
        _totalDistanceKm = 0;
        _currentLat = null;
        _currentLng = null;
        _currentSpeedMs = null;
        _lastRecord = record;
        _status = statusMsg;
        if (record.status == _statusAbnormal) {
          _appealFuture = widget.api.listAppeals(token: widget.session.token);
        }
      });
      widget.onSportActiveChanged?.call(false);
    } catch (error) {
      if (_sessionId != null) {
        final duration = DateTime.now()
            .difference(_startedAt ?? DateTime.now())
            .inSeconds
            .clamp(1, 24 * 3600)
            .toInt();
        final pending = PendingFinishRecord(
          token: widget.session.token,
          sessionId: _sessionId!,
          durationSeconds: duration,
          weightKg: 60,
        );
        await SyncQueue.enqueueFinish(pending);
        if (!mounted) return;
        _elapsedTimer?.cancel();
        _elapsedTimer = null;
        setState(() {
          _sessionId = null;
          _startedAt = null;
          _trackPointCount = 0;
          _stepCount = 0;
          _photoUrl = null;
          _isPaused = false;
          _activeSeconds = 0;
          _totalDistanceKm = 0;
          _currentLat = null;
          _currentLng = null;
          _currentSpeedMs = null;
          _status = '网络暂时不可用，已加入离线同步队列，联网后自动提交';
        });
        widget.onSportActiveChanged?.call(false);
      } else {
        setState(() => _status = friendlyErrorMsg(error));
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  final _durationController = TextEditingController();
  final _distanceController = TextEditingController();
  final _calorieController = TextEditingController();
  final _noteController = TextEditingController();

  Future<Map<String, dynamic>?> _showManualCheckinForm() async {
    return showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: SingleChildScrollView(
          child: Padding(
            padding: EdgeInsets.only(
              bottom: MediaQuery.of(ctx).viewInsets.bottom,
              left: 16,
              right: 16,
              top: 16,
            ),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Text('手动打卡',
                  style: Theme.of(ctx)
                      .textTheme
                      .titleLarge
                      ?.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: 16),
              TextField(
                decoration: const InputDecoration(
                    labelText: '运动时长（分钟）',
                    prefixIcon: Icon(Icons.timer_outlined)),
                keyboardType: TextInputType.number,
                controller: _durationController,
              ),
              const SizedBox(height: 12),
              TextField(
                decoration: const InputDecoration(
                    labelText: '运动距离（公里，可选）',
                    prefixIcon: Icon(Icons.route_outlined)),
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                controller: _distanceController,
              ),
              const SizedBox(height: 12),
              TextField(
                decoration: const InputDecoration(
                    labelText: '消耗卡路里（可选）',
                    prefixIcon: Icon(Icons.bolt_outlined)),
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                controller: _calorieController,
              ),
              const SizedBox(height: 12),
              TextField(
                decoration: const InputDecoration(
                    labelText: '备注（可选）',
                    prefixIcon: Icon(Icons.notes_outlined)),
                controller: _noteController,
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: () {
                  final duration = int.tryParse(_durationController.text) ?? 30;
                  if (duration <= 0 || duration > 1440) {
                    ScaffoldMessenger.of(ctx).showSnackBar(
                      const SnackBar(content: Text('运动时长必须在 1-1440 分钟之间')),
                    );
                    return;
                  }
                  Navigator.pop(ctx, {
                    'durationMinutes': duration,
                    'distanceKm': double.tryParse(_distanceController.text),
                    'calorie': double.tryParse(_calorieController.text),
                    'note': _noteController.text,
                  });
                },
                child: const Text('提交'),
              ),
              const SizedBox(height: 16),
            ]),
          ),
        ),
      ),
    );
  }

  Future<bool> _ensureLocationPermission() async {
    final permission = await widget.locationService.checkPermission();
    if (_canUseLocation(permission)) {
      return true;
    }
    if (permission == LocationPermission.denied) {
      final result = await widget.locationService.requestPermission();
      if (_canUseLocation(result)) {
        return true;
      }
    }
    if (mounted) {
      setState(() => _status = '需要位置权限才能使用GPS打卡');
    }
    return false;
  }

  bool _canUseLocation(LocationPermission permission) {
    return permission == LocationPermission.always ||
        permission == LocationPermission.whileInUse;
  }

  bool _hasUsableAccuracy(Position position) {
    return position.accuracy.isFinite &&
        position.accuracy >= 0 &&
        position.accuracy <= _maxAcceptedAccuracyMeters;
  }

  Future<bool> _uploadTrackPoint(String sessionId, Position position) async {
    if (!_hasUsableAccuracy(position)) {
      if (mounted) {
        setState(() {
          _status =
              'GPS精度不足，已忽略本次轨迹点（${position.accuracy.toStringAsFixed(1)}m）';
        });
      }
      return false;
    }

    await widget.api.uploadTrackPoint(
      token: widget.session.token,
      point: TrackPoint(
        sessionId: sessionId,
        lat: position.latitude,
        lng: position.longitude,
        accuracy: position.accuracy,
        timestamp: position.timestamp,
      ),
    );
    return true;
  }

  /// Haversine 公式计算两点间距离 (km)
  double _haversineKm(double lat1, double lng1, double lat2, double lng2) {
    const r = 6371.0;
    final dLat = _degToRad(lat2 - lat1);
    final dLng = _degToRad(lng2 - lng1);
    final a = sin(dLat / 2) * sin(dLat / 2) +
        cos(_degToRad(lat1)) * cos(_degToRad(lat2)) *
            sin(dLng / 2) * sin(dLng / 2);
    return r * 2 * atan2(sqrt(a), sqrt(1 - a));
  }

  double _degToRad(double deg) => deg * pi / 180.0;

  void _startGpsTracking(String sessionId) {
    const throttleSeconds = 5;
    DateTime? lastUpload;
    final generation = ++_trackingGeneration;

    _positionSubscription = widget.locationService
        .getPositionStream(
      settings: const LocationSettings(
        accuracy: LocationAccuracy.bestForNavigation,
        distanceFilter: 10,
      ),
    )
        .listen((position) {
      if (!_isCurrentTrackingSession(generation, sessionId) || _isPaused) {
        return;
      }
      final now = DateTime.now();

      // 更新实时位置和精度
      if (mounted) {
        setState(() {
          _currentLat = position.latitude;
          _currentLng = position.longitude;
          _currentAccuracy = position.accuracy;
        });
      }

      if (!_hasUsableAccuracy(position)) {
        if (mounted) {
          setState(() {
            _status =
                'GPS精度不足 (${position.accuracy.toStringAsFixed(1)}m)，已忽略';
          });
        }
        return;
      }

      // 计算实时距离增量
      if (_lastLat != null && _lastLng != null) {
        final segKm = _haversineKm(
            _lastLat!, _lastLng!, position.latitude, position.longitude);
        if (mounted) {
          setState(() => _totalDistanceKm += segKm);
        }
      }
      _lastLat = position.latitude;
      _lastLng = position.longitude;

      // 计算当前速度 (m/s)
      if (position.speed >= 0) {
        if (mounted) setState(() => _currentSpeedMs = position.speed);
      }

      // 节流上传
      if (lastUpload != null &&
          now.difference(lastUpload!).inSeconds < throttleSeconds) {
        return;
      }
      lastUpload = now;

      // 异步上传到后端
      _uploadTrackPoint(sessionId, position).then((_) {
        if (!_isCurrentTrackingSession(generation, sessionId)) return;
        _trackPointCount++;
        if (mounted) {
          setState(() {
            _status = 'GPS 打卡进行中，已上传 $_trackPointCount 个轨迹点';
          });
        }
      }).catchError((error) {
        if (mounted) {
          setState(() => _status = 'GPS轨迹点上传失败：${friendlyErrorMsg(error)}');
        }
      });
    }, onError: (Object error) {
      if (!_isCurrentTrackingSession(generation, sessionId)) return;
      if (mounted) {
        setState(() => _status = 'GPS定位失败：${friendlyErrorMsg(error)}');
      }
    });
  }

  void _startElapsedTimer() {
    _elapsedTimer?.cancel();
    _elapsedTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_isPaused || !mounted) return;
      setState(() => _activeSeconds++);
    });
  }

  void _togglePause() {
    if (!_isPaused) {
      setState(() {
        _isPaused = true;
        _status = 'GPS 打卡已暂停';
      });
    } else {
      setState(() {
        _isPaused = false;
        _status = 'GPS 打卡进行中，已上传 $_trackPointCount 个轨迹点';
      });
    }
  }

  String _formatDuration(int totalSeconds) {
    final h = totalSeconds ~/ 3600;
    final m = (totalSeconds % 3600) ~/ 60;
    final s = totalSeconds % 60;
    if (h > 0) return '$h时${m.toString().padLeft(2, '0')}分${s.toString().padLeft(2, '0')}秒';
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  String _formatPace(int totalSeconds, double distanceKm) {
    if (distanceKm < 0.01) return '--';
    final paceSeconds = totalSeconds / distanceKm;
    final paceMin = paceSeconds ~/ 60;
    final paceSec = (paceSeconds % 60).toInt();
    return '$paceMin\'${paceSec.toString().padLeft(2, '0')}"';
  }

  bool _isCurrentTrackingSession(int generation, String sessionId) {
    return _trackingGeneration == generation && _sessionId == sessionId;
  }

  Future<void> _stopGpsTracking() {
    _trackingGeneration++;
    final subscription = _positionSubscription;
    _positionSubscription = null;
    if (subscription != null) {
      unawaited(subscription.cancel());
    }
    _elapsedTimer?.cancel();
    _elapsedTimer = null;
    return Future.value();
  }

  Future<void> _showAppealSheet(int recordId) async {
    final reason = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (context) {
        return _AppealFormSheet(
          api: widget.api,
          token: widget.session.token,
          recordId: recordId,
        );
      },
    );
    if (reason != null && mounted) {
      setState(() {
        _appealFuture = widget.api.listAppeals(token: widget.session.token);
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('申诉已提交')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final running = _sessionId != null;
    final lastRecord = _lastRecord;
    return _PageScaffold(
      title: '运动打卡',
      children: [
        if (!running) ...[
          Card(
            margin: const EdgeInsets.only(bottom: 12),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('选择运动类型：',
                      style: Theme.of(context).textTheme.labelLarge),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String>(
                    initialValue: _selectedSportType,
                    decoration: const InputDecoration(
                      prefixIcon: Icon(Icons.fitness_center_outlined),
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    items: _sportTypes.entries
                        .map((e) => DropdownMenuItem(
                              value: e.key,
                              child: Text(e.value),
                            ))
                        .toList(),
                    onChanged: (v) => setState(() => _selectedSportType = v!),
                  ),
                ],
              ),
            ),
          ),
        ],
        FilledButton.icon(
          key: const Key('sport-session-toggle'),
          onPressed: _busy || _photoUploading ? null : _toggle,
          icon: Icon(running ? Icons.stop : Icons.play_arrow),
          label: Text(running ? '结束打卡' : '开始打卡'),
        ),
        if (_photoUploading)
          const Padding(
            padding: EdgeInsets.only(top: 8),
            child: LinearProgressIndicator(),
          ),
        _MetricCard(
            label: '当前状态', value: _status, icon: Icons.sensors_outlined),
        _MetricCard(
            label: '运动类型',
            value: _sportTypes[_selectedSportType] ?? _selectedSportType,
            icon: Icons.fitness_center_outlined),
        _MetricCard(
            label: '打卡方式',
            value: running
                ? _checkinModeLabel(_selectedCheckinMode)
                : 'GPS / 传感器 / 拍照 / 手动',
            icon: Icons.tune_outlined),
        // GPS 实时指标
        if (running && _selectedCheckinMode == 'gps') ...[
          _MetricCard(
              label: '已用时间',
              value: _formatDuration(_activeSeconds),
              icon: Icons.timer_outlined),
          if (_currentLat != null)
            _MetricCard(
                label: '当前位置',
                value: '${_currentLat!.toStringAsFixed(5)}, ${_currentLng!.toStringAsFixed(5)}',
                icon: Icons.my_location),
          _MetricCard(
              label: '轨迹点数',
              value: '$_trackPointCount 个',
              icon: Icons.route_outlined),
          _MetricCard(
              label: '估算距离',
              value: '${_totalDistanceKm.toStringAsFixed(2)} km',
              icon: Icons.straighten_outlined),
          if (_currentSpeedMs != null)
            _MetricCard(
                label: '当前速度',
                value: '${(_currentSpeedMs! * 3.6).toStringAsFixed(1)} km/h',
                icon: Icons.speed_outlined),
          _MetricCard(
              label: '平均配速',
              value: _formatPace(_activeSeconds, _totalDistanceKm),
              icon: Icons.trending_down_outlined),
          if (_currentAccuracy != null && _currentAccuracy! > _maxAcceptedAccuracyMeters)
            _MetricCard(
                label: 'GPS 精度',
                value: '${_currentAccuracy!.toStringAsFixed(1)}m（信号弱）',
                icon: Icons.warning_amber_outlined),
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _togglePause,
                    icon: Icon(_isPaused ? Icons.play_arrow : Icons.pause),
                    label: Text(_isPaused ? '继续' : '暂停'),
                  ),
                ),
              ],
            ),
          ),
        ],
        if (running && _selectedCheckinMode == 'sensor') ...[
          _MetricCard(
              label: '当前步数',
              value: '$_stepCount 步',
              icon: Icons.directions_walk),
        ],
        if (running &&
            _selectedCheckinMode == 'photo' &&
            _photoUrl != null) ...[
          const _MetricCard(
              label: '打卡照片', value: '已上传', icon: Icons.check_circle_outline),
        ],
        if (lastRecord != null) ...[
          _MetricCard(
            label: '最近一次',
            value:
                '${(lastRecord.durationSeconds / 60).round()} 分钟 / ${lastRecord.calorie.toStringAsFixed(1)} kcal',
            icon: Icons.route_outlined,
          ),
          if (lastRecord.status == _statusAbnormal)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: Theme.of(context).colorScheme.errorContainer,
                  foregroundColor:
                      Theme.of(context).colorScheme.onErrorContainer,
                ),
                icon: const Icon(Icons.report_problem_outlined),
                label: const Text('对本次记录提起申诉'),
                onPressed: () => _showAppealSheet(lastRecord.recordId),
              ),
            ),
          FutureBuilder<AppealListResponse>(
            future: _appealFuture,
            builder: (context, snapshot) {
              final appeals =
                  snapshot.data?.appeals ?? const <AppealResponse>[];
              if (appeals.isEmpty) return const SizedBox.shrink();
              return Card(
                margin: const EdgeInsets.only(bottom: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                      child: Row(
                        children: [
                          const Icon(Icons.fact_check_outlined, size: 18),
                          const SizedBox(width: 8),
                          Text(
                            '我的申诉 (${appeals.length})',
                            style: Theme.of(context).textTheme.titleSmall,
                          ),
                        ],
                      ),
                    ),
                    ...appeals.take(5).map((a) => ListTile(
                          dense: true,
                          leading: Icon(
                            _appealStatusIcon(a.status),
                            color: _appealStatusColor(context, a.status),
                          ),
                          title: Text(
                            '记录 #${a.recordId}',
                            style: const TextStyle(fontSize: 13),
                          ),
                          subtitle: Text(
                            a.reason,
                            style: const TextStyle(fontSize: 12),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          trailing: Text(
                            a.statusLabel,
                            style: TextStyle(
                              fontSize: 12,
                              color: _appealStatusColor(context, a.status),
                            ),
                          ),
                        )),
                  ],
                ),
              );
            },
          ),
        ],
      ],
    );
  }
}

IconData _appealStatusIcon(String status) {
  switch (status) {
    case 'pending':
      return Icons.hourglass_empty;
    case 'approved':
      return Icons.check_circle_outline;
    case 'rejected':
      return Icons.cancel_outlined;
    default:
      return Icons.help_outline;
  }
}

Color _appealStatusColor(BuildContext context, String status) {
  switch (status) {
    case 'pending':
      return Colors.orange;
    case 'approved':
      return Colors.green;
    case 'rejected':
      return Theme.of(context).colorScheme.error;
    default:
      return Colors.grey;
  }
}

class _AppealFormSheet extends StatefulWidget {
  const _AppealFormSheet({
    required this.api,
    required this.token,
    required this.recordId,
  });

  final FitLoopApi api;
  final String token;
  final int recordId;

  @override
  State<_AppealFormSheet> createState() => _AppealFormSheetState();
}

class _AppealFormSheetState extends State<_AppealFormSheet> {
  final _reason = TextEditingController();
  bool _busy = false;
  String? _message;

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final reason = _reason.text.trim();
    if (reason.isEmpty) {
      setState(() => _message = '请输入申诉理由');
      return;
    }
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      await widget.api.createAppeal(
        token: widget.token,
        recordId: widget.recordId,
        reason: reason,
      );
      if (mounted) Navigator.of(context).pop(reason);
    } catch (e) {
      setState(() => _message = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(20, 20, 20, 20 + bottomInset),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              '提起申诉',
              style: Theme.of(context)
                  .textTheme
                  .titleLarge
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Text('记录 #${widget.recordId}',
                style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 16),
            TextField(
              controller: _reason,
              enabled: !_busy,
              maxLines: 4,
              decoration: const InputDecoration(
                hintText: '请描述申诉理由（如：GPS信号异常、实际已完成运动等）',
                prefixIcon: Icon(Icons.edit_note_outlined),
                border: OutlineInputBorder(),
              ),
            ),
            if (_message != null) ...[
              const SizedBox(height: 12),
              Text(_message!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ],
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _busy ? null : _submit,
              icon: _busy
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.send),
              label: const Text('提交申诉'),
            ),
          ],
        ),
      ),
    );
  }
}

class StatsPage extends StatefulWidget {
  const StatsPage({super.key, required this.api, required this.session});

  final FitLoopApi api;
  final UserSession session;

  @override
  State<StatsPage> createState() => _StatsPageState();
}

class _StatsPageState extends State<StatsPage> {
  Future<SportStats>? _summaryFuture;
  Future<SportHistoryResponse>? _historyFuture;
  Future<WeightHistoryResponse>? _weightFuture;
  final List<HealthData> _healthTrend = [];

  HealthData? get _lastHealthData =>
      _healthTrend.isEmpty ? null : _healthTrend.last;

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  void _loadAll() {
    final token = widget.session.token;
    setState(() {
      _summaryFuture = widget.api.sportStats(token: token);
      _historyFuture = widget.api.sportHistory(token: token);
      _weightFuture = widget.api.weightHistory(token: token);
    });
  }

  Future<void> _showHealthDataSheet() async {
    final healthData = await showModalBottomSheet<HealthData>(
      context: context,
      isScrollControlled: true,
      builder: (context) {
        return _HealthDataFormSheet(
          api: widget.api,
          token: widget.session.token,
        );
      },
    );
    if (healthData != null && mounted) {
      setState(() {
        _healthTrend.add(healthData);
        // 刷新体重趋势
        _weightFuture = widget.api.weightHistory(token: widget.session.token);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<SportStats>(
      future: _summaryFuture,
      builder: (context, snapshot) {
        final stats = snapshot.data;
        return _PageScaffold(
          title: '健康统计',
          children: [
            FilledButton.icon(
              onPressed: _loadAll,
              icon: const Icon(Icons.refresh),
              label: const Text('刷新统计'),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: _showHealthDataSheet,
              icon: const Icon(Icons.monitor_heart_outlined),
              label: const Text('记录健康数据'),
            ),
            if (_lastHealthData != null) ...[
              const SizedBox(height: 12),
              _MetricCard(
                label: '最近健康记录',
                value: _formatHealthData(_lastHealthData!),
                icon: Icons.favorite_outline,
              ),
            ],
            if (snapshot.hasError)
              _MetricCard(
                  label: '统计状态',
                  value: friendlyErrorMsg(snapshot.error),
                  icon: Icons.error_outline)
            else if (!snapshot.hasData)
              const _MetricCard(
                  label: '统计状态', value: '加载中', icon: Icons.hourglass_empty)
            else ...[
              _MetricCard(
                  label: '运动次数',
                  value: '${stats!.checkinCount} 次',
                  icon: Icons.calendar_month_outlined),
              _MetricCard(
                  label: '总里程',
                  value: '${stats.distanceKm.toStringAsFixed(1)} km',
                  icon: Icons.route_outlined),
              _MetricCard(
                  label: '消耗',
                  value: '${stats.calorie.toStringAsFixed(1)} kcal',
                  icon: Icons.bolt_outlined),
              // 历史图表 — 真实每日数据
              FutureBuilder<SportHistoryResponse>(
                future: _historyFuture,
                builder: (context, histSnapshot) {
                  if (histSnapshot.hasData) {
                    return Column(children: [
                      WorkoutCountChartCard(history: histSnapshot.data!),
                      DistanceCalorieChartCard(history: histSnapshot.data!),
                    ]);
                  }
                  if (histSnapshot.hasError) {
                    return const _MetricCard(
                        label: '历史图表',
                        value: '加载中，使用备用数据',
                        icon: Icons.warning_amber);
                  }
                  return const _MetricCard(
                      label: '历史图表', value: '加载中', icon: Icons.hourglass_empty);
                },
              ),
              // 体重趋势
              FutureBuilder<WeightHistoryResponse>(
                future: _weightFuture,
                builder: (context, wSnapshot) {
                  if (wSnapshot.hasData) {
                    return WeightTrendChartCard(history: wSnapshot.data!);
                  }
                  return const SizedBox.shrink();
                },
              ),
            ],
          ],
        );
      },
    );
  }
}

class _HealthDataFormSheet extends StatefulWidget {
  const _HealthDataFormSheet({
    required this.api,
    required this.token,
  });

  final FitLoopApi api;
  final String token;

  @override
  State<_HealthDataFormSheet> createState() => _HealthDataFormSheetState();
}

class _HealthDataFormSheetState extends State<_HealthDataFormSheet> {
  final _weight = TextEditingController();
  final _sleep = TextEditingController();
  final _diet = TextEditingController();
  bool _busy = false;
  String? _message;

  @override
  void dispose() {
    _weight.dispose();
    _sleep.dispose();
    _diet.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final weightText = _weight.text.trim();
    final sleepText = _sleep.text.trim();
    final dietNote = _diet.text.trim();
    final weightKg = weightText.isEmpty ? null : double.tryParse(weightText);
    final sleepHours = sleepText.isEmpty ? null : double.tryParse(sleepText);

    if (weightText.isNotEmpty && (weightKg == null || weightKg <= 0)) {
      setState(() => _message = '体重必须大于 0');
      return;
    }
    if (sleepText.isNotEmpty && (sleepHours == null || sleepHours <= 0)) {
      setState(() => _message = '睡眠小时必须大于 0');
      return;
    }
    if (weightKg == null && sleepHours == null && dietNote.isEmpty) {
      setState(() => _message = '请至少填写一项健康数据');
      return;
    }

    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      final healthData = await widget.api.addHealthData(
        token: widget.token,
        weightKg: weightKg,
        sleepHours: sleepHours,
        dietNote: dietNote.isEmpty ? null : dietNote,
        dataDate: _todayText(),
      );
      if (mounted) {
        Navigator.of(context).pop(healthData);
      }
    } catch (error) {
      setState(() => _message = friendlyErrorMsg(error));
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(20, 20, 20, 20 + bottomInset),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              '记录健康数据',
              style: Theme.of(context)
                  .textTheme
                  .titleLarge
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _weight,
              enabled: !_busy,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.monitor_weight_outlined),
                labelText: '体重 kg',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _sleep,
              enabled: !_busy,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.bedtime_outlined),
                labelText: '睡眠小时',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _diet,
              enabled: !_busy,
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.restaurant_outlined),
                labelText: '饮食备注',
              ),
            ),
            if (_message != null) ...[
              const SizedBox(height: 12),
              Text(_message!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ],
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _busy ? null : _submit,
              icon: _busy
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.check),
              label: const Text('保存健康数据'),
            ),
          ],
        ),
      ),
    );
  }
}

String _todayText() {
  final now = DateTime.now();
  final month = now.month.toString().padLeft(2, '0');
  final day = now.day.toString().padLeft(2, '0');
  return '${now.year}-$month-$day';
}

String _formatHealthData(HealthData data) {
  final parts = <String>[];
  if (data.weightKg != null) {
    parts.add('体重 ${_formatNumber(data.weightKg!)} kg');
  }
  if (data.sleepHours != null) {
    parts.add('睡眠 ${_formatNumber(data.sleepHours!)} 小时');
  }
  final dietNote = data.dietNote;
  if (dietNote != null && dietNote.isNotEmpty) {
    parts.add('饮食 $dietNote');
  }
  return '${data.dataDate}：${parts.join(' / ')}';
}

class SocialPage extends StatefulWidget {
  const SocialPage({super.key, required this.api, required this.session});

  final FitLoopApi api;
  final UserSession session;

  @override
  State<SocialPage> createState() => _SocialPageState();
}

class _SocialPageState extends State<SocialPage> {
  Future<_SocialSnapshot>? _future;
  Future<FriendListResponse>? _friendFuture;
  final _searchController = TextEditingController();
  List<UserSearchItem> _searchResults = [];
  bool _searching = false;

  @override
  void initState() {
    super.initState();
    _future = _loadSocial();
    _friendFuture = _loadFriends();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<_SocialSnapshot> _loadSocial() async {
    final medal = await widget.api.medalSummary(token: widget.session.token);
    final ranking = await widget.api.ranking(token: widget.session.token);
    return _SocialSnapshot(medal: medal, ranking: ranking);
  }

  Future<FriendListResponse> _loadFriends() {
    return widget.api.listFriends(token: widget.session.token);
  }

  void _refresh() {
    setState(() {
      _future = _loadSocial();
      _friendFuture = _loadFriends();
      _searchResults = [];
    });
  }

  Future<void> _doSearch() async {
    final q = _searchController.text.trim();
    if (q.isEmpty) {
      setState(() => _searchResults = []);
      return;
    }
    setState(() => _searching = true);
    try {
      final resp = await widget.api.searchUsers(
        token: widget.session.token,
        query: q,
      );
      if (mounted) setState(() => _searchResults = resp.users);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(friendlyErrorMsg(e))),
        );
      }
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  Future<void> _addFriend(int userId) async {
    try {
      await widget.api.addFriend(
        token: widget.session.token,
        friendUserId: userId,
      );
      _refresh();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(friendlyErrorMsg(e))),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return _PageScaffold(
      title: '校园激励',
      children: [
        // 搜索栏
        Card(
          margin: const EdgeInsets.only(bottom: 12),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _searchController,
                    decoration: const InputDecoration(
                      hintText: '搜索好友（昵称或手机号）',
                      prefixIcon: Icon(Icons.search_outlined),
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    onSubmitted: (_) => _doSearch(),
                  ),
                ),
                const SizedBox(width: 8),
                _searching
                    ? const SizedBox.square(
                        dimension: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : IconButton(
                        icon: const Icon(Icons.send_outlined),
                        onPressed: _doSearch,
                      ),
              ],
            ),
          ),
        ),

        // 搜索结果
        if (_searchResults.isNotEmpty) ...[
          Card(
            margin: const EdgeInsets.only(bottom: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                  child: Text('搜索结果',
                      style: Theme.of(context).textTheme.titleSmall),
                ),
                ..._searchResults.map((user) => ListTile(
                      leading: CircleAvatar(child: Text(user.nickname[0])),
                      title: Text(user.nickname),
                      subtitle: Text('Lv.${user.level} · ${user.points} 积分'),
                      trailing: user.isFriend
                          ? const Chip(
                              avatar: Icon(Icons.check, size: 16),
                              label:
                                  Text('已是好友', style: TextStyle(fontSize: 12)),
                            )
                          : FilledButton.tonalIcon(
                              icon: const Icon(Icons.person_add, size: 18),
                              label: const Text('添加',
                                  style: TextStyle(fontSize: 12)),
                              onPressed: () => _addFriend(user.userId),
                            ),
                    )),
              ],
            ),
          ),
        ],

        // 好友列表
        FutureBuilder<FriendListResponse>(
          future: _friendFuture,
          builder: (context, snapshot) {
            final friends = snapshot.data?.friends ?? const <FriendInfo>[];
            if (friends.isEmpty) return const SizedBox.shrink();
            return Card(
              margin: const EdgeInsets.only(bottom: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                    child: Row(
                      children: [
                        Text('我的好友 (${friends.length})',
                            style: Theme.of(context).textTheme.titleSmall),
                        const Spacer(),
                        IconButton(
                          icon: const Icon(Icons.refresh, size: 18),
                          onPressed: _refresh,
                        ),
                      ],
                    ),
                  ),
                  ...friends.map((f) => ListTile(
                        leading: CircleAvatar(child: Text(f.nickname[0])),
                        title: Text(f.nickname),
                        subtitle: Text('Lv.${f.level} · ${f.points} 积分'),
                      )),
                ],
              ),
            );
          },
        ),

        // 激励数据
        FilledButton.icon(
          onPressed: _refresh,
          icon: const Icon(Icons.refresh),
          label: const Text('刷新激励数据'),
        ),
        const SizedBox(height: 12),
        FutureBuilder<_SocialSnapshot>(
          future: _future,
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return _MetricCard(
                label: '激励状态',
                value: friendlyErrorMsg(snapshot.error),
                icon: Icons.error_outline,
              );
            }
            final data = snapshot.data;
            if (data == null) {
              return const _MetricCard(
                label: '激励状态',
                value: '加载中',
                icon: Icons.hourglass_empty,
              );
            }
            return _SocialContent(snapshot: data);
          },
        ),
      ],
    );
  }
}

class _SocialSnapshot {
  const _SocialSnapshot({required this.medal, required this.ranking});

  final MedalSummary medal;
  final RankingResult ranking;
}

class _SocialContent extends StatelessWidget {
  const _SocialContent({required this.snapshot});

  final _SocialSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final medals = snapshot.medal.medals;
    final rankingRows = snapshot.ranking.rows;
    return Column(
      children: [
        _MetricCard(
          label: '积分等级',
          value: '${snapshot.medal.points} 积分 / Lv.${snapshot.medal.level}',
          icon: Icons.workspace_premium_outlined,
        ),
        _MetricCard(
          label: '我的勋章',
          value: medals.isEmpty ? '暂无勋章' : medals.join('、'),
          icon: Icons.military_tech_outlined,
        ),
        if (rankingRows.isEmpty)
          const _MetricCard(
            label: '排行榜',
            value: '暂无排行数据',
            icon: Icons.leaderboard_outlined,
          )
        else
          ...rankingRows.take(5).map(
                (row) => _MetricCard(
                  label: '第 ${row.rank} 名',
                  value:
                      '${row.nickname} / ${row.distanceKm.toStringAsFixed(1)} km / ${row.calorie.toStringAsFixed(1)} kcal',
                  icon: Icons.leaderboard_outlined,
                ),
              ),
      ],
    );
  }
}

class ProfilePage extends StatefulWidget {
  const ProfilePage({
    super.key,
    required this.api,
    required this.reminderScheduler,
    required this.session,
    this.onLogout,
  });

  final FitLoopApi api;
  final ReminderScheduler reminderScheduler;
  final UserSession session;
  final VoidCallback? onLogout;

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  Future<ReminderListResponse>? _future;
  String? _avatarUrl;
  bool _uploading = false;

  @override
  void initState() {
    super.initState();
    _future = widget.api.listReminders(token: widget.session.token);
    _avatarUrl = widget.session.avatarUrl;
    if (_avatarUrl == null) {
      _loadCachedAvatar();
    }
  }

  Future<void> _loadCachedAvatar() async {
    final prefs = await SharedPreferences.getInstance();
    final cached = prefs.getString('avatarUrl_${widget.session.userId}');
    if (cached != null && mounted) {
      setState(() => _avatarUrl = cached);
    }
  }

  Future<void> _pickAndUploadAvatar() async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (context) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.camera_alt_outlined),
              title: const Text('拍照'),
              onTap: () => Navigator.of(context).pop(ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('从相册选择'),
              onTap: () => Navigator.of(context).pop(ImageSource.gallery),
            ),
          ],
        ),
      ),
    );
    if (source == null || !mounted) return;

    final picker = ImagePicker();
    final xFile = await picker.pickImage(
      source: source,
      maxWidth: 512,
      maxHeight: 512,
      imageQuality: 85,
    );
    if (xFile == null || !mounted) return;

    setState(() => _uploading = true);
    try {
      final url = await widget.api.uploadAvatar(
        token: widget.session.token,
        imagePath: xFile.path,
      );
      if (!mounted) return;
      setState(() {
        _avatarUrl = url;
        _uploading = false;
      });
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('avatarUrl_${widget.session.userId}', url);
    } catch (e) {
      if (!mounted) return;
      setState(() => _uploading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(friendlyErrorMsg(e))),
      );
    }
  }

  Future<void> _openSettings(String type, String label, IconData icon) async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => _ReminderSettingsPage(
          api: widget.api,
          reminderScheduler: widget.reminderScheduler,
          token: widget.session.token,
          type: type,
          label: label,
          icon: icon,
        ),
      ),
    );
    if (changed == true && mounted) {
      setState(() =>
          _future = widget.api.listReminders(token: widget.session.token));
    }
  }

  @override
  Widget build(BuildContext context) {
    return _PageScaffold(
      title: '我的',
      children: [
        Card(
          margin: const EdgeInsets.only(bottom: 12),
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: _uploading ? null : _pickAndUploadAvatar,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
              child: Row(
                children: [
                  _AvatarWidget(
                    avatarUrl: _avatarUrl,
                    uploading: _uploading,
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.session.nickname,
                          style: Theme.of(context)
                              .textTheme
                              .titleMedium
                              ?.copyWith(fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _uploading ? '上传中...' : '点击更换头像',
                          style:
                              Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSurfaceVariant,
                                  ),
                        ),
                      ],
                    ),
                  ),
                  if (_uploading)
                    const SizedBox.square(
                      dimension: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  else
                    Icon(
                      Icons.chevron_right,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                ],
              ),
            ),
          ),
        ),
        _MetricCard(
            label: '账号状态',
            value: '已登录：${widget.session.nickname}',
            icon: Icons.verified_user_outlined),
        FutureBuilder<ReminderListResponse>(
          future: _future,
          builder: (context, snapshot) {
            final reminders =
                snapshot.data?.reminders ?? const <ReminderConfig>[];
            ReminderConfig? findByType(String t) {
              return reminders.where((r) => r.type == t).firstOrNull;
            }

            const items = [
              _ReminderTileData('sport', '运动', Icons.directions_run_outlined,
                  Icons.timer_outlined),
              _ReminderTileData('sit', '久坐', Icons.chair_outlined,
                  Icons.access_time_outlined),
              _ReminderTileData('drink', '喝水', Icons.water_drop_outlined,
                  Icons.local_drink_outlined),
              _ReminderTileData('sleep', '睡眠', Icons.bedtime_outlined,
                  Icons.nightlight_outlined),
            ];

            return Card(
              margin: const EdgeInsets.only(bottom: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                    child: Text('提醒设置',
                        style:
                            Theme.of(context).textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w700,
                                )),
                  ),
                  ...items.map((item) {
                    final config = findByType(item.type);
                    final enabled = config?.enabled ?? false;
                    final timeDisplay =
                        config?.time?.substring(0, 5) ?? '--:--';
                    return ListTile(
                      leading: Icon(
                          enabled ? item.filledIcon : item.outlineIcon,
                          color: enabled
                              ? Theme.of(context).colorScheme.primary
                              : null),
                      title: Text(item.label),
                      subtitle: Text(enabled ? '已开启 · $timeDisplay' : '关闭'),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => _openSettings(
                          item.type, item.label, item.outlineIcon),
                    );
                  }),
                ],
              ),
            );
          },
        ),
        Card(
          margin: const EdgeInsets.only(bottom: 12),
          child: Column(
            children: [
              ListTile(
                leading: const Icon(Icons.settings_outlined),
                title: const Text('设置'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () async {
                  await Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => SettingsPage(
                        session: widget.session,
                        api: widget.api,
                        onLogout: widget.onLogout,
                      ),
                    ),
                  );
                },
              ),
              const Divider(height: 1, indent: 16, endIndent: 16),
              ListTile(
                leading: const Icon(Icons.feedback_outlined),
                title: const Text('意见反馈'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () async {
                  await Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => _FeedbackPage(
                        api: widget.api,
                        token: widget.session.token,
                      ),
                    ),
                  );
                },
              ),
              const Divider(height: 1, indent: 16, endIndent: 16),
              ListTile(
                leading: Icon(Icons.logout,
                    color: Theme.of(context).colorScheme.error),
                title: Text('退出登录',
                    style:
                        TextStyle(color: Theme.of(context).colorScheme.error)),
                onTap: () => _showLogoutDialog(context),
              ),
            ],
          ),
        ),
      ],
    );
  }

  void _showLogoutDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('退出登录'),
        content: const Text('确定要退出当前账号吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              widget.onLogout?.call();
            },
            child: const Text('确定退出'),
          ),
        ],
      ),
    );
  }
}

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key, required this.session, required this.api, this.onLogout});

  final UserSession session;
  final FitLoopApi api;
  final VoidCallback? onLogout;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('设置')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Card(
            margin: const EdgeInsets.only(bottom: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                  child: Text('账号信息',
                      style: Theme.of(context)
                          .textTheme
                          .titleMedium
                          ?.copyWith(fontWeight: FontWeight.w700)),
                ),
                _InfoRow(label: '昵称', value: session.nickname),
                _InfoRow(
                    label: '用户ID', value: session.userId.toString()),
                if (session.avatarUrl != null)
                  const _InfoRow(label: '头像', value: '已设置'),
              ],
            ),
          ),
          Card(
            margin: const EdgeInsets.only(bottom: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                  child: Text('关于',
                      style: Theme.of(context)
                          .textTheme
                          .titleMedium
                          ?.copyWith(fontWeight: FontWeight.w700)),
                ),
                const _InfoRow(label: '应用名称', value: 'FitLoop'),
                const _InfoRow(label: '版本', value: '0.1.0'),
                const _InfoRow(label: '构建号', value: '1'),
              ],
            ),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: () => _showAdminLogin(context),
            icon: const Icon(Icons.admin_panel_settings_outlined),
            label: const Text('管理后台'),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: () {
              Navigator.of(context).pop();
              onLogout?.call();
            },
            icon: const Icon(Icons.logout),
            label: const Text('退出登录'),
            style: OutlinedButton.styleFrom(
              foregroundColor: Theme.of(context).colorScheme.error,
            ),
          ),
        ],
      ),
    );
  }

  void _showAdminLogin(BuildContext context) {
    final keyController = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('管理后台'),
        content: TextField(
          controller: keyController,
          obscureText: true,
          decoration: const InputDecoration(
            labelText: '管理员密钥',
            hintText: '请输入 Admin Key',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () async {
              final key = keyController.text.trim();
              if (key.isEmpty) return;
              Navigator.pop(ctx);
              // 验证 admin key
              try {
                await api.adminGetStats(adminKey: key);
                if (!context.mounted) return;
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => _AdminDashboardPage(
                      api: api,
                      adminKey: key,
                    ),
                  ),
                );
              } catch (e) {
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('管理后台访问失败: ${friendlyErrorMsg(e)}')),
                );
              }
            },
            child: const Text('进入'),
          ),
        ],
      ),
    );
  }
}

class _AdminDashboardPage extends StatefulWidget {
  const _AdminDashboardPage({required this.api, required this.adminKey});
  final FitLoopApi api;
  final String adminKey;

  @override
  State<_AdminDashboardPage> createState() => _AdminDashboardPageState();
}

class _AdminDashboardPageState extends State<_AdminDashboardPage> {
  int _tabIndex = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('管理后台')),
      body: IndexedStack(
        index: _tabIndex,
        children: [
          _AdminStatsTab(api: widget.api, adminKey: widget.adminKey),
          _AdminUsersTab(api: widget.api, adminKey: widget.adminKey),
          _AdminFeedbackTab(api: widget.api, adminKey: widget.adminKey),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tabIndex,
        onDestinationSelected: (i) => setState(() => _tabIndex = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.dashboard), label: '概览'),
          NavigationDestination(icon: Icon(Icons.people), label: '用户'),
          NavigationDestination(icon: Icon(Icons.feedback), label: '反馈'),
        ],
      ),
    );
  }
}

class _AdminStatsTab extends StatelessWidget {
  const _AdminStatsTab({required this.api, required this.adminKey});
  final FitLoopApi api;
  final String adminKey;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<AdminStats>(
      future: api.adminGetStats(adminKey: adminKey),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(child: Text(friendlyErrorMsg(snapshot.error)));
        }
        final stats = snapshot.data!;
        return ListView(
          padding: const EdgeInsets.all(20),
          children: [
            _AdminStatCard(title: '总用户数', value: '${stats.totalUsers}'),
            _AdminStatCard(title: '今日新增', value: '${stats.todayNewUsers}'),
            _AdminStatCard(title: '总运动记录', value: '${stats.totalSportRecords}'),
            _AdminStatCard(title: '今日打卡', value: '${stats.todayCheckins}'),
            _AdminStatCard(
                title: '待处理反馈', value: '${stats.pendingFeedbackCount}'),
          ],
        );
      },
    );
  }
}

class _AdminStatCard extends StatelessWidget {
  const _AdminStatCard({required this.title, required this.value});
  final String title;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        title: Text(title),
        trailing: Text(value,
            style: Theme.of(context)
                .textTheme
                .headlineSmall
                ?.copyWith(fontWeight: FontWeight.w700)),
      ),
    );
  }
}

class _AdminUsersTab extends StatelessWidget {
  const _AdminUsersTab({required this.api, required this.adminKey});
  final FitLoopApi api;
  final String adminKey;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<AdminUserListResponse>(
      future: api.adminListUsers(adminKey: adminKey),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(child: Text(friendlyErrorMsg(snapshot.error)));
        }
        final users = snapshot.data!.users;
        return ListView.builder(
          padding: const EdgeInsets.all(12),
          itemCount: users.length,
          itemBuilder: (context, index) {
            final u = users[index];
            return Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                title: Text(u.nickname),
                subtitle: Text(u.email ?? u.phone ?? ''),
                trailing: Text('ID: ${u.userId}'),
                onTap: () async {
                  try {
                    final detail = await api.adminGetUserDetail(
                        adminKey: adminKey, userId: u.userId);
                    if (!context.mounted) return;
                    showDialog(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        title: Text(detail.nickname),
                        content: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('邮箱: ${detail.email ?? "-"}'),
                            Text('手机: ${detail.phone ?? "-"}'),
                            Text('运动记录: ${detail.sportRecordCount}'),
                            Text('目标数: ${detail.targetCount}'),
                            Text('注册时间: ${detail.createdAt ?? "-"}'),
                          ],
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(ctx),
                            child: const Text('关闭'),
                          ),
                        ],
                      ),
                    );
                  } catch (e) {
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(friendlyErrorMsg(e))),
                    );
                  }
                },
              ),
            );
          },
        );
      },
    );
  }
}

class _AdminFeedbackTab extends StatefulWidget {
  const _AdminFeedbackTab({required this.api, required this.adminKey});
  final FitLoopApi api;
  final String adminKey;

  @override
  State<_AdminFeedbackTab> createState() => _AdminFeedbackTabState();
}

class _AdminFeedbackTabState extends State<_AdminFeedbackTab> {
  late Future<FeedbackListResponse> _future;

  @override
  void initState() {
    super.initState();
    _future = widget.api.adminListFeedback(adminKey: widget.adminKey);
  }

  void _refresh() {
    setState(() {
      _future = widget.api.adminListFeedback(adminKey: widget.adminKey);
    });
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<FeedbackListResponse>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(child: Text(friendlyErrorMsg(snapshot.error)));
        }
        final feedbacks = snapshot.data!.feedbacks;
        if (feedbacks.isEmpty) {
          return const Center(child: Text('暂无反馈'));
        }
        return ListView.builder(
          padding: const EdgeInsets.all(12),
          itemCount: feedbacks.length,
          itemBuilder: (context, index) {
            final f = feedbacks[index];
            return Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                title: Text(f.type == 'bug' ? '问题反馈' : (f.type == 'feature' ? '功能建议' : '其他')),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(f.content, maxLines: 2, overflow: TextOverflow.ellipsis),
                    Text('状态: ${f.status}',
                        style: TextStyle(
                            color: f.status == 'pending'
                                ? Colors.orange
                                : Colors.green,
                            fontSize: 12)),
                  ],
                ),
                trailing: f.status == 'pending'
                    ? TextButton(
                        onPressed: () async {
                          try {
                            await widget.api.adminUpdateFeedback(
                              adminKey: widget.adminKey,
                              feedbackId: f.feedbackId,
                              status: 'reviewed',
                              adminNote: '已查看',
                            );
                            _refresh();
                          } catch (e) {
                            if (!context.mounted) return;
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text(friendlyErrorMsg(e))),
                            );
                          }
                        },
                        child: const Text('标记已处理'),
                      )
                    : null,
              ),
            );
          },
        );
      },
    );
  }
}

class _FeedbackPage extends StatefulWidget {
  const _FeedbackPage({required this.api, required this.token});

  final FitLoopApi api;
  final String token;

  @override
  State<_FeedbackPage> createState() => _FeedbackPageState();
}

class _FeedbackPageState extends State<_FeedbackPage> {
  final _content = TextEditingController();
  final _contact = TextEditingController();
  String _type = 'feature';
  bool _busy = false;
  String? _message;
  bool _messageIsSuccess = false;
  late Future<FeedbackListResponse> _future;

  @override
  void initState() {
    super.initState();
    _future = widget.api.listFeedback(token: widget.token);
  }

  @override
  void dispose() {
    _content.dispose();
    _contact.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final content = _content.text.trim();
    if (content.isEmpty) {
      setState(() {
        _message = '请输入反馈内容';
        _messageIsSuccess = false;
      });
      return;
    }
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      await widget.api.submitFeedback(
        token: widget.token,
        type: _type,
        content: content,
        contact: _contact.text.trim().isEmpty ? null : _contact.text.trim(),
      );
      _content.clear();
      _contact.clear();
      setState(() {
        _message = '反馈提交成功，感谢您的建议！';
        _messageIsSuccess = true;
        _future = widget.api.listFeedback(token: widget.token);
      });
    } catch (error) {
      setState(() {
        _message = friendlyErrorMsg(error);
        _messageIsSuccess = false;
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _typeLabel(String type) {
    return switch (type) {
      'bug' => '问题反馈',
      'feature' => '功能建议',
      _ => '其他',
    };
  }

  String _statusLabel(String status) {
    return switch (status) {
      'pending' => '待处理',
      'reviewed' => '已查看',
      'closed' => '已关闭',
      _ => status,
    };
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('意见反馈')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text('提交反馈',
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: _type,
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.category_outlined),
              labelText: '反馈类型',
            ),
            items: const [
              DropdownMenuItem(value: 'feature', child: Text('功能建议')),
              DropdownMenuItem(value: 'bug', child: Text('问题反馈')),
              DropdownMenuItem(value: 'other', child: Text('其他')),
            ],
            onChanged:
                _busy ? null : (value) => setState(() => _type = value ?? 'feature'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _content,
            maxLines: 4,
            maxLength: 2000,
            enabled: !_busy,
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.edit_outlined),
              labelText: '反馈内容',
              hintText: '请描述您的建议或遇到的问题...',
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _contact,
            enabled: !_busy,
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.mail_outline),
              labelText: '联系方式（选填）',
              hintText: '邮箱或手机号，方便我们回复',
            ),
          ),
          if (_message != null) ...[
            const SizedBox(height: 12),
            Text(
              _message!,
              style: TextStyle(
                color: _messageIsSuccess
                    ? Theme.of(context).colorScheme.primary
                    : Theme.of(context).colorScheme.error,
                fontSize: 13,
              ),
            ),
          ],
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _busy ? null : _submit,
            icon: _busy
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.send),
            label: const Text('提交反馈'),
          ),
          const SizedBox(height: 32),
          Text('我的反馈',
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 12),
          FutureBuilder<FeedbackListResponse>(
            future: _future,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snapshot.hasError) {
                return Text(friendlyErrorMsg(snapshot.error),
                    style: TextStyle(
                        color: Theme.of(context).colorScheme.error));
              }
              final feedbacks = snapshot.data?.feedbacks ?? [];
              if (feedbacks.isEmpty) {
                return const Card(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Center(child: Text('暂无反馈记录')),
                  ),
                );
              }
              return Column(
                children: feedbacks.map((f) => Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: ListTile(
                    title: Text(_typeLabel(f.type),
                        style: const TextStyle(fontWeight: FontWeight.w600)),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SizedBox(height: 4),
                        Text(f.content, maxLines: 3, overflow: TextOverflow.ellipsis),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Chip(
                              label: Text(_statusLabel(f.status),
                                  style: const TextStyle(fontSize: 11)),
                              padding: EdgeInsets.zero,
                              materialTapTargetSize:
                                  MaterialTapTargetSize.shrinkWrap,
                              visualDensity: VisualDensity.compact,
                            ),
                            const Spacer(),
                            Text(
                              f.createdAt.length >= 10
                                  ? f.createdAt.substring(0, 10)
                                  : f.createdAt,
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ],
                        ),
                        if (f.adminNote != null && f.adminNote!.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text('回复：${f.adminNote}',
                              style: TextStyle(
                                  color: Theme.of(context).colorScheme.primary,
                                  fontSize: 12)),
                        ],
                      ],
                    ),
                  ),
                )).toList(),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          Text(label,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  )),
          const Spacer(),
          Text(value, style: Theme.of(context).textTheme.bodyMedium),
        ],
      ),
    );
  }
}

class _ReminderTileData {
  const _ReminderTileData(
      this.type, this.label, this.outlineIcon, this.filledIcon);
  final String type;
  final String label;
  final IconData outlineIcon;
  final IconData filledIcon;
}

class _ReminderSettingsPage extends StatefulWidget {
  const _ReminderSettingsPage({
    required this.api,
    required this.reminderScheduler,
    required this.token,
    required this.type,
    required this.label,
    required this.icon,
  });

  final FitLoopApi api;
  final ReminderScheduler reminderScheduler;
  final String token;
  final String type;
  final String label;
  final IconData icon;

  @override
  State<_ReminderSettingsPage> createState() => _ReminderSettingsPageState();
}

class _ReminderSettingsPageState extends State<_ReminderSettingsPage> {
  bool _enabled = false;
  TimeOfDay _time = const TimeOfDay(hour: 8, minute: 0);
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final resp = await widget.api.listReminders(token: widget.token);
      final config =
          resp.reminders.where((r) => r.type == widget.type).firstOrNull;
      if (config != null && mounted) {
        setState(() {
          _enabled = config.enabled;
          if (config.time != null && config.time!.length >= 5) {
            final parts = config.time!.split(':');
            _time = TimeOfDay(
                hour: int.parse(parts[0]), minute: int.parse(parts[1]));
          }
        });
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(context: context, initialTime: _time);
    if (picked != null && mounted) setState(() => _time = picked);
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final timeStr =
          '${_time.hour.toString().padLeft(2, '0')}:${_time.minute.toString().padLeft(2, '0')}:00';
      await widget.api.upsertReminder(
        token: widget.token,
        remindId: 0,
        type: widget.type,
        time: timeStr,
        cycle: 'daily',
        enabled: _enabled,
      );
      if (_enabled) {
        await widget.reminderScheduler.scheduleDaily(
          type: widget.type,
          title: '${widget.label} 提醒',
          body: _reminderNotificationBody(widget.type),
          time: _time,
        );
      } else {
        await widget.reminderScheduler.cancel(widget.type);
      }
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(friendlyErrorMsg(e))),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('${widget.label} 提醒')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(20),
              children: [
                Icon(widget.icon,
                    size: 64, color: Theme.of(context).colorScheme.primary),
                const SizedBox(height: 24),
                SwitchListTile(
                  title: const Text('启用提醒'),
                  subtitle: Text(_enabled ? '每天 $_time 提醒' : '提醒已关闭'),
                  value: _enabled,
                  onChanged: (v) => setState(() => _enabled = v),
                ),
                const SizedBox(height: 12),
                ListTile(
                  leading: const Icon(Icons.access_time),
                  title: const Text('提醒时间'),
                  subtitle: Text(_time.format(context)),
                  trailing: const Icon(Icons.edit_calendar_outlined),
                  onTap: _enabled ? _pickTime : null,
                ),
                const SizedBox(height: 32),
                FilledButton.icon(
                  onPressed: _saving ? null : _save,
                  icon: _saving
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.save),
                  label: const Text('保存'),
                ),
              ],
            ),
    );
  }
}

String _reminderNotificationBody(String type) {
  switch (type) {
    case 'sport':
      return '到时间活动一下，完成今天的运动目标。';
    case 'sit':
      return '久坐太久了，起身走动和拉伸一下。';
    case 'drink':
      return '补充一杯水，让身体保持在线。';
    case 'sleep':
      return '准备休息，给明天的状态充电。';
    default:
      return 'FitLoop 提醒时间到了。';
  }
}

class _AvatarWidget extends StatelessWidget {
  const _AvatarWidget({required this.avatarUrl, required this.uploading});

  final String? avatarUrl;
  final bool uploading;

  @override
  Widget build(BuildContext context) {
    const radius = 40.0;
    if (avatarUrl != null && avatarUrl!.isNotEmpty) {
      return CircleAvatar(
        radius: radius,
        backgroundImage: NetworkImage(avatarUrl!),
      );
    }
    return Stack(
      alignment: Alignment.center,
      children: [
        const CircleAvatar(
          radius: radius,
          backgroundImage: AssetImage(FitLoopAssets.defaultAvatar),
        ),
        if (uploading)
          Container(
            width: radius * 2,
            height: radius * 2,
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.24),
              shape: BoxShape.circle,
            ),
            child: const Padding(
              padding: EdgeInsets.all(18),
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.white,
              ),
            ),
          ),
      ],
    );
  }
}

class _PageScaffold extends StatelessWidget {
  const _PageScaffold({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Text(title,
            style: Theme.of(context)
                .textTheme
                .headlineMedium
                ?.copyWith(fontWeight: FontWeight.w700)),
        const SizedBox(height: 20),
        ...children,
      ],
    );
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard(
      {required this.label, required this.value, required this.icon});

  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        leading: Icon(icon),
        title: Text(label),
        subtitle: Text(value),
      ),
    );
  }
}

class TokenStorage {
  static const _kToken = 'token';
  static const _kUid = 'uid';
  static const _kName = 'nickname';

  static Future<void> save(String token, int userId, String nickname) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_kToken, token);
    await p.setInt(_kUid, userId);
    await p.setString(_kName, nickname);
  }

  static Future<Map<String, Object>?> load() async {
    final p = await SharedPreferences.getInstance();
    final t = p.getString(_kToken);
    if (t == null || t.isEmpty) return null;
    return {
      'token': t,
      'userId': p.getInt(_kUid) ?? 0,
      'nickname': p.getString(_kName) ?? 'FitLoop �û�',
    };
  }

  static Future<void> clear() async {
    final p = await SharedPreferences.getInstance();
    await p.remove(_kToken);
    await p.remove(_kUid);
    await p.remove(_kName);
  }
}
