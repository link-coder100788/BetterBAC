import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// A calendar on the device.
class DeviceCalendarInfo {
  const DeviceCalendarInfo({
    required this.id,
    required this.title,
    required this.account,
    required this.color,
    required this.suggested,
  });

  final String id;
  final String title;

  /// Where it lives, e.g. "iCloud" or "you@gmail.com".
  final String account;
  final Color color;

  /// False for calendars people rarely want imported (birthdays, holidays).
  final bool suggested;
}

/// One event occurrence (recurring events are expanded).
class DeviceEventData {
  const DeviceEventData({
    required this.id,
    required this.calendarId,
    required this.calendarTitle,
    required this.title,
    required this.notes,
    required this.start,
    required this.end,
    required this.allDay,
  });

  final String id;
  final String calendarId;
  final String calendarTitle;
  final String title;
  final String notes;
  final DateTime start;
  final DateTime? end;
  final bool allDay;
}

/// Read-only access to the device's calendars: Apple Calendar on iOS and
/// macOS (EventKit), and Google Calendar and others on Android.
class DeviceCalendarImport {
  static const _channel = MethodChannel('betterbac/device_calendar');

  static bool get isAvailableOnPlatform =>
      !kIsWeb &&
      const [TargetPlatform.iOS, TargetPlatform.macOS, TargetPlatform.android]
          .contains(defaultTargetPlatform);

  /// "Apple Calendar" or "Google Calendar", for UI text.
  static String get providerName =>
      defaultTargetPlatform == TargetPlatform.android
          ? 'Google Calendar'
          : 'Apple Calendar';

  static Future<bool> hasAccess() async {
    if (!isAvailableOnPlatform) return false;
    return await _channel.invokeMethod<bool>('hasAccess') ?? false;
  }

  /// Shows the system permission prompt if needed. Returns whether granted.
  static Future<bool> requestAccess() async {
    if (!isAvailableOnPlatform) return false;
    return await _channel.invokeMethod<bool>('requestAccess') ?? false;
  }

  static Future<List<DeviceCalendarInfo>> calendars() async {
    if (!isAvailableOnPlatform) return const [];
    final raw = await _channel.invokeListMethod<Map>('listCalendars') ?? const [];
    return [
      for (final c in raw)
        DeviceCalendarInfo(
          id: c['id'] as String,
          title: c['title'] as String? ?? '',
          account: c['account'] as String? ?? '',
          color: Color(c['color'] as int? ?? 0xFF1CB0F6),
          suggested: c['suggested'] as bool? ?? true,
        ),
    ];
  }

  /// Every event occurrence in [start, end) from the given calendars.
  static Future<List<DeviceEventData>> events({
    required DateTime start,
    required DateTime end,
    required List<String> calendarIds,
  }) async {
    if (!isAvailableOnPlatform || calendarIds.isEmpty) return const [];
    final raw = await _channel.invokeListMethod<Map>('events', {
          'startMs': start.millisecondsSinceEpoch,
          'endMs': end.millisecondsSinceEpoch,
          'calendarIds': calendarIds,
        }) ??
        const [];
    DateTime ms(Object? v) =>
        DateTime.fromMillisecondsSinceEpoch(v as int, isUtc: true);
    return [
      for (final e in raw)
        DeviceEventData(
          id: e['id'] as String,
          calendarId: e['calendarId'] as String,
          calendarTitle: e['calendarTitle'] as String? ?? '',
          title: e['title'] as String? ?? '',
          notes: e['notes'] as String? ?? '',
          start: ms(e['startMs']),
          end: e['endMs'] == null ? null : ms(e['endMs']),
          allDay: e['allDay'] as bool? ?? false,
        ),
    ];
  }
}
