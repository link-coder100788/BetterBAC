//! Web (wasm) build only. Browsers have no file system, so the database
//! lives in memory and the UI saves snapshots of it to browser storage
//! (see `api::web`). Native builds never compile this (except for tests).

use anyhow::Result;
use rusqlite::{Connection, MAIN_DB};

use super::Store;

impl Store {
    /// Opens an in-memory database, restored from `snapshot` if given, and
    /// runs migrations as usual.
    pub fn open_snapshot(snapshot: Option<&[u8]>) -> Result<Self> {
        let mut conn = Connection::open_in_memory()?;
        if let Some(bytes) = snapshot.filter(|b| !b.is_empty()) {
            conn.deserialize_read_exact(MAIN_DB, bytes, bytes.len(), false)?;
        }
        Self::init(conn)
    }

    /// The whole database as bytes.
    pub fn snapshot(&self) -> Result<Vec<u8>> {
        Ok(self.conn.serialize(MAIN_DB)?.to_vec())
    }

    /// Rows changed since the connection opened; used to skip unchanged saves.
    pub fn total_changes(&self) -> u64 {
        self.conn.total_changes()
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::api::types::ExperienceDraft;
    use crate::api::types::Strand;
    use chrono::Utc;

    #[test]
    fn snapshot_round_trip() {
        let store = Store::open_snapshot(None).unwrap();
        assert_eq!(store.total_changes(), 0);
        store
            .create_experience(
                &ExperienceDraft {
                    title: "Band".into(),
                    description: String::new(),
                    strands: vec![Strand::Creativity],
                    is_project: false,
                    start_date: None,
                    end_date: None,
                },
                Utc::now(),
            )
            .unwrap();
        assert!(store.total_changes() > 0);

        let bytes = store.snapshot().unwrap();
        let restored = Store::open_snapshot(Some(&bytes)).unwrap();
        assert_eq!(restored.list_experiences().unwrap()[0].title, "Band");
        // Restoring doesn't count as a change.
        assert_eq!(restored.total_changes(), 0);
    }
}
