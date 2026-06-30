# Claude Code Statusline

A POSIX shell script that parses Claude Code's JSON output and renders a beautiful, color-coded statusline.

## Installation

Copy `statusline-command.sh` to `~/.claude/statusline-command.sh` and add it to your Claude Code `settings.json`:

```json
{
  "statusLine": {
    "type": "command",
    "command": "sh ~/.claude/statusline-command.sh",
    "padding": 0
  }
}
```

## Output Format

```
🤖 Sonnet 4.6 | 💪 high | 🧠 53% | 💰 $6.74 | ⚡ 69 tok/s | ⏱️ 5h 85% • 6:12PM (2h0m) | 7d 55% • Wed 4:16PM
📁 ProductAgents | 🌳 worktree-v3-streaming-reasoning-ui | 🌿 main
```

### Fields

| Field | Icon | Description |
|-------|------|-------------|
| Model | 🤖 | Claude model being used (Sonnet, Opus, Haiku, etc.) |
| Effort | 💪 | Thinking effort level |
| Context | 🧠 | Context window usage percentage |
| Cost | 💰 | Total session cost in USD |
| Rate | ⚡ | Token rate (tokens per second, session average) |
| Rate Limits | ⏱️ | 5h and 7-day rate limit status |
| Directory | 📁 | Current directory name |
| Worktree | 🌳 | Claude Code worktree name |
| Git | 🌿 | Git branch with staged/modified indicators |

### Rate Limits Format

- **5h limit**: `5h 85% • 6:12PM (2h0m)` — percentage, reset time, countdown
- **7d limit**: `7d 55% • Wed 4:16PM` — percentage, day and time (no countdown)

## Color Coding

### By Status (Context, Cost, Rate Limits)

| Condition | Color |
|-----------|-------|
| Context <40% | Green |
| Context 40-60% | Yellow |
| Context >60% | Red |
| Cost <$10 | Green |
| Cost $10-30 | Yellow |
| Cost >$30 | Red |
| Rate Limits <60% | Green |
| Rate Limits 60-80% | Yellow |
| Rate Limits >80% | Red |

### By Model

| Model | Color |
|-------|-------|
| Opus | Magenta |
| Sonnet | Orange |
| Haiku | Teal |

### By Effort

| Level | Color |
|-------|-------|
| low | Teal |
| medium | Brown |
| high | Orange |
| xhigh | Red |
| max | Pink |
| ultracode | Magenta |

### Token Rate (Inverted - Higher is Better)

| Rate | Color |
|------|-------|
| >80 tok/s | Green |
| 60-80 tok/s | Yellow |
| <60 tok/s | Red |

## Placeholders

When data is unavailable, `--` is shown:
- `💰 $--` — no cost data
- `⚡ -- tok/s` — no rate data
- `5h --%` — 5h limit expired or unavailable
- `7d --%` — 7d limit expired or unavailable

## Token Rate Calculation

The token rate is a **session average**:

```
tok_rate = (total_input_tokens + total_output_tokens) / (total_duration_ms / 1000)
```

Example:
- Input: 105,025 tokens
- Output: 218 tokens
- Duration: 1,529 seconds
- Rate: (105,025 + 218) / 1529 ≈ 69 tok/s

## Requirements

- `jq` — for JSON parsing
- POSIX-compliant shell (sh, dash, etc.)
- Terminal with 256-color support (for model/effort colors)
