"""Create cropped AtlasTexture resources without altering generated PNG pixels.

Reads the six declared sheets, checks cell occupancy and writes the 48 texture
resources plus a reviewable source-hash/region manifest. Requires Pillow.
"""
import hashlib
import json
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
ART = ROOT / 'assets/kingdoms'
CIVS = ('crownlands', 'verdant', 'sunstride')
UNITS = ('villager', 'warrior', 'archer', 'cavalry', 'scout', 'siege')
BUILDINGS = ('town_center', 'house', 'barracks', 'archery_range', 'stable', 'farm', 'resource_camp', 'siege_workshop', 'blacksmith', 'watch_tower')


def prepare() -> None:
    manifest = {'schema': 1, 'scope': 'Generated PNGs are unchanged; regions exclude empty cell padding.', 'sheets': {}, 'textures': {}}
    layouts = json.loads((ART / 'atlas_layout.json').read_text(encoding='utf-8'))['sheets']
    pending = []
    for civ in CIVS:
        for family, cols, rows, names in [('unit', 3, 2, UNITS), ('building', 4, 3, BUILDINGS)]:
            sheet = ART / f'{civ}_{family}s.png'
            sheet_hash = hashlib.sha256(sheet.read_bytes()).hexdigest()
            layout = layouts[sheet.name]
            if layout['sha256'] != sheet_hash or len(layout['bounds']) != len(names):
                raise ValueError(f'{sheet.name}: source differs from reviewed atlas layout')
            with Image.open(sheet) as image:
                if image.mode != 'RGBA':
                    raise ValueError(f'{sheet.name}: expected RGBA, got {image.mode}')
                width, height = image.size
                alpha = image.getchannel('A')
                if alpha.getextrema()[0] != 0:
                    raise ValueError(f'{sheet.name}: no fully transparent pixels')
                manifest['sheets'][sheet.name] = {'size': [width, height], 'sha256': sheet_hash, 'layout': 'reviewed alpha bounds', 'nominal_grid': [cols, rows]}
                for index, name in enumerate(names):
                    cell = tuple(layout['bounds'][index])
                    if not (0 <= cell[0] < cell[2] <= width and 0 <= cell[1] < cell[3] <= height):
                        raise ValueError(f'{sheet.name}: invalid reviewed bounds for {name}')
                    mask = alpha.crop(cell).point(lambda value: 255 if value > 16 else 0)
                    bounds = mask.getbbox()
                    if bounds is None:
                        raise ValueError(f'{sheet.name}: empty {name} cell')
                    left, top, right, bottom = bounds
                    cell_width, cell_height = cell[2] - cell[0], cell[3] - cell[1]
                    # Reviewed bounds isolate the sprite; generated sheets do
                    # not obey equal-sized grid cells.
                    left, top = max(0, left - 2), max(0, top - 2)
                    right, bottom = min(cell_width, right + 2), min(cell_height, bottom + 2)
                    region = (cell[0] + left, cell[1] + top, right - left, bottom - top)
                    if region[2] < cell_width * .15 or region[3] < cell_height * .15:
                        raise ValueError(f'{sheet.name}: implausibly small {name} sprite {region}')
                    resource = ART / civ / f'{family}_{name}.tres'
                    content = ('[gd_resource type="AtlasTexture" load_steps=2 format=3]\n\n'
                               f'[ext_resource type="Texture2D" path="res://assets/kingdoms/{sheet.name}" id="1"]\n\n'
                               '[resource]\n'
                               'atlas = ExtResource("1")\n'
                               f'region = Rect2({region[0]}, {region[1]}, {region[2]}, {region[3]})\n'
                               'filter_clip = true\n')
                    pending.append((resource, content))
                    manifest['textures'][resource.relative_to(ROOT).as_posix()] = {'cell': list(cell), 'region': list(region), 'source': sheet.name}
    # Validate every input first, so a missing sheet cannot leave a partial set.
    for resource, content in pending:
        resource.parent.mkdir(parents=True, exist_ok=True)
        resource.write_text(content, encoding='utf-8', newline='\n')
    (ART / 'atlas_manifest.json').write_text(json.dumps(manifest, indent=2) + '\n', encoding='utf-8', newline='\n')
    print(f'Prepared {len(pending)} atlas textures from {len(manifest["sheets"])} unchanged PNGs.')


if __name__ == '__main__':
    prepare()
