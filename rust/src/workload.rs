//! Upcoming workload and crunch-week detection. Pure functions only.

use chrono::{Datelike, Duration, NaiveDate};

use crate::api::types::{
    CalendarEvent, CrunchWarning, EventCategory, LoadLevel, WeekLoad, WorkloadOutlook,
};
use crate::calendar::{local_date, local_midnight};

pub const DEFAULT_WEEKS: u32 = 6;

/// How much an event contributes to a week's load.
pub(crate) fn weight(c: EventCategory) -> u32 {
    match c {
        EventCategory::Exam | EventCategory::ExtendedEssay | EventCategory::InternalAssessment => 3,
        EventCategory::Tok => 2,
        EventCategory::Cas | EventCategory::Homework | EventCategory::Other => 1,
    }
}

fn is_major(c: EventCategory) -> bool {
    weight(c) >= 3
}

fn level_for(load: u32, majors: usize) -> LoadLevel {
    if load >= 9 || majors >= 3 {
        LoadLevel::Crunch
    } else if load >= 6 {
        LoadLevel::Heavy
    } else if load >= 3 {
        LoadLevel::Moderate
    } else {
        LoadLevel::Light
    }
}

/// Monday of the week containing `day`.
pub fn week_start(day: NaiveDate) -> NaiveDate {
    day - Duration::days(day.weekday().num_days_from_monday().into())
}

/// Buckets the remaining work in `events` into `weeks` weeks starting with the
/// week containing `today`. Completed and already-past events don't count.
pub fn outlook(events: &[CalendarEvent], today: NaiveDate, weeks: u32) -> WorkloadOutlook {
    let first = week_start(today);
    let mut out: Vec<WeekLoad> = (0..weeks)
        .map(|i| WeekLoad {
            week_start: local_midnight(first + Duration::weeks(i.into())),
            load: 0,
            level: LoadLevel::Light,
            event_count: 0,
            major_titles: Vec::new(),
        })
        .collect();

    for e in events.iter().filter(|e| !e.completed) {
        let day = local_date(e.starts_at);
        if day < today {
            continue;
        }
        let Some(week) = out.get_mut(((day - first).num_days() / 7) as usize) else {
            continue;
        };
        week.load += weight(e.category);
        week.event_count += 1;
        if is_major(e.category) {
            week.major_titles.push(e.title.clone());
        }
    }

    for week in &mut out {
        week.level = level_for(week.load, week.major_titles.len());
    }

    let warning = out
        .iter()
        .enumerate()
        .find(|(_, w)| w.level >= LoadLevel::Heavy)
        .map(|(i, w)| warning_for(i as u32, w));
    WorkloadOutlook {
        weeks: out,
        warning,
    }
}

/// "A", "A and B", "A, B and C".
fn join_titles(titles: &[String]) -> String {
    match titles {
        [] => String::new(),
        [one] => one.clone(),
        [init @ .., last] => format!("{} and {last}", init.join(", ")),
    }
}

fn warning_for(weeks_away: u32, week: &WeekLoad) -> CrunchWarning {
    let crunch = week.level == LoadLevel::Crunch;
    let kind = if crunch { "Crunch week" } else { "Busy week" };
    let title = match weeks_away {
        0 => format!("{kind} now"),
        1 => format!("{kind} next week"),
        n => format!("{kind} in {n} weeks"),
    };

    let what = if week.major_titles.is_empty() {
        format!("{} deadlines", week.event_count)
    } else {
        join_titles(&week.major_titles)
    };
    let first = week.major_titles.first().map_or("one task", String::as_str);
    let message = match weeks_away {
        0 => format!(
            "{what} this week. Break each one into small steps, tick them off as you go, \
             and protect your sleep."
        ),
        1 => format!("{what} next week. Make a start on {first} now so it's not all at once."),
        _ => format!(
            "{what} land in the same week. You have time: start {first} early and spread the work out."
        ),
    };

    CrunchWarning {
        week_start: week.week_start,
        weeks_away,
        level: week.level,
        title,
        message,
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use chrono::Duration;

    // Wednesday 21 Oct 2026; its week starts Monday 19 Oct.
    fn today() -> NaiveDate {
        NaiveDate::from_ymd_opt(2026, 10, 21).unwrap()
    }

    fn event(
        title: &str,
        day: NaiveDate,
        category: EventCategory,
        completed: bool,
    ) -> CalendarEvent {
        CalendarEvent {
            id: title.into(),
            source: "test".into(),
            editable: true,
            title: title.into(),
            notes: String::new(),
            category,
            starts_at: local_midnight(day) + Duration::hours(12),
            ends_at: None,
            all_day: false,
            completed,
            calendar_name: None,
        }
    }

    #[test]
    fn empty_calendar_is_light() {
        let o = outlook(&[], today(), 6);
        assert_eq!(o.weeks.len(), 6);
        assert!(o.weeks.iter().all(|w| w.level == LoadLevel::Light));
        assert!(o.warning.is_none());
        assert_eq!(
            o.weeks[0].week_start,
            local_midnight(NaiveDate::from_ymd_opt(2026, 10, 19).unwrap())
        );
    }

    #[test]
    fn detects_crunch_two_weeks_out() {
        let d = |n| today() + Duration::days(n);
        let events = [
            event("Math exam", d(14), EventCategory::Exam, false),
            event("EE draft", d(15), EventCategory::ExtendedEssay, false),
            event("Bio IA", d(16), EventCategory::InternalAssessment, false),
            event("Homework", d(1), EventCategory::Homework, false),
        ];
        let o = outlook(&events, today(), 6);
        assert_eq!(o.weeks[0].level, LoadLevel::Light);
        assert_eq!(o.weeks[2].level, LoadLevel::Crunch);
        assert_eq!(o.weeks[2].load, 9);
        let w = o.warning.unwrap();
        assert_eq!(w.weeks_away, 2);
        assert_eq!(w.title, "Crunch week in 2 weeks");
        assert!(w.message.starts_with("Math exam, EE draft and Bio IA"));
    }

    #[test]
    fn ignores_completed_past_and_out_of_range() {
        let d = |n| today() + Duration::days(n);
        let events = [
            event("Done exam", d(2), EventCategory::Exam, true),
            event("Monday exam", d(-2), EventCategory::Exam, false), // earlier this week
            event("Far exam", d(60), EventCategory::Exam, false),
            event("Exam", d(2), EventCategory::Exam, false),
            event("IA", d(3), EventCategory::InternalAssessment, false),
        ];
        let o = outlook(&events, today(), 6);
        assert_eq!(o.weeks[0].load, 6);
        assert_eq!(o.weeks[0].level, LoadLevel::Heavy);
        let w = o.warning.unwrap();
        assert_eq!(w.title, "Busy week now");
        assert_eq!(w.weeks_away, 0);
    }

    #[test]
    fn many_small_tasks_still_count() {
        let events: Vec<_> = (0..6)
            .map(|i| {
                event(
                    &format!("HW {i}"),
                    today() + Duration::days(7),
                    EventCategory::Homework,
                    false,
                )
            })
            .collect();
        let o = outlook(&events, today(), 6);
        assert_eq!(o.weeks[1].level, LoadLevel::Heavy);
        assert!(o
            .warning
            .unwrap()
            .message
            .starts_with("6 deadlines next week"));
    }
}
