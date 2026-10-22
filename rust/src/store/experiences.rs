use anyhow::{bail, Result};
use chrono::{DateTime, Utc};
use rusqlite::{params, OptionalExtension, Row};

use super::{
    from_millis, new_id, opt_from_millis, strands_from_bits, strands_to_bits, to_millis, Store,
};
use crate::api::types::{Experience, ExperienceDraft};

const SELECT: &str = "
    SELECT e.id, e.title, e.description, e.strands, e.is_project,
           e.start_date, e.end_date, e.created_at,
           (SELECT COUNT(*) FROM reflections r
            WHERE r.experience_id = e.id AND r.deleted_at IS NULL)
    FROM experiences e
    WHERE e.deleted_at IS NULL";

fn from_row(row: &Row) -> rusqlite::Result<Experience> {
    Ok(Experience {
        id: row.get(0)?,
        title: row.get(1)?,
        description: row.get(2)?,
        strands: strands_from_bits(row.get(3)?),
        is_project: row.get(4)?,
        start_date: opt_from_millis(row.get(5)?),
        end_date: opt_from_millis(row.get(6)?),
        created_at: from_millis(row.get(7)?),
        reflection_count: row.get(8)?,
    })
}

fn validate(draft: &ExperienceDraft) -> Result<()> {
    if draft.title.trim().is_empty() {
        bail!("Give your experience a title");
    }
    if draft.strands.is_empty() {
        bail!("Pick at least one strand");
    }
    if let (Some(start), Some(end)) = (draft.start_date, draft.end_date) {
        if end < start {
            bail!("End date can't be before the start date");
        }
    }
    Ok(())
}

impl Store {
    pub fn list_experiences(&self) -> Result<Vec<Experience>> {
        let mut stmt = self
            .conn
            .prepare(&format!("{SELECT} ORDER BY e.created_at DESC"))?;
        let rows = stmt.query_map([], from_row)?;
        Ok(rows.collect::<rusqlite::Result<_>>()?)
    }

    pub fn get_experience(&self, id: &str) -> Result<Option<Experience>> {
        Ok(self
            .conn
            .query_row(&format!("{SELECT} AND e.id = ?1"), [id], from_row)
            .optional()?)
    }

    pub fn create_experience(&self, draft: &ExperienceDraft, now: DateTime<Utc>) -> Result<String> {
        validate(draft)?;
        let id = new_id();
        self.conn.execute(
            "INSERT INTO experiences
                 (id, title, description, strands, is_project, start_date, end_date,
                  created_at, updated_at)
             VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?8)",
            params![
                id,
                draft.title.trim(),
                draft.description.trim(),
                strands_to_bits(&draft.strands),
                draft.is_project,
                draft.start_date.map(to_millis),
                draft.end_date.map(to_millis),
                to_millis(now),
            ],
        )?;
        Ok(id)
    }

    pub fn update_experience(
        &self,
        id: &str,
        draft: &ExperienceDraft,
        now: DateTime<Utc>,
    ) -> Result<()> {
        validate(draft)?;
        let changed = self.conn.execute(
            "UPDATE experiences
             SET title = ?2, description = ?3, strands = ?4, is_project = ?5,
                 start_date = ?6, end_date = ?7, updated_at = ?8
             WHERE id = ?1 AND deleted_at IS NULL",
            params![
                id,
                draft.title.trim(),
                draft.description.trim(),
                strands_to_bits(&draft.strands),
                draft.is_project,
                draft.start_date.map(to_millis),
                draft.end_date.map(to_millis),
                to_millis(now),
            ],
        )?;
        if changed == 0 {
            bail!("Experience not found");
        }
        Ok(())
    }

    /// Soft-deletes the experience and unlinks its reflections (which are kept).
    pub fn delete_experience(&self, id: &str, now: DateTime<Utc>) -> Result<()> {
        let now = to_millis(now);
        self.conn.execute(
            "UPDATE experiences SET deleted_at = ?2, updated_at = ?2
             WHERE id = ?1 AND deleted_at IS NULL",
            params![id, now],
        )?;
        self.conn.execute(
            "UPDATE reflections SET experience_id = NULL, updated_at = ?2
             WHERE experience_id = ?1",
            params![id, now],
        )?;
        Ok(())
    }
}
