#!/bin/sh
#
# Claude Code Statusline
# Parses Claude's JSON output and renders a three-line statusline.
# How to read it and how to tune it: claude/README.md (Statusline section).
#
# Colors come from two families and nothing else:
#   severity (OK/WARN/CRIT): how worried to be. Every gauge uses it.
#   power (P1..P5): how much capability is engaged (model tier, effort).
#     The ramp avoids green/yellow/red so it is never mistaken for a warning.
# DIM marks values Claude has not reported yet.
#

set -eu

# Guard: if jq is absent the statusline would produce garbage on every token
# operation. Exit cleanly so Claude falls back to its default output rather
# than crashing the shell hook.
if ! command -v jq >/dev/null 2>&1; then
    exit 0
fi

# printf "%.0f" and awk parse dot-decimals only. Under a comma-decimal locale
# (pt_BR) bash 3.2's printf rejects Claude's floats and set -e kills the
# statusline before it prints. Pin the numeric category only so date keeps
# day names localized via LANG. LC_ALL overrides LC_NUMERIC, so clear it
# first (an LC_ALL-only setup then falls back to LANG/C for date).
unset LC_ALL
export LC_NUMERIC=C

# Empty stdin renders the "nothing reported yet" placeholders, not a blank line.
input=$(cat)
[ -n "$input" ] || input='{}'

# One jq pass; @sh quotes every value so eval is safe on arbitrary strings.
# Every field goes through a typed reader: missing, null, empty or wrongly
# typed values (at any depth) become '' = "not reported", never an error.
# shellcheck disable=SC2016  # $-free jq program, single quotes are intended
JQ_PROG='
    def get(f): try f catch null;
    def str(f): get(f) | strings | select(. != "");
    def num(f): get(f) | numbers;
    def int(f): num(f) | floor;
    def nat(f): int(f) | select(. >= 0);
    def flag(f): if get(f) == true then "true" else "" end;
    @sh "model=\(str(.model.display_name) // "Unknown Model")",
    @sh "effort=\(str(.effort.level) // "")",
    @sh "fast=\(flag(.fast_mode))",
    @sh "vim_mode=\(str(.vim.mode) // "")",
    @sh "used=\(num(.context_window.used_percentage) // "")",
    @sh "ctx_size=\((int(.context_window.context_window_size) | select(. > 0)) // "")",
    @sh "total_cost=\(num(.cost.total_cost_usd) // "")",
    @sh "duration_ms=\(nat(.cost.total_duration_ms) // "")",
    @sh "session_id=\(str(.session_id) // "")",
    @sh "api_ms=\(nat(.cost.total_api_duration_ms) // "")",
    @sh "out_tokens=\(nat(.context_window.total_output_tokens) // "")",
    @sh "cache_warm=\(flag(.prompt_cache.warm))",
    @sh "cache_expires=\(int(.prompt_cache.expires_at) // "")",
    @sh "cache_hit=\(num(.prompt_cache.hit_ratio) // "")",
    @sh "cache_seen=\(flag(.prompt_cache.caching_observed))",
    @sh "miss_at=\(int(.prompt_cache.last_miss_at) // "")",
    @sh "miss_cause=\([get(.prompt_cache.last_miss_cause.causes[]) | strings
        | if startswith("ttl_expired") then "ttl"
          elif . == "tools_changed" then "tools"
          elif . == "system_prompt_changed" then "prompt"
          elif . == "likely_server_side" then "server"
          else . end] | unique | join(","))",
    @sh "worktree=\(str(.worktree.name) // "")",
    @sh "current_dir=\(str(.worktree.original_cwd) // str(.workspace.project_dir) // str(.cwd) // "")",
    @sh "rl_5h_pct=\(num(.rate_limits.five_hour.used_percentage) // "")",
    @sh "rl_5h_reset=\(int(.rate_limits.five_hour.resets_at) // "")",
    @sh "rl_7d_pct=\(num(.rate_limits.seven_day.used_percentage) // "")",
    @sh "rl_7d_reset=\(int(.rate_limits.seven_day.resets_at) // "")"
'
# Input that is not JSON at all renders the "nothing reported" placeholders.
vars=$(printf '%s' "$input" | jq -r "$JQ_PROG" 2>/dev/null) \
    || vars=$(printf '{}' | jq -r "$JQ_PROG")
eval "$vars"

