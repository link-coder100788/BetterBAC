import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Apple Intelligence availability on this device.
enum AppleCoachStatus {
  available,

  /// Device or OS can't run Apple Intelligence (or not an Apple platform).
  unsupported,

  /// Supported, but the user hasn't turned Apple Intelligence on.
  notEnabled,

  /// Supported and on, but the model is still downloading.
  notReady,
}

/// Thin wrapper over the `betterbac/apple_coach` method channel.
class AppleCoach {
  static const _channel = MethodChannel('betterbac/apple_coach');

  static bool get _isApple =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.iOS ||
          defaultTargetPlatform == TargetPlatform.macOS);

  static Future<AppleCoachStatus> status() async {
    if (!_isApple) return AppleCoachStatus.unsupported;
    try {
      final status = await _channel.invokeMethod<String>('status');
      return switch (status) {
        'available' => AppleCoachStatus.available,
        'unavailable:appleIntelligenceNotEnabled' => AppleCoachStatus.notEnabled,
        'unavailable:modelNotReady' => AppleCoachStatus.notReady,
        _ => AppleCoachStatus.unsupported,
      };
    } on MissingPluginException {
      return AppleCoachStatus.unsupported;
    }
  }

  /// Runs the on-device model. Returns `{headline, tips: [{kind, title, body}]}`.
  /// Throws [PlatformException] if generation fails.
  static Future<Map<String, Object?>> generate({
    required String instructions,
    required String prompt,
  }) async {
    final result = await _channel.invokeMapMethod<String, Object?>(
      'generate',
      {'instructions': instructions, 'prompt': prompt},
    );
    return result ?? const {};
  }
}
