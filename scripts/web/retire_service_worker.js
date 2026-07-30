// Self-destructing service worker.
//
// The Treasury web companion no longer ships a service worker. It is an
// authenticated dashboard, not an offline-first app, so the worker bought
// nothing — and it cost a stale load on every release: Flutter's worker serves
// the PREVIOUS bundle while it installs the new one, which only activates on
// the *next* navigation. A deploy therefore looked like it had not landed
// (`version.json` came over the wire fresh while `main.dart.js` was still
// served from CacheStorage), and even "Clear site data" did not reliably fix
// it. `flutter build web --pwa-strategy=none` stops generating one.
//
// Deleting this file would NOT have retired the workers already registered in
// people's browsers: a browser keeps serving from an existing registration
// indefinitely when the script URL starts 404ing. So we keep serving a worker
// at the same path whose entire job is to remove itself. `firebase.json` sends
// this path `no-cache`, so every browser holding a stale registration
// revalidates it, receives this script, and heals permanently.
//
// Safe to delete once no client can plausibly still hold a registration.

self.addEventListener('install', (event) => {
  // Replace the outgoing worker now rather than waiting for every tab to close.
  event.waitUntil(self.skipWaiting());
});

self.addEventListener('activate', (event) => {
  event.waitUntil((async () => {
    // Drop the cached app shell first, so the reload below cannot be answered
    // from the very caches we are retiring.
    const keys = await caches.keys();
    await Promise.all(keys.map((key) => caches.delete(key)));

    await self.registration.unregister();

    // Reload controlled tabs so they pick up the real bundle immediately
    // instead of showing stale UI until the user happens to navigate.
    const windows = await self.clients.matchAll({ type: 'window' });
    for (const client of windows) {
      client.navigate(client.url);
    }
  })());
});

// Deliberately no 'fetch' handler: with none registered the browser goes
// straight to the network, so nothing is served from cache while we wind down.
