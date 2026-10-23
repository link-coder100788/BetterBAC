//! Reflection coach: feedback on a reflection draft, entirely on-device.
//!
//! Two engines produce a [`CoachReport`]:
//!
//! - **Rules** ([`coach_with_rules`]): a text `Analysis` plus a list of
//!   `Encouragement` rules. Used on Android and Windows, and as the
//!   fallback everywhere.
//! - **Apple Intelligence** ([`coach_prompt`] → Swift → [`coach_with_ai`]):
//!   Rust writes the prompt, Apple's on-device model writes the feedback,
//!   and Rust validates it and merges in the score and outcome-tag tips.
//!
//! Both share the same analysis and score, so feedback stays consistent.
//!
//! # Adding a rule
//!
//! 1. Make a struct for the condition, e.g. `struct NoNumbers;`.
//! 2. `impl Encouragement for NoNumbers`: `applies` says when it fires and
//!    `respond` says what to tell the student. `respond` can branch on the
//!    analysis to build a response tree, and use `Variety::pick` so repeat
//!    visits don't read the same.
//! 3. Add it to `rules()`.
//!
//! The engine lives in a private `mod engine` below so flutter_rust_bridge
//! doesn't try to expose it.

use flutter_rust_bridge::frb;

use super::types::{LearningOutcome, ReflectionDraft};
use engine::{
    clip, headline, rules, Analysis, Variety, AI_INSTRUCTIONS, MAX_PROMPT_WORDS, MIN_WORDS,
};

