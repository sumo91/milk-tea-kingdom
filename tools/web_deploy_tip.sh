#!/bin/sh
# After a Godot 4 Web export, print one deploy tip line:
#   ?v=<git short hash>  pck sha256+size  wasm sha256+size  COI flag
# COI must be false (threads are off). Exits 1 if the built HTML or the
# export preset turns ensure_cross_origin_isolation_headers on.
#
#   sh tools/web_deploy_tip.sh
#   sh tools/web_deploy_tip.sh build/web
#   WEB_BASE_URL=https://sumo91.github.io/milk-tea-kingdom sh tools/web_deploy_tip.sh

set -eu

WEB_DIR=${1:-build/web}
BASE_URL=${WEB_BASE_URL:-https://sumo91.github.io/milk-tea-kingdom}
BASE_URL=${BASE_URL%/}

HTML="$WEB_DIR/index.html"
PCK="$WEB_DIR/index.pck"
WASM="$WEB_DIR/index.wasm"
PRESET=export_presets.cfg

die() {
	printf '%s\n' "$1" >&2
	exit 1
}

[ -f "$HTML" ] || die "missing $HTML (export Web first)"
[ -f "$PCK" ] || die "missing $PCK"
[ -f "$WASM" ] || die "missing $WASM"

file_size() {
	wc -c < "$1" | tr -d '[:space:]'
}

file_sha256() {
	if command -v shasum >/dev/null 2>&1; then
		shasum -a 256 "$1" | awk '{print $1}'
	elif command -v sha256sum >/dev/null 2>&1; then
		sha256sum "$1" | awk '{print $1}'
	else
		die "need shasum or sha256sum"
	fi
}

# Godot writes a JSON boolean with or without a space after the colon.
html_coi=$(tr -d ' \n\r\t' < "$HTML" | sed -n 's/.*"ensureCrossOriginIsolationHeaders":\([^,}]*\).*/\1/p' | head -n 1)
[ -n "$html_coi" ] || die "index.html has no ensureCrossOriginIsolationHeaders (re-export with web/shell.html)"
[ "$html_coi" = "false" ] || die "ensureCrossOriginIsolationHeaders=$html_coi in $HTML; must stay false"

if [ -f "$PRESET" ]; then
	preset_coi=$(sed -n 's/^progressive_web_app\/ensure_cross_origin_isolation_headers=//p' "$PRESET" | head -n 1 | tr -d '[:space:]')
	[ "$preset_coi" = "false" ] || die "export preset ensure_cross_origin_isolation_headers=$preset_coi; must stay false"
fi

if git rev-parse --short=7 HEAD >/dev/null 2>&1; then
	short=$(git rev-parse --short=7 HEAD)
else
	short=$(file_sha256 "$WASM" | cut -c1-7)
fi

pck_sha=$(file_sha256 "$PCK")
wasm_sha=$(file_sha256 "$WASM")
pck_size=$(file_size "$PCK")
wasm_size=$(file_size "$WASM")

printf '%s/?v=%s pck=sha256:%s size=%s wasm=sha256:%s size=%s ensureCrossOriginIsolationHeaders=false\n' \
	"$BASE_URL" "$short" "$pck_sha" "$pck_size" "$wasm_sha" "$wasm_size"
