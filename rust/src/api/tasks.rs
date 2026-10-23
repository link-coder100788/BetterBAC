//! "Most pressing task": the one thing to do next, shown on Home and
//! exportable to Apple Reminders (iPhone and Mac).
//!
//! Ranking: incomplete deadlines in the next [`HORIZON_DAYS`] days, scored by
//! urgency = hours until due ÷ importance (exams, EE and IA weigh 3, TOK 2,
//! the rest 1), lowest first. So an exam in 3 days beats homework in 2.
//! Imported calendar events count only if they look like schoolwork (not
//! `Other`). With no deadlines, the oldest unsent reflection draft is next.

use anyhow::Result;
use chrono::{DateTime, Utc};

use super::types::{CalendarEvent, EventCategory, Reflection};
use crate::state::{self, with_core};

/// Something to do, with everything needed to put it in Reminders.
#[derive(Debug, Clone, PartialEq)]
pub struct PressingTask {
    /// Stable key, e.g. `event:<id>` or `draft:<id>`.
    pub key: String,
    pub title: String,
    /// Short "why this one", e.g. "Exam · tomorrow".
    pub reason: String,
    pub notes: String,
    pub due_at: Option<DateTime<Utc>>,
    pub all_day: bool,
    /// When a reminder should alert (the evening before, if still ahead).
    pub remind_at: Option<DateTime<Utc>>,
    /// Already exported to Apple Reminders from this device.
    pub already_added: bool,
}

const HORIZON_DAYS: i64 = 14;
const PREF_ADDED: &str = "apple_reminders_added";
const MAX_REMEMBERED: usize = 100;

pub fn most_pressing_task() -> Result<Option<PressingTask>> {
    let now = state::now();
    with_core(|store, calendar| pressing_task_in(store, calendar, now))
}

/// For callers already holding the store (e.g. the dashboard).
pub(crate) fn pressing_task_in(
    store: &crate::store::Store,
    calendar: &crate::calendar::CalendarService,
    now: DateTime<Utc>,
) -> Result<Option<PressingTask>> {
    {
        let events = calendar
            .events_between(store, now, now + chrono::Duration::days(HORIZON_DAYS))
            .into_iter()
            .filter(|e| !e.completed)
            .collect::<Vec<_>>();
        let drafts = store
            .list_reflections(None)?
            .into_iter()
            .filter(|r| r.exported_at.is_none())
            .collect::<Vec<_>>();
        let added = added_keys(store)?;
        Ok(engine::pick(now, &events, &drafts).map(|mut t| {
            t.already_added = added.contains(&t.key);
            t
        }))
    }
}

/// Remembers that `key` was added to Apple Reminders, so the button can say so.
pub fn mark_added_to_reminders(key: String) -> Result<()> {
    let now = state::now();
    with_core(|store, _| {
        let mut keys = added_keys(store)?;
        keys.retain(|k| *k != key);
        keys.push(key);
        let start = keys.len().saturating_sub(MAX_REMEMBERED);
        store.set_string_setting(PREF_ADDED, &keys[start..].join("\n"), now)
    })
}

fn added_keys(store: &crate::store::Store) -> Result<Vec<String>> {
    Ok(store
        .string_setting(PREF_ADDED)?
        .map(|s| s.lines().filter(|l| !l.is_empty()).map(String::from).collect())
        .unwrap_or_default())
}

#[flutter_rust_bridge::frb(ignore)]
mod engine {
    use super::*;
    use crate::calendar::{local_date, local_midnight};
    use crate::workload;
    use chrono::{Duration, Local};

    pub(super) fn pick(
        now: DateTime<Utc>,
        events: &[CalendarEvent],
        drafts: &[Reflection],
    ) -> Option<PressingTask> {
        let urgency = |e: &CalendarEvent| {
            let hours = (e.starts_at - now).num_minutes().max(60) as f64 / 60.0;
            hours / workload::weight(e.category) as f64
        };
        let best = events
            .iter()
            .filter(|e| e.editable || e.category != EventCategory::Other)
            .filter(|e| e.starts_at > now)
            .min_by(|a, b| urgency(a).total_cmp(&urgency(b)));
        if let Some(e) = best {
            return Some(from_event(now, e));
        }
        drafts
            .iter()
            .min_by_key(|r| r.updated_at)
            .map(|r| PressingTask {
                key: format!("draft:{}", r.id),
                title: format!("Finish & send \"{}\"", r.title),
                reason: "Reflection draft not yet sent to ManageBAC".into(),
                notes: "Open BetterBAC, finish the reflection, then tap Copy & open ManageBAC.".into(),
                due_at: None,
                all_day: false,
                remind_at: None,
                already_added: false,
            })
    }

