import SwiftUI

/// Mockup of the client device, used in the editor's canvas pane. Shows
/// a page's buttons as they would appear on the real client, framed by
/// a device chrome (status bar at the top, home indicator at the
/// bottom). Supports Phone and Tablet in both orientations so the
/// editor can preview how the layout will look on the user's device.
struct DevicePreview: View {
    enum DeviceFamily: String, CaseIterable, Identifiable {
        case phone = "Phone"
        case pad = "Tablet"
        var id: String { rawValue }
        var icon: String {
            switch self {
            case .phone: return "iphone"
            case .pad: return "ipad"
            }
        }
        /// Real-world device aspect ratio, used to size the preview frame
        /// so the buttons inside end up at roughly their physical size.
        var aspect: CGSize {
            switch self {
            case .phone: return CGSize(width: 393, height: 852)   // iPhone 15
            case .pad:   return CGSize(width: 820, height: 1180)  // iPad Air 11"
            }
        }
    }

    let page: Page
    @Binding var device: DeviceFamily
    @Binding var portrait: Bool
    let selectedButtonId: String?
    let onSelect: (String) -> Void

    /// Size of the preview frame in points, after clamping to the
    /// available space. The outer canvas pads to half this on the
    /// short axis so the device sits centered with breathing room.
    @State private var maxHeight: CGFloat = 600

