import AppKit
import SwiftUI
import AgentchCore

extension NSScreen {
    var displayID: CGDirectDisplayID {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
    }

    var hasNotch: Bool {
        safeAreaInsets.top > 0 && auxiliaryTopLeftArea != nil
    }

    /// The hardware notch, or a pill of similar proportions on displays that lack one.
    var notchSize: CGSize {
        guard hasNotch, let left = auxiliaryTopLeftArea, let right = auxiliaryTopRightArea else {
            return CGSize(width: 190, height: max(NSStatusBar.system.thickness, 24))
        }
        return CGSize(width: frame.width - left.width - right.width, height: safeAreaInsets.top)
    }
}

enum NotchStage {
    case closed, peek, open
}

@MainActor
@Observable
final class NotchViewModel {
    private(set) var stage: NotchStage = .closed
    /// How far the panel's bottom edge sags mid-transition, 0...1. Drives the liquid feel.
    private(set) var bulge: CGFloat = 0

    let closedSize: CGSize
    let isRealNotch: Bool
    @ObservationIgnored var onStageChange: ((NotchStage) -> Void)?

    init(closedSize: CGSize, isRealNotch: Bool) {
        self.closedSize = closedSize
        self.isRealNotch = isRealNotch
    }

    /// Moves the frame. The content reveals itself once the new stage renders, so this only has
    /// to get the shape there.
    func setStage(_ new: NotchStage, motion: NotchMotion) {
        guard new != stage else { return }

        guard !motion.isInstant else {
            bulge = 0
            stage = new
            onStageChange?(new)
            return
        }

        // Closing deforms less; it is a retreat, not a pour.
        bulge = motion.bulgeAmount * (new == .closed ? 0.55 : 1)
        withAnimation(motion.size) { stage = new }
        if motion.bulgeAmount > 0 {
            withAnimation(motion.bulge?.delay(0.02)) { bulge = 0 }
        } else {
            bulge = 0
        }
        onStageChange?(new)
    }

    // MARK: - Sizing

    static let peekRowHeight: CGFloat = 27
    static let peekHeaderHeight: CGFloat = 19
    /// Beyond this the hover would cover half the screen; the rest live behind "show all".
    static let peekRowLimit = 7

    func peekSize(sessionCount: Int) -> CGSize {
        let rows = CGFloat(min(max(sessionCount, 1), Self.peekRowLimit))
        let overflow: CGFloat = sessionCount > Self.peekRowLimit ? 16 : 0
        let width: CGFloat = max(closedSize.width + 300, 470)
        let listHeight: CGFloat = rows * Self.peekRowHeight
        let chrome: CGFloat = closedSize.height + Self.peekHeaderHeight + 18
        return CGSize(width: width, height: chrome + listHeight + overflow)
    }

    var openSize: CGSize { CGSize(width: 700, height: 470) }

    func size(for stage: NotchStage, sessionCount: Int) -> CGSize {
        switch stage {
        case .closed: closedSize
        case .peek: peekSize(sessionCount: sessionCount)
        case .open: openSize
        }
    }
}

final class NotchPanel: NSPanel {
    init(contentRect: NSRect) {
        super.init(contentRect: contentRect,
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered,
                   defer: false)
        isFloatingPanel = true
        level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 8)
        collectionBehavior = [.fullScreenAuxiliary, .stationary, .canJoinAllSpaces, .ignoresCycle]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        isMovable = false
        isMovableByWindowBackground = false
        hidesOnDeactivate = false
        // Ambient state is not interactive, so the menu bar underneath stays clickable.
        ignoresMouseEvents = true
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

/// Owns one panel on one screen and drives its stage from pointer position.
@MainActor
final class NotchController {
    let displayID: CGDirectDisplayID
    private let panel: NotchPanel
    private let vm: NotchViewModel
    private let state: AppState
    private var screenFrame: CGRect

    init(screen: NSScreen, state: AppState) {
        displayID = screen.displayID
        screenFrame = screen.frame
        self.state = state
        // A few points taller than the hardware cutout, so the ambient sliver clears it.
        let notch = screen.notchSize
        let closed = screen.hasNotch ? CGSize(width: notch.width, height: notch.height + 3) : notch
        vm = NotchViewModel(closedSize: closed, isRealNotch: screen.hasNotch)

        // Extra height so the bottom edge can sag past the panel without being clipped.
        let windowSize = CGSize(width: min(vm.openSize.width + 40, screen.frame.width - 40),
                                height: vm.openSize.height + 30)
        panel = NotchPanel(contentRect: NotchGeometry.topCentered(size: windowSize, in: screen.frame))

        let hosting = NSHostingView(rootView: NotchRootView(vm: vm, state: state))
        hosting.autoresizingMask = [.width, .height]
        panel.contentView = hosting
        panel.orderFrontRegardless()

        vm.onStageChange = { [weak self] stage in
            guard let self else { return }
            // Only interactive while the pointer is provably over the content.
            panel.ignoresMouseEvents = (stage == .closed)
            log("stage=\(stage) content=\(vm.size(for: stage, sessionCount: state.activeSessions.count))")
        }
        log("panel up: notch=\(screen.hasNotch) closed=\(vm.closedSize) frame=\(panel.frame.integral)")
    }

    private func log(_ message: String) {
        print("[display \(displayID)] \(message)")
        fflush(stdout)
    }

    /// Rect the pointer must be inside for `stage` to hold, in global coordinates. The peek grows
    /// with the session list, so its target is recomputed rather than fixed.
    private func rect(for stage: NotchStage) -> CGRect {
        let size = vm.size(for: stage, sessionCount: state.activeSessions.count)
        return NotchGeometry.hoverTarget(NotchGeometry.topCentered(size: size, in: screenFrame))
    }

    func pointerMoved(to point: CGPoint) {
        switch vm.stage {
        case .closed:
            if rect(for: .closed).contains(point) { vm.setStage(.peek, motion: state.animation.motion) }
        case .peek:
            // While a menu is up the pointer wanders off; keep the panel open behind it.
            if !rect(for: .peek).contains(point), !state.menuIsOpen { vm.setStage(.closed, motion: state.animation.motion) }
        case .open:
            if !rect(for: .open).contains(point), !state.menuIsOpen { vm.setStage(.closed, motion: state.animation.motion) }
        }
    }

    func close() {
        panel.orderOut(nil)
    }
}