    fn from_event(now: DateTime<Utc>, e: &CalendarEvent) -> PressingTask {
        let today = now.with_timezone(&Local).date_naive();
        let day = local_date(e.starts_at);
        let when = match (day - today).num_days() {
            0 if e.all_day => "today".to_string(),
            0 => format!("today at {}", e.starts_at.with_timezone(&Local).format("%H:%M")),
            1 => "tomorrow".to_string(),
            n => format!("in {n} days"),
        };
        // The evening before, so there's still time to act.
        let evening_before = local_midnight(day) - Duration::hours(6);
        PressingTask {
            key: format!("event:{}", e.id),
            title: e.title.clone(),
            reason: format!("{} · {when}", e.category.label()),
            notes: if e.notes.is_empty() {
                format!("{} from BetterBAC", e.category.label())
            } else {
                e.notes.clone()
            },
            due_at: Some(e.starts_at),
            all_day: e.all_day,
            remind_at: (evening_before > now).then_some(evening_before),
            already_added: false,
        }
    }

    #[cfg(test)]
    mod tests {
        use super::*;

        fn now() -> DateTime<Utc> {
            local_midnight(chrono::NaiveDate::from_ymd_opt(2026, 10, 21).unwrap())
                + Duration::hours(9)
        }

        fn ev(title: &str, cat: EventCategory, hours: i64, editable: bool) -> CalendarEvent {
            CalendarEvent {
                id: title.into(),
                source: if editable { "manual" } else { "device" }.into(),
                editable,
                title: title.into(),
                notes: String::new(),
                category: cat,
                starts_at: now() + Duration::hours(hours),
                ends_at: None,
                all_day: false,
                completed: false,
                calendar_name: None,
            }
        }

        #[test]
        fn important_beats_merely_soon() {
            let events = [
                ev("Homework", EventCategory::Homework, 48, true),
                ev("Math exam", EventCategory::Exam, 72, true),
            ];
            let t = pick(now(), &events, &[]).unwrap();
            assert_eq!(t.title, "Math exam");
            assert_eq!(t.key, "event:Math exam");
            assert_eq!(t.reason, "Exam · in 3 days");
            // Reminder the evening before (18:00 the day before).
            let day = local_date(t.due_at.unwrap());
            assert_eq!(t.remind_at, Some(local_midnight(day) - Duration::hours(6)));
        }

        #[test]
        fn skips_non_school_imports_and_falls_back_to_drafts() {
            let events = [ev("Dentist", EventCategory::Other, 2, false)];
            assert!(pick(now(), &events, &[]).is_none());

            let draft = Reflection {
                id: "r1".into(),
                experience_id: None,
                experience_title: None,
                title: "Concert nerves".into(),
                body: String::new(),
                outcomes: vec![],
                word_count: 0,
                created_at: now(),
                updated_at: now(),
                exported_at: None,
            };
            let t = pick(now(), &events, &[draft]).unwrap();
            assert_eq!(t.key, "draft:r1");
            assert!(t.title.contains("Concert nerves"));
            assert!(t.due_at.is_none());
        }

        #[test]
        fn imported_exams_count_and_soon_reminders_are_skipped() {
            let events = [ev("Bio mock exam", EventCategory::Exam, 3, false)];
            let t = pick(now(), &events, &[]).unwrap();
            assert_eq!(t.title, "Bio mock exam");
            assert_eq!(t.reason, format!("Exam · today at {}", (now() + Duration::hours(3)).with_timezone(&Local).format("%H:%M")));
            // The evening before has already passed.
            assert_eq!(t.remind_at, None);
        }
    }
}
