#!/bin/bash
# Runs the real Service.qml headless against tests/service/mock-kimai.js, with
# a fake secret-tool and a throwaway XDG_CONFIG_HOME. Never touches your
# keyring, config or Kimai server.
set -euo pipefail
root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
tmp=$(mktemp -d)
server_pid=""
cleanup() {
  [[ -n $server_pid ]] && kill "$server_pid" 2>/dev/null || true
  rm -rf "$tmp"
}
trap cleanup EXIT

mkdir -p "$tmp/cfg" "$tmp/config" "$tmp/keyring" "$tmp/bin"
ln -s "$root" "$tmp/cfg/plugin"
cp "$root/tests/service/shell.qml" "$tmp/cfg/shell.qml"
cp "$root/tests/service/secret-tool" "$tmp/bin/secret-tool"
chmod +x "$tmp/bin/secret-tool"

node "$root/tests/service/mock-kimai.js" >"$tmp/server.log" 2>&1 &
server_pid=$!
for _ in $(seq 50); do grep -q '^PORT ' "$tmp/server.log" && break; sleep 0.1; done
port=$(awk '/^PORT /{print $2}' "$tmp/server.log")
[[ -n $port ]] || { echo "mock server did not start" >&2; cat "$tmp/server.log" >&2; exit 1; }

log="$tmp/service-test.log"
KIMAI_TEST_URL="http://127.0.0.1:$port" FAKE_KEYRING="$tmp/keyring" XDG_CONFIG_HOME="$tmp/config" \
  PATH="$tmp/bin:$PATH" QT_QPA_PLATFORM=offscreen \
  timeout 90 qs -p "$tmp/cfg/shell.qml" >"$log" 2>&1 || true

{ grep -E "SVC (PASS|FAIL)" "$log" || true; } | sed -E 's/.*(SVC (PASS|FAIL))/\1/'
grep -E "TypeError|ReferenceError|is not defined|Cannot (read|assign)" "$log" | sed -E 's/^.*qml[^:]*: //' | sort -u | sed 's/^/QML: /' || true
failures=$({ grep -oE "SVC DONE [0-9]+" "$log" || true; } | awk '{print $3}' | tail -1)
if [[ -z $failures ]]; then echo "service test did not finish:" >&2; tail -20 "$log" >&2; exit 1; fi
[[ $failures == 0 ]]
