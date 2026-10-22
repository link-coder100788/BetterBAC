import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:web/web.dart' as web;

const _key = 'betterbac.database.v1';

/// The last saved database snapshot, if any.
Uint8List? loadSnapshot() {
  final stored = web.window.localStorage.getItem(_key);
  if (stored == null) return null;
  try {
    return base64Decode(stored);
  } on FormatException {
    return null;
  }
}

/// Stores a snapshot in localStorage (base64; plenty of room for a student's data).
void saveSnapshot(Uint8List bytes) {
  try {
    web.window.localStorage.setItem(_key, base64Encode(bytes));
  } catch (e) {
    debugPrint('BetterBAC: could not save to browser storage: $e');
  }
}
