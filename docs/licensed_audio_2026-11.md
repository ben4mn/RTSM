# Sound identity audio: sources, licences and processing (2026-11)

Every file under `assets/audio/identity/` is an edit of a recording released under **CC0 1.0** (public-domain dedication). Nothing here carries an attribution or share-alike obligation; the credits below are given by choice. No file was shipped whose licence could not be confirmed on its source page. The earlier Kenney palette is documented in `docs/licensed_audio_2026-10-25.md` and is unchanged.

**Listening quality is unverified.** The set was chosen from descriptions, titles, waveform envelopes and spectral measurements, and built and measured without anyone hearing it. Treat every track and cue as a candidate the owner can veto; removing one is a one-line change in `tools/audio/build_sound_identity.py` (effects, ambience) or `scripts/audio/music_director.gd` (playlists).

## How the licence was verified

- **OpenGameArt.org** entries: `tools/audio/fetch_sources.py` reads the licence names printed on the submission page and refuses any page that does not list CC0. The page as served and an extracted statement are stored beside each download in `.local/audio_src/<slug>/page.html` and `LICENSE_STATEMENT.txt` (outside the repository). `battle-sound-effects` is multi-licensed (CC-BY 3.0, CC-BY-SA 3.0, GPL 2.0/3.0, CC0); it is used under its CC0 option.
- **Freesound.org** items: `tools/audio/fetch_freesound.py` requires the page's single Creative Commons link to be the CC0 1.0 deed (a CC-BY item was used as a negative control and is refused), and stores the page and statement the same way. Original uploads need an account, so the file taken is Freesound's own public high-quality MP3 preview of the sound; the dedication covers the recording, and the preview is more than sufficient for a 32 kHz mono effect.
- **Kenney** recordings are reused from the originals already retained in `assets/audio/kenney/originals/` with their CC0 `License.txt`.
- Licence deed: https://creativecommons.org/publicdomain/zero/1.0/

`assets/audio/identity/manifest.json` maps every shipped file to each source file used (with SHA-256 of source and output), the segment, pitch, gain, delay and filters of every layer, and the build measurements. `assets/audio/identity/analysis.json` holds the independent ffmpeg measurements of the shipped files.

## Sources

