part of '../../main.dart';

class CoachPage extends StatefulWidget {
  const CoachPage({
    super.key,
    required this.api,
    required this.session,
  });

  final FitLoopApi api;
  final UserSession session;

  @override
  State<CoachPage> createState() => _CoachPageState();
}

class _CoachPageState extends State<CoachPage> {
  static const _pollInterval = Duration(seconds: 2);
  static const _requestTimeout = Duration(seconds: 15);
  static const _maxPollAttempts = 60;

  final _objectiveController = TextEditingController();
  Timer? _pollTimer;
  AgentRunCreated? _createdRun;
  AgentRunDetail? _run;
  String? _error;
  bool _creating = false;
  bool _refreshing = false;
  int _pollAttempts = 0;

  String? get _runId => _run?.runId ?? _createdRun?.runId;

  String? get _status => _run?.status ?? _createdRun?.status;

  bool get _hasActiveRun {
    if (_creating || _refreshing) return true;
    if (_run != null) {
      return _run!.shouldPoll || _run!.status == 'WAITING_APPROVAL';
    }
    return _createdRun != null;
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _objectiveController.dispose();
    super.dispose();
  }

  Future<void> _createRun() async {
    final objective = _objectiveController.text.trim();
    if (objective.isEmpty) {
      setState(() => _error = '请先描述你的训练目标。');
      return;
    }

    FocusScope.of(context).unfocus();
    _pollTimer?.cancel();
    _pollAttempts = 0;
    setState(() {
      _creating = true;
      _error = null;
    });

    try {
      final created = await widget.api.createCoachRun(
        token: widget.session.token,
        objective: objective,
      );
      if (!mounted) return;
      setState(() {
        _createdRun = created;
        _run = null;
        _creating = false;
      });
      await _refreshRun(created.runId);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _creating = false;
        _error = _coachUnavailableMessage(error);
      });
    }
  }

  Future<void> _refreshRun(String runId) async {
    if (_refreshing) return;
    setState(() {
      _refreshing = true;
      _error = null;
    });

    try {
      final run = await widget.api
          .getAgentRun(token: widget.session.token, runId: runId)
          .timeout(_requestTimeout);
      if (!mounted) return;
      setState(() {
        _run = run;
        _refreshing = false;
      });
      if (run.shouldPoll) {
        _schedulePoll(runId);
      } else {
        _pollTimer?.cancel();
      }
    } catch (error) {
      if (!mounted) return;
      _pollTimer?.cancel();
      setState(() {
        _refreshing = false;
        _error = _coachUnavailableMessage(error);
      });
    }
  }

  void _schedulePoll(String runId) {
    _pollTimer?.cancel();
    if (_pollAttempts >= _maxPollAttempts) {
      setState(() {
        _error = 'AI 教练仍在处理，请稍后点击“重新获取状态”。运动、统计等功能不受影响。';
      });
      return;
    }
    _pollAttempts += 1;
    _pollTimer = Timer(_pollInterval, () {
      if (mounted) unawaited(_refreshRun(runId));
    });
  }

  void _retryStatus() {
    final runId = _runId;
    if (runId == null) return;
    _pollAttempts = 0;
    unawaited(_refreshRun(runId));
  }

  String _coachUnavailableMessage(Object error) {
    return 'AI 教练暂时不可用：${friendlyErrorMsg(error)}。'
        '运动、统计等功能不受影响。';
  }

  @override
  Widget build(BuildContext context) {
    final run = _run;
    final advice = run?.advice;
    final waitingForPlanApproval = run?.status == 'WAITING_APPROVAL' &&
        run!.proposals.any(
          (proposal) =>
              proposal.actionType == 'CREATE_TRAINING_PLAN' &&
              proposal.status == 'PENDING',
        );

    return Scaffold(
      appBar: AppBar(title: const Text('AI 教练')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const _CoachIntroCard(),
          const SizedBox(height: 16),
          TextField(
            key: const Key('coach-objective'),
            controller: _objectiveController,
            enabled: !_hasActiveRun,
            maxLength: 500,
            maxLines: 4,
            textInputAction: TextInputAction.newline,
            decoration: const InputDecoration(
              labelText: '训练目标',
              hintText: '例如：为下周安排两次循序渐进的跑步训练',
              border: OutlineInputBorder(),
              alignLabelWithHint: true,
            ),
          ),
          const SizedBox(height: 8),
          FilledButton.icon(
            key: const Key('coach-submit'),
            onPressed: _hasActiveRun ? null : _createRun,
            icon: _creating
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.auto_awesome),
            label: Text(_creating
                ? '正在提交'
                : _run?.status == 'WAITING_APPROVAL'
                    ? '草案待确认'
                    : _createdRun == null
                        ? '生成建议'
                        : '重新生成建议'),
          ),
          if (_error != null) ...[
            const SizedBox(height: 16),
            _CoachErrorCard(
              message: _error!,
              onRetry: _runId == null || _refreshing ? null : _retryStatus,
            ),
          ],
          if (_status != null) ...[
            const SizedBox(height: 16),
            _CoachStatusCard(
              status: _status!,
              refreshing: _refreshing || (_pollTimer?.isActive ?? false),
            ),
          ],
          if (advice != null) ...[
            const SizedBox(height: 16),
            _CoachAdviceCard(advice: advice),
          ] else if (run != null &&
              !run.shouldPoll &&
              run.status != 'FAILED_FINAL') ...[
            const SizedBox(height: 16),
            const _CoachInfoCard(
              icon: Icons.info_outline,
              title: '建议暂时无法展示',
              message: '本次返回内容无法识别，请重新发起一次咨询。',
            ),
          ],
          if (waitingForPlanApproval) ...[
            const SizedBox(height: 16),
            const _CoachInfoCard(
              icon: Icons.fact_check_outlined,
              title: '训练计划草案待确认',
              message: 'AI 已生成训练计划草案，但当前入口不会自动保存。'
                  '完整预览和确认/拒绝操作将在后续审批界面中提供。',
            ),
          ],
          if (run?.status == 'FAILED_FINAL') ...[
            const SizedBox(height: 16),
            const _CoachInfoCard(
              icon: Icons.cloud_off_outlined,
              title: '本次分析未完成',
              message: '请稍后重新发起咨询。运动、目标和统计功能仍可正常使用。',
            ),
          ],
        ],
      ),
    );
  }
}

