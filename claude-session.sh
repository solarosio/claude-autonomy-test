#!/bin/bash
# claude-session.sh — Resilient Claude Code session launcher
# Uses tmux + caffeinate to survive terminal disconnects and system sleep
#
# Usage:
#   claude-session [name] [args...]
#   claude-session dev --model opus
#   claude-session                    # defaults to session "claude", --continue
#
# To attach: tmux attach -t claude
# To detach: Ctrl+B, D

SESSION_NAME="${1:-claude}"
shift 2>/dev/null

# Default args if none provided
CLAUDE_ARGS="${@:---dangerously-skip-permissions --model opus --continue}"

# Raise file descriptor limit (Claude Code needs this)
ulimit -n 10240 2>/dev/null

# Export helpful env vars
export CLAUDE_CODE_RESUME_INTERRUPTED_TURN=1

# Check if tmux is installed
if ! command -v tmux &>/dev/null; then
    echo "tmux not found. Install with: brew install tmux"
    exit 1
fi

# Check if session already exists
if tmux has-session -t "$SESSION_NAME" 2>/dev/null; then
    echo "Session '$SESSION_NAME' already exists. Attaching..."
    tmux attach -t "$SESSION_NAME"
    exit 0
fi

# Launch with caffeinate (prevents sleep) inside tmux
echo "Starting Claude Code session '$SESSION_NAME'..."
echo "  Args: $CLAUDE_ARGS"
echo "  Detach: Ctrl+B, D"
echo "  Reattach: tmux attach -t $SESSION_NAME"
echo ""

caffeinate -i -m tmux new-session -s "$SESSION_NAME" "ulimit -n 10240; CLAUDE_CODE_RESUME_INTERRUPTED_TURN=1 claude $CLAUDE_ARGS; echo 'Session ended. Press Enter to close.'; read"
