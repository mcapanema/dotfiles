#!/bin/sh
#
# Regression checks for claude/statusline-command.sh.
# Run: sh claude/test/statusline-test.sh   (exit 0 = all pass)
# STATUSLINE=/path/to/script overrides the script under test.
#

set -eu

DIR=$(cd "$(dirname "$0")" && pwd)
SCRIPT="${STATUSLINE:-$DIR/../statusline-command.sh}"

ESC=$(printf '\033')
RESET="${ESC}[0m"
DIM="${ESC}[2m"
OK="${ESC}[32m"
WARN="${ESC}[33m"
CRIT="${ESC}[38;5;196m"
P1="${ESC}[38;5;80m"
P3="${ESC}[38;5;141m"
P5="${ESC}[38;5;201m"

now=$(date +%s)
fails=0

# Scratch dir for git repos and the script's per-session speed state.
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
export TMPDIR="$tmp"

render() {
    printf '%s' "$1" | /bin/sh "$SCRIPT"
}

has() {
    case "$2" in
        *"$3"*) ;;
        *) printf 'FAIL %s: missing %s\n  in: %s\n' "$1" "$3" "$2" | cat -v; fails=$((fails + 1)) ;;
    esac
}

lacks() {
    case "$2" in
        *"$3"*) printf 'FAIL %s: unexpected %s\n  in: %s\n' "$1" "$3" "$2" | cat -v; fails=$((fails + 1)) ;;
    esac
}

# --- committed fixture -------------------------------------------------------------
out=$(render "$(cat "$DIR/sample-claude-status.json")")
has   fixture-model     "$out" "${P3}Sonnet 4.6${RESET}"
has   fixture-effort    "$out" "${P3}high${RESET}"
has   fixture-context   "$out" "${CRIT}62%${RESET}"
has   fixture-cost      "$out" "${OK}\$0.85${RESET}"
has   fixture-expired   "$out" "${DIM}5h --%${RESET}"
lacks fixture-no-speed  "$out" "tok/s"

# --- empty payload: nothing reported yet ----------------------------------------------
out=$(render '{}')
has   empty-model       "$out" "Unknown Model"
has   empty-context     "$out" "${DIM}--%${RESET}"
has   empty-cost        "$out" "${DIM}\$--${RESET}"
has   empty-limits      "$out" "${DIM}7d --%${RESET}"
lacks empty-no-speed    "$out" "⚡"
out=$(printf '' | /bin/sh "$SCRIPT") || true
has   empty-stdin-model "$out" "Unknown Model"
has   empty-stdin-ctx   "$out" "${DIM}--%${RESET}"

# --- shell metacharacters in reported strings are printed, never executed -----------------
out=$(render '{"model":{"display_name":"It'"'"'s $(echo pwned) `id`"}}')
has   meta-literal      "$out" "It's \$(echo pwned) \`id\`"

# --- comma-decimal locale with fractional values -----------------------------------------
out=$(printf '%s' '{"context_window":{"used_percentage":12.3},"cost":{"total_cost_usd":1.234}}' \
    | env LC_ALL=pt_BR.UTF-8 /bin/sh "$SCRIPT")
has   locale-context    "$out" "${OK}12%${RESET}"
has   locale-cost       "$out" "\$1.23"

# --- power ramp: model and effort share one scale ------------------------------------------
out=$(render '{"model":{"display_name":"Opus 5.5"},"effort":{"level":"max"}}')
has   power-opus        "$out" "${P5}Opus 5.5${RESET}"
has   power-max         "$out" "${P5}max${RESET}"
out=$(render '{"model":{"display_name":"Haiku 4.5"},"effort":{"level":"low"}}')
has   power-haiku       "$out" "${P1}Haiku 4.5${RESET}"
has   power-low         "$out" "${P1}low${RESET}"

