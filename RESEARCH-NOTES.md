# Claude Code Capabilities Research Notes

**Date:** 2026-02-16
**Model:** Claude Opus 4.6 (`claude-opus-4-6`)

## Sub-Agent Patterns

Claude Code can launch specialized sub-agents via the `Task` tool. Each runs autonomously and returns results. Available types:

| Agent Type | Purpose | Tools Available |
|-----------|---------|-----------------|
| **Bash** | Command execution, git ops, terminal tasks | Bash only |
| **Explore** | Fast codebase exploration, file search, keyword search | All read-only tools (no Edit/Write/Task) |
| **Plan** | Architecture design, implementation planning | All read-only tools (no Edit/Write/Task) |
| **code-reviewer** | Review completed work against plans and standards | All tools |
| **general-purpose** | Multi-step research, complex searches | All tools |

**Key features:**
- Agents can run **in parallel** (multiple Task calls in one message)
- Agents can run **in the background** (`run_in_background: true`) with output files to check later
- Agents can be **resumed** by passing their `agentId` back
- Each agent gets a fresh context unless resumed — must provide full task description

## Web Research

| Tool | Works? | Notes |
|------|--------|-------|
| **WebSearch** | Yes | Full web search with results, links, and summaries. Current year (2026) awareness. |
| **WebFetch** | Yes | Fetches URL content, converts HTML to markdown, processes with AI. 15-min cache. |

**Limitations:** WebFetch fails on authenticated/private URLs (Google Docs, Jira, etc.). For GitHub, prefer `gh` CLI.

## MCP Integrations

Full **Slack** integration available:
- Search (public + private), read channels/threads/canvases, send messages, create drafts
- Schedule messages, create canvases, search users/channels, read user profiles

## File Operations

| Tool | Capability |
|------|-----------|
| **Read** | Read files, images (multimodal), PDFs (page ranges), Jupyter notebooks |
| **Write** | Create/overwrite files |
| **Edit** | Surgical string replacement (requires Read first) |
| **Glob** | Fast file pattern matching (`**/*.js`) |
| **Grep** | Ripgrep-powered content search with regex, multiline, context |

## Playwright / Visual Verification

- **Playwright 1.58.2** available via `npx playwright`
- Can screenshot HTML files, then **read the screenshot** (multimodal) to verify visual output
- Enables a create -> screenshot -> review -> iterate loop

## System Environment

- **Node.js:** v25.5.0 | **npm/npx:** 11.8.0
- **Platform:** macOS Darwin 24.3.0, arm64 (Apple Silicon M2)
- **Shell:** zsh

## Known Limits

- **Bash timeout:** 120s default, 600s (10 min) max
- **File read:** 2000 lines default, lines truncated at 2000 chars
- **Bash output:** Truncated at 30,000 chars
- **PDF read:** Max 20 pages per request; large PDFs require `pages` parameter
- **Sub-agent turns:** Configurable `max_turns` parameter
- **WebSearch:** US-only availability
- **Slack scheduled messages:** 10s-120 days future, max 30 per 5-min window per channel

## Parallel Execution Patterns

### Pattern 1: Parallel Task Agents
Launch multiple Task calls in a single message for independent work streams (e.g., implementation + tests + docs). All run simultaneously.

### Pattern 2: Background Work Queue
Use `run_in_background: true` for long-running agents. Continue interactive work, check `TaskOutput` later, resume agents by ID for follow-up.

### Pattern 3: Visual Verification Loop
Write HTML -> `npx playwright screenshot` -> Read screenshot (multimodal) -> analyze -> edit -> repeat until satisfied.

### Pattern 4: Parallel Research + Build
Phase 1 (parallel): WebSearch + WebFetch + Grep codebase simultaneously.
Phase 2 (sequential): Synthesize findings, then implement.

### Pattern 5: Parallel File Operations
Single response block with multiple Glob + Grep + Read + Bash calls for rapid codebase exploration.

## Recommendations
- **Fast exploration:** Explore agent with parallel Glob/Grep/Read
- **Complex work:** general-purpose agent with appropriate `max_turns`
- **Long operations:** Background agents with TaskOutput monitoring
- **UI development:** Playwright screenshot -> Read multimodal verification loop
- **Parallel streams:** Multiple Task agents in one message
- **Quality assurance:** code-reviewer agent after implementation

