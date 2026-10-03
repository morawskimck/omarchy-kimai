#!/bin/bash
# Unit tests, QML lint, offscreen UI tests and manifest validation.
# Run before every commit.
set -euo pipefail
root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
cd "$root"

TZ=Europe/Warsaw node --test tests/

if command -v qmllint >/dev/null && [[ -d /usr/share/omarchy/shell ]]; then
  shopt -s nullglob
  qml=(*.qml views/*.qml)
  if (( ${#qml[@]} )); then qmllint -I /usr/share/omarchy/shell -I . "${qml[@]}"; fi
  echo "qmllint ok"
fi

if command -v qs >/dev/null && [[ -d ${OMARCHY_PATH:-/usr/share/omarchy}/shell/Ui && -f tests/ui/shell.qml ]]; then
  ui_out=$(mktemp -d)
  scripts/ui-test.sh "$ui_out" | tail -1   # keeps the screenshots if it fails
  rm -rf "$ui_out"
  echo "ui tests ok"
fi

if command -v omarchy >/dev/null && [[ -f manifest.json ]]; then
  omarchy plugin validate "$root"
  echo "manifest ok"
fi
