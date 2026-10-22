//! Developer-only database tools: inspection, raw read-only queries, wipes.
//! Only reachable through `api::dev`, which is gated on `DEV_MENU`.

use anyhow::{bail, Result};
use rusqlite::types::ValueRef;
use rusqlite::{params_from_iter, Statement};

use super::{from_millis, Store};
use crate::api::dev::{DbOverview, DevTable, TableInfo};

/// Tables holding user data, wiped by "clear all progress".
const DATA_TABLES: &[&str] = &["experiences", "reflections", "events", "xp_log", "settings"];

/// Max rows any dev query returns, so a careless `SELECT *` can't hang the UI.
const MAX_ROWS: usize = 500;

impl Store {
    pub fn dev_overview(&self) -> Result<DbOverview> {
        let path = self.conn.path().unwrap_or("").to_string();
        let file_size = |p: &str| std::fs::metadata(p).map_or(0, |m| m.len());
        let size_bytes = if path.is_empty() {
            0
        } else {
            file_size(&path) + file_size(&format!("{path}-wal"))
        };

        let mut tables = Vec::new();
        for name in self.dev_table_names()? {
            let rows = self.count(&format!("SELECT COUNT(*) FROM \"{name}\""))?;
            let deleted_rows = if self.has_column(&name, "deleted_at")? {
                Some(self.count(&format!(
                    "SELECT COUNT(*) FROM \"{name}\" WHERE deleted_at IS NOT NULL"
                ))?)
            } else {
                None
            };
            tables.push(TableInfo {
                name,
                rows,
                deleted_rows,
            });
        }

        Ok(DbOverview {
            path,
            size_bytes,
            schema_version: self
                .conn
                .pragma_query_value(None, "user_version", |r| r.get(0))?,
            sqlite_version: rusqlite::version().to_string(),
            tables,
        })
    }

    fn count(&self, sql: &str) -> Result<u64> {
        let n: i64 = self.conn.query_row(sql, [], |r| r.get(0))?;
        Ok(n as u64)
    }

    fn dev_table_names(&self) -> Result<Vec<String>> {
        let mut stmt = self.conn.prepare(
            "SELECT name FROM sqlite_master
             WHERE type = 'table' AND name NOT LIKE 'sqlite_%' ORDER BY name",
        )?;
        let names = stmt.query_map([], |r| r.get(0))?;
        Ok(names.collect::<rusqlite::Result<_>>()?)
    }

    fn has_column(&self, table: &str, column: &str) -> Result<bool> {
        let mut stmt = self
            .conn
            .prepare(&format!("SELECT 1 FROM pragma_table_info('{table}') WHERE name = ?1"))?;
        Ok(stmt.exists([column])?)
    }

    /// A page of raw rows from `table` (validated against the schema).
    pub fn dev_table(&self, table: &str, offset: u32, limit: u32) -> Result<DevTable> {
        if !self.dev_table_names()?.iter().any(|t| t == table) {
            bail!("Unknown table {table}");
        }
        let total = self.count(&format!("SELECT COUNT(*) FROM \"{table}\""))?;
        let mut stmt = self
            .conn
            .prepare(&format!("SELECT * FROM \"{table}\" LIMIT ?1 OFFSET ?2"))?;
        let mut out = collect(&mut stmt, [limit.min(MAX_ROWS as u32), offset])?;
        out.total_rows = Some(total);
        Ok(out)
    }

    /// Runs a single read-only statement (SELECT, PRAGMA reads, …).
    pub fn dev_query(&self, sql: &str) -> Result<DevTable> {
        let mut stmt = self.conn.prepare(sql.trim())?;
        if !stmt.readonly() {
            bail!("Only read-only queries are allowed here");
        }
        collect(&mut stmt, std::iter::empty::<u32>())
    }

    /// Hard-deletes every row of user data. Dev only: bypasses soft deletes.
    pub fn dev_wipe(&self) -> Result<()> {
        for t in DATA_TABLES {
            self.conn.execute(&format!("DELETE FROM {t}"), [])?;
        }
        Ok(())
    }

    /// Hard-deletes the whole XP log (streaks and levels reset too).
    pub fn dev_wipe_xp(&self) -> Result<()> {
        self.conn.execute("DELETE FROM xp_log", [])?;
        Ok(())
    }
}

fn collect<P>(stmt: &mut Statement, params: P) -> Result<DevTable>
where
    P: IntoIterator,
    P::Item: rusqlite::ToSql,
{
    let columns: Vec<String> = stmt.column_names().iter().map(|c| c.to_string()).collect();
    // Integer columns named like timestamps also get a readable date.
    let is_time: Vec<bool> = columns
        .iter()
        .map(|c| c.ends_with("_at") || c.ends_with("_date"))
        .collect();

    let mut rows = Vec::new();
    let mut truncated = false;
    let mut result = stmt.query(params_from_iter(params))?;
    while let Some(row) = result.next()? {
        if rows.len() == MAX_ROWS {
            truncated = true;
            break;
        }
        let mut cells = Vec::with_capacity(columns.len());
        for (i, time) in is_time.iter().enumerate() {
            cells.push(match row.get_ref(i)? {
                ValueRef::Null => "NULL".to_string(),
                ValueRef::Integer(n) if *time => {
                    format!("{n} ({})", from_millis(n).format("%Y-%m-%d %H:%M UTC"))
                }
                ValueRef::Integer(n) => n.to_string(),
                ValueRef::Real(f) => f.to_string(),
                ValueRef::Text(t) => String::from_utf8_lossy(t).into_owned(),
                ValueRef::Blob(b) => format!("<blob {} bytes>", b.len()),
            });
        }
        rows.push(cells);
    }
    Ok(DevTable {
        columns,
        rows,
        total_rows: None,
        truncated,
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn inspect_query_and_wipe() {
        let store = Store::open_in_memory().unwrap();
        store
            .conn
            .execute(
                "INSERT INTO settings (key, value, updated_at) VALUES ('display_name', 'Noah', 0)",
                [],
            )
            .unwrap();

        let o = store.dev_overview().unwrap();
        let settings = o.tables.iter().find(|t| t.name == "settings").unwrap();
        assert_eq!((settings.rows, settings.deleted_rows), (1, None));
        let events = o.tables.iter().find(|t| t.name == "events").unwrap();
        assert_eq!(events.deleted_rows, Some(0));
        assert_eq!(o.schema_version, 2);

        let t = store.dev_table("settings", 0, 50).unwrap();
        assert_eq!(t.columns, ["key", "value", "updated_at"]);
        assert_eq!(t.rows[0][1], "Noah");
        assert!(t.rows[0][2].starts_with("0 (1970-01-01"));
        assert!(store.dev_table("settings; DROP TABLE events", 0, 1).is_err());

        assert_eq!(store.dev_query("SELECT 1 + 1 AS two").unwrap().rows, [["2"]]);
        assert!(store.dev_query("DELETE FROM settings").is_err());

        store.dev_wipe().unwrap();
        assert_eq!(store.dev_table("settings", 0, 50).unwrap().total_rows, Some(0));
    }
}
