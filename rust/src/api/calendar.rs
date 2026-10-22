use anyhow::{anyhow, Result};
use chrono::{DateTime, Utc};

use super::types::{CalendarEvent, EventDraft, MonthOverview, WorkloadOutlook};
use crate::progress;
use crate::state::{self, with_core};
use crate::store::XpEntry;

/// Events from every provider overlapping `[start, end)`.
pub fn events_between(start: DateTime<Utc>, end: DateTime<Utc>) -> Result<Vec<CalendarEvent>> {
    with_core(|store, calendar| Ok(calendar.events_between(store, start, end)))
}

pub fn upcoming_events(limit: u32) -> Result<Vec<CalendarEvent>> {
    let now = state::now();
    with_core(|store, calendar| Ok(calendar.upcoming(store, now, limit as usize)))
}

/// Workload for the next `weeks` weeks (starting with this one) and a
/// warning about the first busy or crunch week.
pub fn workload_outlook(weeks: u32) -> Result<WorkloadOutlook> {
    let today = state::today();
    with_core(|store, calendar| Ok(calendar.workload(store, today, weeks)))
}

/// `month` is 1-based.
pub fn month_overview(year: i32, month: u32) -> Result<MonthOverview> {
    with_core(|store, calendar| calendar.month_overview(store, year, month))
}

/// Asks remote providers to sync. Returns a message per provider that failed.
pub fn refresh_calendars() -> Result<Vec<String>> {
    with_core(|store, calendar| {
        Ok(calendar
            .refresh_all(store)
            .into_iter()
            .map(|(source, err)| format!("{source}: {err:#}"))
            .collect())
    })
}

pub fn create_event(draft: EventDraft) -> Result<CalendarEvent> {
    let now = state::now();
    with_core(|store, _| {
        let id = store.create_event(&draft, now)?;
        Ok(store.get_event(&id)?.expect("just inserted"))
    })
}

pub fn update_event(id: String, draft: EventDraft) -> Result<CalendarEvent> {
    let now = state::now();
    with_core(|store, _| {
        store.update_event(&id, &draft, now)?;
        Ok(store.get_event(&id)?.expect("just updated"))
    })
}

pub fn delete_event(id: String) -> Result<()> {
    let now = state::now();
    with_core(|store, _| {
        store.delete_event(&id, now)?;
        store.revoke_xp_prefix(&progress::event_prefix(&id), now)
    })
}

/// Ticks an event off (or un-ticks it). Returns the XP gained.
pub fn set_event_completed(id: String, completed: bool) -> Result<u32> {
    let (now, today) = (state::now(), state::today());
    with_core(|store, _| {
        store
            .get_event(&id)?
            .ok_or_else(|| anyhow!("Event not found"))?;
        store.set_event_completed(&id, completed, now)?;
        if completed {
            store.award_xp(
                XpEntry {
                    key: &progress::event_key(&id),
                    amount: progress::XP_EVENT_COMPLETED,
                    day: today,
                },
                now,
            )
        } else {
            store.revoke_xp_prefix(&progress::event_prefix(&id), now)?;
            Ok(0)
        }
    })
}
