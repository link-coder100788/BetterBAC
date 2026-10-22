use anyhow::{bail, Result};
use chrono::{DateTime, Utc};
use rusqlite::{params, OptionalExtension, Row};

use super::{
    from_millis, new_id, opt_from_millis, outcomes_from_bits, outcomes_to_bits, to_millis,
    word_count, Store,
};
use crate::api::types::{Reflection, ReflectionDraft};

// The experience join tolerates dangling ids (see the sync conventions in mod.rs).
const SELECT: &str = "
    SELECT r.id, e.id, e.title, r.title, r.body, r.outcomes,
           r.created_at, r.updated_at, r.exported_at
    FROM reflections r
    LEFT JOIN experiences e ON e.id = r.experience_id AND e.deleted_at IS NULL
    WHERE r.deleted_at IS NULL";

fn from_row(row: &Row) -> rusqlite::Result<Reflection> {
    let body: String = row.get(4)?;
    Ok(Reflection {
        id: row.get(0)?,
        experience_id: row.get(1)?,
        experience_title: row.get(2)?,
        title: row.get(3)?,
        word_count: word_count(&body),
        body,
        outcomes: outcomes_from_bits(row.get(5)?),
        created_at: from_millis(row.get(6)?),
        updated_at: from_millis(row.get(7)?),
        exported_at: opt_from_millis(row.get(8)?),
    })
}

/// Reflections may be saved half-written, so only the title is required.
fn normalized_title(draft: &ReflectionDraft) -> String {
    let title = draft.title.trim();
    if title.is_empty() {
        "Untitled reflection".into()
    } else {
        title.into()
    }
}

impl Store {
    /// Newest first. `experience_id` filters to a single experience.
    pub fn list_reflections(&self, experience_id: Option<&str>) -> Result<Vec<Reflection>> {
        let mut stmt = self.conn.prepare(&format!(
            "{SELECT} AND (?1 IS NULL OR r.experience_id = ?1) ORDER BY r.updated_at DESC"
        ))?;
        let rows = stmt.query_map([experience_id], from_row)?;
        Ok(rows.collect::<rusqlite::Result<_>>()?)
    }

    pub fn get_reflection(&self, id: &str) -> Result<Option<Reflection>> {
        Ok(self
            .conn
            .query_row(&format!("{SELECT} AND r.id = ?1"), [id], from_row)
            .optional()?)
    }

    pub fn create_reflection(&self, draft: &ReflectionDraft, now: DateTime<Utc>) -> Result<String> {
        let id = new_id();
        self.conn.execute(
            "INSERT INTO reflections
                 (id, experience_id, title, body, outcomes, created_at, updated_at)
             VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?6)",
            params![
                id,
                draft.experience_id,
                normalized_title(draft),
                draft.body,
                outcomes_to_bits(&draft.outcomes),
                to_millis(now),
            ],
        )?;
        Ok(id)
    }

    pub fn update_reflection(
        &self,
        id: &str,
        draft: &ReflectionDraft,
        now: DateTime<Utc>,
    ) -> Result<()> {
        let changed = self.conn.execute(
            "UPDATE reflections
             SET experience_id = ?2, title = ?3, body = ?4, outcomes = ?5, updated_at = ?6
             WHERE id = ?1 AND deleted_at IS NULL",
            params![
                id,
                draft.experience_id,
                normalized_title(draft),
                draft.body,
                outcomes_to_bits(&draft.outcomes),
                to_millis(now),
            ],
        )?;
        if changed == 0 {
            bail!("Reflection not found");
        }
        Ok(())
    }

    pub fn mark_reflection_exported(&self, id: &str, now: DateTime<Utc>) -> Result<()> {
        self.conn.execute(
            "UPDATE reflections SET exported_at = ?2, updated_at = ?2
             WHERE id = ?1 AND deleted_at IS NULL",
            params![id, to_millis(now)],
        )?;
        Ok(())
    }

    pub fn delete_reflection(&self, id: &str, now: DateTime<Utc>) -> Result<()> {
        self.conn.execute(
            "UPDATE reflections SET deleted_at = ?2, updated_at = ?2
             WHERE id = ?1 AND deleted_at IS NULL",
            params![id, to_millis(now)],
        )?;
        Ok(())
    }
}
