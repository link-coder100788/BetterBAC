use anyhow::{bail, Result};
use chrono::{DateTime, Utc};
use rusqlite::{params, OptionalExtension, Row};

use super::{
    category_from_str, category_to_str, from_millis, new_id, opt_from_millis, to_millis, Store,
};
use crate::api::types::{CalendarEvent, EventDraft};
use crate::calendar::MANUAL_SOURCE;

const SELECT: &str = "
    SELECT id, title, notes, category, starts_at, ends_at, all_day, completed_at IS NOT NULL
    FROM events
    WHERE deleted_at IS NULL";

fn from_row(row: &Row) -> rusqlite::Result<CalendarEvent> {
    Ok(CalendarEvent {
        id: row.get(0)?,
        source: MANUAL_SOURCE.into(),
        editable: true,
        title: row.get(1)?,
        notes: row.get(2)?,
        category: category_from_str(&row.get::<_, String>(3)?),
        starts_at: from_millis(row.get(4)?),
        ends_at: opt_from_millis(row.get(5)?),
        all_day: row.get(6)?,
        completed: row.get(7)?,
        calendar_name: None,
    })
}

fn validate(draft: &EventDraft) -> Result<()> {
    if draft.title.trim().is_empty() {
        bail!("Give your event a title");
    }
    if draft.ends_at.is_some_and(|end| end < draft.starts_at) {
        bail!("Event can't end before it starts");
    }
    Ok(())
}

impl Store {
    /// Events overlapping `[start, end)`, ordered by start time.
    pub fn events_between(
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

    pub fn get_event(&self, id: &str) -> Result<Option<CalendarEvent>> {
        Ok(self
            .conn
            .query_row(&format!("{SELECT} AND id = ?1"), [id], from_row)
            .optional()?)
    }

    pub fn create_event(&self, draft: &EventDraft, now: DateTime<Utc>) -> Result<String> {
        validate(draft)?;
        let id = new_id();
        self.conn.execute(
            "INSERT INTO events
                 (id, title, notes, category, starts_at, ends_at, all_day, created_at, updated_at)
             VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?8)",
            params![
                id,
                draft.title.trim(),
                draft.notes.trim(),
                category_to_str(draft.category),
                to_millis(draft.starts_at),
                draft.ends_at.map(to_millis),
                draft.all_day,
                to_millis(now),
            ],
        )?;
        Ok(id)
    }

    pub fn update_event(&self, id: &str, draft: &EventDraft, now: DateTime<Utc>) -> Result<()> {
        validate(draft)?;
        let changed = self.conn.execute(
            "UPDATE events
             SET title = ?2, notes = ?3, category = ?4, starts_at = ?5, ends_at = ?6,
                 all_day = ?7, updated_at = ?8
             WHERE id = ?1 AND deleted_at IS NULL",
            params![
                id,
                draft.title.trim(),
                draft.notes.trim(),
                category_to_str(draft.category),
                to_millis(draft.starts_at),
                draft.ends_at.map(to_millis),
                draft.all_day,
                to_millis(now),
            ],
        )?;
        if changed == 0 {
            bail!("Event not found");
        }
        Ok(())
    }

    pub fn set_event_completed(&self, id: &str, completed: bool, now: DateTime<Utc>) -> Result<()> {
        let now = to_millis(now);
        self.conn.execute(
            "UPDATE events SET completed_at = ?2, updated_at = ?3
             WHERE id = ?1 AND deleted_at IS NULL",
            params![id, completed.then_some(now), now],
        )?;
        Ok(())
    }

    pub fn delete_event(&self, id: &str, now: DateTime<Utc>) -> Result<()> {
        self.conn.execute(
            "UPDATE events SET deleted_at = ?2, updated_at = ?2
             WHERE id = ?1 AND deleted_at IS NULL",
            params![id, to_millis(now)],
        )?;
        Ok(())
    }
}
