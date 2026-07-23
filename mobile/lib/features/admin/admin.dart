part of '../../main.dart';

class _AdminDashboardPage extends StatefulWidget {
  const _AdminDashboardPage({required this.api, required this.token});
  final FitLoopApi api;
  final String token;

  @override
  State<_AdminDashboardPage> createState() => _AdminDashboardPageState();
}

class _AdminDashboardPageState extends State<_AdminDashboardPage> {
  int _tabIndex = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('管理后台'),
        actions: [
          IconButton(
            tooltip: '审计记录',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => _AdminAuditPage(
                  api: widget.api,
                  token: widget.token,
                ),
              ),
            ),
            icon: const Icon(Icons.history),
          ),
        ],
      ),
      body: IndexedStack(
        index: _tabIndex,
        children: [
          _AdminStatsTab(api: widget.api, token: widget.token),
          _AdminAppealsTab(api: widget.api, token: widget.token),
          _AdminAgentRunsTab(api: widget.api, token: widget.token),
          _AdminUsersTab(api: widget.api, token: widget.token),
          _AdminFeedbackTab(api: widget.api, token: widget.token),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tabIndex,
        onDestinationSelected: (i) => setState(() => _tabIndex = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.dashboard), label: '概览'),
          NavigationDestination(icon: Icon(Icons.gavel), label: '申诉'),
          NavigationDestination(icon: Icon(Icons.smart_toy), label: 'Agent'),
          NavigationDestination(icon: Icon(Icons.people), label: '用户'),
          NavigationDestination(icon: Icon(Icons.feedback), label: '反馈'),
        ],
      ),
    );
  }
}

class _AdminStatsTab extends StatelessWidget {
  const _AdminStatsTab({required this.api, required this.token});
  final FitLoopApi api;
  final String token;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<AdminStats>(
      future: api.adminGetStats(token: token),
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

class _AdminAppealsTab extends StatefulWidget {
  const _AdminAppealsTab({required this.api, required this.token});

  final FitLoopApi api;
  final String token;

  @override
  State<_AdminAppealsTab> createState() => _AdminAppealsTabState();
}

class _AdminAppealsTabState extends State<_AdminAppealsTab> {
  late Future<AdminAppealPage> _future;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  void _refresh() {
    _future = widget.api.adminListAppeals(token: widget.token);
  }

  Future<void> _review(AdminAppealItem appeal, String status) async {
    final note = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(status == 'approved' ? '批准申诉' : '拒绝申诉'),
        content: TextField(
          controller: note,
          maxLength: 255,
          maxLines: 3,
          decoration: const InputDecoration(labelText: '审核说明（可选）'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('确认')),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await widget.api.adminReviewAppeal(
        token: widget.token,
        appealId: appeal.appealId,
        status: status,
        reviewNote: note.text.trim(),
      );
      if (!mounted) return;
      setState(_refresh);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(friendlyErrorMsg(error))));
    }
  }

