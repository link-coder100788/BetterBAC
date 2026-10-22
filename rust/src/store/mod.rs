//! On-device SQLite persistence. All SQL lives under this module.
//!
//! # Sync-readiness conventions
//!
//! The app is local-first: this database is the source of truth on each
//! device, and a future sync module will exchange changed rows with a server.
//! To keep that possible, every table that holds user data follows these rules:
//!
//! - **Ids are UUID v7 strings** generated on the device ([`new_id`]), never
//!   autoincrement integers, so rows created offline on different devices
//!   never collide.
//! - **`updated_at`** (Unix millis) is bumped on every write, so sync can ask
//!   "what changed since T" and resolve conflicts last-writer-wins.
//! - **Deletes are soft**: set `deleted_at` (and `updated_at`) instead of
//!   removing the row, so deletions propagate. Every read filters
//!   `deleted_at IS NULL`.
//! - **No foreign-key constraints** between synced tables: a reflection may
//!   arrive before the experience it references. Reads use LEFT JOINs that
//!   tolerate dangling references.
//! - **XP awards are keyed** (`xp_log.key`) so the same award made on two
//!   devices merges into one.

mod events;
mod experiences;
mod reflections;
mod settings;
mod stats;
mod xp;

use anyhow::{Context, Result};
use chrono::{DateTime, Utc};
use rusqlite::functions::FunctionFlags;
use rusqlite::Connection;
use std::path::Path;

use crate::api::types::{EventCategory, LearningOutcome, Strand};

pub use stats::Stats;
pub use xp::XpEntry;

