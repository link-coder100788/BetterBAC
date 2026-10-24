//! On-device dictation with OpenAI's Whisper (multilingual `base`), run by
//! [candle](https://github.com/huggingface/candle), entirely in Rust.
//!
//! Native only (iPhone, Android, Mac). The web build compiles these functions
//! as stubs, so the Dart API is the same everywhere.
//!
//! Flow (driven by `lib/dictation.dart`):
//! 1. First use: Dart reads the bundled model asset and passes it to
//!    [`install_dictation_model`], which saves it to app support.
//! 2. [`load_dictation_model`] loads it once (it stays in memory).
//! 3. The app records 16 kHz mono PCM; [`transcribe`] turns it into text.
//!
//! The model file comes from `scripts/fetch_whisper_model.sh`. The config,
//! tokenizer and mel filterbank are small, so they're embedded here
//! (`rust/assets/whisper/`).

use anyhow::Result;
use flutter_rust_bridge::frb;

/// The result of one dictation.
#[derive(Debug, Clone, PartialEq)]
pub struct Transcript {
    pub text: String,
    /// Detected language code, e.g. "en" or "fr".
    pub language: String,
}

/// Model file name in the app support directory. Change it when the model
/// changes, so devices re-install.
const MODEL_FILE: &str = "whisper-base-q8.gguf";

/// Whether this build can dictate (false on web).
#[frb(sync)]
pub fn dictation_supported() -> bool {
    cfg!(not(target_arch = "wasm32"))
}

/// Has the model already been saved into `dir` (app support)?
pub fn dictation_model_installed(dir: String) -> bool {
    std::path::Path::new(&dir).join(MODEL_FILE).is_file()
}

/// Saves the bundled model bytes into `dir`, atomically.
pub fn install_dictation_model(dir: String, bytes: Vec<u8>) -> Result<()> {
    let dir = std::path::Path::new(&dir);
    std::fs::create_dir_all(dir)?;
    let part = dir.join(format!("{MODEL_FILE}.part"));
    std::fs::write(&part, &bytes)?;
    std::fs::rename(&part, dir.join(MODEL_FILE))?;
    Ok(())
}

/// Loads the model from `dir` into memory. Does nothing if already loaded.
pub fn load_dictation_model(dir: String) -> Result<()> {
    #[cfg(not(target_arch = "wasm32"))]
    {
        let mut slot = engine::ENGINE
            .lock()
            .map_err(|_| anyhow::anyhow!("dictation lock poisoned"))?;
        if slot.is_none() {
            *slot = Some(engine::Engine::load(&std::path::Path::new(&dir).join(MODEL_FILE))?);
        }
        Ok(())
    }
    #[cfg(target_arch = "wasm32")]
    {
        let _ = dir;
        anyhow::bail!("Dictation isn't available on the web")
    }
}

/// Transcribes 16-bit mono PCM. Other sample rates are resampled to 16 kHz.
pub fn transcribe(samples: Vec<i16>, sample_rate: u32) -> Result<Transcript> {
    #[cfg(not(target_arch = "wasm32"))]
    {
        let pcm = engine::to_16k_f32(&samples, sample_rate);
        engine::check_length(pcm.len())?;
        let mut slot = engine::ENGINE
            .lock()
            .map_err(|_| anyhow::anyhow!("dictation lock poisoned"))?;
        let engine = slot
            .as_mut()
            .ok_or_else(|| anyhow::anyhow!("Dictation model not loaded"))?;
        engine.transcribe(&pcm)
    }
    #[cfg(target_arch = "wasm32")]
    {
        let _ = (samples, sample_rate);
        anyhow::bail!("Dictation isn't available on the web")
    }
}

// ===========================================================================
// Engine (native only, private: kept out of the Dart bridge)
// ===========================================================================

#[cfg(not(target_arch = "wasm32"))]
#[frb(ignore)]
mod engine {
    use std::collections::HashMap;
    use std::path::Path;
    use std::sync::Mutex;

    use anyhow::{anyhow, bail, Context, Result};
    use candle_core::{Device, IndexOp, Tensor, D};
    use candle_transformers::models::whisper::{self as m, audio, quantized_model::Whisper, Config};
    use candle_transformers::quantized_var_builder::VarBuilder;

    use super::Transcript;

    const CONFIG_JSON: &str = include_str!("../../assets/whisper/config.json");
    const TOKENIZER_JSON: &str = include_str!("../../assets/whisper/tokenizer.json");
    const MEL_FILTERS: &[u8] = include_bytes!("../../assets/whisper/melfilters.bytes");

