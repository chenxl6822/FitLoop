part of '../main.dart';

String? _resolveMediaUrl(String? url) {
  if (url == null || url.isEmpty) return url;
  final parsed = Uri.tryParse(url);
  if (parsed != null && parsed.hasScheme) return url;
  if (!url.startsWith('/')) return url;
  final base = ApiConfig.baseUrl.endsWith('/')
      ? ApiConfig.baseUrl.substring(0, ApiConfig.baseUrl.length - 1)
      : ApiConfig.baseUrl;
  return '$base$url';
}

const _sportTypes = {
  'running': '跑步',
  'cycling': '骑行',
  'walking': '健走',
  'rope_skipping': '跳绳',
  'custom': '自定义',
};

/// 将各类异常转换为用户可读的错误消息
String friendlyErrorMsg(dynamic error) {
  final msg = error.toString();
  // 网络连接类错误
  if (msg.contains('SocketException') ||
      msg.contains('Connection refused') ||
      msg.contains('Connection failed') ||
      msg.contains('Connection reset') ||
      msg.contains('Network is unreachable') ||
      msg.contains('No route to host') ||
      msg.contains('Software caused connection abort') ||
      msg.contains('Operation not permitted')) {
    return '服务器连接失败，请检查网络或稍后重试';
  }
  // 超时类
  if (msg.contains('Timeout') ||
      msg.contains('timed out') ||
      msg.contains('Time out')) {
    return '请求超时，请检查网络后重试';
  }
  // DNS 解析失败
  if (msg.contains('No address associated with hostname') ||
      msg.contains('nodename nor servname') ||
      msg.contains('Service not available')) {
    return '无法解析服务器地址，请检查网络配置';
  }
  // TLS/证书错误
  if (msg.contains('TLS') ||
      msg.contains('SSL') ||
      msg.contains('Certificate')) {
    return '安全连接失败，请稍后重试';
  }
  // 认证相关（非网络）
  if (msg.contains('401') || msg.contains('403')) {
    return '登录状态已过期，请重新登录';
  }
  if (msg.contains('500')) {
    return '服务器开小差了，请稍后重试';
  }
  if (msg.contains('Missing type parameter') ||
      msg.contains('flutterlocalnotifications')) {
    return '提醒服务初始化失败，请重启应用后重试';
  }
  // 去除 ApiException: 前缀，展示后端返回的原始消息
  if (msg.startsWith('ApiException: ')) {
    return msg.substring(14);
  }
  return msg;
}

class _PageScaffold extends StatelessWidget {
  const _PageScaffold({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Text(title,
            style: Theme.of(context)
                .textTheme
                .headlineMedium
                ?.copyWith(fontWeight: FontWeight.w700)),
        const SizedBox(height: 20),
        ...children,
      ],
    );
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard(
      {required this.label, required this.value, required this.icon});

  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        leading: Icon(icon),
        title: Text(label),
        subtitle: Text(value),
      ),
    );
  }
}