/// Ordered list of schema migrations; `PRAGMA user_version` records how many
/// have been applied. Only ever append to this list.
const MIGRATIONS: &[&str] = &[
    r#"
    CREATE TABLE experiences (
        id           INTEGER PRIMARY KEY,
        title        TEXT    NOT NULL,
        description  TEXT    NOT NULL DEFAULT '',
        strands      INTEGER NOT NULL DEFAULT 0,
        is_project   INTEGER NOT NULL DEFAULT 0,
        start_date   INTEGER,
        end_date     INTEGER,
        created_at   INTEGER NOT NULL
    );

    CREATE TABLE reflections (
        id            INTEGER PRIMARY KEY,
        experience_id INTEGER REFERENCES experiences(id) ON DELETE SET NULL,
        title         TEXT    NOT NULL,
        body          TEXT    NOT NULL DEFAULT '',
        outcomes      INTEGER NOT NULL DEFAULT 0,
        created_at    INTEGER NOT NULL,
        updated_at    INTEGER NOT NULL,
        exported_at   INTEGER
    );
    CREATE INDEX reflections_experience ON reflections(experience_id);

    CREATE TABLE events (
        id           INTEGER PRIMARY KEY,
        title        TEXT    NOT NULL,
        notes        TEXT    NOT NULL DEFAULT '',
        category     TEXT    NOT NULL,
        starts_at    INTEGER NOT NULL,
        ends_at      INTEGER,
        all_day      INTEGER NOT NULL DEFAULT 0,
        completed_at INTEGER
    );
    CREATE INDEX events_starts_at ON events(starts_at);

    -- One row per XP-earning action; `key` makes awards idempotent.
    CREATE TABLE xp_log (
        key        TEXT    PRIMARY KEY,
        amount     INTEGER NOT NULL,
        earned_on  TEXT    NOT NULL, -- local calendar date, YYYY-MM-DD
        created_at INTEGER NOT NULL
    );
    CREATE INDEX xp_log_earned_on ON xp_log(earned_on);

    CREATE TABLE settings (
        key   TEXT PRIMARY KEY,
        value TEXT NOT NULL
    );
"#,
    // 2: sync-readiness. Integer ids -> UUID strings, updated_at/deleted_at on
    // every table, foreign keys dropped. Existing data (and the ids embedded in
    // XP keys) is carried over via a temporary id map.
    r#"
    CREATE TEMP TABLE id_map (
        kind   TEXT    NOT NULL,
        old_id INTEGER NOT NULL,
        new_id TEXT    NOT NULL,
        PRIMARY KEY (kind, old_id)
    );
    INSERT INTO id_map SELECT 'experience', id, new_id() FROM experiences;
    INSERT INTO id_map SELECT 'reflection', id, new_id() FROM reflections;
    INSERT INTO id_map SELECT 'event',      id, new_id() FROM events;

    CREATE TABLE experiences_v2 (
        id           TEXT    PRIMARY KEY,
        title        TEXT    NOT NULL,
        description  TEXT    NOT NULL DEFAULT '',
        strands      INTEGER NOT NULL DEFAULT 0,
        is_project   INTEGER NOT NULL DEFAULT 0,
        start_date   INTEGER,
        end_date     INTEGER,
        created_at   INTEGER NOT NULL,
        updated_at   INTEGER NOT NULL,
        deleted_at   INTEGER
    );
    INSERT INTO experiences_v2
    SELECT m.new_id, e.title, e.description, e.strands, e.is_project,
           e.start_date, e.end_date, e.created_at, e.created_at, NULL
    FROM experiences e
    JOIN id_map m ON m.kind = 'experience' AND m.old_id = e.id;

    CREATE TABLE reflections_v2 (
        id            TEXT    PRIMARY KEY,
        experience_id TEXT,
        title         TEXT    NOT NULL,
        body          TEXT    NOT NULL DEFAULT '',
        outcomes      INTEGER NOT NULL DEFAULT 0,
        created_at    INTEGER NOT NULL,
        updated_at    INTEGER NOT NULL,
        exported_at   INTEGER,
        deleted_at    INTEGER
    );
    INSERT INTO reflections_v2
    SELECT m.new_id, em.new_id, r.title, r.body, r.outcomes,
           r.created_at, r.updated_at, r.exported_at, NULL
    FROM reflections r
    JOIN id_map m ON m.kind = 'reflection' AND m.old_id = r.id
    LEFT JOIN id_map em ON em.kind = 'experience' AND em.old_id = r.experience_id;

    CREATE TABLE events_v2 (
        id           TEXT    PRIMARY KEY,
        title        TEXT    NOT NULL,
        notes        TEXT    NOT NULL DEFAULT '',
        category     TEXT    NOT NULL,
        starts_at    INTEGER NOT NULL,
        ends_at      INTEGER,
        all_day      INTEGER NOT NULL DEFAULT 0,
        completed_at INTEGER,
        created_at   INTEGER NOT NULL,
        updated_at   INTEGER NOT NULL,
        deleted_at   INTEGER
    );
    INSERT INTO events_v2
    SELECT m.new_id, e.title, e.notes, e.category, e.starts_at, e.ends_at,
           e.all_day, e.completed_at, now_millis(), now_millis(), NULL
    FROM events e
    JOIN id_map m ON m.kind = 'event' AND m.old_id = e.id;

    CREATE TABLE xp_log_v2 (
        key        TEXT    PRIMARY KEY,
        amount     INTEGER NOT NULL,
        earned_on  TEXT    NOT NULL, -- local calendar date, YYYY-MM-DD
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL,
        deleted_at INTEGER
    );
    -- Keys look like "<kind>:<old id>:<suffix>"; swap in the new id.
    WITH parts AS (
        SELECT x.*,
               substr(x.key, 1, instr(x.key, ':') - 1) AS kind,
               substr(x.key, instr(x.key, ':') + 1)    AS rest
        FROM xp_log x
    )
    INSERT INTO xp_log_v2
    SELECT COALESCE(p.kind || ':' || m.new_id || substr(p.rest, instr(p.rest, ':')), p.key),
           p.amount, p.earned_on, p.created_at, p.created_at, NULL
    FROM parts p
    LEFT JOIN id_map m
        ON m.kind = p.kind
       AND m.old_id = CAST(substr(p.rest, 1, instr(p.rest, ':') - 1) AS INTEGER);

    CREATE TABLE settings_v2 (
        key        TEXT    PRIMARY KEY,
        value      TEXT,   -- NULL = cleared (kept so the clear can sync)
        updated_at INTEGER NOT NULL
    );
    INSERT INTO settings_v2 SELECT key, value, now_millis() FROM settings;

    DROP TABLE reflections;
    DROP TABLE experiences;
    DROP TABLE events;
    DROP TABLE xp_log;
    DROP TABLE settings;
    DROP TABLE id_map;
    ALTER TABLE experiences_v2 RENAME TO experiences;
    ALTER TABLE reflections_v2 RENAME TO reflections;
    ALTER TABLE events_v2      RENAME TO events;
    ALTER TABLE xp_log_v2      RENAME TO xp_log;
    ALTER TABLE settings_v2    RENAME TO settings;

    CREATE INDEX reflections_experience ON reflections(experience_id);
    CREATE INDEX events_starts_at       ON events(starts_at);
    CREATE INDEX xp_log_earned_on       ON xp_log(earned_on);
    -- For "what changed since T" during sync.
    CREATE INDEX experiences_updated_at ON experiences(updated_at);
    CREATE INDEX reflections_updated_at ON reflections(updated_at);
    CREATE INDEX events_updated_at      ON events(updated_at);
    CREATE INDEX xp_log_updated_at      ON xp_log(updated_at);
"#,
];

