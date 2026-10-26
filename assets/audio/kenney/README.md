# Kenney sound recordings in Pocket Kingdoms

Creator: **Kenney / Kenney Vleugels**. License: **Creative Commons Zero (CC0 1.0)**. The original package license notices are retained unchanged under `originals/<pack>/License.txt`. Attribution is optional under the supplied licenses; credit here and in release notes is intentional: **Sound effects by Kenney (kenney.nl), CC0; edited for Pocket Kingdoms.**

Verified on the creator's official pages and downloaded 2026-10-25:

| Pack | Official page | Download archive |
| --- | --- | --- |
| Impact Sounds 1.0 | https://kenney.nl/assets/impact-sounds | https://kenney.nl/media/pages/assets/impact-sounds/87b4ddecda-1677589768/kenney_impact-sounds.zip |
| Interface Sounds 1.0 | https://kenney.nl/assets/interface-sounds | https://kenney.nl/media/pages/assets/interface-sounds/fa43c1dd4d-1677589452/kenney_interface-sounds.zip |
| RPG Audio | https://kenney.nl/assets/rpg-audio | https://kenney.nl/media/pages/assets/rpg-audio/8e99002d76-1677590336/kenney_rpg-audio.zip |

License deed: https://creativecommons.org/publicdomain/zero/1.0/

Selected original Ogg files are unmodified. `manifest.json` maps every derived cue to its exact source and SHA-256 hash. `tools/build_sample_palette.py` reproducibly creates the 46 short mono 22.05kHz PCM variants (786,870 bytes total). Edits: resampling, mono fold-down, gentle 4.2kHz low-pass, 5ms onset/35ms tail fades, peak normalization to 0.48, selected pitch edits, and short recorded bell phrases. No speech, music, synthesized oscillators or noise is added. Source files are retained for audit but excluded from Godot importing with `.gdignore`.

The live manager uses six world voices plus four interface/alert voices. A shared 1.5-second work cooldown limits **all workers combined** to at most one gentle gather/build accent per 1.5 seconds. Work is quiet (-21 to -23 dB before master gain), visible/near-camera only, and combat can displace it. Two interface voices remain reserved for alerts; outcomes outrank recruitment. Each cue has two or three variants and cannot immediately repeat a take. All cues end within 1.18 seconds; nothing loops or queues during backgrounding.

`test_tactile_audio` now tests this exact live sample bank, PCM headroom/endpoints, nonrepetition, burst suppression, priorities, gesture unlock and lifecycle. Subjective native/Web listening remains part of integration review; passing these checks does not establish perceived quality.