# --- severity: one scale for every gauge ---------------------------------------------------
out=$(render '{"cost":{"total_cost_usd":12.5}}')
has   cost-warn         "$out" "${WARN}\$12.50${RESET}"
out=$(render '{"cost":{"total_cost_usd":45}}')
has   cost-crit         "$out" "${CRIT}\$45.00${RESET}"
# Context: yellow from 40%, red only above 60% (on the displayed integer).
out=$(render '{"context_window":{"used_percentage":39}}')
has   ctx-ok-39         "$out" "${OK}39%${RESET}"
out=$(render '{"context_window":{"used_percentage":40}}')
has   ctx-warn-40       "$out" "${WARN}40%${RESET}"
out=$(render '{"context_window":{"used_percentage":60}}')
has   ctx-warn-60       "$out" "${WARN}60%${RESET}"
out=$(render '{"context_window":{"used_percentage":60.4}}')
has   ctx-warn-60.4     "$out" "${WARN}60%${RESET}"
out=$(render '{"context_window":{"used_percentage":61}}')
has   ctx-crit-61       "$out" "${CRIT}61%${RESET}"
out=$(render "{\"rate_limits\":{\"five_hour\":{\"used_percentage\":30,\"resets_at\":$((now + 3600))}}}")
has   limit-ok          "$out" "${OK}5h 30%${RESET} • ${OK}+50%${RESET} •"

# --- git: branch, ahead/behind upstream, staged/modified/untracked --------------------------
gc() { git -c user.name=t -c user.email=t@t -c commit.gpgsign=false "$@"; }
git init -q "$tmp/o"
echo x > "$tmp/o/f"
git -C "$tmp/o" add f
out=$(cd "$tmp/o" && render '{}')
has   git-staged        "$out" "${OK}+1${RESET}"
lacks git-no-upstream   "$out" "↑"
# Clone, then diverge by one commit each way, modify one file, add one untracked.
gc -C "$tmp/o" commit -qm base
git clone -q "$tmp/o" "$tmp/c"
gc -C "$tmp/o" commit -q --allow-empty -m upstream
gc -C "$tmp/c" commit -q --allow-empty -m local
git -C "$tmp/c" fetch -q
echo y >> "$tmp/c/f"
echo z > "$tmp/c/new"
out=$(cd "$tmp/c" && render '{}')
has   git-ahead-behind  "$out" " ↑1 ${WARN}↓1${RESET}"
has   git-modified      "$out" "${WARN}~1${RESET}"
has   git-untracked     "$out" "${WARN}?1${RESET}"

# --- speed: last response tok/s and time since it, remembered per session -----------------
speed() {  # API_MS OUTPUT_TOKENS [SESSION_ID]
    render "{\"session_id\":\"${3:-s1}\",\"cost\":{\"total_api_duration_ms\":$1},\"context_window\":{\"total_output_tokens\":$2}}"
}
out=$(speed 10000 100)
has   speed-first       "$out" "⚡ ${DIM}--${RESET}"
out=$(speed 15000 200)
has   speed-ok          "$out" "⚡ ${OK}40 tok/s${RESET} • ${DIM}"
has   speed-age-secs    "$out" "s ago${RESET}"
out=$(speed 15000 200)
has   speed-timer-keeps "$out" "${OK}40 tok/s${RESET}"
# Simulate a long wait: last reply 200s ago.
echo "15000 $((now - 200)) 40" > "$tmp/claude-statusline-s1"
out=$(speed 15000 200)
has   speed-stuck-age   "$out" "${OK}40 tok/s${RESET} • ${DIM}3m ago${RESET}"
out=$(speed 35000 300)
has   speed-warn        "$out" "${WARN}15 tok/s${RESET}"
out=$(speed 85000 400)
has   speed-crit        "$out" "${CRIT}8 tok/s${RESET}"
# A small response (tool call, < SPEED_MIN_TOKENS) restarts "ago" but keeps the
# last real speed: its API time is mostly the wait before the first token.
echo "85000 $((now - 200)) 8" > "$tmp/claude-statusline-s1"
out=$(speed 86000 50)
has   speed-small-keeps "$out" "${CRIT}8 tok/s${RESET} • ${DIM}"
lacks speed-small-age   "$out" "3m ago"
out=$(speed 1000 300 s2)
out=$(speed 2000 50 s2)
has   speed-small-first "$out" "⚡ ${DIM}--${RESET}"
# API total went down (/clear): start over.
out=$(speed 1000 50)
has   speed-reset       "$out" "⚡ ${DIM}--${RESET}"
# Corrupt state must not blank the statusline.
echo "garbage here" > "$tmp/claude-statusline-s1"
out=$(speed 2000 50)
has   speed-corrupt     "$out" "⚡ ${DIM}--${RESET}"
# Session ids that are not plain tokens never become a path.
out=$(speed 2000 50 "../evil")
lacks speed-bad-id      "$out" "⚡"
[ ! -e "$tmp/../claude-statusline-evil" ] || { echo "FAIL speed-bad-id-path: state written outside TMPDIR"; fails=$((fails + 1)); }

