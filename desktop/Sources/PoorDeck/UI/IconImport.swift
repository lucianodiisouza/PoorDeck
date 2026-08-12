import AppKit
import UniformTypeIdentifiers

/// Helpers for turning a user-picked image file into the compact PNG data URL
/// the wire model stores in `DeckButton.customIcon`. Images are downscaled so
/// a 4K PNG doesn't bloat the layout (and any shared pack) — deck tiles never
/// need more than a couple hundred pixels.
enum IconImport {
    /// Present an open panel and return the chosen image as a PNG data URL,
    /// downscaled to fit `maxSize` on its longest edge. Returns nil if the
    /// user cancels or the file can't be read as an image.
    @MainActor
    static func chooseDataURL(maxSize: CGFloat = 256) -> String? {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.png, .jpeg, .heic, .tiff, .gif, .bmp, .image]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.prompt = "Use Image"
        guard panel.runModal() == .OK,
              let url = panel.url,
              let image = NSImage(contentsOf: url)
        else { return nil }
        return dataURL(from: image, maxSize: maxSize)
    }

    /// Encode an `NSImage` as a `data:image/png;base64,...` URL, downscaled so
    /// its longest edge is at most `maxSize` points. Never upscales.
    static func dataURL(from image: NSImage, maxSize: CGFloat) -> String? {
        let size = image.size
        guard size.width > 0, size.height > 0 else { return nil }
        let scale = min(1, maxSize / max(size.width, size.height))
        let target = NSSize(width: max(1, floor(size.width * scale)),
                            height: max(1, floor(size.height * scale)))

        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(target.width),
            pixelsHigh: Int(target.height),
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else { return nil }
        rep.size = target

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        image.draw(in: NSRect(origin: .zero, size: target),
                   from: NSRect(origin: .zero, size: size),
                   operation: .copy,
                   fraction: 1.0)
        NSGraphicsContext.restoreGraphicsState()

        guard let data = rep.representation(using: .png, properties: [:]) else { return nil }
        return "data:image/png;base64," + data.base64EncodedString()
    }
}
