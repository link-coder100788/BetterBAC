The on-device dictation model goes here: `whisper-base-q8.gguf` (~80 MB).

It's not in git. Create it with:

    scripts/fetch_whisper_model.sh

The app still builds without it; the Dictate button then says dictation isn't
available in this build.
