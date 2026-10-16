import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

/// Where a notification tap should take the user.
const kDestinationAddEntry = 'add_entry';

/// Daily reminder service (PRD 5.5).
class NotificationService {
  NotificationService._();
  static final NotificationService instance = NotificationService._();

  static const int _dailyReminderId = 1001;
  static const String _channelId = 'messapp_daily_reminder';
  static const String _channelName = 'Daily mess reminder';
  static const String _channelDescription =
      "Reminds you to add today's mess expense";
  // Must match the channel registered in MainActivity.kt.
  static const _timezoneChannel = MethodChannel('messapp/dev/timezone');

  final _plugin = FlutterLocalNotificationsPlugin();

  final _taps = StreamController<String?>.broadcast();

  /// Fires when a notification is tapped while the app is already running.
  Stream<String?> get onTap => _taps.stream;

  String? _pendingTap;

  /// Destination of a tap that arrived before the UI was listening, for
  /// example when the notification was what launched the app from cold.
  String? takePendingDestination() {
    final destination = _pendingTap;
    _pendingTap = null;
    return destination;
  }

  void _recordTap(NotificationResponse? response) {
    final destination = response?.payload ?? kDestinationAddEntry;
    _pendingTap = destination;
    if (_taps.hasListener) _taps.add(destination);
  }

  /// Whether notifications are allowed right now. Null if unknown.
  Future<bool?> notificationsEnabled() async {
    try {
      return await _plugin
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.areNotificationsEnabled();
    } catch (_) {
      return null;
    }
  }

  /// Asks for POST_NOTIFICATIONS (Android 13+).
  ///
  /// Must be called once the activity window exists, so this is driven from
  /// the UI after the first frame rather than from `main` before `runApp`.
  Future<bool> requestPermission() async {
    try {
      final granted = await _plugin
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.requestNotificationsPermission();
      return granted ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Opens the system page where the user can re-enable notifications, for
  /// when the permission dialog has already been dismissed twice.
  Future<void> openAppSettings() async {
    try {
      await _plugin
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.requestNotificationsPermission();
    } catch (_) {
      // Ignore: the settings screen offers a manual route too.
    }
  }

  Future<void> init() async {
    await _applyDeviceTimeZone();

    // The channel must be created explicitly. Without this the plugin falls
    // back to default channels whose importance it does not control, and the
    // reminder can end up on a channel that is silently set to NONE.
    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    await android?.createNotificationChannel(
      const AndroidNotificationChannel(
        _channelId,
        _channelName,
        description: _channelDescription,
        importance: Importance.high,
      ),
    );

    const init = AndroidInitializationSettings('@mipmap/ic_launcher');
    await _plugin.initialize(
      const InitializationSettings(android: init),
      onDidReceiveNotificationResponse: _recordTap,
    );

    // Cold start: the tap that opened the app is reported here instead.
    final launchDetails = await _plugin.getNotificationAppLaunchDetails();
    if (launchDetails?.didNotificationLaunchApp ?? false) {
      _recordTap(launchDetails?.notificationResponse);
    }
  }

  /// Fires a notification immediately, so the channel and permission can be
  /// verified without waiting for a scheduled time.
  Future<void> showTestNotification() async {
    await _plugin.show(
      9999,
      'MessAppDev',
      "Notifications are working. Reminder: don't forget today's mess expense.",
      const NotificationDetails(
        android: AndroidNotificationDetails(
          _channelId,
          _channelName,
          channelDescription: _channelDescription,
          importance: Importance.high,
          priority: Priority.high,
        ),
      ),
      // Tapping the test notification should behave like the real one.
      payload: kDestinationAddEntry,
    );
  }

  /// Points `tz.local` at the device's real timezone.
  ///
  /// The `timezone` package leaves `tz.local` as UTC. Scheduling against UTC
  /// silently shifts the reminder by the UTC offset, so a 21:00 reminder would
  /// fire hours late. The zone name comes from the platform; if that is
  /// unavailable or unknown, the location is matched by UTC offset instead.
  Future<void> _applyDeviceTimeZone() async {
    tzdata.initializeTimeZones();

    String? zoneId;
    try {
      zoneId = await _timezoneChannel.invokeMethod<String>('getTimeZoneId');
    } catch (_) {
      zoneId = null;
    }

    if (zoneId != null && zoneId.isNotEmpty) {
      try {
        tz.setLocalLocation(tz.getLocation(zoneId));
        return;
      } catch (_) {
        // Name not in the database; fall through to the offset match.
      }
    }

    _matchZoneByOffset();
  }

  /// Last resort: pick a zone whose current UTC offset matches the device.
  void _matchZoneByOffset() {
    final offset = DateTime.now().timeZoneOffset;
    for (final location in tz.timeZoneDatabase.locations.values) {
      if (location.currentTimeZone.offset == offset.inMilliseconds) {
        tz.setLocalLocation(location);
        return;
      }
    }
  }

  /// Schedules (or cancels) the daily reminder according to settings.
  Future<void> applySettings({
    required bool enabled,
    required String timeHHmm,
  }) async {
    await cancelReminder();
    if (!enabled) return;

    final parts = timeHHmm.split(':');
    final hour = int.tryParse(parts[0]) ?? 21;
    final minute = int.tryParse(parts[1]) ?? 0;

    final now = tz.TZDateTime.now(tz.local);
    var scheduled = tz.TZDateTime(
        tz.local, now.year, now.month, now.day, hour, minute);
    if (!scheduled.isAfter(now)) {
      // The chosen time has already passed today, so start from tomorrow.
      scheduled = scheduled.add(const Duration(days: 1));
    }

    const androidDetails = AndroidNotificationDetails(
      _channelId,
      _channelName,
      channelDescription: _channelDescription,
      importance: Importance.high,
      priority: Priority.high,
    );
    const details = NotificationDetails(android: androidDetails);

    try {
      await _plugin.zonedSchedule(
        _dailyReminderId,
        'MessAppDev',
        "Please add today's mess expense.",
        scheduled,
        details,
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        matchDateTimeComponents: DateTimeComponents.time,
        // Tapping the reminder opens the entry screen directly, instead of
        // dropping the user on Home with nothing done.
        payload: kDestinationAddEntry,
      );
      // ignore: avoid_print
      print('MessApp: reminder set for ${scheduled.toIso8601String()} '
          '(zone ${tz.local.name})');
    } catch (e) {
      // Never let a notification failure crash the app, but do record it:
      // a silent catch here is what made the UTC bug invisible.
      // ignore: avoid_print
      print('MessApp: could not schedule reminder: $e');
    }
  }

  /// Removes every pending reminder, including repeats left by earlier runs.
  Future<void> cancelReminder() async {
    await _plugin.cancel(_dailyReminderId);
    // `cancel` only clears the one id; without this a repeat registered by a
    // previous launch can survive and fire at the old time.
    try {
      await _plugin.cancelAll();
    } catch (_) {
      // Ignore: nothing to clear.
    }
  }
}
