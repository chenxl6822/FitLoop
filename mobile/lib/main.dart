import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';
import 'package:pedometer/pedometer.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api_config.dart';
import 'api_client.dart';
import 'fitloop_assets.dart';
import 'onboarding_screen.dart';
import 'reminder_scheduler.dart';
import 'secure_session_storage.dart';
import 'splash_screen.dart';
import 'stats_charts.dart';
import 'sync_queue.dart';

part 'features/workout/workout.dart';
part 'features/admin/admin.dart';
part 'features/auth/auth.dart';
part 'features/dashboard/dashboard.dart';
part 'features/stats/stats.dart';

String? _resolveMediaUrl(String? url) {
  if (url == null || url.isEmpty) return url;
  final parsed = Uri.tryParse(url);
  if (parsed != null && parsed.hasScheme) return url;
  if (!url.startsWith('/')) return url;
  final base = ApiConfig.baseUrl.endsWith('/')
      ? ApiConfig.baseUrl.substring(0, ApiConfig.baseUrl.length - 1)
      : ApiConfig.baseUrl;
  return '$base$url';
}

const _kOnboardingDoneKey = 'onboarding_done';
const _appVersion = String.fromEnvironment(
  'FITLOOP_APP_VERSION',
  defaultValue: '0.1.6',
);
const _appBuildNumber = String.fromEnvironment(
  'FITLOOP_BUILD_NUMBER',
  defaultValue: '7',
);

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
  if (msg.contains('TLS') ||
      msg.contains('SSL') ||
      msg.contains('Certificate')) {
    return '安全连接失败，请稍后重试';
  }
  // 认证相关（非网络）
  if (msg.contains('401') || msg.contains('403')) {
    return '登录状态已过期，请重新登录';
  }
  if (msg.contains('500')) {
    return '服务器开小差了，请稍后重试';
  }
  if (msg.contains('Missing type parameter') ||
      msg.contains('flutterlocalnotifications')) {
    return '提醒服务初始化失败，请重启应用后重试';
  }
  // 去除 ApiException: 前缀，展示后端返回的原始消息
  if (msg.startsWith('ApiException: ')) {
    return msg.substring(14);
  }
  return msg;
}

