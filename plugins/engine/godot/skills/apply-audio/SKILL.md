---
name: apply-audio
description: Apply audio to the game (music, SFX, ambience). Use when adding sound to entities, scenes, or game states.
---

## What I do

Adds audio to the game:
- SFX via `AudioStreamPlayer` (+positioned `AudioStreamPlayer2D` for spatial sources)
- Music/ambience via a dedicated bus and `AudioStreamPlayer` with autoplay
- Procedurally-generated audio: `AudioStreamGenerator` or `AudioStreamWAV` built from code (tones, envelopes) — no binary asset imports
- Audio triggers wired to entity signals (spawn, hit, pickup, death) and UI events

## Conventions

- Route music/ambience through a `Music` bus, SFX through `SFX` bus (created via default_bus_layout)
- Volume constants centralized in an autoload (`res://scripts/audio.gd`) with linear-to-db conversion
- Procedural SFX described in code by envelope + waveform — deterministic, testable
- Never block gameplay on audio (fire-and-forget playback)
- Verify audio fires via MCP `run_project` + `get_debug_output` (stream started/finished logs) — audio itself can't be heard headlessly

## Procedural audio generation (read before synthesizing assets)

> ⚠️ **Godot 4 has NO `AudioStreamWAV.save_to_file()`** — it's a
> plausible-but-nonexistent API (observed: one session burned 4 script
> errors + a pivot cycle on it). Two working recipes:

**Recipe A — generate WAV files in GDScript via ResourceSaver (preferred,
works inside one `run_script` probe):**
```gdscript
func _gen_tone(freq: float, dur: float) -> AudioStreamWAV:
    var rate := 44100
    var n := int(dur * rate)
    var data := PackedByteArray(); data.resize(n * 2)
    for i in n:
        var env := float(i) / n            # linear decay
        var v := int(32767.0 * env * sin(TAU * freq * i / rate))
        data.encode_s16(i * 2, v)
    var wav := AudioStreamWAV.new()
    wav.format = AudioStreamWAV.FORMAT_16_BITS
    wav.mix_rate = rate
    wav.stereo = false
    wav.data = data
    return wav
# save: ResourceSaver.save(_gen_tone(880.0, 0.15), "res://assets/audio/hit.wav")
```
Note: in dynamically submitted scripts (`run_script`) avoid `:=` inference
on typed returns (compile-error class from the create-entity gotchas) —
use explicit types as above.

**Recipe B — raw PCM WAV from python3 stdlib** (`struct`/`wave`, no
numpy) when file-system generation is easier; write to
`assets/audio/*.wav`, then verify Godot imports it (validate or re-run).

Either way: verify the stream loads and plays via `run_project` +
`get_debug_output` (stream started/finished logs), same as binary assets.

## Done when

Triggering the event via `simulate_input` shows the expected audio playback in debug output, with no errors.
