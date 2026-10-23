//! Calendar aggregation over pluggable event sources.
//!
//! Sources:
//! - [`ManualProvider`]: events the user creates in the app.
//! - [`DeviceCalendarProvider`]: events imported from the device's calendars
//!   (Apple Calendar on iPhone and Mac, Google Calendar on Android). The
//!   native side reads them and hands them to `api::device_calendar`, which
//!   caches them in the store; this provider serves that cache.
//!
//! A future ManageBAC iCal feed would be another [`EventProvider`] registered
//! in [`CalendarService::new`]. The UI never needs to know where an event came
//! from beyond `CalendarEvent::{source, editable, calendar_name}`.

use anyhow::Result;
use chrono::{DateTime, Datelike, Duration, Local, NaiveDate, TimeZone, Utc};

use crate::api::types::{CalendarEvent, DaySummary, EventCategory, MonthOverview, WorkloadOutlook};
use crate::store::Store;
use crate::workload;

pub const MANUAL_SOURCE: &str = "manual";
pub const DEVICE_SOURCE: &str = "device";

/// A source of calendar events.
///
/// Providers receive the [`Store`] so that remote providers can keep a local
/// cache (and so the app stays useful offline). They must return events with
/// `source == self.source_id()` and string ids that are stable within that
/// source (e.g. the remote UID).
pub trait EventProvider: Send + Sync {
    /// Stable identifier stored on each event, e.g. `"manual"` or `"managebac-ical"`.
    fn source_id(&self) -> &'static str;

    /// Events overlapping `[start, end)`.
    fn events_between(
        &self,
        store: &Store,
        start: DateTime<Utc>,
        end: DateTime<Utc>,
    ) -> Result<Vec<CalendarEvent>>;

    /// Pull fresh data from the remote source, if any. Local providers do nothing.
    fn refresh(&self, _store: &Store) -> Result<()> {
        Ok(())
    }
}

/// Events created by the user inside BetterBAC.
pub struct ManualProvider;

impl EventProvider for ManualProvider {
    fn source_id(&self) -> &'static str {
        MANUAL_SOURCE
    }

    fn events_between(
        &self,
        store: &Store,
        start: DateTime<Utc>,
        end: DateTime<Utc>,
    ) -> Result<Vec<CalendarEvent>> {
        store.events_between(start, end)
    }
}

/// Events imported from the device's calendars (read-only in BetterBAC).
pub struct DeviceCalendarProvider;

impl EventProvider for DeviceCalendarProvider {
    fn source_id(&self) -> &'static str {
        DEVICE_SOURCE
    }

    fn events_between(
        &self,
        store: &Store,
        start: DateTime<Utc>,
        end: DateTime<Utc>,
    ) -> Result<Vec<CalendarEvent>> {
        store.device_events_between(start, end)
    }
}

/// Best guess at an IB category from an imported event's title, so imported
/// exams and deadlines count towards crunch weeks.
pub fn guess_category(title: &str) -> EventCategory {
    let lower = title.to_lowercase();
    let words: Vec<&str> = lower
        .split(|c: char| !c.is_alphanumeric())
        .filter(|w| !w.is_empty())
        .collect();
    let has_word = |w: &[&str]| words.iter().any(|x| w.contains(x));
    let has = |p: &[&str]| p.iter().any(|x| lower.contains(x));

    if has(&["extended essay"]) || has_word(&["ee"]) {
        EventCategory::ExtendedEssay
    } else if has(&["theory of knowledge"]) || has_word(&["tok"]) {
        EventCategory::Tok
    } else if has(&["internal assessment", "lab report"]) || has_word(&["ia", "ias"]) {
        EventCategory::InternalAssessment
    } else if has_word(&["exam", "exams", "mock", "mocks", "test", "quiz", "paper"]) {
        EventCategory::Exam
    } else if has_word(&["cas", "volunteer", "volunteering"]) {
        EventCategory::Cas
    } else if has_word(&["homework", "hw", "assignment", "due"]) {
        EventCategory::Homework
    } else {
        EventCategory::Other
    }
}

pub struct CalendarService {
    providers: Vec<Box<dyn EventProvider>>,
}

impl Default for CalendarService {
    fn default() -> Self {
        Self::new()
    }
}

impl CalendarService {
    pub fn new() -> Self {
        Self::with_providers(vec![Box::new(ManualProvider), Box::new(DeviceCalendarProvider)])
    }

    pub fn with_providers(providers: Vec<Box<dyn EventProvider>>) -> Self {
        Self { providers }
    }

    /// Merged events from every provider, sorted by start time. A failing
    /// provider is skipped rather than blanking the whole calendar.
    pub fn events_between(
        &self,
        store: &Store,
        start: DateTime<Utc>,
        end: DateTime<Utc>,
    ) -> Vec<CalendarEvent> {
        let mut events: Vec<_> = self
            .providers
            .iter()
            .filter_map(|p| p.events_between(store, start, end).ok())
            .flatten()
            .collect();
        events.sort_by(|a, b| a.starts_at.cmp(&b.starts_at).then_with(|| a.id.cmp(&b.id)));
        events
    }

    pub fn refresh_all(&self, store: &Store) -> Vec<(String, anyhow::Error)> {
        self.providers
            .iter()
            .filter_map(|p| p.refresh(store).err().map(|e| (p.source_id().into(), e)))
            .collect()
    }