/// A new globally unique, time-ordered row id.
pub fn new_id() -> String {
    uuid::Uuid::now_v7().to_string()
}

pub struct Store {
    conn: Connection,
}

impl Store {
    pub fn open(path: impl AsRef<Path>) -> Result<Self> {
        let path = path.as_ref();
        let conn = Connection::open(path)
            .with_context(|| format!("opening database at {}", path.display()))?;
        Self::init(conn)
    }

    #[cfg(test)]
    pub fn open_in_memory() -> Result<Self> {
        Self::init(Connection::open_in_memory()?)
    }

    fn init(conn: Connection) -> Result<Self> {
        conn.pragma_update(None, "journal_mode", "WAL")?;
        register_functions(&conn)?;
        let mut store = Self { conn };
        store.migrate_to(MIGRATIONS.len())?;
        Ok(store)
    }

    /// Applies pending migrations up to (and including) number `target`.
    fn migrate_to(&mut self, target: usize) -> Result<()> {
        let applied: i64 = self
            .conn
            .pragma_query_value(None, "user_version", |r| r.get(0))?;
        let applied = applied as usize;
        if applied >= target {
            return Ok(());
        }
        let tx = self.conn.transaction()?;
        for (i, sql) in MIGRATIONS.iter().enumerate().take(target).skip(applied) {
            tx.execute_batch(sql)
                .with_context(|| format!("applying migration {}", i + 1))?;
        }
        tx.pragma_update(None, "user_version", target as i64)?;
        tx.commit()?;
        Ok(())
    }

    /// Runs `f` atomically. Callers must hold exclusive access to the store
    /// (see `state::with_core`), which is why `&self` suffices here.
    pub fn in_transaction<T>(&self, f: impl FnOnce(&Self) -> Result<T>) -> Result<T> {
        let tx = self.conn.unchecked_transaction()?;
        let out = f(self)?;
        tx.commit()?;
        Ok(out)
    }
}

/// SQL helpers available to migrations and queries.
fn register_functions(conn: &Connection) -> Result<()> {
    conn.create_scalar_function("new_id", 0, FunctionFlags::SQLITE_UTF8, |_| Ok(new_id()))?;
    conn.create_scalar_function("now_millis", 0, FunctionFlags::SQLITE_UTF8, |_| {
        Ok(Utc::now().timestamp_millis())
    })?;
    Ok(())
}

// ---------------------------------------------------------------------------
// Column encodings
// ---------------------------------------------------------------------------

fn to_millis(t: DateTime<Utc>) -> i64 {
    t.timestamp_millis()
}

fn from_millis(ms: i64) -> DateTime<Utc> {
    DateTime::from_timestamp_millis(ms).unwrap_or_default()
}

fn opt_from_millis(ms: Option<i64>) -> Option<DateTime<Utc>> {
    ms.map(from_millis)
}

fn strands_to_bits(strands: &[Strand]) -> i64 {
    strands.iter().fold(0, |acc, s| acc | 1 << *s as u8)
}

