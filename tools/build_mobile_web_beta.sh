#!/bin/sh
set -eu

PROJECT_ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
GODOT_BIN=${GODOT_BIN:-/Applications/Godot.app/Contents/MacOS/Godot}
BUILD_ROOT="$PROJECT_ROOT/build"

if [ ! -x "$GODOT_BIN" ]; then
	echo "Godot 4.6 executable not found at $GODOT_BIN" >&2
	exit 3
fi

GODOT_VERSION=$("$GODOT_BIN" --version | tr -d '\r\n')
case "$GODOT_VERSION" in
	4.6|4.6.*) ;;
	*)
		echo "Godot 4.6 is required; found: $GODOT_VERSION" >&2
		exit 3
		;;
esac

# `rsync --delete` must never receive a path that can escape the dedicated
# build root. Resolve the root physically, require the output to be one direct
# child, and reject both traversal syntax and a symlink destination.
if [ -L "$BUILD_ROOT" ]; then
	echo "Refusing symlink build root: $BUILD_ROOT" >&2
	exit 2
fi
if [ -e "$BUILD_ROOT" ] && [ ! -d "$BUILD_ROOT" ]; then
	echo "Build root is not a directory: $BUILD_ROOT" >&2
	exit 2
fi
mkdir -p "$BUILD_ROOT"
CANON_BUILD_ROOT=$(CDPATH= cd -- "$BUILD_ROOT" && pwd -P)

GDIGNORE_PATH="$CANON_BUILD_ROOT/.gdignore"
if [ -L "$GDIGNORE_PATH" ]; then
	echo "Refusing symlink Godot ignore marker: $GDIGNORE_PATH" >&2
	exit 2
fi
: > "$GDIGNORE_PATH"

OUTPUT_REQUEST=${1:-"$CANON_BUILD_ROOT/mobile-web-beta"}
case "$OUTPUT_REQUEST" in
	/*) ;;
	*) OUTPUT_REQUEST="$PROJECT_ROOT/$OUTPUT_REQUEST" ;;
esac
case "$OUTPUT_REQUEST" in
	*"/../"*|*"/./"*|*/..|*/.)
		echo "Refusing output path containing traversal: $OUTPUT_REQUEST" >&2
		exit 2
		;;
esac

OUTPUT_PARENT=$(dirname -- "$OUTPUT_REQUEST")
OUTPUT_NAME=$(basename -- "$OUTPUT_REQUEST")
case "$OUTPUT_NAME" in
	""|.|..|.gdignore)
		echo "Invalid build output directory name: $OUTPUT_NAME" >&2
		exit 2
		;;
esac
CANON_OUTPUT_PARENT=$(CDPATH= cd -- "$OUTPUT_PARENT" 2>/dev/null && pwd -P) || {
	echo "Build output parent does not exist: $OUTPUT_PARENT" >&2
	exit 2
}
if [ "$CANON_OUTPUT_PARENT" != "$CANON_BUILD_ROOT" ]; then
	echo "Output must be a direct child of $CANON_BUILD_ROOT" >&2
	exit 2
fi
OUTPUT_DIR="$CANON_BUILD_ROOT/$OUTPUT_NAME"
if [ -L "$OUTPUT_DIR" ]; then
	echo "Refusing symlink build destination: $OUTPUT_DIR" >&2
	exit 2
fi
if [ -e "$OUTPUT_DIR" ] && [ ! -d "$OUTPUT_DIR" ]; then
	echo "Build destination is not a directory: $OUTPUT_DIR" >&2
	exit 2
fi

TEMP_DIR=$(mktemp -d "${TMPDIR:-/tmp}/aoem-mobile-web.XXXXXX")
trap 'rm -rf "$TEMP_DIR"' EXIT INT TERM
STAGE_DIR="$TEMP_DIR/project"
EXPORT_DIR="$TEMP_DIR/export"
mkdir -p "$STAGE_DIR" "$EXPORT_DIR"

