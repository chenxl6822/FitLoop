import 'package:fitloop/api_config.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  tearDown(ApiConfig.clearOverride);

  test('release default API base URL uses HTTPS', () {
    expect(
      Uri.parse(ApiConfig.baseUrl).scheme,
      'https',
      reason:
          'release defaults must not send bearer tokens or private health '
          'and location data over cleartext HTTP',
    );
  });
}