fn strands_from_bits(bits: i64) -> Vec<Strand> {
    Strand::ALL
        .into_iter()
        .filter(|s| bits & (1 << *s as u8) != 0)
        .collect()
}

fn outcomes_to_bits(outcomes: &[LearningOutcome]) -> i64 {
    outcomes.iter().fold(0, |acc, o| acc | 1 << *o as u8)
}

fn outcomes_from_bits(bits: i64) -> Vec<LearningOutcome> {
    LearningOutcome::ALL
        .into_iter()
        .filter(|o| bits & (1 << *o as u8) != 0)
        .collect()
}

fn category_to_str(c: EventCategory) -> &'static str {
    match c {
        EventCategory::Cas => "cas",
        EventCategory::ExtendedEssay => "ee",
        EventCategory::Tok => "tok",
        EventCategory::InternalAssessment => "ia",
        EventCategory::Exam => "exam",
        EventCategory::Homework => "homework",
        EventCategory::Other => "other",
    }
}

fn category_from_str(s: &str) -> EventCategory {
    EventCategory::ALL
        .into_iter()
        .find(|c| category_to_str(*c) == s)
        .unwrap_or(EventCategory::Other)
}

pub(crate) fn word_count(text: &str) -> u32 {
    text.split_whitespace().count() as u32
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn bitmask_round_trips() {
        let s = vec![Strand::Creativity, Strand::Service];
        assert_eq!(strands_from_bits(strands_to_bits(&s)), s);
        let o = vec![LearningOutcome::Awareness, LearningOutcome::Ethics];
        assert_eq!(outcomes_from_bits(outcomes_to_bits(&o)), o);
    }

    #[test]
    fn migrations_are_idempotent() {
        let mut store = Store::open_in_memory().unwrap();
        store.migrate_to(MIGRATIONS.len()).unwrap();
    }

    /// Data written under the integer-id schema survives the move to UUIDs,
    /// including links between rows and the ids embedded in XP keys.
    #[test]
    fn migration_2_preserves_data() {
        let conn = Connection::open_in_memory().unwrap();
        register_functions(&conn).unwrap();
        let mut store = Store { conn };
        store.migrate_to(1).unwrap();
        store
            .conn
            .execute_batch(
                "INSERT INTO experiences (id, title, strands, created_at) VALUES (7, 'Band', 1, 1000);
                 INSERT INTO reflections (id, experience_id, title, body, created_at, updated_at)
                     VALUES (3, 7, 'Jam', 'words here', 2000, 2000);
                 INSERT INTO events (id, title, category, starts_at) VALUES (9, 'EE', 'ee', 3000);
                 INSERT INTO xp_log VALUES ('reflection:3:exported', 25, '2026-10-21', 2000);
                 INSERT INTO xp_log VALUES ('event:9:completed', 5, '2026-10-21', 3000);
                 INSERT INTO settings VALUES ('display_name', 'Noah');",
            )
            .unwrap();
        store.migrate_to(2).unwrap();

        let exp = &store.list_experiences().unwrap()[0];
        assert_eq!(exp.title, "Band");
        assert_eq!(exp.id.len(), 36);
        assert_eq!(exp.reflection_count, 1);

        let refl = &store.list_reflections(None).unwrap()[0];
        assert_eq!(refl.experience_id.as_deref(), Some(exp.id.as_str()));
        assert_eq!(refl.experience_title.as_deref(), Some("Band"));

        let event_id: String = store
            .conn
            .query_row("SELECT id FROM events", [], |r| r.get(0))
            .unwrap();
        let mut keys: Vec<String> = store
            .conn
            .prepare("SELECT key FROM xp_log ORDER BY key")
            .unwrap()
            .query_map([], |r| r.get(0))
            .unwrap()
            .map(|k| k.unwrap())
            .collect();
        keys.sort();
        let mut expected = vec![
            format!("event:{event_id}:completed"),
            format!("reflection:{}:exported", refl.id),
        ];
        expected.sort();
        assert_eq!(keys, expected);
        assert_eq!(store.total_xp().unwrap(), 30);
        assert_eq!(store.settings().unwrap().display_name, "Noah");
    }
}
