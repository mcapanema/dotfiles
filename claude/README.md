# Claude Code Configuration

This directory manages Claude Code CLI/App installation and configuration for this dotfiles setup.

## Structure

- `config/` — Settings symlinked to `~/.config/claude-code/`
- `statusline-command.sh` — Statusline script symlinked to `~/.claude/statusline-command.sh`
- `templates/.zshenv` — API key template (sourced by `dotfiles/.zshenv`)
- `install.sh` — Standalone installation script
- `test/` — Statusline fixture and regression checks (`sh claude/test/statusline-test.sh`)

### Standalone
```shell
./claude/install.sh
```

## Manual Setup

If you prefer to set up manually:

1. Install Claude Code: `brew install claude-code`
2. Symlink config: `ln -s /path/to/claude/config ~/.config/claude-code`
3. Symlink statusline: `ln -s /path/to/claude/statusline-command.sh ~/.claude/statusline-command.sh`
4. Make executable: `chmod +x ~/.claude/statusline-command.sh`

## Statusline

The statusline is configured in `config/settings.json`:
```json
{
  "statusLine": {
    "type": "command",
    "command": "sh ~/.claude/statusline-command.sh",
    "padding": 0,
    "refreshInterval": 30,
    "hideVimModeIndicator": true
  }
}
```

- `refreshInterval: 30` re-runs the script every 30s while the session is idle, so countdowns and the "time since last reply" keep moving. Without it the script only runs on events (a new message, `/compact`, a mode change).
- `hideVimModeIndicator: true` hides Claude Code's own `-- INSERT --` text, because the statusline shows the vim mode itself.

### Layout

```
[I] 🤖 Opus 5.5 fast | 💪 max | 🧠 45%/1M | ⏱️ 5h 64% • ×3.8 • 10:15PM (4h9m) | 7d 30% • ×0.6 • Wed 5:26AM
⌛ 1h12m | 💰 $12.50 | 💾 60m • 92% hit • ✗ tools 2m ago | ⚡ 41 tok/s • 8s ago
📁 dotfiles | 🌳 no worktree | 🌿 main ↑1 ↓2 +1 ~2 ?3 | 🔀 #5 [review]
```

Line 1 is the session (model and limits), line 2 is time and spend, line 3 is the repository. A segment Claude Code has not reported yet is either dim (`--%`, `$--`, `⚡ --`) or left out. Missing, null, empty or wrongly typed fields are treated the same way, and input that isn't JSON renders the placeholders instead of a blank line, so the statusline always prints its three lines.

### Colors

Every color belongs to one of two scales, plus dim:

| Scale | Transition | Meaning |
|---|---|---|
| **Severity** | 🟢 → 🟡 → 🔴 | How worried to be. Used by every gauge. |
| **Power** | 🩵 → 💙 → 💜 → 🩷 → 💗 | How much capability is engaged (model, effort, fast mode). It never uses green, yellow or red, so it can't be mistaken for a warning. |
| **Dim** | 🩶 | Not reported yet, or background detail. |

The emoji are the closest match available; the terminal shows these exact colors:

| Step | Terminal color | Used for |
|---|---|---|
| 🟢 | green (ANSI 32) | fine |
| 🟡 | yellow (ANSI 33) | watch it |
| 🔴 | red (256-color 196) | act on it |
| 🩵 | teal (256-color 80) | `low` effort, Haiku |
| 💙 | blue (256-color 75) | `medium` effort |
| 💜 | lavender (256-color 141) | `high` effort, Sonnet |
| 🩷 | pink (256-color 213) | `xhigh` effort |
| 💗 | magenta (256-color 201) | `max` / `ultracode` effort, Opus, Fable, `fast` |
| 🩶 | dim (ANSI 2) | `--` placeholders, context size, speed age |

Most gauges are "higher is worse". Two are reversed, "lower is worse": cache hit % and tok/s.

### Reading each segment

