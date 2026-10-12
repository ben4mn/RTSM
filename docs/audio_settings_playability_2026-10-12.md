# Audio and settings pass — 12 October 2026

The pass replaces unrestricted one-shot players and a single mute switch with
bounded world/UI-alert channels and shared settings from the menu and Pause.
It preserves the running match while changing preferences.

## Changes

- Eighteen short procedural cues use wood, muted impact, metal and horn timbres.
  Selection, movement and attack orders differ; age advancement is confirmed only
  after successful payment. Own training/completion/outcomes and attack warnings
  use the alert channel. There is no music track or inert music setting.
- Eight world voices and four UI/alert voices are reused. Two UI voices remain
  available to alerts; per-event cooldowns suppress repetitive gathering and hits.
  World sounds require canonical human fog visibility and proximity to the camera.
  Hidden enemy harvesting, damage and deaths no longer disclose activity by sound.
- A static bus layout and stream playback avoid an observed Godot Web sample-bus
  routing failure. In the first Web export, dynamically adding buses produced a
  Master → World → UI → Master cycle. Sources started but the measured output was
  zero. The corrected export produced the intended signal.
- Audio, Controls, Display and Match tabs share a scrollable panel with 48-logical-
  pixel controls. Preferences cover master/world/UI-alert levels and mute,
  pan/zoom sensitivity, optional holds, three UI scales, reduced motion/flashes,
  clear circle/diamond player markers, opening guidance, difficulty, population
  and map seed. Match setup is explicitly labeled for the next skirmish.
- Preview respects volume/mute; Reset Defaults affects preferences and next-match
  setup. Sliders ignore wheel changes so scrolling does not alter volume. The
  browser Full screen control is hidden while settings occupy that space.

## Verified evidence

Evidence is under `output/evolution/mobile-playability-pass-20261012/`.
`web-audio-settings.webm` records actual browser output; the adjacent measurements
JSON contains context-state events and 50 ms RMS/peak samples. The short
`web-audio-preview.wav` is a playable excerpt. These were ordinary canvas contacts
in the actual exported game, without bypassing browser autoplay policy.

- Browser audio began suspended and entered running state after a real Settings
  click. Preview maximum RMS was 0.10513 and sample peak was 0.15460 at master 80%.
  At 40%, RMS was 0.05256 and peak 0.07730. Muted preview measured exactly zero;
  unmute restored the expected level. The recorded peaks did not clip.
- The recording includes selection/orders, nearby gathering and paid villager
  training. Population rose from four to five and the food purchase was visible.
  Silence followed Pause with no UI interaction and the transition back to menu.
  UI feedback remained available in Pause. A slider drag and scroll in settings
  returned to the same paused 00:44 match view with its Town Center selected.
- Actual Web screenshots cover 932×430 and 844×390, including Extra Large settings.
  Reload retained master 60%, Extra Large UI and reduced motion/flashes.
- `tools/test_audio_settings.tscn` checks all 12 combinations of those phone sizes,
  three scales and ordinary/notched safe areas across all four tabs, preferences
  save/reload/reset, real paused selection/camera preservation, hidden-source
  suppression, the 12-player bound, mute/preview cancellation and background
  lifecycle handlers. `test_phone_menu_layout.tscn` covers the updated menu flow.

## Limits

Signal capture is not subjective listening verification. The available audio
input tool explicitly reported that this model cannot receive audio input, so no
claim is made about perceived harshness, musical quality or physical speaker
balance. Construction, age advancement, match outcomes and a crowded battle are
source/structurally checked but were not all independently recorded in this
short browser audio session.

The automated browser did not emit `visibilitychange` when its tab/window was
backgrounded, even after focus emulation was disabled. Background cancellation is
therefore handler-tested, not accepted as a real phone/PWA background result.
A second check used native Chrome Guest through macOS UI and the unchanged
preview4 pack, with recording instrumentation added only to an isolated test
shell. Native Chrome reported “Audio playing”; maximum RMS was 0.105205 and peak
was 0.154602. Evidence is `native-web-audio-lifecycle.jsonl`. The Mac locked before
the actual native minimize action; the computer-use tool could not unlock it.
No native minimize/restore result is claimed. Neither the app inventory nor
`~/Applications/Chrome Apps.localized` contained an installed Pocket Kingdoms PWA.

Installed-PWA persistence, a physical phone, Safari audio and subjective listening
remain unverified. Public deployment verification is recorded in the main pass
report rather than inferred from this localhost export.
