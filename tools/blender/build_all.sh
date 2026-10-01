#!/usr/bin/env bash
# Rebuild every generated model from its Blender script.
#
#   tools/blender/build_all.sh              # from the project folder
#   tools/blender/build_all.sh previews/    # also write a contact sheet per model
#
# Needs Blender 5.x on PATH, with numpy available to Blender's Python (on
# Ubuntu/WSL: `sudo apt install python3-numpy`). Each script exports into
# models/generated/. After this, open the project in Godot (or run
# `godot --headless --import`) so the new .glb files are imported.
#
# Every script refuses to export a model that is over its triangle budget, so
# a failure here means "a model got too heavy", not a broken pipeline.

set -euo pipefail
cd "$(dirname "$0")/../.."

PREVIEW_DIR="${1:-}"
if [[ -n "$PREVIEW_DIR" ]]; then
	mkdir -p "$PREVIEW_DIR"
fi

failed=0
for script in tools/blender/create_*.py; do
	name="$(basename "$script" .py)"
	name="${name#create_}"
	extra=()
	if [[ -n "$PREVIEW_DIR" ]]; then
		if [[ "$name" == "arena_props" ]]; then
			extra=(-- --previews "$PREVIEW_DIR")
		else
			extra=(-- --preview "$PREVIEW_DIR/$name.png")
		fi
	fi
	echo "== $name"
	log="$(mktemp)"
	# --python-exit-code makes Blender exit non-zero if the script raises;
	# without it Blender reports success even when a script crashed.
	if blender -b --factory-startup --python-exit-code 1 --python "$script" \
			"${extra[@]}" >"$log" 2>&1; then
		status=0
	else
		status=$?
	fi
	grep -E "\[paintkit\]|Error|Traceback" "$log" || true
	rm -f "$log"
	if [[ $status -ne 0 ]]; then
		echo "!! $script failed (exit $status)"
		failed=1
	fi
done
exit $failed
