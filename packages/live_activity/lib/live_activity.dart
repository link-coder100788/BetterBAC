import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Thin wrapper over the `betterbac/live_activity` channel. iOS only;
/// everywhere else every call is a harmless no-op.
class LiveActivity {
  static const _channel = MethodChannel('betterbac/live_activity');

  static bool get isAvailableOnPlatform =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

  /// True if this iPhone runs iOS 16.2+ and Live Activities are allowed.
  static Future<bool> isSupported() async {
    if (!isAvailableOnPlatform) return false;
    try {
      return await _channel.invokeMethod<bool>('isSupported') ?? false;
    } on MissingPluginException {
      return false;
    }
  }

  /// Starts the activity, or updates it if one is already showing.
  static Future<void> show({
    required int streak,
    required int todayXp,
    required int goalXp,
    required DateTime endsAt,
    required String title,
    required String message,
  }) async {
    if (!isAvailableOnPlatform) return;
    await _channel.invokeMethod<void>('show', {
      'streak': streak,
      'todayXp': todayXp,
      'goalXp': goalXp,
      'endsAtMs': endsAt.millisecondsSinceEpoch,
      'title': title,
      'message': message,
    });
  }

  /// Ends any running activity immediately.
  static Future<void> end() async {
    if (!isAvailableOnPlatform) return;
    await _channel.invokeMethod<void>('end');
  }
}
