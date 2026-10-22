use anyhow::{bail, Result};

use super::types::Settings;
use crate::state::{self, with_core};

pub fn get_settings() -> Result<Settings> {
    with_core(|store, _| store.settings())
}

/// Validates, normalises and saves. Returns what was stored.
pub fn update_settings(settings: Settings) -> Result<Settings> {
    let settings = Settings {
        display_name: settings.display_name.trim().to_string(),
        managebac_cas_url: settings
            .managebac_cas_url
            .as_deref()
            .map(normalize_url)
            .transpose()?
            .flatten(),
        daily_goal_xp: settings.daily_goal_xp.clamp(5, 500),
    };
    let now = state::now();
    with_core(|store, _| {
        store.save_settings(&settings, now)?;
        store.settings()
    })
}

/// Empty input clears the URL; otherwise ensures an http(s) scheme.
fn normalize_url(raw: &str) -> Result<Option<String>> {
    let raw = raw.trim();
    if raw.is_empty() {
        return Ok(None);
    }
    let url = if raw.starts_with("https://") || raw.starts_with("http://") {
        raw.to_string()
    } else if raw.contains("://") {
        bail!("ManageBAC links must start with https://");
    } else {
        format!("https://{raw}")
    };
    let host = url
        .split("://")
        .nth(1)
        .unwrap_or("")
        .split('/')
        .next()
        .unwrap_or("");
    if !host.contains('.') || host.contains(char::is_whitespace) {
        bail!("That doesn't look like a link. Copy it from your browser's address bar.");
    }
    Ok(Some(url))
}

#[cfg(test)]
mod tests {
    use super::normalize_url;

    #[test]
    fn urls() {
        assert_eq!(normalize_url("  ").unwrap(), None);
        assert_eq!(
            normalize_url("school.managebac.com/student/ib/activity/cas")
                .unwrap()
                .as_deref(),
            Some("https://school.managebac.com/student/ib/activity/cas")
        );
        assert!(normalize_url("ftp://x.com").is_err());
        assert!(normalize_url("not a url").is_err());
    }
}
