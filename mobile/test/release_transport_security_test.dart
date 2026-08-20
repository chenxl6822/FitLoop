import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _read(String relativePath) => File(relativePath).readAsStringSync();

void main() {
  test('Android release defaults fail closed for cleartext traffic', () {
    final manifest = _read('android/app/src/main/AndroidManifest.xml');
    final gradle = _read('android/app/build.gradle.kts');
    final productionConfig = _read(
      'android/app/src/main/res/xml/network_security_config.xml',
    );

    expect(
      manifest,
      contains(r'android:usesCleartextTraffic="${usesCleartextTraffic}"'),
    );
    expect(
      manifest,
      contains(r'android:networkSecurityConfig="${networkSecurityConfig}"'),
    );
    expect(gradle, contains('FITLOOP_HTTP_TRANSITION'));
    expect(
      gradle,
      contains('manifestPlaceholders["usesCleartextTraffic"] = "false"'),
    );
    expect(
      productionConfig,
      contains('<base-config cleartextTrafficPermitted="false" />'),
    );
    expect(
      productionConfig,
      isNot(contains('cleartextTrafficPermitted="true"')),
    );
  });

  test('development and approved transition cleartext policies are scoped', () {
    final debugManifest = _read('android/app/src/debug/AndroidManifest.xml');
    final profileManifest = _read(
      'android/app/src/profile/AndroidManifest.xml',
    );
    final debugConfig = _read(
      'android/app/src/debug/res/xml/network_security_config_debug.xml',
    );
    final profileConfig = _read(
      'android/app/src/profile/res/xml/network_security_config_debug.xml',
    );
    final transitionConfig = _read(
      'android/app/src/main/res/xml/network_security_config_http_transition.xml',
    );

    for (final manifest in [debugManifest, profileManifest]) {
      expect(manifest, contains('android:usesCleartextTraffic="true"'));
      expect(
        manifest,
        contains(
          'android:networkSecurityConfig="@xml/network_security_config_debug"',
        ),
      );
    }
    for (final config in [debugConfig, profileConfig]) {
      expect(
        config,
        contains('<base-config cleartextTrafficPermitted="true" />'),
      );
    }
    expect(
      transitionConfig,
      contains('<base-config cleartextTrafficPermitted="false" />'),
    );
    expect(
      transitionConfig,
      contains('<domain includeSubdomains="false">43.139.72.25</domain>'),
    );
    expect(transitionConfig, isNot(contains('>localhost</domain>')));
    expect(transitionConfig, isNot(contains('>10.0.2.2</domain>')));
  });
}