now=$(date +%s)

ESC=$(printf '\033')
RESET="${ESC}[0m"
DIM="${ESC}[2m"

OK="${ESC}[32m"
WARN="${ESC}[33m"
CRIT="${ESC}[38;5;196m"

P1="${ESC}[38;5;80m"   # teal
P2="${ESC}[38;5;75m"   # blue
P3="${ESC}[38;5;141m"  # lavender
P4="${ESC}[38;5;213m"  # pink
P5="${ESC}[38;5;201m"  # magenta

# Severity thresholds (warn, crit). Tune here; every gauge reads these.
CTX_WARN=40;   CTX_CRIT=61    # % of context window (red above 60); quality drops well before auto-compact
COST_WARN=10;  COST_CRIT=30   # session USD
LIMIT_WARN=60; LIMIT_CRIT=80  # % of a rate-limit window used so far
PACE_WARN=80;  PACE_CRIT=100  # burn rate x100 (used% / elapsed%) that colors the +/- balance; 100 = lands exactly on the cap
HIT_WARN=80;   HIT_CRIT=50    # prompt cache hit %; lower is worse (see sev_low)
MISS_RECENT=600               # seconds a cache miss stays on screen
SPEED_WARN=20; SPEED_CRIT=10  # output tok/s of the last response; lower is worse
SPEED_MIN_TOKENS=200          # smaller responses restart "ago" but keep the last tok/s

# sev VALUE WARN CRIT -> severity color for an integer where higher is worse.
sev() {
    if [ "$1" -ge "$3" ]; then
        printf '%s' "$CRIT"
    elif [ "$1" -ge "$2" ]; then
        printf '%s' "$WARN"
    else
        printf '%s' "$OK"
    fi
}

# sev_low VALUE WARN CRIT -> severity color for an integer where lower is worse.
sev_low() {
    if [ "$1" -lt "$3" ]; then
        printf '%s' "$CRIT"
    elif [ "$1" -lt "$2" ]; then
        printf '%s' "$WARN"
    else
        printf '%s' "$OK"
    fi
}

# dur SECONDS -> 4h9m / 29m
dur() {
    if [ "$1" -ge 3600 ]; then
        printf '%sh%sm' $(($1 / 3600)) $((($1 % 3600) / 60))
    else
        printf '%sm' $(($1 / 60))
    fi
}

# power NAME -> ramp color. Model names and effort levels share one scale.
power() {
    case "$1" in
        low|*Haiku*)                  printf '%s' "$P1" ;;
        medium)                       printf '%s' "$P2" ;;
        high|*Sonnet*)                printf '%s' "$P3" ;;
        xhigh)                        printf '%s' "$P4" ;;
        max|ultracode|*Opus*|*Fable*) printf '%s' "$P5" ;;
        *)                            printf '%s' "$RESET" ;;
    esac
}

if [ -n "$used" ]; then
    used_display=$(printf "%.0f" "$used")
    usage_str="$(sev "$used_display" "$CTX_WARN" "$CTX_CRIT")${used_display}%${RESET}"
else
    usage_str="${DIM}--%${RESET}"
fi

if [ -n "$ctx_size" ]; then
    if [ "$ctx_size" -ge 1000000 ]; then
        size_display="$((ctx_size / 1000000))M"
    else
        size_display="$((ctx_size / 1000))k"
    fi
    # A label, not a gauge: the percentage already carries the severity.
    usage_str="${usage_str}${DIM}/${size_display}${RESET}"
fi

if [ -n "$total_cost" ]; then
    cost_display=$(awk "BEGIN { printf \"%.2f\", $total_cost }")
    cost_whole=$(awk "BEGIN { printf \"%.0f\", $total_cost }")
    cost_str="$(sev "$cost_whole" "$COST_WARN" "$COST_CRIT")\$${cost_display}${RESET}"
else
    cost_str="${DIM}\$--${RESET}"
fi

# Cold cache = the next turn re-bills the whole context at full input price.
# The icon follows the state: 🔥 warm, 🧊 cold.
cache_str=""
if [ "$cache_warm" = "true" ] && [ -n "$cache_expires" ] && [ "$cache_expires" -gt "$now" ]; then
    cache_icon="🔥"
    cache_str="${OK}$(((cache_expires - now + 59) / 60))m${RESET}"
