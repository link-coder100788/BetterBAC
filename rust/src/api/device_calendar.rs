//! Importing events from the device's calendars: Apple Calendar on iPhone
//! and Mac (EventKit), Google Calendar and others on Android (the system
//! calendar provider). This is the "refresh" hook for
//! `calendar::DeviceCalendarProvider`.
//!
//! Flow (driven by `lib/device_calendar.dart`):
//! 1. Dart asks Rust for the [`device_import_window`].
//! 2. The native plugin reads every event in that window from the selected
//!    calendars.
//! 3. Dart passes them to [`import_device_events`], which makes the cache
//!    match. The calendar view, crunch weeks and so on pick them up through
//!    the provider.

use anyhow::Result;
use chrono::{DateTime, Duration, Utc};
use flutter_rust_bridge::frb;

use crate::calendar::local_midnight;
use crate::state::{self, with_core};

/// One event occurrence as read from the device.
#[derive(Debug, Clone)]
pub struct DeviceEventInput {
    /// Stable id for this occurrence (recurring events have one per occurrence).
    pub external_id: String,
    pub calendar_id: String,
    pub calendar_name: String,
    pub title: String,
    pub notes: String,
    pub starts_at: DateTime<Utc>,
    pub ends_at: Option<DateTime<Utc>>,
    pub all_day: bool,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct DeviceImportSummary {
    pub added: u32,
    pub updated: u32,
    pub removed: u32,
}

impl DeviceImportSummary {
    #[frb(sync)]
    pub fn changed(&self) -> bool {
        self.added + self.updated + self.removed > 0
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct DeviceCalendarPrefs {
    pub enabled: bool,
    /// Native calendar ids to import from.
    pub calendar_ids: Vec<String>,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct ImportWindow {
    pub start: DateTime<Utc>,
    pub end: DateTime<Utc>,
}

const PREF_ENABLED: &str = "device_calendar_enabled";
const PREF_CALENDARS: &str = "device_calendar_ids";
/// Ids are opaque strings from the OS; newline never appears in them.
const ID_SEPARATOR: char = '\n';

/// Import from a week ago (recent past stays visible) to ~3 months ahead.
const DAYS_BACK: i64 = 7;
const DAYS_AHEAD: i64 = 90;

pub fn get_device_calendar_prefs() -> Result<DeviceCalendarPrefs> {
    with_core(|store, _| {
        Ok(DeviceCalendarPrefs {
            enabled: store.bool_setting(PREF_ENABLED, false)?,
            calendar_ids: store
                .string_setting(PREF_CALENDARS)?
                .map(|s| {
                    s.split(ID_SEPARATOR)
                        .filter(|id| !id.is_empty())
                        .map(String::from)
                        .collect()
                })
                .unwrap_or_default(),
        })
    })
}

/// Saves the prefs. Turning import off removes the imported events.
pub fn set_device_calendar_prefs(prefs: DeviceCalendarPrefs) -> Result<()> {
    let now = state::now();
    with_core(|store, _| {
        store.set_bool_setting(PREF_ENABLED, prefs.enabled, now)?;
        let joined = prefs
            .calendar_ids
            .iter()
            .map(|id| id.replace(ID_SEPARATOR, " "))
            .collect::<Vec<_>>()
            .join(&ID_SEPARATOR.to_string());
        store.set_string_setting(PREF_CALENDARS, &joined, now)?;
        if !prefs.enabled {
            store.clear_device_events(now)?;
        }
        Ok(())
    })
}

/// The time range to read from the device and pass to [`import_device_events`].
#[frb(sync)]
pub fn device_import_window() -> ImportWindow {
    let today = state::today();
    ImportWindow {
        start: local_midnight(today - Duration::days(DAYS_BACK)),
        end: local_midnight(today + Duration::days(DAYS_AHEAD)),
    }
}

/// Replaces the cached events in `window` with `events`: the complete set the
/// device returned for that window from the selected calendars.
pub fn import_device_events(
    window: ImportWindow,
    events: Vec<DeviceEventInput>,
) -> Result<DeviceImportSummary> {
    let now = state::now();
    with_core(|store, _| store.import_device_events(window.start, window.end, &events, now))
}

/// Removes all imported events (e.g. calendar access was revoked).
pub fn clear_device_events() -> Result<u32> {
    let now = state::now();
    with_core(|store, _| store.clear_device_events(now))
}
