<p align="center">
  <img src="docs/icon.png" width="128" alt="agentch">
</p>

<h1 align="center">agentch</h1>

<p align="center">
  A macOS notch app that tracks your AI coding agents.<br>
  Hover the notch to see what Claude Code and Codex are working on, what they have spent,<br>
  and how close you are to your limits.
</p>

<p align="center">
  <img src="https://img.shields.io/github/v/release/aktoriukas/agentch?color=E8913A&label=release" alt="Latest release">
  <img src="https://img.shields.io/badge/macOS-14%2B-black" alt="macOS 14+">
  <img src="https://img.shields.io/badge/universal-Apple%20Silicon%20%2B%20Intel-black" alt="Universal binary">
  <img src="https://img.shields.io/github/license/aktoriukas/agentch?color=black" alt="MIT">
</p>

<p align="center">
  <img src="docs/hover.png" width="760" alt="The hover stage: a progress ring per provider either side of the notch, above the session list">
</p>

---

## Install

Pick one. All three end with the app in `/Applications`.

| | Command | Needs |
| :-- | :-- | :-- |
| **Script** | `curl -fsSL https://raw.githubusercontent.com/aktoriukas/agentch/main/scripts/install.sh \| bash` | nothing |
| **Homebrew** | `brew install aktoriukas/tap/agentch` | Homebrew, Swift toolchain, ~1 min build |
| **Source** | `git clone https://github.com/aktoriukas/agentch.git && cd agentch && ./scripts/build-app.sh --install` | Swift toolchain |

The script downloads a prebuilt universal build. Homebrew and source compile on your machine — no
Xcode needed, the Command Line Tools are enough (`xcode-select --install`).

> [!NOTE]
> Homebrew installs GUI apps into its own prefix, so link it once:
> `ln -sfn "$(brew --prefix)/opt/agentch/Agentch.app" /Applications/Agentch.app`

### First run

**Nothing appears in the Dock or the menu bar.** That is deliberate — move the pointer to the notch,
or to the top centre of the screen on a display without one.

macOS will ask for Keychain access the first time Claude limits are fetched. Allow it and the
numbers come from Anthropic's usage endpoint; deny it and you get a local estimate labelled `est.`
instead. Codex needs neither network nor auth.

Then open the gear to turn on **Launch at login** and **"waiting on you" detection** if you want
them.

<details>
<summary><b>Gatekeeper</b> — why a downloaded copy needs one extra step</summary>

<br>

agentch is not notarised, so a copy you *download* is quarantined and macOS refuses to open it.

- The **install script** clears that flag for you, after verifying the download against a published
  SHA-256.
- **Homebrew** and **source** builds compile locally, so nothing is ever quarantined.
- Grabbing the zip from the releases page by hand? Clear it yourself:

  ```bash
  xattr -dr com.apple.quarantine /Applications/Agentch.app
  ```

</details>

---

## The three stages

### Closed

One segment per provider across the width of the notch, filled with what is **left** of its nearest
limit. The whole thing glows amber when a session is waiting on you. On a notched display only the
bottom sliver shows, which is where the bar lives — displays without a notch get the pill below.

<img src="docs/closed.png" width="420" alt="The closed pill: session count above a two-segment remaining bar">

### Hover

A progress ring per provider, parked in the dead space either side of the cutout, then every active
session one line each. Click a session to reopen it in the app that owns it. The count, the expand
chevron and the gear share a bar along the bottom.

<img src="docs/hover.png" width="760" alt="The hover stage">

### Click

The full panel: the same rings in the same place, every limit window per provider with reset
countdowns, and the session feed with model, project, branch, context use, tokens and cost.

<img src="docs/panel.png" width="760" alt="The full panel: limit windows per provider above the session feed">

Every stage change is instant. No animation to sit through.

---

## What it does

**Sessions**

- Every running Claude Code and Codex session, newest first, across all your projects
- Title, model, project, git branch, context used, tokens and estimated cost per session
- Working · idle · waiting on you · done, as a coloured dot
- Click to reopen a session in the app that owns it; filter the panel by provider

**Limits**

- Every window each provider reports — 5-hour, weekly, and the model-scoped weekly ones
- Reset countdowns, and a colour that escalates as a window fills
- Burn-rate projection: how long until a window fills at your current rate
- Locally derived windows are labelled `est.`, never passed off as reported

**Cost**

- Estimated dollars per session and per day at API list prices, always labelled an estimate
- Token parity toggle: count cache tokens to match `ccusage`, or exclude them to match the web apps

**Appearance**

- Show on the notched built-in, on external displays as a pill, or both
- A colour per agent and per model, seeded from the model name so they differ before you touch it
- Choose which per-session details the hover carries

---

## Under the hood

Everything is read-only. agentch never writes to, or refreshes, another tool's credentials.

| Provider | Source |
| :-- | :-- |
| **Codex** | `~/.codex` — rollout files carry rate-limit snapshots (no network, no auth); the thread database supplies titles, models and token counts |
| **Claude Code** | `~/.claude` — a registry of running sessions, todo lists, and transcripts with per-message token usage. Limits come from Anthropic's OAuth usage endpoint, falling back to a labelled local estimate |

<details>
<summary><b>"Waiting on you" detection</b> — exactly what it changes</summary>

<br>

Off by default. Enabling it adds two hooks (`Notification` and `Stop`) to `~/.claude/settings.json`
that append events to a file agentch watches. Turning it off removes exactly those entries. The
file is backed up to `settings.json.agentch-backup` before either edit.

</details>

<details>
<summary><b>Development</b></summary>

<br>

```bash
swift run Agentch --selfcheck   # assert-based checks for the pure logic in AgentchCore
swift run Agentch --render      # renders each stage to /tmp/agentch-*.png
swift run Agentch --dump        # prints what the providers currently report
swift run Agentch --icon        # renders the app icon to /tmp/agentch-icon.png
```

`--render` exists so the UI can be reviewed without Xcode previews — the screenshots above come
straight out of it. Checks live in `AgentchCore/SelfCheck.swift` rather than a test target, so they
run without XCTest.

The icon is a SwiftUI view (`Sources/Agentch/AppIcon.swift`), not a binary asset:
`scripts/build-app.sh` renders it, downsamples it into an iconset and packs the `.icns` at build
time. Releases are built universal by GitHub Actions, since that needs full Xcode.

</details>

---

## Credits

Built fresh, but standing on MIT-licensed work worth reading:
[NotchDrop](https://github.com/Lakr233/NotchDrop) and
[DynamicNotchKit](https://github.com/MrKai77/DynamicNotchKit) for notch window mechanics,
[codex-island](https://github.com/ericjypark/codex-island) for notch-specific details,
[CodexBar](https://github.com/steipete/CodexBar) for provider endpoint and credential handling, and
[ccusage](https://github.com/ccusage/ccusage) for the cost-computation method.

MIT licensed.
