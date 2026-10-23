//! Reminders: scheduled notifications and the "streak at risk" Live Activity.
//!
//! Everything is local to the device; there is no push server. Rust builds a
//! [`ReminderPlan`] from the current state (streak, deadlines, crunch weeks)
//! and the UI applies it: it cancels all pending notifications, schedules the
//! plan's, and starts, updates or ends the Live Activity. The UI re-applies the
//! plan whenever data changes or the app comes to the foreground, so a
//! reminder that no longer applies (say you saved your streak) disappears
//! automatically.
//!
//! # Adding a rule
//!
//! 1. Make a struct, e.g. `struct WeeklyRecap;`.
//! 2. `impl ScheduleRule for WeeklyRecap` and, in `plan`, call
//!    `p.notify(at, title, body)` and/or `p.live_activity(..)`. Use
//!    `ctx.at(day, hour, minute)` for "local time on that day".
//!    Times in the past are dropped automatically.
//! 3. Add it to `rules()`.

use anyhow::Result;
use chrono::{DateTime, Utc};
use flutter_rust_bridge::frb;

use crate::state::{self, with_core};
use crate::workload;

// ===========================================================================
// Types shared with Dart
// ===========================================================================

/// What the user has switched on. Both default to on.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct ReminderPrefs {
    pub notifications: bool,
    pub live_activity: bool,
}

#[derive(Debug, Clone, PartialEq)]
pub struct PlannedNotification {
    /// Unique within one plan.
    pub id: i32,
    pub fire_at: DateTime<Utc>,
    pub title: String,
    pub body: String,
}

/// Content of the "streak at risk" Live Activity (lock screen + Dynamic Island).
#[derive(Debug, Clone, PartialEq)]
pub struct StreakActivity {
    pub streak: u32,
    pub today_xp: u32,
    pub goal_xp: u32,
    /// When the streak is lost (local midnight); the UI counts down to it.
    pub ends_at: DateTime<Utc>,
    pub title: String,
    pub message: String,
}

#[derive(Debug, Clone, PartialEq)]
pub struct ReminderPlan {
    /// Sorted by time. Empty when notifications are off.
    pub notifications: Vec<PlannedNotification>,
    /// `None` = no activity should be showing (end any running one).
    pub live_activity: Option<StreakActivity>,
}

// ===========================================================================
// API
// ===========================================================================

const PREF_NOTIFICATIONS: &str = "reminders_notifications";
const PREF_LIVE_ACTIVITY: &str = "reminders_live_activity";

pub fn get_reminder_prefs() -> Result<ReminderPrefs> {
    with_core(|store, _| {
        Ok(ReminderPrefs {
            notifications: store.bool_setting(PREF_NOTIFICATIONS, true)?,
            live_activity: store.bool_setting(PREF_LIVE_ACTIVITY, true)?,
        })
    })
}

pub fn set_reminder_prefs(prefs: ReminderPrefs) -> Result<()> {
    let now = state::now();
    with_core(|store, _| {
        store.set_bool_setting(PREF_NOTIFICATIONS, prefs.notifications, now)?;
        store.set_bool_setting(PREF_LIVE_ACTIVITY, prefs.live_activity, now)
    })
}

/// What should be scheduled right now, respecting the user's prefs.
pub fn reminder_plan() -> Result<ReminderPlan> {
    let (now, today) = (state::now(), state::today());
    with_core(|store, calendar| {
        let settings = store.settings()?;
        let streak = crate::progress::streak(&store.active_days()?, today);
        let today_xp = store
            .xp_by_day(today, today)?
            .first()
            .map_or(0, |(_, xp)| *xp);
        let upcoming = calendar
            .events_between(store, now, now + chrono::Duration::days(8))
            .into_iter()
            .filter(|e| !e.completed)
            .collect();
        let crunch = calendar
            .workload(store, today, workload::DEFAULT_WEEKS)
            .warning;

        let ctx = engine::Ctx {
            now,
            today,
            name: settings.display_name,
            streak,
            today_xp,
            goal_xp: settings.daily_goal_xp,
            upcoming,
            crunch,
        };
        let mut plan = engine::build(&ctx);

        let prefs = ReminderPrefs {
            notifications: store.bool_setting(PREF_NOTIFICATIONS, true)?,
            live_activity: store.bool_setting(PREF_LIVE_ACTIVITY, true)?,
        };
        if !prefs.notifications {
            plan.notifications.clear();
        }
        if !prefs.live_activity {
            plan.live_activity = None;
        }
        Ok(plan)
    })
}

