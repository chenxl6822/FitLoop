part of '../../main.dart';

class AuthGate extends StatefulWidget {
  const AuthGate({
    super.key,
    required this.api,
    required this.locationService,
    required this.reminderScheduler,
  });

  final FitLoopApi api;
  final LocationService locationService;
  final ReminderScheduler reminderScheduler;

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  UserSession? _session;
  StreamSubscription<UserSession?>? _sessionSubscription;

  @override
  void initState() {
    super.initState();
    final api = widget.api;
    if (api is SessionAwareApi) {
      final sessionApi = api as SessionAwareApi;
      _sessionSubscription =
          sessionApi.sessionChanges.listen(_onSessionChanged);
    }
    _tryAutoLogin();
  }

  @override
  void dispose() {
    _sessionSubscription?.cancel();
    super.dispose();
  }

  Future<void> _tryAutoLogin() async {
    try {
      final api = widget.api;
      final restored = api is SessionAwareApi
          ? await (api as SessionAwareApi).restoreSession()
          : await TokenStorage.load();
      if (restored != null && mounted) {
        final prefs = await SharedPreferences.getInstance();
        final avatarUrl = prefs.getString('avatarUrl_${restored.userId}') ??
            restored.avatarUrl;
        setState(() => _session = restored.copyWith(avatarUrl: avatarUrl));
      }
    } catch (error) {
      debugPrint('Secure session restore failed: $error');
    }
  }

  void _onSessionChanged(UserSession? session) {
    if (mounted) setState(() => _session = session);
  }

  Future<void> _logout() async {
    final api = widget.api;
    if (api is SessionAwareApi) {
      await (api as SessionAwareApi).logoutSession();
    } else {
      await TokenStorage.clear();
    }
    if (mounted) setState(() => _session = null);
  }

