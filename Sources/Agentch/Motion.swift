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
    var motion: NotchMotion {
        switch self {
        case .liquid:
            // The edge keeps moving after the size lands, which is what sells the pour.
            NotchMotion(size: .spring(response: 0.46, dampingFraction: 0.68),
                        bulge: .spring(response: 0.62, dampingFraction: 0.42),
                        bulgeAmount: 1,
                        content: .easeOut(duration: 0.2),
                        contentDelay: 0.15,
                        hiddenBlur: 5,
                        hiddenScaleX: 0.97,
                        hiddenScaleY: 0.97)

        case .snap:
            NotchMotion(size: .spring(response: 0.24, dampingFraction: 0.92),
                        content: .easeOut(duration: 0.1),
                        contentDelay: 0.03)

        case .unfold:
            // Height leads, content unrolls from the top edge behind it.
            NotchMotion(size: .timingCurve(0.2, 0.9, 0.2, 1, duration: 0.34),
                        content: .easeOut(duration: 0.24),
                        contentDelay: 0.1,
                        hiddenScaleY: 0.72,
                        hiddenOffsetY: -8)

        case .bounce:
            NotchMotion(size: .spring(response: 0.5, dampingFraction: 0.54),
                        content: .spring(response: 0.34, dampingFraction: 0.62),
                        contentDelay: 0.07,
                        hiddenScaleX: 0.88,
                        hiddenScaleY: 0.88)

        case .none:
            NotchMotion()
        }
    }
}
