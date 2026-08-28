import AppKit
import SwiftUI
import AgentchCore

/// Renders each stage offscreen to a PNG so the UI can be reviewed without Xcode previews
/// (and without granting screen-recording access just to look at a window).
/// Usage: `swift run Agentch --render` → /tmp/agentch-{closed-pill,closed-notch,peek,panel}.png
@MainActor
enum DevRender {
    static func writeStagePNGs() {
        let state = AppState()
        state.loadStubData()

        let pill = NotchViewModel(closedSize: CGSize(width: 190, height: 24), isRealNotch: false)
        let notch = NotchViewModel(closedSize: CGSize(width: 220, height: 41), isRealNotch: true)

        write(ClosedView(vm: pill, state: state), size: pill.closedSize, name: "closed-pill")
        write(ClosedView(vm: notch, state: state), size: notch.closedSize, name: "closed-notch")
        write(PeekView(state: state, topInset: pill.closedSize.height), size: pill.peekSize, name: "peek")
        // Worst case for the top inset: content must clear the 38pt hardware cutout.
        write(PeekView(state: state, topInset: notch.closedSize.height), size: notch.peekSize, name: "peek-notch")
        write(PanelView(state: state), size: pill.openSize, name: "panel")

        // ScrollView renders blank under ImageRenderer, so check the rows on their own.
        let rows = VStack(spacing: 0) {
            ForEach(state.activeSessions) { session in
                SessionRow(session: session, parity: state.parity)
                Divider().overlay(.white.opacity(0.06))
            }
        }
        .padding(.horizontal, 16)
        write(rows, size: CGSize(width: 680, height: 220), name: "rows")
    }

    private static func write(_ view: some View, size: CGSize, name: String) {
        let framed = view
            .frame(width: size.width, height: size.height)
            .background(NotchShape().fill(.black))
            .clipShape(NotchShape())
            // The notch is black-on-black; a grey mat shows where its edges actually fall.
            .padding(12)
            .background(Color(white: 0.28))
            .environment(\.colorScheme, .dark)

        let renderer = ImageRenderer(content: framed)
        renderer.scale = 2
        guard let image = renderer.nsImage,
              let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let png = bitmap.representation(using: .png, properties: [:]) else {
            print("render failed: \(name)")
            return
        }
        let url = URL(fileURLWithPath: "/tmp/agentch-\(name).png")
        try? png.write(to: url)
        print("wrote \(url.path)")
    }
}
