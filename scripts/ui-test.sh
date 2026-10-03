#!/bin/bash
# Renders the popup views offscreen against tests/ui/MockService.qml, runs the
# scripted checks in tests/ui/shell.qml and saves screenshots.
#   scripts/ui-test.sh [screenshot-dir]
# Needs Quickshell (`qs`) and Omarchy's shell sources for qs.Commons/qs.Ui.
set -euo pipefail
root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
shell_src=${OMARCHY_PATH:-/usr/share/omarchy}/shell
out=${1:-$(mktemp -d)}
mkdir -p "$out"

cfg=$(mktemp -d)
trap 'rm -rf "$cfg"' EXIT
ln -s "$shell_src/Commons" "$cfg/Commons"
ln -s "$shell_src/Ui" "$cfg/Ui"
ln -s "$root" "$cfg/plugin"
cp "$root/tests/ui/shell.qml" "$cfg/shell.qml"

log="$out/ui-test.log"
KIMAI_UI_OUT="$out" QT_QPA_PLATFORM=offscreen QT_QUICK_BACKEND=software \
  timeout 60 qs -p "$cfg/shell.qml" >"$log" 2>&1 || true

{ grep -E "UI (PASS|FAIL)" "$log" || true; } | sed -E 's/.*(UI (PASS|FAIL))/\1/'
grep -E "TypeError|ReferenceError|is not defined|Cannot (read|assign)" "$log" | sed -E 's/^.*qml[^:]*: //' | sort -u | sed 's/^/QML: /' || true
failures=$({ grep -oE "UI DONE [0-9]+" "$log" || true; } | awk '{print $3}' | tail -1)
echo "screenshots: $out"
if [[ -z $failures ]]; then echo "UI test did not finish; see $log" >&2; exit 1; fi
[[ $failures == 0 ]]
