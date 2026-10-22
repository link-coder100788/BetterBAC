//! Developer menu: tools for testing on a real device (XP, sample data,
//! wiping progress, and inspecting the on-device database).
//!
//! **Set [`DEV_MENU`] to `false` before shipping.** It hides the menu in the
//! UI, and every function here refuses to run while it's off.

use anyhow::{bail, Result};
use chrono::{Duration, NaiveDate};
use flutter_rust_bridge::frb;

use super::types::{
    EventCategory, EventDraft, ExperienceDraft, LearningOutcome, ReflectionDraft, Strand,
};
use crate::calendar::local_midnight;
use crate::progress;
use crate::state::{self, with_core};
use crate::store::{new_id, XpEntry};

/// Compiled-in switch for the developer menu.
const DEV_MENU: bool = true;

#[derive(Debug, Clone)]
pub struct TableInfo {
    pub name: String,
    pub rows: u64,
    /// Soft-deleted rows, for tables that have `deleted_at`.
    pub deleted_rows: Option<u64>,
}

#[derive(Debug, Clone)]
pub struct DbOverview {
    pub path: String,
    /// Database file plus its write-ahead log.
    pub size_bytes: u64,
    pub schema_version: u32,
    pub sqlite_version: String,
    pub tables: Vec<TableInfo>,
}

/// Raw query results, every cell rendered as text.
#[derive(Debug, Clone)]
pub struct DevTable {
    pub columns: Vec<String>,
    pub rows: Vec<Vec<String>>,
    /// Total rows in the table, when browsing a table.
    pub total_rows: Option<u64>,
    /// True if more rows matched than were returned.
    pub truncated: bool,
}

#[frb(sync)]
pub fn dev_menu_enabled() -> bool {
    DEV_MENU
}

fn ensure_enabled() -> Result<()> {
    if !DEV_MENU {
        bail!("The developer menu is disabled in this build");
    }
    Ok(())
}

// ---------------------------------------------------------------------------
// XP and streaks
// ---------------------------------------------------------------------------

/// Grants `amount` XP today.
pub fn dev_add_xp(amount: u32) -> Result<()> {
    ensure_enabled()?;
    let (now, today) = (state::now(), state::today());
    with_core(|store, _| {
        store.award_xp(
            XpEntry {
                key: &format!("dev:xp:{}", new_id()),
                amount,
                day: today,
            },
            now,
        )?;
        Ok(())
    })
}

/// Makes the last `days` days (ending today) active, giving a streak of at
/// least `days`.
pub fn dev_set_streak(days: u32) -> Result<()> {
    ensure_enabled()?;
    let (now, today) = (state::now(), state::today());
    with_core(|store, _| {
        for back in 0..days {
            let day = today - Duration::days(back.into());
            store.award_xp(
                XpEntry {
                    key: &format!("dev:streak:{day}"),
                    amount: 1,
                    day,
                },
                now,
            )?;
        }
        Ok(())
    })
}

/// Deletes all XP: total, level, streak and history back to zero.
pub fn dev_reset_xp() -> Result<()> {
    ensure_enabled()?;
    with_core(|store, _| store.dev_wipe_xp())
}

// ---------------------------------------------------------------------------
// Onboarding and tour
// ---------------------------------------------------------------------------

/// 0 = tour shows in full on next launch; current - 1 = "What's new".
pub fn dev_set_tutorial_seen(version: u32) -> Result<()> {
    ensure_enabled()?;
    let now = state::now();
    with_core(|store, _| store.set_tutorial_seen_version(version, now))
}

/// Clears the name so the welcome screen shows again.
pub fn dev_reset_onboarding() -> Result<()> {
    ensure_enabled()?;
    let now = state::now();
    with_core(|store, _| {
        let mut settings = store.settings()?;
        settings.display_name.clear();
        store.save_settings(&settings, now)
    })
}

// ---------------------------------------------------------------------------
// Data
// ---------------------------------------------------------------------------

/// Deletes every experience, reflection, event, XP award and setting.
pub fn dev_clear_all() -> Result<()> {
    ensure_enabled()?;
    with_core(|store, _| store.dev_wipe())
}

