"""Safety and committed-source provenance for the server context builder."""

import hashlib
import io
import json
from pathlib import Path
import subprocess
import tarfile
import tempfile
import unittest
from unittest.mock import patch

from build_mobile_web_windows import BuildError
from prepare_match_server import extract_committed_archive, prepare, sanitize_server_project, verify_imported_sources
from verify_mobile_web_artifacts import verify_manifest


PROJECT = '''[application]
config/name="Test"
run/main_scene="res://scenes/main/main.tscn"
[autoload]
DebugTools.debug="res://scripts/ui/debug_bootstrap.gd"
MCPGameBridge="res://scripts/managers/runtime_game_bridge.gd"
[editor_plugins]
enabled=foo
[godot_mcp]
port=1
'''


class MatchServerBuildTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)

    def command(self, *args):
        return subprocess.check_output(["git", "-C", str(self.root), *args], stderr=subprocess.PIPE)

    def repository(self, protocol=3):
        self.command("init", "-q")
        files = {
            "assets/art.svg": "committed art\n", "scripts/main.gd": "committed script\n",
            "scripts/network/network_session.gd": "const PROTOCOL := %d\n" % protocol,
            "scripts/ui/debug_bootstrap.gd": "developer only\n",
            "scenes/network/server_lobby.tscn": "committed scene\n",
            "default_bus_layout.tres": "bus\n", "icon.svg": "icon\n",
            "icon.svg.import": "import\n", "project.godot": PROJECT,
            "deploy/match-server/Dockerfile": "FROM debian:bookworm-slim\nCOPY runtime /srv/game\n",
        }
        for name, content in files.items():
            path = self.root / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(content, encoding="utf-8", newline="\n")
        self.command("add", ".")
        self.command("-c", "user.name=Server build test", "-c", "user.email=build@example.invalid", "commit", "-qm", "fixture")
        return files

    def prepare_fixture(self, output="build/server", mutate=False):
        binary = self.root / "fake-godot"
        binary.touch()
        check_output = subprocess.check_output

        def command(arguments, **kwargs):
            if arguments == [str(binary), "--version"]:
                return "4.6.stable.official\n"
            return check_output(arguments, **kwargs)

        def importer(_binary, arguments, log):
            runtime = Path(arguments[2])
            cache = runtime / ".godot/imported"
            cache.mkdir(parents=True)
            (cache / "derived.ctex").write_bytes(b"generated cache")
            if mutate:
                (runtime / "scripts/main.gd").write_text("unexpected rewrite\n")
            log.write_text("import complete\n")

        with patch("prepare_match_server.subprocess.check_output", side_effect=command), patch("prepare_match_server.run_godot", side_effect=importer):
            return prepare(self.root, "HEAD", binary, output)

    def test_dirty_checkout_cannot_change_committed_context_and_manifest_is_closed(self):
        files = self.repository()
        commit = self.command("rev-parse", "HEAD").decode().strip()
        (self.root / "scripts/main.gd").write_text("uncommitted edit\n")
        (self.root / "scripts/untracked.gd").write_text("untracked\n")
        (self.root / "scripts/network/network_session.gd").write_text("const PROTOCOL := 99\n")
        result = self.prepare_fixture()
        target = Path(result["context"])
        self.assertEqual((target / "runtime/scripts/main.gd").read_text(), files["scripts/main.gd"])
        self.assertFalse((target / "runtime/scripts/untracked.gd").exists())
        self.assertFalse((target / "runtime/scripts/ui/debug_bootstrap.gd").exists())
        source = json.loads((target / "SERVER_SOURCE.json").read_text())
        self.assertEqual(source["source_revision"], commit)
        self.assertFalse(source["source_dirty"])
        self.assertIs(type(source["network_protocol"]), int)
        self.assertEqual(source["network_protocol"], 3)
        self.assertEqual(result["network_protocol"], 3)
        self.assertEqual(source["committed_source_sha256"]["runtime/project.godot"], hashlib.sha256(PROJECT.encode()).hexdigest())
        self.assertEqual(result["manifest_sha256"], verify_manifest(target)[1])
        (target / "runtime/extra.gd").write_text("unmanifested\n")
        with self.assertRaises(RuntimeError):
            verify_manifest(target)

    def test_legacy_protocol_two_is_derived_and_bad_protocol_never_imports(self):
        self.repository(protocol=2)
        result = self.prepare_fixture()
        self.assertEqual(json.loads((Path(result["context"]) / "SERVER_SOURCE.json").read_text())["network_protocol"], 2)
        source = self.root / "scripts/network/network_session.gd"
        source.write_text("const PROTOCOL := true\n")
        self.command("add", "scripts/network/network_session.gd")
        self.command("-c", "user.name=Server build test", "-c", "user.email=build@example.invalid", "commit", "-qm", "invalid protocol fixture")
        with self.assertRaisesRegex(BuildError, "positive exact JSON integer"):
            self.prepare_fixture(output="build/invalid-protocol")
        self.assertFalse((self.root / "build/invalid-protocol-import.log").exists())
        self.assertFalse((self.root / "build/invalid-protocol/SERVER_SOURCE.json").exists())

    def test_import_rewriting_committed_input_never_gets_a_success_receipt(self):
        self.repository()
        with self.assertRaisesRegex(BuildError, "differs from committed input"):
            self.prepare_fixture(mutate=True)
        self.assertFalse((self.root / "build/server/SERVER_SOURCE.json").exists())
        self.assertFalse((self.root / "build/server/SHA256SUMS.txt").exists())

    def test_nested_checksum_named_file_is_not_invisible_to_closure(self):
        self.repository()
        result = self.prepare_fixture()
        target = Path(result["context"])
        (target / "runtime/SHA256SUMS.txt").write_text("unmanifested content\n")
        with self.assertRaises(RuntimeError):
            verify_manifest(target)

    def test_output_cannot_overwrite_or_escape_build(self):
        self.repository()
        self.prepare_fixture()
        for output in ("build/server", "build/../outside", "build/nested/deep", "other"):
            with self.assertRaises(BuildError, msg=output):
                self.prepare_fixture(output)

    def test_server_project_requires_one_entrypoint_and_keeps_runtime_bridge(self):
        result = sanitize_server_project(PROJECT, "abcdef012345")
        self.assertIn('run/main_scene="res://scenes/network/server_lobby.tscn"', result)
        self.assertIn('config/playtest_revision="abcdef012345"', result)
        self.assertNotIn(".debug", result)
        self.assertNotIn("[editor_plugins]", result)
        self.assertIn('MCPGameBridge="res://scripts/managers/runtime_game_bridge.gd"', result)
        for source in (PROJECT.replace('run/main_scene=', 'missing='), PROJECT + '[application]\nrun/main_scene="res://other.tscn"\n', PROJECT.replace('MCPGameBridge=', 'OtherBridge=')):
            with self.assertRaises(BuildError):
                sanitize_server_project(source, "abcdef012345")

    def test_archive_rejects_traversal_links_and_case_collisions(self):
        for names, link in ((["../escape"], False), (["scripts/linked.gd"], True), (["scripts/a.gd", "scripts/A.gd"], False)):
            with self.subTest(names=names):
                payload = io.BytesIO()
                with tarfile.open(fileobj=payload, mode="w") as packed:
                    for name in names:
                        entry = tarfile.TarInfo(name)
                        if link:
                            entry.type = tarfile.SYMTYPE
                            entry.linkname = "../../outside"
                            packed.addfile(entry)
                        else:
                            entry.size = 1
                            packed.addfile(entry, io.BytesIO(b"x"))
                with tempfile.TemporaryDirectory(dir=self.root) as folder:
                    with self.assertRaises(BuildError):
                        extract_committed_archive(payload.getvalue(), Path(folder))
        self.assertFalse((self.root.parent / "escape").exists())

    def test_import_cannot_add_uncommitted_executable_source(self):
        runtime = self.root / "runtime"
        runtime.mkdir()
        (runtime / "untracked.gd").write_text("surprise")
        with self.assertRaisesRegex(BuildError, "Uncommitted runtime source"):
            verify_imported_sources(self.root, {}, "")


if __name__ == "__main__":
    unittest.main()