# --- rate limits: usage by raw %, then the balance against an even pace -----------------
# Balance = elapsed% - used%, in points of the window: +N% reserve, -N% deficit, ±0%.
# Colored by the burn rate (used% / elapsed%), so a deficit is always CRIT.
# Offsets carry padding so a slow run cannot cross a rounding boundary.
# 60% used after 40% of the window -> -20: usage WARN, balance CRIT, reset uncolored.
out=$(render "{\"rate_limits\":{\"five_hour\":{\"used_percentage\":60,\"resets_at\":$((now + 10770))}}}")
has   pace-5h-over      "$out" "${WARN}5h 60%${RESET} • ${CRIT}-20%${RESET} •"
lacks pace-no-reset-tint "$out" "${CRIT}-20%${RESET} • ${ESC}"
lacks pace-no-multiplier "$out" "×"
# Balance uses the displayed integer: 59.6 shows as 60%, so still -20.
out=$(render "{\"rate_limits\":{\"five_hour\":{\"used_percentage\":59.6,\"resets_at\":$((now + 10770))}}}")
has   pace-fraction     "$out" "${WARN}5h 60%${RESET} • ${CRIT}-20%${RESET} •"
# 40% used after 2 of 7 days (29%) -> -11: usage OK, balance CRIT.
out=$(render "{\"rate_limits\":{\"seven_day\":{\"used_percentage\":40,\"resets_at\":$((now + 432000))}}}")
has   pace-7d-over      "$out" "${OK}7d 40%${RESET} • ${CRIT}-11%${RESET} •"
# 10% used after 1 of 7 days (14%) -> +4, burning at 0.7 of an even pace: OK.
out=$(render "{\"rate_limits\":{\"seven_day\":{\"used_percentage\":10,\"resets_at\":$((now + 518415))}}}")
has   pace-7d-ok        "$out" "${OK}7d 10%${RESET} • ${OK}+4%${RESET} •"
# 85% used, 10m left (96%) -> +11, burning at 0.9: usage CRIT, balance WARN.
out=$(render "{\"rate_limits\":{\"five_hour\":{\"used_percentage\":85,\"resets_at\":$((now + 700))}}}")
has   pace-late-warn    "$out" "${CRIT}5h 85%${RESET} • ${WARN}+11%${RESET} •"
# 50% used at 50% of the window (50.2%, rate 99 -> WARN): exactly on pace.
out=$(render "{\"rate_limits\":{\"five_hour\":{\"used_percentage\":50,\"resets_at\":$((now + 8970))}}}")
has   pace-on-pace      "$out" "${OK}5h 50%${RESET} • ${WARN}±0%${RESET} •"
lacks pace-no-plus-zero "$out" "+0%"
lacks pace-no-minus-zero "$out" "-0%"
# First 10% of the window (2% used at 5%): shown, but DIM (one burst would extrapolate to nonsense).
out=$(render "{\"rate_limits\":{\"five_hour\":{\"used_percentage\":2,\"resets_at\":$((now + 17100))}}}")
has   pace-early-dim    "$out" "${OK}5h 2%${RESET} • ${DIM}+3%${RESET} •"
# Clock skew: reset further away than the window itself -> cannot compute.
out=$(render "{\"rate_limits\":{\"five_hour\":{\"used_percentage\":30,\"resets_at\":$((now + 20000))}}}")
has   pace-skew         "$out" "${OK}5h 30%${RESET} • ${DIM}--%${RESET} •"
# Already capped (80% elapsed): balance still shown.
out=$(render "{\"rate_limits\":{\"five_hour\":{\"used_percentage\":100,\"resets_at\":$((now + 3615))}}}")
has   pace-capped       "$out" "${CRIT}5h 100%${RESET} • ${CRIT}-20%${RESET} •"
lacks pace-no-warn-sign "$out" "⚠"