| Segment | Example | What it means | Color |
|---|---|---|---|
| Vim mode | `[I]` | First letter of the vim mode (`N`ormal, `I`nsert, `V`isual). Only when vim mode is on. | none |
| 🤖 Model | `Opus 5.5 fast` | Model name; `fast` when fast mode is on. | power: Haiku teal, Sonnet lavender, Opus/Fable magenta; `fast` magenta |
| 💪 Effort | `max` | Reasoning effort. Absent for models without effort levels. | power: `low` teal, `medium` blue, `high` lavender, `xhigh` pink, `max` magenta |
| 🧠 Context | `45%/1M` | Context window used, then the window size. | `%`: yellow from 40%, red from 60%. Size: always dim |
| ⏱️ Limits | `5h 64% • ×3.8 • 10:15PM (4h9m)` | Subscription rate limits: usage, burn multiplier, reset time (5h window also shows a countdown; 7d shows the day). | see below |
| ⌛ Duration | `1h12m` | Session wall-clock time; adds up across resumes. | none |
| 💰 Cost | `$12.50` | Estimated session cost at API list price (resets on `/clear`). | yellow from $10, red from $30 |
| 💾 Cache | `60m • 92% hit • ✗ tools 2m ago` | Prompt cache: time until it expires (or `cold`), hit ratio, and the cause of a recent miss. | see below |
| ⚡ Speed | `41 tok/s • 8s ago` | Speed of the latest response and how long since the model last replied. | see below |
| 📁 Directory | `dotfiles` | Repository root name (the original directory when in a worktree). | none |
| 🌳 Worktree | `no worktree` | Active Claude Code worktree name. | none |
| 🌿 Git | `main ↑1 ↓2 +1 ~2 ?3` | Branch, commits ahead/behind upstream, staged/modified/untracked file counts. | `↓` yellow, `+` green, `~` and `?` yellow |
| 🔀 PR | `#5 [review]` | Pull request for the branch; Cmd+click opens it. | `[approved]` green, `[review]` yellow, `[changes]` red, `[draft]`/`[open]` dim |

#### Rate limits: `5h 64% • ×3.8 • 10:15PM (4h9m)`

- **`5h 64%`** is how much of the window you've used. Yellow from 60%, red from 80%.
- **`×3.8`** is the burn multiplier: used % ÷ elapsed % of the window. `×1.0` means you'll land exactly on 100% at the reset; `×3.8` means you're using it 3.8 times faster than that.
  - Green below `×0.8`, yellow from `×0.8`, red from `×1.0` (you'll hit the cap before the reset at this pace).
  - Dim during the first 10% of the window, where one early burst would exaggerate it.
  - Dim `×--` when it can't be computed (reset time further away than the window).
- **`10:15PM (4h9m)`** is when the window resets. Uncolored.
- `5h --%` (dim) means no data: not a subscriber, before the first response, or the window already reset.

#### Cache: `60m • 92% hit • ✗ tools 2m ago`

- **`60m`** (green) is how long the prompt cache stays warm. **`cold`** (yellow) means it expired, so the next message re-bills the whole context at full price.
- **`92% hit`** is the share of input read from the cache. Green from 80%, yellow below 80%, red below 50%.
- **`✗ tools 2m ago`** (yellow) appears for 10 minutes after a cache miss and says why: `ttl` (cache expired), `tools` (tools or MCP servers changed), `prompt` (system prompt changed), `server`, or the raw cause name.

#### Speed: `41 tok/s • 8s ago`

Claude Code does not report a live speed, so the script compares each refresh with the previous one, keeping one small state file per session in `$TMPDIR`.

- When the session's total API time grows, a response just finished: **tok/s** = that response's output tokens ÷ the API time added since the previous refresh, and **ago** restarts at 0s.
- While nothing new arrives, the 30s refresh keeps the speed and lets **ago** grow. If you're waiting on Claude and it keeps growing, the request is slow or stuck.
- tok/s is green from 20, yellow below 20, red below 10. The age is always dim. The first refresh of a session shows `⚡ --`.

It's an approximation:
- The API time includes the wait before the first token, so short responses (tool calls) and large contexts read slower than the model actually generates.
- If one refresh covers several API calls (fast tool loops, possibly subagents), the time adds up but only the last response's tokens count, so it reads slower.
- Parallel sessions are independent (the state file is named after the session id). The same session open in two terminals shares the file and gives noisy readings.

### Tuning

All thresholds are named settings near the top of `statusline-command.sh`:

| Setting | Default | Controls |
|---|---|---|
| `CTX_WARN` / `CTX_CRIT` | 40 / 60 | context % |
| `COST_WARN` / `COST_CRIT` | 10 / 30 | session cost in USD |
| `LIMIT_WARN` / `LIMIT_CRIT` | 60 / 80 | rate-limit usage % |
| `PACE_WARN` / `PACE_CRIT` | 80 / 100 | burn multiplier ×100 (80 = `×0.8`) |
| `HIT_WARN` / `HIT_CRIT` | 80 / 50 | cache hit % (lower is worse) |
| `MISS_RECENT` | 600 | seconds a cache miss stays on screen |
| `SPEED_WARN` / `SPEED_CRIT` | 20 / 10 | tok/s (lower is worse) |

### Testing

```sh
sh claude/test/statusline-test.sh    # prints PASS
sh claude/statusline-command.sh < claude/test/sample-claude-status.json
```

The test suite renders crafted JSON and checks the exact colors, so run it after every change to the script.
