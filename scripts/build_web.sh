#!/usr/bin/env bash
# Builds the web version of BetterBAC into build/web.
#
#   scripts/build_web.sh                 # base path /BetterBAC/ (GitHub Pages)
#   BASE_HREF=/ scripts/build_web.sh     # serve from a domain root instead
#
# Needs (one-time):
#   rustup target add wasm32-unknown-unknown --toolchain nightly
#   rustup component add rust-src --toolchain nightly
#   cargo install wasm-pack
#   cargo install wasm-bindgen-cli --version <wasm-bindgen version in rust/Cargo.lock>
#   brew install llvm
set -euo pipefail
cd "$(dirname "$0")/.."

BASE_HREF="${BASE_HREF:-/BetterBAC/}"
LLVM_BIN="${LLVM_BIN:-$(brew --prefix llvm 2>/dev/null)/bin}"

if [[ ! -x "$LLVM_BIN/clang" || ! -x "$LLVM_BIN/llvm-ar" ]]; then
  echo "error: LLVM clang/llvm-ar not found in '$LLVM_BIN'. Run 'brew install llvm' or set LLVM_BIN." >&2
  exit 1
fi

want=$(awk '/^name = "wasm-bindgen"$/{getline; gsub(/"/, "", $3); print $3}' rust/Cargo.lock)
have=$(wasm-bindgen --version 2>/dev/null | awk '{print $2}')
if [[ "$want" != "$have" ]]; then
  echo "error: need wasm-bindgen-cli $want (found '${have:-none}'):" >&2
  echo "  cargo install wasm-bindgen-cli --version $want --locked" >&2
  exit 1
fi

# SQLite is C code compiled to WebAssembly. Apple's clang/ar produce an
# archive the wasm linker can't read, so use Homebrew LLVM. The Rust core
# runs on several web workers (shared memory), so the C code needs the
# WebAssembly threads features too.
export CC_wasm32_unknown_unknown="$LLVM_BIN/clang"
export AR_wasm32_unknown_unknown="$LLVM_BIN/llvm-ar"
export CFLAGS_wasm32_unknown_unknown="-matomics -mbulk-memory -mmutable-globals"

echo "==> Building Rust core for the web (web/pkg)"
flutter_rust_bridge_codegen build-web --release

echo "==> Building Flutter web app (base href $BASE_HREF)"
flutter build web --release --base-href "$BASE_HREF" --no-web-resources-cdn

# Dictation is native-only; don't ship the ~80 MB Whisper model to the web.
rm -f build/web/assets/assets/models/*.gguf

echo "==> Done: build/web"
