#!/bin/sh
#
# Claude Code Statusline
# Parses Claude's JSON output and renders a statusline with model, usage, cost, and rate limits.
#

# ============================================================================
# INPUT PARSING
# ============================================================================

input=$(cat)

# Model and effort
model=$(echo "$input" | jq -r '.model.display_name // "Unknown Model"')
effort=$(echo "$input" | jq -r '.effort.level // empty')

# Context window
used=$(echo "$input" | jq -r '.context_window.used_percentage // empty')
total_input_tokens=$(echo "$input" | jq -r '.context_window.total_input_tokens // empty')
total_output_tokens=$(echo "$input" | jq -r '.context_window.total_output_tokens // empty')
total_duration_ms=$(echo "$input" | jq -r '.cost.total_duration_ms // empty')

# Cost
total_cost=$(echo "$input" | jq -r '.cost.total_cost_usd // empty')

# Worktree
worktree=$(echo "$input" | jq -r '.worktree.name // empty')
current_dir=$(echo "$input" | jq -r '.worktree.original_cwd // empty')

# Rate limits (5h and 7d)
rl_5h_pct=$(echo "$input" | jq -r '.rate_limits.five_hour.used_percentage // empty' | awk '{printf "%.0f", $1}')
rl_5h_reset=$(echo "$input" | jq -r '.rate_limits.five_hour.resets_at // empty')
rl_7d_pct=$(echo "$input" | jq -r '.rate_limits.seven_day.used_percentage // empty' | awk '{printf "%.0f", $1}')
rl_7d_reset=$(echo "$input" | jq -r '.rate_limits.seven_day.resets_at // empty')

# ============================================================================
# COLOR DEFINITIONS (using $'' for proper escape interpretation)
# ============================================================================

ESC=$(printf '\033')

# Status colors
ORANGE="${ESC}[38;5;208m"    # Orange
PINK="${ESC}[38;5;213m"      # Pink
RED="${ESC}[38;5;196m"       # Red
BROWN="${ESC}[38;5;130m"     # Brown
TEAL="${ESC}[38;5;80m"       # Teal
MAGENTA="${ESC}[38;5;201m"   # Magenta

# Standard ANSI (for compatibility)
GREEN="${ESC}[32m"
YELLOW="${ESC}[33m"
RESET="${ESC}[0m"

# ============================================================================
# COLOR HELPER FUNCTIONS
# ============================================================================

# Get color based on percentage threshold
# Usage: color=$(get_color_pct "$value" "$red_threshold" "$yellow_threshold")
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

# Get color for model based on name
get_model_color() {
    model="$1"
    case "$model" in
        *Opus*)    echo "$MAGENTA" ;;
        *Sonnet*)  echo "$ORANGE" ;;
        *Haiku*)   echo "$TEAL" ;;
        *)         echo "$RESET" ;;
    esac
}

# Get color for effort level
# low > teal, medium > brown, high > orange, xhigh > red, max > pink, ultracode > magenta
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

# ============================================================================
# MODEL & EFFORT
# ============================================================================

if [ -n "$used" ]; then
    used_display=$(printf "%.0f" "$used")
    # Color context window based on usage (<40 green, 40-60 yellow, >60 red)
    used_color=$(get_color_pct "$used_display" 60 40)
    usage_str="${used_color}${used_display}%${RESET}"
else
    usage_str="0%"
fi

# ============================================================================
# WORKTREE
# ============================================================================

if [ -n "$worktree" ]; then
    worktree_str="${worktree}"
else
    worktree_str="no worktree"
fi

# ============================================================================
# GIT STATUS
# ============================================================================

git_str=""
if git rev-parse --git-dir > /dev/null 2>&1; then
    branch=$(git branch --show-current 2>/dev/null)
    [ -z "$branch" ] && branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null)
    staged=$(git diff --cached --numstat 2>/dev/null | wc -l | tr -d ' ')
    modified=$(git diff --numstat 2>/dev/null | wc -l | tr -d ' ')

    git_str="$branch"
    [ "$staged" -gt 0 ] && git_str="${git_str} $(printf "${GREEN}+${staged}${RESET}")"
    [ "$modified" -gt 0 ] && git_str="${git_str} $(printf "${YELLOW}~${modified}${RESET}")"
else
    git_str="no branch"
fi

# ============================================================================
# COST
# ============================================================================

if [ -n "$total_cost" ]; then
    cost_display=$(awk "BEGIN { printf \"%.2f\", $total_cost }")
    cost_whole=$(awk "BEGIN { printf \"%.0f\", $total_cost }")
    # Color cost based on absolute value (<$10 green, $10-30 yellow, >$30 red)
    cost_color=$(get_color_pct "$cost_whole" 30 10)
    cost_str="${cost_color}\$${cost_display}${RESET}"
else
    cost_str="\$--"
fi

# ============================================================================
# TOKEN RATE (session average: total tokens / total duration)
# ============================================================================

if [ -n "$total_input_tokens" ] && [ -n "$total_output_tokens" ] && [ -n "$total_duration_ms" ] && [ "$total_duration_ms" -gt 0 ]; then
    total_tokens=$((total_input_tokens + total_output_tokens))
    tok_rate=$(awk "BEGIN { printf \"%.0f\", $total_tokens / ($total_duration_ms / 1000) }")
    # Color rate (inverted: higher is better): >80 green, 60-80 yellow, <60 red
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

# ============================================================================
# RATE LIMITS FORMATTING
# ============================================================================

format_rl() {
    pct="$1"
    reset_ts="$2"
    label="$3"

    now=$(date +%s)
    remaining=$((reset_ts - now))

    # Show placeholder if no data or reset time has passed
    if [ -z "$pct" ] || [ "$remaining" -le 0 ]; then
        printf "%s --%%" "$label"
        return
    fi

    # Color based on usage percentage (<60 green, 60-80 yellow, >80 red)
    if [ "$pct" -ge 80 ]; then
        color="$RED"
    elif [ "$pct" -ge 60 ]; then
        color="$YELLOW"
    else
        color="$GREEN"
    fi

    reset_time=$(date -r "$reset_ts" "+%-I:%M%p" 2>/dev/null || date -d "@$reset_ts" "+%-I:%M%p" 2>/dev/null)

    # 7d limit: show day and time (no countdown)
    if [ "$label" = "7d" ]; then
        day_time=$(date -r "$reset_ts" "+%a %-I:%M%p" 2>/dev/null || date -d "@$reset_ts" "+%a %-I:%M%p" 2>/dev/null)
        printf "${color}${label} ${pct}%% • ${day_time}${RESET}"

    # 5h limit: show time and countdown
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

# Build rate limits string (handle missing limits gracefully)
rate_limit_5h=$(format_rl "$rl_5h_pct" "$rl_5h_reset" "5h")
rate_limit_7d=$(format_rl "$rl_7d_pct" "$rl_7d_reset" "7d")

if [ -n "$rate_limit_5h" ] && [ -n "$rate_limit_7d" ]; then
    rate_limit_str="${rate_limit_5h} | ${rate_limit_7d}"
elif [ -n "$rate_limit_5h" ]; then
    rate_limit_str="$rate_limit_5h"
else
    rate_limit_str="$rate_limit_7d"
fi

# ============================================================================
# DIRECTORY DISPLAY
# ============================================================================

repo_root=$(cd "$current_dir" 2>/dev/null && git rev-parse --show-toplevel 2>/dev/null || echo "$current_dir")
dir_display=$(basename "$repo_root")

# ============================================================================
# FINAL OUTPUT
# ============================================================================

# Apply model and effort colors
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