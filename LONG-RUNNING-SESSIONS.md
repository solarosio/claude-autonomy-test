# Long-Running Claude Code Sessions: Research & Best Practices

**Date:** 2026-02-16
**System:** macOS Darwin 24.3.0, Apple Silicon M2, 16 GB RAM
**Claude Code:** v2.1.44 (native Mach-O arm64)
**Model:** Claude Opus 4.6 via Claude Max (first-party)

---

## 1. What Causes Sessions to Die (SIGKILL)

### Three Root Causes

**A. Memory leaks in Claude Code itself (CRITICAL)**
The most significant issue. Multiple GitHub issues report Claude Code consuming 12–129 GB of RAM over time, even when idle. The root cause appears to be unbounded heap growth (anonymous memory, not file-backed). This affects all platforms.
- [#4953](https://github.com/anthropics/claude-code/issues/4953) — 47 upvotes, `oncall` label (being investigated)
- [#11315](https://github.com/anthropics/claude-code/issues/11315) — Memory grows continuously
- [#25545](https://github.com/anthropics/claude-code/issues/25545) — 129 GB RSS reported

**B. Node.js event loop blocking**
After ~10 minutes of active use, the process can become completely unresponsive to all signals except SIGKILL. The event loop locks up, making the process unkillable via normal means.
- [#24478](https://github.com/anthropics/claude-code/issues/24478)

**C. macOS Jetsam (memory pressure killer)**
macOS uses a kernel subsystem called **jetsam** (not a Linux-style OOM killer) that sends **unblockable SIGKILL** when memory pressure becomes critical. Nothing can prevent this — no signal handler, no `nohup`, no `tmux`.

Jetsam triggers when:
- Free pages drop below `vm_page_free_target`
- Compressor memory exceeds thresholds
- Swap space exhausts
- A process exceeds its hard memory limit
- Sustained memory pressure persists 10+ minutes

Current system state (at time of research):
```
Free RAM:       0.13 GB
Active:         3.71 GB
Compressor:     6.32 GB (storing 14.78 GB compressed)
Swap used:      1.2 GB / 2.0 GB
Memory level:   48% (moderate pressure)
```

This system is already under moderate load — a Claude Code memory leak could easily trigger jetsam.

---

## 2. Claude Code CLI Flags for Session Persistence

### Session Resume Flags
| Flag | Description |
|------|-------------|
| `-c, --continue` | Resume the most recent conversation in current directory |
| `-r, --resume [id]` | Resume by session ID, or open interactive picker |
| `--session-id <uuid>` | Use a specific session UUID |
| `--fork-session` | Create new session ID from an existing conversation |
| `--from-pr [value]` | Resume session linked to a PR |
| `--no-session-persistence` | Disable persistence (only works with `--print`) |

### Budget / Guardrails (print mode only)
| Flag | Description |
|------|-------------|
| `--max-budget-usd <amount>` | Maximum dollar spend on API calls |

### There is NO:
- `--max-turns` CLI flag (it's internal only, not user-configurable)
- `--timeout` flag
- `--heartbeat` or `--keepalive` flag
- Auto-resume after crash

### Session Resume Limitations
- `--continue` and `--resume` work for **clean exits only**
- After SIGKILL or crash, the `.jsonl` session file can be corrupted mid-tool-execution
- Large session histories (e.g., 1.4 MB git diffs in transcript) cause hangs when rendering
- [#18880](https://github.com/anthropics/claude-code/issues/18880), [#19036](https://github.com/anthropics/claude-code/issues/19036)

---

## 3. Key Environment Variables

### Session & Context Management
| Variable | Purpose |
|----------|---------|
| `CLAUDE_CODE_RESUME_INTERRUPTED_TURN` | Resume an interrupted turn specifically |
| `CLAUDE_AUTOCOMPACT_PCT_OVERRIDE` | Override auto-compaction trigger threshold (0-100) |
| `DISABLE_COMPACT` | Disable context compaction entirely |
| `DISABLE_AUTO_COMPACT` | Disable automatic compaction |
| `CLAUDE_CODE_MAX_OUTPUT_TOKENS` | Max output tokens per response |
| `CLAUDE_CODE_BLOCKING_LIMIT_OVERRIDE` | Override the blocking context limit |

### Performance & Resources
| Variable | Purpose |
|----------|---------|
| `CLAUDE_CODE_MAX_TOOL_USE_CONCURRENCY` | Max parallel tool calls |
| `CLAUDE_CODE_MAX_RETRIES` | Max API retries |
| `CLAUDE_CODE_EFFORT_LEVEL` | Effort level (low/medium/high) |
| `CLAUDE_ENABLE_STREAM_WATCHDOG` | Enable stream watchdog |
| `CLAUDE_CODE_GLOB_TIMEOUT_SECONDS` | Glob operation timeout |

### Tmux Integration (built-in!)
| Variable | Purpose |
|----------|---------|
| `CLAUDE_CODE_TMUX_PREFIX` | Tmux prefix key |
| `CLAUDE_CODE_TMUX_PREFIX_CONFLICTS` | Tmux prefix conflict handling |
| `CLAUDE_CODE_TMUX_SESSION` | Tmux session name |

Full list: **130+ environment variables** discovered via binary analysis. See the CLI research agent output for the complete catalog.

---

## 4. Resource Limits

### Context Window
- **200K token** context window
- Auto-compaction triggers at ~83.5% capacity (~167K tokens)
- Uses a 33K-token buffer (hardcoded)
- Compaction summarizes older messages, preserving recent context
- Adjustable via `CLAUDE_AUTOCOMPACT_PCT_OVERRIDE`
- Can be disabled with `DISABLE_AUTO_COMPACT=1` (not recommended)

### Node.js Memory
- **Default V8 heap limit:** 4,288 MB (auto-detected from 16 GB system RAM)
- `NODE_OPTIONS` is not currently set on this system
- Can override: `NODE_OPTIONS="--max-old-space-size=8192"`
- Reasonable ceiling for 16 GB system: 4–6 GB (leave room for OS + compressor)

### Process Limits
```
Max processes per user:  2,666 (kern.maxprocperuid)
File descriptors:        256 soft / unlimited hard  ← LOW, should raise
Stack size:              8,176 KB
Address space:           unlimited
```

### Existing Long-Running Sessions (proof of concept)
```
PID 8981:   Running since Feb 4 (12 days), 118h CPU time
PID 18905:  Running since Feb 4 (12 days), 116h CPU time
```
This proves Claude Code has **no built-in timeout** — sessions can run indefinitely.

---

## 5. Best Practices for Long Sessions

### Official Guidance (from docs.anthropic.com)
- Context window is "the most important resource to manage"
- Use `/clear` between unrelated tasks
- After two failed corrections, start fresh
- Use subagents for research to avoid polluting main context

### Practical Recommendations

**A. Use tmux (strongly recommended)**
```bash
brew install tmux
tmux new-session -s claude
# Detach: Ctrl+B, D
# Reattach: tmux attach -t claude
```

**B. Prevent system sleep with caffeinate**
```bash
caffeinate -i -m tmux new-session -s claude 'claude --continue'
```

**C. Raise file descriptor limit (add to ~/.zshrc)**
```bash
ulimit -n 10240
```

**D. Monitor memory pressure**
```bash
# In a separate tmux pane:
watch -n 10 'sysctl kern.memorystatus_level && ps -o pid,rss,%mem,comm -p $(pgrep -f "claude")'
```

**E. Disable App Nap for Terminal**
```bash
defaults write com.apple.Terminal NSAppSleepDisabled -bool YES
```

**F. Periodic session hygiene**
- Use `/clear` or `/compact` when context gets bloated
- Start new sessions for unrelated work rather than reusing one endlessly
- The memory leak means restarting periodically is the only reliable workaround

---

## 6. tmux/screen for Process Management

### tmux (recommended)
- **Not installed by default** — `brew install tmux`
- Session persistence through disconnects
- Multi-pane monitoring (Claude in one pane, memory watch in another)
- Claude Code has built-in tmux env vars (`CLAUDE_CODE_TMUX_SESSION`, etc.)
- [claude-tmux](https://github.com/nielsgroen/claude-tmux) — TUI for managing multiple Claude sessions

### screen (available but outdated)
- Built-in at `/usr/bin/screen` but version 4.00.03 (from 2006)
- Not recommended — stagnant development, security concerns

### Protection Hierarchy
| Method | Terminal close | Logout | Sleep | OOM/Jetsam |
|--------|:-:|:-:|:-:|:-:|
| Background `&` | No | No | No | No |
| `nohup` | Yes | Yes | No | No |
| `disown -h` | Yes | Yes | No | No |
| tmux/screen | Yes | Yes | No | No |
| caffeinate + tmux | Yes | Yes | Yes | No |
| **Nothing** | — | — | — | **SIGKILL is unblockable** |

---

## 7. maxTurns and Internal Limits

- `maxTurns` exists internally in the agent loop code, controls how many assistant turns (tool-use iterations) occur before aborting
- Error message: `"hit max turns, aborting"`
- **Not exposed as a CLI flag** — cannot be set by the user
- In `--print` mode, `--max-budget-usd` is the primary guardrail
- In interactive mode, there is no turn limit — the user controls when to stop

---

## 8. Session Storage & Persistence

### Where sessions live
```
~/.claude/projects/<path-encoded>/          Session transcripts (.jsonl)
~/.claude/session-env/<uuid>/               Per-session environment snapshots
~/.claude/file-history/<uuid>/              File change history per session
~/.claude/todos/<uuid>.json                 Task state per session
~/.claude/debug/<uuid>.txt                  Debug logs (have cleanupPeriodDays)
```

### Transcript format
- JSONL (one JSON object per line)
- Contains: messages, tool calls, tool results, metadata
- Persists indefinitely (no automatic cleanup)
- Can grow large — 1.4 MB+ for sessions with big git diffs

---

## 9. Recommended Setup Script

```bash
#!/bin/bash
# setup-claude-session.sh — Optimal long-running Claude Code environment

# Raise file descriptor limit
ulimit -n 10240

# Set reasonable Node.js heap (optional, default 4.2 GB is fine)
# export NODE_OPTIONS="--max-old-space-size=6144"

# Disable App Nap for terminal processes
defaults write com.apple.Terminal NSAppSleepDisabled -bool YES 2>/dev/null

# Start tmux with caffeinate protection
if command -v tmux &>/dev/null; then
    caffeinate -i -m tmux new-session -s claude "claude $*"
else
    echo "tmux not installed. Install with: brew install tmux"
    echo "Starting without tmux protection..."
    caffeinate -i claude "$@"
fi
```

---

## 10. Summary of Findings

| Question | Answer |
|----------|--------|
| What causes SIGKILL? | Memory leaks in Claude Code (primary), macOS jetsam under memory pressure, Node.js event loop blocking |
| CLI flags for persistence? | `--continue`, `--resume`, `--session-id`, `--fork-session` — but no heartbeat/timeout/max-turns flags |
| Resource limits? | 200K token context (auto-compacted), 4.2 GB Node.js heap (configurable), 256 fd soft limit (should raise) |
| Best practices? | tmux + caffeinate, monitor memory, use `/clear` between tasks, restart periodically for memory leak |
| tmux/screen? | tmux strongly recommended, screen too outdated. Neither protects against SIGKILL. |
| --max-turns flag? | Internal only. Not a CLI flag. No user-configurable turn limit in interactive mode. |

### The uncomfortable truth
The biggest threat to long-running sessions is **Claude Code's own memory leak** ([#4953](https://github.com/anthropics/claude-code/issues/4953)). On a 16 GB system already at 48% memory pressure, a process that can grow to 12–129 GB will inevitably trigger jetsam SIGKILL. The only reliable mitigation today is periodic restarts and using `--continue` to resume.
