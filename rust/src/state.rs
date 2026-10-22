//! Process-wide core state, created once by `api::app::init_core`.

use anyhow::{anyhow, Result};
use chrono::{DateTime, Local, NaiveDate, Utc};
use std::sync::{Mutex, OnceLock};

use crate::calendar::CalendarService;
use crate::store::Store;

pub struct Core {
    store: Mutex<Store>,
    pub calendar: CalendarService,
}

static CORE: OnceLock<Core> = OnceLock::new();

/// Idempotent: Flutter hot-restart re-runs `main` while Rust stays loaded.
pub fn init(db_path: &str) -> Result<()> {
    if CORE.get().is_some() {
        return Ok(());
    }
    let store = Store::open(db_path)?;
    let _ = CORE.set(Core {
        store: Mutex::new(store),
        calendar: CalendarService::new(),
    });
    Ok(())
}

/// Runs `f` with exclusive access to the store, inside a transaction that is
/// committed only if `f` succeeds.
pub fn with_core<T>(f: impl FnOnce(&Store, &CalendarService) -> Result<T>) -> Result<T> {
    let core = CORE
        .get()
        .ok_or_else(|| anyhow!("BetterBAC core not initialised; call init_core first"))?;
    let store = core
        .store
        .lock()
        .map_err(|_| anyhow!("store lock poisoned"))?;
    store.in_transaction(|s| f(s, &core.calendar))
}

pub fn now() -> DateTime<Utc> {
    Utc::now()
}

/// The user's current local calendar day.
pub fn today() -> NaiveDate {
    Local::now().date_naive()
}
