#!/usr/bin/env bash
set -euo pipefail
URL="${1:-}"
if [[ -z "$URL" ]]; then
  echo "usage: doctor.sh <READY_URL>" >&2
  exit 2
fi
code=$(curl -s -o /dev/null -w "%{http_code}" "$URL")
[[ "$code" == "200" ]] || { echo "FAIL: $URL -> HTTP $code"; exit 1; }
base="${URL%/index.html}"
for f in index.js index.wasm index.pck; do
  c=$(curl -s -o /dev/null -w "%{http_code}" "$base/$f")
  [[ "$c" == "200" ]] || { echo "FAIL: $base/$f -> HTTP $c"; exit 1; }
done
# COI must stay off for this project
html=$(curl -sf "$URL")
if echo "$html" | rg -q 'ensureCrossOriginIsolationHeaders["'\'']?\s*[:=]\s*true'; then
  echo "FAIL: COI true in HTML (must be false)"
  exit 1
fi
echo "OK doctor: $URL assets 200; COI not forced true"
