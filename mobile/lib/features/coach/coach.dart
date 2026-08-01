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
  static const _decisionUncertainMessage = '操作结果暂时无法确认。为避免重复提交，'
      '确认和拒绝操作已锁定；请点击“重新获取状态”继续对账。';

  final _objectiveController = TextEditingController();
  Timer? _pollTimer;
  AgentRunCreated? _createdRun;
  AgentRunDetail? _run;
  String? _error;
  String? _decisionReceipt;
  int? _decisionProposalId;
  bool _creating = false;
  bool _refreshing = false;
  bool _deciding = false;
  bool _confirmDialogOpen = false;
  bool _decisionUncertain = false;
  int _pollAttempts = 0;

  String? get _runId => _run?.runId ?? _createdRun?.runId;

  String? get _status => _run?.status ?? _createdRun?.status;

  AgentProposalItem? get _pendingPlanProposal {
    final run = _run;
    if (run == null || run.status != 'WAITING_APPROVAL') return null;
    final matching = run.proposals.where(
      (proposal) =>
          proposal.actionType == 'CREATE_TRAINING_PLAN' &&
          proposal.status == 'PENDING' &&
          !proposal.requiresAdmin,
    );
    return matching.length == 1 ? matching.single : null;
  }

  bool get _hasCurrentPlanProposal {
    final proposal = _pendingPlanProposal;
    return proposal != null &&
        proposal.expiresAt != null &&
        !proposal.isExpiredAt(DateTime.now());
  }

  bool get _hasActiveRun {
    if (_creating ||
        _refreshing ||
        _deciding ||
        _confirmDialogOpen ||
        _decisionUncertain) {
      return true;
    }
    if (_decisionReceipt != null) return false;
    if (_run != null) {
      return _run!.shouldPoll ||
          (_run!.status == 'WAITING_APPROVAL' && _hasCurrentPlanProposal);
    }
    return _createdRun != null;
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _objectiveController.dispose();
    super.dispose();
  }

  void _openSavedPlans() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => _SavedTrainingPlansPage(
          api: widget.api,
          session: widget.session,
        ),
      ),
    );
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
      _decisionReceipt = null;
      _decisionProposalId = null;
      _decisionUncertain = false;
      _createdRun = null;
      _run = null;
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
        _syncDecisionStateFromRun(run);
        if (_decisionUncertain) {
          _error = _decisionUncertainMessage;
        }
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
        _error = _decisionUncertain
            ? _decisionUncertainMessage
            : _coachUnavailableMessage(error);
      });
    }
  }

  void _syncDecisionStateFromRun(AgentRunDetail run) {
    final proposalId = _decisionProposalId;
    if (proposalId == null) return;

    AgentProposalItem? proposal;
    for (final item in run.proposals) {
      if (item.proposalId == proposalId) {
        proposal = item;
        break;
      }
    }
    if (proposal?.status == 'CONFIRMED') {
      if (_decisionReceipt == null || !_decisionReceipt!.startsWith('训练计划')) {
        _decisionReceipt = '训练计划已创建';
      }
      _decisionUncertain = false;
      _error = null;
    } else if (proposal?.status == 'REJECTED') {
      _decisionReceipt = '草案已拒绝，未创建训练计划';
      _decisionUncertain = false;
      _error = null;
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

  AgentProposalItem? _currentDecisionProposal(
    AgentProposalItem candidate, {
    required bool requirePreview,
  }) {
    if (_deciding || _decisionUncertain || _decisionReceipt != null) {
      return null;
    }
    final current = _pendingPlanProposal;
    if (current == null ||
        current.proposalId != candidate.proposalId ||
        current.isExpiredAt(DateTime.now()) ||
        (requirePreview && current.trainingPlanPreview == null)) {
      return null;
    }
    return current;
  }

  Future<void> _confirmPlan(AgentProposalItem proposal) async {
    if (_confirmDialogOpen) return;
    final current = _currentDecisionProposal(
      proposal,
      requirePreview: true,
    );
    if (current == null) {
      setState(() {
        _error = '草案状态已变化或已经过期，未执行创建操作。请重新获取状态。';
      });
      return;
    }

    setState(() => _confirmDialogOpen = true);
    bool? confirmed;
    try {
      confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) {
          return AlertDialog(
            title: const Text('创建这份训练计划？'),
            content: const Text(
              '确认后将立即写入你的训练计划。当前操作没有撤销入口，'
              '请先核对下方展示的目标和每日安排。',
            ),
            actions: [
              TextButton(
                key: const Key('coach-confirm-cancel'),
                autofocus: true,
                onPressed: () => Navigator.of(dialogContext).pop(false),
                child: const Text('暂不创建'),
              ),
              FilledButton(
                key: const Key('coach-confirm-dialog-action'),
                onPressed: () => Navigator.of(dialogContext).pop(true),
                child: const Text('创建并保存'),
              ),
            ],
          );
        },
      );
    } finally {
      if (mounted) setState(() => _confirmDialogOpen = false);
    }
    if (confirmed == true && mounted) {
      await _decidePlan(current, confirm: true);
    }
  }

  Future<void> _decidePlan(
    AgentProposalItem proposal, {
    required bool confirm,
  }) async {
    final current = _currentDecisionProposal(
      proposal,
      requirePreview: confirm,
    );
    if (current == null) {
      if (mounted) {
        setState(() {
          _error = '草案状态已变化或已经过期，未提交操作。请重新获取状态。';
        });
      }
      return;
    }
    setState(() {
      _deciding = true;
      _decisionProposalId = current.proposalId;
      _decisionUncertain = false;
      _error = null;
    });

    try {
      final decision = confirm
          ? await widget.api
              .confirmAgentProposal(
                token: widget.session.token,
                proposalId: current.proposalId,
              )
              .timeout(_requestTimeout)
          : await widget.api
              .rejectAgentProposal(
                token: widget.session.token,
                proposalId: current.proposalId,
                reason: '暂不采用此计划',
              )
              .timeout(_requestTimeout);
      final expectedStatus = confirm ? 'CONFIRMED' : 'REJECTED';
      final hasExpectedResource = confirm
          ? decision.affectedResourceId != null
          : decision.affectedResourceId == null;
      if (decision.proposalId != current.proposalId ||
          decision.status != expectedStatus ||
          !hasExpectedResource) {
        throw const FormatException('Unexpected proposal decision status');
      }
      if (!mounted) return;
      setState(() {
        _deciding = false;
        _decisionReceipt = confirm
            ? decision.affectedResourceId == null
                ? '训练计划已创建'
                : '训练计划 #${decision.affectedResourceId} 已创建'
            : '草案已拒绝，未创建训练计划';
      });
      final runId = _runId;
      if (runId != null) await _refreshRun(runId);
    } catch (_) {
      if (!mounted) return;
      await _reconcileDecision(current);
    }
  }

  Future<void> _reconcileDecision(AgentProposalItem proposal) async {
    AgentRunDetail? reconciled;
    final runId = _runId;
    if (runId != null) {
      try {
        reconciled = await widget.api
            .getAgentRun(token: widget.session.token, runId: runId)
            .timeout(_requestTimeout);
      } catch (_) {
        reconciled = null;
      }
    }
    if (!mounted) return;

    setState(() {
      if (reconciled != null) _run = reconciled;
      _deciding = false;
      _decisionProposalId = proposal.proposalId;
      _decisionUncertain = true;
      if (reconciled != null) _syncDecisionStateFromRun(reconciled);
      if (_decisionUncertain) _error = _decisionUncertainMessage;
    });
  }

  String _coachUnavailableMessage(Object _) {
    return 'AI 教练暂时不可用，请稍后重试。运动、统计等功能不受影响。';
  }

  @override
  Widget build(BuildContext context) {
    final run = _run;
    final advice = run?.advice;
    final waitingForPlanApproval = run?.status == 'WAITING_APPROVAL';
    final planProposal = _pendingPlanProposal;
    final planPreview = planProposal?.trainingPlanPreview;
    final expiration = planProposal?.expiresAt;
    final proposalExpired = planProposal != null &&
        expiration != null &&
        planProposal.isExpiredAt(DateTime.now());
    final canRejectPlan = planProposal != null &&
        expiration != null &&
        !proposalExpired &&
        !_decisionUncertain &&
        _decisionReceipt == null;
    final canConfirmPlan = canRejectPlan && planPreview != null;

    return Scaffold(
      appBar: AppBar(
        title: const Text('AI 教练'),
        actions: [
          TextButton.icon(
            key: const Key('coach-open-saved-plans'),
            onPressed: _openSavedPlans,
            icon: const Icon(Icons.event_note_outlined),
            label: const Text('我的计划'),
          ),
        ],
      ),
      body: ListView(
        key: const Key('coach-list'),
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
            label: Text(
              _creating
                  ? '正在提交'
                  : _hasCurrentPlanProposal && _decisionReceipt == null
                      ? '草案待确认'
                      : _createdRun == null
                          ? '生成建议'
                          : '重新生成建议',
            ),
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
          if (_decisionReceipt != null) ...[
            const SizedBox(height: 16),
            _CoachInfoCard(
              icon: Icons.check_circle_outline,
              title: '操作结果',
              message: _decisionReceipt!,
              actionKey: const Key('coach-view-saved-plans'),
              actionLabel: _decisionReceipt!.startsWith('训练计划') ? '查看计划' : null,
              onAction:
                  _decisionReceipt!.startsWith('训练计划') ? _openSavedPlans : null,
            ),
          ],
          if (waitingForPlanApproval && planProposal != null) ...[
            const SizedBox(height: 16),
            _CoachPlanProposalCard(
              preview: planPreview,
              expiration: expiration,
              expired: proposalExpired,
              deciding: _deciding,
              decisionUncertain: _decisionUncertain,
              onConfirm:
                  canConfirmPlan ? () => _confirmPlan(planProposal) : null,
              onReject: canRejectPlan
                  ? () => _decidePlan(planProposal, confirm: false)
                  : null,
            ),
          ] else if (waitingForPlanApproval) ...[
            const SizedBox(height: 16),
            const _CoachInfoCard(
              icon: Icons.report_gmailerrorred_outlined,
              title: '草案无法在此安全处理',
              message: '草案类型、权限或数量与预期不一致，'
                  '因此不会展示写入操作。你可以重新生成建议。',
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

class _SavedTrainingPlansPage extends StatefulWidget {
  const _SavedTrainingPlansPage({
    required this.api,
    required this.session,
  });

  final FitLoopApi api;
  final UserSession session;

  @override
  State<_SavedTrainingPlansPage> createState() =>
      _SavedTrainingPlansPageState();
}

class _SavedTrainingPlansPageState extends State<_SavedTrainingPlansPage> {
  static const _requestTimeout = Duration(seconds: 15);

  List<SavedTrainingPlan> _plans = const [];
  String? _error;
  bool _loading = true;
  int _request = 0;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    final request = ++_request;
    if (!_loading || _error != null) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final plans = await widget.api
          .listTrainingPlans(token: widget.session.token)
          .timeout(_requestTimeout);
      if (!mounted || request != _request) return;
      setState(() {
        _plans = plans;
        _loading = false;
      });
    } catch (_) {
      if (!mounted || request != _request) return;
      setState(() {
        _loading = false;
        _error = '训练计划暂时无法加载，请稍后重试。';
      });
    }
  }

  void _openPlan(SavedTrainingPlan plan) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => _SavedTrainingPlanPage(plan: plan),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: const Key('coach-saved-plans-page'),
      appBar: AppBar(title: const Text('我的训练计划')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          _SavedTrainingPlansCard(
            plans: _plans,
            loading: _loading,
            error: _error,
            onRefresh: _load,
            onOpen: _openPlan,
          ),
        ],
      ),
    );
  }
}

