# Pocket Kingdoms tactile sound palette

The beta7 sound pass keeps the existing action hooks, persistent settings, fog
rules, camera distance attenuation and browser stream mixer. No simulation,
network messages, action intervals or unit costs change.

## Palette and provenance

`scripts/audio/tactile_palette.gd` is the complete, original source for all 18
sound banks. The recipes were authored for Pocket Kingdoms on 24 October 2026.
They synthesize mono 22,050 Hz / 16-bit PCM at startup using deterministic local
noise and additive damped resonances. There are no external samples, recordings,
voices, music excerpts or third-party asset licenses to obtain. The recipes and
generated sounds are supplied under the repository's own applicable terms.

- Selection and interface touches: a short wooden contact with a little cloth.
- Movement/attack orders: two quiet felt-plucked notes with distinct contours.
- Gathering: cloth/seed rustle, a low wooden chop, a small muted mineral tick.
- Combat: soft wood-and-cloth impacts; a very quiet falling body/rustle.
- Construction: restrained mallet taps, a low placement thump and a three-note
  completion phrase.
- Recruitment: a brief ascending pair. Important alerts use the same instrument
  with a repeated note; advancement and match outcomes get longer cadences.

Frequent tactile sounds and orders each have three small timbral variations;
the scheduler never repeats the same take consecutively. Important melodies
remain stable. There is no continuous music, voice acknowledgement or ambient
loop. The same palette serves French, English and Mongol players equally.

## Busy-scene rules

Eight world players and four UI/alert players are allocated once. Two interface
slots remain reserved for important events. Only a strictly higher priority cue
can displace a playing cue: clicks < selection < orders < recruitment/completion
< attack/age alerts < victory/defeat. A recruitment cannot interrupt a result.

Shared work cooldown (650 ms) covers all gathering and construction together;
shared combat cooldown (180 ms) prevents hits and deaths from alternating into
a continuous rattle. Per-event cooldowns also apply: impacts 200 ms, gathering
1–1.3 s, construction 1.1 s, recruitment 650 ms and attack alerts 6 s. Distant
effects attenuate; offscreen/hidden world events are discarded. A semantic UI
response suppresses a redundant button tick from the same gesture.

Master, world and UI/alert levels and mutes still save with existing preferences.
Pre-gesture browser events are dropped, while Godot's Web Audio backend owns
actual autoplay unlocking. Backgrounding stops voices and cancels delayed
previews; returning does not replay a backlog. Pause/scene transitions also clear
tails. The stream mixer is retained because the previous Web sample backend had
a documented dynamic-bus routing failure.

## Verification

`tools/test_tactile_audio.tscn` checks all stream bounds/headroom, distinct takes,
no immediate variation repeat, a 3,000-event burst, real pool priority preemption,
activation and background/resume cancellation. `tools/test_audio_settings.tscn`
continues to cover persistent preferences, mute/preview cancellation, fog,
settings geometry and paused match preservation. Audio signal measurements are
not a subjective listening claim; release evidence should distinguish live
gameplay recording, signal analysis and human listening.
