import Foundation
import CoreGraphics
import CVirtualDisplay

/// Extend: a second screen for the glasses, 1920x1080 like the glasses themselves, which macOS
/// treats as a real monitor. It lasts as long as this object: dropping it unplugs the screen, and
/// macOS moves its windows back as it would for a cable pulled out.
final class VirtualDisplay {
    private let display: CGVirtualDisplay
    var id: CGDirectDisplayID { display.displayID }

    init?(width: Int = 1920, height: Int = 1080) {
        let descriptor = CGVirtualDisplayDescriptor()
        descriptor.queue = .main
        descriptor.name = "HudCast"
        descriptor.maxPixelsWide = UInt32(width)
        descriptor.maxPixelsHigh = UInt32(height)
        // A 24-inch 16:9 screen, so macOS picks a plain 1x scale: one point, one glasses pixel.
        descriptor.sizeInMillimeters = CGSize(width: 531, height: 299)
        descriptor.vendorID = 0x4855   // "HU"
        descriptor.productID = 0x4443  // "DC"
        descriptor.serialNum = 1
        guard let display = CGVirtualDisplay(descriptor: descriptor) else { return nil }
        let settings = CGVirtualDisplaySettings()
        settings.hiDPI = 0
        settings.modes = [CGVirtualDisplayMode(width: UInt(width), height: UInt(height), refreshRate: 60)]
        guard display.apply(settings) else { return nil }
        self.display = display
    }
}

extension VirtualDisplay {
    /// Puts the glasses' screen directly above the main one, centred, so the pointer goes up to
    /// reach it, the way the glasses sit above what you are looking at. macOS places a new screen
    /// to the right by default, and may remember that; this is set every time it is plugged in.
    func placeAboveMain() {
        let main = CGDisplayBounds(CGMainDisplayID())
        let own = CGDisplayBounds(id)
        guard own.width > 0, main.width > 0 else { return }
        var config: CGDisplayConfigRef?
        guard CGBeginDisplayConfiguration(&config) == .success, let config else { return }
        let x = Int32((main.midX - own.width / 2).rounded())
        let y = Int32((main.minY - own.height).rounded())
        CGConfigureDisplayOrigin(config, id, x, y)
        if CGCompleteDisplayConfiguration(config, .forSession) != .success {
            CGCancelDisplayConfiguration(config)
        }
    }
}