    var body: some View {
        VStack(spacing: 16) {
            controls
            deviceFrame
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var controls: some View {
        HStack(spacing: 12) {
            Picker("Device", selection: $device) {
                ForEach(DeviceFamily.allCases) { d in
                    Label(d.rawValue, systemImage: d.icon).tag(d)
                }
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 220)

            Button {
                withAnimation(.easeOut(duration: 0.2)) {
                    portrait.toggle()
                }
            } label: {
                Image(systemName: portrait ? "rectangle.landscape" : "rectangle.portrait")
                    .font(.system(size: 16, weight: .medium))
            }
            .buttonStyle(.borderless)
            .help(portrait ? "Switch to landscape" : "Switch to portrait")

            Spacer()
        }
        .controlSize(.small)
    }

    /// The chrome'd device frame. Sizes itself to the largest
    /// (frame.width, frame.height) that fits within the available space
    /// while preserving the device's aspect ratio.
    private var deviceFrame: some View {
        GeometryReader { geo in
            let aspect = device.aspect
            let portraitAspect = aspect.height / aspect.width
            let landscapeAspect = aspect.width / aspect.height
            let target = portrait ? portraitAspect : landscapeAspect
            let available = geo.size
            let size = sizeThatFits(target: target, in: available)

            ZStack {
                // Drop shadow + body
                RoundedRectangle(cornerRadius: portrait ? 36 : 24, style: .continuous)
                    .fill(Color.black)
                    .shadow(color: .black.opacity(0.45), radius: 24, x: 0, y: 12)
                    .overlay(
                        RoundedRectangle(cornerRadius: portrait ? 36 : 24, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
                    )

                // Bezel (the rim between the device body and the screen)
                RoundedRectangle(cornerRadius: portrait ? 32 : 20, style: .continuous)
                    .fill(Color(red: 0.06, green: 0.07, blue: 0.09))
                    .padding(portrait ? 6 : 5)

                // Screen content — clipped to the device body so the grid
                // can't escape the bezel.
                screen(size: size)
                    .padding(portrait ? 10 : 8)
            }
            .frame(width: size.width, height: size.height)
        }
    }

    private func screen(size: CGSize) -> some View {
        let screenWidth = size.width - (portrait ? 24 : 20)
        let screenHeight = size.height - (portrait ? 24 : 20)
        // Reserve space at the top (status bar + page chrome) and the
        // bottom (page dots + home indicator) so the grid gets a known
        // height to fit itself into.
        let chromeTop: CGFloat = 36
        let chromeBottom: CGFloat = 28
        let gridArea = max(0, screenHeight - chromeTop - chromeBottom)

        return VStack(spacing: 0) {
            // Fake status bar
            HStack {
                Text("9:41")
                    .font(.system(size: max(8, screenWidth * 0.025), weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.85))
                Spacer()
                HStack(spacing: 4) {
                    Image(systemName: "wifi")
                    Image(systemName: "battery.100")
                }
                .font(.system(size: max(8, screenWidth * 0.025)))
                .foregroundStyle(Color.white.opacity(0.85))
            }
            .padding(.horizontal, max(8, screenWidth * 0.04))
            .padding(.top, max(2, screenHeight * 0.008))
            .frame(height: 14)

            // Page chrome
            HStack {
                Circle().fill(Color.green).frame(width: 5, height: 5)
                Text(page.name)
                    .font(.system(size: max(11, screenWidth * 0.034), weight: .semibold))
                    .foregroundStyle(Color.white)
                Spacer()
                Text("connected")
                    .font(.system(size: max(9, screenWidth * 0.026)))
                    .foregroundStyle(Color.white.opacity(0.5))
            }
            .padding(.horizontal, max(8, screenWidth * 0.04))
            .frame(height: 22)

            // The actual grid — sized to the remaining height so its rows
            // fit the available area without overflowing the device.
            grid(of: screenWidth, height: gridArea)
                .padding(.horizontal, max(6, screenWidth * 0.025))
                .padding(.top, max(4, screenHeight * 0.012))
                .frame(height: gridArea, alignment: .top)

            Spacer(minLength: 0)

            // Page dots
            HStack(spacing: 4) {
                ForEach(0..<max(1, 1), id: \.self) { _ in
                    Circle()
                        .fill(Color.white.opacity(0.85))
                        .frame(width: 4, height: 4)
                }
            }
            .frame(height: 8)

            // Home indicator
            Capsule()
                .fill(Color.white.opacity(0.6))
                .frame(width: max(40, screenWidth * 0.3), height: 4)
                .padding(.bottom, max(2, screenHeight * 0.008))
        }
        .frame(width: screenWidth, height: screenHeight)
    }

    @ViewBuilder
    private func grid(of screenWidth: CGFloat, height screenHeight: CGFloat) -> some View {
        let cols = max(1, page.columns)
        let rows = max(1, Int(ceil(Double(page.buttons.count) / Double(cols))))
        let gap: CGFloat = max(4, screenWidth * 0.014)
        let availableWidth = screenWidth * 0.95
        let cellWidth = (availableWidth - CGFloat(cols - 1) * gap) / CGFloat(cols)
        // Each cell is square; cap it so all rows fit in the available
        // area. The label below the icon takes ~12% of the cell side.
        let cellFromWidth = cellWidth
        let cellFromHeight = (screenHeight - CGFloat(rows - 1) * gap) / CGFloat(rows) * 0.88
        let cellSide = min(cellFromWidth, cellFromHeight)

        LazyVGrid(columns: Array(repeating: GridItem(.fixed(cellWidth), spacing: gap), count: cols),
                  spacing: gap) {
            ForEach(page.buttons) { button in
                previewCell(for: button, side: cellSide)
            }
        }
    }

    private func previewCell(for button: DeckButton, side: CGFloat) -> some View {
        let isSelected = button.id == selectedButtonId
        return Button {
            onSelect(button.id)
        } label: {
            VStack(spacing: 4) {
                ZStack {
                    RoundedRectangle(cornerRadius: side * 0.18)
                        .fill(Color(red: 0.11, green: 0.12, blue: 0.15))
                    if let icon = button.icon, let nsImage = Self.imageFromDataURL(icon) {
                        Image(nsImage: nsImage)
                            .resizable()
                            .interpolation(.high)
                            .aspectRatio(contentMode: .fit)
                            .padding(side * 0.18)
                    } else {
                        Image(systemName: button.symbol ?? "questionmark.square")
                            .font(.system(size: side * 0.35))
                            .foregroundStyle(Color.white)
                    }
                }
                .aspectRatio(1, contentMode: .fit)
                .overlay(
                    RoundedRectangle(cornerRadius: side * 0.18)
                        .strokeBorder(isSelected ? Color.accentColor : Color.clear, lineWidth: 2)
                )
                Text(button.label)
                    .font(.system(size: max(8, side * 0.10)))
                    .foregroundStyle(.white.opacity(0.85))
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
        }
        .buttonStyle(.plain)
    }

    /// Largest size that fits inside `available` while preserving the
    /// device's aspect ratio.
    private func sizeThatFits(target aspect: CGFloat, in available: CGSize) -> CGSize {
        let wByH = available.width
        let hByW = available.height
        if wByH / hByW > aspect {
            return CGSize(width: hByW * aspect, height: hByW)
        } else {
            return CGSize(width: wByH, height: wByH / aspect)
        }
    }

    private static func imageFromDataURL_(_ s: String) -> NSImage? {
        guard let comma = s.firstIndex(of: ","),
              let data = Data(base64Encoded: String(s[s.index(after: comma)...]))
        else { return nil }
        return NSImage(data: data)
    }

    /// Decode a `data:image/png;base64,...` URL into an NSImage. Public
    /// so the legacy grid view in `LayoutEditorView` can reuse it.
    static func imageFromDataURL(_ s: String) -> NSImage? { imageFromDataURL_(s) }
}
