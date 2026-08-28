import AppKit
import ServiceManagement
import AgentchCore

/// Wraps a closure so NSMenuItem can call it without a dedicated target class per action.
final class MenuAction: NSObject {
    private let handler: () -> Void

    init(_ handler: @escaping () -> Void) {
        self.handler = handler
    }

    @objc func fire() { handler() }
}

@MainActor
enum AppMenu {
    /// Held for the lifetime of the menu; NSMenuItem does not retain its target.
    private static var actions: [MenuAction] = []

    static func show(state: AppState,
                     enabledDisplays: Set<CGDirectDisplayID>,
                     at point: NSPoint,
                     toggleDisplay: @escaping (CGDirectDisplayID) -> Void,
                     refresh: @escaping () -> Void) {
        actions = []
        let menu = NSMenu()

        let displays = NSMenu()
        for screen in NSScreen.screens {
            let id = screen.displayID
            let label = screen.localizedName + (screen.hasNotch ? " (notch)" : "")
            displays.addItem(item(label, checked: enabledDisplays.contains(id)) { toggleDisplay(id) })
        }
        let displayItem = NSMenuItem(title: "Show on", action: nil, keyEquivalent: "")
        displayItem.submenu = displays
        menu.addItem(displayItem)

        let fields = NSMenu()
        for (field, label) in HoverFields.choices {
            fields.addItem(item(label, checked: state.hoverFields.contains(field)) {
                state.hoverFields.formSymmetricDifference(field)
                state.hoverFields.save()
            })
        }
        let fieldsItem = NSMenuItem(title: "Hover shows", action: nil, keyEquivalent: "")
        fieldsItem.submenu = fields
        menu.addItem(fieldsItem)

        menu.addItem(.separator())
        menu.addItem(item("Count cache tokens", checked: state.parity == .all) {
            state.parity = state.parity == .all ? .conversational : .all
            UserDefaults.standard.set(state.parity.rawValue, forKey: "tokenParity")
        })

        menu.addItem(.separator())
        let hooksInstalled = ClaudeHooks.isInstalled()
        menu.addItem(item("Show when Claude is waiting on you", checked: hooksInstalled) {
            // Edits ~/.claude/settings.json; a backup is written alongside it first.
            try? hooksInstalled ? ClaudeHooks.uninstall() : ClaudeHooks.install()
        })

        let loginEnabled = SMAppService.mainApp.status == .enabled
        menu.addItem(item("Launch at login", checked: loginEnabled) {
            try? loginEnabled ? SMAppService.mainApp.unregister() : SMAppService.mainApp.register()
        })

        menu.addItem(.separator())
        menu.addItem(item("Refresh now", checked: false, action: refresh))
        menu.addItem(item("Quit agentch", checked: false) { NSApp.terminate(nil) })

        // The pointer leaves the panel to use the menu; hold the panel open until it closes.
        state.menuIsOpen = true
        menu.popUp(positioning: nil, at: point, in: nil)
        state.menuIsOpen = false
    }

    private static func item(_ title: String, checked: Bool, action: @escaping () -> Void) -> NSMenuItem {
        let wrapper = MenuAction(action)
        actions.append(wrapper)
        let item = NSMenuItem(title: title, action: #selector(MenuAction.fire), keyEquivalent: "")
        item.target = wrapper
        item.state = checked ? .on : .off
        return item
    }
}