elif [ "$cache_seen" = "true" ]; then
    cache_icon="🧊"
    cache_str="${WARN}cold${RESET}"
fi
if [ -n "$cache_str" ] && [ -n "$cache_hit" ]; then
    hit=$(awk "BEGIN { printf \"%.0f\", $cache_hit * 100 }")
    cache_str="${cache_str} • $(sev_low "$hit" "$HIT_WARN" "$HIT_CRIT")${hit}% hit${RESET}"
fi
# Speed: output tokens of the latest response / API time added since the
# previous refresh. The API total only grows when a response lands, so its
# last growth is "last reply"; refreshInterval keeps that age ticking while a
# request hangs. State per session in $TMPDIR: "api_ms change_ts rate".
# ponytail: approximate; a refresh spanning several API calls (tool loops,
# subagents) reads slower. Upgrade path: parse transcript_path timings.
speed_str=""
case "$session_id" in
    ""|*[!A-Za-z0-9_-]*) ;;
    *)
        if [ -n "$api_ms" ]; then
            state="${TMPDIR:-/tmp}/claude-statusline-${session_id}"
            prev_api="" change_ts="" rate="-"
            if [ -f "$state" ]; then
                read -r prev_api change_ts rate < "$state" || true
            fi
            # Corrupt or partial state: start over.
            case "$prev_api:$change_ts" in
                :*|*:|*[!0-9:]*) prev_api="" ;;
            esac
            case "$rate" in
                ""|*[!0-9]*) rate="-" ;;
            esac
            if [ -z "$prev_api" ] || [ "$api_ms" -lt "$prev_api" ]; then
                change_ts="$now" rate="-"
            elif [ "$api_ms" -gt "$prev_api" ]; then
                # A response landed. A small one (tool call) is mostly the wait
                # before the first token, so it restarts "ago" but keeps the speed.
                change_ts="$now"
                if [ "${out_tokens:-0}" -ge "$SPEED_MIN_TOKENS" ]; then
                    rate=$((out_tokens * 1000 / (api_ms - prev_api)))
                fi
            fi
            if [ "$api_ms" != "$prev_api" ]; then
                { printf '%s %s %s\n' "$api_ms" "$change_ts" "$rate" > "$state.$$" && mv -f "$state.$$" "$state"; } 2>/dev/null || true
            fi
            if [ "$rate" = "-" ]; then
                speed_str="${DIM}--${RESET}"
            else
                age=$((now - change_ts))
                if [ "$age" -lt 60 ]; then
                    age_str="${age}s"
                else
                    age_str=$(dur "$age")
                fi
                speed_str="$(sev_low "$rate" "$SPEED_WARN" "$SPEED_CRIT")${rate} tok/s${RESET} • ${DIM}${age_str} ago${RESET}"
            fi
        fi
        ;;
esac

# A recent miss re-billed the whole context; say why while it is still news.
if [ -n "$cache_str" ] && [ -n "$miss_at" ]; then
    miss_age=$((now - miss_at))
    if [ "$miss_age" -ge 0 ] && [ "$miss_age" -lt "$MISS_RECENT" ]; then
        if [ "$miss_age" -lt 60 ]; then
            miss_when="now"
        else
            miss_when="$(dur "$miss_age") ago"
        fi
        cache_str="${cache_str} • ${WARN}✗ ${miss_cause:-miss} ${miss_when}${RESET}"
    fi
fi

if [ -n "$worktree" ]; then
    worktree_str="${worktree}"
else
    worktree_str="no worktree"
fi

