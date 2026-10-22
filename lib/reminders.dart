import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:live_activity/live_activity.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import 'app_state.dart';
import 'src/rust/api/reminders.dart';

/// Applies the reminder plan from Rust (`api/reminders.rs`): scheduled
/// notifications on iOS, Android and macOS, plus the streak Live Activity on
/// iOS. The plan is re-applied whenever data changes or the app resumes, so
/// stale reminders disappear on their own.
class Reminders {
  static final _plugin = FlutterLocalNotificationsPlugin();
  static bool _ready = false;
  static Timer? _debounce;
  static ReminderPlan? _applied;
  static AppLifecycleListener? _lifecycle;

  static bool get notificationsSupported =>
      !kIsWeb &&
      const [TargetPlatform.iOS, TargetPlatform.android, TargetPlatform.macOS]
          .contains(defaultTargetPlatform);

  static bool get liveActivitySupported => LiveActivity.isAvailableOnPlatform;

  /// Call once the user is through onboarding (asks for permission).
  static Future<void> start() async {
    if (!notificationsSupported || _ready) return;
    tzdata.initializeTimeZones();
    const darwin = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );
    await _plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        iOS: darwin,
        macOS: darwin,
      ),
    );
    _ready = true;
    dataVersion.addListener(_syncSoon);
    _lifecycle = AppLifecycleListener(onResume: sync);
    if ((await getReminderPrefs()).notifications) await requestPermission();
    await sync();
  }

  /// Asks the OS for permission to show notifications. Returns whether granted.
  static Future<bool> requestPermission() async {
    if (!notificationsSupported) return false;
    final granted = switch (defaultTargetPlatform) {
      TargetPlatform.iOS => await _plugin
          .resolvePlatformSpecificImplementation<
              IOSFlutterLocalNotificationsPlugin>()
          ?.requestPermissions(alert: true, badge: true, sound: true),
      TargetPlatform.macOS => await _plugin
          .resolvePlatformSpecificImplementation<
              MacOSFlutterLocalNotificationsPlugin>()
          ?.requestPermissions(alert: true, badge: true, sound: true),
      TargetPlatform.android => await _plugin
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.requestNotificationsPermission(),
      _ => false,
    };
    return granted ?? false;
  }

  static void _syncSoon() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(seconds: 1), sync);
  }

  /// Fetches the current plan and applies it if it changed.
  static Future<void> sync() async {
    if (!_ready) return;
    try {
      final plan = await reminderPlan();
      if (plan == _applied) return;
      await _applyNotifications(plan.notifications);
      await _applyLiveActivity(plan.liveActivity);
      _applied = plan;
    } catch (e) {
      debugPrint('BetterBAC: could not apply reminders: $e');
    }
  }

  static Future<void> _applyNotifications(List<PlannedNotification> list) async {
    await _plugin.cancelAllPendingNotifications();
    const details = NotificationDetails(
      android: AndroidNotificationDetails(
        'reminders',
        'Reminders',
        channelDescription: 'Streak and deadline reminders',
        importance: Importance.high,
        priority: Priority.high,
      ),
      iOS: DarwinNotificationDetails(),
      macOS: DarwinNotificationDetails(),
    );
    for (final n in list) {
      await _plugin.zonedSchedule(
        id: n.id,
        title: n.title,
        body: n.body,
        scheduledDate: tz.TZDateTime.from(n.fireAt, tz.UTC),
        notificationDetails: details,
        // Inexact is fine for reminders and needs no extra Android permission.
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      );
    }
  }

  static Future<void> _applyLiveActivity(StreakActivity? activity) async {
    if (!liveActivitySupported) return;
    if (activity == null) {
      await LiveActivity.end();
    } else {
      await LiveActivity.show(
        streak: activity.streak,
        todayXp: activity.todayXp,
        goalXp: activity.goalXp,
        endsAt: activity.endsAt,
        title: activity.title,
        message: activity.message,
      );
    }
  }

  /// For tests: forget the last applied plan so the next sync re-applies.
  @visibleForTesting
  static void reset() {
    _applied = null;
    _lifecycle?.dispose();
  }
}
