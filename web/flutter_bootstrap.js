{{flutter_js}}
{{flutter_build_config}}

// No serviceWorkerSettings: Flutter's (deprecated) service worker would
// replace coi-serviceworker.js, which keeps the page cross-origin isolated
// for the multi-threaded Rust core.
_flutter.loader.load();
