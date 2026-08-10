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
    /// When true, the preview mirrors the orientation the most recent
    /// client reported, instead of the local `portrait` toggle. This
    /// is what the user wants when they're actively testing on a
    /// real phone: rotate the phone, the preview rotates to match.
    @Binding var followDevice: Bool
    @EnvironmentObject private var server: Server
    let selectedButtonId: String?
    let onSelect: (String) -> Void

    /// Effective orientation the preview should render. The page's
    /// `orientationLock` is a runtime constraint for the *real client*
    /// (it tells the phone to hold this orientation); it doesn't pin
    /// the editor preview, so the user can still see how the page
    /// looks in both orientations before deciding to lock it. The
    /// "Locked to X" badge in the controls bar makes the lock visible.
    private var effectivePortrait: Bool {
        if followDevice {
            return server.lastDeviceOrientationIsPortrait
        }
        return portrait
    }

    /// Size of the preview frame in points, after clamping to the
    /// available space. The outer canvas pads to half this on the
    /// short axis so the device sits centered with breathing room.
    @State private var maxHeight: CGFloat = 600

    var body: some View {
        VStack(spacing: 16) {
            controls
            deviceFrame
                .frame(maxWidth: .infinity, maxHeight: .infinity)
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

            // Manual orientation toggle for the preview. The page's
            // orientationLock doesn't disable this — the lock is a
            // *client* runtime constraint, the editor still wants to
            // see what the page looks like in both orientations.
            Button {
                withAnimation(.easeOut(duration: 0.2)) {
                    portrait.toggle()
                }
            } label: {
                Image(systemName: portrait ? "rectangle.landscape" : "rectangle.portrait")
                    .font(.system(size: 16, weight: .medium))
            }
            .buttonStyle(.borderless)
            .disabled(followDevice)
            .help(followDevice
                  ? "Follow device is on — turn it off to use the manual toggle"
                  : (portrait ? "Switch to landscape" : "Switch to portrait"))

            Toggle(isOn: $followDevice) {
                Label("Follow", systemImage: followDevice
                      ? "iphone.radiowaves.left.and.right"
                      : "iphone")
            }
            .toggleStyle(.button)
            .controlSize(.small)
            .help("Mirror the orientation of the most recently connected device")

            if let lock = page.orientationLock {
                // Show the lock as a badge so the user remembers the
                // page is locked even though the preview can render
                // either way. The page-level lock field above is the
                // source of truth — this is just a reminder that
                // what they see in the preview may differ from what
                // the client will render.
                Label("Locked to \(lock.rawValue.capitalized)", systemImage: "lock.fill")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color.accentColor)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        Capsule().fill(Color.accentColor.opacity(0.15))
                    )
                    .help("This page is locked to \(lock.rawValue) on the client. The preview still shows the orientation above.")
            }

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
            let isPortrait = effectivePortrait
            let target = isPortrait ? portraitAspect : landscapeAspect
            let available = geo.size
            let size = sizeThatFits(target: target, in: available)

            ZStack {
                // Drop shadow + body
                RoundedRectangle(cornerRadius: isPortrait ? 36 : 24, style: .continuous)
                    .fill(Color.black)
                    .shadow(color: .black.opacity(0.45), radius: 24, x: 0, y: 12)
                    .overlay(
                        RoundedRectangle(cornerRadius: isPortrait ? 36 : 24, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
                    )

                // Bezel (the rim between the device body and the screen)
                RoundedRectangle(cornerRadius: isPortrait ? 32 : 20, style: .continuous)
                    .fill(Color(red: 0.06, green: 0.07, blue: 0.09))
                    .padding(isPortrait ? 6 : 5)

                // Screen content — clipped to the device body so the grid
                // can't escape the bezel.
                screen(size: size, device: device)
                    .padding(isPortrait ? 10 : 8)
            }
            .frame(width: size.width, height: size.height)
        }
    }

    private func screen(size: CGSize, device: DeviceFamily) -> some View {
        let isPortrait = effectivePortrait
        let screenWidth = size.width - (isPortrait ? 24 : 20)
        let screenHeight = size.height - (isPortrait ? 24 : 20)
        // Reserve space at the top (status bar + page chrome) and the
        // bottom (page dots + home indicator) so the grid gets a known
        // height to fit itself into.
        let chromeTop: CGFloat = device == .phone && isPortrait ? 54 : 36
        let chromeBottom: CGFloat = 28
        let gridArea = max(0, screenHeight - chromeTop - chromeBottom)

        return VStack(spacing: 0) {
            statusBar(screenWidth: screenWidth, screenHeight: screenHeight)

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

            // Home indicator (iPhone only — iPads have a real home
            // button visually, not a gesture pill).
            if device == .phone {
                Capsule()
                    .fill(Color.white.opacity(0.6))
                    .frame(width: max(40, screenWidth * 0.3), height: 4)
                    .padding(.bottom, max(2, screenHeight * 0.008))
            }
        }
        .frame(width: screenWidth, height: screenHeight)
        .clipped()
    }

    /// iOS-style status bar. Phones get a Dynamic Island (pill) that
    /// shifts left in landscape; iPads get a small camera dot at the
    /// top center. Time on the left, signal/wifi/battery on the
    /// right — same arrangement Safari/Finder use in the iPad
    /// status bar screenshots.
    @ViewBuilder
    private func statusBar(screenWidth: CGFloat, screenHeight: CGFloat) -> some View {
        let isPortrait = effectivePortrait
        let phonePortrait = device == .phone && isPortrait
        let statusHeight: CGFloat = phonePortrait ? 54 : 28
        let fontSize: CGFloat = max(8, screenWidth * 0.022)

        ZStack(alignment: .top) {
            // Time on the leading side, status icons on the trailing
            // side — the same left/right arrangement as the real
            // iOS status bar. The Dynamic Island / camera sits on
            // top in the ZStack so the time and icons can flow
            // around it.
            HStack(alignment: .firstTextBaseline) {
                Text("9:41")
                    .font(.system(size: fontSize, weight: .semibold))
                    .foregroundStyle(Color.white)
                Spacer()
                HStack(spacing: 4) {
                    Image(systemName: "wifi")
                    Image(systemName: "battery.100")
                }
                .font(.system(size: fontSize))
                .foregroundStyle(Color.white)
            }
            .padding(.horizontal, max(20, screenWidth * 0.06))
            .frame(maxHeight: .infinity, alignment: phonePortrait ? .center : .center)
            .padding(.top, phonePortrait ? 16 : 8)

            // Camera / notch on the centered top edge. iPhone
            // portrait = Dynamic Island pill in the middle; iPhone
            // landscape = pill on the left; iPad = small camera dot.
            if device == .phone {
                Capsule()
                    .fill(Color.black)
                    .frame(
                        width: phonePortrait ? screenWidth * 0.32 : screenWidth * 0.18,
                        height: phonePortrait ? 28 : 8
                    )
                    .padding(.top, phonePortrait ? 8 : 4)
            } else {
                Circle()
                    .fill(Color.black)
                    .frame(width: 6, height: 6)
                    .padding(.top, 4)
            }
        }
        .frame(height: statusHeight)
    }

    @ViewBuilder
    private func grid(of screenWidth: CGFloat, height screenHeight: CGFloat) -> some View {
        // Mirrors the client's CSS: padding 14 around the grid, 12px
        // gap between cells, square cells capped to fit the rows in
        // the available height (with a label at the bottom).
        let cols = max(1, page.columns)
        let rows = max(1, Int(ceil(Double(page.buttons.count) / Double(cols))))
        let gap: CGFloat = 12
        let availableWidth = screenWidth - 28
        let cellWidth = (availableWidth - CGFloat(cols - 1) * gap) / CGFloat(cols)
        // Height budget = screen height - status bar (24) - chrome
        // header (40) - dots (16) - home indicator (30) - padding (12).
        let heightBudget = max(40, screenHeight - 24 - 40 - 16 - 30 - 12)
        let cellFromWidth = cellWidth
        let cellFromHeight = (heightBudget - CGFloat(rows - 1) * gap) / CGFloat(rows)
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
            // Same proportions the client uses: 46% icon, 12px label,
            // radius from the theme. The .icon fits inside an inner
            // padding so the cell reads like the real one on the phone.
            VStack(spacing: 6) {
                ZStack {
                    RoundedRectangle(cornerRadius: side * 0.15)
                        .fill(Color(red: 0.11, green: 0.12, blue: 0.15))
                    if let icon = button.icon, let nsImage = Self.imageFromDataURL(icon) {
                        Image(nsImage: nsImage)
                            .resizable()
                            .interpolation(.high)
                            .aspectRatio(contentMode: .fit)
                            .padding(side * 0.27)
                    } else {
                        Image(systemName: button.symbol ?? "questionmark.square")
                            .font(.system(size: side * 0.46))
                            .foregroundStyle(Color.white)
                    }
                }
                .frame(width: side, height: side)
                .overlay(
                    RoundedRectangle(cornerRadius: side * 0.15)
                        .strokeBorder(isSelected ? Color.accentColor : Color.clear, lineWidth: 2)
                )
                Text(button.label)
                    .font(.system(size: 12))
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
