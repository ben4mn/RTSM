"""Fetch CC0 Freesound items used by tools/audio/build_sound_identity.py.

Freesound's original uploads need a signed-in account, so this takes the public
high-quality preview encode (MP3) that Freesound publishes for every sound. For each
item it saves, OUTSIDE the repository:
  <dest>/freesound-<id>/page.html              the sound page as served (licence evidence)
  <dest>/freesound-<id>/LICENSE_STATEMENT.txt  licence URL, author, title, retrieval date
  <dest>/freesound-<id>/<id>.mp3               the preview encode
An item whose page does not link the CC0 1.0 deed as its licence is refused.

Usage: python tools/audio/fetch_freesound.py <dest-dir> [--list] <user>/<id> ...
With no ids, fetches the shipped set in ITEMS.
"""
from pathlib import Path
import datetime
import hashlib
import html
import json
import re
import sys
import time
import urllib.request

ITEMS: list[str] = ["foxen10/149024", "Twisted_Euphoria/205938", "Vendarro/328541", "Ali_6868/384918", "kirmm/392180", "saturdaysoundguy/394180", "craigsmith/437110", "craigsmith/437111", "o_ciz/475483", "craigsmith/479921", "JoeDinesSound/534956", "EminYILDIRIM/536066", "adharca/539956", "D4XX/564628", "MVMTech/569356", "igroglaz/633208", "Mythmazter/708223", "greyfeather/712918", "daytripper/73678", "tomoan74/748269"]
AGENT = {"User-Agent": "Mozilla/5.0 (asset-licence-check)"}


def fetch(url: str) -> bytes:
    for attempt in range(4):
        try:
            return urllib.request.urlopen(urllib.request.Request(url, headers=AGENT), timeout=120).read()
        except OSError:
            if attempt == 3:
                raise
            time.sleep(3)
    return b""


def main() -> None:
    dest = Path(sys.argv[1])
    args = sys.argv[2:]
    list_only = "--list" in args
    items = [a for a in args if a != "--list"] or ITEMS
    index_path = dest / "sources.json"
    index = json.loads(index_path.read_text(encoding="utf-8")) if index_path.exists() else {}
    for item in items:
        user, sound_id = item.split("/")
        url = "https://freesound.org/people/%s/sounds/%s/" % (user, sound_id)
        page = fetch(url)
        text = page.decode("utf-8", "replace")
        licence = re.findall(r'href="(https?://creativecommons\.org/[^"]+)"', text)
        licence = sorted(set(licence))
        title = re.search(r'<meta property="og:audio:title" content="([^"]*)"', text)
        title_text = html.unescape(title.group(1)) if title else "?"
        preview = re.search(r'(https://cdn\.freesound\.org/previews/\d+/%s_\d+-hq\.mp3)' % sound_id, text)
        desc = re.search(r'<meta name="description" content="([^"]*)"', text)
        duration = re.search(r'data-duration="([0-9.]+)"', text)
        cc0 = len(licence) == 1 and "publicdomain/zero/1.0" in licence[0]
        print("==", item, "|", title_text, "|", licence, "| dur", duration.group(1) if duration else "?", "|", html.unescape(desc.group(1))[:260] if desc else "")
        if not cc0:
            print("   REFUSED: licence is not solely CC0")
            continue
        if list_only or preview is None:
            continue
        folder = dest / ("freesound-" + sound_id)
        folder.mkdir(parents=True, exist_ok=True)
        (folder / "page.html").write_bytes(page)
        retrieved = datetime.date.today().isoformat()
        (folder / "LICENSE_STATEMENT.txt").write_text("Source: %s\nTitle: %s\nAuthor: %s (Freesound user)\nLicence linked on page: %s\nUsed under: CC0 1.0 Universal\nFile: Freesound public HQ preview encode %s\nRetrieved: %s\nThe page as served is saved next to this file as page.html.\n" % (url, title_text, user, licence[0], preview.group(1), retrieved), encoding="utf-8", newline="\n")
        target = folder / (sound_id + ".mp3")
        if not target.exists():
            target.write_bytes(fetch(preview.group(1)))
        index["freesound-" + sound_id] = {"url": url, "title": title_text, "author": user, "licences_on_page": ["CC0"], "licence_url": licence[0], "retrieved": retrieved, "files": {target.name: {"url": preview.group(1), "sha256": hashlib.sha256(target.read_bytes()).hexdigest(), "bytes": target.stat().st_size}}}
        index_path.write_text(json.dumps(index, indent=2) + "\n", encoding="utf-8", newline="\n")
        print("   OK", target.stat().st_size)


if __name__ == "__main__":
    main()
