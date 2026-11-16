"""Build the "sound identity" audio set from retained CC0 sources.

Inputs live OUTSIDE the repository (see tools/audio/fetch_sources.py and
tools/audio/fetch_freesound.py); Kenney originals already retained in
assets/audio/kenney/originals are reused. Outputs:
  assets/audio/identity/sfx/*.wav       32 kHz mono PCM16 (imported as QOA by Godot)
  assets/audio/identity/ambience/*.ogg  32 kHz mono Vorbis seamless loops
  assets/audio/identity/music/*.ogg     32 kHz stereo Vorbis
  assets/audio/identity/manifest.json   every file -> sources, hashes, processing, measurements
  scripts/audio/identity_palette.gd     generated cue bank

Usage: python tools/audio/build_sound_identity.py <audio_src dir> <ffmpeg.exe> [sfx|ambience|music ...]
Requires numpy, scipy, soundfile. Deterministic: no random numbers are used.
"""
from pathlib import Path
import hashlib
import json
import subprocess
import sys
import numpy as np
from scipy.signal import butter, resample_poly, sosfilt
import soundfile as sf

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "assets/audio/identity"
RATE = 32000
SRC = Path(sys.argv[1]) if len(sys.argv) > 1 else Path(".")
FFMPEG = sys.argv[2] if len(sys.argv) > 2 else "ffmpeg"
STAGES = sys.argv[3:] or ["sfx", "ambience", "music"]

X = "_x/"
RPG = X + "rpg-sound-pack/rpg_sound_pack/RPG Sound Pack/"
BFH = X + "75-cc0-breaking-falling-hit-sfx/sfx_breaking_and_falling/"
C100 = X + "100-cc0-sfx/100-CC0-SFX_0/"
C80 = X + "80-cc0-rpg-sfx/80-CC0-RPG-SFX_0/"
LOOPS = X + "30-cc0-sfx-loops/sfx_loops/"
WPN = X + "fantasy-weapons-and-apparel-sfx-library/weapons-apparel/"
CLASH = X + "20-sword-sound-effects-attacks-and-clashes/sword_clash_-_starninjas_0/"
BATTLE = X + "battle-sound-effects/battle_sound_effects_0/"
KEN = "assets/audio/kenney/originals/"


def find(base: str, name: str) -> Path:
    """Locate a file by name below an extracted archive (archives nest differently)."""
    root = SRC / base
    hits = [p for p in root.rglob(name) if "__MACOSX" not in p.parts]
    if not hits:
        raise FileNotFoundError("%s under %s" % (name, root))
    return hits[0]


def source(key: str) -> tuple[str, Path]:
    """key -> (provenance id, path). Keys: 'fs:<id>', 'kenney:<pack>/<file>', '<slug>:<file>'."""
    kind, _, name = key.partition(":")
    if kind == "fs":
        return "freesound-" + name, SRC / ("freesound-" + name) / (name + ".mp3")
    if kind == "kenney":
        return "kenney-" + name.split("/")[0], ROOT / KEN / name
    table = {"rpg": ("rpg-sound-pack", RPG), "bfh": ("75-cc0-breaking-falling-hit-sfx", BFH), "c100": ("100-cc0-sfx", C100), "c80": ("80-cc0-rpg-sfx", C80), "loops": ("30-cc0-sfx-loops", LOOPS), "wpn": ("fantasy-weapons-and-apparel-sfx-library", WPN), "clash": ("20-sword-sound-effects-attacks-and-clashes", CLASH), "battle": ("battle-sound-effects", BATTLE)}
    if kind in table:
        slug, base = table[kind]
        return slug, find(base, name)
    return kind, SRC / kind / name  # loose file directly in a slug folder


_cache: dict[str, np.ndarray] = {}


def load(key: str) -> np.ndarray:
    if key not in _cache:
        _, path = source(key)
        data, sr = sf.read(str(path), always_2d=True)
        mono = data.mean(axis=1)
        if sr != RATE:
            mono = resample_poly(mono, RATE, sr)
        _cache[key] = mono - mono.mean()
    return _cache[key]


def pitch(data: np.ndarray, ratio: float) -> np.ndarray:
    if abs(ratio - 1.0) < 1e-6:
        return data
    return np.interp(np.arange(0, len(data) - 1, ratio), np.arange(len(data)), data)


def filt(data: np.ndarray, kind: str, hz: float) -> np.ndarray:
    return sosfilt(butter(2, hz, btype=kind, fs=RATE, output="sos"), data)