  Future<void> _startAgentReview(AdminAppealItem appeal) async {
    try {
      final runId = await widget.api.adminStartAppealAgentReview(
        token: widget.token,
        appealId: appeal.appealId,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Agent 审核已排队：${runId.substring(0, 8)}')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(friendlyErrorMsg(error))));
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<AdminAppealPage>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(child: Text(friendlyErrorMsg(snapshot.error)));
        }
        final appeals = snapshot.data!.items;
        if (appeals.isEmpty) return const Center(child: Text('暂无申诉'));
        return RefreshIndicator(
          onRefresh: () async => setState(_refresh),
          child: ListView.builder(
            padding: const EdgeInsets.all(12),
            itemCount: appeals.length,
            itemBuilder: (context, index) {
              final appeal = appeals[index];
              final pending = appeal.status == 'pending';
              return Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('申诉 #${appeal.appealId} · 记录 #${appeal.recordId}',
                          style: Theme.of(context).textTheme.titleMedium),
                      const SizedBox(height: 6),
                      Text(appeal.reason),
                      const SizedBox(height: 6),
                      Text('状态：${appeal.status} · 用户：${appeal.userId}'),
                      if (pending) ...[
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          children: [
                            OutlinedButton.icon(
                              onPressed: () => _startAgentReview(appeal),
                              icon: const Icon(Icons.smart_toy_outlined),
                              label: const Text('Agent 建议'),
                            ),
                            FilledButton(
                              onPressed: () => _review(appeal, 'approved'),
                              child: const Text('批准'),
                            ),
                            TextButton(
                              onPressed: () => _review(appeal, 'rejected'),
                              child: const Text('拒绝'),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }
}

class _AdminAgentRunsTab extends StatefulWidget {
  const _AdminAgentRunsTab({required this.api, required this.token});

  final FitLoopApi api;
  final String token;

  @override
  State<_AdminAgentRunsTab> createState() => _AdminAgentRunsTabState();
}

class _AdminAgentRunsTabState extends State<_AdminAgentRunsTab> {
  late Future<AdminAgentRunPage> _future;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  void _refresh() {
    _future = widget.api.adminListAgentRuns(
      token: widget.token,
      type: 'APPEAL_REVIEW',
    );
  }

  Future<void> _decideProposal(
    BuildContext dialogContext,
    AgentProposalItem proposal, {
    required bool confirm,
  }) async {
    try {
      if (confirm) {
        await widget.api.confirmAgentProposal(
          token: widget.token,
          proposalId: proposal.proposalId,
        );
      } else {
        await widget.api.rejectAgentProposal(
          token: widget.token,
          proposalId: proposal.proposalId,
          reason: '管理员拒绝 Agent 建议',
        );
      }
      if (dialogContext.mounted) Navigator.pop(dialogContext);
      if (!mounted) return;
      setState(_refresh);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(confirm ? '已确认 Agent 建议' : '已拒绝 Agent 建议')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(friendlyErrorMsg(error))));
    }
  }

  Future<void> _showAudit(AdminAgentRunItem item) async {
    try {
      final audit = await widget.api.adminGetAgentRunAudit(
        token: widget.token,
        runId: item.runId,
      );
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text('Agent 建议 · ${audit.status}'),
          content: SizedBox(
            width: 520,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('模型：${audit.model ?? "-"}'),
                  Text('Prompt：${audit.promptVersion ?? "-"}'),
                  Text('工具调用：${audit.toolCalls.length} 次'),
                  const Divider(),
                  SelectableText(audit.resultJson ?? '尚未生成建议'),
                  for (final proposal in audit.proposals) ...[
                    const Divider(),
                    Text('操作提案：${proposal.actionType}'),
                    SelectableText(proposal.payloadJson),
                    Text('状态：${proposal.status}'),
                    if (proposal.status == 'PENDING')
                      Wrap(
                        spacing: 8,
                        children: [
                          FilledButton(
                            onPressed: () => _decideProposal(
                              ctx,
                              proposal,
                              confirm: true,
                            ),
                            child: const Text('人工确认执行'),
                          ),
                          TextButton(
                            onPressed: () => _decideProposal(
                              ctx,
                              proposal,
                              confirm: false,
                            ),
                            child: const Text('拒绝建议'),
                          ),
                        ],
                      ),
                  ],
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx), child: const Text('关闭')),
          ],
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(friendlyErrorMsg(error))));
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<AdminAgentRunPage>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(child: Text(friendlyErrorMsg(snapshot.error)));
        }
        final runs = snapshot.data!.items;
        if (runs.isEmpty) return const Center(child: Text('暂无 Agent 审核任务'));
        return RefreshIndicator(
          onRefresh: () async => setState(_refresh),
          child: ListView.builder(
            padding: const EdgeInsets.all(12),
            itemCount: runs.length,
            itemBuilder: (context, index) {
              final run = runs[index];
              return Card(
                child: ListTile(
                  leading: const Icon(Icons.smart_toy_outlined),
                  title: Text('申诉 #${run.subjectResourceId ?? "-"}'),
                  subtitle: Text('${run.status} · ${run.model ?? "等待模型"}'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => _showAudit(run),
                ),
              );
            },
          ),
        );
      },
    );
  }
}

class _AdminUsersTab extends StatelessWidget {
  const _AdminUsersTab({required this.api, required this.token});
  final FitLoopApi api;
  final String token;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<AdminUserListResponse>(
      future: api.adminListUsers(token: token),
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
                        token: token, userId: u.userId);
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
  const _AdminFeedbackTab({required this.api, required this.token});
  final FitLoopApi api;
  final String token;

  @override
  State<_AdminFeedbackTab> createState() => _AdminFeedbackTabState();
}

class _AdminFeedbackTabState extends State<_AdminFeedbackTab> {
  late Future<FeedbackListResponse> _future;

  @override
  void initState() {
    super.initState();
    _future = widget.api.adminListFeedback(token: widget.token);
  }

  void _refresh() {
    setState(() {
      _future = widget.api.adminListFeedback(token: widget.token);
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
                title: Text(f.type == 'bug'
                    ? '问题反馈'
                    : (f.type == 'feature' ? '功能建议' : '其他')),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(f.content,
                        maxLines: 2, overflow: TextOverflow.ellipsis),
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
                              token: widget.token,
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

class _AdminAuditPage extends StatefulWidget {
  const _AdminAuditPage({required this.api, required this.token});

  final FitLoopApi api;
  final String token;

  @override
  State<_AdminAuditPage> createState() => _AdminAuditPageState();
}

class _AdminAuditPageState extends State<_AdminAuditPage> {
  late Future<AdminAuditPage> _future;

  @override
  void initState() {
    super.initState();
    _future = widget.api.adminListAuditLogs(token: widget.token);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('管理审计记录')),
      body: FutureBuilder<AdminAuditPage>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text(friendlyErrorMsg(snapshot.error)));
          }
          final entries = snapshot.data!.items;
          if (entries.isEmpty) return const Center(child: Text('暂无审计记录'));
          return ListView.builder(
            padding: const EdgeInsets.all(12),
            itemCount: entries.length,
            itemBuilder: (context, index) {
              final entry = entries[index];
              return Card(
                child: ListTile(
                  title: Text(entry.action),
                  subtitle: Text(
                    '${entry.resourceType} #${entry.resourceId}\n'
                    '操作者：${entry.actorUserId} · ${entry.createdAt}',
                  ),
                  isThreeLine: true,
                ),
              );
            },
          );
        },
      ),
    );
  }
}
