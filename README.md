# agentch

A macOS notch app that tracks your AI coding agents. Hover the notch to see what Claude Code and
Codex are working on right now, what they have spent, and how close you are to your limits.

Everything is read-only. agentch never writes to, or refreshes, another tool's credentials.

## Screenshots

**Closed.** Ambient only. One segment per provider across the width of the notch, filled with what
is left of its nearest limit. The whole thing glows amber when a session is waiting on you. On a
notched display only the bottom sliver is visible, which is where the bar lives; on displays
without one you get the pill below.

![The closed pill: session count above a two-segment remaining bar](docs/closed.png)

**Hover.** A progress ring per provider parked in the dead space either side of the cutout, then
every active session, one line each. The count, the expand chevron and the gear share a bar along
the bottom. Clicking a session reopens it in the app that owns it.

![The hover stage](docs/hover.png)

**Click.** The full panel: the same rings in the same place, every limit window per provider with
reset countdowns, and the session feed with model, project, branch, context use, tokens and
estimated cost.

![The full panel: limit windows per provider above the session feed](docs/panel.png)

## What it does

**Sessions**

- Live feed of every running Claude Code and Codex session, newest first, across all your projects.
- Per session: title, model, project, git branch, context window used, tokens, and estimated cost.
- State per session — working, idle, waiting on you, done — as a coloured dot.
- Click any session to reopen it in the app that owns it.
- Filter the panel by provider, or show everything.

**Limits**

- Every rate-limit window each provider reports: 5-hour, weekly, and model-scoped weekly windows
  (Opus, Sonnet, Fable) where they exist.
- A reset countdown per window, and a colour that escalates as a window fills.
- Burn-rate projection: how long until a window fills at the rate you are currently going.
- Windows derived locally rather than reported by the server are labelled `est.` so you know the
  difference.

**Cost**

- Estimated dollars per session and for the day, at API list prices, always labelled as an
  estimate.
- A parity toggle for how tokens are counted: include cache tokens to match `ccusage` totals, or
  exclude them to match what the provider web apps show.

**Attention**

- Opt-in detection of sessions blocked on a permission prompt or a question, surfaced as an amber
  pulse on the closed notch and a count in the hover.

**Appearance**

- Per-display: show on the notched built-in, on external displays as a top-centre pill, or both.
- A colour per agent and per model. Models start on a colour derived from their name, so they are
  distinguishable before you pick anything.
- Choose which per-session details the hover carries, so it stays as dense or as sparse as you
  want.

Every stage change is instant — the panel and its content are simply there, with no animation to
sit through.

## Installing it

```bash
brew install aktoriukas/tap/agentch
ln -sfn "$(brew --prefix)/opt/agentch/Agentch.app" /Applications/Agentch.app
open -a Agentch
```

The formula builds from source on your machine, which takes about a minute and needs macOS 14+ and
a Swift 6 toolchain (Xcode or the Command Line Tools — `xcode-select --install`). Building locally
is deliberate rather than lazy: an unsigned app downloaded from a release gets quarantined by
Gatekeeper, and one compiled on your own machine does not. Upgrade later with `brew upgrade
agentch`.

Nothing appears in the Dock or the menu bar — that is deliberate, it runs as an agent app. Move
your pointer to the notch (or to the top centre of your display, if it has no notch) and the panel
appears.

The first time it fetches Claude limits, macOS prompts for access to the Keychain item Claude Code
stores its OAuth token in. Allow it and the limits come from Anthropic's usage endpoint; deny it
and agentch falls back to a local 5-hour estimate, labelled `est.` in the UI. Codex limits need
neither network nor auth — they are read straight out of its local rollout files.

Then, optionally, open the gear in the hover or the panel to turn on **Launch at login** and
**"waiting on you" detection**.

### From source

```bash
git clone https://github.com/aktoriukas/agentch.git
cd agentch
./scripts/build-app.sh --install
```

That builds `Agentch.app`, icon and all, and copies it to `/Applications`. Drop `--install` to
leave it in `build/`. The bare executable at `.build/release/Agentch` runs too, but launch-at-login
needs the bundle.

### Detecting sessions that are waiting on you

Off by default. Enabling it adds two hooks (`Notification` and `Stop`) to `~/.claude/settings.json`
that append events to a file agentch watches; turning it off removes exactly those entries. The
file is backed up to `settings.json.agentch-backup` before either edit.

## How it gets its data

- **Codex** — `~/.codex`: rollout files carry live rate-limit snapshots (no network, no auth), and
  the thread database supplies titles, models and per-thread token counts.
- **Claude Code** — `~/.claude`: a registry of running sessions, per-session todo lists, and
  transcripts with per-message token usage for cost. Subscription limits come from Anthropic's
  OAuth usage endpoint, falling back to a labelled local estimate when it is unavailable.

## Development

```bash
swift run Agentch --selfcheck   # assert-based checks for the pure logic in AgentchCore
swift run Agentch --render      # renders each stage to /tmp/agentch-*.png
swift run Agentch --dump        # prints what the providers currently report
swift run Agentch --icon        # renders the app icon to /tmp/agentch-icon.png
```

The icon is drawn in SwiftUI (`Sources/Agentch/AppIcon.swift`) rather than kept as a binary asset,
so `scripts/build-app.sh` renders it, downsamples it into an iconset and packs the `.icns` at build
time.

`--render` exists because this machine has Command Line Tools without Xcode: there are no previews,
and no XCTest or swift-testing either, so checks live in `AgentchCore/SelfCheck.swift`. The
screenshots above come straight out of it.

## Credits

Built fresh, but standing on MIT-licensed work worth reading:
[NotchDrop](https://github.com/Lakr233/NotchDrop) and
[DynamicNotchKit](https://github.com/MrKai77/DynamicNotchKit) for notch window mechanics,
[codex-island](https://github.com/ericjypark/codex-island) for notch-specific details,
[CodexBar](https://github.com/steipete/CodexBar) for provider endpoint and credential handling, and
[ccusage](https://github.com/ccusage/ccusage) for the cost-computation method.

MIT licensed.
