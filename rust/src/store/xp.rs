use anyhow::Result;
use chrono::{DateTime, NaiveDate, Utc};
use rusqlite::params;

use super::{to_millis, Store};

const DATE_FMT: &str = "%Y-%m-%d";

/// A single XP-earning action.
pub struct XpEntry<'a> {
    /// Idempotency key, e.g. `reflection:<uuid>:exported`. Awarding the same key twice is a no-op.
    pub key: &'a str,
    pub amount: u32,
    /// The user's local calendar day the XP counts towards (drives streaks).
    pub day: NaiveDate,
}

impl Store {
    /// Records an award. Returns the XP actually gained (0 if `key` is
    /// already awarded). A previously revoked award is revived.
    pub fn award_xp(&self, entry: XpEntry, now: DateTime<Utc>) -> Result<u32> {
        if entry.amount == 0 {
            return Ok(0);
        }
        let inserted = self.conn.execute(
            "INSERT INTO xp_log (key, amount, earned_on, created_at, updated_at)
             VALUES (?1, ?2, ?3, ?4, ?4)
             ON CONFLICT(key) DO UPDATE
                 SET amount = excluded.amount, earned_on = excluded.earned_on,
                     updated_at = excluded.updated_at, deleted_at = NULL
                 WHERE xp_log.deleted_at IS NOT NULL",
            params![
                entry.key,
                entry.amount,
                entry.day.format(DATE_FMT).to_string(),
                to_millis(now),
            ],
        )?;
        Ok(if inserted == 1 { entry.amount } else { 0 })
    }

    /// Revokes (soft-deletes) every award whose key starts with `prefix`.
    pub fn revoke_xp_prefix(&self, prefix: &str, now: DateTime<Utc>) -> Result<()> {
        self.conn.execute(
            "UPDATE xp_log SET deleted_at = ?2, updated_at = ?2
             WHERE substr(key, 1, length(?1)) = ?1 AND deleted_at IS NULL",
            params![prefix, to_millis(now)],
        )?;
        Ok(())
    }

    pub fn total_xp(&self) -> Result<u32> {
        Ok(self.conn.query_row(
            "SELECT COALESCE(SUM(amount), 0) FROM xp_log WHERE deleted_at IS NULL",
            [],
            |r| r.get(0),
        )?)
    }

    /// XP per day for `[from, to]` inclusive, only days with XP > 0.
    pub fn xp_by_day(&self, from: NaiveDate, to: NaiveDate) -> Result<Vec<(NaiveDate, u32)>> {
        let mut stmt = self.conn.prepare(
            "SELECT earned_on, SUM(amount) FROM xp_log
             WHERE earned_on BETWEEN ?1 AND ?2 AND deleted_at IS NULL
             GROUP BY earned_on ORDER BY earned_on",
        )?;
        let rows = stmt.query_map(
            params![
                from.format(DATE_FMT).to_string(),
                to.format(DATE_FMT).to_string()
            ],
            |r| Ok((r.get::<_, String>(0)?, r.get::<_, u32>(1)?)),
        )?;
        let mut out = Vec::new();
        for row in rows {
            let (day, xp) = row?;
            if let Ok(day) = NaiveDate::parse_from_str(&day, DATE_FMT) {
                out.push((day, xp));
            }
        }
        Ok(out)
    }

    /// Every distinct day the user earned XP, ascending.
    pub fn active_days(&self) -> Result<Vec<NaiveDate>> {
        let mut stmt = self.conn.prepare(
            "SELECT DISTINCT earned_on FROM xp_log
                 WHERE deleted_at IS NULL ORDER BY earned_on",
        )?;
        let rows = stmt.query_map([], |r| r.get::<_, String>(0))?;
        let mut out = Vec::new();
        for row in rows {
            if let Ok(day) = NaiveDate::parse_from_str(&row?, DATE_FMT) {
                out.push(day);
            }
        }
        Ok(out)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn awards_are_idempotent_and_revocable() {
        let store = Store::open_in_memory().unwrap();
        let day = NaiveDate::from_ymd_opt(2026, 10, 21).unwrap();
        let now = Utc::now();
        let entry = || XpEntry {
            key: "reflection:1:done",
            amount: 20,
            day,
        };
        assert_eq!(store.award_xp(entry(), now).unwrap(), 20);
        assert_eq!(store.award_xp(entry(), now).unwrap(), 0);
        store
            .award_xp(
                XpEntry {
                    key: "reflection:10:done",
                    amount: 5,
                    day,
                },
                now,
            )
            .unwrap();
        assert_eq!(store.total_xp().unwrap(), 25);
        store.revoke_xp_prefix("reflection:1:", now).unwrap();
        assert_eq!(store.total_xp().unwrap(), 5);
        // Re-awarding a revoked key revives it.
        assert_eq!(store.award_xp(entry(), now).unwrap(), 20);
        assert_eq!(store.total_xp().unwrap(), 25);
    }
}