    /// Next `limit` incomplete events that haven't finished yet.
    pub fn upcoming(&self, store: &Store, now: DateTime<Utc>, limit: usize) -> Vec<CalendarEvent> {
        self.events_between(store, now, now + Duration::days(60))
            .into_iter()
            .filter(|e| !e.completed)
            .take(limit)
            .collect()
    }

    /// Remaining workload for `weeks` weeks starting with the current one.
    pub fn workload(&self, store: &Store, today: NaiveDate, weeks: u32) -> WorkloadOutlook {
        let first = workload::week_start(today);
        let end = first + Duration::weeks(weeks.into());
        let events = self.events_between(store, local_midnight(first), local_midnight(end));
        workload::outlook(&events, today, weeks)
    }

    pub fn month_overview(&self, store: &Store, year: i32, month: u32) -> Result<MonthOverview> {
        let first = NaiveDate::from_ymd_opt(year, month, 1)
            .ok_or_else(|| anyhow::anyhow!("invalid month {year}-{month}"))?;
        let next = first
            .checked_add_months(chrono::Months::new(1))
            .expect("month in range");
        let events = self.events_between(store, local_midnight(first), local_midnight(next));
        Ok(build_month(first, next, &events))
    }
}

/// Start of `day` in the device's timezone, as UTC.
pub fn local_midnight(day: NaiveDate) -> DateTime<Utc> {
    let naive = day.and_hms_opt(0, 0, 0).expect("midnight exists");
    Local
        .from_local_datetime(&naive)
        .earliest()
        // DST gaps at midnight: fall back to treating it as UTC.
        .map(|t| t.with_timezone(&Utc))
        .unwrap_or_else(|| naive.and_utc())
}

/// The device-local calendar date of `t`.
pub fn local_date(t: DateTime<Utc>) -> NaiveDate {
    t.with_timezone(&Local).date_naive()
}

fn build_month(first: NaiveDate, next: NaiveDate, events: &[CalendarEvent]) -> MonthOverview {
    let mut days: Vec<DaySummary> = first
        .iter_days()
        .take_while(|d| *d < next)
        .map(|d| DaySummary {
            day: d.day(),
            event_count: 0,
            categories: Vec::new(),
        })
        .collect();

    for e in events {
        let start = local_date(e.starts_at).max(first);
        let end = e
            .ends_at
            .map(local_date)
            .unwrap_or(start)
            .min(next.pred_opt().unwrap());
        for d in start.iter_days().take_while(|d| *d <= end) {
            let cell = &mut days[d.day0() as usize];
            cell.event_count += 1;
            if !cell.categories.contains(&e.category) {
                cell.categories.push(e.category);
            }
        }
    }

    MonthOverview {
        year: first.year(),
        month: first.month(),
        leading_blanks: first.weekday().num_days_from_monday(),
        days,
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::api::types::{EventCategory, EventDraft};

    struct FailingProvider;
    impl EventProvider for FailingProvider {
        fn source_id(&self) -> &'static str {
            "broken"
        }
        fn events_between(
            &self,
            _: &Store,
            _: DateTime<Utc>,
            _: DateTime<Utc>,
        ) -> Result<Vec<CalendarEvent>> {
            anyhow::bail!("offline")
        }
    }

    fn draft(title: &str, day: NaiveDate, len_days: i64) -> EventDraft {
        let start = local_midnight(day) + Duration::hours(9);
        EventDraft {
            title: title.into(),
            notes: String::new(),
            category: EventCategory::Cas,
            starts_at: start,
            ends_at: (len_days > 0).then(|| start + Duration::days(len_days)),
            all_day: false,
        }
    }

    #[test]
    fn guesses_categories() {
        use EventCategory::*;
        for (title, want) in [
            ("Math AA paper 2", Exam),
            ("Bio mock exam", Exam),
            ("EE draft due", ExtendedEssay),
            ("Extended Essay meeting", ExtendedEssay),
            ("TOK exhibition", Tok),
            ("Physics IA final", InternalAssessment),
            ("Chem lab report", InternalAssessment),
            ("CAS beach cleanup", Cas),
            ("History homework", Homework),
            ("Dentist", Other),
            ("Meet Lee", Other), // "ee" only as a whole word
        ] {
            assert_eq!(guess_category(title), want, "{title}");
        }
    }

    #[test]
    fn month_overview_spreads_multi_day_events() {
        let store = Store::open_in_memory().unwrap();
        let oct = |d| NaiveDate::from_ymd_opt(2026, 10, d).unwrap();
        let now = Utc::now();
        store
            .create_event(&draft("Single", oct(5), 0), now)
            .unwrap();
        store.create_event(&draft("Trip", oct(30), 4), now).unwrap(); // runs into November

        let svc = CalendarService::with_providers(vec![
            Box::new(ManualProvider),
            Box::new(FailingProvider),
        ]);
        let m = svc.month_overview(&store, 2026, 10).unwrap();
        assert_eq!(m.days.len(), 31);
        assert_eq!(m.leading_blanks, 3); // 1 Oct 2026 is a Thursday
        assert_eq!(m.days[4].event_count, 1);
        assert_eq!(m.days[29].event_count, 1);
        assert_eq!(m.days[30].event_count, 1);
        assert_eq!(m.days[0].event_count, 0);

        let nov = svc.month_overview(&store, 2026, 11).unwrap();
        assert_eq!(nov.days[0].event_count, 1);
        assert_eq!(nov.days[3].event_count, 0);
    }
}