void main() {
  WidgetsFlutterBinding.ensureInitialized();
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
  final _socialPageKey = GlobalKey<_SocialPageState>();
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
      SocialPage(
        key: _socialPageKey,
        api: widget.api,
        session: widget.session,
      ),
      ProfilePage(
        api: widget.api,
        reminderScheduler: widget.reminderScheduler,
        session: widget.session,
        onLogout: () => _handleLogout(),
      ),
    ];
  }

  void _handleLogout() async {
    widget.onLogout?.call();
  }

  void _selectTab(int value) {
    setState(() => _index = value);
    if (value == 3) {
      _socialPageKey.currentState?.refresh();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: IndexedStack(index: _index, children: _pages),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: _selectTab,
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
  String _rankingScope = 'friends';

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
    final ranking = await widget.api.ranking(
      token: widget.session.token,
      scope: _rankingScope,
    );
    return _SocialSnapshot(medal: medal, ranking: ranking);
  }

  Future<FriendListResponse> _loadFriends() {
    return widget.api.listFriends(token: widget.session.token);
  }

  void refresh() {
    setState(() {
      _future = _loadSocial();
      _friendFuture = _loadFriends();
      _searchResults = [];
    });
  }

  void _selectRankingScope(String scope) {
    if (_rankingScope == scope) return;
    setState(() {
      _rankingScope = scope;
      _future = _loadSocial();
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
      refresh();
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
                          onPressed: refresh,
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

        Card(
          margin: const EdgeInsets.only(bottom: 12),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ChoiceChip(
                  key: const Key('ranking-scope-personal'),
                  label: const Text('个人'),
                  selected: _rankingScope == 'personal',
                  onSelected: (_) => _selectRankingScope('personal'),
                ),
                ChoiceChip(
                  key: const Key('ranking-scope-friends'),
                  label: const Text('好友'),
                  selected: _rankingScope == 'friends',
                  onSelected: (_) => _selectRankingScope('friends'),
                ),
                ChoiceChip(
                  key: const Key('ranking-scope-global'),
                  label: const Text('全站'),
                  selected: _rankingScope == 'global',
                  onSelected: (_) => _selectRankingScope('global'),
                ),
              ],
            ),
          ),
        ),

        // 激励数据
        FilledButton.icon(
          onPressed: refresh,
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
    final saved = await Navigator.of(context).push<ReminderConfig>(
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
    if (saved == null || !mounted) return;

    var reminders = const <ReminderConfig>[];
    try {
      reminders = (await _future)?.reminders ?? reminders;
    } catch (_) {
      // The save response is authoritative even if the original list failed.
    }
    final updated = [
      for (final reminder in reminders)
        if (reminder.type != saved.type) reminder,
      saved,
    ];
    if (!mounted) return;
    setState(() {
      _future = Future.value(ReminderListResponse(reminders: updated));
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('提醒设置已保存')),
    );
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
  const SettingsPage(
      {super.key, required this.session, required this.api, this.onLogout});

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
                _InfoRow(label: '用户ID', value: session.userId.toString()),
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
                const _InfoRow(label: '版本', value: _appVersion),
                const _InfoRow(label: '构建号', value: _appBuildNumber),
              ],
            ),
          ),
          if (session.isAdmin) ...[
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: () => _openAdminDashboard(context),
              icon: const Icon(Icons.admin_panel_settings_outlined),
              label: const Text('管理后台'),
            ),
          ],
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

  void _openAdminDashboard(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => _AdminDashboardPage(api: api, token: session.token),
      ),
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
            onChanged: _busy
                ? null
                : (value) => setState(() => _type = value ?? 'feature'),
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
                    style:
                        TextStyle(color: Theme.of(context).colorScheme.error));
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
                children: feedbacks
                    .map((f) => Card(
                          margin: const EdgeInsets.only(bottom: 8),
                          child: ListTile(
                            title: Text(_typeLabel(f.type),
                                style: const TextStyle(
                                    fontWeight: FontWeight.w600)),
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const SizedBox(height: 4),
                                Text(f.content,
                                    maxLines: 3,
                                    overflow: TextOverflow.ellipsis),
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
                                      style:
                                          Theme.of(context).textTheme.bodySmall,
                                    ),
                                  ],
                                ),
                                if (f.adminNote != null &&
                                    f.adminNote!.isNotEmpty) ...[
                                  const SizedBox(height: 4),
                                  Text('回复：${f.adminNote}',
                                      style: TextStyle(
                                          color: Theme.of(context)
                                              .colorScheme
                                              .primary,
                                          fontSize: 12)),
                                ],
                              ],
                            ),
                          ),
                        ))
                    .toList(),
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
  int _remindId = 0;
  ReminderConfig? _originalConfig;
  bool _enabled = false;
  TimeOfDay _time = const TimeOfDay(hour: 8, minute: 0);
  String _cycle = 'daily';
  int _weeklyTimes = 3;
  bool _loading = true;
  bool _saving = false;
  String? _loadError;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _loadError = null;
      });
    }
    try {
      final resp = await widget.api.listReminders(token: widget.token);
      final config =
          resp.reminders.where((r) => r.type == widget.type).firstOrNull;
      if (!mounted) return;
      if (config != null) {
        setState(() {
          _originalConfig = config;
          _remindId = config.id;
          _enabled = config.enabled;
          _parseCycle(config.cycle);
          _time = _parseTime(config.time) ?? _time;
        });
      }
    } catch (error) {
      if (mounted) setState(() => _loadError = friendlyErrorMsg(error));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  TimeOfDay? _parseTime(String? value) {
    if (value == null) return null;
    final parts = value.split(':');
    if (parts.length < 2) return null;
    final hour = int.tryParse(parts[0]);
    final minute = int.tryParse(parts[1]);
    if (hour == null ||
        minute == null ||
        hour < 0 ||
        hour > 23 ||
        minute < 0 ||
        minute > 59) {
      return null;
    }
    return TimeOfDay(hour: hour, minute: minute);
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(context: context, initialTime: _time);
    if (picked != null && mounted) setState(() => _time = picked);
  }

  void _parseCycle(String cycle) {
    if (cycle.startsWith('weekly:')) {
      _cycle = 'weekly';
      _weeklyTimes = int.tryParse(cycle.substring('weekly:'.length))
              ?.clamp(1, 7)
              .toInt() ??
          3;
      return;
    }
    if (cycle == 'once') {
      _cycle = 'once';
      return;
    }
    _cycle = 'daily';
  }

  String _cycleValue() {
    if (_cycle == 'weekly') return 'weekly:$_weeklyTimes';
    return _cycle;
  }

  String _cycleLabel() {
    if (_cycle == 'once') return '不重复';
    if (_cycle == 'weekly') return '每周 $_weeklyTimes 次';
    return '每天重复';
  }

  Future<void> _applyLocalReminder({
    required bool enabled,
    required TimeOfDay time,
    required String cycle,
  }) async {
    if (!enabled) {
      await widget.reminderScheduler.cancel(widget.type);
      return;
    }

    final weeklyTimes = cycle.startsWith('weekly:')
        ? int.tryParse(cycle.substring('weekly:'.length))
                ?.clamp(1, 7)
                .toInt() ??
            3
        : 3;
    switch (cycle.split(':').first) {
      case 'once':
        await widget.reminderScheduler.scheduleOnce(
          type: widget.type,
          title: '${widget.label} 提醒',
          body: _reminderNotificationBody(widget.type),
          time: time,
        );
      case 'weekly':
        await widget.reminderScheduler.scheduleWeekly(
          type: widget.type,
          title: '${widget.label} 提醒',
          body: _reminderNotificationBody(widget.type),
          time: time,
          timesPerWeek: weeklyTimes,
        );
      default:
        await widget.reminderScheduler.scheduleDaily(
          type: widget.type,
          title: '${widget.label} 提醒',
          body: _reminderNotificationBody(widget.type),
          time: time,
        );
    }
  }

  Future<void> _restoreOriginalReminder() async {
    final original = _originalConfig;
    if (original == null || !original.enabled) {
      await widget.reminderScheduler.cancel(widget.type);
      return;
    }
    final originalTime = _parseTime(original.time);
    if (originalTime == null) return;
    await _applyLocalReminder(
      enabled: true,
      time: originalTime,
      cycle: original.cycle,
    );
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);
    final enabled = _enabled;
    final time = _time;
    final cycle = _cycleValue();
    var localChangeAttempted = false;
    try {
      final timeStr =
          '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}:00';

      // Apply locally first. If notification scheduling fails, the server state
      // remains unchanged instead of leaving the page in a half-saved state.
      localChangeAttempted = true;
      await _applyLocalReminder(enabled: enabled, time: time, cycle: cycle);
      final saved = await widget.api.upsertReminder(
        token: widget.token,
        remindId: _remindId,
        type: widget.type,
        time: timeStr,
        cycle: cycle,
        enabled: enabled,
      );
      if (mounted) Navigator.of(context).pop(saved);
    } catch (error) {
      var rollbackFailed = false;
      if (localChangeAttempted && error is! ReminderPermissionDeniedException) {
        try {
          await _restoreOriginalReminder();
        } catch (_) {
          rollbackFailed = true;
        }
      }
      if (mounted) {
        final message = friendlyErrorMsg(error);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              rollbackFailed ? '$message；本地提醒恢复失败，请重新保存' : message,
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_saving,
      child: Scaffold(
        appBar: AppBar(title: Text('${widget.label} 提醒')),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : _loadError != null
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.error_outline, size: 48),
                          const SizedBox(height: 12),
                          Text(_loadError!, textAlign: TextAlign.center),
                          const SizedBox(height: 16),
                          OutlinedButton.icon(
                            onPressed: _load,
                            icon: const Icon(Icons.refresh),
                            label: const Text('重新加载'),
                          ),
                        ],
                      ),
                    ),
                  )
                : ListView(
                    padding: const EdgeInsets.all(20),
                    children: [
                      Icon(widget.icon,
                          size: 64,
                          color: Theme.of(context).colorScheme.primary),
                      const SizedBox(height: 24),
                      SwitchListTile(
                        title: const Text('启用提醒'),
                        subtitle: Text(
                          _enabled
                              ? '${_time.format(context)} · ${_cycleLabel()}'
                              : '提醒已关闭',
                        ),
                        value: _enabled,
                        onChanged: _saving
                            ? null
                            : (value) => setState(() => _enabled = value),
                      ),
                      const SizedBox(height: 12),
                      ListTile(
                        leading: const Icon(Icons.access_time),
                        title: const Text('提醒时间'),
                        subtitle: Text(_time.format(context)),
                        trailing: const Icon(Icons.edit_calendar_outlined),
                        onTap: _enabled && !_saving ? _pickTime : null,
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        initialValue: _cycle,
                        decoration: const InputDecoration(
                          prefixIcon: Icon(Icons.repeat),
                          labelText: '重复方式',
                        ),
                        items: const [
                          DropdownMenuItem(value: 'once', child: Text('不重复')),
                          DropdownMenuItem(value: 'daily', child: Text('每天重复')),
                          DropdownMenuItem(
                              value: 'weekly', child: Text('每周重复')),
                        ],
                        onChanged: _enabled && !_saving
                            ? (value) =>
                                setState(() => _cycle = value ?? 'daily')
                            : null,
                      ),
                      if (_cycle == 'weekly') ...[
                        const SizedBox(height: 12),
                        ListTile(
                          leading: const Icon(Icons.event_repeat),
                          title: const Text('每周提醒次数'),
                          subtitle: Slider(
                            value: _weeklyTimes.toDouble(),
                            min: 1,
                            max: 7,
                            divisions: 6,
                            label: '$_weeklyTimes 次',
                            onChanged: _enabled && !_saving
                                ? (value) =>
                                    setState(() => _weeklyTimes = value.round())
                                : null,
                          ),
                          trailing: Text('$_weeklyTimes 次'),
                        ),
                      ],
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(
                          _enabled ? _cycleLabel() : '提醒已关闭',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ),
                      const SizedBox(height: 32),
                      FilledButton.icon(
                        onPressed: _saving ? null : _save,
                        icon: _saving
                            ? const SizedBox.square(
                                dimension: 18,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.save),
                        label: const Text('保存'),
                      ),
                    ],
                  ),
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
        backgroundImage: NetworkImage(_resolveMediaUrl(avatarUrl)!),
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