class _CoachIntroCard extends StatelessWidget {
  const _CoachIntroCard();

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.psychology_alt_outlined,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Text(
                  '基于你的 FitLoop 数据生成建议',
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
              ],
            ),
            const SizedBox(height: 10),
            const Text('AI 会读取你的目标、近期运动和健康趋势。'
                '它不会直接修改训练计划，生成内容仅供参考。'),
          ],
        ),
      ),
    );
  }
}

class _CoachStatusCard extends StatelessWidget {
  const _CoachStatusCard({
    required this.status,
    required this.refreshing,
  });

  final String status;
  final bool refreshing;

  String get _label {
    return switch (status) {
      'QUEUED' => '已提交，等待处理',
      'RUNNING' => '正在分析',
      'FAILED_RETRYABLE' => '正在自动重试',
      'WAITING_APPROVAL' => '建议已生成，等待后续确认',
      'SUCCEEDED' => '建议已完成',
      'FAILED_FINAL' => '本次分析未完成',
      _ => '状态更新中',
    };
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '运行状态',
              style: Theme.of(context)
                  .textTheme
                  .titleSmall
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Text(_label),
            if (refreshing) ...[
              const SizedBox(height: 12),
              const LinearProgressIndicator(),
            ],
          ],
        ),
      ),
    );
  }
}

class _CoachAdviceCard extends StatelessWidget {
  const _CoachAdviceCard({required this.advice});

  final CoachAdvice advice;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.lightbulb_outline,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Text(
                  '教练建议',
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
              ],
            ),
            const SizedBox(height: 12),
            SelectableText(advice.answer),
            if (advice.safetyNotices.isNotEmpty) ...[
              const SizedBox(height: 16),
              Text(
                '安全提醒',
                style: Theme.of(context)
                    .textTheme
                    .titleSmall
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 6),
              for (final notice in advice.safetyNotices)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text('• $notice'),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

class _CoachErrorCard extends StatelessWidget {
  const _CoachErrorCard({
    required this.message,
    this.onRetry,
  });

  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return Card(
      color: Theme.of(context).colorScheme.errorContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(message),
            if (onRetry != null) ...[
              const SizedBox(height: 8),
              TextButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh),
                label: const Text('重新获取状态'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _CoachInfoCard extends StatelessWidget {
  const _CoachInfoCard({
    required this.icon,
    required this.title,
    required this.message,
  });

  final IconData icon;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: Icon(icon),
        title: Text(title),
        subtitle: Text(message),
      ),
    );
  }
}
