import 'dart:async';

import 'package:fitloop/async_serial_executor.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('does not start the next action until the current one completes',
      () async {
    final executor = AsyncSerialExecutor();
    final firstGate = Completer<void>();
    final events = <String>[];

    final first = executor.run(() async {
      events.add('first-start');
      await firstGate.future;
      events.add('first-end');
    });
    final second = executor.run(() async {
      events.add('second');
    });
    await Future<void>.delayed(Duration.zero);

    expect(events, ['first-start']);
    firstGate.complete();
    await Future.wait([first, second]);
    expect(events, ['first-start', 'first-end', 'second']);
  });

  test('continues processing after a failed action', () async {
    final executor = AsyncSerialExecutor();

    final failed = executor.run<void>(() async => throw StateError('failed'));
    final succeeded = executor.run(() async => 'ok');

    await expectLater(failed, throwsStateError);
    await expectLater(succeeded, completion('ok'));
  });
}