// ===========================================================================
// Engine (private: kept out of the Dart bridge)
// ===========================================================================

#[frb(ignore)]
mod engine {
    use super::*;
    use crate::api::types::{CalendarEvent, CrunchWarning, StreakInfo};
    use crate::calendar::{local_date, local_midnight};
    use chrono::{Duration, Local, NaiveDate, Timelike};

    /// iOS keeps at most 64 pending notifications per app; stay well under.
    const MAX_NOTIFICATIONS: usize = 48;

    /// Everything a rule can look at.
    pub(super) struct Ctx {
        pub now: DateTime<Utc>,
        pub today: NaiveDate,
        pub name: String,
        pub streak: StreakInfo,
        pub today_xp: u32,
        pub goal_xp: u32,
        /// Incomplete events in the next 8 days, by start time.
        pub upcoming: Vec<CalendarEvent>,
        pub crunch: Option<CrunchWarning>,
    }

    impl Ctx {
        /// `hour:minute` local time on `day`.
        pub fn at(&self, day: NaiveDate, hour: i64, minute: i64) -> DateTime<Utc> {
            local_midnight(day) + Duration::hours(hour) + Duration::minutes(minute)
        }

        pub fn tomorrow(&self) -> NaiveDate {
            self.today + Duration::days(1)
        }

        /// Hour of the day, local time.
        pub fn local_hour(&self) -> u32 {
            self.now.with_timezone(&Local).hour()
        }

        /// Has a streak going, but no XP yet today.
        pub fn streak_at_risk(&self) -> bool {
            self.streak.current > 0 && !self.streak.active_today
        }

        /// "Noah, " or "" so messages read naturally either way.
        pub fn name_prefix(&self) -> String {
            if self.name.is_empty() {
                String::new()
            } else {
                format!("{}, ", self.name)
            }
        }
    }

    /// Collects what the rules ask for.
    pub(super) struct Planner {
        now: DateTime<Utc>,
        notifications: Vec<(DateTime<Utc>, String, String)>,
        live_activity: Option<StreakActivity>,
    }

    impl Planner {
        /// Schedules a notification. Times in the past (or the next minute)
        /// are ignored, so rules don't need to check.
        pub fn notify(&mut self, at: DateTime<Utc>, title: impl Into<String>, body: impl Into<String>) {
            if at > self.now + Duration::minutes(1) {
                self.notifications.push((at, title.into(), body.into()));
            }
        }

        /// Shows (or updates) the Live Activity. The last rule to call this wins.
        pub fn live_activity(&mut self, activity: StreakActivity) {
            self.live_activity = Some(activity);
        }
    }

    /// A reminder rule: looks at the context and adds to the plan.
    pub(super) trait ScheduleRule {
        fn plan(&self, ctx: &Ctx, p: &mut Planner);
    }

    /// Every rule. Order doesn't matter for notifications (they're sorted by time).
    fn rules() -> Vec<Box<dyn ScheduleRule>> {
        vec![
            Box::new(StreakReminders),
            Box::new(DeadlineReminders),
            Box::new(CrunchWeekHeadsUp),
            Box::new(StreakAtRiskActivity),
        ]
    }

    pub(super) fn build(ctx: &Ctx) -> ReminderPlan {
        let mut p = Planner {
            now: ctx.now,
            notifications: Vec::new(),
            live_activity: None,
        };
        for rule in rules() {
            rule.plan(ctx, &mut p);
        }
        p.notifications.sort_by_key(|(at, ..)| *at);
        p.notifications.truncate(MAX_NOTIFICATIONS);
        ReminderPlan {
            notifications: p
                .notifications
                .into_iter()
                .enumerate()
                .map(|(i, (fire_at, title, body))| PlannedNotification {
                    id: i as i32 + 1,
                    fire_at,
                    title,
                    body,
                })
                .collect(),
            live_activity: p.live_activity,
        }
    }

