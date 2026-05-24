import 'package:flutter/material.dart';

void main() {
  runApp(const FitLoopApp());
}

class FitLoopApp extends StatelessWidget {
  const FitLoopApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'FitLoop',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF1F8A70)),
        useMaterial3: true,
      ),
      home: const AppShell(),
    );
  }
}

class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _index = 0;

  static const _pages = [
    DashboardPage(),
    SportPage(),
    StatsPage(),
    SocialPage(),
    ProfilePage(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(child: _pages[_index]),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (value) => setState(() => _index = value),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home), label: '首页'),
          NavigationDestination(icon: Icon(Icons.directions_run_outlined), selectedIcon: Icon(Icons.directions_run), label: '运动'),
          NavigationDestination(icon: Icon(Icons.bar_chart_outlined), selectedIcon: Icon(Icons.bar_chart), label: '统计'),
          NavigationDestination(icon: Icon(Icons.groups_outlined), selectedIcon: Icon(Icons.groups), label: '社交'),
          NavigationDestination(icon: Icon(Icons.person_outline), selectedIcon: Icon(Icons.person), label: '我的'),
        ],
      ),
    );
  }
}

class DashboardPage extends StatelessWidget {
  const DashboardPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const _PageScaffold(
      title: 'FitLoop',
      children: [
        _MetricCard(label: '本周目标', value: '60%', icon: Icons.flag_outlined),
        _MetricCard(label: '今日运动', value: '0 分钟', icon: Icons.timer_outlined),
        _MetricCard(label: '连续打卡', value: '0 天', icon: Icons.local_fire_department_outlined),
      ],
    );
  }
}

class SportPage extends StatelessWidget {
  const SportPage({super.key});

  @override
  Widget build(BuildContext context) {
    return _PageScaffold(
      title: '运动打卡',
      children: [
        FilledButton.icon(
          onPressed: () {},
          icon: const Icon(Icons.play_arrow),
          label: const Text('开始跑步'),
        ),
        const _MetricCard(label: '打卡方式', value: 'GPS / 传感器 / 拍照 / 手动', icon: Icons.sensors_outlined),
      ],
    );
  }
}

class StatsPage extends StatelessWidget {
  const StatsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const _PageScaffold(
      title: '健康统计',
      children: [
        _MetricCard(label: '周运动次数', value: '0 次', icon: Icons.calendar_month_outlined),
        _MetricCard(label: '总里程', value: '0.0 km', icon: Icons.route_outlined),
        _MetricCard(label: '消耗', value: '0 kcal', icon: Icons.bolt_outlined),
      ],
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
        _MetricCard(label: '积分等级', value: 'Lv.1', icon: Icons.workspace_premium_outlined),
        _MetricCard(label: '排行榜', value: '班级 / 宿舍 / 好友', icon: Icons.leaderboard_outlined),
      ],
    );
  }
}

class ProfilePage extends StatelessWidget {
  const ProfilePage({super.key});

  @override
  Widget build(BuildContext context) {
    return const _PageScaffold(
      title: '我的',
      children: [
        _MetricCard(label: '账号状态', value: '未登录', icon: Icons.verified_user_outlined),
        _MetricCard(label: '提醒设置', value: '运动 / 久坐 / 喝水 / 睡眠', icon: Icons.notifications_outlined),
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
        Text(title, style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w700)),
        const SizedBox(height: 20),
        ...children,
      ],
    );
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({required this.label, required this.value, required this.icon});

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
