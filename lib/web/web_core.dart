import 'dart:async';

import 'package:flutter/foundation.dart';

import '../src/rust/api/web.dart';
import 'browser_storage.dart';

/// Starts the Rust core in the browser from the last saved snapshot, then
/// saves a new snapshot whenever the data changes.
///
/// The browser has no file system, so the web build keeps its database in
/// memory and persists it to localStorage. Native builds never call this.
Future<void> startWebCore() async {
  await webInitCore(snapshot: loadSnapshot());
  Timer.periodic(const Duration(seconds: 2), (_) => _saveIfChanged());
}

bool _saving = false;

Future<void> _saveIfChanged() async {
  if (_saving) return;
  _saving = true;
  try {
    final bytes = await webSnapshotIfChanged();
    if (bytes != null) saveSnapshot(bytes);
  } catch (e) {
    debugPrint('BetterBAC: autosave failed: $e');
  } finally {
    _saving = false;
  }
}