| Source | Author | Page | Licence on page | Retrieved |
| --- | --- | --- | --- | --- |
| 100 CC0 SFX | rubberduck | https://opengameart.org/content/100-cc0-sfx | CC0 | 2026-11-09 |
| 20 Sword Sound Effects (Attacks and Clashes) | StarNinjas | https://opengameart.org/content/20-sword-sound-effects-attacks-and-clashes | CC0 | 2026-11-09 |
| 30 CC0 SFX loops | rubberduck | https://opengameart.org/content/30-cc0-sfx-loops | CC0 | 2026-11-09 |
| 75 CC0 breaking / falling / hit sfx | rubberduck | https://opengameart.org/content/75-cc0-breaking-falling-hit-sfx | CC0 | 2026-11-09 |
| 80 CC0 RPG SFX | rubberduck | https://opengameart.org/content/80-cc0-rpg-sfx | CC0 | 2026-11-09 |
| AMB Morning Sounds (Perfect Loop) | Kresiek The Furry | https://opengameart.org/content/amb-morning-sounds-perfect-loop | CC0 | 2026-11-09 |
| Ambient Bird Sounds | isaiah658 | https://opengameart.org/content/ambient-bird-sounds | CC0 | 2026-11-09 |
| Battle Sound Effects | artisticdude | https://opengameart.org/content/battle-sound-effects | CC-BY 3.0, CC-BY-SA 3.0, GPL 3.0, GPL 2.0, CC0 | 2026-11-09 |
| Blacksmith's Hammer | VishwaJai | https://opengameart.org/content/blacksmiths-hammer | CC0 | 2026-11-09 |
| Breaking Rock | themightyglider | https://opengameart.org/content/breaking-rock | CC0 | 2026-11-09 |
| Cave In | StarNinjas | https://opengameart.org/content/cave-in | CC0 | 2026-11-09 |
| Classic fanfare lick | fvcalderan | https://opengameart.org/content/classic-fanfare-lick | CC0 | 2026-11-09 |
| Fantasy Weapons and Apparel SFX Library | Vehicle | https://opengameart.org/content/fantasy-weapons-and-apparel-sfx-library | CC0 | 2026-11-09 |
| Horse_Whinny.wav | foxen10 | https://freesound.org/people/foxen10/sounds/149024/ | CC0 | 2026-11-09 |
| Arrow Impact | Twisted_Euphoria | https://freesound.org/people/Twisted_Euphoria/sounds/205938/ | CC0 | 2026-11-09 |
| Deep Horn | Vendarro | https://freesound.org/people/Vendarro/sounds/328541/ | CC0 | 2026-11-09 |
| Bow Release (Bow and Arrow) 3 | Ali_6868 | https://freesound.org/people/Ali_6868/sounds/384918/ | CC0 | 2026-11-09 |
| Battle_horn_1.wav | kirmm | https://freesound.org/people/kirmm/sounds/392180/ | CC0 | 2026-11-09 |
| Arrow Loose and Flyby | saturdaysoundguy | https://freesound.org/people/saturdaysoundguy/sounds/394180/ | CC0 | 2026-11-09 |
| G38-15-Perfect Horse Whinny.wav | craigsmith | https://freesound.org/people/craigsmith/sounds/437110/ | CC0 | 2026-11-09 |
| G38-16-Four Horse Snorts.wav | craigsmith | https://freesound.org/people/craigsmith/sounds/437111/ | CC0 | 2026-11-09 |
| Horse(snort)_3.wav | o_ciz | https://freesound.org/people/o_ciz/sounds/475483/ | CC0 | 2026-11-09 |
| R01-03-Catapult Launch and Hit Target.wav | craigsmith | https://freesound.org/people/craigsmith/sounds/479921/ | CC0 | 2026-11-09 |
| ARROW_WOOD_IMPACT_SINGLE_ARCHERY_01.wav | JoeDinesSound | https://freesound.org/people/JoeDinesSound/sounds/534956/ | CC0 | 2026-11-09 |
| Bow Impact | EminYILDIRIM | https://freesound.org/people/EminYILDIRIM/sounds/536066/ | CC0 | 2026-11-09 |
| war horn.wav | adharca | https://freesound.org/people/adharca/sounds/539956/ | CC0 | 2026-11-09 |
| Single Horse Galopp | D4XX | https://freesound.org/people/D4XX/sounds/564628/ | CC0 | 2026-11-09 |
| Church Bell.wav | MVMTech | https://freesound.org/people/MVMTech/sounds/569356/ | CC0 | 2026-11-09 |
| Old Church Bell (no noise) | igroglaz | https://freesound.org/people/igroglaz/sounds/633208/ | CC0 | 2026-11-09 |
| Arrow_Hit_1 | Mythmazter | https://freesound.org/people/Mythmazter/sounds/708223/ | CC0 | 2026-11-09 |
| building collapse / demolition | greyfeather | https://freesound.org/people/greyfeather/sounds/712918/ | CC0 | 2026-11-09 |
| TollBell.wav | daytripper | https://freesound.org/people/daytripper/sounds/73678/ | CC0 | 2026-11-09 |
| Church Bell, Treble | tomoan74 | https://freesound.org/people/tomoan74/sounds/748269/ | CC0 | 2026-11-09 |
| Hammer on Anvil | themightyglider | https://opengameart.org/content/hammer-on-anvil | CC0 | 2026-11-09 |
| Medieval: Battle | RandomMind | https://opengameart.org/content/medieval-battle | CC0 | 2026-11-09 |
| Medieval: Defeat Theme | RandomMind | https://opengameart.org/content/medieval-defeat-theme | CC0 | 2026-11-09 |
| Medieval: Exploration | RandomMind | https://opengameart.org/content/medieval-exploration | CC0 | 2026-11-09 |
| Medieval: King's Feast | RandomMind | https://opengameart.org/content/medieval-kings-feast | CC0 | 2026-11-09 |
| Medieval: Market Day | RandomMind | https://opengameart.org/content/medieval-market-day | CC0 | 2026-11-09 |
| Medieval: The Bard's Tale | RandomMind | https://opengameart.org/content/medieval-the-bards-tale | CC0 | 2026-11-09 |
| Medieval: The Old Tower Inn | RandomMind | https://opengameart.org/content/medieval-the-old-tower-inn | CC0 | 2026-11-09 |
| Medieval: Victory Theme | RandomMind | https://opengameart.org/content/medieval-victory-theme | CC0 | 2026-11-09 |
| Park ambiences | Thimras | https://opengameart.org/content/park-ambiences | CC0 | 2026-11-09 |
| RPG Sound Pack | artisticdude | https://opengameart.org/content/rpg-sound-pack | CC0 | 2026-11-09 |
| Tree Creaking | AntumDeluge | https://opengameart.org/content/tree-creaking | CC0 | 2026-11-09 |
| Trumpet Fanfare | gchoc | https://opengameart.org/content/trumpet-fanfare | CC0 | 2026-11-09 |
| Kenney Impact Sounds 1.0 | Kenney (Kenney Vleugels) | https://kenney.nl/assets/impact-sounds | CC0 | 2026-10-25 (retained originals) |
| Kenney Interface Sounds 1.0 | Kenney (Kenney Vleugels) | https://kenney.nl/assets/interface-sounds | CC0 | 2026-10-25 (retained originals) |
| Kenney RPG Audio | Kenney (Kenney Vleugels) | https://kenney.nl/assets/rpg-audio | CC0 | 2026-10-25 (retained originals) |