    /// Longest dictation accepted, in seconds.
    const MAX_SECONDS: usize = 5 * 60;
    /// Shortest worth transcribing, in seconds.
    const MIN_SECONDS: f32 = 0.5;
    /// Upper bound on tokens per 30 s segment.
    const MAX_TOKENS: usize = 224;

    pub(super) static ENGINE: Mutex<Option<Engine>> = Mutex::new(None);

    pub(super) fn check_length(samples: usize) -> Result<()> {
        if (samples as f32) < MIN_SECONDS * m::SAMPLE_RATE as f32 {
            bail!("That was too short. Hold on a moment longer.");
        }
        if samples > MAX_SECONDS * m::SAMPLE_RATE {
            bail!("Dictations are limited to {} minutes.", MAX_SECONDS / 60);
        }
        Ok(())
    }

    /// 16-bit PCM at any rate → f32 in [-1, 1] at 16 kHz (linear interpolation).
    pub(super) fn to_16k_f32(samples: &[i16], rate: u32) -> Vec<f32> {
        let f: Vec<f32> = samples.iter().map(|s| *s as f32 / 32768.0).collect();
        let target = m::SAMPLE_RATE as f64;
        if rate == 0 || rate as f64 == target || f.len() < 2 {
            return f;
        }
        let ratio = rate as f64 / target;
        let out_len = (f.len() as f64 / ratio) as usize;
        (0..out_len)
            .map(|i| {
                let pos = i as f64 * ratio;
                let j = pos.floor() as usize;
                let frac = (pos - j as f64) as f32;
                let a = f[j.min(f.len() - 1)];
                let b = f[(j + 1).min(f.len() - 1)];
                a + (b - a) * frac
            })
            .collect()
    }

    pub(super) struct Engine {
        model: Whisper,
        config: Config,
        tok: Tokenizer,
        mel_filters: Vec<f32>,
        /// Added to logits: -inf for tokens that must never be produced.
        suppress: Tensor,
        device: Device,
    }

    impl Engine {
        pub fn load(model_path: &Path) -> Result<Self> {
            let device = Device::Cpu;
            let config: Config = serde_json::from_str(CONFIG_JSON)?;
            let tok = Tokenizer::from_json(TOKENIZER_JSON)?;
            let vb = VarBuilder::from_gguf(model_path, &device)
                .with_context(|| format!("loading {}", model_path.display()))?;
            let model = Whisper::load(&vb, config.clone())?;

            let mel_filters: Vec<f32> = MEL_FILTERS
                .chunks_exact(4)
                .map(|b| f32::from_le_bytes([b[0], b[1], b[2], b[3]]))
                .collect();

            // Never emit the configured suppressed tokens or any special /
            // timestamp token (we transcribe without timestamps). End-of-text
            // comes before the specials, so it stays allowed.
            let suppress: Vec<f32> = (0..config.vocab_size as u32)
                .map(|i| {
                    if config.suppress_tokens.contains(&i) || i >= tok.sot {
                        f32::NEG_INFINITY
                    } else {
                        0.0
                    }
                })
                .collect();
            let suppress = Tensor::new(suppress.as_slice(), &device)?;

            Ok(Self {
                model,
                config,
                tok,
                mel_filters,
                suppress,
                device,
            })
        }

        pub fn transcribe(&mut self, pcm: &[f32]) -> Result<Transcript> {
            // Whisper tends to "hear" words in silence ("you", "Thank you."),
            // so don't run it at all unless there's actual speech.
            let speech = Speech::analyse(pcm);
            if !speech.any() {
                return Ok(Transcript {
                    text: String::new(),
                    language: String::new(),
                });
            }

            let n_mels = self.config.num_mel_bins;
            let mel = audio::pcm_to_mel(&self.config, pcm, &self.mel_filters);
            let total_frames = mel.len() / n_mels;
            let mel = Tensor::from_vec(mel, (1, n_mels, total_frames), &self.device)?;
            // The mel is padded with silence; only decode where there's audio.
            let content_frames = pcm.len() / m::HOP_LENGTH;

            let mut language = None;
            let mut parts = Vec::new();
            let mut seek = 0;
            while seek < content_frames {
                let start = seek * m::HOP_LENGTH;
                if !speech.any_between(start, start + m::N_SAMPLES) {
                    seek += m::N_FRAMES;
                    continue;
                }
                let size = m::N_FRAMES.min(total_frames - seek);
                let segment = mel.narrow(2, seek, size)?;
                let features = self.model.encoder.forward(&segment, true)?;
                let lang = match language {
                    Some(l) => l,
                    None => *language.insert(self.detect_language(&features)?),
                };
                let (tokens, avg_logprob, no_speech) = self.decode_segment(&features, lang)?;
                // Whisper's standard silence check: skip segments it thinks
                // contain no speech and that it isn't confident about.
                let silent =
                    no_speech > m::NO_SPEECH_THRESHOLD && avg_logprob < m::LOGPROB_THRESHOLD;
                if !silent {
                    let text = self.tok.decode(&tokens);
                    if !text.is_empty() {
                        parts.push(text);
                    }
                }
                seek += m::N_FRAMES;
            }

            Ok(Transcript {
                text: parts.join(" "),
                language: language.map(|l| self.tok.language_code(l)).unwrap_or_default(),
            })
        }

