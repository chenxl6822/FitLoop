import 'package:flutter/material.dart';

import 'api_client.dart';

void main() {
  runApp(FitLoopApp());
}

class FitLoopApp extends StatelessWidget {
  FitLoopApp({super.key, FitLoopApi? api})
      : api = api ?? const _ApiFactory().create();

  final FitLoopApi api;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'FitLoop',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF1F8A70)),
        useMaterial3: true,
      ),
      home: AuthGate(api: api),
    );
  }
}

class _ApiFactory {
  const _ApiFactory();

  FitLoopApi create() => HttpFitLoopApi();
}

class AuthGate extends StatefulWidget {
  const AuthGate({super.key, required this.api});

  final FitLoopApi api;

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  UserSession? _session;

  @override
  Widget build(BuildContext context) {
    final session = _session;
    if (session != null) {
      return AppShell(api: widget.api, session: session);
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
  final _account = TextEditingController(text: '13800000001');
  final _password = TextEditingController(text: 'pass1234');
  final _nickname = TextEditingController(text: '测试用户');
  bool _registerMode = false;
  bool _busy = false;
  String? _message;

  @override
  void dispose() {
    _account.dispose();
    _password.dispose();
    _nickname.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      if (_registerMode) {
        await widget.api.register(
          account: _account.text.trim(),
          password: _password.text,
          nickname: _nickname.text.trim().isEmpty
              ? 'FitLoop 用户'
              : _nickname.text.trim(),
        );
      }
      final session = await widget.api.login(
        account: _account.text.trim(),
        password: _password.text,
      );
      widget.onSignedIn(session);
    } catch (error) {
      setState(() => _message = error.toString());
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
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
            Text('校园运动打卡与健康管理', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 32),
            TextField(
              controller: _account,
              decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.phone_android), labelText: '手机号或邮箱'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _password,
              obscureText: true,
              decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.lock_outline), labelText: '密码'),
            ),
            if (_registerMode) ...[
              const SizedBox(height: 12),
              TextField(
                controller: _nickname,
                decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.badge_outlined), labelText: '昵称'),
              ),
            ],
            if (_message != null) ...[
              const SizedBox(height: 12),
              Text(_message!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ],
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: _busy ? null : _submit,
              icon: _busy
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : Icon(_registerMode ? Icons.person_add_alt : Icons.login),
              label: Text(_registerMode ? '注册并进入' : '登录'),
            ),
            TextButton(
              onPressed: _busy
                  ? null
                  : () => setState(() => _registerMode = !_registerMode),
              child: Text(_registerMode ? '已有账号，去登录' : '没有账号，创建账号'),
            ),
          ],
        ),
      ),
    );
  }
}

class AppShell extends StatefulWidget {
  const AppShell({super.key, required this.api, required this.session});

  final FitLoopApi api;
  final UserSession session;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    final pages = [
      DashboardPage(session: widget.session),
      SportSessionPage(api: widget.api, session: widget.session),
      StatsPage(api: widget.api, session: widget.session),
      const SocialPage(),
      ProfilePage(session: widget.session),
    ];
    return Scaffold(
      body: SafeArea(child: pages[_index]),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (value) => setState(() => _index = value),
        destinations: const [
          NavigationDestination(
              icon: Icon(Icons.home_outlined),
              selectedIcon: Icon(Icons.home),
              label: '首页'),
          NavigationDestination(
              icon: Icon(Icons.directions_run_outlined),
              selectedIcon: Icon(Icons.directions_run),
              label: '运动'),
          NavigationDestination(
              icon: Icon(Icons.bar_chart_outlined),
              selectedIcon: Icon(Icons.bar_chart),
              label: '统计'),
          NavigationDestination(
              icon: Icon(Icons.groups_outlined),
              selectedIcon: Icon(Icons.groups),
              label: '社交'),
          NavigationDestination(
              icon: Icon(Icons.person_outline),
              selectedIcon: Icon(Icons.person),
              label: '我的'),
        ],
      ),
    );
  }
}

class DashboardPage extends StatelessWidget {
  const DashboardPage({super.key, required this.session});

  final UserSession session;

  @override
  Widget build(BuildContext context) {
    return _PageScaffold(
      title: 'FitLoop',
      children: [
        _MetricCard(
            label: '欢迎回来',
            value: session.nickname,
            icon: Icons.waving_hand_outlined),
        const _MetricCard(
            label: '本周目标', value: '连接后端后自动更新', icon: Icons.flag_outlined),
        const _MetricCard(
            label: '今日运动', value: '从运动页开始打卡', icon: Icons.timer_outlined),
      ],
    );
  }
}

class SportSessionPage extends StatefulWidget {
  const SportSessionPage({super.key, required this.api, required this.session});

