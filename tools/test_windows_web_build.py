"""Cross-platform build safety and provenance regression checks."""

import os
import subprocess
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

from build_mobile_web_windows import BuildError, allowed_source, output_directory, sanitize_project, stage_committed_source, write_manifest
from verify_mobile_web_artifacts import ABSOLUTE_PATH_PATTERN, installed_template_archive, verify_manifest


class WindowsWebBuildTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)

    def test_runtime_allowlist_rejects_developer_and_sensitive_paths(self):
        for name in ("assets/art.png", "scripts/data/civilization_data.gd", "scenes/ui/main_menu.tscn", "web/pocket_shell.html", "project.godot"):
            self.assertTrue(allowed_source(name), name)
        for name in ("tools/test.gd", "addons/godot_mcp/plugin.gd", "scripts/ui/debug_panel.gd", "scripts/ui/debug_bootstrap.gd.uid", "scripts/.env.secret", "../scripts/x.gd", "/scripts/x.gd", "scripts\\x.gd", "docs/secret.txt"):
            self.assertFalse(allowed_source(name), name)

    def test_output_is_immutable_direct_child_without_traversal(self):
        output = output_directory(self.root, "build/valid")
        self.assertEqual(output, self.root / "build/valid")
        output.mkdir()
        for name in ("build/valid", "build/nested/deeper", "build/../outside", "outside", "build/.gdignore"):
            with self.assertRaises(BuildError, msg=name):
                output_directory(self.root, name)

    def test_project_removes_debug_but_preserves_runtime_and_revision(self):
        source = '[application]\nconfig/name="Test"\n[autoload]\nDebugTools.debug="res://debug.gd"\nMCPGameBridge="res://scripts/managers/runtime_game_bridge.gd"\n[editor_plugins]\nenabled=foo\n[godot_mcp]\nport=1\n[editor]\nimport/use_multiple_threads=false\n'
        result = sanitize_project(source, "abcdef012345")
        self.assertNotIn(".debug", result)
        self.assertNotIn("[editor_plugins]", result)
        self.assertNotIn("[godot_mcp]", result)
        self.assertIn('config/playtest_revision="abcdef012345"', result)
        self.assertIn('MCPGameBridge="res://scripts/managers/runtime_game_bridge.gd"', result)
        self.assertEqual(result.count("export/convert_text_resources_to_binary=false"), 1)
        self.assertEqual(sanitize_project(result, "fedcba543210").count("config/playtest_revision="), 1)

    def test_manifest_closes_and_rejects_added_payload(self):
        (self.root / "runtime.bin").write_bytes(b"release")
        write_manifest(self.root, self.root / "SHA256SUMS.txt")
        self.assertEqual(verify_manifest(self.root)[0], 1)
        (self.root / "extra.txt").write_text("unexpected")
        with self.assertRaises(RuntimeError):
            verify_manifest(self.root)

    def test_committed_stage_ignores_modified_and_untracked_runtime(self):
        def command(*args):
            return subprocess.check_output(["git", "-C", str(self.root), *args], stderr=subprocess.PIPE)
        command("init", "-q")
        command("config", "core.autocrlf", "true")
        for name in ("assets", "scenes", "scripts", "web", "tools"):
            (self.root / name).mkdir()
        for name in ("assets/a.txt", "scenes/a.tscn", "scripts/main.gd", "web/a.html", "default_bus_layout.tres", "export_presets.cfg", "icon.svg", "icon.svg.import", "project.godot", "tools/render_pwa_icon.gd"):
            (self.root / name).write_text("committed\n", encoding="utf-8")
        command("add", ".")
        command("-c", "user.name=Build test", "-c", "user.email=build@example.invalid", "commit", "-qm", "fixture")
        (self.root / "scripts/main.gd").write_text("edited\n", encoding="utf-8")
        (self.root / "scripts/untracked.gd").write_text("untracked\n", encoding="utf-8")
        stage = self.root / "stage"
        stage.mkdir()
        stage_committed_source(self.root, "HEAD", stage, self.root / "helper.gd")
        self.assertEqual((stage / "scripts/main.gd").read_bytes(), b"committed\n")
        self.assertFalse((stage / "scripts/untracked.gd").exists())
        self.assertFalse((stage / "tools").exists())
        self.assertTrue((self.root / "helper.gd").is_file())

    def test_template_paths_match_each_platform(self):
        with patch("sys.platform", "win32"), patch.dict(os.environ, {"APPDATA": str(self.root)}):
            self.assertEqual(installed_template_archive("4.6.stable"), self.root / "Godot/export_templates/4.6.stable/web_nothreads_release.zip")
        with patch("sys.platform", "linux"), patch.dict(os.environ, {"XDG_DATA_HOME": str(self.root)}):
            self.assertEqual(installed_template_archive("4.6.stable"), self.root / "godot/export_templates/4.6.stable/web_nothreads_release.zip")

    def test_windows_absolute_path_scan_covers_native_escaped_and_godot_paths(self):
        for path in (b"C:\\Users\\private\\game", b"C:\\\\Users\\\\private", b"C:/Users/private/game", b"file:///Users/private/game"):
            self.assertIsNotNone(ABSOLUTE_PATH_PATTERN.search(path), path)
        self.assertIsNone(ABSOLUTE_PATH_PATTERN.search(b"res://scripts/main/main.gd"))


if __name__ == "__main__":
    unittest.main()
