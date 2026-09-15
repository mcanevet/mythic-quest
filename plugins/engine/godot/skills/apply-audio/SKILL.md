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

## Done when

Triggering the event via `simulate_input` shows the expected audio playback in debug output, with no errors.
