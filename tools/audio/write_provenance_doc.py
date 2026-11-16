"""Regenerate docs/licensed_audio_2026-11.md from the sound-identity manifest and analysis.

Usage: python tools/audio/write_provenance_doc.py
"""
from pathlib import Path
import json

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "assets/audio/identity"
manifest = json.loads((OUT / "manifest.json").read_text(encoding="utf-8"))
analysis = json.loads((OUT / "analysis.json").read_text(encoding="utf-8"))
sources = manifest["sources"]
KENNEY = {
    "kenney-impact": ("Impact Sounds 1.0", "https://kenney.nl/assets/impact-sounds"),
    "kenney-interface": ("Interface Sounds 1.0", "https://kenney.nl/assets/interface-sounds"),
    "kenney-rpg": ("RPG Audio", "https://kenney.nl/assets/rpg-audio"),
}
TRACKS = {
    "peace_old_tower_inn": ("Medieval: The Old Tower Inn", "peace playlist", "Inn/tavern theme by its title; brightest spectrum of the set, moderate level with a gently rising envelope."),
    "peace_bards_tale": ("Medieval: The Bard's Tale", "peace playlist", "Author calls it a fantasy track; quiet opening and close with a fuller middle section."),
    "peace_kings_feast": ("Medieval: King's Feast", "peace playlist", "Feast theme by its title; steady level from start to finish."),
    "peace_market_day": ("Medieval: Market Day", "peace playlist", "Densest and loudest source (constant envelope), so it is mixed 1 LU lower; the first candidate to drop if it feels busy."),
    "menu_exploration": ("Medieval: Exploration", "main menu, and fifth in the peace playlist", "Author: fits menu and/or exploration; the quietest, most even source. First 120 s with a 6 s fade."),
    "battle": ("Medieval: Battle", "battle (loops by self-crossfade)", "Author: medieval battle track; loud and constant, the only tense piece."),
    "stinger_victory": ("Medieval: Victory Theme", "victory result", "Author: medieval victory track; 31 s, after which the menu theme returns."),
    "stinger_defeat": ("Medieval: Defeat Theme", "defeat result", "Author: medieval/fantasy defeat theme; first 32 s with a 5 s fade."),
}


def source_names(record: dict) -> list[str]:
    names: list[str] = []
    for item in record["layers"]:
        for slug in item.get("sources", [item.get("source")]):
            if slug not in names:
                names.append(slug)
    return names


def short(slug: str) -> str:
    if slug in KENNEY:
        return "Kenney " + KENNEY[slug][0]
    info = sources[slug]
    return "%s (%s)" % (info["title"].replace("|", "/"), info["author"])


lines: list[str] = []
add = lines.append
add("# Sound identity audio: sources, licences and processing (2026-11)")
add("")
add("Every file under `assets/audio/identity/` is an edit of a recording released under **CC0 1.0** (public-domain dedication). Nothing here carries an attribution or share-alike obligation; the credits below are given by choice. No file was shipped whose licence could not be confirmed on its source page. The earlier Kenney palette is documented in `docs/licensed_audio_2026-10-25.md` and is unchanged.")
add("")
add("**Listening quality is unverified.** The set was chosen from descriptions, titles, waveform envelopes and spectral measurements, and built and measured without anyone hearing it. Treat every track and cue as a candidate the owner can veto; removing one is a one-line change in `tools/audio/build_sound_identity.py` (effects, ambience) or `scripts/audio/music_director.gd` (playlists).")
add("")
add("## How the licence was verified")
add("")
add("- **OpenGameArt.org** entries: `tools/audio/fetch_sources.py` reads the licence names printed on the submission page and refuses any page that does not list CC0. The page as served and an extracted statement are stored beside each download in `.local/audio_src/<slug>/page.html` and `LICENSE_STATEMENT.txt` (outside the repository). `battle-sound-effects` is multi-licensed (CC-BY 3.0, CC-BY-SA 3.0, GPL 2.0/3.0, CC0); it is used under its CC0 option.")
add("- **Freesound.org** items: `tools/audio/fetch_freesound.py` requires the page's single Creative Commons link to be the CC0 1.0 deed (a CC-BY item was used as a negative control and is refused), and stores the page and statement the same way. Original uploads need an account, so the file taken is Freesound's own public high-quality MP3 preview of the sound; the dedication covers the recording, and the preview is more than sufficient for a 32 kHz mono effect.")
add("- **Kenney** recordings are reused from the originals already retained in `assets/audio/kenney/originals/` with their CC0 `License.txt`.")
add("- Licence deed: https://creativecommons.org/publicdomain/zero/1.0/")
add("")
add("`assets/audio/identity/manifest.json` maps every shipped file to each source file used (with SHA-256 of source and output), the segment, pitch, gain, delay and filters of every layer, and the build measurements. `assets/audio/identity/analysis.json` holds the independent ffmpeg measurements of the shipped files.")
add("")
add("## Sources")
add("")
add("| Source | Author | Page | Licence on page | Retrieved |")
add("| --- | --- | --- | --- | --- |")
for slug, info in sources.items():
    add("| %s | %s | %s | %s | %s |" % (info["title"].replace("|", "/"), info["author"].replace("&amp;", "&"), info["url"], ", ".join(info["licences_on_page"]), info["retrieved"]))
