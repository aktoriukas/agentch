# agentch

A macOS notch app that tracks your AI coding agents. Hover the notch to see what Claude Code and
Codex are working on right now, what they have spent, and how close you are to your limits.

Status: **M1 — Codex live**. The notch/pill windows and the three interaction stages work, and
Codex sessions, tokens, estimated cost and both rate-limit windows come from real local data.
Claude lands in M2.
See [PLAN.md](PLAN.md) for the roadmap and [RESEARCH.md](RESEARCH.md) for how the integrations work.

## Running it

```bash
swift run Agentch
```

It runs as a menu-bar-less agent app: a panel appears over the notch on a notched display, and as a
small pill at the top centre of displays without one. By default it shows on your main display plus
a notched built-in.

- **closed** — ambient only: active session count, a tint that shifts green → amber → red as your
  worst limit window fills, and an orange dot when a session is waiting on you.
- **hover** — limit bars per provider with reset countdowns, plus any attention alerts.
- **click** — the full panel: combined session feed (filterable per provider), per-session model,
  context use, tokens and estimated cost.

## Development

```bash
swift run Agentch --selfcheck   # assert-based checks for the pure logic in AgentchCore
swift run Agentch --render      # renders each stage to /tmp/agentch-*.png
swift run Agentch --dump        # prints what the providers currently report
```

`--render` exists because this machine has Command Line Tools without Xcode: there are no previews,
and no XCTest or swift-testing either, so checks live in `AgentchCore/SelfCheck.swift`.

## How it gets its data

Everything is read-only. agentch never writes to, or refreshes, another tool's credentials.

- **Codex** — `~/.codex`: rollout files carry live rate-limit snapshots (no network, no auth), and
  the thread database supplies titles, models and per-thread token counts.
- **Claude Code** — `~/.claude`: a registry of running sessions, per-session todo lists, and
  transcripts with per-message token usage for cost. Subscription limits come from Anthropic's
  OAuth usage endpoint, falling back to a labelled local estimate when it is unavailable.

## Credits

Built fresh, but standing on MIT-licensed work worth reading:
[NotchDrop](https://github.com/Lakr233/NotchDrop) and
[DynamicNotchKit](https://github.com/MrKai77/DynamicNotchKit) for notch window mechanics,
[codex-island](https://github.com/ericjypark/codex-island) for notch-specific details,
[CodexBar](https://github.com/steipete/CodexBar) for provider endpoint and credential handling, and
[ccusage](https://github.com/ccusage/ccusage) for the cost-computation method.

MIT licensed.