/// Adds a realistic set of experiences, reflections, deadlines (including a
/// crunch week) and a week-long streak. Also useful as a demo for judges.
pub fn dev_seed_sample_data() -> Result<()> {
    ensure_enabled()?;
    let (now, today) = (state::now(), state::today());
    let at = |day: NaiveDate, hour: i64| local_midnight(day) + Duration::hours(hour);

    with_core(|store, _| {
        let award = |key: String, amount: u32, day: NaiveDate| {
            store.award_xp(XpEntry { key: &key, amount, day }, now)
        };

        // Experiences
        let experiences = [
            ("School jazz band", "Weekly rehearsals and the spring concert.", vec![Strand::Creativity], false, 60),
            ("Food bank volunteering", "Sorting donations every Saturday with friends.", vec![Strand::Service, Strand::Activity], true, 45),
            ("Climbing club", "Training twice a week; aiming for my first outdoor lead climb.", vec![Strand::Activity], false, 30),
        ];
        let mut ids = Vec::new();
        for (title, description, strands, is_project, days_ago) in experiences {
            let id = store.create_experience(
                &ExperienceDraft {
                    title: title.into(),
                    description: description.into(),
                    strands,
                    is_project,
                    start_date: Some(at(today - Duration::days(days_ago), 9)),
                    end_date: None,
                },
                now,
            )?;
            award(progress::experience_key(&id), progress::XP_EXPERIENCE_CREATED, today - Duration::days(6))?;
            ids.push(id);
        }

        // Reflections: two sent to ManageBAC, two drafts.
        let reflections = [
            (0, "Learning to improvise", "I was nervous before my first solo because I always play from sheet music. When I missed a note, I panicked, but our director told me to repeat it like I meant it. I learned that mistakes can become part of the music, and that I rely too much on preparation. Next time I will practise improvising for five minutes every rehearsal so it feels less scary.", vec![LearningOutcome::Challenge, LearningOutcome::Awareness], true),
            (1, "Planning the winter drive", "Our team planned a winter food drive for the whole school. I organised the collection schedule and made posters. Working with five other people was hard because we disagreed about dates, but we compromised and collected over 400 items for local families. I felt proud and realised how much our community relies on volunteers. In the future I want to involve younger students too.", vec![LearningOutcome::Initiative, LearningOutcome::Collaboration, LearningOutcome::GlobalEngagement], true),
            (2, "First lead climb nerves", "Today I tried leading a route for the first time. I got halfway and came down. I felt frustrated with myself.", vec![LearningOutcome::Commitment], false),
            (1, "Why food waste matters", "We went to the food bank. Then we sorted cans. After that we packed boxes. Then we went home.", vec![], false),
        ];
        for (exp, title, body, outcomes, sent) in reflections {
            let id = store.create_reflection(
                &ReflectionDraft {
                    experience_id: Some(ids[exp].clone()),
                    title: title.into(),
                    body: body.into(),
                    outcomes,
                },
                now,
            )?;
            if sent {
                store.mark_reflection_exported(&id, now)?;
                let words = crate::store::word_count(body);
                award(progress::reflection_export_key(&id), progress::reflection_export_xp(words), today - Duration::days(3))?;
            }
        }

        // Deadlines: a few this week, a crunch week two weeks out.
        let events = [
            ("TOK exhibition draft", EventCategory::Tok, 1, true),
            ("Climbing club session", EventCategory::Cas, 2, false),
            ("Chemistry homework", EventCategory::Homework, 3, false),
            ("Math AA paper 2 mock", EventCategory::Exam, 14, false),
            ("EE full draft due", EventCategory::ExtendedEssay, 15, false),
            ("Physics IA final", EventCategory::InternalAssessment, 16, false),
            ("History essay", EventCategory::Homework, 22, false),
        ];
        for (title, category, in_days, done) in events {
            let id = store.create_event(
                &EventDraft {
                    title: title.into(),
                    notes: String::new(),
                    category,
                    starts_at: at(today + Duration::days(in_days), 15),
                    ends_at: None,
                    all_day: false,
                },
                now,
            )?;
            if done {
                store.set_event_completed(&id, true, now)?;
                award(progress::event_key(&id), progress::XP_EVENT_COMPLETED, today)?;
            }
        }

        // A week-long streak.
        for back in 0..7 {
            let day = today - Duration::days(back);
            award(format!("dev:streak:{day}"), 5, day)?;
        }
        Ok(())
    })
}

// ---------------------------------------------------------------------------
// Database inspector
// ---------------------------------------------------------------------------

pub fn dev_db_overview() -> Result<DbOverview> {
    ensure_enabled()?;
    with_core(|store, _| store.dev_overview())
}

/// A page of raw rows from one table.
pub fn dev_table(table: String, offset: u32, limit: u32) -> Result<DevTable> {
    ensure_enabled()?;
    with_core(|store, _| store.dev_table(&table, offset, limit))
}

/// Runs one read-only SQL statement (at most 500 rows).
pub fn dev_query(sql: String) -> Result<DevTable> {
    ensure_enabled()?;
    with_core(|store, _| store.dev_query(&sql))
}
