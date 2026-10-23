//! Plain data types shared with Dart. Everything `pub` in this file is
//! mirrored into `lib/src/rust/api/types.dart` by flutter_rust_bridge.

use chrono::{DateTime, Utc};
use flutter_rust_bridge::frb;

// ---------------------------------------------------------------------------
// CAS
// ---------------------------------------------------------------------------

#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub enum Strand {
    Creativity,
    Activity,
    Service,
}

impl Strand {
    pub(crate) const ALL: [Strand; 3] = [Strand::Creativity, Strand::Activity, Strand::Service];

    #[frb(sync)]
    pub fn label(&self) -> String {
        match self {
            Strand::Creativity => "Creativity",
            Strand::Activity => "Activity",
            Strand::Service => "Service",
        }
        .into()
    }
}

/// The seven IB CAS learning outcomes. Every one must be evidenced at least
/// once before CAS can be completed.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub enum LearningOutcome {
    Awareness,
    Challenge,
    Initiative,
    Commitment,
    Collaboration,
    GlobalEngagement,
    Ethics,
}

impl LearningOutcome {
    pub(crate) const ALL: [LearningOutcome; 7] = [
        LearningOutcome::Awareness,
        LearningOutcome::Challenge,
        LearningOutcome::Initiative,
        LearningOutcome::Commitment,
        LearningOutcome::Collaboration,
        LearningOutcome::GlobalEngagement,
        LearningOutcome::Ethics,
    ];

    /// 1-based number as used by the IB ("LO3").
    #[frb(sync)]
    pub fn number(&self) -> u8 {
        *self as u8 + 1
    }

    #[frb(sync)]
    pub fn short_name(&self) -> String {
        match self {
            LearningOutcome::Awareness => "Strengths & growth",
            LearningOutcome::Challenge => "New challenges",
            LearningOutcome::Initiative => "Initiative & planning",
            LearningOutcome::Commitment => "Commitment",
            LearningOutcome::Collaboration => "Collaboration",
            LearningOutcome::GlobalEngagement => "Global engagement",
            LearningOutcome::Ethics => "Ethics",
        }
        .into()
    }

    #[frb(sync)]
    pub fn description(&self) -> String {
        match self {
            LearningOutcome::Awareness => {
                "Identify own strengths and develop areas for growth"
            }
            LearningOutcome::Challenge => {
                "Demonstrate that challenges have been undertaken, developing new skills in the process"
            }
            LearningOutcome::Initiative => "Demonstrate how to initiate and plan a CAS experience",
            LearningOutcome::Commitment => {
                "Show commitment to and perseverance in CAS experiences"
            }
            LearningOutcome::Collaboration => {
                "Demonstrate the skills and recognize the benefits of working collaboratively"
            }
            LearningOutcome::GlobalEngagement => {
                "Demonstrate engagement with issues of global significance"
            }
            LearningOutcome::Ethics => "Recognize and consider the ethics of choices and actions",
        }
        .into()
    }
}

#[derive(Debug, Clone)]
pub struct Experience {
    pub id: String,
    pub title: String,
    pub description: String,
    pub strands: Vec<Strand>,
    pub is_project: bool,
    pub start_date: Option<DateTime<Utc>>,
    pub end_date: Option<DateTime<Utc>>,
    pub created_at: DateTime<Utc>,
    pub reflection_count: u32,
}

/// User-editable fields of an [`Experience`].
#[derive(Debug, Clone)]
pub struct ExperienceDraft {
    pub title: String,
    pub description: String,
    pub strands: Vec<Strand>,
    pub is_project: bool,
    pub start_date: Option<DateTime<Utc>>,
    pub end_date: Option<DateTime<Utc>>,
}

#[derive(Debug, Clone)]
pub struct Reflection {
    pub id: String,
    pub experience_id: Option<String>,
    pub experience_title: Option<String>,
    pub title: String,
    pub body: String,
    pub outcomes: Vec<LearningOutcome>,
    pub word_count: u32,
    pub created_at: DateTime<Utc>,
    pub updated_at: DateTime<Utc>,
    /// Set once the reflection has been copied over to ManageBAC.
    pub exported_at: Option<DateTime<Utc>>,
}

/// User-editable fields of a [`Reflection`].
#[derive(Debug, Clone)]
pub struct ReflectionDraft {
    pub experience_id: Option<String>,
    pub title: String,
    pub body: String,
    pub outcomes: Vec<LearningOutcome>,
}

#[derive(Debug, Clone)]
pub struct ExperienceSaved {
    pub experience: Experience,
    pub xp_gained: u32,
}

#[derive(Debug, Clone)]
pub struct ReflectionSaved {
    pub reflection: Reflection,
    pub xp_gained: u32,
}

/// Everything the UI needs to hand a reflection over to ManageBAC.
#[derive(Debug, Clone)]
pub struct ManageBacExport {
    /// Text to put on the clipboard.
    pub text: String,
    /// The user's ManageBAC CAS page, if configured.
    pub url: Option<String>,
    pub xp_gained: u32,
}

// ---------------------------------------------------------------------------
// Calendar
// ---------------------------------------------------------------------------

#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub enum EventCategory {
    Cas,
    ExtendedEssay,
    Tok,
    InternalAssessment,
    Exam,
    Homework,
    Other,
}

impl EventCategory {
    pub(crate) const ALL: [EventCategory; 7] = [
        EventCategory::Cas,
        EventCategory::ExtendedEssay,
        EventCategory::Tok,
        EventCategory::InternalAssessment,
        EventCategory::Exam,
        EventCategory::Homework,
        EventCategory::Other,
    ];

