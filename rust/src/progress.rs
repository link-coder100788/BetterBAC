//! XP, levels, streaks and achievements. Pure functions only — no storage.

use chrono::NaiveDate;

use crate::api::types::{Achievement, LearningOutcome, LevelInfo, Strand, StreakInfo};
use crate::store::Stats;

// ---------------------------------------------------------------------------
// XP rules
// ---------------------------------------------------------------------------

pub const XP_EXPERIENCE_CREATED: u32 = 15;
pub const XP_EVENT_COMPLETED: u32 = 5;
/// Awarded at most once per reflection per day for writing at least
/// [`DRAFT_MIN_WORDS`] words, so daily writing keeps the streak alive.
pub const XP_DRAFT_SESSION: u32 = 5;
pub const DRAFT_MIN_WORDS: u32 = 30;

/// XP for handing a finished reflection to ManageBAC: a flat 20 plus one
/// point per 20 words, capped so essays don't dwarf everything else.
pub fn reflection_export_xp(words: u32) -> u32 {
    20 + (words / 20).min(30)
}

// XP keys. Every key for an entity shares the `<kind>:<id>:` prefix so it can
// be revoked when the entity is deleted.
pub fn experience_key(id: &str) -> String {
    format!("experience:{id}:created")
}
pub fn experience_prefix(id: &str) -> String {
    format!("experience:{id}:")
}
pub fn reflection_export_key(id: &str) -> String {
    format!("reflection:{id}:exported")
}
pub fn reflection_draft_key(id: &str, day: NaiveDate) -> String {
    format!("reflection:{id}:draft:{day}")
}
pub fn reflection_prefix(id: &str) -> String {
    format!("reflection:{id}:")
}
pub fn event_key(id: &str) -> String {
    format!("event:{id}:completed")
}
pub fn event_prefix(id: &str) -> String {
    format!("event:{id}:")
}

// ---------------------------------------------------------------------------
// Levels
// ---------------------------------------------------------------------------

/// XP needed to go from `level` to `level + 1`: 100, 150, 200, ...
fn xp_to_advance(level: u32) -> u32 {
    50 + 50 * level
}

pub fn level_for_xp(total: u32) -> LevelInfo {
    let mut level = 1;
    let mut remaining = total;
    while remaining >= xp_to_advance(level) {
        remaining -= xp_to_advance(level);
        level += 1;
    }
    LevelInfo {
        level,
        xp_into_level: remaining,
        xp_for_next_level: xp_to_advance(level),
    }
}

// ---------------------------------------------------------------------------
// Streaks
// ---------------------------------------------------------------------------

/// `active_days` must be sorted ascending and deduplicated. Like Duolingo, a
/// streak survives until the end of the day after the last active day.
pub fn streak(active_days: &[NaiveDate], today: NaiveDate) -> StreakInfo {
    let mut best = 0;
    let mut run = 0;
    let mut prev: Option<NaiveDate> = None;
    for &day in active_days.iter().filter(|d| **d <= today) {
        run = match prev {
            Some(p) if p.succ_opt() == Some(day) => run + 1,
            _ => 1,
        };
        best = best.max(run);
        prev = Some(day);
    }

    let active_today = prev == Some(today);
    let alive = active_today || prev.is_some_and(|p| p.succ_opt() == Some(today));
    StreakInfo {
        current: if alive { run } else { 0 },
        best,
        active_today,
    }
}

// ---------------------------------------------------------------------------
// Achievements
// ---------------------------------------------------------------------------