def fade(data: np.ndarray, fin: float, fout: float) -> np.ndarray:
    data = data.copy()
    n = min(int(fin * RATE), len(data) // 2)
    if n > 0:
        data[:n] *= np.linspace(0.0, 1.0, n)
    n = min(int(fout * RATE), len(data) // 2)
    if n > 0:
        data[-n:] *= np.linspace(1.0, 0.0, n) ** 2
    return data


def layer(key: str, start: float = 0.0, end: float | None = None, **o) -> dict:
    return {"src": key, "start": start, "end": end, **o}


def render(layers: list[dict]) -> np.ndarray:
    parts = []
    total = 0
    for spec in layers:
        data = load(spec["src"])
        a = int(spec["start"] * RATE)
        b = len(data) if spec["end"] is None else min(len(data), int(spec["end"] * RATE))
        seg = pitch(data[a:b], float(spec.get("pitch", 1.0)))
        if "lp" in spec:
            seg = filt(seg, "low", spec["lp"])
        if "hp" in spec:
            seg = filt(seg, "high", spec["hp"])
        seg = fade(seg, float(spec.get("fin", 0.003)), float(spec.get("fout", 0.04)))
        peak = np.abs(seg).max()
        seg = seg / max(peak, 1e-6) * 10 ** (float(spec.get("gain", 0.0)) / 20)  # layer gains are relative to each layer's own peak
        offset = int(float(spec.get("delay", 0.0)) * RATE)
        parts.append((offset, seg))
        total = max(total, offset + len(seg))
    mix = np.zeros(total)
    for offset, seg in parts:
        mix[offset:offset + len(seg)] += seg
    return mix


def active_rms_db(data: np.ndarray) -> float:
    n = int(0.02 * RATE)
    frames = max(1, len(data) // n)
    rms = np.sqrt(np.mean(data[: frames * n].reshape(frames, n) ** 2, axis=1) + 1e-12)
    gate = rms.max() * 10 ** (-20 / 20)
    return float(20 * np.log10(np.sqrt(np.mean(rms[rms >= gate] ** 2))))


def trim(data: np.ndarray, floor_db: float = -52.0) -> np.ndarray:
    level = np.abs(data)
    thr = level.max() * 10 ** (floor_db / 20)
    idx = np.nonzero(level > thr)[0]
    if len(idx) == 0:
        return data
    return data[max(0, idx[0] - int(0.002 * RATE)): idx[-1] + int(0.02 * RATE)]


# Loudness classes: (active-RMS target dBFS, peak ceiling dBFS). Documented in docs/licensed_audio_2026-11.md.
CLASSES = {"combat": (-20.0, -3.0), "heavy": (-18.0, -2.5), "death": (-21.0, -4.0), "ack": (-24.0, -6.0), "building": (-24.0, -6.0), "alert": (-17.0, -2.0), "event": (-18.0, -2.5)}


def finish(data: np.ndarray, cls: str, max_len: float | None, tail: float) -> np.ndarray:
    data = trim(data)
    if max_len is not None and len(data) > int(max_len * RATE):
        data = data[: int(max_len * RATE)]
    data = fade(data, 0.002, tail)
    target, ceiling = CLASSES[cls]
    data = data * 10 ** ((target - active_rms_db(data)) / 20)
    limit = 10 ** (ceiling / 20)
    if np.abs(data).max() > limit:
        # Transparent below ~70% of the ceiling, smooth saturation above: keeps the body at target loudness.
        knee = limit * 0.7
        over = np.abs(data) > knee
        data[over] = np.sign(data[over]) * (knee + (limit - knee) * np.tanh((np.abs(data[over]) - knee) / (limit - knee)))
    # Tighten to the audible span: inaudible fade tails only occupy voices and bytes.
    level = np.abs(data)
    idx = np.nonzero(level > 10 ** (-48 / 20))[0]
    if len(idx):
        data = data[max(0, idx[0] - int(0.001 * RATE)): min(len(data), idx[-1] + int(0.03 * RATE))]
    data = fade(data, 0.001, 0.03)
    data[0] = 0.0
    data[-1] = 0.0
    return data


# --------------------------------------------------------------------------------------
# SFX recipes: cue -> (class, max seconds, tail fade seconds, [variants as layer lists])
# --------------------------------------------------------------------------------------
L = layer
THUD_A = L("bfh:bfh1_hit_02.ogg", 0, 0.35, gain=-7, lp=900, delay=0.012)
THUD_B = L("c100:wooden_01.ogg", 0, 0.3, gain=-9, lp=1200, pitch=0.8, delay=0.012)
THUD_C = L("kenney:impact/impactPunch_medium_000.ogg", 0, 0.3, gain=-6, delay=0.01)

SFX: dict[str, tuple[str, float | None, float, list[list[dict]]]] = {
    # ---- combat: attacks and impacts by weapon class ----
    "melee_hit": ("combat", 0.6, 0.12, [
        [L("clash:sword_clash.2.ogg", lp=7500), THUD_A],
        [L("clash:sword_clash.3.ogg", lp=7500), THUD_C],
        [L("clash:sword_clash.5.ogg", lp=7500), THUD_B],
        [L("clash:sword_clash.8.ogg", lp=7500), THUD_A],
        [L("clash:sword_clash.10.ogg", lp=7500), THUD_C],
        [L("wpn:sword-knife-clash-07.wav", lp=7500), THUD_B],
    ]),
    "villager_hit": ("combat", 0.4, 0.08, [
        [L("bfh:bfh1_wood_hit_01.ogg", gain=-2), L("rpg:cloth.wav", gain=-10)],
        [L("bfh:bfh1_wood_hit_03.ogg", gain=-2), L("kenney:impact/impactPunch_medium_000.ogg", gain=-6)],
        [L("c100:wooden_02.ogg", gain=-2), L("rpg:cloth-heavy.wav", gain=-10)],
    ]),
    "bow_release": ("combat", 0.45, 0.1, [
        [L("battle:Bow.wav")],
        [L("battle:Bow.wav", pitch=0.9), L("battle:swish_2.wav", gain=-14, hp=800)],
        [L("fs:384918", 0.05, 0.4), L("battle:swish_4.wav", gain=-12, hp=800, delay=0.02)],
        [L("fs:394180", 0.0, 0.4, lp=8000)],
    ]),
    "arrow_impact": ("combat", 0.4, 0.1, [
        [L("fs:708223", 0.40, 0.8)],
        [L("fs:534956", 0.09, 0.5)],
        [L("fs:205938", 0.03, 0.36, lp=6500)],
        [L("fs:536066", 0.0, 0.3), L("fs:708223", 0.40, 0.7, gain=-8, pitch=1.1)],
    ]),
    "cavalry_hit": ("combat", 0.7, 0.15, [
        [L("fs:564628", 2.00, 2.55, gain=-3), L("clash:sword_clash.4.ogg", gain=-4, lp=7000, delay=0.12), L("bfh:bfh1_hit_02.ogg", 0, 0.35, gain=-6, lp=900, delay=0.13)],
        [L("fs:564628", 4.10, 4.65, gain=-3), L("clash:sword_clash.7.ogg", gain=-4, lp=7000, delay=0.12), L("c100:wooden_01.ogg", 0, 0.3, gain=-8, pitch=0.8, delay=0.13)],
        [L("fs:564628", 6.20, 6.75, gain=-3), L("clash:sword_clash.9.ogg", gain=-4, lp=7000, delay=0.12), L("kenney:impact/impactPunch_medium_000.ogg", gain=-5, delay=0.13)],
    ]),
    "siege_launch": ("heavy", 1.1, 0.25, [
        [L("tree-creaking:tree_creak.flac", 2.87, 3.30, gain=-4), L("battle:swish_3.wav", pitch=0.55, gain=-2, delay=0.22), L("bfh:bfh1_wood_hit_02.ogg", pitch=0.7, gain=0, delay=0.30)],
        [L("tree-creaking:tree_creak.flac", 0.47, 0.95, gain=-5), L("battle:swish_3.wav", pitch=0.5, gain=-2, delay=0.25), L("bfh:bfh1_wood_hit_01.ogg", pitch=0.65, gain=0, delay=0.34)],
        [L("fs:479921", 0.08, 1.1, gain=0), L("bfh:bfh1_wood_hit_02.ogg", pitch=0.75, gain=-3, delay=0.05)],
    ]),
    "siege_impact": ("heavy", 1.1, 0.3, [
        [L("breaking-rock:rock_break.ogg", pitch=0.6), L("bfh:bfh1_hit_02.ogg", pitch=0.6, gain=-1, lp=700), L("bfh:bfh1_rock_falling_01.ogg", gain=-9, delay=0.12)],
        [L("bfh:bfh1_rock_breaking_02.ogg", pitch=0.7), L("c100:wooden_01.ogg", pitch=0.5, gain=-2, lp=700), L("bfh:bfh1_rock_falling_03.ogg", gain=-10, delay=0.15)],
        [L("bfh:bfh1_rock_breaking_01.ogg", pitch=0.65), L("bfh:bfh1_hit_02.ogg", pitch=0.5, gain=-1, lp=700), L("c80:stones_03.ogg", gain=-10, delay=0.12)],
    ]),
    "building_hit": ("combat", 0.5, 0.12, [
        [L("bfh:bfh1_wood_hit_02.ogg", pitch=0.8), L("c80:stones_04.ogg", gain=-12, delay=0.04)],
        [L("bfh:bfh1_wood_hit_01.ogg", pitch=0.75), L("bfh:bfh1_rock_hit_01.ogg", gain=-10, delay=0.02)],
        [L("c100:wooden_01.ogg", pitch=0.85), L("bfh:bfh1_rock_falling_07.ogg", gain=-13, delay=0.05)],
        [L("kenney:impact/impactPlank_medium_001.ogg", pitch=0.8), L("c80:item_stone_02.ogg", gain=-12, delay=0.04)],
    ]),
    "building_collapse": ("heavy", 3.0, 0.9, [
        [L("fs:712918", 0.0, 2.9), L("bfh:bfh1_wood_breaking_03.ogg", gain=-6, delay=0.05), L("bfh:bfh1_falling_04.ogg", gain=-8, delay=0.5)],
        [L("cave-in:cave_in_-_starninjas.ogg", 0.29, 3.2, pitch=0.8, lp=5000), L("bfh:bfh1_wood_falling_01.ogg", gain=-5, delay=0.0), L("bfh:bfh1_rock_falling_01.ogg", gain=-7, delay=0.7)],
        [L("fs:712918", 0.0, 2.9, pitch=0.88), L("bfh:bfh1_breaking_01.ogg", gain=-6, delay=0.1), L("bfh:bfh1_falling_07.ogg", gain=-8, delay=0.8)],
    ]),
    # ---- deaths by class (no voices, no gore) ----
    "death_infantry": ("death", 0.9, 0.2, [
        [L("bfh:bfh1_metal_falling_03.ogg", gain=-3, lp=7000), L("bfh:bfh1_hit_02.ogg", gain=0, lp=900, delay=0.05)],
        [L("rpg:chainmail2.wav", gain=-4), L("c100:wooden_03.ogg", pitch=0.7, gain=0, lp=1000, delay=0.08)],
        [L("bfh:bfh1_metal_falling_05.ogg", gain=-3, lp=7000), L("rpg:armor-light.wav", gain=-8, delay=0.1), L("bfh:bfh1_hit_02.ogg", gain=0, lp=900, delay=0.06)],
    ]),
    "death_soft": ("death", 0.7, 0.2, [
        [L("rpg:cloth-heavy.wav", gain=-3), L("bfh:bfh1_hit_02.ogg", gain=0, lp=800, delay=0.06)],
        [L("kenney:rpg/dropLeather.ogg", gain=-2), L("c100:wooden_03.ogg", pitch=0.7, gain=-2, lp=900, delay=0.05)],
        [L("rpg:cloth.wav", gain=-3), L("kenney:impact/impactPunch_medium_000.ogg", pitch=0.8, gain=0, delay=0.05)],
    ]),
    "death_cavalry": ("death", 1.5, 0.35, [
        [L("fs:149024", 3.49, 4.75, gain=0), L("bfh:bfh1_hit_02.ogg", gain=-3, lp=800, pitch=0.8, delay=0.75)],
        [L("fs:437110", 10.76, 12.2, gain=0), L("c100:wooden_03.ogg", pitch=0.6, gain=-4, lp=900, delay=0.85)],
        [L("fs:149024", 2.28, 2.62, gain=0), L("fs:149024", 5.50, 6.05, gain=-4, delay=0.3), L("bfh:bfh1_hit_02.ogg", gain=-3, lp=800, pitch=0.8, delay=0.6)],
    ]),
    "death_siege": ("death", 1.3, 0.3, [
        [L("bfh:bfh1_wood_breaking_03.ogg", pitch=0.8), L("bfh:bfh1_wood_falling_01.ogg", gain=-3, delay=0.2)],
        [L("bfh:bfh1_wood_breaking_04.ogg", pitch=0.75), L("bfh:bfh1_wood_falling_02.ogg", gain=-3, delay=0.18), L("bfh:bfh1_breaking_02.ogg", gain=-8, delay=0.35)],
        [L("bfh:bfh1_breaking_03.ogg", pitch=0.8), L("bfh:bfh1_wood_hit_02.ogg", pitch=0.7, gain=-2, delay=0.05), L("bfh:bfh1_wood_falling_01.ogg", gain=-5, delay=0.3)],
    ]),
    # ---- non-verbal selection acknowledgements by unit class ----
    "select_villager": ("ack", 0.4, 0.1, [
        [L("rpg:cloth.wav")],
        [L("rpg:wood-small.wav"), L("rpg:cloth-heavy.wav", gain=-10, delay=0.05)],
        [L("kenney:rpg/handleSmallLeather.ogg", 0, 0.4)],
    ]),
    "select_infantry": ("ack", 0.5, 0.12, [
        [L("rpg:chainmail1.wav", lp=7000)],
        [L("rpg:armor-light.wav", lp=7000)],
        [L("rpg:chainmail2.wav", 0, 0.5, lp=7000)],
    ]),
    "select_archer": ("ack", 0.5, 0.12, [
        [L("wpn:quiver-leather-squeeze-03.wav")],
        [L("wpn:quiver-leather-squeeze-08.wav")],
        [L("wpn:arrow-feathers-02.wav"), L("wpn:quiver-leather-squeeze-12.wav", gain=-8, delay=0.05)],
    ]),
    "select_cavalry": ("ack", 0.6, 0.15, [
        [L("fs:437111", 2.03, 2.45)],
        [L("fs:475483", 0.0, 0.46)],
        [L("fs:437111", 8.52, 9.04)],
    ]),
    "select_siege": ("ack", 0.6, 0.15, [
        [L("tree-creaking:tree_creak.flac", 0.47, 1.0)],
        [L("tree-creaking:tree_creak.flac", 2.87, 3.42)],
        [L("c80:wood_04.ogg"), L("c80:chain_02.ogg", gain=-14, lp=6000, delay=0.08)],
    ]),
    # ---- non-verbal order acknowledgements ----
    "order_villager": ("ack", 0.45, 0.1, [
        [L("wpn:boots-leather-step-01.wav"), L("wpn:boots-leather-step-03.wav", gain=-3, delay=0.16)],
        [L("wpn:boots-leather-step-02.wav"), L("rpg:cloth.wav", gain=-9, delay=0.1)],
        [L("wpn:boots-leather-step-04.wav"), L("wpn:boots-leather-step-01.wav", gain=-3, delay=0.17)],
    ]),
    "order_infantry": ("ack", 0.5, 0.1, [
        [L("wpn:boots-leather-step-01.wav"), L("rpg:armor-light.wav", gain=-6, lp=7000, delay=0.03), L("wpn:boots-leather-step-02.wav", gain=-3, delay=0.18)],
        [L("wpn:belt-buckle-02.wav"), L("rpg:chainmail1.wav", gain=-6, lp=7000, delay=0.06)],
        [L("wpn:boots-leather-step-03.wav"), L("rpg:chainmail2.wav", 0, 0.4, gain=-6, lp=7000, delay=0.04)],
    ]),
    "order_archer": ("ack", 0.5, 0.1, [
        [L("wpn:arrow-grab-from-quiver-02.wav")],
        [L("wpn:arrow-grab-from-quiver-05.wav")],
        [L("wpn:boots-leather-step-02.wav"), L("wpn:arrow-feathers-01.wav", gain=-4, delay=0.08)],
    ]),
    "order_cavalry": ("ack", 0.6, 0.15, [
        [L("fs:564628", 3.00, 3.55), L("c80:chain_02.ogg", gain=-16, lp=6000, delay=0.05)],
        [L("fs:564628", 5.10, 5.65), L("c80:chain_01.ogg", gain=-16, lp=6000, delay=0.05)],
        [L("fs:564628", 7.30, 7.85), L("fs:475483", 0.0, 0.4, gain=-8, delay=0.1)],
    ]),
    "order_siege": ("ack", 0.9, 0.2, [
        [L("loops:rolling.ogg", 0.0, 0.8), L("tree-creaking:tree_creak.flac", 0.47, 0.9, gain=-6, delay=0.05)],
        [L("loops:rolling.ogg", 0.2, 1.0, pitch=0.9), L("c80:wood_04.ogg", gain=-6, delay=0.1)],
    ]),
    "order_attack_melee": ("ack", 0.5, 0.12, [
        [L("rpg:sword-unsheathe.wav", lp=7500)],
        [L("rpg:sword-unsheathe3.wav", lp=7500)],
        [L("rpg:sword-unsheathe5.wav", lp=7500)],
    ]),
    "order_attack_villager": ("ack", 0.45, 0.1, [
        [L("wpn:knife-unsheathe-01.wav", lp=7500)],
        [L("wpn:knife-unsheathe-03.wav", lp=7500)],
    ]),
    "order_attack_archer": ("ack", 0.6, 0.12, [
        [L("wpn:arrow-grab-from-quiver-03.wav"), L("wpn:quiver-leather-squeeze-05.wav", gain=-3, delay=0.22)],
        [L("wpn:arrow-grab-from-quiver-06.wav"), L("wpn:quiver-leather-squeeze-10.wav", gain=-3, delay=0.22)],
    ]),
    "order_attack_cavalry": ("ack", 0.9, 0.2, [
        [L("fs:149024", 2.28, 2.62), L("fs:564628", 8.40, 8.95, gain=-5, delay=0.2)],
        [L("fs:437111", 4.04, 4.6), L("fs:564628", 9.30, 9.85, gain=-4, delay=0.25)],
    ]),
    "order_attack_siege": ("ack", 0.9, 0.2, [
        [L("tree-creaking:tree_creak.flac", 0.47, 1.1), L("c80:chain_03.ogg", gain=-10, lp=6000, delay=0.1)],
        [L("tree-creaking:tree_creak.flac", 2.87, 3.42), L("c80:chain_01.ogg", gain=-10, lp=6000, delay=0.15)],
    ]),
    # ---- buildings: each answers with its own trade ----
    "select_town_center": ("building", 1.0, 0.4, [
        [L("fs:748269", 0.0, 1.0)],
        [L("fs:748269", 0.0, 1.0, pitch=0.89)],
    ]),
    "select_house": ("building", 0.5, 0.12, [
        [L("c100:door_close_03.ogg")],
        [L("c100:door_close_04.ogg")],
    ]),
    "select_barracks": ("building", 0.6, 0.15, [
        [L("rpg:metal-ringing.wav", lp=7000), L("rpg:armor-light.wav", gain=-8, delay=0.05)],
        [L("wpn:sword-knife-clash-12.wav", lp=7000), L("rpg:chainmail1.wav", gain=-8, delay=0.06)],
    ]),
    "select_archery_range": ("building", 0.6, 0.15, [
        [L("battle:Bow.wav", gain=-3), L("fs:536066", 0.0, 0.3, delay=0.22)],
        [L("fs:384918", 0.05, 0.35, gain=-3), L("fs:534956", 0.09, 0.45, delay=0.22)],
    ]),
    "select_stable": ("building", 1.0, 0.2, [
        [L("fs:437111", 4.04, 4.9)],
        [L("fs:437111", 5.77, 6.7)],
    ]),
    "select_farm": ("building", 0.6, 0.15, [
        [L("c80:stones_04.ogg", pitch=0.8), L("rpg:cloth.wav", gain=-6, delay=0.1)],
        [L("kenney:rpg/cloth2.ogg"), L("c80:item_wood_02.ogg", gain=-6, delay=0.12)],
    ]),
    "select_resource_camp": ("building", 0.6, 0.15, [
        [L("kenney:impact/impactWood_light_000.ogg"), L("c80:item_wood_01.ogg", gain=-5, delay=0.14)],
        [L("kenney:impact/impactMining_001.ogg"), L("c80:item_wood_03.ogg", gain=-5, delay=0.14)],
    ]),
    "select_siege_workshop": ("building", 0.9, 0.2, [
        [L("loops:saw.ogg", 0.0, 0.75), L("c100:wooden_02.ogg", gain=-4, delay=0.62)],
        [L("loops:saw.ogg", 1.1, 1.85, pitch=0.93), L("bfh:bfh1_wood_hit_03.ogg", gain=-4, delay=0.62)],
    ]),
    "select_blacksmith": ("building", 1.0, 0.3, [
        [L("hammer-on-anvil:forger.ogg", 0.05, 1.05)],
        [L("blacksmiths-hammer:blacksmithhammer.wav"), L("blacksmiths-hammer:blacksmithhammer.wav", pitch=1.06, gain=-4, delay=0.3)],
    ]),
    "select_watch_tower": ("building", 0.8, 0.2, [
        [L("c100:door_close_02.ogg")],
        [L("rpg:door.wav", 0.1, 0.9, gain=-2)],
    ]),
    # ---- signature events ----
    "age_up_fanfare": ("alert", 5.2, 1.6, [
        [L("trumpet-fanfare:castlefanfare.ogg", 0.0, 2.3, gain=0), L("fs:633208", 0.0, 3.2, gain=-7, delay=0.0), L("fs:73678", 0.0, 3.6, gain=-3, delay=1.75)],
        [L("classic-fanfare-lick:fanfare_3.ogg", 0.18, 2.4, gain=0), L("fs:633208", 0.0, 3.2, gain=-7, delay=0.0), L("fs:569356", 0.0, 3.6, gain=-3, delay=1.85)],
    ]),
    "alert_town": ("alert", 2.2, 0.8, [
        [L("fs:748269", 0.0, 1.0), L("fs:748269", 0.0, 1.0, delay=0.27), L("fs:748269", 0.0, 1.0, delay=0.54), L("fs:633208", 0.0, 2.0, gain=-8)],
        [L("fs:748269", 0.0, 1.0, pitch=0.94), L("fs:748269", 0.0, 1.0, pitch=0.94, delay=0.25), L("fs:748269", 0.0, 1.0, pitch=0.94, delay=0.5), L("fs:633208", 0.0, 2.0, gain=-8, pitch=0.94)],
    ]),
    "alert_army": ("alert", 2.6, 0.7, [
        [L("fs:392180", 0.06, 2.7)],
        [L("fs:539956", 0.05, 2.7)],
    ]),
    "trained_military": ("event", 1.0, 0.3, [
        [L("rpg:sword-unsheathe2.wav", lp=7500), L("rpg:chainmail2.wav", gain=-7, lp=7000, delay=0.12), L("kenney:interface/confirmation_002.ogg", gain=-8, pitch=0.8, delay=0.2)],
        [L("rpg:sword-unsheathe4.wav", lp=7500), L("rpg:armor-light.wav", gain=-7, lp=7000, delay=0.12), L("kenney:interface/confirmation_001.ogg", gain=-8, pitch=0.8, delay=0.2)],
    ]),
    "trained_villager": ("event", 0.9, 0.3, [
        [L("rpg:wood-small.wav", gain=-5), L("kenney:interface/confirmation_001.ogg", gain=0, delay=0.1)],
        [L("rpg:cloth.wav", gain=-6), L("kenney:interface/confirmation_002.ogg", gain=0, delay=0.1)],
    ]),
    "building_complete_chime": ("event", 1.5, 0.5, [
        [L("c100:wooden_01.ogg", gain=-3), L("c100:wooden_01.ogg", gain=-2, pitch=1.05, delay=0.17), L("kenney:interface/confirmation_003.ogg", gain=0, delay=0.36), L("c100:bell_01.ogg", gain=-9, delay=0.4, lp=7000)],
        [L("bfh:bfh1_wood_hit_02.ogg", gain=-3), L("bfh:bfh1_wood_hit_02.ogg", gain=-2, pitch=1.05, delay=0.17), L("kenney:interface/confirmation_004.ogg", gain=0, delay=0.36), L("c100:bell_01.ogg", gain=-9, delay=0.4, lp=7000, pitch=1.12)],
    ]),
    "research_complete": ("event", 1.6, 0.5, [
        [L("c80:book_01.ogg", gain=-5), L("c100:bell_01.ogg", gain=0, delay=0.3, lp=7000), L("kenney:interface/confirmation_004.ogg", gain=-6, pitch=1.2, delay=0.32)],
        [L("c80:book_02.ogg", gain=-5), L("c100:bell_01.ogg", gain=0, delay=0.35, lp=7000, pitch=1.12), L("kenney:interface/confirmation_003.ogg", gain=-6, pitch=1.2, delay=0.37)],
    ]),
    "sacred_captured": ("alert", 3.6, 1.4, [
        [L("fs:633208", 0.0, 3.2, gain=0), L("fs:748269", 0.0, 1.0, gain=-5, delay=0.55), L("c100:bell_03.ogg", gain=-9, delay=0.95, lp=7000)],
        [L("fs:633208", 0.0, 3.2, gain=0, pitch=1.12), L("fs:748269", 0.0, 1.0, gain=-5, delay=0.5), L("c100:bell_03.ogg", gain=-9, delay=0.9, lp=7000, pitch=1.12)],
    ]),
    "sacred_lost": ("alert", 3.0, 1.2, [
        [L("c100:gong_02.ogg", pitch=0.7, gain=0), L("fs:328541", 0.04, 2.6, gain=-4, delay=0.05)],
    ]),
    "town_bell": ("alert", 4.6, 1.8, [
        [L("fs:73678", 0.0, 3.4)],
        [L("fs:73678", 0.0, 3.4), L("fs:73678", 0.0, 3.4, delay=1.15)],
    ]),
}


def sha(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def describe(spec: dict) -> dict:
    slug, path = source(spec["src"])
    try:
        rel = path.relative_to(SRC).as_posix()
    except ValueError:
        rel = path.relative_to(ROOT).as_posix()
    out = {"source": slug, "file": rel, "sha256": sha(path)}
    for key in ("start", "end", "pitch", "gain", "delay", "lp", "hp"):
        if spec.get(key) not in (None, 0.0) or key == "start":
            out[key] = spec.get(key)
    return out


def build_sfx(manifest: dict) -> None:
    folder = OUT / "sfx"
    folder.mkdir(parents=True, exist_ok=True)
    for old in folder.glob("*.wav"):
        old.unlink()
    bank: dict[str, list[str]] = {}
    for cue, (cls, max_len, tail, variants) in SFX.items():
        bank[cue] = []
        for index, layers in enumerate(variants):
            data = finish(render(layers), cls, max_len, tail)
            path = folder / ("%s_%02d.wav" % (cue, index + 1))
            sf.write(str(path), data, RATE, subtype="PCM_16")
            rel = path.relative_to(ROOT).as_posix()
            bank[cue].append("res://" + rel)
            manifest["files"][rel] = {"kind": "sfx", "cue": cue, "loudness_class": cls, "seconds": round(len(data) / RATE, 3), "peak_dbfs": round(float(20 * np.log10(np.abs(data).max())), 2), "active_rms_dbfs": round(active_rms_db(data), 2), "sha256": sha(path), "processing": "mono 32 kHz; layers peak-normalised then mixed at listed gain/pitch/delay/filters; trimmed; faded; active-RMS normalised to class target with soft peak ceiling", "layers": [describe(s) for s in layers]}
    lines = ["extends RefCounted", "## Generated by tools/audio/build_sound_identity.py. CC0 sources; see docs/licensed_audio_2026-11.md.", "## Edited recordings only: no synthesis, no gameplay RNG. AudioManager owns gain, priorities and caps.", "", "const BANK: Dictionary = {"]
    for cue, paths in bank.items():
        lines.append('\t"' + cue + '": [' + ", ".join('preload("' + p + '")' for p in paths) + "],")
    lines += ["}", "", "", "static func build() -> Dictionary:", "\treturn BANK.duplicate(true)", ""]
    (ROOT / "scripts/audio/identity_palette.gd").write_bytes("\n".join(lines).encode())
    print("sfx: %d files, %d cues, %.1f s, %d bytes PCM" % (sum(len(v) for v in bank.values()), len(bank), sum(f["seconds"] for f in manifest["files"].values() if f["kind"] == "sfx"), sum((ROOT / r).stat().st_size for r, f in manifest["files"].items() if f["kind"] == "sfx")))


# --------------------------------------------------------------------------------------
# Ambience loops
# --------------------------------------------------------------------------------------
def read_native(key: str, start: float, seconds: float) -> np.ndarray:
    _, path = source(key)
    info = sf.info(str(path))
    data, sr = sf.read(str(path), start=int(start * info.samplerate), frames=int(seconds * info.samplerate), always_2d=True)
    mono = data.mean(axis=1)
    return resample_poly(mono, RATE, sr) if sr != RATE else mono


def make_loop(data: np.ndarray, seconds: float, cross: float) -> np.ndarray:
    """Seamless loop: the material after the loop end is equal-power crossfaded into the head."""
    n = int(seconds * RATE)
    c = int(cross * RATE)
    body = data[:n].copy()
    tail = data[n:n + c]
    t = np.linspace(0.0, np.pi / 2, c)
    body[:c] = body[:c] * np.sin(t) + tail * np.cos(t)
    return body


def rms_db(data: np.ndarray) -> float:
    return float(20 * np.log10(np.sqrt(np.mean(data ** 2)) + 1e-12))


def town_bed(seconds: float) -> np.ndarray:
    """A sparse, distant workshop pattern assembled from recorded tools. Silence at both ends keeps it loopable."""
    events = [
        (1.2, L("hammer-on-anvil:forger.ogg", 0.05, 1.7, gain=-6)),
        (4.4, L("loops:saw.ogg", 0.0, 2.2, gain=-10)),
        (7.3, L("c100:wooden_02.ogg", gain=-9)),
        (7.9, L("c100:wooden_03.ogg", gain=-10)),
        (10.0, L("blacksmiths-hammer:blacksmithhammer.wav", gain=-7)),
        (10.55, L("blacksmiths-hammer:blacksmithhammer.wav", gain=-9, pitch=1.04)),
        (11.1, L("blacksmiths-hammer:blacksmithhammer.wav", gain=-8, pitch=0.97)),
        (13.6, L("bfh:bfh1_wood_hit_01.ogg", gain=-9)),
        (14.3, L("c80:item_wood_01.ogg", gain=-10)),
        (16.4, L("loops:saw.ogg", 0.4, 2.3, gain=-11, pitch=0.94)),
        (19.2, L("rpg:door.wav", gain=-12)),
        (21.0, L("hammer-on-anvil:forger.ogg", 0.05, 1.2, gain=-8, pitch=0.95)),
        (22.6, L("c100:wooden_01.ogg", gain=-11, pitch=1.1)),
    ]
    mix = np.zeros(int(seconds * RATE))
    for at, spec in events:
        seg = render([spec])
        start = int(at * RATE)
        seg = seg[: len(mix) - start]
        mix[start:start + len(seg)] += seg
    return filt(mix, "low", 3800)  # distance: the town is around the camera, not under the microphone


AMBIENCE = {
    # name: (loop seconds, crossfade seconds, [(key, start, gain dB, highpass Hz)], target RMS dBFS)
    "day_bed": (30.0, 3.0, [("amb-morning-sounds-perfect-loop:amb_morning.ogg", 4.0, 0.0, 150.0), ("park-ambiences:park_ambience_wind.wav", 112.0, -9.0, 120.0)], -30.0),
    "forest": (22.0, 2.5, [("ambient-bird-sounds:birds-isaiah658.ogg", 0.3, 0.0, 300.0), ("park-ambiences:park_ambience_birds.wav", 60.0, -8.0, 400.0)], -30.0),
    "water": (20.0, 2.5, [("park-ambiences:park_ambience_river.wav", 120.0, 0.0, 180.0)], -30.0),
}


def encode_ogg(wav: Path, ogg: Path, quality: str, channels: int) -> None:
    subprocess.run([FFMPEG, "-hide_banner", "-loglevel", "error", "-y", "-i", str(wav), "-map_metadata", "-1", "-ac", str(channels), "-ar", str(RATE), "-c:a", "libvorbis", "-q:a", quality, "-fflags", "+bitexact", str(ogg)], check=True)


def build_ambience(manifest: dict) -> None:
    folder = OUT / "ambience"
    folder.mkdir(parents=True, exist_ok=True)
    tmp = ROOT / "output" / "_audio_tmp.wav"
    for name, (seconds, cross, parts, target) in AMBIENCE.items():
        mix = np.zeros(int((seconds + cross) * RATE))
        layers = []
        for key, start, gain, hp in parts:
            seg = read_native(key, start, seconds + cross + 0.5)[: len(mix)]
            seg = filt(seg - seg.mean(), "high", hp)
            seg = seg / (np.sqrt(np.mean(seg ** 2)) + 1e-9) * 10 ** (gain / 20)  # layer gains are relative RMS
            mix[: len(seg)] += seg
            slug, path = source(key)
            layers.append({"source": slug, "file": path.relative_to(SRC).as_posix(), "sha256": sha(path), "start": start, "seconds": seconds + cross, "gain": gain, "hp": hp})
        loop = make_loop(mix, seconds, cross)
        loop *= 10 ** ((target - rms_db(loop)) / 20)
        loop = np.clip(loop, -0.7, 0.7)
        _write_loop(manifest, folder, tmp, name, loop, layers, "mono 32 kHz; high-pass; layers RMS-balanced; %.1f s equal-power crossfade of the following material into the loop head; RMS normalised to %.0f dBFS; Vorbis q2" % (cross, target))
    seconds = 24.0
    loop = town_bed(seconds)
    loop *= 10 ** ((-34.0 - rms_db(loop)) / 20)
    loop = np.clip(loop, -0.7, 0.7)
    _write_loop(manifest, folder, tmp, "town", loop, [{"note": "sparse composite of anvil, hammer, saw, door and wood-knock recordings; see town_bed() in tools/audio/build_sound_identity.py", "sources": ["hammer-on-anvil", "blacksmiths-hammer", "30-cc0-sfx-loops", "100-cc0-sfx", "80-cc0-rpg-sfx", "75-cc0-breaking-falling-hit-sfx", "rpg-sound-pack"]}], "mono 32 kHz; events placed on a silent 24 s timeline; 3.8 kHz low-pass; RMS normalised to -34 dBFS; Vorbis q2")
    tmp.unlink(missing_ok=True)


def _write_loop(manifest: dict, folder: Path, tmp: Path, name: str, loop: np.ndarray, layers: list, processing: str) -> None:
    sf.write(str(tmp), loop, RATE, subtype="PCM_16")
    path = folder / (name + ".ogg")
    encode_ogg(tmp, path, "2", 1)
    rel = path.relative_to(ROOT).as_posix()
    seam = float(abs(loop[0] - loop[-1]))
    edge = rms_db(np.concatenate([loop[-RATE // 2:], loop[: RATE // 2]]))
    manifest["files"][rel] = {"kind": "ambience", "seconds": round(len(loop) / RATE, 3), "rms_dbfs": round(rms_db(loop), 2), "peak_dbfs": round(float(20 * np.log10(np.abs(loop).max() + 1e-9)), 2), "loop_seam_step": round(seam, 5), "loop_seam_rms_dbfs": round(edge, 2), "sha256": sha(path), "bytes": path.stat().st_size, "processing": processing, "layers": layers}
    print("ambience %-8s %.1fs rms %.1f seam step %.5f seam rms %.1f bytes %d" % (name, len(loop) / RATE, rms_db(loop), seam, edge, path.stat().st_size))


# --------------------------------------------------------------------------------------
# Music
# --------------------------------------------------------------------------------------
MUSIC = {
    # name: (key, start, end or None, fade-out seconds, target LUFS, description)
    "peace_old_tower_inn": ("medieval-the-old-tower-inn:The_Old_Tower_Inn.mp3", 0.0, None, 0.0, -20.0),
    "peace_bards_tale": ("medieval-the-bards-tale:The_Bards_Tale.mp3", 0.0, None, 0.0, -20.0),
    "peace_kings_feast": ("medieval-kings-feast:Kings_Feast.mp3", 0.0, None, 0.0, -20.0),
    "peace_market_day": ("medieval-market-day:Market_Day.mp3", 0.0, None, 0.0, -21.0),
    "menu_exploration": ("medieval-exploration:Exploration.mp3", 0.0, 120.0, 6.0, -20.0),
    "battle": ("medieval-battle:battle_7.mp3", 0.0, None, 0.0, -18.0),
    "stinger_victory": ("medieval-victory-theme:victory.wav", 0.0, None, 0.0, -17.0),
    "stinger_defeat": ("medieval-defeat-theme:defeat.wav", 0.0, 32.0, 5.0, -18.0),
}
MUSIC_QUALITY = "0.3"


def measure_lufs(path: Path) -> tuple[float, float]:
    out = subprocess.run([FFMPEG, "-hide_banner", "-nostats", "-i", str(path), "-af", "ebur128=peak=true", "-f", "null", "-"], capture_output=True, text=True).stderr
    summary = out[out.rfind("Summary:"):]
    integrated = float(summary.split("I:")[1].split("LUFS")[0])
    peak = float(summary.split("Peak:")[1].split("dBFS")[0])
    return integrated, peak


def build_music(manifest: dict) -> None:
    folder = OUT / "music"
    folder.mkdir(parents=True, exist_ok=True)
    tmp = ROOT / "output" / "_audio_tmp.wav"
    total = 0
    for name, (key, start, end, fade_out, target) in MUSIC.items():
        slug, path = source(key)
        cut = ["-ss", str(start)] + (["-to", str(end)] if end is not None else [])
        subprocess.run([FFMPEG, "-hide_banner", "-loglevel", "error", "-y", "-i", str(path)] + cut + ["-map_metadata", "-1", "-vn", "-ac", "2", "-ar", str(RATE), "-af", "silenceremove=start_periods=1:start_threshold=-60dB:start_silence=0.05,areverse,silenceremove=start_periods=1:start_threshold=-48dB:start_silence=0.3,areverse", str(tmp)], check=True)
        integrated, peak = measure_lufs(tmp)
        gain = target - integrated
        if peak + gain > -1.5:
            gain = -1.5 - peak  # never limit music: back the gain off instead so dynamics stay untouched
        duration = sf.info(str(tmp)).duration
        filters = "volume=%.2fdB" % gain
        if fade_out > 0:
            filters += ",afade=t=out:st=%.2f:d=%.2f" % (duration - fade_out, fade_out)
        filters += ",afade=t=in:st=0:d=0.02"
        out = folder / (name + ".ogg")
        subprocess.run([FFMPEG, "-hide_banner", "-loglevel", "error", "-y", "-i", str(tmp), "-map_metadata", "-1", "-af", filters, "-c:a", "libvorbis", "-q:a", MUSIC_QUALITY, "-fflags", "+bitexact", str(out)], check=True)
        final_i, final_peak = measure_lufs(out)
        rel = out.relative_to(ROOT).as_posix()
        total += out.stat().st_size
        manifest["files"][rel] = {"kind": "music", "seconds": round(sf.info(str(out)).duration, 2), "integrated_lufs": final_i, "true_peak_dbfs": final_peak, "sha256": sha(out), "bytes": out.stat().st_size, "processing": "stereo 32 kHz; leading/trailing digital silence removed; source %.1f-%s s; linear gain %+.2f dB to %.0f LUFS (no compression or limiting)%s; Vorbis q%s" % (start, "end" if end is None else "%.1f" % end, gain, target, "; %.0f s fade-out" % fade_out if fade_out else "", MUSIC_QUALITY), "layers": [{"source": slug, "file": path.relative_to(SRC).as_posix(), "sha256": sha(path)}]}
        print("music %-22s %6.1fs %6.1f LUFS peak %5.1f dBFS %7d bytes (%.0f kbps)" % (name, sf.info(str(out)).duration, final_i, final_peak, out.stat().st_size, out.stat().st_size * 8 / 1000 / sf.info(str(out)).duration))
    tmp.unlink(missing_ok=True)
    print("music total bytes", total)


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    manifest_path = OUT / "manifest.json"
    manifest = json.loads(manifest_path.read_text(encoding="utf-8")) if manifest_path.exists() else {"license": "CC0-1.0", "files": {}}
    for stage in STAGES:
        manifest["files"] = {k: v for k, v in manifest["files"].items() if v["kind"] != stage}
        {"sfx": build_sfx, "ambience": build_ambience, "music": build_music}[stage](manifest)
    index_path = SRC / "sources.json"
    index = json.loads(index_path.read_text(encoding="utf-8")) if index_path.exists() else {}
    used: set[str] = set()
    for record in manifest["files"].values():
        for item in record["layers"]:
            used.update(item.get("sources", [item.get("source")]))
    manifest["sources"] = {slug: {k: v for k, v in index[slug].items() if k != "files"} for slug in sorted(used) if slug in index}
    manifest["files"] = dict(sorted(manifest["files"].items()))
    manifest_path.write_text(json.dumps(manifest, indent=1) + "\n", encoding="utf-8", newline="\n")
    print("manifest: %d files, %d sources" % (len(manifest["files"]), len(manifest["sources"])))


if __name__ == "__main__":
    main()
