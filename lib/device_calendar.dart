import 'package:device_calendar_import/device_calendar_import.dart';
import 'package:flutter/widgets.dart';

import 'app_state.dart';
import 'src/rust/api/device_calendar.dart';

/// Imports events from Apple Calendar (iPhone, Mac) or Google Calendar
/// (Android) into BetterBAC. The native plugin reads; Rust
/// (`api/device_calendar.rs`) stores them and serves them through the
/// calendar's `DeviceCalendarProvider`.
class DeviceCalendar {
  static bool _started = false;
  static bool _syncing = false;
  static AppLifecycleListener? _lifecycle;

  static bool get supported => DeviceCalendarImport.isAvailableOnPlatform;

  /// "Apple Calendar" or "Google Calendar".
  static String get providerName => DeviceCalendarImport.providerName;

  /// Imports now and whenever the app comes back to the foreground.
  static Future<void> start() async {
    if (!supported || _started) return;
    _started = true;
    _lifecycle = AppLifecycleListener(onResume: sync);
    await sync();
  }

  /// Re-imports if import is on. Returns what changed, or null if nothing ran.
  static Future<DeviceImportSummary?> sync() async {
    if (!supported || _syncing) return null;
    _syncing = true;
    try {
      final prefs = await getDeviceCalendarPrefs();
      if (!prefs.enabled) return null;
      if (!await DeviceCalendarImport.hasAccess()) {
        // Access was revoked in system settings: drop what we imported.
        if (await clearDeviceEvents() > 0) notifyDataChanged();
        return null;
      }
      final window = deviceImportWindow();
      final events = await DeviceCalendarImport.events(
        start: window.start,
        end: window.end,
        calendarIds: prefs.calendarIds,
      );
      final summary = await importDeviceEvents(
        window: window,
        events: [
          for (final e in events)
            DeviceEventInput(
              externalId: e.id,
              calendarId: e.calendarId,
              calendarName: e.calendarTitle,
              title: e.title,
              notes: e.notes,
              startsAt: e.start,
              endsAt: e.end,
              allDay: e.allDay,
            ),
        ],
      );
      if (summary.changed()) notifyDataChanged();
      return summary;
    } catch (e) {
      debugPrint('BetterBAC: calendar import failed: $e');
      return null;
    } finally {
      _syncing = false;
    }
  }

  /// Asks for calendar access. Returns the calendars to choose from, or null
  /// if access was denied.
  static Future<List<DeviceCalendarInfo>?> connect() async {
    if (!await DeviceCalendarImport.requestAccess()) return null;
    return DeviceCalendarImport.calendars();
  }

  static Future<List<DeviceCalendarInfo>> calendars() =>
      DeviceCalendarImport.calendars();

  /// Turns import on for [calendarIds] and imports straight away.
  static Future<DeviceImportSummary?> enable(Set<String> calendarIds) async {
    await setDeviceCalendarPrefs(
      prefs: DeviceCalendarPrefs(enabled: true, calendarIds: calendarIds.toList()),
    );
    return sync();
  }

  /// Turns import off and removes imported events.
  static Future<void> disable() async {
    await setDeviceCalendarPrefs(
      prefs: const DeviceCalendarPrefs(enabled: false, calendarIds: []),
    );
    notifyDataChanged();
  }

  @visibleForTesting
  static void reset() {
    _lifecycle?.dispose();
    _started = false;
  }
}