# One git call: branch, ahead/behind upstream, staged/modified/untracked counts.
# Porcelain v2 lines: "# branch.head X", "# branch.ab +A -B", "1|2 XY ..." for
# changed entries (X staged, Y worktree, "." = clean), "u ..." unmerged, "? path".
git_info=$(git status --porcelain=v2 --branch 2>/dev/null | awk '
    $2 == "branch.oid"  { oid = substr($3, 1, 7) }
    $2 == "branch.head" { head = $3 }
    $2 == "branch.ab"   { ahead = substr($3, 2); behind = substr($4, 2) }
    $1 == "1" || $1 == "2" {
        if (substr($2, 1, 1) != ".") staged++
        if (substr($2, 2, 1) != ".") modified++
    }
    $1 == "u" { modified++ }
    $1 == "?" { untracked++ }
    END {
        if (head == "") exit
        if (head == "(detached)") head = oid
        printf "%s %d %d %d %d %d", head, ahead, behind, staged, modified, untracked
    }') || git_info=""

if [ -n "$git_info" ]; then
    # shellcheck disable=SC2086  # ref names cannot contain spaces
    set -- $git_info
    git_str="$1"
    [ "$2" -gt 0 ] && git_str="${git_str} ↑$2"
    [ "$3" -gt 0 ] && git_str="${git_str} ${WARN}↓$3${RESET}"
    [ "$4" -gt 0 ] && git_str="${git_str} ${OK}+$4${RESET}"
    [ "$5" -gt 0 ] && git_str="${git_str} ${WARN}~$5${RESET}"
    [ "$6" -gt 0 ] && git_str="${git_str} ${WARN}?$6${RESET}"
else
    git_str="no branch"
fi

# format_rl PCT RESET_TS LABEL WINDOW_SECONDS
format_rl() {
    pct="$1"
    reset_ts="$2"
    label="$3"
    window="$4"

    if [ -z "$pct" ] || [ -z "$reset_ts" ] || [ "$reset_ts" -le "$now" ]; then
        printf "%s%s --%%%s" "$DIM" "$label" "$RESET"
        return
    fi

    pct=$(printf "%.0f" "$pct")
    remaining=$((reset_ts - now))
    elapsed=$((window - remaining))

    # Balance: elapsed% - used% of the window, in points ahead of (+, reserve)
    # or behind (-, deficit) an even pace. Colored by the burn rate (used% /
    # elapsed%, x100), so a deficit is always CRIT. DIM in the first 10% of the
    # window, where one burst would extrapolate to nonsense; --% when the clock
    # makes it uncomputable.
    if [ "$elapsed" -le 0 ]; then
        pace="${DIM}--%${RESET}"
    else
        rate=$((pct * window / elapsed))
        delta=$(((elapsed * 100 + window / 2) / window - pct))
        if [ "$delta" -gt 0 ]; then
            balance="+${delta}%"
        elif [ "$delta" -lt 0 ]; then
            balance="${delta}%"
        else
            balance="±0%"
        fi
        if [ $((elapsed * 10)) -lt "$window" ]; then
            pace_color="$DIM"
        else
            pace_color=$(sev "$rate" "$PACE_WARN" "$PACE_CRIT")
        fi
        pace="${pace_color}${balance}${RESET}"
    fi

    if [ "$label" = "7d" ]; then
        when=$(date -r "$reset_ts" "+%a %-I:%M%p")
    else
        when="$(date -r "$reset_ts" "+%-I:%M%p") ($(dur "$remaining"))"
    fi
    printf "%s%s %s%%%s • %s • %s" "$(sev "$pct" "$LIMIT_WARN" "$LIMIT_CRIT")" "$label" "$pct" "$RESET" "$pace" "$when"
}

rate_limit_str="$(format_rl "$rl_5h_pct" "$rl_5h_reset" "5h" 18000) | $(format_rl "$rl_7d_pct" "$rl_7d_reset" "7d" 604800)"

repo_root=$(cd "${current_dir:-$PWD}" 2>/dev/null && git rev-parse --show-toplevel 2>/dev/null || echo "${current_dir:-$PWD}")
dir_display=$(basename "$repo_root")

model_str="$(power "$model")${model}${RESET}"
[ "$fast" = "true" ] && model_str="${model_str} ${P5}fast${RESET}"

# Line 1: session. Line 2: time, cost, cache. Line 3: repository.
line1="🤖 ${model_str}"
[ -n "$vim_mode" ] && line1="[$(printf '%.1s' "$vim_mode")] ${line1}"
[ -n "$effort" ] && line1="${line1} | 💪 $(power "$effort")${effort}${RESET}"
line1="${line1} | 🧠 ${usage_str} | ⏱️ ${rate_limit_str}"

line2="💰 ${cost_str}"
[ -n "$duration_ms" ] && line2="⌛ $(dur $((duration_ms / 1000))) | ${line2}"
[ -n "$cache_str" ] && line2="${line2} | ${cache_icon} ${cache_str}"
[ -n "$speed_str" ] && line2="${line2} | ⚡ ${speed_str}"

line3="📁 ${dir_display} | 🌳 ${worktree_str} | 🌿 ${git_str}"

printf '%s\n%s\n%s' "$line1" "$line2" "$line3"
