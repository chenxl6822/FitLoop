part of '../../main.dart';

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
                  child: Text('隐私与数据',
                      style: Theme.of(context)
                          .textTheme
                          .titleMedium
                          ?.copyWith(fontWeight: FontWeight.w700)),
                ),
                ListTile(
                  key: const Key('privacy-explanation-entry'),
                  leading: const Icon(Icons.privacy_tip_outlined),
                  title: const Text('数据使用说明'),
                  subtitle: const Text('了解轨迹、健康与 AI 数据如何使用'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const _PrivacyPage()),
                  ),
                ),
                const Divider(height: 1, indent: 16, endIndent: 16),
                ListTile(
                  key: const Key('account-data-entry'),
                  leading: const Icon(Icons.manage_accounts_outlined),
                  title: const Text('我的数据与账号'),
                  subtitle: const Text('导出副本或申请注销账号'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => _AccountDataPage(
                        api: api,
                        session: session,
                        onDeleted: onLogout,
                      ),
                    ),
                  ),
                ),
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

class _PrivacyPage extends StatelessWidget {
  const _PrivacyPage();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('数据使用说明')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: const [
          _PrivacySection(
            icon: Icons.route_outlined,
            title: '运动轨迹',
            body:
                '仅在你开始 GPS 运动并授权定位后记录。轨迹详情只对账号本人开放；道路底图需要单独同意，加载时地图服务商会接收瓦片坐标、IP 等必要网络信息。',
          ),
          _PrivacySection(
            icon: Icons.favorite_border,
            title: '健康与训练数据',
            body: '体重、睡眠、饮食、目标和训练记录用于统计与个性化建议。当前版本由你主动录入，不会在后台读取系统健康数据。',
          ),
          _PrivacySection(
            icon: Icons.psychology_outlined,
            title: 'AI 教练',
            body: 'AI 建议仅供训练参考。需要写入训练计划的操作会先展示给你确认；不要在目标描述中填写身份证号、病历等无关敏感信息。',
          ),
          _PrivacySection(
            icon: Icons.lock_outline,
            title: '你的控制权',
            body:
                '你可以在“我的数据与账号”导出副本，或验证当前密码后注销。注销会删除业务数据并撤销会话，同时保留不含联系方式的最小注销标记以维护数据一致性。',
          ),
        ],
      ),
    );
  }
}

class _PrivacySection extends StatelessWidget {
  const _PrivacySection({
    required this.icon,
    required this.title,
    required this.body,
  });

  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: Theme.of(context).colorScheme.primary),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: Theme.of(context)
                          .textTheme
                          .titleMedium
                          ?.copyWith(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 6),
                  Text(body),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AccountDataPage extends StatefulWidget {
  const _AccountDataPage({
    required this.api,
    required this.session,
    this.onDeleted,
  });

  final FitLoopApi api;
  final UserSession session;
  final VoidCallback? onDeleted;

  @override
  State<_AccountDataPage> createState() => _AccountDataPageState();
}

class _AccountDataPageState extends State<_AccountDataPage> {
  bool _exporting = false;
  bool _deleting = false;
  String? _exportedJson;
  String? _error;

  Future<void> _export() async {
    setState(() {
      _exporting = true;
      _error = null;
    });
    try {
      final data =
          await widget.api.exportAccountData(token: widget.session.token);
      if (!mounted) return;
      setState(() =>
          _exportedJson = const JsonEncoder.withIndent('  ').convert(data));
    } catch (error) {
      if (mounted) setState(() => _error = _friendlyError(error));
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  Future<void> _copyExport() async {
    final value = _exportedJson;
    if (value == null) return;
    await Clipboard.setData(ClipboardData(text: value));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('数据副本已复制到剪贴板')),
      );
    }
  }

  Future<void> _confirmDelete() async {
    final password = await showDialog<String>(
      context: context,
      builder: (_) => const _DeleteAccountDialog(),
    );
    if (password == null || password.isEmpty || !mounted) return;

    setState(() {
      _deleting = true;
      _error = null;
    });
    try {
      await widget.api.deleteAccount(
        token: widget.session.token,
        password: password,
      );
      if (!mounted) return;
      widget.onDeleted?.call();
    } catch (error) {
      if (mounted) setState(() => _error = _friendlyError(error));
    } finally {
      if (mounted) setState(() => _deleting = false);
    }
  }

  String _friendlyError(Object error) {
    if (error is ApiException) return error.message;
    return '操作失败，请检查网络后重试';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('我的数据与账号')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('导出数据副本',
                      style: Theme.of(context)
                          .textTheme
                          .titleMedium
                          ?.copyWith(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 8),
                  const Text(
                      '包括账号资料、运动与轨迹、目标、健康记录、提醒、社交关系、申诉、反馈和训练计划。不会包含密码或登录令牌。'),
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    key: const Key('export-account-data'),
                    onPressed: _exporting ? null : _export,
                    icon: _exporting
                        ? const SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.download_outlined),
                    label: Text(_exporting ? '正在准备…' : '生成数据副本'),
                  ),
                  if (_exportedJson != null) ...[
                    const SizedBox(height: 16),
                    Container(
                      key: const Key('account-export-preview'),
                      constraints: const BoxConstraints(maxHeight: 260),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color:
                            Theme.of(context).colorScheme.surfaceContainerLow,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: SingleChildScrollView(
                        child: SelectableText(
                          _exportedJson!,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      key: const Key('copy-account-data'),
                      onPressed: _copyExport,
                      icon: const Icon(Icons.copy_outlined),
                      label: const Text('复制 JSON'),
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('注销账号',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                            color: Theme.of(context).colorScheme.error,
                          )),
                  const SizedBox(height: 8),
                  const Text('建议先导出数据副本。注销成功后会立即退出，且无法恢复原有记录。'),
                  const SizedBox(height: 16),
                  OutlinedButton.icon(
                    key: const Key('delete-account'),
                    onPressed: _deleting ? null : _confirmDelete,
                    icon: _deleting
                        ? const SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.delete_forever_outlined),
                    label: Text(_deleting ? '正在注销…' : '永久注销账号'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(
              _error!,
              key: const Key('account-data-error'),
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
        ],
      ),
    );
  }
}

class _DeleteAccountDialog extends StatefulWidget {
  const _DeleteAccountDialog();

  @override
  State<_DeleteAccountDialog> createState() => _DeleteAccountDialogState();
}

class _DeleteAccountDialogState extends State<_DeleteAccountDialog> {
  final _password = TextEditingController();

  @override
  void dispose() {
    _password.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('永久注销账号？'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('运动轨迹、健康记录、训练计划和社交关系将被删除，此操作不可恢复。请输入当前密码确认。'),
            const SizedBox(height: 16),
            TextField(
              key: const Key('delete-account-password'),
              controller: _password,
              obscureText: true,
              autofocus: true,
              decoration: const InputDecoration(labelText: '当前密码'),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(
          key: const Key('confirm-delete-account'),
          onPressed: () {
            final value = _password.text;
            if (value.isNotEmpty) Navigator.of(context).pop(value);
          },
          child: const Text('确认永久注销'),
        ),
      ],
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