    // --- Rules -----------------------------------------------------------------

    /// Evening nudges to keep (or start) a streak, today and tomorrow.
    /// Tomorrow's is replaced as soon as the app opens tomorrow, so it only
    /// fires if you haven't been back.
    struct StreakReminders;
    impl ScheduleRule for StreakReminders {
        fn plan(&self, ctx: &Ctx, p: &mut Planner) {
            let n = ctx.streak.current;
            if ctx.streak_at_risk() {
                p.notify(
                    ctx.at(ctx.today, 19, 0),
                    format!("🔥 Your {n}-day streak is on the line"),
                    format!(
                        "{}earn a little XP before midnight to keep it: tick off a deadline or write a few lines.",
                        ctx.name_prefix()
                    ),
                );
                p.notify(
                    ctx.at(ctx.today, 22, 0),
                    "⏰ Last call for your streak",
                    format!("Your {n}-day streak ends at midnight."),
                );
            } else if !ctx.streak.active_today {
                p.notify(
                    ctx.at(ctx.today, 19, 0),
                    "Ready to start a streak?",
                    "Five minutes on a reflection is all it takes.",
                );
            }

            // Tomorrow: the streak survives only if you were active today.
            if ctx.streak.active_today && n > 0 {
                p.notify(
                    ctx.at(ctx.tomorrow(), 19, 0),
                    format!("🔥 Keep your {n}-day streak going"),
                    "A quick reflection or a ticked-off deadline is all it takes.",
                );
            } else {
                p.notify(
                    ctx.at(ctx.tomorrow(), 19, 0),
                    "We miss you!",
                    "Start a new streak today. Five minutes is enough.",
                );
            }
        }
    }

    /// The evening before, the morning of, and an hour before timed events.
    struct DeadlineReminders;
    impl ScheduleRule for DeadlineReminders {
        fn plan(&self, ctx: &Ctx, p: &mut Planner) {
            // Imported events already get reminders from their own calendar app.
            for e in ctx.upcoming.iter().filter(|e| e.editable) {
                let day = local_date(e.starts_at);
                let what = e.category.label();
                let when = if e.all_day {
                    "all day".to_string()
                } else {
                    e.starts_at.with_timezone(&Local).format("%H:%M").to_string()
                };
                p.notify(
                    ctx.at(day - Duration::days(1), 18, 0),
                    format!("📅 Tomorrow: {}", e.title),
                    format!("{what} · {when}. Anything left to prepare?"),
                );
                p.notify(
                    ctx.at(day, 8, 0),
                    format!("Today: {}", e.title),
                    format!("{what} · {when}"),
                );
                if !e.all_day {
                    p.notify(
                        e.starts_at - Duration::hours(1),
                        format!("⏰ In 1 hour: {}", e.title),
                        what,
                    );
                }
            }
        }
    }

    /// A heads-up the evening before a crunch week starts.
    struct CrunchWeekHeadsUp;
    impl ScheduleRule for CrunchWeekHeadsUp {
        fn plan(&self, ctx: &Ctx, p: &mut Planner) {
            let Some(w) = &ctx.crunch else { return };
            if w.weeks_away == 0 {
                return;
            }
            let monday = local_date(w.week_start);
            p.notify(
                ctx.at(monday - Duration::days(1), 17, 0),
                format!("⚠️ {} starts tomorrow", if w.level == crate::api::types::LoadLevel::Crunch { "Crunch week" } else { "A busy week" }),
                w.message.clone(),
            );
        }
    }

    /// From 4 pm, a lock-screen countdown to midnight while the streak is at risk.
    struct StreakAtRiskActivity;
    impl ScheduleRule for StreakAtRiskActivity {
        fn plan(&self, ctx: &Ctx, p: &mut Planner) {
            if !ctx.streak_at_risk() || ctx.local_hour() < 16 {
                return;
            }
            let n = ctx.streak.current;
            p.live_activity(StreakActivity {
                streak: n,
                today_xp: ctx.today_xp,
                goal_xp: ctx.goal_xp,
                ends_at: ctx.at(ctx.tomorrow(), 0, 0),
                title: format!("{n}-day streak at risk"),
                message: "Earn XP before midnight to keep it!".into(),
            });
        }
    }

