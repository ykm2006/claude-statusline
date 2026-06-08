#!/bin/bash
# Claude Code Enhanced Status Line
# Cross-platform: macOS / Linux / Windows (Git Bash) / WSL
# Based on: https://dev.classmethod.jp/articles/less-than-greater-than-claude-code/
# Model | Context | In/Cache/Out | Remaining | ETA | Compression | Burn Rate
# Line 2: Burn rate | real Anthropic rate limits (5h / 7d windows)
#
# Requires Claude Code v2.1.132+ (context_window.total_input_tokens = current
# context occupancy, current_usage breakdown available; rate_limits present
# for subscription/Pro/Max sessions).

# Ensure jq is on PATH (Windows/Git Bash may need ~/bin)
export PATH="$HOME/bin:$PATH"

CLAUDE_DIR="$HOME/.claude"
SESSION_FILE="$CLAUDE_DIR/.sl_session.json"
LAST_STATE_FILE="$CLAUDE_DIR/.sl_last_state.json"
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

# Real Anthropic rate limits (subscription sessions only; -1 = field absent)
rl_5h_pct=$(echo "$input" | jq -r '.rate_limits.five_hour.used_percentage // -1')
rl_5h_reset=$(echo "$input" | jq -r '.rate_limits.five_hour.resets_at // 0')
rl_7d_pct=$(echo "$input" | jq -r '.rate_limits.seven_day.used_percentage // -1')
rl_7d_reset=$(echo "$input" | jq -r '.rate_limits.seven_day.resets_at // 0')

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
  # New session: start a fresh consumption counter
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

# Format real Anthropic rate limits (5h rolling / 7d weekly windows).
# Colour by remaining headroom; show reset time if available.
# Cross-platform reset formatting: GNU date, then BSD date.
fmt_reset() {
  local ts=$1
  [ "${ts:-0}" -gt 0 ] 2>/dev/null || { echo ""; return; }
  date -d "@$ts" +"%m/%d %H:%M" 2>/dev/null \
    || date -r "$ts" +"%m/%d %H:%M" 2>/dev/null \
    || echo ""
}

rl_color() {
  local p=$1
  if [ "$p" -ge 90 ] 2>/dev/null; then echo "🔴"
  elif [ "$p" -ge 75 ] 2>/dev/null; then echo "🟠"
  elif [ "$p" -ge 50 ] 2>/dev/null; then echo "🟡"
  else echo "🟢"; fi
}

# Assemble each window segment, or "--" when the field is absent (API sessions)
if [ "$rl_5h_pct" -ge 0 ] 2>/dev/null; then
  r=$(fmt_reset "$rl_5h_reset"); [ -n "$r" ] && r=" ($r)"
  rl_5h_str="$(rl_color "$rl_5h_pct") ${rl_5h_pct}%${r}"
else
  rl_5h_str="--"
fi
if [ "$rl_7d_pct" -ge 0 ] 2>/dev/null; then
  r=$(fmt_reset "$rl_7d_reset"); [ -n "$r" ] && r=" ($r)"
  rl_7d_str="$(rl_color "$rl_7d_pct") ${rl_7d_pct}%${r}"
else
  rl_7d_str="--"
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
# ⏱5h / 📅7d = real Anthropic rate-limit windows (subscription sessions)
printf "🤖 %s │ 📊 %s/%s %s %d%% %s │ ⬇ %s ⚡ %s ⬆ %s │ 💡 残%s │ ⏳ ~%s │ 🔄 %d回\n🔥 %s │ ⏱ 5h:%s │ 📅 7d:%s" \
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
  "$rl_5h_str" \
  "$rl_7d_str"
