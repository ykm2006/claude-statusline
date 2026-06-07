#!/bin/bash
# Claude Code Enhanced Status Line
# Cross-platform: macOS / Linux / Windows (Git Bash) / WSL
# Based on: https://dev.classmethod.jp/articles/less-than-greater-than-claude-code/
# Model | Context | In/Cache/Out | Remaining | ETA | Compression | Burn Rate | D/W/M
#
# Requires Claude Code v2.1.132+ (context_window.total_input_tokens = current
# context occupancy, current_usage breakdown available).

# Ensure jq is on PATH (Windows/Git Bash may need ~/bin)
export PATH="$HOME/bin:$PATH"

CLAUDE_DIR="$HOME/.claude"
SESSION_FILE="$CLAUDE_DIR/.sl_session.json"
LAST_STATE_FILE="$CLAUDE_DIR/.sl_last_state.json"
USAGE_LOG="$CLAUDE_DIR/.sl_usage_log.csv"
COMPRESS_FILE="$CLAUDE_DIR/.sl_compress.json"

input=$(cat)

# Extract data
model=$(echo "$input" | jq -r '.model.display_name // "Unknown"')
context_size=$(echo "$input" | jq -r '.context_window.context_window_size // 200000')
session_id=$(echo "$input" | jq -r '.session_id // "unknown"')

# v2.1.132+: total_input_tokens = tokens currently in the context window
# (input + cache_creation + cache_read). Use it directly — no lossy
# roundtrip through the integer used_percentage.
current_used=$(echo "$input" | jq -r '.context_window.total_input_tokens // 0')

# Latest API call breakdown (v2.1.132+). Falls back to 0 on older versions.
cu_in=$(echo "$input" | jq -r '.context_window.current_usage.input_tokens // 0')
cu_out=$(echo "$input" | jq -r '.context_window.current_usage.output_tokens // 0')
cu_cache_read=$(echo "$input" | jq -r '.context_window.current_usage.cache_read_input_tokens // 0')

remaining_tokens=$((context_size - current_used))
[ "$remaining_tokens" -lt 0 ] && remaining_tokens=0
current_time=$(date +%s)

# Format number with k/M suffix
fmt() {
  local n=$1
  if [ "$n" -ge 1000000 ] 2>/dev/null; then
    awk "BEGIN {printf \"%.1fM\", $n/1000000}"
  elif [ "$n" -ge 1000 ] 2>/dev/null; then
    awk "BEGIN {printf \"%.1fk\", $n/1000}"
  else
    echo "${n:-0}"
  fi
}

# Initialize usage log
[ ! -f "$USAGE_LOG" ] && echo "ts,sid,tokens" > "$USAGE_LOG"

# --- Session tracking ---
# LAST_STATE_FILE : {sid, tok (= context occupancy at last render), ts}
# SESSION_FILE    : {ts (session start), cum (tokens consumed this session)}
# COMPRESS_FILE   : {sid, count}
#
# total_input_tokens is occupancy, not a cumulative counter (v2.1.132+),
# so we accumulate consumption as the sum of positive occupancy deltas.
# An occupancy drop within the same session is a compaction, NOT a new
# session — detect it BEFORE state files are overwritten.
last_sid=""
last_tok=0
if [ -f "$LAST_STATE_FILE" ]; then
  last_sid=$(jq -r '.sid // ""' "$LAST_STATE_FILE" 2>/dev/null)
  last_tok=$(jq -r '.tok // 0' "$LAST_STATE_FILE" 2>/dev/null)
fi

s_start=$current_time
cum=0
compress_count=0

if [ "$session_id" = "$last_sid" ] && [ -f "$SESSION_FILE" ]; then
  # Same session: accumulate delta
  s_start=$(jq -r '.ts // 0' "$SESSION_FILE" 2>/dev/null)
  [ "$s_start" -gt 0 ] 2>/dev/null || s_start=$current_time
  cum=$(jq -r '.cum // 0' "$SESSION_FILE" 2>/dev/null)
  compress_count=$(jq -r '.count // 0' "$COMPRESS_FILE" 2>/dev/null)
  delta=$((current_used - last_tok))
  if [ "$delta" -ge 0 ]; then
    cum=$((cum + delta))
  else
    # Occupancy dropped: compaction if the drop is large enough
    drop=$((-delta))
    threshold=$((last_tok / 5))
    [ "$threshold" -lt 10000 ] && threshold=10000
    if [ "$drop" -ge "$threshold" ]; then
      compress_count=$((compress_count + 1))
    fi
  fi
else
  # New session: archive the previous session's consumption
  if [ -n "$last_sid" ] && [ -f "$SESSION_FILE" ]; then
    prev_cum=$(jq -r '.cum // 0' "$SESSION_FILE" 2>/dev/null)
    if [ "${prev_cum:-0}" -gt 0 ] 2>/dev/null; then
      echo "$current_time,$last_sid,$prev_cum" >> "$USAGE_LOG"
    fi
  fi
  cum=$current_used