# --- context size (always dim: a label, not a gauge); no session churn segment ---------
out=$(render "$(cat "$DIR/sample-claude-status.json")")
has   fixture-ctx-size  "$out" "${CRIT}62%${RESET}${DIM}/200k${RESET}"
lacks fixture-no-churn  "$out" "📝"
out=$(render '{"context_window":{"used_percentage":30,"context_window_size":1000000},"exceeds_200k_tokens":true}')
has   ctx-1m-dim        "$out" "${OK}30%${RESET}${DIM}/1M${RESET}"
out=$(render '{"context_window":{"used_percentage":null,"context_window_size":200000}}')
has   ctx-size-no-pct   "$out" "${DIM}--%${RESET}${DIM}/200k${RESET}"

# --- prompt cache --------------------------------------------------------------------
# expires_at carries a 30s pad so a slow run still rounds up to 5m.
out=$(render "{\"prompt_cache\":{\"warm\":true,\"caching_observed\":true,\"expires_at\":$((now + 270)),\"hit_ratio\":0.92}}")
has   cache-warm        "$out" "🔥 ${OK}5m${RESET} • ${OK}92% hit${RESET}"
out=$(render "{\"prompt_cache\":{\"warm\":false,\"caching_observed\":true,\"expires_at\":$((now - 60)),\"hit_ratio\":0.4}}")
has   cache-cold        "$out" "🧊 ${WARN}cold${RESET} • ${CRIT}40% hit${RESET}"
out=$(render "{\"prompt_cache\":{\"warm\":true,\"caching_observed\":true,\"expires_at\":$((now + 270)),\"hit_ratio\":0.7}}")
has   cache-hit-warn    "$out" "• ${WARN}70% hit${RESET}"
out=$(render '{"prompt_cache":{"warm":false,"caching_observed":false,"expires_at":null,"hit_ratio":null}}')
lacks cache-unused      "$out" "🔥"
lacks cache-unused-ice  "$out" "🧊"
# Recent miss (< 10m): cause + age in WARN. last_miss_at carries a 10s pad.
out=$(render "{\"prompt_cache\":{\"warm\":true,\"caching_observed\":true,\"expires_at\":$((now + 270)),\"hit_ratio\":0.92,\"last_miss_at\":$((now - 130)),\"last_miss_cause\":{\"causes\":[\"tools_changed\"]}}}")
has   miss-recent       "$out" "🔥 ${OK}5m${RESET} • ${OK}92% hit${RESET} • ${WARN}✗ tools 2m ago${RESET}"
out=$(render "{\"prompt_cache\":{\"warm\":true,\"caching_observed\":true,\"expires_at\":$((now + 270)),\"last_miss_at\":$((now - 5)),\"last_miss_cause\":{\"causes\":[\"ttl_expired_5m\",\"system_prompt_changed\",\"likely_server_side\"]}}}")
has   miss-causes       "$out" "${WARN}✗ prompt,server,ttl now${RESET}"
out=$(render "{\"prompt_cache\":{\"warm\":true,\"caching_observed\":true,\"expires_at\":$((now + 270)),\"last_miss_at\":$((now - 60)),\"last_miss_cause\":{\"causes\":[\"new_cause_x\"]}}}")
has   miss-unknown      "$out" "✗ new_cause_x 1m ago"
out=$(render "{\"prompt_cache\":{\"warm\":true,\"caching_observed\":true,\"expires_at\":$((now + 270)),\"last_miss_at\":$((now - 60))}}")
has   miss-no-cause     "$out" "✗ miss 1m ago"
out=$(render "{\"prompt_cache\":{\"warm\":true,\"caching_observed\":true,\"expires_at\":$((now + 270)),\"last_miss_at\":$((now - 900)),\"last_miss_cause\":{\"causes\":[\"tools_changed\"]}}}")
lacks miss-old          "$out" "✗"