class _SavedTrainingPlansCard extends StatelessWidget {
  const _SavedTrainingPlansCard({
    required this.plans,
    required this.loading,
    required this.error,
    required this.onRefresh,
    required this.onOpen,
  });

  final List<SavedTrainingPlan> plans;
  final bool loading;
  final String? error;
  final VoidCallback onRefresh;
  final ValueChanged<SavedTrainingPlan> onOpen;

  String _dateLabel(SavedTrainingPlan plan) {
    final date = plan.createdAtUtc?.toLocal();
    if (date == null) return '创建时间未知';
    String twoDigits(int value) => value.toString().padLeft(2, '0');
    return '${date.year}-${twoDigits(date.month)}-${twoDigits(date.day)}';
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      key: const Key('coach-saved-plans'),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.event_note_outlined,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '我的训练计划',
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                ),
                IconButton(
                  key: const Key('coach-refresh-saved-plans'),
                  tooltip: '刷新训练计划',
                  onPressed: loading ? null : onRefresh,
                  icon: const Icon(Icons.refresh),
                ),
              ],
            ),
            if (loading) const LinearProgressIndicator(),
            if (error != null) ...[
              const SizedBox(height: 8),
              Text(
                error!,
                key: const Key('coach-saved-plans-error'),
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
            if (!loading && error == null && plans.isEmpty) ...[
              const SizedBox(height: 8),
              const Text('暂无已保存的训练计划。确认 AI 教练草案后会显示在这里。'),
            ],
            for (var index = 0; index < plans.length; index++) ...[
              if (index > 0) const Divider(height: 1),
              ListTile(
                key: Key('coach-saved-plan-${plans[index].planId}'),
                contentPadding: EdgeInsets.zero,
                title: Text(plans[index].title),
                subtitle: Text(
                  '${plans[index].status == 'ACTIVE' ? '进行中' : plans[index].status}'
                  ' · ${_dateLabel(plans[index])}',
                ),
                trailing: TextButton(
                  key: Key('coach-view-plan-${plans[index].planId}'),
                  onPressed: () => onOpen(plans[index]),
                  child: const Text('查看'),
                ),
                onTap: () => onOpen(plans[index]),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _SavedTrainingPlanPage extends StatelessWidget {
  const _SavedTrainingPlanPage({required this.plan});

  final SavedTrainingPlan plan;

  String _intensityLabel(String intensity) {
    return switch (intensity) {
      'LOW' => '低强度',
      'MODERATE' => '中等强度',
      'HIGH' => '高强度',
      _ => '未知强度',
    };
  }

  @override
  Widget build(BuildContext context) {
    final preview = plan.preview;
    return Scaffold(
      key: Key('coach-plan-detail-${plan.planId}'),
      appBar: AppBar(title: const Text('训练计划详情')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(
            plan.title,
            style: Theme.of(context)
                .textTheme
                .headlineSmall
                ?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          Text(plan.status == 'ACTIVE' ? '状态：进行中' : '状态：${plan.status}'),
          const SizedBox(height: 20),
          if (preview == null)
            const _CoachInfoCard(
              icon: Icons.warning_amber_outlined,
              title: '计划内容暂时无法展示',
              message: '已保存的计划结构与当前版本不兼容，请稍后刷新或联系管理员。',
            )
          else ...[
            Text(
              '目标',
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            SelectableText(preview.goal),
            const SizedBox(height: 20),
            Text(
              '每日安排',
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            for (final day in preview.days)
              Card(
                key: Key('coach-plan-${plan.planId}-day-${day.day}'),
                child: ListTile(
                  title: Text('第 ${day.day} 天 · ${day.sessionType}'),
                  subtitle: Text([
                    '${day.durationMinutes} 分钟 · ${_intensityLabel(day.intensity)}',
                    if (day.notes != null && day.notes!.trim().isNotEmpty)
                      day.notes!,
                  ].join('\n')),
                ),
              ),
          ],
        ],
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
      'WAITING_APPROVAL' => '建议已生成，草案等待你的确认',
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
            if (advice.rationale.isNotEmpty) ...[
              const SizedBox(height: 16),
              Text(
                '依据摘要（Agent 生成）',
                style: Theme.of(context)
                    .textTheme
                    .titleSmall
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 4),
              Text(
                '这是 AI 根据 FitLoop 结构化数据生成的摘要，'
                '不是原始记录或来源引用。',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 8),
              for (final rationale in advice.rationale)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text('• $rationale'),
                ),
            ],
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

class _CoachPlanProposalCard extends StatelessWidget {
  const _CoachPlanProposalCard({
    required this.preview,
    required this.expiration,
    required this.expired,
    required this.deciding,
    required this.decisionUncertain,
    this.onConfirm,
    this.onReject,
  });

  final TrainingPlanPreview? preview;
  final DateTime? expiration;
  final bool expired;
  final bool deciding;
  final bool decisionUncertain;
  final VoidCallback? onConfirm;
  final VoidCallback? onReject;

  String _intensityLabel(String intensity) {
    return switch (intensity) {
      'LOW' => '低强度',
      'MODERATE' => '中等强度',
      'HIGH' => '高强度',
      _ => '未知强度',
    };
  }

  String _formatExpiration(DateTime value) {
    final utc = value.toUtc();
    String twoDigits(int number) => number.toString().padLeft(2, '0');
    return '${utc.year}-${twoDigits(utc.month)}-${twoDigits(utc.day)} '
        '${twoDigits(utc.hour)}:${twoDigits(utc.minute)} UTC';
  }

  @override
  Widget build(BuildContext context) {
    final plan = preview;
    return Card(
      key: const Key('coach-plan-preview'),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.fact_check_outlined,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '训练计划草案',
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                ),
                if (!expired && expiration != null)
                  const Chip(label: Text('待确认')),
              ],
            ),
            const SizedBox(height: 12),
            if (plan != null) ...[
              Text(
                '计划标题',
                style: Theme.of(context).textTheme.labelMedium,
              ),
              const SizedBox(height: 4),
              Text(
                plan.title,
                style: Theme.of(context)
                    .textTheme
                    .titleSmall
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 10),
              Text(
                '训练目标',
                style: Theme.of(context).textTheme.labelMedium,
              ),
              const SizedBox(height: 4),
              Text(plan.goal),
              const SizedBox(height: 14),
              for (final day in plan.days)
                Container(
                  width: double.infinity,
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surfaceContainerLow,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '第 ${day.day} 天 · ${day.sessionType}',
                        style: Theme.of(context)
                            .textTheme
                            .bodyLarge
                            ?.copyWith(fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${day.durationMinutes} 分钟 · '
                        '${_intensityLabel(day.intensity)}',
                      ),
                      if (day.notes != null &&
                          day.notes!.trim().isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(day.notes!),
                      ],
                    ],
                  ),
                ),
            ] else ...[
              const _CoachInlineNotice(
                icon: Icons.warning_amber_rounded,
                message: '草案内容不完整或包含未知字段，已禁用创建操作。'
                    '你仍可拒绝这份草案。',
              ),
            ],
            if (expiration == null) ...[
              const SizedBox(height: 4),
              const _CoachInlineNotice(
                icon: Icons.schedule_outlined,
                message: '有效期信息无法验证，已禁用写入操作。你可以重新生成建议。',
              ),
            ] else if (expired) ...[
              const SizedBox(height: 4),
              const _CoachInlineNotice(
                icon: Icons.schedule_outlined,
                message: '草案已过期，未创建训练计划。你可以重新生成建议。',
              ),
            ] else ...[
              Text(
                '草案有效期至 ${_formatExpiration(expiration!)}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 10),
              const Text('确认会立即创建并保存以上计划；拒绝不会创建计划。'),
            ],
            if (decisionUncertain) ...[
              const SizedBox(height: 10),
              const _CoachInlineNotice(
                icon: Icons.sync_problem_outlined,
                message: '操作结果正在对账。为避免重复提交，确认和拒绝已锁定。',
              ),
            ],
            if (onReject != null || onConfirm != null) ...[
              const SizedBox(height: 16),
              if (deciding) ...[
                const LinearProgressIndicator(),
                const SizedBox(height: 8),
                const Text('正在提交你的选择…'),
              ] else ...[
                if (onReject != null)
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      key: const Key('coach-reject-plan'),
                      onPressed: onReject,
                      icon: const Icon(Icons.close),
                      label: const Text('拒绝草案（不创建）'),
                    ),
                  ),
                if (onReject != null && onConfirm != null)
                  const SizedBox(height: 8),
                if (onConfirm != null)
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      key: const Key('coach-confirm-plan'),
                      onPressed: onConfirm,
                      icon: const Icon(Icons.add_task),
                      label: const Text('创建并保存训练计划'),
                    ),
                  ),
              ],
            ],
          ],
        ),
      ),
    );
  }
}

class _CoachInlineNotice extends StatelessWidget {
  const _CoachInlineNotice({
    required this.icon,
    required this.message,
  });

  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 20),
        const SizedBox(width: 8),
        Expanded(child: Text(message)),
      ],
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
    this.actionKey,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String title;
  final String message;
  final Key? actionKey;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: Icon(icon),
        title: Text(title),
        subtitle: Text(message),
        trailing: onAction == null
            ? null
            : TextButton(
                key: actionKey,
                onPressed: onAction,
                child: Text(actionLabel!),
              ),
      ),
    );
  }
}
