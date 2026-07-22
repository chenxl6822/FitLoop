part of '../../main.dart';

abstract class LocationService {
  Future<LocationPermission> checkPermission();

  Future<LocationPermission> requestPermission();

  Future<Position> getCurrentPosition();

  Stream<Position> getPositionStream({required LocationSettings settings});
}

class GeolocatorLocationService implements LocationService {
  @override
  Future<LocationPermission> checkPermission() {
    return Geolocator.checkPermission();
  }

  @override
  Future<Position> getCurrentPosition() {
    return Geolocator.getCurrentPosition();
  }

  @override
  Stream<Position> getPositionStream({required LocationSettings settings}) {
    return Geolocator.getPositionStream(locationSettings: settings);
  }

  @override
  Future<LocationPermission> requestPermission() {
    return Geolocator.requestPermission();
  }
}

abstract class PedometerService {
  Stream<int> get stepCountStream;

  Future<int> get currentStepCount;

  void dispose();
}

class AndroidPedometerService implements PedometerService {
  AndroidPedometerService();

  int _initialSteps = 0;
  bool _initialized = false;
  StreamSubscription<StepCount>? _subscription;
  final StreamController<int> _stepController =
      StreamController<int>.broadcast();

  @override
  Future<int> get currentStepCount async {
    return 0;
  }

  @override
  Stream<int> get stepCountStream {
    _subscription = Pedometer.stepCountStream.listen((event) {
      final steps = event.steps;
      if (!_initialized) {
        _initialSteps = steps;
        _initialized = true;
        _stepController.add(0);
        return;
      }
      _stepController.add(steps - _initialSteps);
    });
    return _stepController.stream;
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _stepController.close();
  }
}

class SportSessionPage extends StatefulWidget {
  const SportSessionPage({
    super.key,
    required this.api,
    required this.locationService,
    required this.session,
    this.onSportActiveChanged,
  });

  final FitLoopApi api;
  final LocationService locationService;
  final UserSession session;
  final ValueChanged<bool>? onSportActiveChanged;

  @override
  State<SportSessionPage> createState() => _SportSessionPageState();
}

class _SportSessionPageState extends State<SportSessionPage> {
  static const _maxAcceptedAccuracyMeters = 50.0;

  String? _sessionId;
  SportRecord? _lastRecord;
  bool _busy = false;
  String _status = '未开始';
  DateTime? _startedAt;
  StreamSubscription<Position>? _positionSubscription;
  int _trackPointCount = 0;
  int _trackingGeneration = 0;
  // GPS 实时状态
  double? _currentLat;
  double? _currentLng;
  double? _currentAccuracy;
  double _totalDistanceKm = 0;
  double? _lastLat;
  double? _lastLng;
  double? _currentSpeedMs;
  bool _isPaused = false;
  Timer? _elapsedTimer;
  int _activeSeconds = 0;
  Future<_SportAppealSnapshot>? _appealFuture;

  String _selectedSportType = 'running';
  String _selectedCheckinMode = 'gps';
  int _stepCount = 0;
  PedometerService? _pedometerService;
  StreamSubscription<int>? _stepSubscription;

  @override
  void initState() {
    super.initState();
    _appealFuture = _loadAppealCenter();
  }

  Future<_SportAppealSnapshot> _loadAppealCenter() async {
    final appealsFuture = widget.api.listAppeals(token: widget.session.token);
    final recordsFuture =
        widget.api.listSportRecords(token: widget.session.token);
    return _SportAppealSnapshot(
      appeals: await appealsFuture,
      records: await recordsFuture,
    );
  }

  void _refreshAppealCenter() {
    setState(() {
      _appealFuture = _loadAppealCenter();
    });
  }

