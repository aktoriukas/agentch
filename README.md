# agentch

A macOS notch app that tracks your AI coding agents. Hover the notch to see what Claude Code and
Codex are working on right now, what they have spent, and how close you are to your limits.

Status: **working on real data for both providers.** Sessions, token spend, estimated cost and
rate limits are live for Claude Code and Codex, along with burn-rate projection and opt-in
"waiting on you" detection. Remaining: packaging and release (see [PLAN.md](PLAN.md)).
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
- **hover** — every active session, one line each, sized to fit however many there are; plus a gear
  for settings and a chevron to expand.
- **click** — the full panel: limit gauges per provider with reset countdowns, the session feed
  filterable per provider with model, branch, context use, tokens and estimated cost, and how long
  until a limit window fills at the current burn rate.

The gear — in the hover as well as the panel — holds the settings: which displays to appear on,
which per-session details the hover carries, how the panel animates when it opens, whether to
count cache tokens, launch at login, and whether to detect sessions waiting on you.

Five opening animations are available: **Liquid** (the default — the panel pinches at the top and
its bottom edge sags as it pours out of the notch), **Snap** (quick and crisp), **Unfold** (unrolls
downwards like a drawer), **Bounce** (overshoots and settles), and **No animation**.

### Detecting sessions that are waiting on you

Off by default. Enabling it adds two hooks (`Notification` and `Stop`) to `~/.claude/settings.json`
that append events to a file agentch watches; turning it off removes exactly those entries. The
file is backed up to `settings.json.agentch-backup` before either edit.

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
