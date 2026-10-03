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

# One jq pass; @sh quotes every value so eval is safe on arbitrary strings.
# Absent/null fields become ''. Note `false // ""` is also '' in jq.
vars=$(jq -r '
    @sh "model=\(.model.display_name // "Unknown Model")",
    @sh "effort=\(.effort.level // "")",
    @sh "used=\(.context_window.used_percentage // "")",
    @sh "ctx_size=\(.context_window.context_window_size // "")",
    @sh "over_200k=\(.exceeds_200k_tokens // "")",
    @sh "total_cost=\(.cost.total_cost_usd // "")",
    @sh "lines_added=\(.cost.total_lines_added // "")",
    @sh "lines_removed=\(.cost.total_lines_removed // "")",
    @sh "worktree=\(.worktree.name // "")",
    @sh "current_dir=\(.worktree.original_cwd // .workspace.project_dir // .cwd // "")",
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
LIMIT_WARN=80; LIMIT_CRIT=100 # % of a rate-limit window, projected to its reset

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
    # Past 200k input tokens every request bills at the long-context premium.
    if [ "$over_200k" = "true" ]; then
        size_color="$CRIT"
    else
        size_color="$DIM"
    fi
    usage_str="${usage_str}${size_color}/${size_display}${RESET}"
fi

if [ -n "$total_cost" ]; then
    cost_display=$(awk "BEGIN { printf \"%.2f\", $total_cost }")
    cost_whole=$(awk "BEGIN { printf \"%.0f\", $total_cost }")
    cost_str="$(sev "$cost_whole" "$COST_WARN" "$COST_CRIT")\$${cost_display}${RESET}"
else
    cost_str="${DIM}\$--${RESET}"
fi

if [ -n "$worktree" ]; then
    worktree_str="${worktree}"
else
    worktree_str="no worktree"
fi

git_str=""
if git rev-parse --git-dir > /dev/null 2>&1; then
    branch=$(git branch --show-current 2>/dev/null)
    [ -z "$branch" ] && branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null)
    # $(( )) strips the left padding macOS wc adds.
    staged=$(($(git diff --cached --numstat 2>/dev/null | wc -l)))
    modified=$(($(git diff --numstat 2>/dev/null | wc -l)))

    git_str="$branch"
    [ "$staged" -gt 0 ] && git_str="${git_str} ${OK}+${staged}${RESET}"
    [ "$modified" -gt 0 ] && git_str="${git_str} ${WARN}~${modified}${RESET}"
else
    git_str="no branch"
fi

churn_str=""
if [ -n "$lines_added" ] && [ -n "$lines_removed" ] && [ "$((lines_added + lines_removed))" -gt 0 ]; then
    churn_str="+${lines_added} -${lines_removed}"
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

    # Linear projection to reset. Skipped in the first 10% of the window,
    # where one burst would extrapolate to nonsense.
    projected="$pct"
    if [ $((elapsed * 10)) -ge "$window" ]; then
        projected=$((pct * window / elapsed))
    fi
    worst="$pct"
    [ "$projected" -gt "$worst" ] && worst="$projected"
    color=$(sev "$worst" "$LIMIT_WARN" "$LIMIT_CRIT")

    pace=""
    if [ "$projected" -gt "$pct" ] && [ "$projected" -ge "$LIMIT_WARN" ]; then
        pace=" →${projected}%"
    fi

    if [ "$label" = "7d" ]; then
        when=$(date -r "$reset_ts" "+%a %-I:%M%p")
    else
        hours=$((remaining / 3600))
        mins=$(((remaining % 3600) / 60))
        if [ "$hours" -gt 0 ]; then
            countdown="${hours}h${mins}m"
        else
            countdown="${mins}m"
        fi
        when="$(date -r "$reset_ts" "+%-I:%M%p") (${countdown})"
    fi
    printf "%s%s %s%%%s • %s%s" "$color" "$label" "$pct" "$pace" "$when" "$RESET"
}

rate_limit_str="$(format_rl "$rl_5h_pct" "$rl_5h_reset" "5h" 18000) | $(format_rl "$rl_7d_pct" "$rl_7d_reset" "7d" 604800)"

repo_root=$(cd "${current_dir:-$PWD}" 2>/dev/null && git rev-parse --show-toplevel 2>/dev/null || echo "$current_dir")
dir_display=$(basename "$repo_root")

model_str="$(power "$model")${model}${RESET}"

line1="🤖 ${model_str}"
[ -n "$effort" ] && line1="${line1} | 💪 $(power "$effort")${effort}${RESET}"
line1="${line1} | 🧠 ${usage_str} | 💰 ${cost_str}"
line1="${line1} | ⏱️ ${rate_limit_str}"

line2="📁 ${dir_display} | 🌳 ${worktree_str} | 🌿 ${git_str}"
[ -n "$churn_str" ] && line2="${line2} | 📝 ${churn_str}"

printf '%s\n%s' "$line1" "$line2"