        /// The language token the model finds most likely for this audio.
        fn detect_language(&mut self, features: &Tensor) -> Result<u32> {
            let tokens = Tensor::new(&[self.tok.sot], &self.device)?.unsqueeze(0)?;
            let ys = self.model.decoder.forward(&tokens, features, true)?;
            let logits = self.model.decoder.final_linear(&ys.i(..1)?)?.i(0)?.i(0)?;
            let ids: Vec<u32> = self.tok.languages.iter().map(|(id, _)| *id).collect();
            let index = Tensor::new(ids.as_slice(), &self.device)?;
            let best = logits.index_select(&index, 0)?.argmax(0)?.to_scalar::<u32>()?;
            Ok(ids[best as usize])
        }

        /// Greedy decoding of one 30 s segment. Returns text tokens, their
        /// average log-probability, and the no-speech probability.
        fn decode_segment(&mut self, features: &Tensor, lang: u32) -> Result<(Vec<u32>, f64, f64)> {
            let t = &self.tok;
            let prefix = [t.sot, lang, t.transcribe, t.no_timestamps];
            let mut tokens = prefix.to_vec();
            let (mut sum_logprob, mut no_speech) = (0.0f64, 0.0f64);

            for i in 0..MAX_TOKENS {
                let input = Tensor::new(tokens.as_slice(), &self.device)?.unsqueeze(0)?;
                let ys = self.model.decoder.forward(&input, features, i == 0)?;

                if i == 0 {
                    if let Some(ns) = self.tok.no_speech {
                        let first = self.model.decoder.final_linear(&ys.i(..1)?)?.i(0)?.i(0)?;
                        no_speech = candle_nn::ops::softmax(&first, D::Minus1)?
                            .i(ns as usize)?
                            .to_scalar::<f32>()? as f64;
                    }
                }

                let (_, seq_len, _) = ys.dims3()?;
                let logits = self
                    .model
                    .decoder
                    .final_linear(&ys.i((..1, seq_len - 1..))?)?
                    .i(0)?
                    .i(0)?
                    .broadcast_add(&self.suppress)?;
                let next = logits.argmax(D::Minus1)?.to_scalar::<u32>()?;
                if next == self.tok.eot || tokens.len() >= self.config.max_target_positions {
                    break;
                }
                let prob = candle_nn::ops::softmax(&logits, D::Minus1)?
                    .i(next as usize)?
                    .to_scalar::<f32>()? as f64;
                sum_logprob += prob.max(1e-10).ln();
                tokens.push(next);
            }

            let text_tokens = tokens.split_off(prefix.len());
            let avg = if text_tokens.is_empty() {
                f64::NEG_INFINITY
            } else {
                sum_logprob / text_tokens.len() as f64
            };
            Ok((text_tokens, avg, no_speech))
        }
    }

    /// Simple energy-based voice activity detection: 30 ms frames are
    /// "voiced" when clearly louder than the recording's own noise floor.
    pub(super) struct Speech {
        voiced: Vec<bool>,
    }

    impl Speech {
        const FRAME: usize = 480; // 30 ms at 16 kHz
        /// Never call anything quieter than this speech (RMS, full scale = 1).
        const MIN_RMS: f32 = 0.01;
        /// Speech must be at least this many times the noise floor.
        const OVER_FLOOR: f32 = 3.0;
        /// Need ~0.25 s of voiced audio to count as speech.
        const MIN_VOICED_FRAMES: usize = 8;

        pub fn analyse(pcm: &[f32]) -> Self {
            let rms: Vec<f32> = pcm
                .chunks(Self::FRAME)
                .map(|f| (f.iter().map(|s| s * s).sum::<f32>() / f.len() as f32).sqrt())
                .collect();
            // Noise floor: the 20th-percentile frame.
            let mut sorted = rms.clone();
            sorted.sort_by(f32::total_cmp);
            let floor = sorted.get(sorted.len() / 5).copied().unwrap_or(0.0);
            let threshold = Self::MIN_RMS.max(floor * Self::OVER_FLOOR);
            Self {
                voiced: rms.iter().map(|r| *r > threshold).collect(),
            }
        }

