#!/usr/bin/env python3
"""Bounded, private storage for Pocket Kingdoms playtest gesture reports.

This server is reachable only on the game's Compose network. Nginx exposes the
single POST endpoint; reports are read through SSH, never through HTTP.
"""

from __future__ import annotations

import json
import math
import os
import re
import secrets
import shutil
import threading
import time
from datetime import datetime
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from typing import Any


MAX_BODY_BYTES = 256 * 1024
MAX_EVENTS = 600
MAX_DEPTH = 8
MAX_KEYS = 80
MAX_STRING = 400
ID_PATTERN = re.compile(r"[A-Za-z0-9_-]{1,64}\Z", re.ASCII)
REASONS = {"periodic", "problem", "pagehide", "startup"}

# No arbitrary descriptions, player names, headers, URLs or full user agents.
BUILD_FIELDS = {
    "product", "version", "channel", "source_revision", "source_tree_sha256",
    "built_at_utc", "godot", "entrypoint", "source_dirty",
    "runtime_revision", "served_revision", "source_mismatch",
}
DEVICE_FIELDS = {
    "browser_family", "platform", "viewport_width", "viewport_height",
    "screen_width", "screen_height", "device_pixel_ratio", "orientation",
    "standalone", "pointer_coarse", "touch_points", "online", "visibility",
    "ui_scale", "safe_area", "canvas_width", "canvas_height",
    "viewport", "css_canvas", "backing_canvas", "visual_viewport", "dpr",
    "screen", "browser", "pointer_types", "max_touch_points",
}
SIZE_FIELDS = {"width", "height", "x", "y", "offset_x", "offset_y", "offsetX", "offsetY", "offset_left", "offset_top", "scale"}
CONTEXT_FIELDS = {
    "ui_scale", "map_seed", "game_speed", "selection_count", "armed_action",
    "modal", "scene", "match_id", "difficulty", "population_cap",
}
EVENT_FIELDS = {"sequence", "elapsed_ms", "utc_ms", "kind", "fields"}
PROBLEM_FIELDS = {"report_id", "note", "marked_sequence", "preceding_events", "following_events", "events", "context"}
SENSITIVE_FIELDS = {
    "name", "names", "username", "user_name", "player_name", "display_name",
    "email", "email_address", "password", "token", "access_token", "refresh_token",
    "authorization", "cookie", "cookies", "chat", "message", "messages",
    "user_agent", "full_user_agent", "useragent", "ip", "ip_address", "remote_addr",
    "location", "latitude", "longitude", "gps", "headers", "url", "href", "referrer",
    "api_key", "secret", "credential", "credentials", "private_key", "auth", "bearer",
}


class ValidationError(ValueError):
    pass


class StorageFullError(OSError):
    pass


def _check_shape(value: Any, depth: int = 0) -> None:
    """Reject pathological JSON before removing fields we do not retain."""
    if depth > MAX_DEPTH:
        raise ValidationError("JSON nesting exceeds limit")
    if isinstance(value, dict):
        if len(value) > MAX_KEYS:
            raise ValidationError("Object has too many keys")
        for key, item in value.items():
            if not isinstance(key, str) or len(key) > 64:
                raise ValidationError("Invalid object key")
            _check_shape(item, depth + 1)
    elif isinstance(value, list):
        if len(value) > MAX_EVENTS:
            raise ValidationError("Array exceeds limit")
        for item in value:
            _check_shape(item, depth + 1)
    elif isinstance(value, str):
        if len(value) > MAX_STRING:
            raise ValidationError("String exceeds limit")
    elif isinstance(value, float) and not math.isfinite(value):
        raise ValidationError("Non-finite number")
    elif value is not None and not isinstance(value, (bool, int, float)):
        raise ValidationError("Unsupported JSON value")
    elif isinstance(value, int) and not isinstance(value, bool) and abs(value) > 10 ** 15:
        raise ValidationError("Number exceeds limit")


