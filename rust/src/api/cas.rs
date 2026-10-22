use anyhow::{anyhow, bail, Result};
use flutter_rust_bridge::frb;

use super::types::{
    Experience, ExperienceDraft, ExperienceSaved, LearningOutcome, ManageBacExport, Reflection,
    ReflectionDraft, ReflectionSaved,
};
use crate::progress;
use crate::state::{self, with_core};
use crate::store::{self, XpEntry};

// ---------------------------------------------------------------------------
// Experiences
// ---------------------------------------------------------------------------

pub fn list_experiences() -> Result<Vec<Experience>> {
    with_core(|store, _| store.list_experiences())
}

pub fn get_experience(id: String) -> Result<Experience> {
    with_core(|store, _| {
        store
            .get_experience(&id)?
            .ok_or_else(|| anyhow!("Experience not found"))
    })
}

pub fn create_experience(draft: ExperienceDraft) -> Result<ExperienceSaved> {
    let (now, today) = (state::now(), state::today());
    with_core(|store, _| {
        let id = store.create_experience(&draft, now)?;
        let xp_gained = store.award_xp(
            XpEntry {
                key: &progress::experience_key(&id),
                amount: progress::XP_EXPERIENCE_CREATED,
                day: today,
            },
            now,
        )?;
        let experience = store.get_experience(&id)?.expect("just inserted");
        Ok(ExperienceSaved {
            experience,
            xp_gained,
        })
    })
}

pub fn update_experience(id: String, draft: ExperienceDraft) -> Result<Experience> {
    let now = state::now();
    with_core(|store, _| {
        store.update_experience(&id, &draft, now)?;
        Ok(store.get_experience(&id)?.expect("just updated"))
    })
}

/// Deletes the experience. Its reflections are kept but unlinked.
pub fn delete_experience(id: String) -> Result<()> {
    let now = state::now();
    with_core(|store, _| {
        store.delete_experience(&id, now)?;
        store.revoke_xp_prefix(&progress::experience_prefix(&id), now)
    })
}

// ---------------------------------------------------------------------------
// Reflections
// ---------------------------------------------------------------------------

/// Newest first. Pass `experience_id` to only list one experience's reflections.
pub fn list_reflections(experience_id: Option<String>) -> Result<Vec<Reflection>> {
    with_core(|store, _| store.list_reflections(experience_id.as_deref()))
}

pub fn get_reflection(id: String) -> Result<Reflection> {
    with_core(|store, _| {
        store
            .get_reflection(&id)?
            .ok_or_else(|| anyhow!("Reflection not found"))
    })
}

/// Creates (`id == None`) or updates a reflection. Writing a meaningful
/// amount earns a small amount of XP once per reflection per day.
pub fn save_reflection(id: Option<String>, draft: ReflectionDraft) -> Result<ReflectionSaved> {
    let (now, today) = (state::now(), state::today());
    with_core(|store, _| {
        let id = match id {
            Some(id) => {
                store.update_reflection(&id, &draft, now)?;
                id
            }
            None => store.create_reflection(&draft, now)?,
        };
        let xp_gained = if store::word_count(&draft.body) >= progress::DRAFT_MIN_WORDS {
            store.award_xp(
                XpEntry {
                    key: &progress::reflection_draft_key(&id, today),
                    amount: progress::XP_DRAFT_SESSION,
                    day: today,
                },
                now,
            )?
        } else {
            0
        };
        let reflection = store.get_reflection(&id)?.expect("just saved");
        Ok(ReflectionSaved {
            reflection,
            xp_gained,
        })
    })
}

pub fn delete_reflection(id: String) -> Result<()> {
    let now = state::now();
    with_core(|store, _| {
        store.delete_reflection(&id, now)?;
        store.revoke_xp_prefix(&progress::reflection_prefix(&id), now)
    })
}

/// Prepares a reflection for pasting into ManageBAC and marks it as sent.
/// The UI copies `text` to the clipboard and opens `url`.
pub fn export_reflection(id: String) -> Result<ManageBacExport> {
    let (now, today) = (state::now(), state::today());
    with_core(|store, _| {
        let reflection = store
            .get_reflection(&id)?
            .ok_or_else(|| anyhow!("Reflection not found"))?;
        let text = reflection.body.trim().to_string();
        if text.is_empty() {
            bail!("Write something before sending it to ManageBAC");
        }
        store.mark_reflection_exported(&id, now)?;
        let xp_gained = store.award_xp(
            XpEntry {
                key: &progress::reflection_export_key(&id),
                amount: progress::reflection_export_xp(reflection.word_count),
                day: today,
            },
            now,
        )?;
        Ok(ManageBacExport {
            text,
            url: store.settings()?.managebac_cas_url,
            xp_gained,
        })
    })
}

/// Guiding questions to help the student start writing.
#[frb(sync)]
pub fn reflection_prompts(outcomes: Vec<LearningOutcome>) -> Vec<String> {
    progress::reflection_prompts(&outcomes)
}

#[frb(sync)]
pub fn count_words(text: String) -> u32 {
    store::word_count(&text)
}
