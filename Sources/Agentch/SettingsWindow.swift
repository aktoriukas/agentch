import AppKit
import SwiftUI
import ServiceManagement
import AgentchCore

/// A real window rather than a menu: colours need swatches, and displays need more than a list of
/// checkmarks squeezed into a submenu.
@MainActor
final class SettingsWindowController {
    private var window: NSWindow?
    private let state: AppState
    private let toggleDisplay: (CGDirectDisplayID) -> Void
    private let enabledDisplays: () -> Set<CGDirectDisplayID>
    private let refresh: () -> Void

    init(state: AppState,
         enabledDisplays: @escaping () -> Set<CGDirectDisplayID>,
         toggleDisplay: @escaping (CGDirectDisplayID) -> Void,
         refresh: @escaping () -> Void) {
        self.state = state
        self.enabledDisplays = enabledDisplays
        self.toggleDisplay = toggleDisplay
        self.refresh = refresh
    }

    func show() {
        if let window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let view = SettingsView(state: state,
                                enabledDisplays: enabledDisplays,
                                toggleDisplay: toggleDisplay,
                                refresh: refresh)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 460, height: 560),
                              styleMask: [.titled, .closable, .miniaturizable],
                              backing: .buffered,
                              defer: false)
        window.title = "agentch"
        let hosting = NSHostingView(rootView: view)
        window.contentView = hosting
        window.isReleasedWhenClosed = false
        // Sized to what it actually holds: the model list grows as models are discovered, so any
        // fixed height opens either scrolled or half empty.
        window.setContentSize(NSSize(width: 460, height: min(hosting.fittingSize.height, 700)))
        window.center()
        window.makeKeyAndOrderFront(nil)
        // An accessory app has no windows of its own by default; this one needs focus to be usable.
        NSApp.activate(ignoringOtherApps: true)
        self.window = window
        print("settings window: \(window.frame.integral) visible=\(window.isVisible)")
        fflush(stdout)
    }
}

struct SettingsView: View {
    @Bindable var state: AppState
    var enabledDisplays: () -> Set<CGDirectDisplayID>
    var toggleDisplay: (CGDirectDisplayID) -> Void
    var refresh: () -> Void

    @State private var displays: Set<CGDirectDisplayID> = []
    @State private var hooksInstalled = ClaudeHooks.isInstalled()
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled

    var body: some View {
        ScrollView {
            content
        }
        .frame(minWidth: 440, minHeight: 400)
        .onAppear { displays = enabledDisplays() }
    }

    /// Separate from `body` so it can be rendered offscreen; a ScrollView draws blank there.
    @ViewBuilder
    var content: some View {
            VStack(alignment: .leading, spacing: 16) {
                section("Displays") {
                    ForEach(NSScreen.screens, id: \.displayID) { screen in
                        Toggle(isOn: Binding(
                            get: { displays.contains(screen.displayID) },
                            set: { _ in
                                toggleDisplay(screen.displayID)
                                displays = enabledDisplays()
                            }
                        )) {
                            Text(screen.localizedName + (screen.hasNotch ? " · notch" : ""))
                        }
                    }
                }

                section("Agent colours") {
                    ForEach(Provider.allCases) { provider in
                        ColorRow(label: provider.displayName,
                                 hex: state.appearance.color(for: provider),
                                 isCustom: state.appearance.isCustom(provider: provider),
                                 set: { hex in
                                     state.appearance.set(hex, for: provider)
                                     state.appearance.save()
                                 })
                    }
                }

                section("Model colours") {
                    if state.knownModels.isEmpty {
                        Text("Models appear here once a session has used one.")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                    ForEach(state.knownModels, id: \.self) { model in
                        ColorRow(label: model,
                                 hex: state.appearance.color(forModel: model),
                                 isCustom: state.appearance.isCustom(model: model),
                                 set: { hex in
                                     state.appearance.set(hex, forModel: model)
                                     state.appearance.save()
                                 })
                    }
                }

                section("Hover shows") {
                    ForEach(HoverFields.choices, id: \.label) { choice in
                        Toggle(isOn: Binding(
                            get: { state.hoverFields.contains(choice.field) },
                            set: { _ in
                                state.hoverFields.formSymmetricDifference(choice.field)
                                state.hoverFields.save()
                            }
                        )) {
                            Text(choice.label)
                        }
                    }
                }

                section("Counting") {
                    Toggle(isOn: Binding(
                        get: { state.parity == .all },
                        set: { state.parity = $0 ? .all : .conversational
                               UserDefaults.standard.set(state.parity.rawValue, forKey: "tokenParity") }
                    )) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Count cache tokens")
                            Text("On matches ccusage totals; off matches what the web apps show.")
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                section("Claude Code") {
                    Toggle(isOn: Binding(
                        get: { hooksInstalled },
                        set: { wanted in
                            try? wanted ? ClaudeHooks.install() : ClaudeHooks.uninstall()
                            hooksInstalled = ClaudeHooks.isInstalled()
                        }
                    )) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Show when a session is waiting on you")
                            Text("Adds two hooks to ~/.claude/settings.json, backed up first.")
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                section("General") {
                    Toggle(isOn: Binding(
                        get: { launchAtLogin },
                        set: { wanted in
                            try? wanted ? SMAppService.mainApp.register() : SMAppService.mainApp.unregister()
                            launchAtLogin = SMAppService.mainApp.status == .enabled
                        }
                    )) {
                        Text("Launch at login")
                    }
                    HStack {
                        Button("Refresh now", action: refresh)
                        Spacer()
                        Button("Quit agentch") { NSApp.terminate(nil) }
                    }
                    .padding(.top, 4)
                }
            }
            .font(.system(size: 11))
            .padding(16)
    }

    private func section(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased())
                .font(.system(size: 9, weight: .semibold))
                .tracking(0.5)
                .foregroundStyle(.tertiary)
            content()
        }
    }
}

/// A swatch plus a reset, so an automatic colour can be taken back.
struct ColorRow: View {
    var label: String
    var hex: String
    var isCustom: Bool
    var set: (String?) -> Void

    var body: some View {
        HStack(spacing: 8) {
            ColorPicker("", selection: Binding(
                get: { Color(hex: hex) },
                set: { set($0.hexString) }
            ), supportsOpacity: false)
            .labelsHidden()

            Text(label)
                .font(.system(size: 11))
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer()

            if isCustom {
                Button("Reset") { set(nil) }
                    .buttonStyle(.link)
                    .font(.system(size: 10))
            } else {
                Text("auto")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }
        }
    }
}
