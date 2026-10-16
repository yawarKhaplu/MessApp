import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

/// Retry reads only. Authentication and writes must never use this helper.
Future<T> readCloudOperation<T>(
  String operation,
  Future<T> Function() action, {
  Duration initialDelay = const Duration(seconds: 1),
}) async {
  for (var attempt = 0; ; attempt++) {
    try {
      return await diagnoseCloudOperation(operation, action);
    } on FirebaseException catch (error) {
      final transient =
          error.plugin == 'cloud_firestore' &&
          (error.code == 'unavailable' || error.code == 'deadline-exceeded');
      if (!transient || attempt >= 3) rethrow;
      await Future<void>.delayed(initialDelay * (1 << attempt));
    }
  }
}

/// Use fixed operation labels, never document IDs, emails, tokens or payloads.
/// Preserve the original exception and stack so callers can still retry by code.
Future<T> diagnoseCloudOperation<T>(
  String operation,
  Future<T> Function() action,
) async {
  try {
    return await action();
  } catch (error, stack) {
    final category = error is FirebaseException
        ? '${error.plugin}/${error.code}'
        : error.runtimeType.toString();
    // Exception messages can contain document contents or account identifiers.
    // Log only the type/code and stack, including in release builds.
    debugPrint('[MessAppCloud] operation=$operation error=$category');
    debugPrintStack(label: '[MessAppCloud] stack', stackTrace: stack);
    rethrow;
  }
}
