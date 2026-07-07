#!/bin/sh
#
# Claude Code Statusline
# Parses Claude's JSON output and renders a statusline with model, usage, cost, and rate limits.
#

set -eu

# Guard: if jq is absent the statusline would produce garbage on every token
# operation. Exit cleanly so Claude falls back to its default output rather
# than crashing the shell hook.
if ! command -v jq >/dev/null 2>&1; then
    exit 0
fi

input=$(cat)

model=$(echo "$input" | jq -r '.model.display_name // "Unknown Model"')
effort=$(echo "$input" | jq -r '.effort.level // empty')

used=$(echo "$input" | jq -r '.context_window.used_percentage // empty')
total_input_tokens=$(echo "$input" | jq -r '.context_window.total_input_tokens // empty')
total_output_tokens=$(echo "$input" | jq -r '.context_window.total_output_tokens // empty')
total_duration_ms=$(echo "$input" | jq -r '.cost.total_duration_ms // empty')

total_cost=$(echo "$input" | jq -r '.cost.total_cost_usd // empty')

worktree=$(echo "$input" | jq -r '.worktree.name // empty')
current_dir=$(echo "$input" | jq -r '.worktree.original_cwd // empty')

rl_5h_pct=$(echo "$input" | jq -r '.rate_limits.five_hour.used_percentage // empty')
rl_5h_reset=$(echo "$input" | jq -r '.rate_limits.five_hour.resets_at // empty')
rl_7d_pct=$(echo "$input" | jq -r '.rate_limits.seven_day.used_percentage // empty')
rl_7d_reset=$(echo "$input" | jq -r '.rate_limits.seven_day.resets_at // empty')

ESC=$(printf '\033')

ORANGE="${ESC}[38;5;208m"
PINK="${ESC}[38;5;213m"
RED="${ESC}[38;5;196m"
BROWN="${ESC}[38;5;130m"
TEAL="${ESC}[38;5;80m"
MAGENTA="${ESC}[38;5;201m"

GREEN="${ESC}[32m"
YELLOW="${ESC}[33m"
RESET="${ESC}[0m"

get_color_pct() {
    val="$1"
    red="$2"
    yellow="$3"
    if [ -z "$val" ]; then
        echo ""
        return
    fi
    if [ "$val" -ge "$red" ]; then
        echo "$RED"
    elif [ "$val" -ge "$yellow" ]; then
        echo "$YELLOW"
    else
        echo "$GREEN"
    fi
}

get_model_color() {
    model="$1"
    case "$model" in
        *Opus*)    echo "$MAGENTA" ;;
        *Sonnet*)  echo "$ORANGE" ;;
        *Haiku*)   echo "$TEAL" ;;
        *)         echo "$RESET" ;;
    esac
}

get_effort_color() {
    effort="$1"
    case "$effort" in
        ultracode)  echo "$MAGENTA" ;;
        max)        echo "$PINK" ;;
        xhigh)      echo "$RED" ;;
        high)       echo "$ORANGE" ;;
        medium)     echo "$BROWN" ;;
        low)        echo "$TEAL" ;;
        *)          echo "$RESET" ;;
    esac
}

if [ -n "$used" ]; then
    used_display=$(printf "%.0f" "$used")
    used_color=$(get_color_pct "$used_display" 60 40)
    usage_str="${used_color}${used_display}%${RESET}"
else
    usage_str="0%"
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
    staged=$(git diff --cached --numstat 2>/dev/null | wc -l)
    modified=$(git diff --numstat 2>/dev/null | wc -l)

    git_str="$branch"
    [ "$staged" -gt 0 ] && git_str="${git_str} $(printf "${GREEN}+${staged}${RESET}")"
    [ "$modified" -gt 0 ] && git_str="${git_str} $(printf "${YELLOW}~${modified}${RESET}")"
else
    git_str="no branch"
fi