  final FitLoopApi api;
  final UserSession session;

  @override
  State<SportSessionPage> createState() => _SportSessionPageState();
}

class _SportSessionPageState extends State<SportSessionPage> {
  String? _sessionId;
  SportRecord? _lastRecord;
  bool _busy = false;
  String _status = '未开始';
  DateTime? _startedAt;

  TrackPoint _sampleTrackPoint({
    required String sessionId,
    required DateTime timestamp,
    required int offset,
  }) {
    return TrackPoint(
      sessionId: sessionId,
      lat: 31.2304 + offset * 0.0001,
      lng: 121.4737 + offset * 0.0001,
      accuracy: 20,
      timestamp: timestamp,
    );
  }

  Future<void> _toggle() async {
    setState(() => _busy = true);
    try {
      if (_sessionId == null) {
        final start = await widget.api.startSport(
          token: widget.session.token,
          sportType: 'running',
          checkinMode: 'gps',
        );
        final startedAt = DateTime.now();
        await widget.api.uploadTrackPoint(
          token: widget.session.token,
          point: _sampleTrackPoint(
            sessionId: start.sessionId,
            timestamp: startedAt,
            offset: 0,
          ),
        );
        setState(() {
          _sessionId = start.sessionId;
          _startedAt = startedAt;
          _status = 'GPS 打卡进行中，已上传 1 个轨迹点';
        });
      } else {
        final duration = DateTime.now()
            .difference(_startedAt ?? DateTime.now())
            .inSeconds
            .clamp(60, 24 * 3600)
            .toInt();
        await widget.api.uploadTrackPoint(
          token: widget.session.token,
          point: _sampleTrackPoint(
            sessionId: _sessionId!,
            timestamp:
                (_startedAt ?? DateTime.now()).add(Duration(seconds: duration)),
            offset: 1,
          ),
        );
        final record = await widget.api.finishSport(
          token: widget.session.token,
          sessionId: _sessionId!,
          durationSeconds: duration,
          weightKg: 60,
        );
        setState(() {
          _sessionId = null;
          _lastRecord = record;
          _status = '已保存记录 #${record.recordId}';
        });
      }
    } catch (error) {
      setState(() => _status = error.toString());
    } finally {
      if (mounted) {
        setState(() => _busy = false);
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
        FilledButton.icon(
          onPressed: _busy ? null : _toggle,
          icon: Icon(running ? Icons.stop : Icons.play_arrow),
          label: Text(running ? '结束打卡' : '开始跑步'),
        ),
        _MetricCard(
            label: '当前状态', value: _status, icon: Icons.sensors_outlined),
        _MetricCard(
            label: '打卡方式',
            value: running ? 'GPS session: $_sessionId' : 'GPS / 传感器 / 拍照 / 手动',
            icon: Icons.tune_outlined),
        if (lastRecord != null)
          _MetricCard(
            label: '最近一次',
            value:
                '${(lastRecord.durationSeconds / 60).round()} 分钟 / ${lastRecord.calorie.toStringAsFixed(1)} kcal',
            icon: Icons.route_outlined,
          ),
      ],
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
  Future<SportStats>? _future;

  @override
  void initState() {
    super.initState();
    _future = widget.api.sportStats(token: widget.session.token);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<SportStats>(
      future: _future,
      builder: (context, snapshot) {
        final stats = snapshot.data;
        return _PageScaffold(
          title: '健康统计',
          children: [
            FilledButton.icon(
              onPressed: () => setState(() =>
                  _future = widget.api.sportStats(token: widget.session.token)),
              icon: const Icon(Icons.refresh),
              label: const Text('刷新统计'),
            ),
            if (snapshot.hasError)
              _MetricCard(
                  label: '统计状态',
                  value: snapshot.error.toString(),
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
            ],
          ],
        );
      },
    );
  }
}

class SocialPage extends StatelessWidget {
  const SocialPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const _PageScaffold(
      title: '校园激励',
      children: [
        _MetricCard(
            label: '积分等级',
            value: '后续接入勋章接口',
            icon: Icons.workspace_premium_outlined),
        _MetricCard(
            label: '排行榜',
            value: '班级 / 宿舍 / 好友',
            icon: Icons.leaderboard_outlined),
      ],
    );
  }
}

class ProfilePage extends StatelessWidget {
  const ProfilePage({super.key, required this.session});

  final UserSession session;

  @override
  Widget build(BuildContext context) {
    return _PageScaffold(
      title: '我的',
      children: [
        _MetricCard(
            label: '账号状态',
            value: '已登录：${session.nickname}',
            icon: Icons.verified_user_outlined),
        const _MetricCard(
            label: '提醒设置',
            value: '运动 / 久坐 / 喝水 / 睡眠',
            icon: Icons.notifications_outlined),
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