        pub fn any(&self) -> bool {
            self.voiced.iter().filter(|v| **v).count() >= Self::MIN_VOICED_FRAMES
        }

        /// Any speech in samples `[start, end)`?
        pub fn any_between(&self, start: usize, end: usize) -> bool {
            let (a, b) = (start / Self::FRAME, end.div_ceil(Self::FRAME));
            self.voiced
                .get(a..b.min(self.voiced.len()))
                .is_some_and(|f| f.iter().filter(|v| **v).count() >= Self::MIN_VOICED_FRAMES)
        }
    }

    /// Just enough of Whisper's byte-level BPE tokenizer to *decode*
    /// (no `tokenizers` crate needed): id → token string → bytes → UTF-8.
    pub(super) struct Tokenizer {
        /// Token string by id (empty for unknown ids).
        tokens: Vec<String>,
        /// GPT-2's printable-character → byte table.
        byte_of: HashMap<char, u8>,
        pub eot: u32,
        pub sot: u32,
        pub transcribe: u32,
        pub no_timestamps: u32,
        pub no_speech: Option<u32>,
        /// (token id, code) for every language token, e.g. (50259, "en").
        pub languages: Vec<(u32, String)>,
    }

    impl Tokenizer {
        pub fn from_json(json: &str) -> Result<Self> {
            let v: serde_json::Value = serde_json::from_str(json)?;
            let mut by_id: HashMap<u32, String> = HashMap::new();
            for (token, id) in v["model"]["vocab"]
                .as_object()
                .ok_or_else(|| anyhow!("tokenizer: no vocab"))?
            {
                by_id.insert(id.as_u64().unwrap_or_default() as u32, token.clone());
            }
            let mut special: HashMap<String, u32> = HashMap::new();
            for t in v["added_tokens"].as_array().into_iter().flatten() {
                let (Some(id), Some(content)) = (t["id"].as_u64(), t["content"].as_str()) else {
                    continue;
                };
                by_id.insert(id as u32, content.to_string());
                special.insert(content.to_string(), id as u32);
            }

            let id = |s: &str| {
                special
                    .get(s)
                    .copied()
                    .ok_or_else(|| anyhow!("tokenizer: missing {s}"))
            };
            let sot = id(m::SOT_TOKEN)?;
            let translate = id(m::TRANSLATE_TOKEN)?;
            // Language tokens sit between <|startoftranscript|> and <|translate|>.
            let mut languages: Vec<(u32, String)> = special
                .iter()
                .filter(|(_, id)| **id > sot && **id < translate)
                .map(|(s, id)| (*id, s.trim_start_matches("<|").trim_end_matches("|>").to_string()))
                .collect();
            languages.sort();

            let max_id = by_id.keys().copied().max().unwrap_or(0) as usize;
            let mut tokens = vec![String::new(); max_id + 1];
            for (id, s) in by_id {
                tokens[id as usize] = s;
            }

            Ok(Self {
                tokens,
                byte_of: gpt2_byte_decoder(),
                eot: id(m::EOT_TOKEN)?,
                sot,
                transcribe: id(m::TRANSCRIBE_TOKEN)?,
                no_timestamps: id(m::NO_TIMESTAMPS_TOKEN)?,
                no_speech: m::NO_SPEECH_TOKENS.iter().find_map(|s| special.get(*s).copied()),
                languages,
            })
        }

        /// Text for `ids`, skipping special tokens.
        pub fn decode(&self, ids: &[u32]) -> String {
            let bytes: Vec<u8> = ids
                .iter()
                .filter(|id| **id < self.eot)
                .filter_map(|id| self.tokens.get(*id as usize))
                .flat_map(|s| s.chars())
                .filter_map(|c| self.byte_of.get(&c).copied())
                .collect();
            String::from_utf8_lossy(&bytes).trim().to_string()
        }

        pub fn language_code(&self, id: u32) -> String {
            self.languages
                .iter()
                .find(|(l, _)| *l == id)
                .map(|(_, code)| code.clone())
                .unwrap_or_default()
        }
    }

