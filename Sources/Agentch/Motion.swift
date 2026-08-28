import SwiftUI
import AgentchCore

/// How the frame travels. This is the part the settings choose between; the content reveal is
/// the same whichever frame style is picked.
struct NotchMotion {
    var size: Animation?
    var bulge: Animation?
    /// 0 leaves the panel edges rigid; 1 is the full liquid deformation.
    var bulgeAmount: CGFloat = 0
    /// Roughly how long the frame takes to arrive. Content waits this long before it starts,
    /// so nothing appears while the panel is still moving.
    var settle: Double = 0

    var isInstant: Bool { size == nil && bulgeAmount == 0 }

    var reveal: RevealSpec { RevealSpec(enabled: !isInstant, leadIn: settle) }
}

/// When and whether the content lines cascade in.
struct RevealSpec {
    var enabled: Bool
    var leadIn: Double

    static let off = RevealSpec(enabled: false, leadIn: 0)
}

extension NotchAnimation {
    /// Deliberately small: short travel, near-critical damping. The frame should look precise,
    /// not springy.
    var motion: NotchMotion {
        switch self {
        case .liquid:
            // The edge lags the size change, by just enough to read as give rather than bounce.
            // Waits on the size, not the edge: the bulge is still easing out underneath.
            NotchMotion(size: .spring(response: 0.28, dampingFraction: 0.88),
                        bulge: .spring(response: 0.34, dampingFraction: 0.74),
                        bulgeAmount: 0.42,
                        settle: 0.3)
        case .snap:
            NotchMotion(size: .spring(response: 0.17, dampingFraction: 0.96), settle: 0.19)
        case .unfold:
            NotchMotion(size: .timingCurve(0.25, 0.9, 0.25, 1, duration: 0.24), settle: 0.24)
        case .bounce:
            // The springiest of the set, which still means a single small overshoot.
            // Longer than the others: the overshoot has to come back before content lands.
            NotchMotion(size: .spring(response: 0.3, dampingFraction: 0.72), settle: 0.38)
        case .none:
            NotchMotion()
        }
    }
}

/// Content settles in behind the frame, one line after another. Shared by every frame style, and
/// skipped entirely when animation is off.
enum ContentReveal {
    /// Gap between consecutive lines. Small: the stagger should be sensed, not counted.
    static let step = 0.02
    static let duration = 0.13
    static let rise: CGFloat = -4
    /// Rows past this share the last delay, so a long list reveals no slower than a short one.
    /// The cascade is already waiting on the frame, so it has to stay brief.
    static let lastStaggeredRow = 6

    static func animation(row: Int, leadIn: Double) -> Animation {
        let delay = leadIn + Double(min(row, lastStaggeredRow)) * step
        return .easeOut(duration: duration).delay(delay)
    }
}

/// Fades a line in, offset by its position so the panel fills top to bottom.
struct StaggeredLine: ViewModifier {
    var row: Int
    var spec: RevealSpec
    @State private var shown = false

    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .offset(y: shown ? 0 : ContentReveal.rise)
            .onAppear {
                // Driven from onAppear rather than a shared flag: the flag would be set and
                // cleared inside one runloop and never render its "hidden" frame.
                guard spec.enabled else {
                    shown = true
                    return
                }
                withAnimation(ContentReveal.animation(row: row, leadIn: spec.leadIn)) { shown = true }
            }
    }
}

extension View {
    func staggered(row: Int, spec: RevealSpec) -> some View {
        modifier(StaggeredLine(row: row, spec: spec))
    }
}
