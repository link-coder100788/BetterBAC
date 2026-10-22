import 'dart:typed_data';

/// Native builds keep the database in a file, so there's nothing to load.
Uint8List? loadSnapshot() => null;

void saveSnapshot(Uint8List bytes) {}
