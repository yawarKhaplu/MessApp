import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:messapp/services/cloud_diagnostics.dart';

void main() {
  test('retries unavailable reads and returns the recovered result', () async {
    var calls = 0;
    final result = await readCloudOperation('collection.read', () async {
      calls++;
      if (calls < 3) {
        throw FirebaseException(plugin: 'cloud_firestore', code: 'unavailable');
      }
      return 42;
    }, initialDelay: Duration.zero);
    expect(result, 42);
    expect(calls, 3);
  });

  test('persistent unavailable stops after four attempts', () async {
    var calls = 0;
    final error = FirebaseException(
      plugin: 'cloud_firestore',
      code: 'unavailable',
    );
    await expectLater(
      readCloudOperation<void>('collection.read', () async {
        calls++;
        throw error;
      }, initialDelay: Duration.zero),
      throwsA(same(error)),
    );
    expect(calls, 4);
  });

  test('does not retry denied reads or parsing failures', () async {
    for (final error in <Object>[
      FirebaseException(plugin: 'cloud_firestore', code: 'permission-denied'),
      const FormatException('Invalid data'),
    ]) {
      var calls = 0;
      await expectLater(
        readCloudOperation<void>('collection.read', () async {
          calls++;
          throw error;
        }, initialDelay: Duration.zero),
        throwsA(same(error)),
      );
      expect(calls, 1);
    }
  });

  test(
    'preserves Firebase errors and logs codes without private messages',
    () async {
      final savedPrint = debugPrint;
      final lines = <String>[];
      debugPrint = (String? message, {int? wrapWidth}) {
        if (message != null) lines.add(message);
      };
      addTearDown(() => debugPrint = savedPrint);
      final error = FirebaseException(
        plugin: 'cloud_firestore',
        code: 'permission-denied',
        message: 'private-email@example.com secret-token',
      );
      final stack = StackTrace.fromString('diagnostic-test-stack');

      try {
        await diagnoseCloudOperation<void>(
          'reports.meals',
          () => Future<void>.error(error, stack),
        );
        fail('Expected the original failure');
      } catch (caught, caughtStack) {
        expect(caught, same(error));
        expect(caughtStack.toString(), contains('diagnostic-test-stack'));
      }
      expect(lines.join('\n'), contains('cloud_firestore/permission-denied'));
      expect(lines.join('\n'), contains('reports.meals'));
      expect(lines.join('\n'), isNot(contains('private-email')));
      expect(lines.join('\n'), isNot(contains('secret-token')));
    },
  );

  test('successful empty reads remain successful', () async {
    expect(
      await diagnoseCloudOperation('reports.meals', () async => <int>[]),
      isEmpty,
    );
  });
}
