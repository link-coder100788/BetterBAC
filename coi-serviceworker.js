/*
 * Cross-origin isolation for static hosts that can't set response headers
 * (e.g. GitHub Pages).
 *
 * The Rust core runs as multi-threaded WebAssembly, which needs
 * SharedArrayBuffer, which browsers only allow on "cross-origin isolated"
 * pages (COOP + COEP headers). This file is both:
 *   - the page script: registers itself as a service worker and reloads once
 *     so the page is served through it, and
 *   - the service worker: adds the two headers to every response.
 *
 * Same approach as coi-serviceworker by Guido Zuidhof (MIT).
 */

if (typeof window === 'undefined') {
  // ---- Service worker ----
  self.addEventListener('install', () => self.skipWaiting());
  self.addEventListener('activate', (event) => event.waitUntil(self.clients.claim()));

  self.addEventListener('fetch', (event) => {
    const request = event.request;
    if (request.cache === 'only-if-cached' && request.mode !== 'same-origin') return;

    event.respondWith(
      fetch(request).then((response) => {
        // Opaque responses can't be modified; pass them through untouched.
        if (response.status === 0) return response;

        const headers = new Headers(response.headers);
        headers.set('Cross-Origin-Embedder-Policy', 'require-corp');
        headers.set('Cross-Origin-Opener-Policy', 'same-origin');
        headers.set('Cross-Origin-Resource-Policy', 'cross-origin');
        return new Response(response.body, {
          status: response.status,
          statusText: response.statusText,
          headers,
        });
      }),
    );
  });
} else {
  // ---- Page ----
  (() => {
    const KEY = 'betterbac-coi-reloaded';

    if (window.crossOriginIsolated) {
      sessionStorage.removeItem(KEY);
      return;
    }
    if (!window.isSecureContext || !navigator.serviceWorker) {
      console.warn('BetterBAC: cannot enable cross-origin isolation in this browser.');
      return;
    }

    // Reload at most once per attempt, to avoid loops if isolation fails.
    const reloadOnce = () => {
      if (sessionStorage.getItem(KEY)) return;
      sessionStorage.setItem(KEY, '1');
      window.location.reload();
    };

    navigator.serviceWorker.register(document.currentScript.src).then(
      (registration) => {
        if (registration.active || navigator.serviceWorker.controller) {
          reloadOnce();
        } else {
          navigator.serviceWorker.addEventListener('controllerchange', reloadOnce);
        }
      },
      (err) => console.error('BetterBAC: service worker registration failed', err),
    );
  })();
}
