#!/bin/bash
# Runs tools/tests/online_checklist.gd: a local dedicated server plus test
# clients (host and guest; Survival adds a mate), from WSL. Prints every client's PASS/FAIL
# lines and exits non-zero if any check failed.
#
#   tools/tests/run_online_checklist.sh                 (Team Deathmatch)
#   MODE=survival tools/tests/run_online_checklist.sh   (Survival)
#   WINDOWED=host SHOTS=/some/dir tools/tests/run_online_checklist.sh
#                                    (that client runs in a window and saves
#                                     screenshots of each screen into SHOTS)
#   GODOT=/path/to/godot_console.exe tools/tests/run_online_checklist.sh
GODOT="${GODOT:-/mnt/c/Users/jlion/Downloads/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64_console.exe}"
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
P="$(wslpath -w "$ROOT")"
OUT="${OUT:-$(mktemp -d)}"
RUN="$(date +%s)"
EXTRA="${EXTRA:-}"
MODE="${MODE:-tdm}"
ROLES="host guest"
if [[ "$MODE" == "survival" ]]; then
	ROLES="host guest mate"
fi

"$GODOT" --headless --path "$P" -- --server > "$OUT/server.log" 2>&1 &
SERVER=$!
# The server can take 15+ seconds to start when the project is read over the
# WSL file share. Wait for its "listening" line before starting any client.
for _ in $(seq 1 90); do
	grep -q "listening on" "$OUT/server.log" && break
	sleep 1
done
if ! grep -q "listening on" "$OUT/server.log"; then
	echo "local server did not start"; kill $SERVER; exit 1
fi
for role in $ROLES; do
	DISPLAY_FLAG="--headless"
	ROLE_EXTRA="$EXTRA"
	if [[ "$role" == "${WINDOWED:-}" ]]; then
		DISPLAY_FLAG="--windowed"
		ROLE_EXTRA="$EXTRA --shots=$(wslpath -w "$SHOTS")"
	fi
	"$GODOT" $DISPLAY_FLAG --path "$P" --script res://tools/tests/online_checklist.gd -- --role=$role --run=$RUN --mode=$MODE $ROLE_EXTRA > "$OUT/$role.log" 2>&1 &
	eval "PID_$role=$!"
	sleep 0.5
done
FAIL=0
for role in $ROLES; do
	eval "wait \$PID_$role" || FAIL=1
done
kill $SERVER 2>/dev/null
for role in $ROLES; do
	grep -E "^\[$role\]|SCRIPT ERROR|ERROR:" "$OUT/$role.log" | grep -vE "MCP|bridge"
done
grep -E "SCRIPT ERROR|ERROR:" "$OUT/server.log" | head -5
echo "logs: $OUT"
exit $FAIL
