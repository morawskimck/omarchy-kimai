#!/bin/bash
# Development helper: call the Kimai API the way the plugin does, with the
# token from the keyring passed to curl on stdin (never in argv).
#   scripts/kimai-api.sh GET /timesheets/active
#   scripts/kimai-api.sh POST /timesheets '{"project":1,"activity":1}'
# Prints the response body, then the HTTP status on its own line.
set -euo pipefail
config="${XDG_CONFIG_HOME:-$HOME/.config}/omarchy-kimai/config.json"
url=$(jq -r '.url // empty' "$config")
[[ -n $url ]] || { echo "No url in $config" >&2; exit 1; }
token=$(secret-tool lookup application omarchy-kimai url "$url")
[[ -n $token ]] || { echo "No token in the keyring for $url" >&2; exit 1; }

method=$1
path=$2
body=${3:-}
args=(-sS --max-time 15 --config - -X "$method" -H "Accept: application/json" -w '\n%{http_code}\n')
[[ -n $body ]] && args+=(-H "Content-Type: application/json" --data-binary "$body")
printf 'header = "Authorization: Bearer %s"\n' "$token" | curl "${args[@]}" "$url/api$path"
