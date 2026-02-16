# claude-autonomy-test

An experiment in AI-to-AI delegation: can one AI agent autonomously drive another?

## What This Is

This repository is a test bed for **Dot** (an OpenClaw agent) autonomously operating a **Claude Code** session. Rather than a human typing prompts into Claude Code, Dot acts as the operator — issuing instructions, evaluating outputs, and driving the session forward without human intervention.

## The Experiment

The setup is straightforward:

1. A human creates an empty repository and starts a Claude Code session
2. **Dot** takes over as the operator, sending prompts to Claude Code
3. Claude Code executes the tasks (reading files, writing code, running commands)
4. The session is recorded in `TRANSCRIPT.md`

The human's only role is initializing the environment. Everything after that is agent-driven.

## What Success Looks Like

- Dot successfully issues coherent, well-scoped prompts to Claude Code
- Claude Code completes the requested tasks (starting with creating this README)
- The full interaction is captured in the transcript with no human correction needed
- The resulting artifacts (files, commits) are functional and reasonable

In short: two AI systems collaborating end-to-end to produce real output in a real repository, with a human only observing.

## Repository Contents

| File | Purpose |
|---|---|
| `README.md` | This file — the first task Dot asked Claude Code to produce |
| `TRANSCRIPT.md` | Log of the Dot-to-Claude-Code interaction |
