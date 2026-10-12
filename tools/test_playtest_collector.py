"""Private collector regression tests, including real HTTP and disk failures."""

import importlib.util
import json
import os
import tempfile
import threading
import unittest
import urllib.error
import urllib.request
from pathlib import Path
from unittest import mock


SOURCE = Path(__file__).resolve().parents[1] / "deploy" / "diagnostics_server.py"
SPEC = importlib.util.spec_from_file_location("diagnostics_server", SOURCE)
collector = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(collector)


def packet(session="s_123", reason="periodic", report=None):
    value = {
        "schema_version": 1, "session_id": session, "reason": reason,
        "sent_at_utc": "2026-10-12T01:15:30.123Z",
        "build": {"source_revision": "a13d1f93bd02", "source_tree_sha256": "abc"},
        "device": {"viewport": {"width": 844, "height": 390}, "dpr": 3, "browser": "Safari"},
        "context": {"ui_scale": 1.15, "selection_count": 2, "map_seed": 444},
        "counters": {"pointerdown": 2, "world select miss": 1},
        "events": [{"sequence": 2, "elapsed_ms": 250, "utc_ms": 1791767700000,
                    "kind": "world select miss", "fields": {"screen_position": {"x": 242, "y": 180}, "candidate_count": 0}}],
    }
    if report:
        value["report_id"] = report
    return value


class EnvelopeTests(unittest.TestCase):
    def test_useful_event_data_and_coarse_device_metadata_survive(self):
        value = collector.validate_envelope(packet())
        self.assertEqual(value["events"][0]["fields"]["screen_position"], {"x": 242, "y": 180})
        self.assertEqual(value["device"]["viewport"], {"width": 844, "height": 390})
        self.assertEqual(value["counters"]["world select miss"], 1)

    def test_unknown_metadata_and_nested_identity_transport_fields_are_removed(self):
        value = packet()
        value.update({"email": "unwanted@example.test", "token": "secret", "headers": {"Cookie": "secret"}})
        value["build"]["name"] = "unwanted"
        value["device"].update({"full_user_agent": "full agent", "ip": "192.0.2.20", "viewport": {"width": 844, "height": 390, "email": "bad"}})
        value["events"][0]["fields"].update({"playerName": "unwanted", "email": "bad", "accessToken": "secret",
                                             "headers": {"Cookie": "secret"}, "location": {"latitude": 3},
                                             "world_position": {"x": 25, "y": 17}, "inner": {"password": "secret", "dx": 4}})
        value["counters"]["token"] = 9
        stored = collector.encode_envelope(collector.validate_envelope(value)).decode()
        for forbidden in ("unwanted", "secret", "full agent", "192.0.2.20", "latitude", "Cookie", "password", "accessToken"):
            self.assertNotIn(forbidden, stored)
        self.assertIn('"world_position":{"x":25,"y":17}', stored)
        self.assertIn('"inner":{"dx":4}', stored)

    def test_problem_note_and_window_survive_without_automatic_identity_metadata(self):
        value = packet(reason="problem", report="PK-123abc")
        value["note"] = "Unit taps missed after moving the camera."
        value["problem_window"] = {"report_id": "PK-123abc", "note": value["note"], "marked_sequence": 2,
                                   "preceding_events": value["events"], "following_events": [], "email": "bad"}
        stored = collector.validate_envelope(value)
        self.assertEqual(stored["note"], value["note"])
        self.assertEqual(stored["problem_window"]["preceding_events"], value["events"])
        self.assertNotIn("email", stored["problem_window"])

    def test_ids_reject_traversal_unicode_empty_and_oversize(self):
        for invalid in ("../escape", "a/b", "", "a" * 65, "é", "/tmp/x", "a.b"):
            for field in ("session_id", "report_id"):
                with self.subTest(field=field, invalid=invalid):
                    value = packet()
                    value[field] = invalid
                    with self.assertRaises(collector.ValidationError):
                        collector.validate_envelope(value)

    def test_wrong_schema_reason_dates_and_event_shapes_reject(self):
        cases = [("schema_version", 2), ("schema_version", True), ("reason", {}), ("reason", "unknown"),
                 ("sent_at_utc", "2026-99-88T25:61:00Z"), ("events", "bad"), ("events", [{}]),
                 ("events", [{"kind": "tap", "fields": []}]), ("counters", [])]
        for field, replacement in cases:
            with self.subTest(field=field, replacement=replacement):
                value = packet()
                value[field] = replacement
                with self.assertRaises(collector.ValidationError):
                    collector.validate_envelope(value)

    def test_array_depth_string_keys_and_nonfinite_limits_reject(self):
        nested = 1
        for _ in range(10):
            nested = {"child": nested}
        cases = [({"extra": nested}), ({"events": [{"kind": "tap"}] * 601}),
                 ({"note": "x" * 401}), ({"extra": {str(i): i for i in range(81)}}),
                 ({"extra": {"x": float("nan")}}), ({"extra": {"x": 10 ** 16}})]
        for additions in cases:
            with self.subTest(additions=str(additions)[:40]):
                value = packet()
                value.update(additions)
                with self.assertRaises(collector.ValidationError):
                    collector.validate_envelope(value)
        for body in (b"{", b"\xff", b" " * (collector.MAX_BODY_BYTES + 1)):
            with self.assertRaises(collector.ValidationError):
                collector.decode_envelope(body)


class StoreTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.store = collector.ReportStore(self.root)

    def test_latest_updates_and_problem_snapshot_survives_later_periodic_flush(self):
        marked = packet(reason="problem", report="PK-123abc")
        result = self.store.save(marked)
        self.assertEqual(result["report_id"], "PK-123abc")
        report = self.root / "s_123/reports/PK-123abc.json"
        original = report.read_bytes()
        periodic = packet()
        periodic["events"].append({"kind": "camera pan", "fields": {"dx": 45}})
        self.store.save(periodic)
        self.assertEqual(report.read_bytes(), original)
        self.assertEqual(len(json.loads((self.root / "s_123/latest.json").read_bytes())["events"]), 2)
        self.assertFalse(list(self.root.rglob("*.tmp")))

    def test_identical_report_dedup_and_following_trace_update_same_code(self):
        value = packet(reason="problem", report="PK-123abc")
        self.assertFalse(self.store.save(value)["duplicate"])
        report = self.root / "s_123/reports/PK-123abc.json"
        stamp = report.stat().st_mtime_ns
        self.assertTrue(self.store.save(value)["duplicate"])
        self.assertEqual(report.stat().st_mtime_ns, stamp)
        value["events"].append({"kind": "camera pan", "fields": {"dx": 5}})
        self.assertFalse(self.store.save(value)["duplicate"])
        self.assertEqual(len(list((self.root / "s_123/reports").glob("*.json"))), 1)
        self.assertEqual(len(json.loads(report.read_bytes())["events"]), 2)

    def test_server_can_generate_safe_problem_code(self):
        result = self.store.save(packet(reason="problem"))
        self.assertRegex(result["report_id"], r"^PK_[A-Za-z0-9_-]+$")
        self.assertTrue((self.root / "s_123/reports" / (result["report_id"] + ".json")).exists())

    def test_same_code_keeps_marked_window_when_current_ring_has_moved_on(self):
        marked = packet(reason="problem", report="PK-123abc")
        marked["note"] = "Unit taps missed."
        marked["problem_window"] = {"marked_sequence": 2, "preceding_events": marked["events"]}
        self.store.save(marked)
        following = packet(reason="periodic", report="PK-123abc")
        following["events"] = [{"kind": "camera pan", "sequence": 200, "fields": {"dx": 45}}]
        self.store.save(following)
        report = json.loads((self.root / "s_123/reports/PK-123abc.json").read_bytes())
        self.assertEqual(report["note"], marked["note"])
        self.assertEqual(report["problem_window"], marked["problem_window"])
        self.assertEqual(report["events"][0]["sequence"], 200)

    def test_idle_pruning_removes_expired_problem_reports(self):
        self.store.save(packet(reason="problem", report="PK-123abc"))
        for path in self.root.rglob("*.json"):
            os.utime(path, (1, 1))
        self.store.prune()
        self.assertFalse(list(self.root.iterdir()))

    def test_session_report_ttl_and_disk_quotas_are_enforced(self):
        store = collector.ReportStore(self.root, max_sessions=2, max_reports_per_session=2)
        for number in range(3):
            store.save(packet(reason="problem", report="PK-" + str(number)))
        self.assertEqual(len(list((self.root / "s_123/reports").glob("*.json"))), 2)
        store.save(packet(session="second"))
        store.save(packet(session="third"))
        self.assertEqual(len(store._sessions()), 2)
        self.assertFalse((self.root / "s_123").exists())
        stale = self.root / "second/latest.json"
        os.utime(stale, (1, 1))
        store.save(packet(session="fourth"))
        self.assertFalse((self.root / "second").exists())
        tiny = collector.ReportStore(self.root / "tiny", max_bytes=10)
        with self.assertRaises(collector.StorageFullError):
            tiny.save(packet())
        self.assertFalse((self.root / "tiny/s_123/latest.json").exists())

    def test_disk_pressure_evicts_old_sessions_and_preserves_current(self):
        size = len(collector.encode_envelope(collector.validate_envelope(packet())))
        store = collector.ReportStore(self.root, max_bytes=size + 30)
        store.save(packet())
        store.save(packet(session="second"))
        self.assertFalse((self.root / "s_123").exists())
        self.assertTrue((self.root / "second/latest.json").exists())
        self.assertLessEqual(store._size(), store.max_bytes)

    def test_symlink_directory_cannot_escape_data_volume(self):
        outside = self.root / "outside"
        outside.mkdir()
        (self.root / "evil").symlink_to(outside, target_is_directory=True)
        with self.assertRaises(OSError):
            self.store.save(packet(session="evil"))
        self.assertFalse((outside / "latest.json").exists())


class HTTPTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.store = collector.ReportStore(self.root)
        self.server = collector.DiagnosticsServer(("127.0.0.1", 0), self.store)
        self.thread = threading.Thread(target=self.server.serve_forever, daemon=True)
        self.thread.start()
        self.addCleanup(self.stop)
        self.origin = "http://127.0.0.1:" + str(self.server.server_port)

    def stop(self):
        self.server.shutdown()
        self.server.server_close()
        self.thread.join(timeout=2)

    def request(self, path, body=None, content_type="application/json", headers=None):
        request = urllib.request.Request(self.origin + path, data=body)
        if body is not None:
            request.add_header("Content-Type", content_type)
        for key, value in (headers or {}).items():
            request.add_header(key, value)
        try:
            with urllib.request.urlopen(request, timeout=2) as response:
                return response.status, response.read(), response.headers
        except urllib.error.HTTPError as error:
            return error.code, error.read(), error.headers

    def post(self, value):
        return self.request("/api/playtest-diagnostics", json.dumps(value).encode())

    def test_health_real_post_and_no_public_report_retrieval(self):
        self.assertEqual(self.request("/health")[0], 200)
        status, body, headers = self.post(packet(reason="problem", report="PK-123abc"))
        self.assertEqual(status, 202)
        self.assertTrue(json.loads(body)["stored"])
        self.assertEqual(headers["Cache-Control"], "no-store")
        for path in ("/api/playtest-diagnostics", "/s_123/latest.json", "/reports/PK-123abc.json", "/health?report=PK-123abc"):
            self.assertEqual(self.request(path)[0], 404)
        self.assertTrue((self.root / "s_123/reports/PK-123abc.json").exists())

    def test_malformed_media_type_oversize_schema_and_traversal_reject(self):
        self.assertEqual(self.request("/api/playtest-diagnostics", b"not json")[0], 400)
        self.assertEqual(self.request("/api/playtest-diagnostics", b"{}", content_type="text/plain")[0], 415)
        # Probe the length gate without racing a refused body's socket close.
        self.assertEqual(self.request("/api/playtest-diagnostics", b"x",
                                      headers={"Content-Length": str(collector.MAX_BODY_BYTES + 1)})[0], 413)
        value = packet(session="../escape")
        self.assertEqual(self.post(value)[0], 400)
        value = packet()
        value["schema_version"] = 4
        self.assertEqual(self.post(value)[0], 400)
        self.assertEqual(self.request("/api/playtest-diagnostics?token=x", b"{}")[0], 404)
        self.assertFalse(list(self.root.rglob("*.json")))

    def test_write_failure_and_storage_quota_never_acknowledge_success(self):
        with mock.patch.object(self.store, "_atomic_write", side_effect=OSError("disk offline")):
            self.assertEqual(self.post(packet())[0], 503)
        self.store.max_bytes = 1
        self.assertEqual(self.post(packet())[0], 507)
        self.assertFalse(list(self.root.rglob("*.json")))

    def test_headers_and_remote_address_are_not_persisted(self):
        body = json.dumps(packet()).encode()
        status, _, _ = self.request("/api/playtest-diagnostics", body,
                                    headers={"User-Agent": "UNWANTED-full-agent", "Cookie": "UNWANTED-secret", "X-Forwarded-For": "192.0.2.88"})
        self.assertEqual(status, 202)
        saved = (self.root / "s_123/latest.json").read_text()
        self.assertNotIn("UNWANTED", saved)
        self.assertNotIn("192.0.2.88", saved)


if __name__ == "__main__":
    unittest.main()
