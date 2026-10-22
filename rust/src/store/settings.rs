use anyhow::Result;
use chrono::{DateTime, Utc};
use rusqlite::{params, OptionalExtension};

use super::{to_millis, Store};
use crate::api::types::Settings;

const DISPLAY_NAME: &str = "display_name";
const CAS_URL: &str = "managebac_cas_url";
const DAILY_GOAL: &str = "daily_goal_xp";
const TUTORIAL_SEEN: &str = "tutorial_seen_version";

pub const DEFAULT_DAILY_GOAL_XP: u32 = 20;

impl Store {
    fn get_setting(&self, key: &str) -> Result<Option<String>> {
        Ok(self
            .conn
            .query_row("SELECT value FROM settings WHERE key = ?1", [key], |r| {
                r.get::<_, Option<String>>(0)
            })
            .optional()?
            .flatten())
    }

    /// `None` clears the setting but keeps the row, so the clear can sync.
    /// Unchanged values don't bump `updated_at`.
    fn put_setting(&self, key: &str, value: Option<&str>, now: DateTime<Utc>) -> Result<()> {
        self.conn.execute(
            "INSERT INTO settings (key, value, updated_at) VALUES (?1, ?2, ?3)
             ON CONFLICT(key) DO UPDATE
                 SET value = excluded.value, updated_at = excluded.updated_at
                 WHERE settings.value IS NOT excluded.value",
            params![key, value, to_millis(now)],
        )?;
        Ok(())
    }

    pub fn settings(&self) -> Result<Settings> {
        Ok(Settings {
            display_name: self.get_setting(DISPLAY_NAME)?.unwrap_or_default(),
            managebac_cas_url: self.get_setting(CAS_URL)?,
            daily_goal_xp: self
                .get_setting(DAILY_GOAL)?
                .and_then(|v| v.parse().ok())
                .unwrap_or(DEFAULT_DAILY_GOAL_XP),
        })
    }

    /// Stores already-validated settings (see `api::settings`).
    pub fn save_settings(&self, s: &Settings, now: DateTime<Utc>) -> Result<()> {
        self.put_setting(DISPLAY_NAME, Some(&s.display_name), now)?;
        self.put_setting(CAS_URL, s.managebac_cas_url.as_deref(), now)?;
        self.put_setting(DAILY_GOAL, Some(&s.daily_goal_xp.to_string()), now)?;
        Ok(())
    }

    /// Highest tutorial version the user has finished (0 = never).
    pub fn tutorial_seen_version(&self) -> Result<u32> {
        Ok(self
            .get_setting(TUTORIAL_SEEN)?
            .and_then(|v| v.parse().ok())
            .unwrap_or(0))
    }

    pub fn set_tutorial_seen_version(&self, version: u32, now: DateTime<Utc>) -> Result<()> {
        self.put_setting(TUTORIAL_SEEN, Some(&version.to_string()), now)
    }
}