  @override
  void dispose() {
    widget.onSportActiveChanged?.call(false);
    _trackingGeneration++;
    _positionSubscription?.cancel();
    _stepSubscription?.cancel();
    _pedometerService?.dispose();
    _elapsedTimer?.cancel();
    _durationController.dispose();
    _distanceController.dispose();
    _calorieController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  bool _isOutdoorSport(String type) {
    return {'running', 'cycling', 'walking'}.contains(type);
  }

  Future<String?> _chooseCheckinMode() {
    final outdoor = _isOutdoorSport(_selectedSportType);
    return showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          if (outdoor)
            ListTile(
              leading: const Icon(Icons.location_on),
              title: const Text('GPS 定位打卡'),
              subtitle: const Text('实时定位追踪轨迹'),
              onTap: () => Navigator.pop(ctx, 'gps'),
            ),
          ListTile(
            leading: const Icon(Icons.sensors_outlined),
            title: const Text('传感器打卡'),
            subtitle: const Text('记录步数或活动数据'),
            onTap: () => Navigator.pop(ctx, 'sensor'),
          ),
          ListTile(
            leading: const Icon(Icons.timer_outlined),
            title: const Text('计时打卡'),
            subtitle: const Text('记录运动时长'),
            onTap: () => Navigator.pop(ctx, 'timer'),
          ),
          if (!outdoor)
            ListTile(
              leading: const Icon(Icons.fitness_center),
              title: const Text('次数打卡'),
              subtitle: const Text('记录运动次数/组数'),
              onTap: () => Navigator.pop(ctx, 'count'),
            ),
          if (!outdoor)
            ListTile(
              leading: const Icon(Icons.local_fire_department),
              title: const Text('热量估算'),
              subtitle: const Text('根据运动类型估算消耗'),
              onTap: () => Navigator.pop(ctx, 'calorie'),
            ),
          ListTile(
            leading: const Icon(Icons.edit),
            title: const Text('手动打卡'),
            subtitle: const Text('自行输入运动数据'),
            onTap: () => Navigator.pop(ctx, 'manual'),
          ),
        ]),
      ),
    );
  }

  Future<void> _toggle() async {
    if (_sessionId == null) {
      final mode = await _chooseCheckinMode();
      if (mode == null || !mounted) return;
      _selectedCheckinMode = mode;

      switch (mode) {
        case 'gps':
          await _startGpsCheckin();
        case 'sensor':
          await _startSensorCheckin();
        case 'timer':
          await _startTimerCheckin();
        case 'count':
          await _startManualCheckin(checkinMode: 'count');
        case 'calorie':
          await _startManualCheckin(checkinMode: 'calorie');
        case 'manual':
          await _startManualCheckin();
      }
    } else {
      await _finishCheckin();
    }
  }

  Future<void> _startGpsCheckin() async {
    final canUseLocation = await _ensureLocationPermission();
    if (!canUseLocation) return;

    setState(() => _busy = true);
    try {
      await _stopGpsTracking();
      final start = await widget.api.startSport(
        token: widget.session.token,
        sportType: _selectedSportType,
        checkinMode: 'gps',
      );
      final startedAt = DateTime.now();
      setState(() {
        _sessionId = start.sessionId;
        _startedAt = startedAt;
        _trackPointCount = 0;
        _totalDistanceKm = 0;
        _lastLat = null;
        _lastLng = null;
        _currentSpeedMs = null;
        _currentLat = null;
        _currentLng = null;
        _currentAccuracy = null;
        _isPaused = false;
        _activeSeconds = 0;
        _status = 'GPS 打卡进行中，正在获取位置...';
        _busy = false;
      });
      widget.onSportActiveChanged?.call(true);
      _startGpsTracking(start.sessionId);
      _startElapsedTimer();
    } catch (error) {
      setState(() {
        _status = friendlyErrorMsg(error);
        _busy = false;
      });
    }
  }

  Future<void> _startTimerCheckin() async {
    setState(() => _busy = true);
    try {
      final start = await widget.api.startSport(
        token: widget.session.token,
        sportType: _selectedSportType,
        checkinMode: 'timer',
      );
      final startedAt = DateTime.now();
      setState(() {
        _sessionId = start.sessionId;
        _startedAt = startedAt;
        _isPaused = false;
        _activeSeconds = 0;
        _status = '计时打卡进行中';
        _busy = false;
      });
      widget.onSportActiveChanged?.call(true);
      _startElapsedTimer();
    } catch (error) {
      setState(() {
        _status = friendlyErrorMsg(error);
        _busy = false;
      });
    }
  }

  Future<void> _startSensorCheckin() async {
    setState(() => _busy = true);
    try {
      final start = await widget.api.startSport(
        token: widget.session.token,
        sportType: _selectedSportType,
        checkinMode: 'sensor',
      );
      final startedAt = DateTime.now();
      _stepCount = 0;
      _pedometerService = AndroidPedometerService();
      _stepSubscription = _pedometerService!.stepCountStream.listen((steps) {
        if (mounted) {
          setState(() {
            _stepCount = steps;
            _status = '传感器打卡进行中，当前步数：$steps';
          });
        }
      });
      setState(() {
        _sessionId = start.sessionId;
        _startedAt = startedAt;
        _status = '传感器打卡进行中，正在记录步数...';
        _busy = false;
      });
      widget.onSportActiveChanged?.call(true);
    } catch (error) {
      setState(() {
        _status = friendlyErrorMsg(error);
        _busy = false;
      });
    }
  }

  Future<void> _startManualCheckin({String checkinMode = 'manual'}) async {
    final data = await _showManualCheckinForm();
    if (data == null || !mounted) return;

    setState(() => _busy = true);
    try {
      final start = await widget.api.startSport(
        token: widget.session.token,
        sportType: _selectedSportType,
        checkinMode: checkinMode,
      );
      final durationMinutes = data['durationMinutes'] as int;
      final distanceKm = data['distanceKm'] as double?;
      final calorie = data['calorie'] as double?;
      final note = data['note'] as String?;

      final record = await widget.api.finishSport(
        token: widget.session.token,
        sessionId: start.sessionId,
        durationSeconds: durationMinutes * 60,
        weightKg: 60,
        distanceKm: distanceKm,
        calorie: calorie,
        note: note,
      );
      setState(() {
        _lastRecord = record;
        _status = '已保存手动打卡记录 #${record.recordId}';
        _busy = false;
      });
    } catch (error) {
      setState(() {
        _status = friendlyErrorMsg(error);
        _busy = false;
      });
    }
  }

  Future<void> _finishCheckin() async {
    setState(() {
      _busy = true;
      _status = '结算中，请稍候...';
    });
    try {
      if (_selectedCheckinMode == 'gps') {
        await _stopGpsTracking();

        Position? lastPosition;
        try {
          lastPosition = await widget.locationService.getCurrentPosition();
        } catch (_) {}

        if (lastPosition != null &&
            await _uploadTrackPoint(_sessionId!, lastPosition)) {
          _trackPointCount++;
        }
      }

      if (_selectedCheckinMode == 'sensor') {
        _stepSubscription?.cancel();
        _pedometerService?.dispose();
      }

      final duration = DateTime.now()
          .difference(_startedAt ?? DateTime.now())
          .inSeconds
          .clamp(1, 24 * 3600)
          .toInt();

      double? distanceKm;
      if (_selectedCheckinMode == 'gps' && _totalDistanceKm > 0) {
        distanceKm = _totalDistanceKm;
      } else if (_selectedCheckinMode == 'sensor' && _stepCount > 0) {
        distanceKm = _stepCount * 0.7 / 1000.0;
      }

      final record = await widget.api.finishSport(
        token: widget.session.token,
        sessionId: _sessionId!,
        durationSeconds: duration,
        weightKg: 60,
        distanceKm: distanceKm,
      );

      var statusMsg = '已保存记录 #${record.recordId}';
      if (_selectedCheckinMode == 'gps') {
        statusMsg += '，共上传 $_trackPointCount 个轨迹点';
      } else if (_selectedCheckinMode == 'sensor') {
        statusMsg +=
            '，步数 $_stepCount，距离 ${distanceKm?.toStringAsFixed(2) ?? "0"} km';
      }

      _elapsedTimer?.cancel();
      _elapsedTimer = null;
      setState(() {
        _sessionId = null;
        _startedAt = null;
        _trackPointCount = 0;
        _stepCount = 0;
        _isPaused = false;
        _activeSeconds = 0;
        _totalDistanceKm = 0;
        _currentLat = null;
        _currentLng = null;
        _currentSpeedMs = null;
        _lastRecord = record;
        _status = statusMsg;
        _appealFuture = _loadAppealCenter();
      });
      widget.onSportActiveChanged?.call(false);
    } catch (error) {
      if (_sessionId != null) {
        final duration = DateTime.now()
            .difference(_startedAt ?? DateTime.now())
            .inSeconds
            .clamp(1, 24 * 3600)
            .toInt();
        final pending = PendingFinishRecord(
          token: widget.session.token,
          sessionId: _sessionId!,
          durationSeconds: duration,
          weightKg: 60,
        );
        await SyncQueue.enqueueFinish(pending);
        if (!mounted) return;
        _elapsedTimer?.cancel();
        _elapsedTimer = null;
        setState(() {
          _sessionId = null;
          _startedAt = null;
          _trackPointCount = 0;
          _stepCount = 0;
          _isPaused = false;
          _activeSeconds = 0;
          _totalDistanceKm = 0;
          _currentLat = null;
          _currentLng = null;
          _currentSpeedMs = null;
          _status = '网络暂时不可用，已加入离线同步队列，联网后自动提交';
        });
        widget.onSportActiveChanged?.call(false);
      } else {
        setState(() => _status = friendlyErrorMsg(error));
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  final _durationController = TextEditingController();
  final _distanceController = TextEditingController();
  final _calorieController = TextEditingController();
  final _noteController = TextEditingController();

  Future<Map<String, dynamic>?> _showManualCheckinForm() async {
    return showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: SingleChildScrollView(
          child: Padding(
            padding: EdgeInsets.only(
              bottom: MediaQuery.of(ctx).viewInsets.bottom,
              left: 16,
              right: 16,
              top: 16,
            ),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Text('手动打卡',
                  style: Theme.of(ctx)
                      .textTheme
                      .titleLarge
                      ?.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: 16),
              TextField(
                decoration: const InputDecoration(
                    labelText: '运动时长（分钟）',
                    prefixIcon: Icon(Icons.timer_outlined)),
                keyboardType: TextInputType.number,
                controller: _durationController,
              ),
              const SizedBox(height: 12),
              TextField(
                decoration: const InputDecoration(
                    labelText: '运动距离（公里，可选）',
                    prefixIcon: Icon(Icons.route_outlined)),
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                controller: _distanceController,
              ),
              const SizedBox(height: 12),
              TextField(
                decoration: const InputDecoration(
                    labelText: '消耗卡路里（可选）',
                    prefixIcon: Icon(Icons.bolt_outlined)),
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                controller: _calorieController,
              ),
              const SizedBox(height: 12),
              TextField(
                decoration: const InputDecoration(
                    labelText: '备注（可选）',
                    prefixIcon: Icon(Icons.notes_outlined)),
                controller: _noteController,
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: () {
                  final duration = int.tryParse(_durationController.text) ?? 30;
                  if (duration <= 0 || duration > 1440) {
                    ScaffoldMessenger.of(ctx).showSnackBar(
                      const SnackBar(content: Text('运动时长必须在 1-1440 分钟之间')),
                    );
                    return;
                  }
                  Navigator.pop(ctx, {
                    'durationMinutes': duration,
                    'distanceKm': double.tryParse(_distanceController.text),
                    'calorie': double.tryParse(_calorieController.text),
                    'note': _noteController.text,
                  });
                },
                child: const Text('提交'),
              ),
              const SizedBox(height: 16),
            ]),
          ),
        ),
      ),
    );
  }

  Future<bool> _ensureLocationPermission() async {
    final permission = await widget.locationService.checkPermission();
    if (_canUseLocation(permission)) {
      return true;
    }
    if (permission == LocationPermission.denied) {
      final result = await widget.locationService.requestPermission();
      if (_canUseLocation(result)) {
        return true;
      }
    }
    if (mounted) {
      setState(() => _status = '需要位置权限才能使用GPS打卡');
    }
    return false;
  }

  bool _canUseLocation(LocationPermission permission) {
    return permission == LocationPermission.always ||
        permission == LocationPermission.whileInUse;
  }

  bool _hasUsableAccuracy(Position position) {
    return position.accuracy.isFinite &&
        position.accuracy >= 0 &&
        position.accuracy <= _maxAcceptedAccuracyMeters;
  }

  Future<bool> _uploadTrackPoint(String sessionId, Position position) async {
    if (!_hasUsableAccuracy(position)) {
      if (mounted) {
        setState(() {
          _status =
              'GPS精度不足，已忽略本次轨迹点（${position.accuracy.toStringAsFixed(1)}m）';
        });
      }
      return false;
    }

    await widget.api.uploadTrackPoint(
      token: widget.session.token,
      point: TrackPoint(
        sessionId: sessionId,
        lat: position.latitude,
        lng: position.longitude,
        accuracy: position.accuracy,
        timestamp: position.timestamp,
      ),
    );
    return true;
  }

  /// Haversine 公式计算两点间距离 (km)
  double _haversineKm(double lat1, double lng1, double lat2, double lng2) {
    const r = 6371.0;
    final dLat = _degToRad(lat2 - lat1);
    final dLng = _degToRad(lng2 - lng1);
    final a = sin(dLat / 2) * sin(dLat / 2) +
        cos(_degToRad(lat1)) *
            cos(_degToRad(lat2)) *
            sin(dLng / 2) *
            sin(dLng / 2);
    return r * 2 * atan2(sqrt(a), sqrt(1 - a));
  }

  double _degToRad(double deg) => deg * pi / 180.0;

  void _startGpsTracking(String sessionId) {
    const throttleSeconds = 5;
    DateTime? lastUpload;
    final generation = ++_trackingGeneration;

    _positionSubscription = widget.locationService
        .getPositionStream(
      settings: const LocationSettings(
        accuracy: LocationAccuracy.bestForNavigation,
        distanceFilter: 10,
      ),
    )
        .listen((position) {
      if (!_isCurrentTrackingSession(generation, sessionId) || _isPaused) {
        return;
      }
      final now = DateTime.now();

      // 更新实时位置和精度
      if (mounted) {
        setState(() {
          _currentLat = position.latitude;
          _currentLng = position.longitude;
          _currentAccuracy = position.accuracy;
        });
      }

      if (!_hasUsableAccuracy(position)) {
        if (mounted) {
          setState(() {
            _status = 'GPS精度不足 (${position.accuracy.toStringAsFixed(1)}m)，已忽略';
          });
        }
        return;
      }

      // 计算实时距离增量
      if (_lastLat != null && _lastLng != null) {
        final segKm = _haversineKm(
            _lastLat!, _lastLng!, position.latitude, position.longitude);
        if (mounted) {
          setState(() => _totalDistanceKm += segKm);
        }
      }
      _lastLat = position.latitude;
      _lastLng = position.longitude;

      // 计算当前速度 (m/s)
      if (position.speed >= 0) {
        if (mounted) setState(() => _currentSpeedMs = position.speed);
      }

      // 节流上传
      if (lastUpload != null &&
          now.difference(lastUpload!).inSeconds < throttleSeconds) {
        return;
      }
      lastUpload = now;

      // 异步上传到后端
      _uploadTrackPoint(sessionId, position).then((_) {
        if (!_isCurrentTrackingSession(generation, sessionId)) return;
        _trackPointCount++;
        if (mounted) {
          setState(() {
            _status = 'GPS 打卡进行中，已上传 $_trackPointCount 个轨迹点';
          });
        }
      }).catchError((error) {
        if (mounted) {
          setState(() => _status = 'GPS轨迹点上传失败：${friendlyErrorMsg(error)}');
        }
      });
    }, onError: (Object error) {
      if (!_isCurrentTrackingSession(generation, sessionId)) return;
      if (mounted) {
        setState(() => _status = 'GPS定位失败：${friendlyErrorMsg(error)}');
      }
    });
  }

  void _startElapsedTimer() {
    _elapsedTimer?.cancel();
    _elapsedTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_isPaused || !mounted) return;
      setState(() => _activeSeconds++);
    });
  }

  void _togglePause() {
    if (!_isPaused) {
      setState(() {
        _isPaused = true;
        _status = 'GPS 打卡已暂停';
      });
    } else {
      setState(() {
        _isPaused = false;
        _status = 'GPS 打卡进行中，已上传 $_trackPointCount 个轨迹点';
      });
    }
  }

  String _formatDuration(int totalSeconds) {
    final h = totalSeconds ~/ 3600;
    final m = (totalSeconds % 3600) ~/ 60;
    final s = totalSeconds % 60;
    if (h > 0) {
      return '$h时${m.toString().padLeft(2, '0')}分${s.toString().padLeft(2, '0')}秒';
    }
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  String _formatPace(int totalSeconds, double distanceKm) {
    if (distanceKm < 0.01) return '--';
    final paceSeconds = totalSeconds / distanceKm;
    final paceMin = paceSeconds ~/ 60;
    final paceSec = (paceSeconds % 60).toInt();
    return '$paceMin\'${paceSec.toString().padLeft(2, '0')}"';
  }

  bool _isCurrentTrackingSession(int generation, String sessionId) {
    return _trackingGeneration == generation && _sessionId == sessionId;
  }

  Future<void> _stopGpsTracking() {
    _trackingGeneration++;
    final subscription = _positionSubscription;
    _positionSubscription = null;
    if (subscription != null) {
      unawaited(subscription.cancel());
    }
    _elapsedTimer?.cancel();
    _elapsedTimer = null;
    return Future.value();
  }

  Future<void> _showAppealSheet(int recordId) async {
    final reason = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (context) {
        return _AppealFormSheet(
          api: widget.api,
          token: widget.session.token,
          recordId: recordId,
        );
      },
    );
    if (reason != null && mounted) {
      _refreshAppealCenter();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('申诉已提交')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final running = _sessionId != null;
    final lastRecord = _lastRecord;
    return _PageScaffold(
      title: '运动打卡',
      children: [
        if (!running) ...[
          Card(
            margin: const EdgeInsets.only(bottom: 12),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('选择运动类型：',
                      style: Theme.of(context).textTheme.labelLarge),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String>(
                    initialValue: _selectedSportType,
                    decoration: const InputDecoration(
                      prefixIcon: Icon(Icons.fitness_center_outlined),
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    items: _sportTypes.entries
                        .map((e) => DropdownMenuItem(
                              value: e.key,
                              child: Text(e.value),
                            ))
                        .toList(),
                    onChanged: (v) => setState(() => _selectedSportType = v!),
                  ),
                ],
              ),
            ),
          ),
        ],
        FilledButton.icon(
          key: const Key('sport-session-toggle'),
          onPressed: _busy ? null : _toggle,
          icon: Icon(running ? Icons.stop : Icons.play_arrow),
          label: Text(running ? '结束打卡' : '开始打卡'),
        ),
        _MetricCard(
            label: '当前状态', value: _status, icon: Icons.sensors_outlined),
        _MetricCard(
            label: '运动类型',
            value: _sportTypes[_selectedSportType] ?? _selectedSportType,
            icon: Icons.fitness_center_outlined),
        _MetricCard(
            label: '打卡方式',
            value: running
                ? _checkinModeLabel(_selectedCheckinMode)
                : 'GPS / 计时 / 传感器 / 手动',
            icon: Icons.tune_outlined),
        // GPS 实时指标
        if (running && _selectedCheckinMode == 'timer') ...[
          _MetricCard(
              label: '已用时间',
              value: _formatDuration(_activeSeconds),
              icon: Icons.timer_outlined),
        ],
        if (running && _selectedCheckinMode == 'gps') ...[
          _MetricCard(
              label: '已用时间',
              value: _formatDuration(_activeSeconds),
              icon: Icons.timer_outlined),
          if (_currentLat != null)
            _MetricCard(
                label: '当前位置',
                value:
                    '${_currentLat!.toStringAsFixed(5)}, ${_currentLng!.toStringAsFixed(5)}',
                icon: Icons.my_location),
          _MetricCard(
              label: '轨迹点数',
              value: '$_trackPointCount 个',
              icon: Icons.route_outlined),
          _MetricCard(
              label: '估算距离',
              value: '${_totalDistanceKm.toStringAsFixed(2)} km',
              icon: Icons.straighten_outlined),
          if (_currentSpeedMs != null)
            _MetricCard(
                label: '当前速度',
                value: '${(_currentSpeedMs! * 3.6).toStringAsFixed(1)} km/h',
                icon: Icons.speed_outlined),
          _MetricCard(
              label: '平均配速',
              value: _formatPace(_activeSeconds, _totalDistanceKm),
              icon: Icons.trending_down_outlined),
          if (_currentAccuracy != null &&
              _currentAccuracy! > _maxAcceptedAccuracyMeters)
            _MetricCard(
                label: 'GPS 精度',
                value: '${_currentAccuracy!.toStringAsFixed(1)}m（信号弱）',
                icon: Icons.warning_amber_outlined),
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _busy ? null : _togglePause,
                    icon: Icon(_isPaused ? Icons.play_arrow : Icons.pause),
                    label: Text(_isPaused ? '继续' : '暂停'),
                  ),
                ),
              ],
            ),
          ),
        ],
        if (running && _selectedCheckinMode == 'sensor') ...[
          _MetricCard(
              label: '当前步数',
              value: '$_stepCount 步',
              icon: Icons.directions_walk),
        ],
        if (lastRecord != null) ...[
          _MetricCard(
            label: '最近一次',
            value:
                '${(lastRecord.durationSeconds / 60).round()} 分钟 / ${lastRecord.calorie.toStringAsFixed(1)} kcal',
            icon: Icons.route_outlined,
          ),
        ],
        FutureBuilder<_SportAppealSnapshot>(
          future: _appealFuture,
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return _AppealCenterError(
                message: friendlyErrorMsg(snapshot.error),
                onRefresh: _refreshAppealCenter,
              );
            }
            final data = snapshot.data;
            if (data == null) {
              return const Card(
                margin: EdgeInsets.only(bottom: 12),
                child: Padding(
                  padding: EdgeInsets.all(20),
                  child: Center(child: CircularProgressIndicator()),
                ),
              );
            }
            return _SportAppealCenter(
              snapshot: data,
              onAppeal: _showAppealSheet,
              onRefresh: _refreshAppealCenter,
            );
          },
        ),
      ],
    );
  }
}

