# Learning Design

## Philosophy

Cartograph is built on the premise that understanding a codebase is an active skill, not a passive one. Rather than generating AI summaries for you to read, it structures the codebase into a learning experience where you read actual source code, build mental models through guided paths, and reinforce understanding through spaced repetition.

## Learning Units

The fundamental learning unit is a **symbol cluster**: one symbol (function, class, or method) plus its immediate neighborhood in the call graph — what calls it and what it calls. Each cluster represents 3-8 minutes of focused reading time.

This granularity is intentional:
- A single function is too small — no context for why it exists
- An entire module is too large — overwhelms working memory
- A symbol + its neighbors provides just enough context to understand purpose and relationships

## Reading Path Strategies

### Complexity Ascending (Recommended for ADHD)

Sorts symbols by line count, simplest first. This provides:
- **Early wins**: The first few steps are 2-5 line enums and constants
- **Gradual ramp**: Complexity increases steadily
- **Momentum**: Each step feels achievable because you just completed a simpler one

### Topological (Bottom-Up)

Reverse topological sort of the dependency graph. You read leaf functions first (utilities, helpers) and work toward entry points. This builds understanding from foundations upward — you never encounter a function call you haven't already read.

### Entry-Point First (Top-Down)

BFS from main/CLI entry points outward. You start with the high-level flow and drill into implementations. Good for understanding "what does this program do" before "how does it do it."

## ADHD-Friendly Features

### Bounded Sessions

The focus timer defaults to 15-minute sessions. This is deliberate:
- Open-ended exploration is the worst modality for ADHD — no sense of progress, easy to hyperfocus or abandon
- Bounded sessions create a contract: "read for 15 minutes, then decide if you want another round"
- The timer is visible but non-stressful — a gentle activity ring, not a countdown bomb

### Zero-Friction Resume

`carto resume` (CLI) or the "Continue" card (GUI) picks up exactly where you left off. The goal is zero activation energy to re-enter a learning session. No choosing, no remembering, no deciding — just continue.

### Progress Visibility

A persistent progress bar shows "Step 14 of 87 (16%)" throughout the session. This provides:
- Concrete evidence of progress (fights the "I'm not getting anywhere" feeling)
- A sense of the whole — you know the territory you're mapping
- Permission to stop — "I've done 5 steps, that's enough for today"

### Micro-Rewards

Brief celebrations after completing each step. Streak counting ("4 steps in a row!") with escalating messages. These are intentionally subtle — a moment of acknowledgment, not a dopamine trap.

### Quick Capture

A hotkey sheet for capturing thoughts mid-reading. If you have an insight about the code, capture it without context-switching away from the reading flow. Notes are appended to `~/.cartograph/notes.md` with timestamps and symbol context.

## Spaced Repetition

### How It Works

When you encounter a concept worth remembering (a function's purpose, a design pattern, an architectural decision), you can create a review item. The system schedules reviews at expanding intervals:

| Review # | Interval | Example |
|----------|----------|---------|
| 1st | 1 day | Tomorrow |
| 2nd | 3 days | Thursday |
| 3rd | 7 days | Next week |
| 4th | 14 days | Two weeks |
| 5th | 30 days | Next month |
| 6th+ | 90 days | Quarterly |

Getting a review wrong resets the interval to 1 day. Getting it right advances to the next interval.

### Quiz Types

Questions are generated from the symbol graph:
- "What does `authenticate_user` call?" — tests call graph knowledge
- "Which module contains `SessionManager`?" — tests code organization knowledge
- "What does `validate_token` return?" — tests signature understanding

### Why This Matters

Without reinforcement, code understanding decays rapidly. You read a function on Monday, understand it, and by Friday it's fuzzy. Spaced repetition catches the decay before it happens, turning temporary understanding into durable knowledge.

## Explanation Levels

The explain panel offers three levels to match your current understanding:

- **Beginner**: Plain language, no jargon. "This function checks if a user's login information is correct."
- **Intermediate**: Purpose + design decisions + system context. "This authenticates against the OAuth provider, falling back to local credentials. It's called from the login middleware."
- **Expert**: Edge cases, performance, tradeoffs, alternatives. "This uses bcrypt with a cost factor of 12, which takes ~250ms. Consider argon2id for memory-hard resistance. The token TTL of 1 hour is a tradeoff between security and UX friction."
