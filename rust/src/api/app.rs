use anyhow::Result;
use chrono::{Datelike, Duration};
use flutter_rust_bridge::frb;

use super::types::{
    Achievement, Dashboard, DayActivity, LearningOutcome, OutcomeCoverage, Strand, StrandCount,
};
use crate::calendar::local_midnight;
use crate::progress;
use crate::state::{self, with_core};
use crate::workload;

#[frb(init)]
pub fn init_app() {
    flutter_rust_bridge::setup_default_user_utils();
}

/// Opens (creating if needed) the database at `db_path`. Call once at startup.
pub fn init_core(db_path: String) -> Result<()> {
    state::init(&db_path)
}

pub fn get_dashboard() -> Result<Dashboard> {
    let now = state::now();
    let today = state::today();
    with_core(|store, calendar| {
        let settings = store.settings()?;
        let stats = store.stats()?;
        let total_xp = store.total_xp()?;
        let streak = progress::streak(&store.active_days()?, today);

        let week_start = today - Duration::days(6);
        let xp_by_day = store.xp_by_day(week_start, today)?;
        let week = week_start
            .iter_days()
            .take(7)
            .map(|day| DayActivity {
                date: local_midnight(day),
                weekday_label: day.weekday().to_string()[..1].into(),
                xp: xp_by_day
                    .iter()
                    .find(|(d, _)| *d == day)
                    .map_or(0, |(_, xp)| *xp),
                is_today: day == today,
            })
            .collect::<Vec<_>>();
        let today_xp = week.last().map_or(0, |d| d.xp);

        Ok(Dashboard {
            display_name: settings.display_name,
            total_xp,
            today_xp,
            daily_goal_xp: settings.daily_goal_xp,
            level: progress::level_for_xp(total_xp),
            streak,
            week,
            strand_balance: Strand::ALL
                .into_iter()
                .map(|strand| StrandCount {
                    strand,
                    experiences: stats.strand(strand),
                })
                .collect(),
            outcome_coverage: LearningOutcome::ALL
                .into_iter()
                .map(|outcome| OutcomeCoverage {
                    outcome,
                    reflections: stats.outcome(outcome),
                })
                .collect(),
            upcoming: calendar.upcoming(store, now, 5),
            crunch: calendar
                .workload(store, today, workload::DEFAULT_WEEKS)
                .warning,
            draft_count: stats.reflection_drafts,
            pressing_task: super::tasks::pressing_task_in(store, calendar, now)?,
        })
    })
}

pub fn get_achievements() -> Result<Vec<Achievement>> {
    let today = state::today();
    with_core(|store, _| {
        let best = progress::streak(&store.active_days()?, today).best;
        Ok(progress::achievements(&store.stats()?, best))
    })
}
