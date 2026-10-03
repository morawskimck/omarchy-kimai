#!/bin/bash
# Link this checkout into Omarchy's plugin directory and reload plugins.
# Symlinked plugin dirs are not watched for changes, so run this again
# (or `omarchy-shell shell rescanPlugins`) after every edit.
set -euo pipefail
root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
id=io.github.morawskimck.kimai
dest="$HOME/.config/omarchy/plugins/$id"

if [[ -e $dest && ! -L $dest ]]; then
  echo "$dest exists and is not a symlink; remove it first" >&2
  exit 1
fi
ln -sfn "$root" "$dest"
omarchy-shell shell rescanPlugins >/dev/null

# The rescan is asynchronous; wait so a following `omarchy plugin enable` works.
for _ in $(seq 20); do
  omarchy plugin list --json 2>/dev/null | jq -e --arg id "$id" 'any(.[]; .id == $id)' >/dev/null && break
  sleep 0.25
done
echo "Linked $dest -> $root and rescanned plugins"
