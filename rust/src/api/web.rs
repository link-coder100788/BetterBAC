//! Web build support.
//!
//! These functions exist on every platform so the Dart bindings are the same
//! everywhere, but they only work in the browser. Native builds use
//! `app::init_core` with a database file instead.
//!
//! In the browser the database lives in memory. The Dart side calls
//! [`web_init_core`] with the last saved snapshot on startup, then polls
//! [`web_snapshot_if_changed`] and writes any new snapshot to browser storage.

use anyhow::Result;

/// Starts the core from a saved snapshot (or empty if `None`). Idempotent.
pub fn web_init_core(snapshot: Option<Vec<u8>>) -> Result<()> {
    #[cfg(target_arch = "wasm32")]
    {
        if !crate::state::is_initialised() {
            let store = crate::store::Store::open_snapshot(snapshot.as_deref())?;
            crate::state::install(store);
        }
        Ok(())
    }
    #[cfg(not(target_arch = "wasm32"))]
    {
        let _ = snapshot;
        anyhow::bail!("web_init_core is only available in the web build")
    }
}

/// The database as bytes, or `None` if nothing changed since the last call.
pub fn web_snapshot_if_changed() -> Result<Option<Vec<u8>>> {
    #[cfg(target_arch = "wasm32")]
    {
        use std::sync::atomic::{AtomicU64, Ordering};
        static LAST_SAVED: AtomicU64 = AtomicU64::new(0);

        crate::state::with_core(|store, _| {
            let changes = store.total_changes();
            if changes == LAST_SAVED.load(Ordering::Relaxed) {
                return Ok(None);
            }
            let bytes = store.snapshot()?;
            LAST_SAVED.store(changes, Ordering::Relaxed);
            Ok(Some(bytes))
        })
    }
    #[cfg(not(target_arch = "wasm32"))]
    {
        Ok(None)
    }
}