  @override
  Widget build(BuildContext context) {
    final session = _session;
    if (session != null) {
      return AppShell(
        api: widget.api,
        locationService: widget.locationService,
        reminderScheduler: widget.reminderScheduler,
        session: session,
        onLogout: _logout,
      );
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
  final _account = TextEditingController();
  final _password = TextEditingController();
  final _confirmPassword = TextEditingController();
  final _nickname = TextEditingController();
  final _code = TextEditingController();
  final _accountFocus = FocusNode();
  bool _registerMode = false;
  bool _resetPasswordMode = false;
  bool _busy = false;
  String? _message;
  bool _messageIsSuccess = false;
  String _loginTab = 'password';
  int _countdown = 0;
  bool _rememberMe = true;
  Timer? _countdownTimer;
  FeatureFlags? _features;

  bool get _smsAvailable => _features?.smsEnabled ?? false;

  @override
  void initState() {
    super.initState();
    _loadSavedAccount();
    _fetchFeatures();
  }

  Future<void> _loadSavedAccount() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString('saved_account');
    if (saved != null && saved.isNotEmpty) {
      _account.text = saved;
    }
  }

  Future<void> _fetchFeatures() async {
    try {
      final features = await widget.api.fetchFeatureFlags();
      if (mounted) setState(() => _features = features);
    } catch (_) {
      // 获取失败时使用默认值（SMS 不可用）
    }
  }

  @override
  void dispose() {
    _account.dispose();
    _password.dispose();
    _confirmPassword.dispose();
    _nickname.dispose();
    _code.dispose();
    _accountFocus.dispose();
    _countdownTimer?.cancel();
    super.dispose();
  }

  String _friendlyError(dynamic error) => friendlyErrorMsg(error);

  bool _isPhoneAccount(String value) => RegExp(r'^1\d{10}$').hasMatch(value);
  bool _isEmailAccount(String value) =>
      RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(value);
  bool _isValidAccount(String value) =>
      _isPhoneAccount(value) || _isEmailAccount(value);
  String _channelForAccount(String value) =>
      _isEmailAccount(value) ? 'email' : 'phone';
  String _verificationPurpose() {
    if (_resetPasswordMode) return 'reset_password';
    if (_registerMode) return 'register';
    return 'login';
  }

  Future<void> _sendCode() async {
    final account = _account.text.trim();
    if (account.isEmpty) {
      setState(() {
        _message = '请输入手机号或邮箱';
        _messageIsSuccess = false;
      });
      return;
    }
    if (!_isValidAccount(account)) {
      setState(() {
        _message = '请输入正确的手机号或邮箱';
        _messageIsSuccess = false;
      });
      return;
    }
    final channel = _channelForAccount(account);
    if (channel == 'phone' && !_smsAvailable) {
      setState(() {
        _message = '手机验证码暂未开放，请使用邮箱验证码';
        _messageIsSuccess = false;
      });
      return;
    }
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      final result = await widget.api.sendVerificationCode(
        channel: channel,
        target: account,
        purpose: _verificationPurpose(),
      );
      if (!mounted) return;
      final debugCode = result['debugCode'];
      final serverMessage = result['message'] ?? '验证码已发送';
      setState(() {
        _countdown = 60;
        if (debugCode != null && channel == 'phone' && _smsAvailable) {
          _message = '内测验证码：$debugCode';
        } else if (debugCode != null) {
          _message = '调试验证码：$debugCode';
        } else {
          _message = serverMessage;
        }
        _messageIsSuccess = true;
      });
      _startCountdown();
    } catch (error) {
      setState(() {
        _message = _friendlyError(error);
        _messageIsSuccess = false;
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _startCountdown() {
    _countdownTimer?.cancel();
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      setState(() => _countdown = _countdown > 0 ? _countdown - 1 : 0);
      if (_countdown <= 0) {
        timer.cancel();
      }
    });
  }

  Future<void> _submit() async {
    final account = _account.text.trim();
    if (account.isEmpty) {
      setState(() {
        _message = '请输入手机号或邮箱';
        _messageIsSuccess = false;
      });
      return;
    }
    if (!_isValidAccount(account)) {
      setState(() {
        _message = '请输入正确的手机号或邮箱';
        _messageIsSuccess = false;
      });
      return;
    }
    if (_resetPasswordMode) {
      if (_code.text.trim().isEmpty) {
        setState(() {
          _message = '请输入验证码';
          _messageIsSuccess = false;
        });
        return;
      }
      if (_password.text.isEmpty) {
        setState(() {
          _message = '请输入新密码';
          _messageIsSuccess = false;
        });
        return;
      }
      if (_password.text != _confirmPassword.text) {
        setState(() {
          _message = '两次输入的密码不一致';
          _messageIsSuccess = false;
        });
        return;
      }
    }
    if (_registerMode) {
      if (_password.text.isEmpty) {
        setState(() {
          _message = '请输入密码';
          _messageIsSuccess = false;
        });
        return;
      }
      if (_password.text != _confirmPassword.text) {
        setState(() {
          _message = '两次输入的密码不一致';
          _messageIsSuccess = false;
        });
        return;
      }
      if (_code.text.trim().isEmpty) {
        setState(() {
          _message = '请输入验证码';
          _messageIsSuccess = false;
        });
        return;
      }
    } else if (_loginTab == 'code') {
      final code = _code.text.trim();
      if (code.isEmpty) {
        setState(() {
          _message = '请输入验证码';
          _messageIsSuccess = false;
        });
        return;
      }
    }

    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      if (_resetPasswordMode) {
        await widget.api.resetPassword(
          account: account,
          code: _code.text.trim(),
          newPassword: _password.text,
        );
        if (!mounted) return;
        setState(() {
          _resetPasswordMode = false;
          _registerMode = false;
          _password.clear();
          _confirmPassword.clear();
          _code.clear();
          _message = '密码已重置，请使用新密码登录';
          _messageIsSuccess = true;
        });
        return;
      }
      if (_registerMode) {
        await widget.api.register(
          account: account,
          password: _password.text,
          nickname: _nickname.text.trim().isEmpty
              ? 'FitLoop 用户'
              : _nickname.text.trim(),
          code: _code.text.trim(),
        );
      }
      final loginType =
          _loginTab == 'code' && !_registerMode ? 'code' : 'password';
      final session = await widget.api.login(
        account: account,
        password: loginType == 'password' ? _password.text : null,
        code: loginType == 'code' ? _code.text.trim() : null,
        loginType: loginType,
      );
      final prefs = await SharedPreferences.getInstance();
      if (_rememberMe) {
        await prefs.setString('saved_account', account);
      } else {
        await prefs.remove('saved_account');
      }
      if (mounted) widget.onSignedIn(session);
    } catch (error) {
      if (mounted) {
        setState(() {
          _message = _friendlyError(error);
          _messageIsSuccess = false;
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isCodeLogin = _loginTab == 'code';
    final showCodeInput =
        _resetPasswordMode || (!_registerMode && isCodeLogin) || _registerMode;
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
            Text(
                _resetPasswordMode
                    ? '找回账号密码'
                    : (_registerMode ? '创建账号' : '校园运动打卡与健康管理'),
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 24),
            // Login mode: show password/code toggle
            if (!_registerMode && !_resetPasswordMode)
              Row(
                children: [
                  Expanded(
                    child: ChoiceChip(
                      label: const Text('密码登录'),
                      selected: _loginTab == 'password',
                      onSelected: _busy
                          ? null
                          : (_) => setState(() => _loginTab = 'password'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ChoiceChip(
                      label: const Text('验证码登录'),
                      selected: _loginTab == 'code',
                      onSelected: _busy
                          ? null
                          : (_) => setState(() => _loginTab = 'code'),
                    ),
                  ),
                ],
              ),
            if (!_registerMode) const SizedBox(height: 16),
            // Account input
            TextField(
              controller: _account,
              focusNode: _accountFocus,
              autofocus: true,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.phone_android), labelText: '手机号或邮箱'),
            ),
            // 手机验证码未开放提示
            if (isCodeLogin &&
                _isPhoneAccount(_account.text.trim()) &&
                !_smsAvailable) ...[
              const SizedBox(height: 8),
              Text(
                '手机验证码暂未开放，请使用邮箱',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.error,
                  fontSize: 12,
                ),
              ),
            ],
            // Password login: password field only
            if (!_registerMode && !_resetPasswordMode && !isCodeLogin) ...[
              const SizedBox(height: 12),
              TextField(
                controller: _password,
                obscureText: true,
                decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.lock_outline), labelText: '密码'),
              ),
            ],
            // Register mode: password + confirm + nickname
            if (_registerMode || _resetPasswordMode) ...[
              const SizedBox(height: 12),
              TextField(
                controller: _password,
                obscureText: true,
                decoration: InputDecoration(
                    prefixIcon: const Icon(Icons.lock_outline),
                    labelText: _resetPasswordMode ? '新密码' : '密码'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _confirmPassword,
                obscureText: true,
                decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.lock_outline), labelText: '确认密码'),
              ),
              if (_registerMode) ...[
                const SizedBox(height: 12),
                TextField(
                  controller: _nickname,
                  decoration: const InputDecoration(
                      prefixIcon: Icon(Icons.badge_outlined), labelText: '昵称'),
                ),
              ],
            ],
            // Verification code input + send button
            if (showCodeInput) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _code,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                          prefixIcon: Icon(Icons.pin_outlined),
                          labelText: '验证码'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  FilledButton.tonal(
                    onPressed: (_busy || _countdown > 0) ? null : _sendCode,
                    child: Text(_countdown > 0 ? '${_countdown}s' : '获取验证码'),
                  ),
                ],
              ),
            ],
            // Message
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
            const SizedBox(height: 20),
            // Remember me
            if (!_registerMode && !_resetPasswordMode)
              CheckboxListTile(
                value: _rememberMe,
                onChanged: _busy
                    ? null
                    : (v) => setState(() => _rememberMe = v ?? true),
                title: const Text('记住账号', style: TextStyle(fontSize: 14)),
                controlAffinity: ListTileControlAffinity.leading,
                dense: true,
                contentPadding: EdgeInsets.zero,
              ),
            // Submit button
            FilledButton.icon(
              onPressed: _busy ? null : _submit,
              icon: _busy
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : Icon(_resetPasswordMode
                      ? Icons.lock_reset
                      : (_registerMode ? Icons.person_add_alt : Icons.login)),
              label: Text(_resetPasswordMode
                  ? '重置密码'
                  : (_registerMode ? '注册并进入' : '登录')),
            ),
            if (!_registerMode && !_resetPasswordMode)
              TextButton(
                onPressed: _busy
                    ? null
                    : () => setState(() {
                          _resetPasswordMode = true;
                          _message = null;
                          _code.clear();
                          _password.clear();
                          _confirmPassword.clear();
                        }),
                child: const Text('忘记密码'),
              ),
            // Toggle register/login
            TextButton(
              onPressed: _busy
                  ? null
                  : () => setState(() {
                        if (_resetPasswordMode) {
                          _resetPasswordMode = false;
                          _registerMode = false;
                        } else {
                          _registerMode = !_registerMode;
                        }
                        _message = null;
                        _code.clear();
                      }),
              child: Text(_resetPasswordMode
                  ? '返回登录'
                  : (_registerMode ? '已有账号，去登录' : '没有账号，创建账号')),
            ),
          ],
        ),
      ),
    );
  }
}