# --- PR is never shown (Claude Code still sends it); fast mode, vim mode ----------------
out=$(render '{"pr":{"number":12,"url":"https://github.com/o/r/pull/12","review_state":"approved"},"vim":{"mode":"INSERT"},"fast_mode":true}')
lacks pr-hidden         "$out" "🐙"
lacks pr-no-number      "$out" "#12"
lacks pr-no-link        "$out" "]8;;"
lacks pr-no-badge       "$out" "approved"
has   vim-insert        "$out" "[I] 🤖"
has   fast-tag          "$out" "${P5}fast${RESET}"
out=$(render '{"fast_mode":false}')
lacks fast-off          "$out" "fast"
out=$(render '{}')
lacks vim-absent        "$out" "] 🤖"

# --- settings: time-based segments refresh while idle; vim mode shown once ---------------
settings=$(jq -c '.statusLine | {refreshInterval, hideVimModeIndicator}' "$DIR/../config/settings.json")
has   settings-refresh  "$settings" '"refreshInterval":30'
has   settings-vim-once "$settings" '"hideVimModeIndicator":true'

# --- session duration --------------------------------------------------------------------------
out=$(render '{"cost":{"total_cost_usd":0.5,"total_duration_ms":4320000}}')
has   duration          "$out" "⌛ 1h12m | 💰 ${OK}\$0.50${RESET}"
out=$(render '{}')
lacks duration-absent   "$out" "⌛"

# --- layout: 1 session, 2 time/cost/cache, 3 repository ------------------------------------
out=$(render "$(cat "$DIR/sample-claude-status.json")")
l1=$(printf '%s\n' "$out" | sed -n 1p)
l2=$(printf '%s\n' "$out" | sed -n 2p)
l3=$(printf '%s\n' "$out" | sed -n 3p)
has   layout-l1-model   "$l1" "🤖 "
has   layout-l1-limits  "$l1" "⏱️ "
lacks layout-l1-no-cost "$l1" "💰"
has   layout-l2-start   "$l2" "⌛ 3m | 💰 "
has   layout-l2-speed-end "$l2" "${RESET} | ⚡ ${DIM}--${RESET}"
lacks layout-l2-speed-mid "$l2" "⚡ ${DIM}--${RESET} |"
out=$(render "{\"session_id\":\"lay\",\"cost\":{\"total_api_duration_ms\":1000},\"prompt_cache\":{\"warm\":true,\"caching_observed\":true,\"expires_at\":$((now + 270))}}")
has   layout-l2-order   "$out" "💰 ${DIM}\$--${RESET} | 🔥 ${OK}5m${RESET} | ⚡ ${DIM}--${RESET}"
has   layout-l3-start   "$l3" "📁 "
lacks layout-no-4th     "$(printf '%s\n' "$out" | sed -n 4p)" "📁"
out=$(render '{}')
l2=$(printf '%s\n' "$out" | sed -n 2p)
has   layout-l2-empty   "$l2" "💰 ${DIM}\$--${RESET}"
lacks layout-l2-no-lead "$l2" "| 💰"

