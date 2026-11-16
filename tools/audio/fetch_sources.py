"""Download the CC0 source audio used by tools/audio/build_sound_identity.py.

Every entry is an OpenGameArt.org submission whose page states CC0, or an official
Kenney.nl CC0 pack. For each source this saves, OUTSIDE the repository:
  <dest>/<slug>/page.html              the submission page as served (licence evidence)
  <dest>/<slug>/LICENSE_STATEMENT.txt  extracted licence names, author, URL, retrieval date
  <dest>/<slug>/<file>                 the audio file or archive of audio
and writes <dest>/sources.json with SHA-256 hashes. Zip archives must then be unpacked
to <dest>/_x/<slug>/<archive name without extension>/ (the build script looks there). A source whose page does not list
CC0 among its licences is refused. Only audio files and archives are fetched.

Usage: python tools/audio/fetch_sources.py <dest-dir>
"""
from pathlib import Path
import datetime
import hashlib
import html
import json
import re
import sys
import urllib.parse
import urllib.request

OGA = "https://opengameart.org/content/"
# slug -> list of file basenames to download from that page (exact match on the page's links)
SOURCES = {
    # --- music, all by RandomMind ---
    "medieval-the-old-tower-inn": ["The_Old_Tower_Inn.mp3"],
    "medieval-the-bards-tale": ["The_Bards_Tale.mp3"],
    "medieval-market-day": ["Market_Day.mp3"],
    "medieval-kings-feast": ["Kings_Feast.mp3"],
    "medieval-exploration": ["Exploration.mp3"],
    "medieval-battle": ["battle_7.mp3"],
    "medieval-victory-theme": ["victory.wav"],
    "medieval-defeat-theme": ["defeat.wav"],
    # --- ambience ---
    "amb-morning-sounds-perfect-loop": ["amb_morning.ogg"],
    "park-ambiences": ["park_ambience_birds.wav", "park_ambience_river.wav", "park_ambience_wind.wav"],
    "ambient-bird-sounds": ["birds-isaiah658.ogg"],
    "30-cc0-sfx-loops": ["sfx_loops.zip"],
    # --- effects ---
    "rpg-sound-pack": ["rpg_sound_pack.zip"],
    "swishes-sound-pack": ["swishes.zip"],
    "battle-sound-effects": ["battle_sound_effects_0.zip"],
    "fantasy-weapons-and-apparel-sfx-library": ["weapons-apparel.zip"],
    "20-sword-sound-effects-attacks-and-clashes": ["sword_-_starninjas_1.zip", "sword_clash_-_starninjas_0.zip"],
    "75-cc0-breaking-falling-hit-sfx": ["sfx_breaking_and_falling.zip"],
    "80-cc0-rpg-sfx": ["80-CC0-RPG-SFX_0.zip"],
    "100-cc0-sfx": ["100-CC0-SFX_0.zip"],
    "trumpet-fanfare": ["castlefanfare.ogg"],
    "classic-fanfare-lick": ["fanfare_3.ogg"],
    "cave-in": ["cave_in_-_starninjas.ogg"],
    "breaking-rock": ["rock_break.ogg"],
    "hammer-on-anvil": ["forger.ogg"],
    "blacksmiths-hammer": ["blacksmithhammer.wav"],
    "tree-creaking": ["tree_creak.flac"],
}
EXTRA = [s for s in sys.argv[2:]]
ALLOWED = (".zip", ".7z", ".ogg", ".wav", ".mp3", ".flac")
AGENT = {"User-Agent": "Mozilla/5.0 (asset-licence-check)"}


def fetch(url: str) -> bytes:
    return urllib.request.urlopen(urllib.request.Request(url, headers=AGENT), timeout=180).read()


def main() -> None:
    dest = Path(sys.argv[1])
    dest.mkdir(parents=True, exist_ok=True)
    index_path = dest / "sources.json"
    index = json.loads(index_path.read_text(encoding="utf-8")) if index_path.exists() else {}
    sources = dict(SOURCES)
    for extra in EXTRA:  # "slug" lists a page's files without downloading; "slug=file1,file2" downloads
        slug, _, names = extra.partition("=")
        sources[slug] = [n for n in names.split(",") if n]
    for slug, wanted in sources.items():
        folder = dest / slug
        folder.mkdir(exist_ok=True)
        url = OGA + slug
        page = fetch(url)
        text = page.decode("utf-8", "replace")
        licences = re.findall(r"license-name'>(.*?)<", text)
        author = re.findall(r"class='username'[^>]*>(?:<a[^>]*>)?([^<]+)", text)[:1]
        title = re.search(r"<title>(.*?)</title>", text, re.S)
        if "CC0" not in licences:
            print("REFUSED (no CC0):", slug, licences)
            continue
        (folder / "page.html").write_bytes(page)
        links = sorted(set(re.findall(r"""https?://opengameart\.org/sites/default/files/[^'" >]+""", text)))
        links = [l for l in links if l.lower().endswith(ALLOWED) and "/audio_preview/" not in l and "/styles/" not in l]
        record = {"url": url, "title": html.unescape(title.group(1).split("|")[0].strip()) if title else slug, "author": html.unescape(author[0]) if author else "?", "licences_on_page": licences, "retrieved": datetime.date.today().isoformat(), "files": index.get(slug, {}).get("files", {})}
        (folder / "LICENSE_STATEMENT.txt").write_text("Source: %s\nTitle: %s\nAuthor: %s\nLicence(s) stated on page: %s\nUsed under: CC0 1.0 Universal (https://creativecommons.org/publicdomain/zero/1.0/)\nRetrieved: %s\nThe page as served is saved next to this file as page.html.\n" % (url, record["title"], record["author"], ", ".join(licences), record["retrieved"]), encoding="utf-8", newline="\n")
        if not wanted:
            print("LIST", slug, record["author"], licences, [urllib.parse.unquote(l.rsplit("/", 1)[1]) for l in links])
        for name in wanted:
            match = [l for l in links if urllib.parse.unquote(l.rsplit("/", 1)[1]) == name]
            if not match:
                print("MISSING", slug, name, [l.rsplit("/", 1)[1] for l in links])
                continue
            target = folder / name
            if not target.exists():
                target.write_bytes(fetch(match[0]))
            record["files"][name] = {"url": match[0], "sha256": hashlib.sha256(target.read_bytes()).hexdigest(), "bytes": target.stat().st_size}
            print("OK", slug, name, target.stat().st_size)
        index[slug] = record
        index_path.write_text(json.dumps(index, indent=2) + "\n", encoding="utf-8", newline="\n")


if __name__ == "__main__":
    main()
