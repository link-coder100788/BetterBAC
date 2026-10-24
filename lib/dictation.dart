import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import 'src/rust/api/dictation.dart';

/// The bundled Whisper model isn't in this build
/// (run `scripts/fetch_whisper_model.sh` before building).
class DictationModelMissing implements Exception {}

/// On-device dictation. Whisper runs in Rust (`api/dictation.rs`); this only
/// gets the bundled model onto disk once and loads it.
class Dictation {
  static const _asset = 'assets/models/whisper-base-q8.gguf';
  static Future<void>? _ready;

  /// iPhone, Android and Mac (not web or Windows).
  static bool get supported =>
      !kIsWeb &&
      const [TargetPlatform.iOS, TargetPlatform.android, TargetPlatform.macOS]
          .contains(defaultTargetPlatform) &&
      dictationSupported();

  /// Installs (first run only) and loads the model. Cheap after the first call.
  static Future<void> prepare() {
    return _ready ??= _prepare().catchError((Object e) {
      _ready = null; // allow a retry
      throw e;
    });
  }

  static Future<void> _prepare() async {
    final dir = (await getApplicationSupportDirectory()).path;
    if (!await dictationModelInstalled(dir: dir)) {
      final ByteData data;
      try {
        data = await rootBundle.load(_asset);
      } catch (_) {
        debugPrint('BetterBAC: $_asset missing; run scripts/fetch_whisper_model.sh');
        throw DictationModelMissing();
      }
      await installDictationModel(
        dir: dir,
        bytes: data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
      );
    }
    await loadDictationModel(dir: dir);
  }
}