class _SportAppealSnapshot {
  const _SportAppealSnapshot({required this.appeals, required this.records});

  final AppealListResponse appeals;
  final List<SportRecord> records;
}

class _SportAppealCenter extends StatelessWidget {
  const _SportAppealCenter({
    required this.snapshot,
    required this.onAppeal,
    required this.onRefresh,
  });

  final _SportAppealSnapshot snapshot;
  final ValueChanged<int> onAppeal;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    final appeals = snapshot.appeals.appeals;
    final appealedRecordIds = appeals.map((appeal) => appeal.recordId).toSet();
    return Column(
      children: [
        Card(
          key: const Key('sport-records-card'),
          margin: const EdgeInsets.only(bottom: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 8, 4),
                child: Row(
                  children: [
                    const Icon(Icons.history, size: 18),
                    const SizedBox(width: 8),
                    Text('最近运动记录',
                        style: Theme.of(context).textTheme.titleSmall),
                    const Spacer(),
                    IconButton(
                      tooltip: '刷新记录',
                      onPressed: onRefresh,
                      icon: const Icon(Icons.refresh, size: 18),
                    ),
                  ],
                ),
              ),
              if (snapshot.records.isEmpty)
                const Padding(
                  padding: EdgeInsets.fromLTRB(16, 8, 16, 16),
                  child: Text('暂无运动记录'),
                )
              else
                ...snapshot.records.take(10).map((record) {
                  final canAppeal = record.status == 2 &&
                      !appealedRecordIds.contains(record.recordId);
                  final reason = record.abnormalReason;
                  return ListTile(
                    key: Key('sport-record-${record.recordId}'),
                    dense: true,
                    leading: Icon(
                      _sportRecordStatusIcon(record.status),
                      color: _sportRecordStatusColor(context, record.status),
                    ),
                    title: Text(
                      '记录 #${record.recordId} · ${_sportRecordStatusLabel(record.status)}',
                      style: const TextStyle(fontSize: 13),
                    ),
                    subtitle: Text(
                      '${(record.durationSeconds / 60).round()} 分钟 · '
                      '${record.distanceKm.toStringAsFixed(2)} km'
                      '${reason == null || reason.isEmpty ? '' : '\n$reason'}',
                      style: const TextStyle(fontSize: 12),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: canAppeal
                        ? TextButton(
                            key: Key('appeal-record-${record.recordId}'),
                            onPressed: () => onAppeal(record.recordId),
                            child: const Text('申诉'),
                          )
                        : null,
                  );
                }),
            ],
          ),
        ),
        if (appeals.isNotEmpty)
          Card(
            key: const Key('my-appeals-card'),
            margin: const EdgeInsets.only(bottom: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                  child: Row(
                    children: [
                      const Icon(Icons.fact_check_outlined, size: 18),
                      const SizedBox(width: 8),
                      Text('我的申诉 (${appeals.length})',
                          style: Theme.of(context).textTheme.titleSmall),
                    ],
                  ),
                ),
                ...appeals.take(5).map((appeal) => ListTile(
                      dense: true,
                      leading: Icon(
                        _appealStatusIcon(appeal.status),
                        color: _appealStatusColor(context, appeal.status),
                      ),
                      title: Text('记录 #${appeal.recordId}',
                          style: const TextStyle(fontSize: 13)),
                      subtitle: Text(
                        appeal.reason,
                        style: const TextStyle(fontSize: 12),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      trailing: Text(
                        appeal.statusLabel,
                        style: TextStyle(
                          fontSize: 12,
                          color: _appealStatusColor(context, appeal.status),
                        ),
                      ),
                    )),
              ],
            ),
          ),
      ],
    );
  }
}

