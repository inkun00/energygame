# Bundled sound effects

All 17 effects are original synthesized sounds, baked by
`python tools/generate_sfx.py`. The score preserves the previous effect timings;
each complete effect is one file, including overlapping notes and short gaps.

- Source: 22,050 Hz, mono, 16-bit WAV (371,624 bytes total).
- Godot import: QOA, no normalization or trimming, no loops.
- Compressed audio payload: 75,416 bytes; imported resources including metadata:
  81,927 bytes. Source WAV files are remapped to these imports in the web pack.
- All clips are preloaded by AudioManager and downloaded with `index.pck` before
  the game opens. Replaying an effect performs no network or file request.
- Web uses Web Audio sample playback. Other platforms use stream playback.
- A pool of 12 reusable players permits overlapping effects. At saturation a new
  request is dropped instead of interrupting an existing sound. No note timers or
  runtime waveform generation remain.

The browser's normal HTTP cache controls reuse of the game pack between visits;
this does not add an offline/PWA installation or permanent browser storage.

Verification: run Godot with `--headless --path . -s
scripts/tests/AudioPlaybackSmokeTest.gd`. The test covers all clips, compression,
natural completion, repeated use, and overlapping effects. The normal gameplay
smoke test also exercises the unchanged public audio event methods.