fi

printf '{"ts":%d,"cum":%d}' "$s_start" "$cum" > "$SESSION_FILE"
printf '{"sid":"%s","count":%d}' "$session_id" "$compress_count" > "$COMPRESS_FILE"
printf '{"sid":"%s","tok":%d,"ts":%d}' "$session_id" "$current_used" "$current_time" > "$LAST_STATE_FILE"

# Calculate burn rate & ETA (based on actual consumption, not occupancy)
burn_rate_str="--"
eta_str="--"
elapsed=$((current_time - s_start))
if [ "$elapsed" -gt 10 ] && [ "$cum" -gt 0 ]; then
  br_val=$(awk "BEGIN {v=($cum * 60.0) / $elapsed; printf \"%.0f\", v}")
  burn_rate_str="$(fmt "$br_val")/min"
  if [ "$br_val" -gt 0 ] 2>/dev/null; then
    eta_sec=$(awk "BEGIN {printf \"%.0f\", ($remaining_tokens * 60.0) / $br_val}")
    if [ "$eta_sec" -ge 3600 ] 2>/dev/null; then
      eta_str="$(awk "BEGIN {printf \"%.1f\", $eta_sec/3600}")h"
    elif [ "$eta_sec" -ge 60 ] 2>/dev/null; then
      eta_str="$(awk "BEGIN {printf \"%.0f\", $eta_sec/60}")min"
    else
      eta_str="${eta_sec}s"
    fi
  fi
fi

# Aggregate daily/weekly/monthly (archived sessions + current session)
# Cross-platform: try GNU date first, then BSD date, then fallback
day_start=$(date -d "today 00:00:00" +%s 2>/dev/null \
  || date -j -v0H -v0M -v0S +%s 2>/dev/null \
  || echo $((current_time - 86400)))
week_ago=$((current_time - 604800))
month_ago=$((current_time - 2592000))
d_total=0; w_total=0; m_total=0

if [ -f "$USAGE_LOG" ]; then
  while IFS=, read -r ts sid tok; do
    [ "$ts" = "ts" ] && continue
    [[ "$tok" =~ ^[0-9]+$ ]] || continue
    [ "${ts:-0}" -ge "$day_start" ] 2>/dev/null && d_total=$((d_total + tok))
    [ "${ts:-0}" -ge "$week_ago" ] 2>/dev/null && w_total=$((w_total + tok))
    [ "${ts:-0}" -ge "$month_ago" ] 2>/dev/null && m_total=$((m_total + tok))
  done < "$USAGE_LOG"
fi

d_total=$((d_total + cum))
w_total=$((w_total + cum))
m_total=$((m_total + cum))

# Prune old entries occasionally
if [ $((RANDOM % 50)) -eq 0 ] && [ -f "$USAGE_LOG" ]; then
  cutoff=$((current_time - 7776000))
  tmp="$USAGE_LOG.tmp"
  head -1 "$USAGE_LOG" > "$tmp"
  tail -n +2 "$USAGE_LOG" | awk -F, -v c="$cutoff" '$1 >= c' >> "$tmp"
  mv "$tmp" "$USAGE_LOG"
fi

# Build progress bar (input-only formula, same as used_percentage)
pct_int=$(awk "BEGIN {printf \"%.0f\", ($current_used * 100.0) / $context_size}" 2>/dev/null || echo "0")
filled=$((pct_int / 10))
[ "$filled" -gt 10 ] && filled=10
empty=$((10 - filled))
bar=""
for ((i=0; i<filled; i++)); do bar+="█"; done
for ((i=0; i<empty; i++)); do bar+="░"; done

# Performance zone indicator
if [ "$pct_int" -ge 90 ]; then
  perf="🔴 Critical"
elif [ "$pct_int" -ge 70 ]; then
  perf="🟠 Warning"
elif [ "$pct_int" -ge 50 ]; then
  perf="🟡 Caution"
else
  perf="🟢 Good"
fi

# Output (2 lines)
# ⬇/⚡/⬆ = latest API call: fresh input / cache read / output
printf "🤖 %s │ 📊 %s/%s %s %d%% %s │ ⬇%s ⚡%s ⬆%s │ 💡残%s │ ⏳~%s │ 🔄%d回\n🔥 %s │ 🕐 Daily:%s  🗓 Weekly:%s  📊 Monthly:%s" \
  "$model" \
  "$(fmt $current_used)" \
  "$(fmt $context_size)" \
  "$bar" \
  "$pct_int" \
  "$perf" \
  "$(fmt $cu_in)" \
  "$(fmt $cu_cache_read)" \
  "$(fmt $cu_out)" \
  "$(fmt $remaining_tokens)" \
  "$eta_str" \
  "$compress_count" \
  "$burn_rate_str" \
  "$(fmt $d_total)" \
  "$(fmt $w_total)" \
  "$(fmt $m_total)"