    #[cfg(test)]
    mod tests {
        use super::*;
        use crate::api::types::{EventCategory, LoadLevel};

        fn today() -> NaiveDate {
            NaiveDate::from_ymd_opt(2026, 10, 21).unwrap()
        }

        fn ctx(hour: i64, current: u32, active_today: bool) -> Ctx {
            Ctx {
                now: local_midnight(today()) + Duration::hours(hour),
                today: today(),
                name: "Noah".into(),
                streak: StreakInfo { current, best: current, active_today },
                today_xp: if active_today { 10 } else { 0 },
                goal_xp: 20,
                upcoming: vec![],
                crunch: None,
            }
        }

        fn titles(plan: &ReminderPlan) -> Vec<&str> {
            plan.notifications.iter().map(|n| n.title.as_str()).collect()
        }

        #[test]
        fn streak_at_risk_in_the_evening() {
            let plan = build(&ctx(17, 5, false));
            let t = titles(&plan);
            assert!(t.contains(&"🔥 Your 5-day streak is on the line"));
            assert!(t.contains(&"⏰ Last call for your streak"));
            assert!(t.contains(&"We miss you!"));
            let live = plan.live_activity.expect("activity after 4 pm");
            assert_eq!(live.streak, 5);
            assert_eq!(live.ends_at, local_midnight(today() + Duration::days(1)));
            // Sorted, unique ids.
            assert!(plan.notifications.windows(2).all(|w| w[0].fire_at <= w[1].fire_at));
            assert_eq!(plan.notifications[0].id, 1);
        }

        #[test]
        fn no_activity_before_four_or_when_safe() {
            assert!(build(&ctx(10, 5, false)).live_activity.is_none());
            let safe = build(&ctx(17, 5, true));
            assert!(safe.live_activity.is_none());
            assert_eq!(titles(&safe), ["🔥 Keep your 5-day streak going"]);
        }

        #[test]
        fn past_times_are_dropped() {
            // 23:00: tonight's 19:00 and 22:00 reminders have passed.
            let plan = build(&ctx(23, 5, false));
            assert_eq!(titles(&plan), ["We miss you!"]);
        }

        #[test]
        fn deadlines_and_crunch() {
            let mut c = ctx(9, 0, true);
            let due = today() + Duration::days(2);
            c.upcoming.push(CalendarEvent {
                id: "e1".into(),
                source: "manual".into(),
                editable: true,
                title: "EE draft".into(),
                notes: String::new(),
                category: EventCategory::ExtendedEssay,
                starts_at: local_midnight(due) + Duration::hours(15),
                ends_at: None,
                all_day: false,
                completed: false,
                calendar_name: None,
            });
            c.crunch = Some(CrunchWarning {
                week_start: local_midnight(NaiveDate::from_ymd_opt(2026, 11, 2).unwrap()),
                weeks_away: 2,
                level: LoadLevel::Crunch,
                title: "Crunch week in 2 weeks".into(),
                message: "Start early.".into(),
            });
            let plan = build(&c);
            let t = titles(&plan);
            assert!(t.contains(&"📅 Tomorrow: EE draft"));
            assert!(t.contains(&"Today: EE draft"));
            assert!(t.contains(&"⏰ In 1 hour: EE draft"));
            let crunch = plan
                .notifications
                .iter()
                .find(|n| n.title == "⚠️ Crunch week starts tomorrow")
                .unwrap();
            assert_eq!(
                crunch.fire_at,
                local_midnight(NaiveDate::from_ymd_opt(2026, 11, 1).unwrap()) + Duration::hours(17)
            );
        }

        #[test]
        fn capped() {
            let mut c = ctx(9, 0, true);
            for i in 0..40 {
                c.upcoming.push(CalendarEvent {
                    id: format!("e{i}"),
                    source: "manual".into(),
                    editable: true,
                    title: format!("Task {i}"),
                    notes: String::new(),
                    category: EventCategory::Homework,
                    starts_at: local_midnight(today() + Duration::days(3)) + Duration::hours(12),
                    ends_at: None,
                    all_day: false,
                    completed: false,
                    calendar_name: None,
                });
            }
            assert_eq!(build(&c).notifications.len(), MAX_NOTIFICATIONS);
        }
    }
}
