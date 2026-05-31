import 'dart:async';
import 'dart:io';

import 'api_config.dart';

/// 网络连通性监测（HTTP 探测式，纯 dart:io，无需原生插件）
class ConnectivityService {
  ConnectivityService({this.checkInterval = const Duration(seconds: 30)});

  final Duration checkInterval;

  /// 上一次探测是否在线。
  bool _online = true;
  bool get online => _online;

  final StreamController<bool> _statusController =
      StreamController<bool>.broadcast();

  /// 订阅网络状态变化。
  Stream<bool> get onStatusChange => _statusController.stream;

  Timer? _timer;

  /// 启动定期探测。
  void start() {
    _check();
    _timer = Timer.periodic(checkInterval, (_) => _check());
  }

  /// 停止探测。
  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  /// 主动触发一次探测。
  Future<bool> checkNow() => _check();

  Future<bool> _check() async {
    final old = _online;

    // 后端健康检查 + 外网 fallback
    _online = await _reachable('${ApiConfig.baseUrl}/actuator/health') ||
        await _reachable('https://www.baidu.com');

    if (old != _online) {
      _statusController.add(_online);
    }
    return _online;
  }

  Future<bool> _reachable(String url) async {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 5);
    try {
      final request = await client.getUrl(Uri.parse(url));
      request.followRedirects = false;
      final response = await request.close();
      await response.drain();
      return true;
    } catch (_) {
      return false;
    } finally {
      client.close(force: true);
    }
  }

  void dispose() {
    stop();
    _statusController.close();
  }
}
