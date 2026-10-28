import AppKit
import SwiftUI

/// A user-supplied image in place of an account's tag. Stored as a small PNG
/// in the account metadata; drawn at menu bar height, so 2x that is enough.
enum AccountIcon {
    static let pointHeight: CGFloat = 16
    private static let storedHeight: CGFloat = pointHeight * 2

    /// Asks for an image file and returns it scaled down, or nil if cancelled
    /// or unreadable.
    @MainActor
    static func pick(message: String = "Choose an image for this account's menu bar icon") -> Data? {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        panel.message = message
        guard panel.runModal() == .OK, let url = panel.url, let image = NSImage(contentsOf: url) else { return nil }
        return png(image)
    }

    /// Scaled to `storedHeight` keeping the aspect ratio, so an arbitrary photo
    /// stays a few KB in user defaults.
    static func png(_ image: NSImage) -> Data? {
        guard image.size.height > 0 else { return nil }
        let scale = storedHeight / image.size.height
        let size = NSSize(width: (image.size.width * scale).rounded(), height: storedHeight)
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: Int(size.width), pixelsHigh: Int(size.height),
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        ) else { return nil }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        image.draw(in: NSRect(origin: .zero, size: size), from: .zero, operation: .copy, fraction: 1)
        NSGraphicsContext.restoreGraphicsState()
        return rep.representation(using: .png, properties: [:])
    }
}

/// The account's icon if it has one, else its tag, at the given text weight.
struct AccountLabel: View {
    let account: Account
    var height: CGFloat = AccountIcon.pointHeight

    var body: some View {
        if let data = account.icon, let image = NSImage(data: data) {
            Image(nsImage: image).resizable().scaledToFit().frame(height: height)
        } else {
            Text(account.tag).fontWeight(.semibold)
        }
    }
}
