import CoreGraphics

/// Screen maths for placing the notch/pill. Pure functions so they can be tested without a display.
public enum NotchGeometry {
    /// Rect anchored to the top centre of `screenFrame`, in global (bottom-left origin) coordinates.
    public static func topCentered(size: CGSize, in screenFrame: CGRect) -> CGRect {
        CGRect(x: screenFrame.midX - size.width / 2,
               y: screenFrame.maxY - size.height,
               width: size.width,
               height: size.height)
    }

    /// Hover target for `rect`: a little wider, and taller downwards only — there is no room above the screen edge.
    public static func hoverTarget(_ rect: CGRect, slop: CGFloat = 4) -> CGRect {
        CGRect(x: rect.minX - slop,
               y: rect.minY - slop,
               width: rect.width + slop * 2,
               height: rect.height + slop)
    }
}
