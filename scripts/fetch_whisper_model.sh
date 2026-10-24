#!/usr/bin/env bash
# Downloads OpenAI's whisper-base (multilingual, Apache-2.0) from Hugging Face
# and quantizes it to 8-bit GGUF for on-device dictation.
#
#   scripts/fetch_whisper_model.sh
#
# Output: assets/models/whisper-base-q8.gguf (~80 MB, bundled into the app,
# gitignored). Run once per clone, before `flutter run` / `flutter build`.
# Without it the app still builds; the mic button just says the model is missing.
set -euo pipefail
cd "$(dirname "$0")/.."

OUT=assets/models/whisper-base-q8.gguf
SRC_DIR=build/whisper-src
URL=https://huggingface.co/openai/whisper-base/resolve/main/model.safetensors

if [[ -f "$OUT" && "${1:-}" != "--force" ]]; then
  echo "==> $OUT already exists (use --force to rebuild)."
  exit 0
fi

mkdir -p "$SRC_DIR" "$(dirname "$OUT")"
if [[ ! -f "$SRC_DIR/model.safetensors" ]]; then
  echo "==> Downloading whisper-base weights (~290 MB)"
  curl -fL --progress-bar -o "$SRC_DIR/model.safetensors.part" "$URL"
  mv "$SRC_DIR/model.safetensors.part" "$SRC_DIR/model.safetensors"
fi

echo "==> Quantizing to 8-bit"
cargo run -q --release --manifest-path rust/tools/whisper_quantize/Cargo.toml -- \
  "$SRC_DIR/model.safetensors" "$OUT"

echo "==> Done: $OUT ($(du -h "$OUT" | cut -f1))"
