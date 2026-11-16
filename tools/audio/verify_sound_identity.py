"""Measure every shipped sound-identity file with ffmpeg and write analysis.json.

For each file: duration, sample peak (volumedetect), EBU R128 integrated loudness and
maximum momentary loudness (ebur128; integrated needs >= 0.4 s of signal), silence at
head and tail (first/last sample above -50 dBFS), and for loops the continuity of the
loop boundary measured on the DECODED shipped file (wrap-around step versus the typical
sample-to-sample step, and RMS just before the end versus just after the start).
Exits non-zero when a file breaks its class limits.

Usage: python tools/audio/verify_sound_identity.py <ffmpeg.exe>
"""
from pathlib import Path
import json
import re
import subprocess
import sys
import numpy as np

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "assets/audio/identity"
FFMPEG = sys.argv[1] if len(sys.argv) > 1 else "ffmpeg"


def decode(path: Path) -> tuple[np.ndarray, int]:
    raw = subprocess.run([FFMPEG, "-hide_banner", "-loglevel", "error", "-i", str(path), "-ac", "1", "-f", "f32le", "-"], capture_output=True, check=True).stdout
    probe = subprocess.run([FFMPEG, "-hide_banner", "-i", str(path)], capture_output=True, text=True).stderr
    rate = int(re.search(r"(\d+) Hz", probe).group(1))
    return np.frombuffer(raw, dtype=np.float32).astype(np.float64), rate


def ebur128(path: Path) -> tuple[float | None, float | None, float]:
    err = subprocess.run([FFMPEG, "-hide_banner", "-nostats", "-i", str(path), "-af", "ebur128=peak=sample", "-f", "null", "-"], capture_output=True, text=True).stderr
    momentary = [float(v) for v in re.findall(r" M:\s*(-?[\d.]+)", err)]
    summary = err[err.rfind("Summary:"):]
    integrated = re.search(r"I:\s*(-?[\d.]+) LUFS", summary)
    peak = re.search(r"Peak:\s*(-?[\d.]+) dBFS", summary)
    value = float(integrated.group(1)) if integrated else None
    if value is not None and value <= -69.0:
        value = None  # too short for a gated measurement
    return value, (max(momentary) if momentary else None), float(peak.group(1)) if peak else float("nan")


def main() -> int:
    manifest = json.loads((OUT / "manifest.json").read_text(encoding="utf-8"))
    analysis = {}
    problems = []
    for rel, record in manifest["files"].items():
        path = ROOT / rel
        data, rate = decode(path)
        level = np.abs(data)
        loud = np.nonzero(level > 10 ** (-50 / 20))[0]
        head = float(loud[0] / rate) if len(loud) else 0.0
        tail = float((len(data) - 1 - loud[-1]) / rate) if len(loud) else 0.0
        integrated, momentary, peak = ebur128(path)
        entry = {"kind": record["kind"], "seconds": round(len(data) / rate, 3), "sample_rate": rate, "bytes": path.stat().st_size, "peak_dbfs": round(peak, 2), "integrated_lufs": integrated, "max_momentary_lufs": momentary, "head_silence_s": round(head, 3), "tail_silence_s": round(tail, 3)}
        if record["kind"] == "ambience":
            typical = float(np.percentile(np.abs(np.diff(data)), 99)) + 1e-9
            wrap = float(abs(data[0] - data[-1]))
            n = rate // 4
            before = 20 * np.log10(np.sqrt(np.mean(data[-n:] ** 2)) + 1e-9)
            after = 20 * np.log10(np.sqrt(np.mean(data[:n] ** 2)) + 1e-9)
            entry.update({"loop_wrap_step": round(wrap, 5), "loop_typical_step_p99": round(typical, 5), "loop_rms_before_end_db": round(float(before), 2), "loop_rms_after_start_db": round(float(after), 2)})
            silent_edges = before < -70 and after < -70
            if wrap > typical * 1.5 and not silent_edges:
                problems.append("%s: loop wrap step %.4f exceeds 1.5x typical %.4f" % (rel, wrap, typical))
            if not silent_edges and abs(before - after) > 6.0:
                problems.append("%s: loop level jump %.1f dB" % (rel, before - after))
        if peak > -0.9:
            problems.append("%s: peak %.2f dBFS" % (rel, peak))
        if record["kind"] == "sfx" and (head > 0.02 or tail > 0.12):
            problems.append("%s: silence head %.3f tail %.3f" % (rel, head, tail))
        if record["kind"] == "music" and (head > 0.6 or tail > 1.5):
            problems.append("%s: silence head %.3f tail %.3f" % (rel, head, tail))
        analysis[rel] = entry
    (OUT / "analysis.json").write_text(json.dumps(analysis, indent=1) + "\n", encoding="utf-8", newline="\n")
    families: dict[str, list] = {}
    for rel, entry in analysis.items():
        record = manifest["files"][rel]
        key = record.get("loudness_class", record["kind"]) if record["kind"] == "sfx" else record["kind"]
        families.setdefault(key, []).append((rel, entry, record))
    for key, items in sorted(families.items()):
        peaks = [e["peak_dbfs"] for _, e, _ in items]
        moment = [e["max_momentary_lufs"] for _, e, _ in items if e["max_momentary_lufs"] is not None]
        rms = [r["active_rms_dbfs"] for _, _, r in items if "active_rms_dbfs" in r]
        print("%-9s n=%3d  seconds %.2f..%.2f  peak %.1f..%.1f dBFS  max-momentary %s  active-rms %s  bytes %d" % (key, len(items), min(e["seconds"] for _, e, _ in items), max(e["seconds"] for _, e, _ in items), min(peaks), max(peaks), "%.1f..%.1f LUFS" % (min(moment), max(moment)) if moment else "n/a", "%.1f..%.1f" % (min(rms), max(rms)) if rms else "n/a", sum(e["bytes"] for _, e, _ in items)))
    for rel, entry in analysis.items():
        if entry["kind"] != "sfx":
            print("%-52s %7.2fs  I %s LUFS  peak %6.2f  head %.3f tail %.3f %s" % (rel.split("identity/")[1], entry["seconds"], entry["integrated_lufs"], entry["peak_dbfs"], entry["head_silence_s"], entry["tail_silence_s"], ("wrap %.5f/typ %.5f  rms %.1f->%.1f" % (entry["loop_wrap_step"], entry["loop_typical_step_p99"], entry["loop_rms_before_end_db"], entry["loop_rms_after_start_db"])) if "loop_wrap_step" in entry else ""))
    print("files %d, total source bytes %d" % (len(analysis), sum(e["bytes"] for e in analysis.values())))
    for problem in problems:
        print("PROBLEM", problem)
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main())