verify_closed_payload() {
	payload_dir=$1
	manifest="$payload_dir/SHA256SUMS.txt"
	if [ ! -f "$manifest" ]; then
		echo "Missing payload checksum manifest: $manifest" >&2
		return 1
	fi
	unsupported_entries=$(find "$payload_dir" ! -type d ! -type f -print)
	if [ -n "$unsupported_entries" ]; then
		echo "Payload contains unmanifestable symlinks or special entries:" >&2
		printf '%s\n' "$unsupported_entries" >&2
		return 1
	fi
	if grep -Ev '^[0-9a-f]{64}  \./' "$manifest" >/dev/null; then
		echo "Malformed payload checksum manifest: $manifest" >&2
		return 1
	fi
	if ! (cd "$payload_dir" && shasum -a 256 -c SHA256SUMS.txt); then
		echo "Payload checksum verification failed: $payload_dir" >&2
		return 1
	fi
	(
		cd "$payload_dir"
		find . -type f ! -path './SHA256SUMS.txt' -print | LC_ALL=C sort
	) > "$TEMP_DIR/payload-actual-files.txt"
	cut -c 67- "$manifest" | LC_ALL=C sort > "$TEMP_DIR/payload-listed-files.txt"
	if ! cmp -s "$TEMP_DIR/payload-actual-files.txt" "$TEMP_DIR/payload-listed-files.txt"; then
		echo "Payload is not closed; unlisted, missing, or duplicate files:" >&2
		diff -u "$TEMP_DIR/payload-listed-files.txt" "$TEMP_DIR/payload-actual-files.txt" >&2 || true
		return 1
	fi
}