---

# Long-Running Session Research

**Research Date:** 2026-02-16
**Researcher:** Claude Opus 4.6

## Table of Contents

1. [SIGKILL and Process Termination Issues](#1-sigkill-and-process-termination-issues)
2. [Memory Leaks](#2-memory-leaks)
3. [Context Window and Compaction](#3-context-window-and-compaction)
4. [Session Resume and Recovery](#4-session-resume-and-recovery)
5. [Terminal Multiplexers (tmux/screen)](#5-terminal-multiplexers-tmuxscreen)
6. [Heartbeat and Keepalive](#6-heartbeat-and-keepalive)
7. [Timeout Configuration](#7-timeout-configuration)
8. [Headless and Autonomous Mode](#8-headless-and-autonomous-mode)
9. [Official Best Practices Summary](#9-official-best-practices-summary)
10. [Practical Recommendations](#10-practical-recommendations)

---

## 1. SIGKILL and Process Termination Issues

### 1.1 CLI Freezes Requiring SIGKILL

**Source:** [GitHub Issue #24478](https://github.com/anthropics/claude-code/issues/24478) (Feb 2026)

- Claude Code CLI becomes completely unresponsive after ~10 minutes of active use
- Process ignores all signals: Ctrl+C, Ctrl+Z, SIGINT, SIGTERM, SIGHUP, SIGTSTP
- Only `kill -9` (SIGKILL) successfully terminates the process
- Session resume (`claude --resume`) also hangs indefinitely on "Resuming conversation"
- Affected version: 2.1.37 on Fedora Linux 43 (aarch64)
- Suspected causes: Node.js event loop blocking, conversation state serialization bug, or resource leak
- Multiple duplicate issues: [#20572](https://github.com/anthropics/claude-code/issues/20572), [#23590](https://github.com/anthropics/claude-code/issues/23590), [#23725](https://github.com/anthropics/claude-code/issues/23725)
- **Status: OPEN, no official fix**

### 1.2 Docker Container Self-Kill (Exit Code 137)

**Source:** [GitHub Issue #16135](https://github.com/anthropics/claude-code/issues/16135) (Jan-Feb 2026)

- When running in Docker, killing a background process causes Claude Code itself to crash
- **Root cause identified:** Claude Code and spawned processes share the same process group; when Claude sends `kill -PGID`, it kills itself
- Exit code 137 = SIGKILL
- Workaround: `setsid uvicorn api:app --port 8000 > /tmp/server.log 2>&1 &` (isolates child but loses monitoring)
- Suggested fix: spawn background processes with `setsid` or `setpgid()` for process group isolation
- Multiple duplicates: #16302, #19024, #23484, #24004
- **Status: OPEN, well-understood root cause but not fixed**

### 1.3 SIGABRT During Shutdown

**Source:** [GitHub Issue #7718](https://github.com/anthropics/claude-code/issues/7718) (Sep 2025)

- Claude Code crashes with SIGABRT during shutdown due to MCP server termination failure
- Generates large core dumps
- Related: [Issue #11617](https://github.com/anthropics/claude-code/issues/11617) - SIGABRT on process termination

### 1.4 Self-Termination When Killing Node.js Processes

**Source:** [GitHub Issue #9970](https://github.com/anthropics/claude-code/issues/9970)

- When asked to kill Node.js processes, Claude Code terminates itself
- Same underlying cause as the Docker issue: shared process group

### Key Insight for SIGKILL Issues
The fundamental problem is that Claude Code's Node.js process shares process groups with child processes and has fragile signal handling. Long-running sessions accumulate state that can block the event loop. There is no robust watchdog or self-recovery mechanism.

---

## 2. Memory Leaks

### 2.1 Critical: 120+ GB RAM Consumption

**Source:** [GitHub Issue #4953](https://github.com/anthropics/claude-code/issues/4953) (47 upvotes, 61 comments)

- Process grows from ~400MB to 120+ GB RAM during extended sessions (30-60 minutes)
- OOM killer terminates process; system becomes unresponsive
- OOM kill logs show: `total-vm:234427056kB, anon-rss:124857720kB` (234GB virtual, 125GB physical)
- Memory is anonymous (heap), not file-backed -- suggests unbounded data structures
- Restarts begin at ~400MB but leak resumes
- Workaround: "committing to memory that CC should terminate any processes it's done using" -- suggests unclosed subprocess handles
- **Labels: `oncall` (on team's radar), `has repro`, `perf:memory`**

### 2.2 Critical: 129GB RAM / System Freeze

**Source:** [GitHub Issue #11315](https://github.com/anthropics/claude-code/issues/11315)

- Version 2.0.36 on Ubuntu 24.04 (16GB RAM system)
- Memory growth timeline: 2GB -> 12GB in 30 minutes, system freeze at 33 minutes
- After restart: 72GB VmSize allocated IMMEDIATELY (leak persists across restarts!)
- VmData segment: 68GB -- suggests heap corruption or leaked allocations
- No OOM killer, no kernel panic -- complete kernel/hardware lockup requiring hard power reset
- Triggers: calling subtasks, multiple agents, extended runtime (14+ hours), large conversation history (500+ sessions = 488MB)
- Related: #11377 (23GB after 14 hours), #12221 (500+ sessions crash), #12327, #12399

### 2.3 Idle Memory Consumption

**Source:** [GitHub Issue #25545](https://github.com/anthropics/claude-code/issues/25545) (Feb 2026)

- 22GB+ RAM consumed **while idle** with no active tasks
- Version 2.1.39 on Windows
- Error logs show repeated `ECONNABORTED` timeout errors from telemetry system
- Related: #24827, #24840 (13GB RSS / 47GB commit on Windows), #18859 (idle sessions)

### 2.4 macOS-Specific

**Source:** [GitHub Issue #23252](https://github.com/anthropics/claude-code/issues/23252)

- Claude Code 2.1.19 consuming ~12GB RAM on macOS 15.5
- Normal usage patterns, not extended sessions

### Key Insight for Memory Issues
Memory leaks are the **most critical long-running session problem**. They affect all platforms (Linux, macOS, Windows), accumulate even when idle, and can persist across restarts. The only reliable mitigation is periodic restarts before memory exhaustion. Monitor with `ps aux --sort=-%mem | head -5` and restart when RSS exceeds 4-5GB.

---

## 3. Context Window and Compaction

### 3.1 Context Window Basics

**Source:** [Official Docs - Best Practices](https://code.claude.com/docs/en/best-practices)

- Claude's context window is 200K tokens (500K for Sonnet 4.5 on Enterprise)
- Context holds: entire conversation + every file read + every command output
- **Performance degrades as context fills** -- Claude "forgets" earlier instructions, makes more mistakes
- Context window is described as "the most important resource to manage"

### 3.2 Auto-Compaction

**Source:** [Official Docs - Best Practices](https://code.claude.com/docs/en/best-practices), [claudefast Blog](https://claudefa.st/blog/guide/mechanics/context-buffer-management)

- Triggers automatically at ~83.5% of window (was ~77-78% previously)
- For a 200K window: compaction occurs around 167K tokens
- Buffer reduced from 45K to ~33K tokens (16.5% of window) in early 2026
- Claude summarizes conversation history, replacing older messages with condensed summaries
- Granular details from early parts of session are lost
- Can achieve ~58.6% token reduction

### 3.3 Manual Compaction

**Source:** [Official Docs](https://code.claude.com/docs/en/best-practices)

- `/compact` command: takes conversation history and creates summary, starts new session with summary preloaded
- `/compact <instructions>`: customize what to preserve, e.g., `/compact Focus on the API changes`
- `Esc + Esc` or `/rewind`: selective summarization -- summarize from a checkpoint forward while keeping earlier context
- Can customize in CLAUDE.md: `"When compacting, always preserve the full list of modified files and any test commands"`

### 3.4 Server-Side Compaction API (Beta)

**Source:** [Anthropic Platform Docs](https://platform.claude.com/docs/en/build-with-claude/compaction)

- Beta feature: `compact-2026-01-12`
- Supported on Claude Opus 4.6
- Trigger threshold: configurable, minimum 50K tokens, default 150K
- `pause_after_compaction`: allows injecting preserved messages before continuing
- Custom `instructions` parameter to control summarization focus
- Compaction blocks replace all prior content when passed back to API
- Works with prompt caching (can cache system prompt separately)
- Can enforce total token budgets by counting compactions

### 3.5 Environment Variables

**Source:** [claudefast Blog](https://claudefa.st/blog/guide/mechanics/context-buffer-management)

- `CLAUDE_AUTOCOMPACT_PCT_OVERRIDE` (1-100): adjust when compaction fires
- `CLAUDE_CODE_MAX_OUTPUT_TOKENS`: controls response length (default: 32K), not buffer size
- The 33K autocompact buffer is hardcoded and non-configurable

### 3.6 Extended Context Options

- `sonnet[1m]` model offers 1M token windows, dramatically extending usable space
- `/context` command: monitor real-time token allocation

### Key Insight for Context Management
Auto-compaction prevents hard crashes but causes information loss. Users report that waiting for auto-compact can cause the agent to "lose important context and spiral out of control." Proactive `/clear` between tasks and manual `/compact` with specific preservation instructions are more reliable than relying on auto-compaction.

---

## 4. Session Resume and Recovery

### 4.1 Resume Commands

**Source:** [Official Docs](https://code.claude.com/docs/en/best-practices), [mehmetbaykar.com](https://mehmetbaykar.com/posts/resume-claude-code-sessions-after-restart/)

- `claude --continue` (`-c`): resume most recent conversation
- `claude --resume` (`-r`): browse and select from recent sessions
- `/resume`: in-session picker for previous sessions
- `/rename`: give sessions descriptive names for later retrieval
- Session IDs can be captured: `session_id=$(claude -p "..." --output-format json | jq -r '.session_id')`
- Conversations saved locally as `.jsonl` files

### 4.2 Known Resume Issues

**Source:** [GitHub Issue #7455](https://github.com/anthropics/claude-code/issues/7455), [#19036](https://github.com/anthropics/claude-code/issues/19036), [#18880](https://github.com/anthropics/claude-code/issues/18880)

- **Windows freezing:** `claude --continue` causes complete terminal freeze; `--resume` freezes temporarily but eventually recovers
- **Large session data:** Sessions with large tool output (e.g., 1.4MB git diff) cause hangs when rendering history
- **Killed sessions:** If killed during tool execution, `.jsonl` session file is left incomplete; resume fails with error
- **Resume crashes on killed sessions:** `claude --resume` crashes when attempting to resume sessions that were forcefully terminated; Ctrl+C is unresponsive during tool execution ([#18880](https://github.com/anthropics/claude-code/issues/18880))

### 4.3 MCP Reconnection

**Source:** [GitHub Issue #15232](https://github.com/anthropics/claude-code/issues/15232)

- Feature request for auto-reconnect or `/reconnect-mcp` command
- MCP HTTP transport drops after ~89 minutes without reconnection ([#21721](https://github.com/anthropics/claude-code/issues/21721))

### Key Insight for Session Resume
Session resume exists and works for clean exits, but is unreliable after crashes or SIGKILL. Large session histories cause hangs. The `.jsonl` format can be corrupted by unclean termination. For critical work, commit code frequently -- do not rely on session resume as your only recovery mechanism.

---

## 5. Terminal Multiplexers (tmux/screen)

### 5.1 Why Use tmux

**Source:** [Geeky Gadgets](https://www.geeky-gadgets.com/making-claude-code-work-247-using-tmux/), [hboon.com](https://hboon.com/using-tmux-with-claude-code/)

- Detach from session while Claude Code keeps running; reattach hours/days later
- Conversation history, running processes, and builds preserved on reattach
- Critical for SSH sessions that may disconnect
- Enables running multiple Claude Code instances simultaneously

### 5.2 Multi-Agent tmux Workflows

**Source:** [Medium - Agent Teams](https://darasoba.medium.com/how-to-set-up-and-use-claude-code-agent-teams-and-actually-get-great-results-9a34f8648f6d), [Scuti AI](https://scuti.asia/combining-tmux-and-claude-to-build-an-automated-ai-agent-system-for-mac-linux/)

- Each Claude Code agent team member can get its own tmux pane
- Recommended for more than two teammates to spot problems as they happen
- `claude-tmux` tool: TUI for managing multiple Claude Code sessions within tmux ([GitHub](https://github.com/nielsgroen/claude-tmux))

### 5.3 Known tmux Issues

**Source:** [GitHub Issue #9935](https://github.com/anthropics/claude-code/issues/9935)

- Claude Code's streaming output causes **4,000-6,700 scroll events per second** in tmux
- Results in severe UI jitter and flickering
- Affects tmux and smux terminal multiplexers

### 5.4 Remote Development Pattern

**Source:** [blog.esc.sh](https://blog.esc.sh/using-claude-code-on-the-go/)

- tmux + Tailscale: run Claude Code on a remote machine, access from any device
- Session persists regardless of local device disconnection

### Key Insight for tmux
tmux is the recommended approach for long-running Claude Code sessions. It provides session persistence through network disconnects, allows monitoring multiple agents, and enables remote access. However, be aware of the scroll event jitter issue when using streaming output.

---

## 6. Heartbeat and Keepalive

### 6.1 No Built-In Keepalive for CLI Sessions

There is no documented keepalive or heartbeat mechanism for interactive Claude Code CLI sessions. The process relies on the terminal session staying alive.

### 6.2 Connection Timeout Issues

**Source:** [GitHub Issue #8698](https://github.com/anthropics/claude-code/issues/8698)

- "fetch failed" errors after ~10 seconds despite timeout config of 600000ms
- System uses retry mechanism: up to 10 retries before failing

### 6.3 MCP HTTP Transport Timeout

**Source:** [GitHub Issue #21721](https://github.com/anthropics/claude-code/issues/21721)

- MCP HTTP transport connections drop after ~89 minutes (5322 seconds) without automatic reconnection
- Feature request ([#5982](https://github.com/anthropics/claude-code/issues/5982)) for MCP connect/disconnect/heartbeat monitor hooks

### 6.4 Chrome Extension Service Worker Timeout

**Source:** [GitHub Issue #15239](https://github.com/anthropics/claude-code/issues/15239)

- Chrome extension service worker times out after ~30 seconds idle
- Proposed keepalive: call `chrome.runtime.getPlatformInfo()` every ~25 seconds

### 6.5 Claude Desktop Idle Timeout

**Source:** [GitHub Issue #23092](https://github.com/anthropics/claude-code/issues/23092)

- `SessionIdleManager` with hardcoded 300-second (5-minute) timeout
- Silently quits with no warning, no configuration option to disable
- Interrupts background agents and long-running operations
- **Not configurable** -- no `claude_desktop_config.json` option exists

### Key Insight for Keepalive
There is no keepalive mechanism for the CLI. The MCP transport drops after 89 minutes. The Desktop app kills sessions after 5 minutes idle. For long-running sessions, use tmux to maintain terminal connectivity, and be aware that MCP server connections may need manual intervention for sessions exceeding ~90 minutes.

---

## 7. Timeout Configuration

### 7.1 Bash Command Timeouts

**Source:** [GitHub Issue #5615](https://github.com/anthropics/claude-code/issues/5615)

- Default: 2 minutes (120,000ms) per bash command
- Maximum: 10 minutes (600,000ms) per bash command
- Configurable in `~/.claude/settings.json`:

```json
{
  "env": {
    "BASH_DEFAULT_TIMEOUT_MS": "1800000",
    "BASH_MAX_TIMEOUT_MS": "7200000"
  }
}
```

- The above sets 30-minute default and 2-hour max

### 7.2 API Request Timeouts

- API requests use retry logic with up to 10 attempts
- Context usage above 70% can trigger API timeout errors ([#14407](https://github.com/anthropics/claude-code/issues/14407))

### Key Insight for Timeouts
Bash command timeouts are the most commonly hit limit. Configure them in settings.json for your use case. API timeouts are harder to control and correlate with high context usage.

---

## 8. Headless and Autonomous Mode

### 8.1 Headless Mode Basics

**Source:** [Official Docs](https://code.claude.com/docs/en/headless)

- `claude -p "prompt"`: run non-interactively
- Output formats: `text` (default), `json`, `stream-json`
- Can continue sessions: `claude -p "..." --continue` or `--resume "$session_id"`
- System prompt customization: `--append-system-prompt`, `--system-prompt`
- Tool restrictions: `--allowedTools "Read,Edit,Bash(git commit *)"`

### 8.2 Autonomous Execution

**Source:** [VentureBeat](https://venturebeat.com/orchestration/claude-codes-tasks-update-lets-agents-work-longer-and-coordinate-across-sessions/)

- "Tasks" feature enables persistent memory, dependency understanding, and stability for long-running processes
- Moves Claude Code from "copilot" to "subagent" that can run in background
- `--dangerously-skip-permissions`: bypass all permission checks (use only in sandboxed environments)
- `/sandbox`: OS-level isolation with defined boundaries (safer alternative)

### 8.3 Fan-Out Pattern

**Source:** [Official Docs](https://code.claude.com/docs/en/best-practices)

- Generate task list, loop through calling `claude -p` for each
- Example: migrate 2,000 files in parallel with scoped permissions
- Test on a few files first, refine prompt, then scale

### Key Insight for Headless Mode
Headless mode is the most robust way to run long autonomous tasks. It avoids interactive session issues, can be wrapped in monitoring scripts, and supports session chaining via `--continue`/`--resume`. For critical long-running work, prefer headless with explicit session management over interactive sessions.

---

## 9. Official Best Practices Summary

**Source:** [Official Docs - Best Practices](https://code.claude.com/docs/en/best-practices)

### Context Management (Most Important)
1. **Context window fills up fast** -- performance degrades as it fills
2. Use `/clear` frequently between unrelated tasks
3. Use subagents for investigation to avoid consuming main context
4. After two failed corrections on the same issue, `/clear` and start fresh
5. Auto-compaction preserves "important code and decisions" but loses details

### Session Management
1. Course-correct early: `Esc` to stop, `Esc+Esc` to rewind, `/clear` to reset
2. Use `/rename` to name sessions for later retrieval
3. `claude --continue` and `--resume` for session persistence
4. Checkpoints: every Claude action creates one; restore code, conversation, or both
5. Checkpoints persist across sessions (survive terminal close)

### Scaling
1. Multiple parallel sessions for speed
2. Writer/Reviewer pattern: separate sessions for implementation and review
3. Headless mode for CI/CD integration
4. Fan-out for batch operations across many files

### Anti-Patterns to Avoid
1. **Kitchen sink session**: mixing unrelated tasks in one session
2. **Correction spiral**: repeatedly correcting instead of clearing and restarting
3. **Over-specified CLAUDE.md**: too long = instructions get ignored
4. **Trust-then-verify gap**: no tests = plausible but broken code
5. **Infinite exploration**: unscoped investigation fills context

---

## 10. Practical Recommendations

### For Long-Running Sessions

1. **Use tmux** -- essential for any session expected to last more than a few minutes. Protects against SSH disconnects, terminal closes, and allows reattachment.

2. **Monitor memory** -- run `watch -n 30 'ps aux --sort=-%mem | head -5'` in a separate tmux pane. Restart Claude Code if RSS exceeds 4-5GB.

3. **Commit frequently** -- do not rely on session resume. Git commits are the only reliable state preservation mechanism.

4. **Proactive context management** -- use `/clear` between tasks, `/compact` with specific preservation instructions before auto-compaction triggers. Do not let context fill to 83.5%.

5. **Prefer headless for autonomous work** -- `claude -p "..." --continue` in a script with session ID tracking is more robust than interactive sessions for unattended work.

6. **Configure timeouts** -- set `BASH_DEFAULT_TIMEOUT_MS` and `BASH_MAX_TIMEOUT_MS` in settings.json for your expected workloads.

7. **Use subagents for research** -- delegate investigation to subagents to keep main context clean.

8. **Name sessions** -- use `/rename` immediately so you can find and resume sessions later.

9. **Expect MCP drops** -- MCP HTTP connections drop after ~89 minutes. Plan for reconnection in sessions longer than 90 minutes.

10. **Avoid Docker without process isolation** -- background processes in Docker containers will share process groups, causing self-kill. Use `setsid` for child processes.

### Emergency Recovery

If Claude Code freezes:
- Try `Esc` first (interrupt current action)
- Try `Ctrl+C` (SIGINT)
- Try `kill <pid>` from another terminal (SIGTERM)
- Last resort: `kill -9 <pid>` (SIGKILL) -- session file may be corrupted
- After SIGKILL: your last git commit is your recovery point; `claude --resume` may or may not work

### Environment Variables Reference

| Variable | Purpose | Default |
|----------|---------|---------|
| `BASH_DEFAULT_TIMEOUT_MS` | Default bash command timeout | 120000 (2 min) |
| `BASH_MAX_TIMEOUT_MS` | Maximum bash command timeout | 600000 (10 min) |
| `CLAUDE_AUTOCOMPACT_PCT_OVERRIDE` | Compaction trigger threshold (1-100) | ~83.5% |
| `CLAUDE_CODE_MAX_OUTPUT_TOKENS` | Max response length | 32000 |
| `CLAUDE_CODE_DISABLE_AUTO_MEMORY` | Force auto memory on (0) or off (1) | gradual rollout |

---

## Source Index

### Official Documentation
- [Best Practices](https://code.claude.com/docs/en/best-practices)
- [Headless / Programmatic Mode](https://code.claude.com/docs/en/headless)
- [Memory Management](https://code.claude.com/docs/en/memory)
- [Server-Side Compaction API](https://platform.claude.com/docs/en/build-with-claude/compaction)
- [Usage and Length Limits](https://support.claude.com/en/articles/11647753-understanding-usage-and-length-limits)

### GitHub Issues - SIGKILL / Process Termination
- [#24478](https://github.com/anthropics/claude-code/issues/24478) - CLI freeze requiring SIGKILL (Feb 2026)
- [#16135](https://github.com/anthropics/claude-code/issues/16135) - Docker self-kill via shared process group
- [#7718](https://github.com/anthropics/claude-code/issues/7718) - SIGABRT on MCP shutdown
- [#9970](https://github.com/anthropics/claude-code/issues/9970) - Self-termination killing Node.js processes
- [#25629](https://github.com/anthropics/claude-code/issues/25629) - CLI hangs in stream-json mode
- [#6352](https://github.com/anthropics/claude-code/issues/6352) - Unhandled process termination

### GitHub Issues - Memory Leaks
- [#4953](https://github.com/anthropics/claude-code/issues/4953) - 120+ GB RAM, OOM killed (47 upvotes)
- [#11315](https://github.com/anthropics/claude-code/issues/11315) - 129GB RAM, system freeze
- [#23252](https://github.com/anthropics/claude-code/issues/23252) - 12GB on macOS
- [#20777](https://github.com/anthropics/claude-code/issues/20777) - 20GB+ on Linux
- [#25545](https://github.com/anthropics/claude-code/issues/25545) - 22GB+ when idle (Windows)
- [#11377](https://github.com/anthropics/claude-code/issues/11377) - 23GB after 14 hours

### GitHub Issues - Session / Connection
- [#7455](https://github.com/anthropics/claude-code/issues/7455) - Resume freezing on Windows
- [#19036](https://github.com/anthropics/claude-code/issues/19036) - Hang on large session history
- [#18880](https://github.com/anthropics/claude-code/issues/18880) - Resume crash on killed sessions
- [#23092](https://github.com/anthropics/claude-code/issues/23092) - Desktop 5-minute idle timeout
- [#21721](https://github.com/anthropics/claude-code/issues/21721) - MCP HTTP drops after 89 minutes
- [#15232](https://github.com/anthropics/claude-code/issues/15232) - MCP auto-reconnect request
- [#8698](https://github.com/anthropics/claude-code/issues/8698) - Persistent connection timeouts
- [#14407](https://github.com/anthropics/claude-code/issues/14407) - API timeout at >70% context
- [#5615](https://github.com/anthropics/claude-code/issues/5615) - Timeout configuration guide

### GitHub Issues - Terminal Multiplexer
- [#9935](https://github.com/anthropics/claude-code/issues/9935) - Scroll event jitter in tmux (4K-6.7K events/sec)

### Community Resources
- [Claude Code + tmux Workflow](https://www.geeky-gadgets.com/making-claude-code-work-247-using-tmux/)
- [claude-tmux Manager](https://github.com/nielsgroen/claude-tmux)
- [Session Management Course](https://stevekinney.com/courses/ai-development/claude-code-session-management)
- [Context Buffer Analysis](https://claudefa.st/blog/guide/mechanics/context-buffer-management)
- [Compaction Deep Dive](https://stevekinney.com/courses/ai-development/claude-code-compaction)
- [Resume Sessions After Restart](https://mehmetbaykar.com/posts/resume-claude-code-sessions-after-restart/)
- [Troubleshooting and Recovery](https://www.letanure.dev/blog/2025-08-09--claude-code-part-11-troubleshooting-recovery)
- [Using Claude Code on the Go](https://blog.esc.sh/using-claude-code-on-the-go/)
