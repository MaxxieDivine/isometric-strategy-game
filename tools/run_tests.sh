#!/usr/bin/env bash
# Linux/macOS twin of run_tests.ps1 (used by CI): reimports the project, then
# runs every tests/test_*.gd suite headless. Exits 0 if all pass, 1 if any fail.
#
# Usage:  tools/run_tests.sh            (all suites)
#         tools/run_tests.sh cities     (only suites whose name contains "cities")
# Set GODOT to the Godot binary if it is not on PATH as "godot".

set -u
filter="${1:-}"
godot="${GODOT:-godot}"
root="$(cd "$(dirname "$0")/.." && pwd)"
script_errors="SCRIPT ERROR|Parse Error|Failed to load script"

if ! command -v "$godot" >/dev/null 2>&1; then
	echo "Godot not found: $godot (set GODOT)"
	exit 2
fi

echo "Reimporting project..."
import_out="$("$godot" --headless --path "$root" --import 2>&1)"
if grep -Eq "$script_errors" <<<"$import_out"; then
	echo "Import reported script errors:"
	grep -E "$script_errors|^\s+at: " <<<"$import_out" | sed 's/^/  /'
fi

shopt -s nullglob
suites=()
for path in "$root"/tests/test_*"$filter"*.gd; do
	suites+=("$(basename "$path")")
done
if [ ${#suites[@]} -eq 0 ]; then
	echo "No test suites match '$filter'."
	exit 2
fi

failed=()
for suite in "${suites[@]}"; do
	echo "--- ${suite%.gd}"
	out="$("$godot" --headless --path "$root" --script "res://tests/$suite" 2>&1)"
	code=$?
	grep -v -e '^\s*$' -e '^Godot Engine v' <<<"$out" | sed 's/^/  /'
	# A parse error can still exit 0, so check the output too.
	if [ $code -ne 0 ] || grep -Eq "$script_errors|^FAIL:" <<<"$out"; then
		failed+=("${suite%.gd}")
	fi
done

echo
if [ ${#failed[@]} -gt 0 ]; then
	echo "FAILED: ${failed[*]}"
	exit 1
fi
echo "All ${#suites[@]} test suites passed."
exit 0