    #[frb(sync)]
    pub fn label(&self) -> String {
        match self {
            EventCategory::Cas => "CAS",
            EventCategory::ExtendedEssay => "Extended Essay",
            EventCategory::Tok => "TOK",
            EventCategory::InternalAssessment => "IA",
            EventCategory::Exam => "Exam",
            EventCategory::Homework => "Homework",
            EventCategory::Other => "Other",
        }
        .into()
    }
}

#[derive(Debug, Clone)]
pub struct CalendarEvent {
    /// Unique within `source`. Manual events use UUIDs.
    pub id: String,
    /// Which [`crate::calendar::EventProvider`] produced this event.
    pub source: String,
    /// Whether the user may edit / delete / complete this event.
    pub editable: bool,
    pub title: String,
    pub notes: String,
    pub category: EventCategory,
    pub starts_at: DateTime<Utc>,
    pub ends_at: Option<DateTime<Utc>>,
    pub all_day: bool,
    pub completed: bool,
    /// For imported events: the calendar it came from (e.g. "Work").
    pub calendar_name: Option<String>,
}

/// User-editable fields of a manual [`CalendarEvent`].
#[derive(Debug, Clone)]
pub struct EventDraft {
    pub title: String,
    pub notes: String,
    pub category: EventCategory,
    pub starts_at: DateTime<Utc>,
    pub ends_at: Option<DateTime<Utc>>,
    pub all_day: bool,
}

#[derive(Debug, Clone)]
pub struct DaySummary {
    /// Day of month, 1-based.
    pub day: u32,
    pub event_count: u32,
    pub categories: Vec<EventCategory>,
}

/// Layout + per-day summary for a month grid.
#[derive(Debug, Clone)]
pub struct MonthOverview {
    pub year: i32,
    pub month: u32,
    /// Number of blank cells before day 1 in a Monday-first grid.
    pub leading_blanks: u32,
    pub days: Vec<DaySummary>,
}

// ---------------------------------------------------------------------------
// Workload / crunch weeks
// ---------------------------------------------------------------------------

#[derive(Debug, Clone, Copy, PartialEq, Eq, PartialOrd, Ord)]
pub enum LoadLevel {
    Light,
    Moderate,
    Heavy,
    Crunch,
}

impl LoadLevel {
    #[frb(sync)]
    pub fn label(&self) -> String {
        match self {
            LoadLevel::Light => "Light",
            LoadLevel::Moderate => "Moderate",
            LoadLevel::Heavy => "Heavy",
            LoadLevel::Crunch => "Crunch",
        }
        .into()
    }
}

/// Remaining (incomplete, not yet past) workload for one Monday-to-Sunday week.
#[derive(Debug, Clone)]
pub struct WeekLoad {
    /// Local midnight of the week's Monday.
    pub week_start: DateTime<Utc>,
    /// Weighted score: exams, EE and IA count 3, TOK 2, everything else 1.
    pub load: u32,
    pub level: LoadLevel,
    pub event_count: u32,
    /// Titles of the big deadlines (exams, EE, IA) that week.
    pub major_titles: Vec<String>,
}

#[derive(Debug, Clone)]
pub struct CrunchWarning {
    pub week_start: DateTime<Utc>,
    /// 0 = this week, 1 = next week, ...
    pub weeks_away: u32,
    pub level: LoadLevel,
    pub title: String,
    pub message: String,
}

#[derive(Debug, Clone)]
pub struct WorkloadOutlook {
    /// Starting with the current week.
    pub weeks: Vec<WeekLoad>,
    /// The first Heavy or Crunch week ahead, if any.
    pub warning: Option<CrunchWarning>,
}

// ---------------------------------------------------------------------------
// Progress / gamification
// ---------------------------------------------------------------------------

#[derive(Debug, Clone)]
pub struct LevelInfo {
    pub level: u32,
    pub xp_into_level: u32,
    pub xp_for_next_level: u32,
}

#[derive(Debug, Clone)]
pub struct StreakInfo {
    pub current: u32,
    pub best: u32,
    pub active_today: bool,
}

#[derive(Debug, Clone)]
pub struct DayActivity {
    pub date: DateTime<Utc>,
    /// Single-letter weekday label, e.g. "M".
    pub weekday_label: String,
    pub xp: u32,
    pub is_today: bool,
}

#[derive(Debug, Clone)]
pub struct StrandCount {
    pub strand: Strand,
    pub experiences: u32,
}

#[derive(Debug, Clone)]
pub struct OutcomeCoverage {
    pub outcome: LearningOutcome,
    /// Number of reflections evidencing this outcome.
    pub reflections: u32,
}

#[derive(Debug, Clone)]
pub struct Achievement {
    pub id: String,
    pub title: String,
    pub description: String,
    /// Material icon name hint for the UI.
    pub icon: String,
    pub progress: u32,
    pub goal: u32,
    pub unlocked: bool,
}

#[derive(Debug, Clone)]
pub struct Dashboard {
    pub display_name: String,
    pub total_xp: u32,
    pub today_xp: u32,
    pub daily_goal_xp: u32,
    pub level: LevelInfo,
    pub streak: StreakInfo,
    pub week: Vec<DayActivity>,
    pub strand_balance: Vec<StrandCount>,
    pub outcome_coverage: Vec<OutcomeCoverage>,
    pub upcoming: Vec<CalendarEvent>,
    pub crunch: Option<CrunchWarning>,
    pub draft_count: u32,
    /// The one thing to do next (see `api::tasks`).
    pub pressing_task: Option<super::tasks::PressingTask>,
}

// ---------------------------------------------------------------------------
// Settings
// ---------------------------------------------------------------------------

#[derive(Debug, Clone)]
pub struct Settings {
    pub display_name: String,
    pub managebac_cas_url: Option<String>,
    pub daily_goal_xp: u32,
}
