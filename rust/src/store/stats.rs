use anyhow::Result;

use super::{outcomes_from_bits, strands_from_bits, word_count, Store};
use crate::api::types::{LearningOutcome, Strand};

/// Aggregate counts used by the dashboard and achievements.
#[derive(Debug, Default, Clone)]
pub struct Stats {
    pub experiences: u32,
    pub projects: u32,
    /// Experiences per strand, indexed by `Strand as usize`.
    pub strand_experiences: [u32; 3],
    /// Reflections evidencing each outcome, indexed by `LearningOutcome as usize`.
    pub outcome_reflections: [u32; 7],
    pub reflections_exported: u32,
    pub reflection_drafts: u32,
    pub words_exported: u32,
    pub events_completed: u32,
}

impl Store {
    pub fn stats(&self) -> Result<Stats> {
        let mut s = Stats::default();

        let mut stmt = self
            .conn
            .prepare("SELECT strands, is_project FROM experiences WHERE deleted_at IS NULL")?;
        let mut rows = stmt.query([])?;
        while let Some(row) = rows.next()? {
            s.experiences += 1;
            if row.get::<_, bool>(1)? {
                s.projects += 1;
            }
            for strand in strands_from_bits(row.get(0)?) {
                s.strand_experiences[strand as usize] += 1;
            }
        }

        let mut stmt = self.conn.prepare(
            "SELECT outcomes, body, exported_at IS NOT NULL FROM reflections
             WHERE deleted_at IS NULL",
        )?;
        let mut rows = stmt.query([])?;
        while let Some(row) = rows.next()? {
            for outcome in outcomes_from_bits(row.get(0)?) {
                s.outcome_reflections[outcome as usize] += 1;
            }
            if row.get::<_, bool>(2)? {
                s.reflections_exported += 1;
                s.words_exported += word_count(&row.get::<_, String>(1)?);
            } else {
                s.reflection_drafts += 1;
            }
        }

        s.events_completed = self.conn.query_row(
            "SELECT COUNT(*) FROM events WHERE completed_at IS NOT NULL AND deleted_at IS NULL",
            [],
            |r| r.get(0),
        )?;
        Ok(s)
    }
}

impl Stats {
    pub fn strand(&self, strand: Strand) -> u32 {
        self.strand_experiences[strand as usize]
    }

    pub fn outcome(&self, outcome: LearningOutcome) -> u32 {
        self.outcome_reflections[outcome as usize]
    }
}
