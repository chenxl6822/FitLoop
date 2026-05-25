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
      DashboardPage(api: widget.api, session: widget.session),
      SportSessionPage(api: widget.api, session: widget.session),
      StatsPage(api: widget.api, session: widget.session),
      SocialPage(api: widget.api, session: widget.session),
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

class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key, required this.api, required this.session});

  final FitLoopApi api;
  final UserSession session;

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  Future<List<SportTarget>>? _future;

  @override
  void initState() {
    super.initState();
    _future = _loadTargets();
  }

  Future<List<SportTarget>> _loadTargets() {
    return widget.api.currentTargets(token: widget.session.token);
  }

  void _refreshTargets() {
    setState(() {
      _future = _loadTargets();
    });
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
      _refreshTargets();
    }
  }

  @override
  Widget build(BuildContext context) {
    return _PageScaffold(
      title: 'FitLoop',
      children: [
        _MetricCard(
            label: '欢迎回来',
            value: widget.session.nickname,
            icon: Icons.waving_hand_outlined),
        FutureBuilder<List<SportTarget>>(
          future: _future,
          builder: (context, snapshot) {
            final targets = snapshot.data ?? const <SportTarget>[];
            return _TargetSummaryCard(
              loading: snapshot.connectionState == ConnectionState.waiting,
              error: snapshot.error,
              target: targets.isEmpty ? null : targets.first,
              onRefresh: _refreshTargets,
              onCreate: _showCreateTargetSheet,
            );
          },
        ),
        const _MetricCard(
            label: '今日运动', value: '从运动页开始打卡', icon: Icons.timer_outlined),
      ],
    );
  }
}

class _TargetSummaryCard extends StatelessWidget {
  const _TargetSummaryCard({
    required this.loading,
    required this.error,
    required this.target,
    required this.onRefresh,
    required this.onCreate,
  });

  final bool loading;
  final Object? error;
  final SportTarget? target;
  final VoidCallback onRefresh;
  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) {
    final target = this.target;
    String value;
    if (loading) {
      value = '加载中';
    } else if (error != null) {
      value = error.toString();
    } else if (target == null) {
      value = '暂无进行中目标';
    } else {
      value =
          '${_periodLabel(target.periodType)} ${_metricLabel(target.metric)}：'
          '${_formatNumber(target.completedValue)} / ${_formatNumber(target.targetValue)}，'
          '进度 ${target.progress.toStringAsFixed(1)}%';
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Column(
        children: [
          ListTile(
            leading: const Icon(Icons.flag_outlined),
            title: const Text('运动目标'),
            subtitle: Text(value),
          ),
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
                const SizedBox(width: 12),
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

class _TargetFormSheet extends StatefulWidget {
  const _TargetFormSheet({
    required this.api,
    required this.token,
  });

  final FitLoopApi api;
  final String token;

  @override
  State<_TargetFormSheet> createState() => _TargetFormSheetState();
}

class _TargetFormSheetState extends State<_TargetFormSheet> {
  final _value = TextEditingController(text: '3');
  String _periodType = 'week';
  String _metric = 'count';
  bool _busy = false;
  String? _message;

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
      await widget.api.createTarget(
        token: widget.token,
        periodType: _periodType,
        metric: _metric,
        targetValue: targetValue,
      );
      if (mounted) {
        Navigator.of(context).pop(true);
      }
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
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(20, 20, 20, 20 + bottomInset),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              '创建运动目标',
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
              label: const Text('保存目标'),
            ),
          ],
        ),
      ),
    );
  }
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

class SocialPage extends StatefulWidget {
  const SocialPage({super.key, required this.api, required this.session});

  final FitLoopApi api;
  final UserSession session;

  @override
  State<SocialPage> createState() => _SocialPageState();
}

class _SocialPageState extends State<SocialPage> {
  Future<_SocialSnapshot>? _future;

  @override
  void initState() {
    super.initState();
    _future = _loadSocial();
  }

  Future<_SocialSnapshot> _loadSocial() async {
    final medal = await widget.api.medalSummary(token: widget.session.token);
    final ranking = await widget.api.ranking(token: widget.session.token);
    return _SocialSnapshot(medal: medal, ranking: ranking);
  }

  void _refresh() {
    setState(() {
      _future = _loadSocial();
    });
  }

  @override
  Widget build(BuildContext context) {
    return _PageScaffold(
      title: '校园激励',
      children: [
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
                value: snapshot.error.toString(),
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
