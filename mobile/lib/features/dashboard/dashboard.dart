part of '../../main.dart';

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

  void _openCoach() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => CoachPage(
          api: widget.api,
          session: widget.session,
        ),
      ),
    );
  }

  Future<void> _deleteTarget(SportTarget target) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('确认删除'),
        content: Text(
            '确定要删除目标"${_metricLabel(target.metric)} ${_formatNumber(target.targetValue)}"吗？此操作不可恢复。'),
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

  String _dateKey(DateTime date) {
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');
    return '${date.year}-$month-$day';
  }

  List<DateTime> _currentWeekDays() {
    final now = DateTime.now();
    final start = DateTime(now.year, now.month, now.day)
        .subtract(Duration(days: now.weekday - DateTime.monday));
    return List.generate(7, (index) => start.add(Duration(days: index)));
  }

  String _weekdayLabel(DateTime date) {
    const labels = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    return labels[date.weekday - 1];
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
            final todayPoint = points.where((p) => p.date == today).firstOrNull;
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
            final pointByDate = {
              for (final point in points) point.date: point,
            };
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
                      children: _currentWeekDays().map((date) {
                        final key = _dateKey(date);
                        final point = pointByDate[key];
                        final hasActivity = (point?.count ?? 0) > 0;
                        final dayLabel = '${date.month}/${date.day}';
                        final isToday = key == today;
                        return Column(
                          children: [
                            Text(_weekdayLabel(date),
                                style: TextStyle(
                                  fontSize: 10,
                                  color: isToday
                                      ? Theme.of(context).colorScheme.primary
                                      : Theme.of(context)
                                          .colorScheme
                                          .onSurfaceVariant,
                                )),
                            const SizedBox(height: 2),
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
                                    : (isToday
                                        ? Theme.of(context)
                                            .colorScheme
                                            .primaryContainer
                                        : Colors.grey.shade200),
                                shape: BoxShape.circle,
                                border: isToday
                                    ? Border.all(
                                        color: Theme.of(context)
                                            .colorScheme
                                            .primary,
                                        width: 2,
                                      )
                                    : null,
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
                        onTap: () => widget.onNavigateToTab?.call(1),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _QuickAction(
                        icon: Icons.bar_chart,
                        label: '查看统计',
                        onTap: () => widget.onNavigateToTab?.call(2),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: _QuickAction(
                    icon: Icons.auto_awesome,
                    label: 'AI 教练',
                    onTap: _openCoach,
                  ),
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
                    key: const Key('target-create-button'),
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
                  icon: Icon(Icons.delete_outline,
                      size: 18, color: Theme.of(context).colorScheme.error),
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
              key: const Key('target-save-button'),
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
