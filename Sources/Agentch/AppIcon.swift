import SwiftUI

/// The app icon, drawn rather than drawn-in-an-editor: `--icon` renders it to an iconset and
/// `scripts/build-app.sh` turns that into the bundle's .icns, so the mark is versioned as code.
///
/// Laid out in a 1024 canvas: macOS supplies no squircle of its own for a custom icon, so the
/// artwork carries it, inset the standard 100 on every side.
struct AppIcon: View {
    static let canvas: CGFloat = 1024

    private let inset: CGFloat = 100
    private var side: CGFloat { Self.canvas - inset * 2 }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: side * 0.2237, style: .continuous)
                .fill(LinearGradient(colors: [Color(hex: "#33333A"), Color(hex: "#0A0A0C")],
                                     startPoint: .top, endPoint: .bottom))
                .frame(width: side, height: side)

            ring
            notch
        }
        .frame(width: Self.canvas, height: Self.canvas)
        // The two are one mark, not a stack of two: the notch is subtracted from the ring.
        .compositingGroup()
    }

    /// The limit meter, most of the way round.
    private var ring: some View {
        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.13), lineWidth: 54)
            Circle()
                .trim(from: 0, to: 0.72)
                .stroke(Color(hex: "#E8913A"),
                        style: StrokeStyle(lineWidth: 54, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .frame(width: 400, height: 400)
        .offset(y: 78)
    }

    /// The cutout the whole app hangs from, biting into the top of the ring.
    private var notch: some View {
        VStack(spacing: 0) {
            NotchShape(cornerRadius: 56)
                .fill(.black)
                .frame(width: 268, height: 190)
            Spacer(minLength: 0)
        }
        .frame(width: side, height: side)
    }
}