for slug, (name, url) in KENNEY.items():
    add("| Kenney %s | Kenney (Kenney Vleugels) | %s | CC0 | 2026-10-25 (retained originals) |" % (name, url))
add("")
add("## Music (8 files, Ogg Vorbis, 32 kHz stereo)")
add("")
add("All music is by **RandomMind** (OpenGameArt). Processing: leading and trailing digital silence removed, optional cut and fade as listed, one linear gain to the loudness target (no compression, limiting or EQ), re-encoded with libvorbis q0.3.")
add("")
add("| File | Source track | Used for | One-line description (from the title, the author's note and measurements; not from listening) | Length | Integrated loudness | Peak | Size |")
add("| --- | --- | --- | --- | --- | --- | --- | --- |")
for rel, record in manifest["files"].items():
    if record["kind"] != "music":
        continue
    key = Path(rel).stem
    title, use, description = TRACKS[key]
    a = analysis[rel]
    add("| `%s` | %s | %s | %s | %.0f s | %.1f LUFS | %.1f dBFS | %d kB |" % (Path(rel).name, title, use, description, a["seconds"], a["integrated_lufs"], a["peak_dbfs"], a["bytes"] // 1000))
add("")
add("## Ambience (4 seamless loops, Ogg Vorbis, 32 kHz mono)")
add("")
add("| File | Sources | Processing | Length | Integrated loudness | Loop boundary (decoded file) |")
add("| --- | --- | --- | --- | --- | --- |")
for rel, record in manifest["files"].items():
    if record["kind"] != "ambience":
        continue
    a = analysis[rel]
    seam = "wrap step %.4f vs typical step %.4f; RMS %.1f dB before end, %.1f dB after start" % (a["loop_wrap_step"], a["loop_typical_step_p99"], a["loop_rms_before_end_db"], a["loop_rms_after_start_db"])
    if a["loop_rms_before_end_db"] < -70:
        seam = "silent at both ends by construction"
    add("| `%s` | %s | %s | %.0f s | %.1f LUFS | %s |" % (Path(rel).name, "; ".join(short(s) for s in source_names(record)), record["processing"], a["seconds"], a["integrated_lufs"], seam))
add("")
add("## Effects (124 files, 32 kHz mono PCM16 sources, imported by Godot as QOA)")
add("")
add("Processing for every effect: source decoded to mono 32 kHz; each layer cut to the listed segment, pitch-shifted by resampling where listed, filtered where listed, faded, peak-normalised and mixed at its listed gain and delay; the mix is trimmed, faded and normalised to its loudness class; a soft knee holds the peak under the class ceiling. No oscillators, noise generators or other synthesis are used. Exact per-layer values are in `manifest.json`.")
add("")
add("| Cue family | Variants | Class | Length | Peak (dBFS) | Sources |")
add("| --- | --- | --- | --- | --- | --- |")
families: dict[str, list] = {}
for rel, record in manifest["files"].items():
    if record["kind"] == "sfx":
        families.setdefault(record["cue"], []).append((rel, record))
for cue, items in families.items():
    names: list[str] = []
    for _, record in items:
        for slug in source_names(record):
            if slug not in names:
                names.append(slug)
    seconds = [analysis[rel]["seconds"] for rel, _ in items]
    peaks = [analysis[rel]["peak_dbfs"] for rel, _ in items]
    add("| `%s_NN.wav` | %d | %s | %.2f-%.2f s | %.1f to %.1f | %s |" % (cue, len(items), items[0][1]["loudness_class"], min(seconds), max(seconds), min(peaks), max(peaks), "; ".join(short(s) for s in names)))
add("")
add("## Loudness targets")
add("")
add("| Group | Target | Ceiling | Why |")
add("| --- | --- | --- | --- |")
add("| Music: peace, menu | -20 LUFS integrated (Market Day -21) | no limiting; gain backed off if peak would pass -1.5 dBFS | Sits under effects at the default 50% Music slider |")
add("| Music: battle / victory / defeat | -18 / -17 / -18 LUFS | same | Battle and results should lift above the peace bed |")
add("| Ambience loops | -30 dBFS RMS (town -34) | clip guard at -3 dBFS | A bed, further trimmed -7 to -11 dB per layer at run time |")
add("| Effects `alert` (fanfare, alarms, bells, Sacred Site) | -17 dBFS active RMS | -2 dBFS | Must read over music and battle |")
add("| Effects `event` (trained, complete, research) | -18 dBFS active RMS | -2.5 dBFS | Positive confirmations |")
add("| Effects `heavy` (siege, collapse) | -18 dBFS active RMS | -2.5 dBFS | Weight |")
add("| Effects `combat` (melee, arrows, cavalry, building hits) | -20 dBFS active RMS | -3 dBFS | Many overlap |")
add("| Effects `death` | -21 dBFS active RMS | -4 dBFS | Present, never dominant |")
add("| Effects `ack`, `building` (selection and orders) | -24 dBFS active RMS | -6 dBFS | Heard on every tap; must stay pleasant |")
add("")
add("\"Active RMS\" is the RMS of the 20 ms frames within 20 dB of the loudest frame, which is meaningful for sounds too short for a gated EBU R128 measurement. Measured spread per class is within about 1.5 dB of target; per-cue run-time gains, random level/pitch spread, cooldowns and voice limits are in the `IDENTITY` table of `scripts/managers/audio_manager.gd`.")
add("")
add("## Verification performed (and not performed)")
add("")
total = sum(a["bytes"] for a in analysis.values())
add("- `tools/audio/verify_sound_identity.py` decodes each shipped file with ffmpeg and checks duration, sample peak, EBU R128 integrated and maximum momentary loudness, head/tail silence, and for loops the wrap-around step against the typical sample step plus the level either side of the boundary. All %d files pass (peak under -0.9 dBFS; effects start within 20 ms and end within 120 ms of audible signal; loop wrap steps are under 0.3x a typical step and level differences under 1 dB)." % len(analysis))
add("- Source sizes: music %d kB, ambience %d kB, effects %d kB as PCM (about a fifth of that once imported as QOA). The exported `.pck` grew by about 8.0 MB." % (sum(a["bytes"] for a in analysis.values() if a["kind"] == "music") // 1000, sum(a["bytes"] for a in analysis.values() if a["kind"] == "ambience") // 1000, sum(a["bytes"] for a in analysis.values() if a["kind"] == "sfx") // 1000))
add("- `tools/test_sound_identity` exercises cue resolution, voice bounds, the battle-music hysteresis and the gesture/mute/background lifecycle against a real match scene.")
add("- **Not verified:** how any of it sounds. In particular the layered cues (fanfare plus bells, alarm bell triplets, cavalry hooves plus steel, siege launch) are assembled from separate recordings whose pitch and timbre relationships were never auditioned, and loop seams are verified numerically, not by ear.")
add("")
add("## Rebuilding")
add("")
add("```")
add("python tools/audio/fetch_sources.py <audio_src>      # then unpack each zip to <audio_src>/_x/<slug>/<archive name>/")
add("python tools/audio/fetch_freesound.py <audio_src>")
add("python tools/audio/build_sound_identity.py <audio_src> <ffmpeg>")
add("python tools/audio/verify_sound_identity.py <ffmpeg>")
add("python tools/audio/write_provenance_doc.py")
add("```")
add("")
add("Godot `.import` files for the effects set `compress/mode=2` (QOA); the ambience loops are also marked looping at run time.")
add("")
(ROOT / "docs/licensed_audio_2026-11.md").write_text("\n".join(lines), encoding="utf-8", newline="\n")
print("wrote docs/licensed_audio_2026-11.md", len(lines), "lines; total bytes", total)