pub fn achievements(stats: &Stats, best_streak: u32) -> Vec<Achievement> {
    let strands_covered = Strand::ALL.iter().filter(|s| stats.strand(**s) > 0).count() as u32;
    let outcomes_covered = LearningOutcome::ALL
        .iter()
        .filter(|o| stats.outcome(**o) > 0)
        .count() as u32;

    let defs: [(&str, &str, &str, &str, u32, u32); 10] = [
        (
            "first_reflection",
            "First Words",
            "Send your first reflection to ManageBAC",
            "edit_note",
            stats.reflections_exported,
            1,
        ),
        (
            "reflections_10",
            "Deep Thinker",
            "Send 10 reflections to ManageBAC",
            "psychology",
            stats.reflections_exported,
            10,
        ),
        (
            "wordsmith",
            "Wordsmith",
            "Reflect with 5,000 words in total",
            "menu_book",
            stats.words_exported,
            5000,
        ),
        (
            "streak_7",
            "On Fire",
            "Reach a 7-day streak",
            "local_fire_department",
            best_streak,
            7,
        ),
        (
            "streak_30",
            "Unstoppable",
            "Reach a 30-day streak",
            "whatshot",
            best_streak,
            30,
        ),
        (
            "first_experience",
            "Getting Started",
            "Log your first CAS experience",
            "flag",
            stats.experiences,
            1,
        ),
        (
            "all_strands",
            "Triple Threat",
            "Log experiences in all three strands",
            "category",
            strands_covered,
            3,
        ),
        (
            "all_outcomes",
            "Full Spectrum",
            "Evidence all 7 learning outcomes",
            "verified",
            outcomes_covered,
            7,
        ),
        (
            "cas_project",
            "Project Leader",
            "Start a CAS project",
            "groups",
            stats.projects,
            1,
        ),
        (
            "planner",
            "Planner",
            "Complete 10 calendar events",
            "event_available",
            stats.events_completed,
            10,
        ),
    ];

    defs.into_iter()
        .map(
            |(id, title, description, icon, progress, goal)| Achievement {
                id: id.into(),
                title: title.into(),
                description: description.into(),
                icon: icon.into(),
                progress: progress.min(goal),
                goal,
                unlocked: progress >= goal,
            },
        )
        .collect()
}

// ---------------------------------------------------------------------------
// Writing prompts
// ---------------------------------------------------------------------------

/// Guiding questions for a reflection, tailored to the outcomes being evidenced.
pub fn reflection_prompts(outcomes: &[LearningOutcome]) -> Vec<String> {
    let mut prompts: Vec<&str> = vec![
        "What did you do, and why did you choose to do it?",
        "How did you feel before, during and after?",
    ];
    for o in outcomes {
        prompts.push(match o {
            LearningOutcome::Awareness => {
                "What strength did you rely on, and what would you like to get better at?"
            }
            LearningOutcome::Challenge => {
                "What was new or difficult, and what skill did you develop to handle it?"
            }
            LearningOutcome::Initiative => {
                "How did you plan this? What would you plan differently next time?"
            }
            LearningOutcome::Commitment => {
                "When did you feel like giving up, and what kept you going?"
            }
            LearningOutcome::Collaboration => "How did working with others change the outcome?",
            LearningOutcome::GlobalEngagement => {
                "How does this connect to an issue beyond your school or community?"
            }
            LearningOutcome::Ethics => {
                "What choices did you face, and how did you decide what was right?"
            }
        });
    }
    prompts.push("What will you do differently next time?");
    prompts.into_iter().map(String::from).collect()
}

#[cfg(test)]
mod tests {
    use super::*;

    fn d(day: u32) -> NaiveDate {
        NaiveDate::from_ymd_opt(2026, 10, day).unwrap()
    }

    #[test]
    fn levels() {
        assert_eq!(level_for_xp(0).level, 1);
        assert_eq!(level_for_xp(99).level, 1);
        let l = level_for_xp(100);
        assert_eq!((l.level, l.xp_into_level, l.xp_for_next_level), (2, 0, 150));
        assert_eq!(level_for_xp(250).level, 3);
    }

    #[test]
    fn streak_alive_through_next_day() {
        let days = [d(1), d(3), d(4), d(5)];
        let s = streak(&days, d(5));
        assert_eq!((s.current, s.best, s.active_today), (3, 3, true));
        let s = streak(&days, d(6));
        assert_eq!((s.current, s.active_today), (3, false));
        let s = streak(&days, d(7));
        assert_eq!((s.current, s.best), (0, 3));
    }

    #[test]
    fn streak_empty() {
        let s = streak(&[], d(1));
        assert_eq!((s.current, s.best, s.active_today), (0, 0, false));
    }

    #[test]
    fn export_xp_is_capped() {
        assert_eq!(reflection_export_xp(0), 20);
        assert_eq!(reflection_export_xp(200), 30);
        assert_eq!(reflection_export_xp(100_000), 50);
    }

    #[test]
    fn achievements_unlock() {
        let mut stats = Stats::default();
        stats.strand_experiences = [1, 2, 1];
        let a = achievements(&stats, 8);
        let get = |id: &str| a.iter().find(|x| x.id == id).unwrap().clone();
        assert!(get("all_strands").unlocked);
        assert!(get("streak_7").unlocked);
        let s30 = get("streak_30");
        assert!(!s30.unlocked);
        assert_eq!(s30.progress, 8);
    }
}
