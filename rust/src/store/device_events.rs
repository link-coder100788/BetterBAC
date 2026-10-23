//! Events imported from the device's calendars (Apple Calendar on iPhone and
//! Mac, Google Calendar and others on Android). Read-only in BetterBAC.

use std::collections::HashSet;

use anyhow::Result;
use chrono::{DateTime, Duration, Utc};
use rusqlite::{params, OptionalExtension, Row};

use super::{category_from_str, category_to_str, from_millis, new_id, opt_from_millis, to_millis, Store};
use crate::api::device_calendar::{DeviceEventInput, DeviceImportSummary};
use crate::api::types::CalendarEvent;
use crate::calendar::{guess_category, DEVICE_SOURCE};

const SELECT: &str = "
    SELECT id, title, notes, category, starts_at, ends_at, all_day, calendar_name
    FROM device_events
    WHERE deleted_at IS NULL";

fn from_row(row: &Row) -> rusqlite::Result<CalendarEvent> {
    Ok(CalendarEvent {
        id: row.get(0)?,
        source: DEVICE_SOURCE.into(),
        editable: false,
        title: row.get(1)?,
        notes: row.get(2)?,
        category: category_from_str(&row.get::<_, String>(3)?),
        starts_at: from_millis(row.get(4)?),
        ends_at: opt_from_millis(row.get(5)?),
        all_day: row.get(6)?,
        completed: false,
        calendar_name: Some(row.get(7)?),
    })
}

/// An imported event, cleaned up for storage.
struct Normalized<'a> {
    input: &'a DeviceEventInput,
    title: String,
    category: &'static str,
    ends_at: Option<i64>,
}

fn normalize(e: &DeviceEventInput) -> Normalized<'_> {
    let title = match e.title.trim() {
        "" => "(No title)".to_string(),
        t => t.to_string(),
    };
    // Single-day all-day events and zero-length events have no meaningful end.
    let ends_at = e.ends_at.filter(|end| {
        *end > e.starts_at && !(e.all_day && *end - e.starts_at <= Duration::days(1))
    });
    Normalized {
        category: category_to_str(guess_category(&title)),
        title,
        input: e,
        ends_at: ends_at.map(to_millis),
    }
}

impl Store {
    /// Imported events overlapping `[start, end)`, ordered by start time.
    pub fn device_events_between(
        &self,
        start: DateTime<Utc>,
        end: DateTime<Utc>,
    ) -> Result<Vec<CalendarEvent>> {
        let mut stmt = self.conn.prepare(&format!(
            "{SELECT}
               AND starts_at < ?2 AND COALESCE(ends_at, starts_at) >= ?1
             ORDER BY starts_at"
        ))?;
        let rows = stmt.query_map(params![to_millis(start), to_millis(end)], from_row)?;
        Ok(rows.collect::<rusqlite::Result<_>>()?)
    }

    /// Makes the stored events starting in `[window_start, window_end)` match
    /// `events` (the complete set the device returned for that window):
    /// inserts new ones, updates changed ones, and soft-deletes ones that are
    /// gone (deleted in the calendar, or from a calendar no longer imported).
    pub fn import_device_events(
        &self,
        window_start: DateTime<Utc>,
        window_end: DateTime<Utc>,
        events: &[DeviceEventInput],
        now: DateTime<Utc>,
    ) -> Result<DeviceImportSummary> {
        let now = to_millis(now);
        let mut summary = DeviceImportSummary {
            added: 0,
            updated: 0,
            removed: 0,
        };
        let mut seen = HashSet::new();

        for e in events.iter().map(normalize) {
            if !seen.insert(e.input.external_id.as_str()) {
                continue; // duplicate in the input
            }
            let existing: Option<(String, bool)> = self
                .conn
                .query_row(
                    "SELECT id,
                            deleted_at IS NULL
                            AND title = ?2 AND notes = ?3 AND category = ?4
                            AND starts_at = ?5 AND ends_at IS ?6 AND all_day = ?7
                            AND calendar_id = ?8 AND calendar_name = ?9
                     FROM device_events WHERE external_id = ?1",
                    params![
                        e.input.external_id,
                        e.title,
                        e.input.notes,
                        e.category,
                        to_millis(e.input.starts_at),
                        e.ends_at,
                        e.input.all_day,
                        e.input.calendar_id,
                        e.input.calendar_name,
                    ],
                    |r| Ok((r.get(0)?, r.get(1)?)),
                )
                .optional()?;

            match existing {
                Some((_, true)) => {} // unchanged
                Some((id, false)) => {
                    self.conn.execute(
                        "UPDATE device_events
                         SET title = ?2, notes = ?3, category = ?4, starts_at = ?5, ends_at = ?6,
                             all_day = ?7, calendar_id = ?8, calendar_name = ?9,
                             updated_at = ?10, deleted_at = NULL
                         WHERE id = ?1",
                        params![
                            id,
                            e.title,
                            e.input.notes,
                            e.category,
                            to_millis(e.input.starts_at),
                            e.ends_at,
                            e.input.all_day,
                            e.input.calendar_id,
                            e.input.calendar_name,
                            now,
                        ],
                    )?;
                    summary.updated += 1;
                }
                None => {
                    self.conn.execute(
                        "INSERT INTO device_events
                             (id, external_id, calendar_id, calendar_name, title, notes, category,
                              starts_at, ends_at, all_day, created_at, updated_at)
                         VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, ?11, ?11)",
                        params![
                            new_id(),
                            e.input.external_id,
                            e.input.calendar_id,
                            e.input.calendar_name,
                            e.title,
                            e.input.notes,
                            e.category,
                            to_millis(e.input.starts_at),
                            e.ends_at,
                            e.input.all_day,
                            now,
                        ],
                    )?;
                    summary.added += 1;
                }
            }
        }