## Music (8 files, Ogg Vorbis, 32 kHz stereo)

All music is by **RandomMind** (OpenGameArt). Processing: leading and trailing digital silence removed, optional cut and fade as listed, one linear gain to the loudness target (no compression, limiting or EQ), re-encoded with libvorbis q0.3.

| File | Source track | Used for | One-line description (from the title, the author's note and measurements; not from listening) | Length | Integrated loudness | Peak | Size |
| --- | --- | --- | --- | --- | --- | --- | --- |
| `battle.ogg` | Medieval: Battle | battle (loops by self-crossfade) | Author: medieval battle track; loud and constant, the only tense piece. | 71 s | -18.0 LUFS | -4.5 dBFS | 541 kB |
| `menu_exploration.ogg` | Medieval: Exploration | main menu, and fifth in the peace playlist | Author: fits menu and/or exploration; the quietest, most even source. First 120 s with a 6 s fade. | 120 s | -20.2 LUFS | -1.9 dBFS | 784 kB |
| `peace_bards_tale.ogg` | Medieval: The Bard's Tale | peace playlist | Author calls it a fantasy track; quiet opening and close with a fuller middle section. | 150 s | -20.0 LUFS | -5.0 dBFS | 1020 kB |
| `peace_kings_feast.ogg` | Medieval: King's Feast | peace playlist | Feast theme by its title; steady level from start to finish. | 129 s | -20.0 LUFS | -5.1 dBFS | 920 kB |
| `peace_market_day.ogg` | Medieval: Market Day | peace playlist | Densest and loudest source (constant envelope), so it is mixed 1 LU lower; the first candidate to drop if it feels busy. | 135 s | -21.1 LUFS | -11.8 dBFS | 916 kB |
| `peace_old_tower_inn.ogg` | Medieval: The Old Tower Inn | peace playlist | Inn/tavern theme by its title; brightest spectrum of the set, moderate level with a gently rising envelope. | 97 s | -20.1 LUFS | -4.9 dBFS | 687 kB |
| `stinger_defeat.ogg` | Medieval: Defeat Theme | defeat result | Author: medieval/fantasy defeat theme; first 32 s with a 5 s fade. | 32 s | -18.0 LUFS | -7.8 dBFS | 216 kB |
| `stinger_victory.ogg` | Medieval: Victory Theme | victory result | Author: medieval victory track; 31 s, after which the menu theme returns. | 31 s | -17.1 LUFS | -5.7 dBFS | 219 kB |

## Ambience (4 seamless loops, Ogg Vorbis, 32 kHz mono)

| File | Sources | Processing | Length | Integrated loudness | Loop boundary (decoded file) |
| --- | --- | --- | --- | --- | --- |
| `day_bed.ogg` | AMB Morning Sounds (Perfect Loop) (Kresiek The Furry); Park ambiences (Thimras) | mono 32 kHz; high-pass; layers RMS-balanced; 3.0 s equal-power crossfade of the following material into the loop head; RMS normalised to -30 dBFS; Vorbis q2 | 30 s | -29.8 LUFS | wrap step 0.0033 vs typical step 0.0422; RMS -32.7 dB before end, -33.0 dB after start |
| `forest.ogg` | Ambient Bird Sounds (isaiah658); Park ambiences (Thimras) | mono 32 kHz; high-pass; layers RMS-balanced; 2.5 s equal-power crossfade of the following material into the loop head; RMS normalised to -30 dBFS; Vorbis q2 | 22 s | -26.8 LUFS | wrap step 0.0042 vs typical step 0.0966; RMS -41.5 dB before end, -42.0 dB after start |
| `town.ogg` | Hammer on Anvil (themightyglider); Blacksmith's Hammer (VishwaJai); 30 CC0 SFX loops (rubberduck); 100 CC0 SFX (rubberduck); 80 CC0 RPG SFX (rubberduck); 75 CC0 breaking / falling / hit sfx (rubberduck); RPG Sound Pack (artisticdude) | mono 32 kHz; events placed on a silent 24 s timeline; 3.8 kHz low-pass; RMS normalised to -34 dBFS; Vorbis q2 | 24 s | -29.8 LUFS | silent at both ends by construction |
| `water.ogg` | Park ambiences (Thimras) | mono 32 kHz; high-pass; layers RMS-balanced; 2.5 s equal-power crossfade of the following material into the loop head; RMS normalised to -30 dBFS; Vorbis q2 | 20 s | -28.8 LUFS | wrap step 0.0118 vs typical step 0.0437; RMS -30.0 dB before end, -30.0 dB after start |

## Effects (124 files, 32 kHz mono PCM16 sources, imported by Godot as QOA)

Processing for every effect: source decoded to mono 32 kHz; each layer cut to the listed segment, pitch-shifted by resampling where listed, filtered where listed, faded, peak-normalised and mixed at its listed gain and delay; the mix is trimmed, faded and normalised to its loudness class; a soft knee holds the peak under the class ceiling. No oscillators, noise generators or other synthesis are used. Exact per-layer values are in `manifest.json`.

| Cue family | Variants | Class | Length | Peak (dBFS) | Sources |
| --- | --- | --- | --- | --- | --- |
| `age_up_fanfare_NN.wav` | 2 | alert | 4.82-4.88 s | -2.6 to -2.2 | Trumpet Fanfare (gchoc); Old Church Bell (no noise) (igroglaz); TollBell.wav (daytripper); Classic fanfare lick (fvcalderan); Church Bell.wav (MVMTech) |
| `alert_army_NN.wav` | 2 | alert | 2.51-2.52 s | -6.1 to -2.9 | Battle_horn_1.wav (kirmm); war horn.wav (adharca) |
| `alert_town_NN.wav` | 2 | alert | 1.86-1.98 s | -3.6 to -2.9 | Church Bell, Treble (tomoan74); Old Church Bell (no noise) (igroglaz) |
| `arrow_impact_NN.wav` | 4 | combat | 0.22-0.32 s | -7.6 to -3.0 | Arrow_Hit_1 (Mythmazter); ARROW_WOOD_IMPACT_SINGLE_ARCHERY_01.wav (JoeDinesSound); Arrow Impact (Twisted_Euphoria); Bow Impact (EminYILDIRIM) |
| `bow_release_NN.wav` | 4 | combat | 0.23-0.39 s | -10.3 to -3.0 | Battle Sound Effects (artisticdude); Bow Release (Bow and Arrow) 3 (Ali_6868); Arrow Loose and Flyby (saturdaysoundguy) |
| `building_collapse_NN.wav` | 3 | heavy | 2.77-2.92 s | -6.8 to -3.4 | building collapse / demolition (greyfeather); 75 CC0 breaking / falling / hit sfx (rubberduck); Cave In (StarNinjas) |
| `building_complete_chime_NN.wav` | 2 | event | 1.08-1.18 s | -6.2 to -4.7 | 100 CC0 SFX (rubberduck); Kenney Interface Sounds 1.0; 75 CC0 breaking / falling / hit sfx (rubberduck) |
| `building_hit_NN.wav` | 4 | combat | 0.14-0.34 s | -11.1 to -6.7 | 75 CC0 breaking / falling / hit sfx (rubberduck); 80 CC0 RPG SFX (rubberduck); 100 CC0 SFX (rubberduck); Kenney Impact Sounds 1.0 |
| `cavalry_hit_NN.wav` | 3 | combat | 0.57-0.66 s | -6.8 to -4.2 | Single Horse Galopp (D4XX); 20 Sword Sound Effects (Attacks and Clashes) (StarNinjas); 75 CC0 breaking / falling / hit sfx (rubberduck); 100 CC0 SFX (rubberduck); Kenney Impact Sounds 1.0 |
| `death_cavalry_NN.wav` | 3 | death | 1.16-1.43 s | -8.1 to -6.5 | Horse_Whinny.wav (foxen10); 75 CC0 breaking / falling / hit sfx (rubberduck); G38-15-Perfect Horse Whinny.wav (craigsmith); 100 CC0 SFX (rubberduck) |
| `death_infantry_NN.wav` | 3 | death | 0.48-0.54 s | -7.5 to -4.4 | 75 CC0 breaking / falling / hit sfx (rubberduck); RPG Sound Pack (artisticdude); 100 CC0 SFX (rubberduck) |
| `death_siege_NN.wav` | 3 | death | 0.56-0.77 s | -4.4 to -4.0 | 75 CC0 breaking / falling / hit sfx (rubberduck) |
| `death_soft_NN.wav` | 3 | death | 0.29-0.52 s | -10.7 to -7.8 | RPG Sound Pack (artisticdude); 75 CC0 breaking / falling / hit sfx (rubberduck); Kenney RPG Audio; 100 CC0 SFX (rubberduck); Kenney Impact Sounds 1.0 |
| `melee_hit_NN.wav` | 6 | combat | 0.36-0.59 s | -5.2 to -3.0 | 20 Sword Sound Effects (Attacks and Clashes) (StarNinjas); 75 CC0 breaking / falling / hit sfx (rubberduck); Kenney Impact Sounds 1.0; 100 CC0 SFX (rubberduck); Fantasy Weapons and Apparel SFX Library (Vehicle) |
| `order_archer_NN.wav` | 3 | ack | 0.47-0.50 s | -6.5 to -6.0 | Fantasy Weapons and Apparel SFX Library (Vehicle) |
| `order_attack_archer_NN.wav` | 2 | ack | 0.60-0.60 s | -6.6 to -6.1 | Fantasy Weapons and Apparel SFX Library (Vehicle) |
| `order_attack_cavalry_NN.wav` | 2 | ack | 0.72-0.76 s | -9.7 to -8.7 | Horse_Whinny.wav (foxen10); Single Horse Galopp (D4XX); G38-16-Four Horse Snorts.wav (craigsmith) |
| `order_attack_melee_NN.wav` | 3 | ack | 0.29-0.33 s | -10.7 to -9.1 | RPG Sound Pack (artisticdude) |
| `order_attack_siege_NN.wav` | 2 | ack | 0.53-0.66 s | -6.0 to -6.0 | Tree Creaking (AntumDeluge); 80 CC0 RPG SFX (rubberduck) |
| `order_attack_villager_NN.wav` | 2 | ack | 0.45-0.45 s | -6.5 to -6.0 | Fantasy Weapons and Apparel SFX Library (Vehicle) |
| `order_cavalry_NN.wav` | 3 | ack | 0.52-0.54 s | -9.7 to -6.6 | Single Horse Galopp (D4XX); 80 CC0 RPG SFX (rubberduck); Horse(snort)_3.wav (o_ciz) |
| `order_infantry_NN.wav` | 3 | ack | 0.36-0.43 s | -7.9 to -6.0 | Fantasy Weapons and Apparel SFX Library (Vehicle); RPG Sound Pack (artisticdude) |
| `order_siege_NN.wav` | 2 | ack | 0.79-0.87 s | -10.4 to -10.3 | 30 CC0 SFX loops (rubberduck); Tree Creaking (AntumDeluge); 80 CC0 RPG SFX (rubberduck) |
| `order_villager_NN.wav` | 3 | ack | 0.36-0.36 s | -10.0 to -6.5 | Fantasy Weapons and Apparel SFX Library (Vehicle); RPG Sound Pack (artisticdude) |
| `research_complete_NN.wav` | 2 | event | 1.24-1.30 s | -2.8 to -2.5 | 80 CC0 RPG SFX (rubberduck); 100 CC0 SFX (rubberduck); Kenney Interface Sounds 1.0 |
| `sacred_captured_NN.wav` | 2 | alert | 2.55-2.87 s | -4.1 to -3.1 | Old Church Bell (no noise) (igroglaz); Church Bell, Treble (tomoan74); 100 CC0 SFX (rubberduck) |
| `sacred_lost_NN.wav` | 1 | alert | 2.48-2.48 s | -2.6 to -2.6 | 100 CC0 SFX (rubberduck); Deep Horn (Vendarro) |
| `select_archer_NN.wav` | 3 | ack | 0.31-0.50 s | -7.3 to -6.1 | Fantasy Weapons and Apparel SFX Library (Vehicle) |
| `select_archery_range_NN.wav` | 2 | building | 0.34-0.43 s | -11.3 to -11.0 | Battle Sound Effects (artisticdude); Bow Impact (EminYILDIRIM); Bow Release (Bow and Arrow) 3 (Ali_6868); ARROW_WOOD_IMPACT_SINGLE_ARCHERY_01.wav (JoeDinesSound) |
| `select_barracks_NN.wav` | 2 | building | 0.43-0.54 s | -12.0 to -6.3 | RPG Sound Pack (artisticdude); Fantasy Weapons and Apparel SFX Library (Vehicle) |
| `select_blacksmith_NN.wav` | 2 | building | 0.65-0.95 s | -10.6 to -8.1 | Hammer on Anvil (themightyglider); Blacksmith's Hammer (VishwaJai) |
| `select_cavalry_NN.wav` | 3 | ack | 0.41-0.46 s | -9.7 to -7.2 | G38-16-Four Horse Snorts.wav (craigsmith); Horse(snort)_3.wav (o_ciz) |
| `select_farm_NN.wav` | 2 | building | 0.32-0.36 s | -7.9 to -6.2 | 80 CC0 RPG SFX (rubberduck); RPG Sound Pack (artisticdude); Kenney RPG Audio |
| `select_house_NN.wav` | 2 | building | 0.27-0.32 s | -8.2 to -8.0 | 100 CC0 SFX (rubberduck) |
| `select_infantry_NN.wav` | 3 | ack | 0.34-0.40 s | -8.6 to -6.5 | RPG Sound Pack (artisticdude) |
| `select_resource_camp_NN.wav` | 2 | building | 0.49-0.50 s | -9.2 to -6.1 | Kenney Impact Sounds 1.0; 80 CC0 RPG SFX (rubberduck) |
| `select_siege_NN.wav` | 3 | ack | 0.34-0.53 s | -6.0 to -6.0 | Tree Creaking (AntumDeluge); 80 CC0 RPG SFX (rubberduck) |
| `select_siege_workshop_NN.wav` | 2 | building | 0.80-0.86 s | -8.3 to -7.4 | 30 CC0 SFX loops (rubberduck); 100 CC0 SFX (rubberduck); 75 CC0 breaking / falling / hit sfx (rubberduck) |
| `select_stable_NN.wav` | 2 | building | 0.79-0.90 s | -10.1 to -8.9 | G38-16-Four Horse Snorts.wav (craigsmith) |
| `select_town_center_NN.wav` | 2 | building | 0.86-0.88 s | -10.1 to -9.5 | Church Bell, Treble (tomoan74) |
| `select_villager_NN.wav` | 3 | ack | 0.22-0.29 s | -6.3 to -6.2 | RPG Sound Pack (artisticdude); Kenney RPG Audio |
| `select_watch_tower_NN.wav` | 2 | building | 0.61-0.69 s | -6.6 to -6.3 | 100 CC0 SFX (rubberduck); RPG Sound Pack (artisticdude) |
| `siege_impact_NN.wav` | 3 | heavy | 0.78-1.04 s | -4.7 to -3.3 | Breaking Rock (themightyglider); 75 CC0 breaking / falling / hit sfx (rubberduck); 100 CC0 SFX (rubberduck); 80 CC0 RPG SFX (rubberduck) |
| `siege_launch_NN.wav` | 3 | heavy | 0.91-1.01 s | -5.8 to -3.5 | Tree Creaking (AntumDeluge); Battle Sound Effects (artisticdude); 75 CC0 breaking / falling / hit sfx (rubberduck); R01-03-Catapult Launch and Hit Target.wav (craigsmith) |
| `town_bell_NN.wav` | 2 | alert | 3.09-4.17 s | -5.2 to -4.8 | TollBell.wav (daytripper) |
| `trained_military_NN.wav` | 2 | event | 0.51-0.71 s | -2.8 to -2.7 | RPG Sound Pack (artisticdude); Kenney Interface Sounds 1.0 |
| `trained_villager_NN.wav` | 2 | event | 0.35-0.51 s | -7.8 to -6.1 | RPG Sound Pack (artisticdude); Kenney Interface Sounds 1.0 |
| `villager_hit_NN.wav` | 3 | combat | 0.25-0.34 s | -4.9 to -3.4 | 75 CC0 breaking / falling / hit sfx (rubberduck); RPG Sound Pack (artisticdude); Kenney Impact Sounds 1.0; 100 CC0 SFX (rubberduck) |

## Loudness targets

| Group | Target | Ceiling | Why |
| --- | --- | --- | --- |
| Music: peace, menu | -20 LUFS integrated (Market Day -21) | no limiting; gain backed off if peak would pass -1.5 dBFS | Sits under effects at the default 50% Music slider |
| Music: battle / victory / defeat | -18 / -17 / -18 LUFS | same | Battle and results should lift above the peace bed |
| Ambience loops | -30 dBFS RMS (town -34) | clip guard at -3 dBFS | A bed, further trimmed -7 to -11 dB per layer at run time |
| Effects `alert` (fanfare, alarms, bells, Sacred Site) | -17 dBFS active RMS | -2 dBFS | Must read over music and battle |
| Effects `event` (trained, complete, research) | -18 dBFS active RMS | -2.5 dBFS | Positive confirmations |
| Effects `heavy` (siege, collapse) | -18 dBFS active RMS | -2.5 dBFS | Weight |
| Effects `combat` (melee, arrows, cavalry, building hits) | -20 dBFS active RMS | -3 dBFS | Many overlap |
| Effects `death` | -21 dBFS active RMS | -4 dBFS | Present, never dominant |
| Effects `ack`, `building` (selection and orders) | -24 dBFS active RMS | -6 dBFS | Heard on every tap; must stay pleasant |

"Active RMS" is the RMS of the 20 ms frames within 20 dB of the loudest frame, which is meaningful for sounds too short for a gated EBU R128 measurement. Measured spread per class is within about 1.5 dB of target; per-cue run-time gains, random level/pitch spread, cooldowns and voice limits are in the `IDENTITY` table of `scripts/managers/audio_manager.gd`.

## Verification performed (and not performed)

- `tools/audio/verify_sound_identity.py` decodes each shipped file with ffmpeg and checks duration, sample peak, EBU R128 integrated and maximum momentary loudness, head/tail silence, and for loops the wrap-around step against the typical sample step plus the level either side of the boundary. All 136 files pass (peak under -0.9 dBFS; effects start within 20 ms and end within 120 ms of audible signal; loop wrap steps are under 0.3x a typical step and level differences under 1 dB).
- Source sizes: music 5306 kB, ambience 594 kB, effects 6599 kB as PCM (about a fifth of that once imported as QOA). The exported `.pck` grew by about 8.0 MB.
- `tools/test_sound_identity` exercises cue resolution, voice bounds, the battle-music hysteresis and the gesture/mute/background lifecycle against a real match scene.
- **Not verified:** how any of it sounds. In particular the layered cues (fanfare plus bells, alarm bell triplets, cavalry hooves plus steel, siege launch) are assembled from separate recordings whose pitch and timbre relationships were never auditioned, and loop seams are verified numerically, not by ear.

## Rebuilding

```
python tools/audio/fetch_sources.py <audio_src>      # then unpack each zip to <audio_src>/_x/<slug>/<archive name>/
python tools/audio/fetch_freesound.py <audio_src>
python tools/audio/build_sound_identity.py <audio_src> <ffmpeg>
python tools/audio/verify_sound_identity.py <ffmpeg>
python tools/audio/write_provenance_doc.py
```

Godot `.import` files for the effects set `compress/mode=2` (QOA); the ambience loops are also marked looping at run time.
