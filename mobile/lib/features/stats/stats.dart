part of '../../main.dart';

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
