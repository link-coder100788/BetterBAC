//! The replayable app tour.
//!
//! **Every user-facing feature should have a step here.** When you ship a new
//! feature:
//!
//! 1. Bump [`TUTORIAL_VERSION`].
//! 2. Add a step with `since: TUTORIAL_VERSION` (the new value).
//! 3. Give it an illustration in `lib/screens/tutorial_screen.dart`
//!    (keyed by `id`; without one it falls back to `icon`).
//!
//! Existing users then see just the new steps as "What's new" on their next
//! launch, and new users get the whole tour.

use anyhow::Result;
use flutter_rust_bridge::frb;

use crate::progress;
use crate::state::{self, with_core};

/// Increase whenever steps are added.
const TUTORIAL_VERSION: u32 = 5;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum TutorialAccent {
    Green,
    Blue,
    Orange,
    Purple,
    Red,
    Yellow,
}

#[derive(Debug, Clone)]
pub struct TutorialStep {
    /// Stable key the UI uses to pick an illustration.
    pub id: String,
    pub title: String,
    pub body: String,
    /// Material icon name, used if the UI has no custom illustration.
    pub icon: String,
    pub accent: TutorialAccent,
    /// Tutorial version that introduced this step.
    pub since: u32,
}

#[derive(Debug, Clone)]
pub struct TutorialStatus {
    pub current_version: u32,
    /// 0 if the user has never finished the tour.
    pub seen_version: u32,
}

impl TutorialStatus {
    /// Should the tour show automatically on launch?
    #[frb(sync)]
    pub fn needs_tour(&self) -> bool {
        self.seen_version < self.current_version
    }

    /// True when only new steps should show ("What's new"), not the full tour.
    #[frb(sync)]
    pub fn is_update(&self) -> bool {
        self.seen_version > 0 && self.needs_tour()
    }
}

pub fn tutorial_status() -> Result<TutorialStatus> {
    with_core(|store, _| {
        Ok(TutorialStatus {
            current_version: TUTORIAL_VERSION,
            seen_version: store.tutorial_seen_version()?,
        })
    })
}

/// Records that the user finished (or skipped) the current tour.
pub fn mark_tutorial_seen() -> Result<()> {
    let now = state::now();
    with_core(|store, _| store.set_tutorial_seen_version(TUTORIAL_VERSION, now))
}

/// Steps added after `after_version`: pass 0 for the full tour, or the
/// user's seen version for just what's new.
#[frb(sync)]
pub fn tutorial_steps(after_version: u32) -> Vec<TutorialStep> {
    all_steps()
        .into_iter()
        .filter(|s| s.since > after_version)
        .collect()
}

fn step(
    id: &str,
    accent: TutorialAccent,
    icon: &str,
    title: &str,
    body: impl Into<String>,
) -> TutorialStep {
    TutorialStep {
        id: id.into(),
        title: title.into(),
        body: body.into(),
        icon: icon.into(),
        accent,
        since: 1,
    }
}

