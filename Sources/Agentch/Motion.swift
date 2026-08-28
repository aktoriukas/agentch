import SwiftUI
import AgentchCore

/// How the frame travels. This is the part the settings choose between; the content reveal is
/// the same whichever frame style is picked.
struct NotchMotion {
    var size: Animation?
    var bulge: Animation?
    /// 0 leaves the panel edges rigid; 1 is the full liquid deformation.
    var bulgeAmount: CGFloat = 0

    var isInstant: Bool { size == nil && bulgeAmount == 0 }
}

extension NotchAnimation {
    /// Deliberately small: short travel, near-critical damping. The frame should look precise,
    /// not springy.
    var motion: NotchMotion {
        switch self {
        case .liquid:
            // The edge lags the size change, by just enough to read as give rather than bounce.
            NotchMotion(size: .spring(response: 0.28, dampingFraction: 0.88),
                        bulge: .spring(response: 0.34, dampingFraction: 0.74),
                        bulgeAmount: 0.42)
        case .snap:
            NotchMotion(size: .spring(response: 0.17, dampingFraction: 0.96))
        case .unfold:
            NotchMotion(size: .timingCurve(0.25, 0.9, 0.25, 1, duration: 0.24))
        case .bounce:
            // The springiest of the set, which still means a single small overshoot.
            NotchMotion(size: .spring(response: 0.3, dampingFraction: 0.72))
        case .none:
            NotchMotion()
        }
    }
}

/// Content settles in behind the frame, one line after another. Shared by every frame style, and
/// skipped entirely when animation is off.
enum ContentReveal {
    /// Long enough for the frame to be underway before the first line lands.
    static let leadIn = 0.05
    /// Gap between consecutive lines. Small: the stagger should be sensed, not counted.
    static let step = 0.022
    static let duration = 0.15
    static let rise: CGFloat = -4
    /// Rows past this share the last delay, so a long list reveals no slower than a short one.
    static let lastStaggeredRow = 8

    static func animation(row: Int) -> Animation {
        let delay = leadIn + Double(min(row, lastStaggeredRow)) * step
        return .easeOut(duration: duration).delay(delay)
    }
}

/// Fades a line in, offset by its position so the panel fills top to bottom.
struct StaggeredLine: ViewModifier {
    var row: Int
    var enabled: Bool
    @State private var shown = false

    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .offset(y: shown ? 0 : ContentReveal.rise)
            .onAppear {
                // Driven from onAppear rather than a shared flag: the flag would be set and
                // cleared inside one runloop and never render its "hidden" frame.
                guard enabled else {
                    shown = true
                    return
                }
                withAnimation(ContentReveal.animation(row: row)) { shown = true }
            }
    }
}

extension View {
    func staggered(row: Int, enabled: Bool) -> some View {
        modifier(StaggeredLine(row: row, enabled: enabled))
    }
}
