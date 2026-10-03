#!/bin/sh
#
# Claude Code Statusline
# Parses Claude's JSON output and renders a statusline with model, usage, cost, and rate limits.
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
# Absent/null fields become ''. Note `false // ""` is also '' in jq.
vars=$(printf '%s' "$input" | jq -r '
    @sh "model=\(.model.display_name // "Unknown Model")",
    @sh "effort=\(.effort.level // "")",
    @sh "fast=\(.fast_mode // "")",
    @sh "vim_mode=\(.vim.mode // "")",
    @sh "used=\(.context_window.used_percentage // "")",
    @sh "ctx_size=\(.context_window.context_window_size // "")",
    @sh "total_cost=\(.cost.total_cost_usd // "")",
    @sh "duration_ms=\(.cost.total_duration_ms // "")",
    @sh "cache_warm=\(.prompt_cache.warm // "")",
    @sh "cache_expires=\(.prompt_cache.expires_at // "")",
    @sh "cache_hit=\(.prompt_cache.hit_ratio // "")",
    @sh "cache_seen=\(.prompt_cache.caching_observed // "")",
    @sh "worktree=\(.worktree.name // "")",
    @sh "current_dir=\(.worktree.original_cwd // .workspace.project_dir // .cwd // "")",
    @sh "pr_number=\(.pr.number // "")",
    @sh "pr_url=\(.pr.url // "")",
    @sh "pr_state=\(.pr.review_state // "")",
    @sh "rl_5h_pct=\(.rate_limits.five_hour.used_percentage // "")",
    @sh "rl_5h_reset=\(.rate_limits.five_hour.resets_at // "")",
    @sh "rl_7d_pct=\(.rate_limits.seven_day.used_percentage // "")",
    @sh "rl_7d_reset=\(.rate_limits.seven_day.resets_at // "")"
') || exit 0
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
CTX_WARN=40;   CTX_CRIT=60    # % of context window; quality drops well before auto-compact
COST_WARN=10;  COST_CRIT=30   # session USD
LIMIT_WARN=60; LIMIT_CRIT=80  # % of a rate-limit window used so far
PACE_WARN=80;  PACE_CRIT=100  # burn rate x100 (used% / elapsed%); 100 = lands exactly on the cap
HIT_WARN=80;   HIT_CRIT=50    # prompt cache hit %; lower is worse (see sev_low)

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
cache_str=""
if [ "$cache_warm" = "true" ] && [ -n "$cache_expires" ] && [ "$cache_expires" -gt "$now" ]; then
    cache_str="${OK}$(((cache_expires - now + 59) / 60))m${RESET}"
elif [ "$cache_seen" = "true" ]; then
    cache_str="${WARN}cold${RESET}"
fi
if [ -n "$cache_str" ] && [ -n "$cache_hit" ]; then
    hit=$(awk "BEGIN { printf \"%.0f\", $cache_hit * 100 }")
    cache_str="${cache_str} • $(sev_low "$hit" "$HIT_WARN" "$HIT_CRIT")${hit}% hit${RESET}"
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

pr_str=""
if [ -n "$pr_number" ]; then
    case "$pr_state" in
        approved)          pr_color="$OK";   pr_mark=" ✓" ;;
        changes_requested) pr_color="$CRIT"; pr_mark=" ✗" ;;
        pending)           pr_color="$WARN"; pr_mark=" …" ;;
        draft)             pr_color="$DIM";  pr_mark=" draft" ;;
        *)                 pr_color="";      pr_mark="" ;;
    esac
    pr_str="${pr_color}#${pr_number}${pr_mark}${RESET}"
    # OSC 8 hyperlink: Cmd+click opens the PR.
    [ -n "$pr_url" ] && pr_str="${ESC}]8;;${pr_url}${ESC}\\${pr_str}${ESC}]8;;${ESC}\\"
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

    # Burn multiplier: used% / elapsed% of the window. x1.0 lands exactly on
    # the cap at reset. DIM in the first 10% of the window, where one burst
    # would extrapolate to nonsense; x-- when the clock makes it uncomputable.
    if [ "$elapsed" -le 0 ]; then
        pace="${DIM}×--${RESET}"
    else
        rate=$((pct * window / elapsed))
        tenths=$(((pct * window + elapsed * 5) / (elapsed * 10)))
        if [ $((elapsed * 10)) -lt "$window" ]; then
            pace_color="$DIM"
        else
            pace_color=$(sev "$rate" "$PACE_WARN" "$PACE_CRIT")
        fi
        pace="${pace_color}×$((tenths / 10)).$((tenths % 10))${RESET}"
    fi

    if [ "$label" = "7d" ]; then
        when=$(date -r "$reset_ts" "+%a %-I:%M%p")
    else
        when="$(date -r "$reset_ts" "+%-I:%M%p") ($(dur "$remaining"))"
    fi
    printf "%s%s %s%%%s • %s • %s" "$(sev "$pct" "$LIMIT_WARN" "$LIMIT_CRIT")" "$label" "$pct" "$RESET" "$pace" "$when"
}

rate_limit_str="$(format_rl "$rl_5h_pct" "$rl_5h_reset" "5h" 18000) | $(format_rl "$rl_7d_pct" "$rl_7d_reset" "7d" 604800)"

repo_root=$(cd "${current_dir:-$PWD}" 2>/dev/null && git rev-parse --show-toplevel 2>/dev/null || echo "$current_dir")
dir_display=$(basename "$repo_root")

model_str="$(power "$model")${model}${RESET}"
[ "$fast" = "true" ] && model_str="${model_str} ${P5}fast${RESET}"

line1="🤖 ${model_str}"
[ -n "$vim_mode" ] && line1="[$(printf '%.1s' "$vim_mode")] ${line1}"
[ -n "$effort" ] && line1="${line1} | 💪 $(power "$effort")${effort}${RESET}"
line1="${line1} | 🧠 ${usage_str} | 💰 ${cost_str}"
[ -n "$duration_ms" ] && line1="${line1} | ⌛ $(dur $((${duration_ms%.*} / 1000)))"
[ -n "$cache_str" ] && line1="${line1} | 💾 ${cache_str}"
line1="${line1} | ⏱️ ${rate_limit_str}"

line2="📁 ${dir_display} | 🌳 ${worktree_str} | 🌿 ${git_str}"
[ -n "$pr_str" ] && line2="${line2} | 🔀 ${pr_str}"

printf '%s\n%s' "$line1" "$line2"
