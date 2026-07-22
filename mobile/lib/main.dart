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
part 'features/social/social.dart';
part 'features/profile/profile.dart';
part 'shared/shared_ui.dart';

const _kOnboardingDoneKey = 'onboarding_done';
const _appVersion = String.fromEnvironment(
  'FITLOOP_APP_VERSION',
  defaultValue: '0.1.6',
);
const _appBuildNumber = String.fromEnvironment(
  'FITLOOP_BUILD_NUMBER',
  defaultValue: '7',
);

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
