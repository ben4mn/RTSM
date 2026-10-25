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

A 55.04-second controlled native capture at an 844×390 viewport exercised paid
recruitment, natural house construction, gathering and staged 12-vs-12 combat.
The foreground lifecycle was explicitly bypassed only in this debug capture
fixture after two ordinary foreground attempts correctly paused on focus loss;
it is not a foreground/background or browser acceptance claim. The capture had
zero dropped frames and zero clipped PCM samples. Peak was 0.12564 (−18.02 dBFS),
full-recording RMS 0.007619. In 25.276 seconds of combat, 145 actual landed hits
produced 48 audible impact cues (1.90/second) and two attack warnings; peak voice
concurrency was two. The economy segment included paid recruitment completion,
house completion, eight construction taps and nineteen gathering cues. These
are objective mix/event results, not subjective listening. Physical speakers,
Safari and perceived timbral balance still require human/device review.

The corresponding 1280×720 controlled native run completed successfully with
57.675 seconds of PCM and no script errors, dropped frames or clipped samples.
Peak was 0.12613 (−17.98 dBFS), RMS 0.008098. Its 25.351-second battle generated
156 landed hits, 49 audible impacts (1.93/second), three attack warnings and one
death cue, with a peak of two simultaneous voices. Paid recruitment/house
completion, seven construction taps and twenty gathering cues were also
recorded. This has the same explicit foreground-lifecycle bypass and subjective
listening limitations as the phone-viewport controlled run.
