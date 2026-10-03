#!/bin/bash
# Regenerates preview.png (README + marketplace image) from the real widgets
# and views with demo data, offscreen, at 2x.
set -euo pipefail
root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
shell_src=${OMARCHY_PATH:-/usr/share/omarchy}/shell
cfg=$(mktemp -d)
trap 'rm -rf "$cfg"' EXIT
ln -s "$shell_src/Commons" "$cfg/Commons"
ln -s "$shell_src/Ui" "$cfg/Ui"
ln -s "$root" "$cfg/plugin"
cp "$root/tests/ui/preview.qml" "$cfg/shell.qml"
PREVIEW_OUT="$root/preview.png" QT_QPA_PLATFORM=offscreen QT_QUICK_BACKEND=software QT_SCALE_FACTOR=2 \
  timeout 60 qs -p "$cfg/shell.qml" 2>&1 | grep -q "PREVIEW saved=true"
echo "wrote $root/preview.png"