if [ -n "$total_cost" ]; then
    cost_display=$(awk "BEGIN { printf \"%.2f\", $total_cost }")
    cost_whole=$(awk "BEGIN { printf \"%.0f\", $total_cost }")
    cost_color=$(get_color_pct "$cost_whole" 30 10)
    cost_str="${cost_color}\$${cost_display}${RESET}"
else
    cost_str="\$--"
fi

if [ -n "$total_input_tokens" ] && [ -n "$total_output_tokens" ] && [ -n "$total_duration_ms" ] && [ "$total_duration_ms" -gt 0 ]; then
    total_tokens=$((total_input_tokens + total_output_tokens))
    tok_rate=$(awk "BEGIN { printf \"%.0f\", $total_tokens / ($total_duration_ms / 1000) }")
    if [ "$tok_rate" -gt 80 ]; then
        rate_color="$GREEN"
    elif [ "$tok_rate" -ge 60 ]; then
        rate_color="$YELLOW"
    else
        rate_color="$RED"
    fi
    rate_str="${rate_color}${tok_rate} tok/s${RESET}"
else
    rate_str="-- tok/s"
fi

format_rl() {
    pct="$1"
    reset_ts="$2"
    label="$3"

    now=$(date +%s)
    remaining=$((reset_ts - now))

    if [ -z "$pct" ] || [ "$remaining" -le 0 ]; then
        printf "%s --%%" "$label"
        return
    fi

    if [ "$pct" -ge 80 ]; then
        color="$RED"
    elif [ "$pct" -ge 60 ]; then
        color="$YELLOW"
    else
        color="$GREEN"
    fi

    reset_time=$(date -r "$reset_ts" "+%-I:%M%p")

    if [ "$label" = "7d" ]; then
        day_time=$(date -r "$reset_ts" "+%a %-I:%M%p")
        printf "${color}${label} ${pct}%% • ${day_time}${RESET}"
    else
        hours=$((remaining / 3600))
        mins=$(((remaining % 3600) / 60))
        if [ "$hours" -gt 0 ]; then
            countdown="${hours}h${mins}m"
        else
            countdown="${mins}m"
        fi
        printf "${color}${label} ${pct}%% • ${reset_time} (${countdown})${RESET}"
    fi
}

rate_limit_5h=$(format_rl "$rl_5h_pct" "$rl_5h_reset" "5h")
rate_limit_7d=$(format_rl "$rl_7d_pct" "$rl_7d_reset" "7d")

if [ -n "$rate_limit_5h" ] && [ -n "$rate_limit_7d" ]; then
    rate_limit_str="${rate_limit_5h} | ${rate_limit_7d}"
elif [ -n "$rate_limit_5h" ]; then
    rate_limit_str="$rate_limit_5h"
else
    rate_limit_str="$rate_limit_7d"
fi

repo_root=$(cd "$current_dir" 2>/dev/null && git rev-parse --show-toplevel 2>/dev/null || echo "$current_dir")
dir_display=$(basename "$repo_root")

model_color=$(get_model_color "$model")
effort_color=$(get_effort_color "$effort")
model_str="${model_color}${model}${RESET}"

if [ -n "$effort" ]; then
    effort_str="${effort_color}${effort}${RESET}"
    printf "🤖 %s | 💪 %s | 🧠 %s | 💰 %s | ⚡ %s | ⏱️ %s\n📁 %s | 🌳 %s | 🌿 %s" \
        "$model_str" "$effort_str" "$usage_str" "$cost_str" "$rate_str" "$rate_limit_str" \
        "$dir_display" "$worktree_str" "$git_str"
else
    printf "🤖 %s | 🧠 %s | 💰 %s | ⚡ %s | ⏱️ %s\n📁 %s | 🌳 %s | 🌿 %s" \
        "$model_str" "$usage_str" "$cost_str" "$rate_str" "$rate_limit_str" \
        "$dir_display" "$worktree_str" "$git_str"
fi