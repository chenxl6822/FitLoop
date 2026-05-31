/// FitLoop API 统一配置
///
/// 使用方法：
///
/// **生产 APK / 下载站：**
///   默认使用 http://43.139.72.25
///
/// **开发调试（电脑本机）：**
///   flutter run --dart-define=FITLOOP_API_BASE_URL=http://localhost:8080
///
/// **Android 模拟器访问本机后端：**
///   flutter run --dart-define=FITLOOP_API_BASE_URL=http://10.0.2.2:8080
///
/// **真机访问电脑后端（同 WiFi）：**
///   flutter run --dart-define=FITLOOP_API_BASE_URL=http://192.168.x.x:8080
///   （替换为电脑的局域网 IP，如 192.168.1.100）
///
/// **访问云服务器：**
///   flutter run --dart-define=FITLOOP_API_BASE_URL=https://your-domain.com
///
/// **构建 APK（真机 / 生产环境）：**
///   flutter build apk --release --dart-define=FITLOOP_API_BASE_URL=http://43.139.72.25
///
/// **运行时覆盖（用于设置页面）：**
///   ApiConfig.setBaseUrl('http://new-server:8080');
///
/// 注意：localhost 在手机上指向手机自己，不能用于真机访问电脑后端。
class ApiConfig {
  ApiConfig._();

  static String? _overrideBaseUrl;

  /// 编译时默认值（可通过 --dart-define=FITLOOP_API_BASE_URL 覆盖）
  static const String _buildTimeBaseUrl = String.fromEnvironment(
    'FITLOOP_API_BASE_URL',
    defaultValue: 'http://43.139.72.25',
  );

  /// 当前生效的 base URL
  static String get baseUrl {
    if (_overrideBaseUrl != null) return _overrideBaseUrl!;
    return _buildTimeBaseUrl;
  }

  /// 运行时覆盖 base URL（用于设置页面或调试）
  static void setBaseUrl(String url) {
    _overrideBaseUrl = url;
  }

  /// 清除运行时覆盖，恢复编译时默认值
  static void clearOverride() {
    _overrideBaseUrl = null;
  }

  /// 当前是否已运行时覆盖
  static bool get hasOverride => _overrideBaseUrl != null;
}