verify_staged_source() {
	# The production stage is the source of truth for export. Check it directly,
	# rather than relying only on rsync patterns or Godot's export filter. Ignore
	# the derived .godot cache created by --import; it is neither source-hashed
	# nor copied into the final payload.
	unsupported_entries=$(find "$STAGE_DIR" \
		-path "$STAGE_DIR/.godot" -prune -o \
		! -type d ! -type f -print)
	if [ -n "$unsupported_entries" ]; then
		echo "Production stage contains symlinks or special entries:" >&2
		printf '%s\n' "$unsupported_entries" >&2
		return 1
	fi

	for forbidden_path in \
		.git \
		.github \
		.gitignore \
		.godot-mcp \
		.claude \
		.codex \
		.mcp.json \
		.playwright-cli \
		.tmp_phone_test \
		addons/godot_mcp \
		build \
		deploy \
		docs \
		export \
		output \
		reports \
		tests \
		tools \
		AGENTS.md \
		CLAUDE.md \
		PHASED_CHANGES.md \
		roadmap.md \
		scripts/ui/debug_bootstrap.gd \
		scripts/ui/debug_bootstrap.gd.uid \
		scripts/ui/debug_panel.gd \
		scripts/ui/debug_panel.gd.uid
	do
		if [ -e "$STAGE_DIR/$forbidden_path" ] || [ -L "$STAGE_DIR/$forbidden_path" ]; then
			echo "Developer-only path reached production stage: $forbidden_path" >&2
			return 1
		fi
	done

	unexpected_dev_files=$(find "$STAGE_DIR" \
		-path "$STAGE_DIR/.godot" -prune -o \
		-type f \( \
			-name '*.log' -o \
			-name '*.md' -o \
			-name '*.py' -o \
			-name '*.pyc' -o \
			-name '*.pyo' -o \
			-name '*.bak' -o \
			-name '*.tmp' -o \
			-name '*.orig' -o \
			-name '*.rej' -o \
			-name 'test_*.gd' -o \
			-name 'test_*.tscn' -o \
			-name '*_test.gd' -o \
			-name '*_test.tscn' \
		\) -print)
	if [ -n "$unexpected_dev_files" ]; then
		echo "Developer-only file type or test reached production stage:" >&2
		printf '%s\n' "$unexpected_dev_files" >&2
		return 1
	fi

	if grep -Eq '\.debug[[:space:]]*=|^\[editor_plugins\]$|^\[godot_mcp\]$|addons/godot_mcp|scripts/ui/debug_(bootstrap|panel)\.gd' "$STAGE_DIR/project.godot"; then
		echo "Staged project.godot still contains a debug override, editor plugin, or MCP add-on reference" >&2
		return 1
	fi
	if [ "$(grep -Fxc 'MCPGameBridge="res://scripts/managers/runtime_game_bridge.gd"' "$STAGE_DIR/project.godot")" -ne 1 ]; then
		echo "Staged project.godot must contain exactly one production runtime bridge autoload" >&2
		return 1
	fi
	if [ "$(grep -Fxc 'export/convert_text_resources_to_binary=false' "$STAGE_DIR/project.godot")" -ne 1 ]; then
		echo "Staged project.godot must disable nondeterministic text-resource conversion" >&2
		return 1
	fi
	if [ ! -f "$STAGE_DIR/scripts/managers/runtime_game_bridge.gd" ]; then
		echo "Production runtime bridge stub is missing from the stage" >&2
		return 1
	fi
}

# Export from a clean staging copy so Godot's generated UID/class caches cannot
# leak paths for developer-only resources into the PCK. The runtime bridge stub
# remains, while debug-only autoload overrides and editor plugin configuration do not.
rsync -a \
	--exclude '/.git/' \
	--exclude '/.github/' \
	--exclude '/.gitignore' \
	--exclude '/.godot/' \
	--exclude '/.godot-mcp/' \
	--exclude '/.claude/' \
	--exclude '/.codex/' \
	--exclude '/.mcp.json' \
	--exclude '/.playwright-cli/' \
	--exclude '/.tmp_phone_test/' \
	--exclude '/export/' \
	--exclude '/addons/godot_mcp/' \
	--exclude '/build/' \
	--exclude '/deploy/' \
	--exclude '/docs/' \
	--exclude '/output/' \
	--exclude '/reports/' \
	--exclude '/scripts/ui/debug_bootstrap.gd' \
	--exclude '/scripts/ui/debug_bootstrap.gd.uid' \
	--exclude '/scripts/ui/debug_panel.gd' \
	--exclude '/scripts/ui/debug_panel.gd.uid' \
	--exclude '/tools/' \
	--exclude '/tests/' \
	--exclude '/AGENTS.md' \
	--exclude '/CLAUDE.md' \
	--exclude '/PHASED_CHANGES.md' \
	--exclude '/roadmap.md' \
	--exclude '.env*' \
	--exclude '.DS_Store' \
	--exclude '._*' \
	--exclude 'Thumbs.db' \
	--exclude 'desktop.ini' \
	"$PROJECT_ROOT/" "$STAGE_DIR/"

awk '
	/^\[autoload\]$/ { in_autoload = 1 }
	/^\[/ && $0 != "[autoload]" { in_autoload = 0 }
	in_autoload && /^[[:space:]]*[A-Za-z_][A-Za-z0-9_]*\.debug[[:space:]]*=/ { next }
	/^\[editor_plugins\]$/ || /^\[godot_mcp\]$/ { skip = 1; next }
	/^\[/ { skip = 0 }
	!skip { print }
' "$PROJECT_ROOT/project.godot" > "$STAGE_DIR/project.godot"

# Godot 4.6's text-to-binary scene conversion emits byte-different `.scn`
# payloads across otherwise identical export processes. Retaining text scenes
# keeps the release pack reproducible; GDScript remains compiled by the preset.
printf '\n%s\n%s\n' \
	'[editor]' \
	'export/convert_text_resources_to_binary=false' \
	>> "$STAGE_DIR/project.godot"

verify_staged_source
# Fail before export when a preset silently falls back to the stock page.
python3 - "$STAGE_DIR" <<'PY'
from pathlib import Path
import sys

root = Path(sys.argv[1])
options = (root / "export_presets.cfg").read_text().split("[preset.1.options]", 1)[1]
assert 'html/custom_html_shell="res://web/pocket_shell.html"' in options, "Missing mobile Web shell preset"
assert 'html/canvas_resize_policy=0' in options, "Mobile shell must own canvas resizing"
assert (root / "web/pocket_shell.html").is_file(), "Missing mobile Web shell source"
PY
"$GODOT_BIN" --headless --path "$STAGE_DIR" --import
verify_staged_source

# Hash the exact staged source that feeds the export, after any generated UID
# sidecars have settled but without Godot's derived `.godot` cache. This includes
# tracked and untracked runtime files copied into the production stage.
SOURCE_MANIFEST="$EXPORT_DIR/SOURCE_SHA256SUMS.txt"
(
	cd "$STAGE_DIR"
	find . -path './.godot' -prune -o -type f -print | LC_ALL=C sort | while IFS= read -r file; do
		shasum -a 256 "$file"
	done
) > "$SOURCE_MANIFEST"
SOURCE_TREE_SHA256=$(shasum -a 256 "$SOURCE_MANIFEST" | awk '{print $1}')

"$GODOT_BIN" --headless --path "$STAGE_DIR" --export-release "Mobile Web Beta" "$EXPORT_DIR/index.html"

# Godot's stock PWA exporter generates 144/180/512 icons. Chromium also needs
# 192; render it from the same staged vector source and package it before hashes.
"$GODOT_BIN" --headless --path "$STAGE_DIR" --script "$PROJECT_ROOT/tools/render_pwa_icon.gd" -- \
	"$STAGE_DIR/icon.svg" "$EXPORT_DIR/index.192x192.png"

python3 - "$PROJECT_ROOT/tools" "$EXPORT_DIR" <<'PY'
from pathlib import Path
import sys

sys.path.insert(0, sys.argv[1])
from package_mobile_web_pwa import package_pwa
from verify_mobile_web_artifacts import verify_service_worker, verify_web_shell

root = Path(sys.argv[2])
package_pwa(root)
verify_service_worker(root)
verify_web_shell(root)
PY

GIT_REV=$(git -C "$PROJECT_ROOT" rev-parse --short=12 HEAD 2>/dev/null || printf 'unversioned')
PRODUCT_VERSION=$(sed -n 's/^config\/version="\(.*\)"/\1/p' "$PROJECT_ROOT/project.godot" | head -n 1)
if git -C "$PROJECT_ROOT" diff --quiet --ignore-submodules HEAD -- 2>/dev/null && [ -z "$(git -C "$PROJECT_ROOT" ls-files --others --exclude-standard 2>/dev/null)" ]; then
	DIRTY=false
else
	DIRTY=true
fi
BUILD_UTC=$(date -u +%Y-%m-%dT%H:%M:%SZ)

printf '%s\n' \
	'{' \
	'  "product": "Pocket Kingdoms",' \
	"  \"version\": \"$PRODUCT_VERSION\"," \
	'  "channel": "internal-mobile-web-beta",' \
	"  \"source_revision\": \"$GIT_REV\"," \
	"  \"source_dirty\": $DIRTY," \
	"  \"source_tree_sha256\": \"$SOURCE_TREE_SHA256\"," \
	'  "source_manifest": "SOURCE_SHA256SUMS.txt",' \
	"  \"built_at_utc\": \"$BUILD_UTC\"," \
	"  \"godot\": \"$GODOT_VERSION\"," \
	'  "entrypoint": "index.html"' \
	'}' > "$EXPORT_DIR/version.json"

# Treat malformed provenance metadata as a build failure, not a payload that
# happens to checksum successfully.
python3 - "$EXPORT_DIR/version.json" <<'PY'
import json
import pathlib
import sys

json.loads(pathlib.Path(sys.argv[1]).read_text(encoding="utf-8"))
PY

PCK_STRINGS="$TEMP_DIR/index-pck-strings.txt"
LC_ALL=C strings "$EXPORT_DIR/index.pck" > "$PCK_STRINGS"

# Godot can store a dependency directory and basename as separate printable
# strings. Scan both complete resource paths and distinctive standalone
# basenames so an excluded preload such as `res://scripts/ui/` +
# `debug_panel.gd` cannot evade the production audit.
PCK_FORBIDDEN_PATH_MATCHES=$(grep -E \
	'res://(addons/godot_mcp|tools|tests|docs|reports|output|build|\.playwright-cli|\.tmp_phone_test|\.godot-mcp)(/|$)|res://(\.mcp\.json|AGENTS\.md|CLAUDE\.md|PHASED_CHANGES\.md|roadmap\.md)' \
	"$PCK_STRINGS" || true)
PCK_FORBIDDEN_BASENAME_MATCHES=$(grep -E \
	'debug_(bootstrap|panel)\.gd(c|\.remap)?|mcp_(game_bridge|debugger_plugin|constants|enums|log|logger|utils)\.gd(c|\.remap)?|(^|/)test_[^/[:space:]]*\.(gd|tscn|py)(c|\.remap)?($|[^[:alnum:]_.-])|(^|/)[^/[:space:]]*_test\.(gd|tscn|py)(c|\.remap)?($|[^[:alnum:]_.-])|(^|/)(\.mcp\.json|AGENTS\.md|CLAUDE\.md|PHASED_CHANGES\.md|roadmap\.md)($|[^[:alnum:]_.-])' \
	"$PCK_STRINGS" || true)
FORBIDDEN_MATCHES=$(printf '%s\n%s\n' "$PCK_FORBIDDEN_PATH_MATCHES" "$PCK_FORBIDDEN_BASENAME_MATCHES" | sed '/^$/d' | LC_ALL=C sort -u)
if [ -n "$FORBIDDEN_MATCHES" ]; then
	echo "Production content audit failed; developer-only resource paths remain:" >&2
	printf '%s\n' "$FORBIDDEN_MATCHES" >&2
	exit 4
fi

STAGE_SOURCE_FILE_COUNT=$(wc -l < "$SOURCE_MANIFEST" | tr -d '[:space:]')
PCK_SHA256=$(shasum -a 256 "$EXPORT_DIR/index.pck" | awk '{print $1}')
PCK_SIZE_BYTES=$(wc -c < "$EXPORT_DIR/index.pck" | tr -d '[:space:]')
PCK_STRING_COUNT=$(wc -l < "$PCK_STRINGS" | tr -d '[:space:]')

printf '%s\n' \
	'audit_format=1' \
	'status=PASS' \
	'product=Pocket Kingdoms mobile Web beta' \
	'staged_source_exclusions=PASS' \
	'staged_project_configuration=PASS' \
	'deterministic_text_resources=PASS' \
	'pck_complete_resource_path_scan=PASS' \
	'pck_split_basename_scan=PASS' \
	'excluded_tools_and_tests=PASS' \
	'excluded_docs_reports_and_temporary_output=PASS' \
	'excluded_debug_bootstrap_and_panel=PASS' \
	'excluded_godot_mcp_addon=PASS' \
	"staged_source_file_count=$STAGE_SOURCE_FILE_COUNT" \
	"source_tree_sha256=$SOURCE_TREE_SHA256" \
	"pck_sha256=$PCK_SHA256" \
	"pck_size_bytes=$PCK_SIZE_BYTES" \
	"pck_printable_string_count=$PCK_STRING_COUNT" \
	'source_manifest=SOURCE_SHA256SUMS.txt' \
	'runtime_bridge=scripts/managers/runtime_game_bridge.gd' \
	'scope=staged source paths, staged project configuration, packaged resource paths, and distinctive excluded-resource basenames' \
	'compiled_diagnostic_symbol_absence=NOT_CERTIFIED' \
	> "$EXPORT_DIR/CONTENT_AUDIT.txt"

(
	cd "$EXPORT_DIR"
	find . -type f ! -path './SHA256SUMS.txt' -print | LC_ALL=C sort | while IFS= read -r file; do
		shasum -a 256 "$file"
	done > SHA256SUMS.txt
)
verify_closed_payload "$EXPORT_DIR"

if [ -L "$OUTPUT_DIR" ]; then
	echo "Refusing symlink build destination before copy: $OUTPUT_DIR" >&2
	exit 2
fi
mkdir -p "$OUTPUT_DIR"
if [ -L "$OUTPUT_DIR" ] || [ ! -d "$OUTPUT_DIR" ]; then
	echo "Build destination changed or is unsafe: $OUTPUT_DIR" >&2
	exit 2
fi
rsync -a --delete "$EXPORT_DIR/" "$OUTPUT_DIR/"
verify_closed_payload "$OUTPUT_DIR"
echo "Mobile Web beta built at $OUTPUT_DIR"
echo "Version: $GIT_REV (dirty=$DIRTY), Godot $GODOT_VERSION"
echo "Staged source tree: $SOURCE_TREE_SHA256"
echo "Checksums: $OUTPUT_DIR/SHA256SUMS.txt"