fn all_steps() -> Vec<TutorialStep> {
    use TutorialAccent::*;
    // XP numbers come from the real rules so the tour never goes stale.
    let short_export = progress::reflection_export_xp(0);
    let long_export = progress::reflection_export_xp(u32::MAX);
    vec![
        step(
            "welcome",
            Green,
            "school",
            "Welcome to BetterBAC",
            "Your CAS, deadlines and reflections in one place, built to make the IB a little less stressful. Here's a quick tour.",
        ),
        step(
            "daily_goal",
            Orange,
            "local_fire_department",
            "Build a streak",
            format!(
                "Earn XP for real progress: {} for logging an experience, {short_export}–{long_export} for sending a reflection, {} for ticking off a deadline. Hit your daily goal and keep your streak alive.",
                progress::XP_EXPERIENCE_CREATED,
                progress::XP_EVENT_COMPLETED,
            ),
        ),
        step(
            "outcomes",
            Green,
            "verified",
            "Track all 7 learning outcomes",
            "Home shows which CAS learning outcomes you've evidenced and how balanced your Creativity, Activity and Service are, so nothing surprises you at the end.",
        ),
        step(
            "experiences",
            Purple,
            "flag",
            "Log your CAS experiences",
            "Add each experience in the CAS tab, pick its strands, and mark your CAS project. All its reflections stay together.",
        ),
        step(
            "reflections",
            Blue,
            "edit_note",
            "Write reflections anywhere",
            "Tag learning outcomes, tap \"Need inspiration?\" for prompts, and stop worrying about losing work: drafts save automatically when you leave.",
        ),
        TutorialStep {
            since: 5,
            ..step(
                "dictation",
                Blue,
                "mic",
                "Just say it",
                "Tap Dictate in the reflection editor and talk. Whisper turns your speech into text right on your device, in English, French, Spanish and many more. Your voice never leaves your phone.",
            )
        },
        step(
            "coach",
            Purple,
            "auto_awesome",
            "Get coached",
            "Tap \"Coach my reflection\" for instant, private feedback on your writing. It uses Apple Intelligence on supported iPhones and Macs, and BetterBAC's own coach everywhere else.",
        ),
        step(
            "managebac",
            Green,
            "send",
            "Send to ManageBAC in one tap",
            "\"Copy & open ManageBAC\" copies your reflection and opens your CAS page. Just paste. Add your ManageBAC link in Profile to jump straight there.",
        ),
        step(
            "calendar",
            Blue,
            "calendar_month",
            "Every deadline in one calendar",
            "Add CAS, EE, TOK, IA, exam and homework deadlines. Tick them off when they're done.",
        ),
        TutorialStep {
            since: 3,
            ..step(
                "calendar_import",
                Blue,
                "event_repeat",
                "Bring in your calendar",
                "Connect Apple Calendar (Google Calendar on Android) from the Calendar tab. Exams and deadlines show up next to your CAS work and count towards crunch-week warnings. BetterBAC only reads your calendar.",
            )
        },
        TutorialStep {
            since: 4,
            ..step(
                "pressing_task",
                Red,
                "flag",
                "Know what to do next",
                "Home shows your most pressing task, the deadline that matters most soonest. On iPhone and Mac, one tap adds it to Apple Reminders so it nudges you the evening before.",
            )
        },
        step(
            "crunch",
            Red,
            "warning",
            "See crunch weeks coming",
            "BetterBAC watches your next six weeks. When big deadlines pile up, it warns you early so you can spread the work out and look after yourself.",
        ),
        TutorialStep {
            since: 2,
            ..step(
                "reminders",
                Orange,
                "notifications_active",
                "Never lose your streak",
                "Get a nudge when your streak is at risk, and reminders before deadlines and crunch weeks. On iPhone, a Live Activity counts down to midnight on your lock screen. Switch either off in Profile.",
            )
        },
        step(
            "achievements",
            Yellow,
            "emoji_events",
            "Unlock achievements",
            "Collect badges as you go. Find them, your settings, and this tour in the Profile tab.",
        ),
        step(
            "privacy",
            Blue,
            "lock",
            "Private by design",
            "No accounts. Everything you write stays on your device.",
        ),
    ]
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn steps_are_well_formed() {
        let steps = tutorial_steps(0);
        assert!(!steps.is_empty());
        let mut ids: Vec<_> = steps.iter().map(|s| s.id.as_str()).collect();
        ids.sort();
        ids.dedup();
        assert_eq!(ids.len(), steps.len(), "step ids must be unique");
        assert!(steps.iter().all(|s| s.since >= 1 && s.since <= TUTORIAL_VERSION));
        assert!(tutorial_steps(TUTORIAL_VERSION).is_empty());
    }

    #[test]
    fn status_logic() {
        let s = |seen| TutorialStatus { current_version: 2, seen_version: seen };
        assert!(s(0).needs_tour() && !s(0).is_update());
        assert!(s(1).needs_tour() && s(1).is_update());
        assert!(!s(2).needs_tour());
    }
}
