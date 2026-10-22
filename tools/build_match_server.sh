#!/bin/sh
# Stage only game runtime resources; never copy repository credentials/tools.
set -eu
project_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
stage_root="$project_root/build/match-server"
mkdir -p "$stage_root/runtime"
python3 - "$project_root" "$stage_root/runtime" <<'PY'
from pathlib import Path
import shutil, sys
source, target = map(Path, sys.argv[1:])
for directory in ('assets', 'scenes', 'scripts'):
    dest = target / directory
    if dest.exists():
        shutil.rmtree(dest)
    shutil.copytree(source / directory, dest)
for name in ('debug_bootstrap.gd','debug_bootstrap.gd.uid','debug_panel.gd','debug_panel.gd.uid'):
    (target / 'scripts/ui' / name).unlink(missing_ok=True)
shutil.copy2(source/'icon.svg', target/'icon.svg')
lines=[]
skip=False
for line in (source/'project.godot').read_text().splitlines():
    if line.startswith('['):
        skip=line in ('[editor_plugins]','[godot_mcp]')
    if skip or '.debug=' in line or 'addons/godot_mcp' in line:
        continue
    if line.startswith('run/main_scene='):
        line='run/main_scene="res://scenes/network/server_lobby.tscn"'
    lines.append(line)
(target/'project.godot').write_text('\n'.join(lines)+'\n')
PY
"${GODOT_BIN:-/Applications/Godot.app/Contents/MacOS/Godot}" --headless --path "$stage_root/runtime" --editor --quit
cp "$project_root/deploy/match-server/Dockerfile" "$stage_root/Dockerfile"
printf 'Server build context: %s\n' "$stage_root"
