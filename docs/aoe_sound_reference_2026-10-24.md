# AoE II / IV references for Pocket Kingdoms sound

Research date: 24 October 2026. The useful influence is semantic clarity:
recognizable action feedback, sparse danger cues and a mix that leaves room for
decisions. Pocket Kingdoms keeps its warm illustrated scale and original sounds.
No Age of Empires asset, voice line, recording, melody or extracted game file is
copied or included.

## Evidence and limits

This research read publisher material and first-person developer explanations,
and located official gameplay references. It did **not** hear their audio.
The available audio-return tool previously rejected the gameplay WAV as
unsupported; browser playback is not auditory input to the agent. No perceived
similarity, preferred timbre, listening comfort or subjective A/B result is
claimed. The choices below are an explicit design inference from documented
behavior, backed by our source and event/signal checks.

Primary material consulted:

1. [AoE II DE, Update 35584, Audio section](https://www.ageofempires.com/news/aoe2de-update-35584/).
   The publisher documents selection versus failed-action feedback, revisions
   to attack warnings, and distinct buy/sell sounds. **Principle inferred:**
   tell the player what happened, especially when attention is elsewhere;
   one generic successful click cannot convey every result.
2. [AoE II DE, Update 153015, Audio section, 12 August 2025](https://www.ageofempires.com/news/age-of-empires-ii-definitive-edition-update-153015/).
   Selection/command sounds for hero units were made quieter and less frequent;
   chicken variation/frequency/volume were adjusted, while a specific attack
   effect was made more audible. **Principle inferred:** manage repeated sounds
   by event importance instead of making all activity louder.
3. [Lin Gardiner, The Music of Age of Empires IV: A Retrospective, 29 November 2024](https://www.supergmusic.com/the-music-of-age-of-empires-iv-a-retrospective/).
   This is the lead music designer's first-person account, not a publisher SFX
   specification. It describes civilization/age identity, changing density with
   combat state, controlled randomness and special age transitions. **Limited
   inference:** larger state changes deserve a distinct, coherent phrase.
   This does not establish the game's impact mix, alert waveform or cooldowns.
   Her linked Audiokinetic technical article returned HTTP 403 to this browser
   fetch and is not cited as independently read evidence.
4. [World's Edge / Relic, Age IV Accessibility Features](https://www.ageofempires.com/age-iv-accessibility/).
   The official page specifies separate master, music, speech and effects levels
   plus camera and text controls. **Principle inferred:** comfort controls are
   part of the sound design. Our master/world/interface-alert controls retain
   their persistent levels and mutes; we do not add inert music/voice sliders.
5. [World's Edge interview with audio director Todd Masten, 28 September 2020](https://www.ageofempires.com/news/interview-todd-masten/).
   Though mainly about AoE III, Masten explicitly describes AoE II DE's short
   civilization introductions and its recomposed soundtrack. This establishes
   an identity-at-transition reference, not a reason to play a musical jingle
   for every command. Civilization music would be a separate future project.

Actual official gameplay material located:

- [Age of Empires IV — 2v2 Showmatch, official Age of Empires channel, 28 October 2021](https://www.youtube.com/watch?v=5FV3XTxtQR0).
  The official description identifies a Relic balance-team match. It is an
  appropriate full-match reference for a human listening pass, with the caveat
  that broadcast commentary is not an isolated game mix. Only the published
  page/title/description were inspected here; no timestamped sonic observation
  is invented.
- [AoE II DE console gameplay material, official Age of Empires channel, 24 January 2023](https://www.youtube.com/watch?v=VMUmrwFJW5k).
  The official description discusses the controller adaptation. As above, this
  is a verified source to review, not a claim that its soundtrack was heard.

## Audit of the existing 18-bank palette

Source: `scripts/audio/tactile_palette.gd`, `scripts/managers/audio_manager.gd`,
and the damage/order/production hooks in `scripts/main/main.gd`.

| Event role | Current behavior | Decision |
| --- | --- | --- |
| Selection / interface | About 65 / 105 ms tactile taps; selection and click limits; duplicate gesture suppression | Keep short and soft. Three variants on frequent taps. |
| Move / attack orders | Different two-note contours, 250 / 265 ms; shared 180 ms order gate, individual 200 / 240 ms gates | Keep. Feedback follows accepted commands; it does not delay or automate the command. |
| Gathering / building labor | Material-like taps, shared 650 ms gate plus longer per-event limits | Keep. Continuous economy activity must leave room for tactical information. |
| Hits / deaths | Soft local effects, camera/fog filtering and shared 180 ms gate | Keep. Earlier actual battle captures had roughly 1.9 audible impacts/second despite many more landed hits. |
| Recruitment / completion | Ascending felt confirmations, higher priority than input clicks | Keep. They confirm completed state changes, not each queued slot. |
| Under attack | Initially the same felt instrument and first pitch as Move, with repeated notes; -6 dB, six-second audio cooldown, priority four | Change only its waveform to a rounded two-pulse wood/reed texture with a separate descending contour. |
| Age / victory / defeat | Stable, progressively longer cadences; outcomes have highest priority | Keep stable and rare; do not randomize the recognizable outcome. |

The palette has **18 banks total**. Frequent taps and order cues have three small
variations; important cadences have one stable take. There are eight world and
four interface voices, with two interface slots reserved for alerts. A strictly
higher-priority cue may replace a lower-priority cue. These are Pocket Kingdoms
parameters, not asserted Age of Empires parameters.

## Bounded follow-up

The warning remains 430 ms long and keeps its existing scheduler gain, six-second
cooldown, priority and ownership routing. A rounded 12 ms onset, two separated
pulses, quiet odd harmonic and short inharmonic wood resonance distinguish it
from the positive felt accents. This is original additive synthesis, not an
attempt to reproduce a particular AoE horn or bell. Actual playback still needs
human listening to establish how distinct and pleasant it feels on speakers.

Before touching the waveform, a new Main-scene regression passed nine checks:
canonical local visibility and genuine offscreen position, discarded routine
impact, real unit damage reaching the alert channel, burst suppression, enemy
ownership isolation, real building damage reaching the alert channel, and mute.
The same test runs after the change alongside the existing PCM/scheduler test.
The visual front tracker may further limit repeated warnings; this pass does
not change that layer or expose enemy information.

## Fast play and APM

Audio can help a player confirm an order and notice a threat while watching a
different part of the map. It does not itself create strategy or meaningful
actions per minute. Keep command acceptance immediate and preserve visible
feedback, hotkeys, group control and production management. Do not add a sound
for every APM statistic, reward empty repeated clicks, increase game speed, or
change costs, training times, combat intervals or networking to make the game
seem busier. Useful actions and controllable priorities should drive the pace.

## Follow-up verification

The original PCM/scheduler regression passed, as did all nine Main damage-routing
checks after the waveform change. A fresh 1280×720 controlled native capture
completed with 53.227 seconds of actual engine-mix PCM, zero dropped capture
frames and zero clipped samples. Peak was -19.38 dBFS; whole-recording RMS was
-42.09 dBFS. Its 24.697-second battle generated 143 real landed hits, 48 audible
impact cues (1.94/second) and two attack warnings. Peak concurrency was two.
The economy segment completed the paid recruit and House, with eight construction
and eighteen gathering cues. The battle screenshot was inspected: actual actors,
terrain and field HUD were visible with no pause modal.

Evidence is in the task's `outputs/audio-aoe-followup/`: `gameplay-mix.wav`,
`gameplay-audio.json`, `audio-analysis.json`, `economy.png` and `battle.png`.
As with the earlier fixture, its explicit debug-only offscreen capture mode
bypasses foreground pausing; this run recorded no focus changes. It uses a
custom 40-cap match, funded paid economy actions and free staged 12-versus-12
armies. It is not a normally paid 100-population match, browser audio proof or
subjective listening. Earlier recordings remain historical evidence, not
re-labeled proof of this revision. Physical-device, real mobile-browser playback
and perceived comparison with AoE II/IV remain unverified.
