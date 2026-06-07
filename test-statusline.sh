#!/bin/bash
# Ad-hoc test harness for statusline.sh
# Simulates a sequence of renders with a fake HOME so real ~/.claude is untouched.
set -u
SCRIPT="$(cd "$(dirname "$0")" && pwd)/statusline.sh"
export HOME="$(mktemp -d)"
mkdir -p "$HOME/.claude"

render() { # render <sid> <total_input> <in> <out> <cache_read>
  jq -n --arg sid "$1" --argjson ti "$2" --argjson in "$3" --argjson out "$4" --argjson cr "$5" '{
    session_id: $sid,
    model: { id: "claude-opus-4-8", display_name: "Opus 4.8" },
    context_window: {
      total_input_tokens: $ti,
      total_output_tokens: $out,
      context_window_size: 200000,
      used_percentage: (($ti * 100 / 200000) | floor),
      remaining_percentage: ((100 - $ti * 100 / 200000) | floor),
      current_usage: {
        input_tokens: $in, output_tokens: $out,
        cache_creation_input_tokens: 0, cache_read_input_tokens: $cr
      }
    }
  }' | bash "$SCRIPT"
  echo ""
}

state() {
  echo "  session: $(cat "$HOME/.claude/.sl_session.json")"
  echo "  compress: $(cat "$HOME/.claude/.sl_compress.json")"
  echo "  log: $(tail -n +2 "$HOME/.claude/.sl_usage_log.csv" | tr '\n' ' ')"
}

echo "=== 1. new session A, used=50k (expect cum=50000, compress=0) ==="
render sessA 50000 1000 500 49000; state

echo "=== 2. session A grows to 80k (expect cum=80000) ==="
render sessA 80000 2000 1500 78000; state

echo "=== 3. session A compaction to 30k (expect cum=80000, compress=1) ==="
render sessA 30000 500 200 29500; state

echo "=== 4. session A grows to 45k (expect cum=95000, compress=1) ==="
render sessA 45000 1000 800 44000; state

echo "=== 5. burn rate: backdate session start by 600s (expect 🔥 ~9.5k/min, ETA) ==="
ts=$(jq -r '.ts' "$HOME/.claude/.sl_session.json")
cum=$(jq -r '.cum' "$HOME/.claude/.sl_session.json")
printf '{"ts":%d,"cum":%d}' $((ts - 600)) "$cum" > "$HOME/.claude/.sl_session.json"
render sessA 45000 1000 800 44000; state

echo "=== 6. new session B, used=10k (expect A archived w/ 95000, cum=10000, Daily=105k) ==="
render sessB 10000 800 300 9200; state

echo "=== 7. small rewind within session B: 10k -> 9k (expect NO compress, cum stays 10000) ==="
render sessB 9000 100 50 8900; state

rm -rf "$HOME"