class _AppealCenterError extends StatelessWidget {
  const _AppealCenterError({required this.message, required this.onRefresh});

  final String message;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        leading: const Icon(Icons.error_outline),
        title: const Text('运动记录加载失败'),
        subtitle: Text(message),
        trailing: IconButton(
          tooltip: '重试',
          onPressed: onRefresh,
          icon: const Icon(Icons.refresh),
        ),
      ),
    );
  }
}

String _sportRecordStatusLabel(int status) => switch (status) {
      0 => '进行中',
      1 => '有效',
      2 => '异常',
      3 => '申诉中',
      _ => '未知',
    };

IconData _sportRecordStatusIcon(int status) => switch (status) {
      1 => Icons.check_circle_outline,
      2 => Icons.warning_amber_outlined,
      3 => Icons.hourglass_empty,
      _ => Icons.directions_run_outlined,
    };

Color _sportRecordStatusColor(BuildContext context, int status) =>
    switch (status) {
      1 => Colors.green,
      2 => Theme.of(context).colorScheme.error,
      3 => Colors.orange,
      _ => Theme.of(context).colorScheme.onSurfaceVariant,
    };

IconData _appealStatusIcon(String status) {
  switch (status) {
    case 'pending':
      return Icons.hourglass_empty;
    case 'approved':
      return Icons.check_circle_outline;
    case 'rejected':
      return Icons.cancel_outlined;
    default:
      return Icons.help_outline;
  }
}