def _sensitive(key: str) -> bool:
    normalized = re.sub(r"(?<=[a-z])(?=[A-Z])", "_", key).lower().replace("-", "_")
    return normalized in SENSITIVE_FIELDS or any(
        normalized.endswith("_" + suffix)
        for suffix in ("email", "password", "token", "cookie", "user_agent", "ip_address", "player_name", "username")
    )


def _clean_game(value: Any) -> Any:
    """Keep bounded technical fields, while excluding identity/transport data."""
    if isinstance(value, dict):
        return {key: _clean_game(item) for key, item in value.items() if not _sensitive(key)}
    if isinstance(value, list):
        return [_clean_game(item) for item in value]
    return value


def _clean_metadata(value: dict[str, Any], fields: set[str]) -> dict[str, Any]:
    clean = {}
    for key, item in value.items():
        if key not in fields:
            continue
        if isinstance(item, dict):
            clean[key] = {subkey: subvalue for subkey, subvalue in item.items()
                          if subkey in SIZE_FIELDS and isinstance(subvalue, (int, float)) and not isinstance(subvalue, bool)}
        elif isinstance(item, list):
            clean[key] = [part for part in item if isinstance(part, (str, int, float, bool))][:16]
        else:
            clean[key] = item
    return clean


def _clean_event(value: dict[str, Any]) -> dict[str, Any]:
    return {key: _clean_game(item) for key, item in value.items() if key in EVENT_FIELDS}


def validate_envelope(value: Any) -> dict[str, Any]:
    _check_shape(value)
    if not isinstance(value, dict) or value.get("schema_version") != 1 or isinstance(value.get("schema_version"), bool):
        raise ValidationError("Unsupported schema_version")
    session_id = value.get("session_id")
    if not isinstance(session_id, str) or not ID_PATTERN.fullmatch(session_id):
        raise ValidationError("Invalid session_id")
    report_id = value.get("report_id")
    if report_id is not None and (not isinstance(report_id, str) or not ID_PATTERN.fullmatch(report_id)):
        raise ValidationError("Invalid report_id")
    reason = value.get("reason")
    if not isinstance(reason, str) or reason not in REASONS:
        raise ValidationError("Invalid reason")
    sent_at = value.get("sent_at_utc")
    if not isinstance(sent_at, str) or not re.fullmatch(r"\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d{1,6})?Z", sent_at):
        raise ValidationError("Invalid sent_at_utc")
    try:
        datetime.fromisoformat(sent_at.replace("Z", "+00:00"))
    except ValueError as error:
        raise ValidationError("Invalid sent_at_utc") from error
    for field in ("build", "device", "counters"):
        if not isinstance(value.get(field), dict):
            raise ValidationError("Missing " + field + " object")
    events = value.get("events")
    if not isinstance(events, list) or any(not isinstance(event, dict) for event in events):
        raise ValidationError("events must be an array of objects")
    for event in events:
        if not isinstance(event.get("kind"), str) or not 1 <= len(event["kind"]) <= 64:
            raise ValidationError("Invalid event kind")
        if "fields" in event and not isinstance(event["fields"], dict):
            raise ValidationError("Invalid event fields")
    clean = {
        "schema_version": 1,
        "session_id": session_id,
        "reason": reason,
        "sent_at_utc": sent_at,
        "build": _clean_metadata(value["build"], BUILD_FIELDS),
        "device": _clean_metadata(value["device"], DEVICE_FIELDS),
        "counters": {key: count for key, count in value["counters"].items()
                     if not _sensitive(key) and isinstance(count, int) and not isinstance(count, bool) and count >= 0},
        "events": [_clean_event(event) for event in events],
    }
    if report_id is not None:
        clean["report_id"] = report_id
    if "context" in value:
        if not isinstance(value["context"], dict):
            raise ValidationError("Invalid context")
        clean["context"] = _clean_metadata(value["context"], CONTEXT_FIELDS)
    if "note" in value:
        if not isinstance(value["note"], str):
            raise ValidationError("Invalid note")
        clean["note"] = value["note"]
    if "problem_window" in value:
        window = value["problem_window"]
        if not isinstance(window, (dict, list)):
            raise ValidationError("Invalid problem_window")
        clean["problem_window"] = (_clean_game(window) if isinstance(window, list)
                                   else {key: _clean_game(item) for key, item in window.items() if key in PROBLEM_FIELDS})
    return clean


