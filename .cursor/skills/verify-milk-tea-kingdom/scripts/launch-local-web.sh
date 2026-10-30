#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../../../.." && pwd)"
WEB="$ROOT/build/web"
PORT="${VERIFY_PORT:-8765}"
RUN_ID="${VERIFY_RUN_ID:-$$}"
PIDFILE="/tmp/milk-tea-verify-$RUN_ID.pid"
LOG="/tmp/milk-tea-verify-$RUN_ID.log"

if [[ ! -f "$WEB/index.html" || ! -f "$WEB/index.wasm" || ! -f "$WEB/index.pck" ]]; then
  echo "FAIL: missing build/web/{index.html,index.wasm,index.pck} under $ROOT. Export Web with Godot first." >&2
  exit 1
fi

if [[ -f "$PIDFILE" ]] && kill -0 "$(cat "$PIDFILE")" 2>/dev/null; then
  echo "READY_URL=http://127.0.0.1:$PORT/index.html"
  echo "PIDFILE=$PIDFILE"
  exit 0
fi

cd "$WEB"
python3 -c "
import http.server, socketserver, mimetypes, os
mimetypes.add_type('application/wasm', '.wasm')
mimetypes.add_type('application/octet-stream', '.pck')
port = int(os.environ.get('PORT', '$PORT'))
class H(http.server.SimpleHTTPRequestHandler):
    def log_message(self, fmt, *args):
        pass
httpd = socketserver.TCPServer(('127.0.0.1', port), H)
open('$PIDFILE','w').write(str(os.getpid()))
httpd.serve_forever()
" >"$LOG" 2>&1 &
echo $! > "$PIDFILE"
export PORT="$PORT"
for i in $(seq 1 40); do
  if curl -sf -o /dev/null "http://127.0.0.1:$PORT/index.html"; then
    echo "READY_URL=http://127.0.0.1:$PORT/index.html"
    echo "PIDFILE=$PIDFILE"
    exit 0
  fi
  sleep 0.25
done
echo "FAIL: server did not become ready on :$PORT (log $LOG)" >&2
exit 1