# --- empty and malformed state: every field, every bad value, still three lines ------------
# Start from a payload that lights up every segment, then break one field at a time.
full=$(jq -nc --argjson now "$now" '{
    session_id: "fz", model: {display_name: "Opus 5.5"}, effort: {level: "max"},
    fast_mode: true, vim: {mode: "INSERT"},
    context_window: {used_percentage: 45, context_window_size: 1000000, total_output_tokens: 300},
    cost: {total_cost_usd: 1.5, total_duration_ms: 60000, total_api_duration_ms: 30000},
    prompt_cache: {warm: true, caching_observed: true, expires_at: ($now + 300), hit_ratio: 0.9,
        last_miss_at: ($now - 60), last_miss_cause: {causes: ["tools_changed"]}},
    worktree: {name: "w", original_cwd: "/tmp"}, workspace: {project_dir: "/tmp"}, cwd: "/tmp",
    pr: {number: 5, url: "https://x/5", review_state: "approved"},
    rate_limits: {five_hour: {used_percentage: 50, resets_at: ($now + 3600)},
                  seven_day: {used_percentage: 20, resets_at: ($now + 86400)}}}')
paths='model model.display_name effort.level fast_mode vim vim.mode context_window
context_window.used_percentage context_window.context_window_size
context_window.total_output_tokens cost cost.total_cost_usd cost.total_duration_ms
cost.total_api_duration_ms session_id prompt_cache prompt_cache.warm prompt_cache.expires_at
prompt_cache.hit_ratio prompt_cache.caching_observed prompt_cache.last_miss_at
prompt_cache.last_miss_cause prompt_cache.last_miss_cause.causes worktree worktree.name
worktree.original_cwd workspace workspace.project_dir cwd pr pr.number pr.url
pr.review_state rate_limits rate_limits.five_hour rate_limits.five_hour.used_percentage
rate_limits.five_hour.resets_at rate_limits.seven_day.used_percentage
rate_limits.seven_day.resets_at'
bad=0
for path in $paths; do
    for value in null '""' '"x"' 1.5 -1 0 '{}' '[]'; do
        json=$(printf '%s' "$full" | jq -c --arg p "$path" --argjson v "$value" 'setpath($p | split("."); $v)')
        res=$(printf '%s' "$json" | /bin/sh "$SCRIPT" 2>&1) && rc=0 || rc=$?
        if [ "$rc" -ne 0 ] || [ "$(printf '%s\n' "$res" | wc -l)" -ne 3 ] \
            || ! printf '%s\n' "$res" | sed -n 3p | grep -q '^📁 '; then
            printf 'FAIL malformed %s=%s (rc=%s): %s\n' "$path" "$value" "$rc" \
                "$(printf '%s' "$res" | grep -v '^\(🤖\|\[\|⌛\|💰\|📁\)' | head -1)"
            bad=$((bad + 1))
        fi
    done
done
[ "$bad" -eq 0 ] || fails=$((fails + bad))
# Whole-input garbage renders the placeholders, not a blank line.
for doc in 'not json' '[]' 'null' '42' '{"model":'; do
    res=$(printf '%s' "$doc" | /bin/sh "$SCRIPT" 2>&1) || true
    has   "garbage-input:$doc" "$res" "${DIM}--%${RESET}"
done
out=$(render '{"model":{"display_name":""},"worktree":{"name":""}}')
has   empty-string-model "$out" "Unknown Model"
has   empty-string-tree  "$out" "🌳 no worktree"
out=$(render '{"context_window":{"used_percentage":30,"context_window_size":0}}')
has   ctx-size-zero      "$out" "${OK}30%${RESET} |"

if [ "$fails" -gt 0 ]; then
    echo "$fails check(s) failed"
    exit 1
fi
echo "PASS"