Color _appealStatusColor(BuildContext context, String status) {
  switch (status) {
    case 'pending':
      return Colors.orange;
    case 'approved':
      return Colors.green;
    case 'rejected':
      return Theme.of(context).colorScheme.error;
    default:
      return Colors.grey;
  }
}

class _AppealFormSheet extends StatefulWidget {
  const _AppealFormSheet({
    required this.api,
    required this.token,
    required this.recordId,
  });

  final FitLoopApi api;
  final String token;
  final int recordId;

  @override
  State<_AppealFormSheet> createState() => _AppealFormSheetState();
}

class _AppealFormSheetState extends State<_AppealFormSheet> {
  final _reason = TextEditingController();
  bool _busy = false;
  String? _message;

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final reason = _reason.text.trim();
    if (reason.isEmpty) {
      setState(() => _message = '请输入申诉理由');
      return;
    }
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      await widget.api.createAppeal(
        token: widget.token,
        recordId: widget.recordId,
        reason: reason,
      );
      if (mounted) Navigator.of(context).pop(reason);
    } catch (e) {
      setState(() => _message = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
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
              '提起申诉',
              style: Theme.of(context)
                  .textTheme
                  .titleLarge
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Text('记录 #${widget.recordId}',
                style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 16),
            TextField(
              controller: _reason,
              enabled: !_busy,
              maxLines: 4,
              decoration: const InputDecoration(
                hintText: '请描述申诉理由（如：GPS信号异常、实际已完成运动等）',
                prefixIcon: Icon(Icons.edit_note_outlined),
                border: OutlineInputBorder(),
              ),
            ),
            if (_message != null) ...[
              const SizedBox(height: 12),
              Text(_message!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ],
            const SizedBox(height: 16),
            FilledButton.icon(
              key: const Key('submit-appeal'),
              onPressed: _busy ? null : _submit,
              icon: _busy
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.send),
              label: const Text('提交申诉'),
            ),
          ],
        ),
      ),
    );
  }
}
