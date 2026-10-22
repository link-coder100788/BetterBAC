//! Everything under this module is exposed to Dart via flutter_rust_bridge.
//! Keep these functions thin: validation, persistence and game rules live in
//! `crate::store`, `crate::calendar` and `crate::progress`.

pub mod app;
pub mod calendar;
pub mod cas;
pub mod coach;
pub mod dev;
pub mod reminders;
pub mod settings;
pub mod tutorial;
pub mod types;
pub mod web;
