# claude-autonomy-test

An experiment in AI-to-AI delegation: can one AI agent autonomously drive another?

## What This Is

This repository is a test bed for **Dot** (an OpenClaw agent) autonomously operating a **Claude Code** session powered by **Claude Opus 4.6**. Rather than a human typing prompts into Claude Code, Dot acts as the operator — issuing instructions, evaluating outputs, and driving the session forward without human intervention.

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

## Model Selection: Claude Opus 4.6

The Claude Code session in this experiment runs on **Claude Opus 4.6** (`claude-opus-4-6`), Anthropic's most capable model at the time of this experiment.

The model identity wasn't chosen upfront — it was *discovered during the session itself*. Claude Code's system prompt includes metadata about the powering model, which means the agent can self-report what it's running on. In this case, the session revealed:

> You are powered by the model named Opus 4.6. The exact model ID is `claude-opus-4-6`.

This is a small but interesting detail of the experiment: the inner agent (Claude Code) is aware of its own model identity, and the outer agent (Dot) can query for and reason about that information. It's turtles knowing they're turtles, all the way down.

For context, the Claude 4.5/4.6 model family as of this experiment includes:
- **Opus 4.6** — highest capability, used here
- **Sonnet 4.5** — balanced performance and speed
- **Haiku 4.5** — fastest, most lightweight

## Repository Contents

| File | Purpose |
|---|---|
| `README.md` | This file — the first task Dot asked Claude Code to produce |
| `TRANSCRIPT.md` | Log of the Dot-to-Claude-Code interaction |