def decode_envelope(body: bytes) -> dict[str, Any]:
    if len(body) > MAX_BODY_BYTES:
        raise ValidationError("Body exceeds limit")
    try:
        value = json.loads(body.decode("utf-8"))
    except (ValueError, UnicodeError, RecursionError) as error:
        raise ValidationError("Invalid JSON") from error
    return validate_envelope(value)


def encode_envelope(value: dict[str, Any]) -> bytes:
    return (json.dumps(value, sort_keys=True, separators=(",", ":"), ensure_ascii=False, allow_nan=False) + "\n").encode("utf-8")


class ReportStore:
    def __init__(self, directory: Path, *, max_sessions: int = 500,
                 max_reports_per_session: int = 32, max_bytes: int = 64 * 1024 * 1024,
                 ttl_seconds: int = 7 * 24 * 60 * 60, clock=time.time):
        self.directory = directory
        self.directory.mkdir(parents=True, exist_ok=True)
        self.max_sessions = max_sessions
        self.max_reports_per_session = max_reports_per_session
        self.max_bytes = max_bytes
        self.ttl_seconds = ttl_seconds
        self.clock = clock
        self.lock = threading.Lock()

    def _sessions(self) -> list[Path]:
        return [path for path in self.directory.iterdir()
                if path.is_dir() and not path.is_symlink() and ID_PATTERN.fullmatch(path.name)]

    def _files(self, directory: Path) -> list[Path]:
        return [path for path in directory.rglob("*.json") if path.is_file() and not path.is_symlink()]

    def _size(self) -> int:
        return sum(path.stat().st_size for session in self._sessions() for path in self._files(session))

    def _remove_session(self, session: Path) -> None:
        shutil.rmtree(session)

    def _prune(self, current: Path | None, required_bytes: int) -> None:
        cutoff = self.clock() - self.ttl_seconds
        for session in self._sessions():
            for path in self._files(session):
                if path.stat().st_mtime < cutoff:
                    path.unlink()
            if not self._files(session) and session != current:
                self._remove_session(session)
        others = sorted((session for session in self._sessions() if session != current),
                        key=lambda session: max((path.stat().st_mtime for path in self._files(session)), default=0))
        while others and (len(self._sessions()) > self.max_sessions or self._size() + required_bytes > self.max_bytes):
            self._remove_session(others.pop(0))
        if len(self._sessions()) > self.max_sessions or self._size() + required_bytes > self.max_bytes:
            raise StorageFullError("Diagnostics storage quota reached")

    def prune(self) -> None:
        with self.lock:
            self._prune(None, 0)

    @staticmethod
    def _atomic_write(destination: Path, payload: bytes) -> None:
        temporary = destination.with_name("." + destination.name + "." + secrets.token_hex(6) + ".tmp")
        try:
            with temporary.open("xb") as stream:
                stream.write(payload)
                stream.flush()
                os.fsync(stream.fileno())
            os.replace(temporary, destination)
        finally:
            temporary.unlink(missing_ok=True)

    def save(self, envelope: dict[str, Any]) -> dict[str, Any]:
        # The HTTP path always validates first; direct callers share that guard.
        envelope = validate_envelope(envelope)
        if envelope["reason"] == "problem" and "report_id" not in envelope:
            envelope["report_id"] = "PK_" + secrets.token_urlsafe(9)
        payload = encode_envelope(envelope)
        session = self.directory / envelope["session_id"]
        with self.lock:
            if session.is_symlink():
                raise OSError("Invalid storage directory")
            session.mkdir(exist_ok=True)
            latest = session / "latest.json"
            report = None
            report_payload = payload
            duplicate = False
            if "report_id" in envelope:
                reports = session / "reports"
                if reports.is_symlink():
                    raise OSError("Invalid reports directory")
                reports.mkdir(exist_ok=True)
                report = reports / (envelope["report_id"] + ".json")
                if report.is_symlink():
                    raise OSError("Invalid report file")
                if report.exists():
                    previous_bytes = report.read_bytes()
                    # Saved snapshots may combine the marked window and a later
                    # bounded ring; the transport body limit does not apply here.
                    previous = validate_envelope(json.loads(previous_bytes))
                    preserved = dict(envelope)
                    for field in ("problem_window", "note"):
                        if field not in preserved and field in previous:
                            preserved[field] = previous[field]
                    report_payload = encode_envelope(preserved)
                    duplicate = previous_bytes == report_payload
                existing = sorted((path for path in reports.glob("*.json") if path != report and not path.is_symlink()),
                                  key=lambda path: path.stat().st_mtime)
                while len(existing) + 1 > self.max_reports_per_session:
                    existing.pop(0).unlink()
            destinations = [(latest, payload)] + ([(report, report_payload)] if report is not None else [])
            required = sum(len(data) - (path.stat().st_size if path.exists() and not path.is_symlink() else 0)
                           for path, data in destinations)
            self._prune(session, required)
            if report is not None and not duplicate:
                self._atomic_write(report, report_payload)
            self._atomic_write(latest, payload)
            return {"stored": True, "report_id": envelope.get("report_id"), "duplicate": duplicate}


