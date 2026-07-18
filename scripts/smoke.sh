#!/usr/bin/env sh
# Smoke test iperf3 on host (gnu / macos): server + client loopback.
# Verifies the binary actually runs and produces sane output.
set -eu

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
BIN="${IPERF_BIN:-$ROOT/build/src/iperf3}"

[ -x "$BIN" ] || { echo "error: $BIN not found or not executable" >&2; exit 1; }

echo "==> version"
"$BIN" --version || true

echo "==> help (first 5 lines)"
"$BIN" --help 2>&1 | head -5 || true

echo "==> loopback test (1 second TCP, JSON output)"
PORT=5201
"$BIN" -s -p "$PORT" -1 &
SERVER_PID=$!
sleep 0.5
JSON_OUT="$("$BIN" -c 127.0.0.1 -p "$PORT" -t 1 -J 2>/dev/null || true)"
wait "$SERVER_PID" 2>/dev/null || true

# Crude sanity check: must have 'sum_received' or 'error' field
echo "$JSON_OUT" | python3 -c "
import json, sys
try:
    d = json.loads(sys.stdin.read())
    if 'error' in d:
        print('FAIL: iperf3 reported error:', d['error'])
        sys.exit(1)
    if 'end' in d and 'sum_received' in d['end']:
        bps = d['end']['sum_received']['bits_per_second']
        print(f'OK: loopback throughput = {bps/1e6:.2f} Mbit/s')
        sys.exit(0)
    print('FAIL: unexpected JSON shape:', json.dumps(d)[:200])
    sys.exit(1)
except Exception as e:
    print('FAIL: parse error:', e)
    sys.exit(1)
"