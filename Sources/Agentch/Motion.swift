import SwiftUI
import AgentchCore

/// The curves behind each animation choice: how the shape travels, whether its edge deforms,
/// and how the content arrives once the shape has.
struct NotchMotion {
    var size: Animation?
    var bulge: Animation?
    /// 0 leaves the panel edges rigid; 1 is the full liquid deformation.
    var bulgeAmount: CGFloat = 0
    var content: Animation?
    var contentDelay: Double = 0

    // What the content looks like before it arrives.
    var hiddenOpacity: Double = 0
    var hiddenBlur: CGFloat = 0
    var hiddenScaleX: CGFloat = 1
    var hiddenScaleY: CGFloat = 1
    var hiddenOffsetY: CGFloat = 0

    var isInstant: Bool { size == nil && content == nil && bulgeAmount == 0 }
}

extension NotchAnimation {
    /// Deliberately small: short travel, near-critical damping, displacements measured in a few
    /// points. The panel should look precise, not springy.
    var motion: NotchMotion {
        switch self {
        case .liquid:
            // The edge still lags the size change, just by much less than it takes to notice as bounce.
            NotchMotion(size: .spring(response: 0.28, dampingFraction: 0.88),
                        bulge: .spring(response: 0.34, dampingFraction: 0.74),
                        bulgeAmount: 0.42,
                        content: .easeOut(duration: 0.13),
                        contentDelay: 0.06,
                        hiddenBlur: 2.5,
                        hiddenScaleX: 0.994,
                        hiddenScaleY: 0.994)

        case .snap:
            NotchMotion(size: .spring(response: 0.17, dampingFraction: 0.96),
                        content: .easeOut(duration: 0.08),
                        contentDelay: 0.015)

        case .unfold:
            NotchMotion(size: .timingCurve(0.25, 0.9, 0.25, 1, duration: 0.24),
                        content: .easeOut(duration: 0.15),
                        contentDelay: 0.05,
                        hiddenScaleY: 0.94,
                        hiddenOffsetY: -3)

        case .bounce:
            // The springiest of the set, which still means a single small overshoot.
            NotchMotion(size: .spring(response: 0.3, dampingFraction: 0.72),
                        content: .spring(response: 0.24, dampingFraction: 0.82),
                        contentDelay: 0.035,
                        hiddenScaleX: 0.97,
                        hiddenScaleY: 0.97)

        case .none:
            NotchMotion()
        }
    }
}