class DiagnosticsServer(ThreadingHTTPServer):
    daemon_threads = True

    def __init__(self, address: tuple[str, int], store: ReportStore):
        self.store = store
        super().__init__(address, DiagnosticsHandler)


class DiagnosticsHandler(BaseHTTPRequestHandler):
    server: DiagnosticsServer
    server_version = "PocketDiagnostics/1"

    def setup(self) -> None:
        super().setup()
        self.connection.settimeout(10)

    def log_message(self, format: str, *args: Any) -> None:
        # Standard access logs expose addresses and request/header material.
        pass

    def _reply(self, status: int, body: dict[str, Any] | None = None) -> None:
        payload = json.dumps(body, separators=(",", ":")).encode() if body is not None else b""
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(payload)))
        self.send_header("Cache-Control", "no-store")
        self.send_header("X-Content-Type-Options", "nosniff")
        self.end_headers()
        if payload:
            self.wfile.write(payload)

    def do_GET(self) -> None:
        if self.path == "/health":
            try:
                self.server.store.prune()
            except OSError:
                self._reply(503, {"ok": False})
                return
            self._reply(200, {"ok": True})
        else:
            self._reply(404, {"error": "Not found"})

    def do_POST(self) -> None:
        if self.path != "/api/playtest-diagnostics":
            self._reply(404, {"error": "Not found"})
            return
        if self.headers.get("Transfer-Encoding"):
            self._reply(400, {"error": "Content-Length required"})
            return
        try:
            length = int(self.headers.get("Content-Length", ""))
        except ValueError:
            self._reply(411, {"error": "Content-Length required"})
            return
        if length < 1 or length > MAX_BODY_BYTES:
            self._reply(413, {"error": "Body exceeds limit"})
            return
        if self.headers.get("Content-Type", "").split(";", 1)[0].strip().lower() != "application/json":
            self._reply(415, {"error": "JSON required"})
            return
        try:
            body = self.rfile.read(length)
            if len(body) != length:
                raise ValidationError("Incomplete body")
            envelope = decode_envelope(body)
            result = self.server.store.save(envelope)
        except (ValidationError, TimeoutError):
            self._reply(400, {"error": "Invalid diagnostics envelope"})
            return
        except StorageFullError:
            self._reply(507, {"error": "Diagnostics storage quota reached"})
            return
        except OSError:
            self._reply(503, {"error": "Diagnostics could not be saved"})
            return
        self._reply(202, result)


def main() -> None:
    directory = Path(os.environ.get("DIAGNOSTICS_DATA_DIR", "/data"))
    store = ReportStore(directory)
    server = DiagnosticsServer(("0.0.0.0", int(os.environ.get("DIAGNOSTICS_PORT", "8080"))), store)
    try:
        server.serve_forever()
    finally:
        server.server_close()


if __name__ == "__main__":
    main()
