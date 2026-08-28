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
    var stage: NotchStage = .closed {
        didSet {
            guard stage != oldValue else { return }
            onStageChange?(stage)
        }
    }

    let closedSize: CGSize
    let isRealNotch: Bool
    @ObservationIgnored var onStageChange: ((NotchStage) -> Void)?

    init(closedSize: CGSize, isRealNotch: Bool) {
        self.closedSize = closedSize
        self.isRealNotch = isRealNotch
    }

    /// Height follows the closed height: content sits below the cutout, so a taller notch needs a taller peek.
    var peekSize: CGSize { CGSize(width: max(closedSize.width + 280, 440), height: closedSize.height + 116) }
    var openSize: CGSize { CGSize(width: 680, height: 460) }

    func size(for stage: NotchStage) -> CGSize {
        switch stage {
        case .closed: closedSize
        case .peek: peekSize
        case .open: openSize
        }
    }

    var currentSize: CGSize { size(for: stage) }
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
    private var screenFrame: CGRect

    init(screen: NSScreen, state: AppState) {
        displayID = screen.displayID
        screenFrame = screen.frame
        // A few points taller than the hardware cutout, so the ambient sliver clears it.
        let notch = screen.notchSize
        let closed = screen.hasNotch ? CGSize(width: notch.width, height: notch.height + 3) : notch
        vm = NotchViewModel(closedSize: closed, isRealNotch: screen.hasNotch)

        let windowSize = CGSize(width: min(vm.openSize.width, screen.frame.width - 40),
                                height: vm.openSize.height)
        panel = NotchPanel(contentRect: NotchGeometry.topCentered(size: windowSize, in: screen.frame))

        let hosting = NSHostingView(rootView: NotchRootView(vm: vm, state: state))
        hosting.autoresizingMask = [.width, .height]
        panel.contentView = hosting
        panel.orderFrontRegardless()

        vm.onStageChange = { [weak self] stage in
            guard let self else { return }
            // Only interactive while the pointer is provably over the content.
            panel.ignoresMouseEvents = (stage == .closed)
            log("stage=\(stage) frame=\(panel.frame.integral) content=\(vm.size(for: stage))")
        }
        log("panel up: notch=\(screen.hasNotch) closed=\(vm.closedSize) frame=\(panel.frame.integral)")
    }

    private func log(_ message: String) {
        print("[display \(displayID)] \(message)")
        fflush(stdout)
    }

    /// Rect the pointer must be inside for `stage` to hold, in global coordinates.
    private func rect(for stage: NotchStage) -> CGRect {
        NotchGeometry.hoverTarget(NotchGeometry.topCentered(size: vm.size(for: stage), in: screenFrame))
    }

    func pointerMoved(to point: CGPoint) {
        switch vm.stage {
        case .closed:
            if rect(for: .closed).contains(point) { vm.stage = .peek }
        case .peek:
            if !rect(for: .peek).contains(point) { vm.stage = .closed }
        case .open:
            if !rect(for: .open).contains(point) { vm.stage = .closed }
        }
    }

    func close() {
        panel.orderOut(nil)
    }
}
