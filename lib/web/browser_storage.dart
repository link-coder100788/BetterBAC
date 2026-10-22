// Saves database snapshots in the browser. Native builds get the no-op stub.
export 'browser_storage_stub.dart'
    if (dart.library.js_interop) 'browser_storage_web.dart';