    /// Inverse of GPT-2's `bytes_to_unicode`: printable bytes map to
    /// themselves, the rest to U+0100 onwards.
    fn gpt2_byte_decoder() -> HashMap<char, u8> {
        let mut printable: Vec<u32> = (u32::from(b'!')..=u32::from(b'~'))
            .chain(0xA1..=0xAC)
            .chain(0xAE..=0xFF)
            .collect();
        let mut chars = printable.clone();
        let mut extra = 0;
        for b in 0..=255u32 {
            if !printable.contains(&b) {
                printable.push(b);
                chars.push(256 + extra);
                extra += 1;
            }
        }
        printable
            .into_iter()
            .zip(chars)
            .filter_map(|(b, c)| char::from_u32(c).map(|c| (c, b as u8)))
            .collect()
    }

    #[cfg(test)]
    mod tests {
        use super::*;

        #[test]
        fn tokenizer_decodes_and_finds_specials() {
            let tok = Tokenizer::from_json(TOKENIZER_JSON).unwrap();
            assert_eq!((tok.eot, tok.sot), (50257, 50258));
            assert!(tok.languages.len() >= 99);
            assert_eq!(tok.languages[0], (50259, "en".to_string()));
            assert!(tok.languages.iter().any(|(_, c)| c == "fr"));
            assert!(tok.no_speech.is_some());

            // Round-trip some ordinary words through the vocab.
            let ids: Vec<u32> = ["Hello", "Ġworld", "!"]
                .iter()
                .map(|t| tok.tokens.iter().position(|s| s == t).unwrap() as u32)
                .collect();
            assert_eq!(tok.decode(&ids), "Hello world!");
            // Special tokens are skipped.
            assert_eq!(tok.decode(&[tok.sot, ids[0], tok.eot]), "Hello");
        }

        #[test]
        fn non_ascii_bytes_round_trip() {
            let decoder = gpt2_byte_decoder();
            assert_eq!(decoder.len(), 256);
            assert_eq!(decoder[&'Ġ'], b' ');
        }

        #[test]
        fn resampling_and_length_checks() {
            let pcm = vec![0i16; 48_000]; // 1 s at 48 kHz
            assert_eq!(to_16k_f32(&pcm, 48_000).len(), 16_000);
            assert_eq!(to_16k_f32(&pcm[..16_000], 16_000).len(), 16_000);
            assert!(check_length(4_000).is_err()); // 0.25 s
            assert!(check_length(16_000).is_ok());
            assert!(check_length(16_000 * 60 * 6).is_err());
        }

        #[test]
        fn voice_activity() {
            let silence = vec![0.0f32; 32_000];
            assert!(!Speech::analyse(&silence).any());

            // Faint hiss stays below the minimum.
            let hiss: Vec<f32> = (0..32_000).map(|i| ((i * 7919) % 13) as f32 * 0.0004 - 0.0024).collect();
            assert!(!Speech::analyse(&hiss).any());

            // 1 s of a loud tone after 1 s of silence is speech, in the right place.
            let mut tone = vec![0.0f32; 16_000];
            tone.extend((0..16_000).map(|i| (i as f32 * 0.05).sin() * 0.2));
            let s = Speech::analyse(&tone);
            assert!(s.any());
            assert!(!s.any_between(0, 16_000));
            assert!(s.any_between(16_000, 32_000));
        }

        /// End-to-end with the real model: `cargo test -- --ignored`.
        /// Needs `scripts/fetch_whisper_model.sh` and a 16 kHz mono WAV at
        /// `$BETTERBAC_TEST_WAV` (e.g. made with macOS `say` + `afconvert`).
        #[test]
        #[ignore]
        fn transcribes_real_audio() {
            let model = Path::new(env!("CARGO_MANIFEST_DIR")).join("../assets/models/whisper-base-q8.gguf");
            let wav = std::env::var("BETTERBAC_TEST_WAV").expect("set BETTERBAC_TEST_WAV");
            let bytes = std::fs::read(wav).unwrap();
            // Find the "data" chunk of the WAV and read 16-bit samples.
            let data = bytes.windows(4).position(|w| w == b"data").unwrap() + 8;
            let samples: Vec<i16> = bytes[data..]
                .chunks_exact(2)
                .map(|b| i16::from_le_bytes([b[0], b[1]]))
                .collect();
            let mut engine = Engine::load(&model).unwrap();
            let started = std::time::Instant::now();
            let t = engine.transcribe(&to_16k_f32(&samples, 16_000)).unwrap();
            println!("[{}] {:?} in {:?}", t.language, t.text, started.elapsed());
            let expected = std::env::var("BETTERBAC_TEST_EXPECT").unwrap_or_default();
            assert!(
                t.text.to_lowercase().contains(&expected.to_lowercase()),
                "got {:?}",
                t.text
            );
        }
    }
}