        // Anything in the window the device no longer reports is gone.
        let mut stmt = self.conn.prepare(
            "SELECT id, external_id FROM device_events
             WHERE deleted_at IS NULL AND starts_at >= ?1 AND starts_at < ?2",
        )?;
        let stale: Vec<String> = stmt
            .query_map(params![to_millis(window_start), to_millis(window_end)], |r| {
                Ok((r.get::<_, String>(0)?, r.get::<_, String>(1)?))
            })?
            .filter_map(|r| r.ok())
            .filter(|(_, ext)| !seen.contains(ext.as_str()))
            .map(|(id, _)| id)
            .collect();
        for id in stale {
            self.conn.execute(
                "UPDATE device_events SET deleted_at = ?2, updated_at = ?2 WHERE id = ?1",
                params![id, now],
            )?;
            summary.removed += 1;
        }
        Ok(summary)
    }

    /// Soft-deletes every imported event (used when import is switched off).
    pub fn clear_device_events(&self, now: DateTime<Utc>) -> Result<u32> {
        let n = self.conn.execute(
            "UPDATE device_events SET deleted_at = ?1, updated_at = ?1 WHERE deleted_at IS NULL",
            [to_millis(now)],
        )?;
        Ok(n as u32)
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::api::types::EventCategory;

    fn ev(id: &str, title: &str, day: i64) -> DeviceEventInput {
        let base = DateTime::from_timestamp(1_800_000_000, 0).unwrap();
        DeviceEventInput {
            external_id: id.into(),
            calendar_id: "cal1".into(),
            calendar_name: "School".into(),
            title: title.into(),
            notes: String::new(),
            starts_at: base + Duration::days(day),
            ends_at: Some(base + Duration::days(day) + Duration::hours(1)),
            all_day: false,
        }
    }

    #[test]
    fn import_upserts_and_removes() {
        let store = Store::open_in_memory().unwrap();
        let base = DateTime::from_timestamp(1_800_000_000, 0).unwrap();
        let (ws, we) = (base - Duration::days(1), base + Duration::days(30));
        let now = Utc::now();

        let first = vec![ev("a", "Math exam", 1), ev("b", "Team meeting", 2), ev("c", "TOK essay", 3)];
        let s = store.import_device_events(ws, we, &first, now).unwrap();
        assert_eq!((s.added, s.updated, s.removed), (3, 0, 0));

        let events = store.device_events_between(ws, we).unwrap();
        assert_eq!(events.len(), 3);
        assert!(events.iter().all(|e| !e.editable && e.source == DEVICE_SOURCE));
        assert_eq!(events[0].category, EventCategory::Exam);
        assert_eq!(events[2].category, EventCategory::Tok);
        assert_eq!(events[0].calendar_name.as_deref(), Some("School"));

        // Same data again: nothing changes.
        let s = store.import_device_events(ws, we, &first, now).unwrap();
        assert_eq!((s.added, s.updated, s.removed), (0, 0, 0));

        // "b" renamed, "c" deleted in the calendar.
        let second = vec![ev("a", "Math exam", 1), ev("b", "EE meeting", 2)];
        let s = store.import_device_events(ws, we, &second, now).unwrap();
        assert_eq!((s.added, s.updated, s.removed), (0, 1, 1));
        let events = store.device_events_between(ws, we).unwrap();
        assert_eq!(events.len(), 2);
        assert_eq!(events[1].category, EventCategory::ExtendedEssay);

        // "c" comes back: revived, not duplicated.
        let s = store.import_device_events(ws, we, &first, now).unwrap();
        assert_eq!((s.added, s.updated), (0, 2));

        assert_eq!(store.clear_device_events(now).unwrap(), 3);
        assert!(store.device_events_between(ws, we).unwrap().is_empty());
    }

    #[test]
    fn single_day_all_day_events_have_no_end() {
        let store = Store::open_in_memory().unwrap();
        let base = DateTime::from_timestamp(1_800_000_000, 0).unwrap();
        let mut e = ev("x", "", 1);
        e.all_day = true;
        e.ends_at = Some(e.starts_at + Duration::days(1));
        store
            .import_device_events(base, base + Duration::days(5), &[e], Utc::now())
            .unwrap();
        let got = &store.device_events_between(base, base + Duration::days(5)).unwrap()[0];
        assert_eq!(got.ends_at, None);
        assert_eq!(got.title, "(No title)");
    }
}