// ===========================================================================
// Types shared with Dart
// ===========================================================================

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum TipKind {
    /// Something the student did well.
    Praise,
    /// Something to improve.
    Suggestion,
    /// About learning-outcome tags; `CoachTip::outcome` says which.
    Outcome,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum CoachSource {
    AppleIntelligence,
    Rules,
}

#[derive(Debug, Clone)]
pub struct CoachTip {
    pub kind: TipKind,
    pub title: String,
    pub body: String,
    /// For [`TipKind::Outcome`] tips that suggest tagging this outcome.
    pub suggest_tag: Option<LearningOutcome>,
}

#[derive(Debug, Clone)]
pub struct CoachReport {
    pub source: CoachSource,
    /// Reflection strength, 0 to 100.
    pub score: u8,
    pub headline: String,
    pub tips: Vec<CoachTip>,
}

/// Prompt for an on-device language model.
#[derive(Debug, Clone)]
pub struct CoachPrompt {
    pub instructions: String,
    pub prompt: String,
}

/// Raw structured output from the language model.
#[derive(Debug, Clone)]
pub struct AiFeedback {
    pub headline: String,
    pub tips: Vec<AiTip>,
}

#[derive(Debug, Clone)]
pub struct AiTip {
    /// "praise" or "suggestion".
    pub kind: String,
    pub title: String,
    pub body: String,
}

// ===========================================================================
// API
// ===========================================================================

/// The coach needs at least this many words to say anything useful.
#[frb(sync)]
pub fn coach_min_words() -> u32 {
    MIN_WORDS
}

/// Feedback from the built-in rules.
pub fn coach_with_rules(draft: ReflectionDraft) -> CoachReport {
    let a = Analysis::new(&draft);
    let mut v = Variety::seeded(&draft.body);

    let mut fired: Vec<(u8, CoachTip)> = rules()
        .iter()
        .filter(|r| r.applies(&a))
        .map(|r| (r.priority(), r.respond(&a, &mut v)))
        .collect();
    fired.sort_by(|x, y| y.0.cmp(&x.0));

    let take = |kind: TipKind, n: usize| {
        fired
            .iter()
            .filter(move |(_, t)| t.kind == kind)
            .take(n)
            .map(|(_, t)| t.clone())
    };
    let tips = take(TipKind::Praise, 2)
        .chain(take(TipKind::Suggestion, 3))
        .chain(take(TipKind::Outcome, 2))
        .collect();

    CoachReport {
        source: CoachSource::Rules,
        score: a.score(),
        headline: headline(a.score(), &mut v),
        tips,
    }
}

/// Instructions and prompt for Apple Intelligence (or any on-device model).
#[frb(sync)]
pub fn coach_prompt(draft: ReflectionDraft) -> CoachPrompt {
    let a = Analysis::new(&draft);
    let tagged = if draft.outcomes.is_empty() {
        "none".to_string()
    } else {
        draft
            .outcomes
            .iter()
            .map(|o| format!("LO{} ({})", o.number(), o.description()))
            .collect::<Vec<_>>()
            .join("; ")
    };
    let body: String = draft
        .body
        .split_whitespace()
        .take(MAX_PROMPT_WORDS)
        .collect::<Vec<_>>()
        .join(" ");

    CoachPrompt {
        instructions: AI_INSTRUCTIONS.into(),
        prompt: format!(
            "Learning outcomes the student tagged: {tagged}\n\
             Notes from a quick analysis:\n{notes}\n\n\
             Title: {title}\n\
             Reflection:\n\"\"\"\n{body}\n\"\"\"",
            notes = a.notes_for_model(),
            title = draft.title.trim(),
        ),
    }
}

/// Validates model output and merges it with the score and outcome tips.
pub fn coach_with_ai(draft: ReflectionDraft, feedback: AiFeedback) -> CoachReport {
    let rules_report = coach_with_rules(draft);

    let mut tips: Vec<CoachTip> = feedback
        .tips
        .into_iter()
        .filter_map(|t| {
            let title = clip(t.title.trim(), 60);
            let body = clip(t.body.trim(), 280);
            (!title.is_empty() && !body.is_empty()).then(|| CoachTip {
                kind: if t.kind.trim().eq_ignore_ascii_case("praise") {
                    TipKind::Praise
                } else {
                    TipKind::Suggestion
                },
                title,
                body,
                suggest_tag: None,
            })
        })
        .take(4)
        .collect();
    // The model doesn't know about the app's tag buttons; keep those from the rules.
    tips.extend(
        rules_report
            .tips
            .iter()
            .filter(|t| t.kind == TipKind::Outcome)
            .cloned(),
    );

    // An empty or unusable answer means we fall back to the rules entirely.
    if tips.iter().all(|t| t.kind == TipKind::Outcome) {
        return rules_report;
    }
    let headline = clip(feedback.headline.trim(), 90);
    CoachReport {
        source: CoachSource::AppleIntelligence,
        score: rules_report.score,
        headline: if headline.is_empty() {
            rules_report.headline
        } else {
            headline
        },
        tips,
    }
}

// ===========================================================================
// Engine (private: kept out of the Dart bridge)
// ===========================================================================

#[frb(ignore)]
mod engine {
    use super::*;

    // ===========================================================================
    // Analysis
    // ===========================================================================

    pub(super) const MIN_WORDS: u32 = 15;
    pub(super) const MAX_PROMPT_WORDS: usize = 1200;
    const GOOD_LENGTH: u32 = 150;

    pub(super) const AI_INSTRUCTIONS: &str = "\
    You are a warm, encouraging coach helping an IB Diploma student improve a CAS \
    reflection before they submit it. A strong CAS reflection briefly says what \
    happened, explores how the student felt, names what they learned about \
    themselves or the world, connects to the IB CAS learning outcomes they tagged, \
    and says what they will do differently next time.

    Give feedback grounded only in the student's text. Never invent details and \
    never rewrite the reflection for them. Talk to the student as \"you\". Praise \
    one or two specific things that work, then give the most useful suggestions, \
    each as a question or concrete idea. Keep every tip to one or two short \
    sentences. Be kind, upbeat and specific.";

    const FEELINGS: &[&str] = &[
        "felt",
        "feel",
        "feeling",
        "nervous",
        "anxious",
        "excited",
        "proud",
        "happy",
        "frustrat",
        "scared",
        "worried",
        "overwhelm",
        "relieved",
        "grateful",
        "satisf",
        "disappoint",
        "confiden",
        "embarrass",
        "enjoy",
        "surpris",
        "stress",
        "motivat",
        "inspired",
        "uncomfortable",
    ];
    const LEARNING: &[&str] = &[
        "i learned",
        "i learnt",
        "i realised",
        "i realized",
        "taught me",
        "i discovered",
        "i understood",
        "i now understand",
        "made me realise",
        "made me realize",
        "i noticed",
        "showed me",
        "i found out",
        "i understand",
        "learned that",
        "learnt that",
    ];
    const FUTURE: &[&str] = &[
        "next time",
        "in the future",
        "i will",
        "i'll",
        "i plan",
        "going forward",
        "from now on",
        "i want to",
        "i hope to",
        "i would like to",
        "my goal",
        "i'm going to",
        "i am going to",
    ];
    const NARRATIVE: &[&str] = &[
        " then ",
        "after that",
        " first ",
        " next ",
        " finally ",
        " later ",
    ];
    const FIRST_PERSON: &[&str] = &["i", "me", "my", "myself", "i'm", "i've", "i'd", "i'll"];
    const WENT_WRONG: &[&str] = &["wrong", "dificult", "issue", "problem", "challenge", "obstacle", "complication", "hurdle", "constraint"];

    /// Text signals that count as evidence for each outcome, indexed by `LearningOutcome as usize`.
    const OUTCOME_EVIDENCE: [&[&str]; 7] = [
        &[
            "strength",
            "good at",
            "weakness",
            "improve",
            "grow",
            "confident",
            "about myself",
            "i realised i",
            "i realized i",
        ],
        &[
            "challeng",
            "difficult",
            "hard",
            "new skill",
            "first time",
            "struggl",
            "comfort zone",
            "learned how to",
            "learnt how to",
        ],
        &[
            "plan",
            "organis",
            "organiz",
            "initiat",
            "set up",
            "i started",
            "propos",
            "schedul",
            "idea",
        ],
        &[
            "every week",
            "weekly",
            "kept going",
            "persever",
            "commit",
            "give up",
            "gave up",
            "months",
            "regularly",
            "consisten",
        ],
        &[
            "team",
            "together",
            "group",
            "collaborat",
            "partner",
            "others",
            "classmates",
            " we ",
        ],
        &[
            "community",
            "global",
            "world",
            "environment",
            "climate",
            "poverty",
            "sustainab",
            "society",
            "refugee",
            "local",
        ],
        &[
            "ethic",
            "fair",
            "right thing",
            "responsib",
            "moral",
            "respect",
            "consequence",
            "honest",
        ],
    ];

    /// Signals extracted from a draft. Rules read this; they never see raw text.
    pub(super) struct Analysis {
        words: u32,
        sentences: u32,
        first_person: u32,
        feeling_words: Vec<String>,
        learning: bool,
        future: bool,
        narrative_markers: u32,
        tagged: Vec<LearningOutcome>,
        difficulties: Vec<String>,
        /// Outcomes with textual evidence.
        evidenced: Vec<LearningOutcome>,
    }

    impl Analysis {
        pub(super) fn new(draft: &ReflectionDraft) -> Self {
            // Pad and normalise so phrase matching can rely on word boundaries.
            let text = format!(
                " {} ",
                draft
                    .body
                    .to_lowercase()
                    .replace(['’', '‘'], "'")
                    .split_whitespace()
                    .collect::<Vec<_>>()
                    .join(" ")
            );
            let tokens: Vec<&str> = text
                .split(|c: char| !(c.is_alphanumeric() || c == '\''))
                .filter(|t| !t.is_empty())
                .collect();

            let has = |list: &[&str]| list.iter().any(|p| text.contains(p));
            let feeling_words = FEELINGS
                .iter()
                .filter_map(|f| {
                    tokens
                        .iter()
                        .find(|t| t.starts_with(f))
                        .map(|t| t.to_string())
                })
                .collect();
            let difficulties = WENT_WRONG
                .iter()
                .filter_map(|f| {
                    tokens
                        .iter()
                        .find(|t| t.starts_with(f))
                        .map(|t| t.to_string())
                })
                .collect();
            Self {
                words: tokens.len() as u32,
                sentences: draft
                    .body
                    .split(['.', '!', '?'])
                    .filter(|s| !s.trim().is_empty())
                    .count() as u32,
                first_person: tokens.iter().filter(|t| FIRST_PERSON.contains(t)).count() as u32,
                feeling_words,
                learning: has(LEARNING),
                future: has(FUTURE),
                narrative_markers: NARRATIVE
                    .iter()
                    .map(|m| text.matches(m).count() as u32)
                    .sum(),
                tagged: draft.outcomes.clone(),
                difficulties,
                evidenced: LearningOutcome::ALL
                    .into_iter()
                    .filter(|o| has(OUTCOME_EVIDENCE[*o as usize]))
                    .collect(),
            }
        }

        fn has_feelings(&self) -> bool {
            !self.feeling_words.is_empty()
        }

        fn about_self(&self) -> bool {
            self.words == 0 || self.first_person * 100 / self.words >= 2
        }

        fn tagged_with_evidence(&self) -> usize {
            self.tagged
                .iter()
                .filter(|o| self.evidenced.contains(o))
                .count()
        }

        /// 0 to 100. Length 25, feelings 15, learning 20, looking ahead 15,
        /// outcome evidence 15, written about yourself 10.
        pub(super) fn score(&self) -> u8 {
            let mut s = 25 * self.words.min(GOOD_LENGTH) / GOOD_LENGTH;
            s += if self.has_feelings() { 15 } else { 0 };
            s += if self.learning { 20 } else { 0 };
            s += if self.future { 15 } else { 0 };
            if !self.tagged.is_empty() {
                s += 15 * self.tagged_with_evidence() as u32 / self.tagged.len() as u32;
            }
            s += if self.about_self() && self.words > 0 {
                10
            } else {
                0
            };
            s.min(100) as u8
        }

        /// Plain-language observations to steer the model.
        pub(super) fn notes_for_model(&self) -> String {
            let yes_no =
                |b: bool, yes: &str, no: &str| if b { yes.to_string() } else { no.to_string() };
            let mut notes = vec![
                format!("- {} words in {} sentences", self.words, self.sentences),
                yes_no(
                    self.has_feelings(),
                    &format!("- Mentions feelings ({})", self.feeling_words.join(", ")),
                    "- Does not describe feelings",
                ),
                yes_no(
                    self.learning,
                    "- States what was learned",
                    "- Does not clearly state what was learned",
                ),
                yes_no(
                    self.future,
                    "- Looks ahead to next time",
                    "- Does not say what they'd do differently",
                ),
            ];
            for o in &self.tagged {
                if !self.evidenced.contains(o) {
                    notes.push(format!(
                        "- Tagged LO{} but the text shows little evidence for it",
                        o.number()
                    ));
                }
            }
            notes.join("\n")
        }
    }

    // ===========================================================================
    // Rules
    // ===========================================================================

    /// A condition on a draft and what the coach says when it holds.
    pub(super) trait Encouragement {
        /// Does this rule have something to say?
        fn applies(&self, a: &Analysis) -> bool;
        /// The tip. Branch on `a` for a response tree; use `v` for variety.
        fn respond(&self, a: &Analysis, v: &mut Variety) -> CoachTip;
        /// Higher shows first within its kind.
        fn priority(&self) -> u8 {
            50
        }
    }

    /// Every rule, in no particular order (sorted by priority at runtime).
    pub(super) fn rules() -> Vec<Box<dyn Encouragement>> {
        let mut rules: Vec<Box<dyn Encouragement>> = vec![
            // Praise
            Box::new(NamesLearning),
            Box::new(SharesFeelings),
            Box::new(LooksAhead),
            Box::new(GoodLength),
            Box::new(WentWrong),
            // Suggestions
            Box::new(TooShort),
            Box::new(NoLearning),
            Box::new(NoFeelings),
            Box::new(NoFuture),
            Box::new(MostlyNarrative),
            Box::new(NotAboutYou),
            Box::new(NoOutcomesTagged),
            Box::new(TooLong),
        ];
        for o in LearningOutcome::ALL {
            rules.push(Box::new(TaggedWithoutEvidence(o)));
            rules.push(Box::new(EvidencedButUntagged(o)));
        }
        rules
    }

    fn tip(kind: TipKind, title: &str, body: impl Into<String>) -> CoachTip {
        CoachTip {
            kind,
            title: title.into(),
            body: body.into(),
            suggest_tag: None,
        }
    }

    // --- Praise ----------------------------------------------------------------

    struct NamesLearning;
    impl Encouragement for NamesLearning {
        fn applies(&self, a: &Analysis) -> bool {
            a.learning
        }
        fn respond(&self, _: &Analysis, v: &mut Variety) -> CoachTip {
            tip(
                TipKind::Praise,
                "You named what you learned",
                v.pick(&[
                    "That's the heart of a great reflection. Supervisors look for exactly this.",
                    "Spelling out what you learned turns a diary entry into a real reflection.",
                ]),
            )
        }
        fn priority(&self) -> u8 {
            80
        }
    }

    struct SharesFeelings;
    impl Encouragement for SharesFeelings {
        fn applies(&self, a: &Analysis) -> bool {
            a.has_feelings()
        }
        fn respond(&self, a: &Analysis, v: &mut Variety) -> CoachTip {
            let word = &a.feeling_words[0];
            let why = v.pick(&[
                "helps the reader understand what this meant to you",
                "makes your reflection personal and real",
            ]);
            tip(
                TipKind::Praise,
                "You were honest about how it felt",
                format!("Writing \"{word}\" {why}."),
            )
        }
        fn priority(&self) -> u8 {
            70
        }
    }

    struct LooksAhead;
    impl Encouragement for LooksAhead {
        fn applies(&self, a: &Analysis) -> bool {
            a.future
        }
        fn respond(&self, _: &Analysis, v: &mut Variety) -> CoachTip {
            tip(
                TipKind::Praise,
                "You're looking ahead",
                v.pick(&[
                    "Saying what you'll do next time shows real growth.",
                    "Planning your next step is what makes CAS a journey, not a checklist.",
                ]),
            )
        }
        fn priority(&self) -> u8 {
            60
        }
    }

    struct GoodLength;
    impl Encouragement for GoodLength {
        fn applies(&self, a: &Analysis) -> bool {
            a.words >= GOOD_LENGTH && a.words <= 600
        }
        fn respond(&self, _: &Analysis, _: &mut Variety) -> CoachTip {
            tip(
                TipKind::Praise,
                "Great length",
                "Enough detail to be meaningful, without rambling.",
            )
        }
        fn priority(&self) -> u8 {
            30
        }
    }

    struct WentWrong;
    impl Encouragement for WentWrong {
        fn applies(&self, a: &Analysis) -> bool {
            !a.difficulties.is_empty()
        }
        fn respond(&self, _: &Analysis, _: &mut Variety) -> CoachTip {
            tip(
                TipKind::Praise,
                "Included difficulties",
                "Including challenges is a good way to show learning"
            )
        }
    }

    // --- Suggestions -------------------------------------------------------------

    struct TooShort;
    impl Encouragement for TooShort {
        fn applies(&self, a: &Analysis) -> bool {
            a.words < 80
        }
        fn respond(&self, a: &Analysis, v: &mut Variety) -> CoachTip {
            if a.words < 40 {
                tip(
                    TipKind::Suggestion,
                    "Keep going!",
                    v.pick(&[
                        "You've made a start. Try adding a few sentences about what happened and why it mattered to you.",
                        "Good start! Aim for at least a short paragraph so your supervisor can see your thinking.",
                    ]),
                )
            } else {
                tip(
                    TipKind::Suggestion,
                    "Add a little more detail",
                    "Pick one moment that stood out and describe it. Specific moments make reflections memorable.",
                )
            }
        }
        fn priority(&self) -> u8 {
            90
        }
    }

    struct NoLearning;
    impl Encouragement for NoLearning {
        fn applies(&self, a: &Analysis) -> bool {
            !a.learning && a.words >= MIN_WORDS
        }
        fn respond(&self, a: &Analysis, v: &mut Variety) -> CoachTip {
            let body = if a.has_feelings() {
                "You've described how it felt. Now ask yourself why you felt that way, and what it taught you."
            } else {
                v.pick(&[
                    "What did this experience teach you about yourself or others? Try starting a sentence with \"I learned…\" or \"I realised…\".",
                    "Try finishing this sentence: \"This experience made me realise…\".",
                ])
            };
            tip(TipKind::Suggestion, "What did you learn?", body)
        }
        fn priority(&self) -> u8 {
            85
        }
    }

    struct NoFeelings;
    impl Encouragement for NoFeelings {
        fn applies(&self, a: &Analysis) -> bool {
            !a.has_feelings() && a.words >= MIN_WORDS
        }
        fn respond(&self, _: &Analysis, v: &mut Variety) -> CoachTip {
            tip(
                TipKind::Suggestion,
                "How did it feel?",
                v.pick(&[
                    "Were you nervous, proud, frustrated, surprised? A sentence about your feelings makes it personal.",
                    "Describe how you felt before and after. The change is often the most interesting part.",
                ]),
            )
        }
        fn priority(&self) -> u8 {
            75
        }
    }

    struct NoFuture;
    impl Encouragement for NoFuture {
        fn applies(&self, a: &Analysis) -> bool {
            !a.future && a.words >= MIN_WORDS
        }
        fn respond(&self, _: &Analysis, _: &mut Variety) -> CoachTip {
            tip(
                TipKind::Suggestion,
                "What's next?",
                "End with what you'd do differently next time, or a goal for your next session.",
            )
        }
        fn priority(&self) -> u8 {
            65
        }
    }

    struct MostlyNarrative;
    impl Encouragement for MostlyNarrative {
        fn applies(&self, a: &Analysis) -> bool {
            !a.learning && a.narrative_markers >= 3
        }
        fn respond(&self, _: &Analysis, _: &mut Variety) -> CoachTip {
            tip(
                TipKind::Suggestion,
                "Less what, more why",
                "This reads a bit like a timeline. Cut a step or two of \"then we…\" and use the space to explain why it mattered.",
            )
        }
        fn priority(&self) -> u8 {
            70
        }
    }

    struct NotAboutYou;
    impl Encouragement for NotAboutYou {
        fn applies(&self, a: &Analysis) -> bool {
            !a.about_self() && a.words >= 40
        }
        fn respond(&self, _: &Analysis, _: &mut Variety) -> CoachTip {
            tip(
                TipKind::Suggestion,
                "Make it about you",
                "Reflections are personal. Use \"I\" and focus on your own actions, thoughts and growth.",
            )
        }
        fn priority(&self) -> u8 {
            60
        }
    }

    struct NoOutcomesTagged;
    impl Encouragement for NoOutcomesTagged {
        fn applies(&self, a: &Analysis) -> bool {
            a.tagged.is_empty() && a.evidenced.is_empty() && a.words >= MIN_WORDS
        }
        fn respond(&self, _: &Analysis, _: &mut Variety) -> CoachTip {
            tip(
                TipKind::Suggestion,
                "Link it to a learning outcome",
                "Tag at least one learning outcome above. You need evidence for all 7 to complete CAS.",
            )
        }
        fn priority(&self) -> u8 {
            40
        }
    }

    struct TooLong;
    impl Encouragement for TooLong {
        fn applies(&self, a: &Analysis) -> bool {
            a.words >= 750
        }
        fn respond(&self, a: &Analysis, _: &mut Variety) -> CoachTip {
            tip(
                TipKind::Suggestion,
                "Try to shorten your reflection",
                format!("You currently have {} words, try to keep your reflection under 750", a.words),
            )
        }
    }

    // --- Learning outcomes (one rule instance per outcome) ----------------------

    struct TaggedWithoutEvidence(LearningOutcome);
    impl Encouragement for TaggedWithoutEvidence {
        fn applies(&self, a: &Analysis) -> bool {
            a.tagged.contains(&self.0) && !a.evidenced.contains(&self.0)
        }
        fn respond(&self, _: &Analysis, _: &mut Variety) -> CoachTip {
            let o = self.0;
            let idea = match o {
                LearningOutcome::Awareness => {
                    "Name a strength you used, or something you want to get better at."
                }
                LearningOutcome::Challenge => {
                    "Describe what was hard or new, and what skill you built to handle it."
                }
                LearningOutcome::Initiative => "Explain how you planned or kicked this off.",
                LearningOutcome::Commitment => {
                    "Mention how long you've kept at it, or a moment you pushed through."
                }
                LearningOutcome::Collaboration => {
                    "Mention who you worked with and how the team helped."
                }
                LearningOutcome::GlobalEngagement => {
                    "Connect it to a bigger issue in your community or the world."
                }
                LearningOutcome::Ethics => {
                    "Describe a choice you faced and how you decided what was right."
                }
            };
            tip(
                TipKind::Outcome,
                &format!("Show LO{}: {}", o.number(), o.short_name()),
                format!("You tagged this outcome, but the text doesn't show it yet. {idea}"),
            )
        }
        fn priority(&self) -> u8 {
            60
        }
    }

    struct EvidencedButUntagged(LearningOutcome);
    impl Encouragement for EvidencedButUntagged {
        fn applies(&self, a: &Analysis) -> bool {
            !a.tagged.contains(&self.0) && a.evidenced.contains(&self.0)
        }
        fn respond(&self, _: &Analysis, _: &mut Variety) -> CoachTip {
            let o = self.0;
            CoachTip {
                suggest_tag: Some(o),
                ..tip(
                    TipKind::Outcome,
                    &format!("This looks like LO{}", o.number()),
                    format!(
                        "Your writing shows {}. Tag it to count towards your 7 outcomes.",
                        o.short_name().to_lowercase()
                    ),
                )
            }
        }
        fn priority(&self) -> u8 {
            50
        }
    }

    // ===========================================================================
    // Helpers
    // ===========================================================================

    pub(super) fn headline(score: u8, v: &mut Variety) -> String {
        match score {
            80.. => v.pick(&[
                "This is a strong reflection!",
                "Wow, this one's ready to shine.",
            ]),
            60..=79 => v.pick(&[
                "Solid! A couple of tweaks will make it great.",
                "Nice work, you're nearly there.",
            ]),
            35..=59 => v.pick(&[
                "Good start. Let's dig a little deeper.",
                "You're on your way. Here's how to level it up.",
            ]),
            _ => v.pick(&[
                "Every reflection starts somewhere. Let's build it up!",
                "Let's turn this into a great reflection.",
            ]),
        }
        .into()
    }

    /// Truncates to at most `max` characters on a word boundary.
    pub(super) fn clip(s: &str, max: usize) -> String {
        if s.chars().count() <= max {
            return s.to_string();
        }
        let cut: String = s.chars().take(max).collect();
        match cut.rfind(' ') {
            Some(i) => format!("{}…", &cut[..i]),
            None => format!("{cut}…"),
        }
    }

    /// Tiny xorshift PRNG for picking phrasings; no need for a `rand` dependency.
    pub(super) struct Variety(u64);

    impl Variety {
        pub(super) fn seeded(text: &str) -> Self {
            #[cfg(not(target_arch = "wasm32"))]
            let nanos = std::time::SystemTime::now()
                .duration_since(std::time::UNIX_EPOCH)
                .map_or(0, |d| d.subsec_nanos() as u64);
            // `SystemTime::now` panics in the browser; chrono reads the JS clock.
            #[cfg(target_arch = "wasm32")]
            let nanos = chrono::Utc::now().timestamp_subsec_nanos() as u64;
            let hash = text.bytes().fold(0xcbf29ce484222325u64, |h, b| {
                (h ^ b as u64).wrapping_mul(0x100000001b3)
            });
            Self((hash ^ nanos) | 1)
        }

        fn next(&mut self) -> u64 {
            self.0 ^= self.0 << 13;
            self.0 ^= self.0 >> 7;
            self.0 ^= self.0 << 17;
            self.0
        }

        fn pick<'a>(&mut self, options: &[&'a str]) -> &'a str {
            options[(self.next() % options.len() as u64) as usize]
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn draft(body: &str, outcomes: &[LearningOutcome]) -> ReflectionDraft {
        ReflectionDraft {
            experience_id: None,
            title: "Test".into(),
            body: body.into(),
            outcomes: outcomes.to_vec(),
        }
    }

    const STRONG: &str = "I was nervous before my first shift at the food bank because I \
        had never volunteered before. Working with a team of older volunteers was hard at \
        first, but they were patient. I learned that asking questions is a strength, not a \
        weakness, and I realised how many families in our local community rely on the food \
        bank every week. I felt proud when we packed two hundred boxes together. Next time \
        I will take the initiative to organise the sorting table myself so new volunteers \
        feel welcome. Overall it changed how I see my own neighbourhood and I want to keep \
        going every week this term.";

    #[test]
    fn strong_reflection_scores_high_with_praise() {
        let r = coach_with_rules(draft(STRONG, &[LearningOutcome::Collaboration]));
        assert!(r.score >= 80, "score {}", r.score);
        assert!(r.tips.iter().any(|t| t.kind == TipKind::Praise));
        assert!(!r.tips.iter().any(|t| t.title == "What did you learn?"));
        // Global engagement is evident but untagged, so suggest tagging it.
        assert!(r
            .tips
            .iter()
            .any(|t| t.suggest_tag.is_some() && t.kind == TipKind::Outcome));
    }

    #[test]
    fn weak_reflection_gets_suggestions() {
        let r = coach_with_rules(draft(
            "We went to the park. Then we picked up litter. After that we went home. Then we ate lunch.",
            &[LearningOutcome::Ethics],
        ));
        assert!(r.score < 40, "score {}", r.score);
        let titles: Vec<_> = r.tips.iter().map(|t| t.title.as_str()).collect();
        assert!(titles.contains(&"What did you learn?"));
        assert!(titles.contains(&"Keep going!"));
        assert!(titles.iter().any(|t| t.starts_with("Show LO7")));
        assert!(
            r.tips
                .iter()
                .filter(|t| t.kind == TipKind::Suggestion)
                .count()
                <= 3
        );
    }

    #[test]
    fn ai_output_is_validated_and_merged() {
        let d = draft(STRONG, &[LearningOutcome::Collaboration]);
        let r = coach_with_ai(
            d.clone(),
            AiFeedback {
                headline: "  Lovely, honest reflection!  ".into(),
                tips: vec![
                    AiTip {
                        kind: "PRAISE".into(),
                        title: "Vivid".into(),
                        body: "Great detail.".into(),
                    },
                    AiTip {
                        kind: "suggestion".into(),
                        title: "".into(),
                        body: "dropped".into(),
                    },
                    AiTip {
                        kind: "suggestion".into(),
                        title: "Numbers".into(),
                        body: "x ".repeat(400),
                    },
                ],
            },
        );
        assert_eq!(r.source, CoachSource::AppleIntelligence);
        assert_eq!(r.headline, "Lovely, honest reflection!");
        assert_eq!(r.score, coach_with_rules(d.clone()).score);
        assert_eq!(r.tips[0].kind, TipKind::Praise);
        assert_eq!(r.tips[1].title, "Numbers");
        assert!(r.tips[1].body.chars().count() <= 281);
        assert!(r.tips.iter().any(|t| t.kind == TipKind::Outcome));

        // Unusable output falls back to the rules.
        let fallback = coach_with_ai(
            d,
            AiFeedback {
                headline: String::new(),
                tips: vec![],
            },
        );
        assert_eq!(fallback.source, CoachSource::Rules);
    }

    #[test]
    fn prompt_includes_text_and_notes() {
        let p = coach_prompt(draft(STRONG, &[LearningOutcome::Ethics]));
        assert!(p.prompt.contains("food bank"));
        assert!(p
            .prompt
            .contains("Tagged LO7 but the text shows little evidence"));
        assert!(p.instructions.contains("CAS"));
    }
}
