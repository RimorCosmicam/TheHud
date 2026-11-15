#if canImport(UIKit)
import SwiftUI
import UIKit
import AVFoundation

/// Hosts the desktop link's display layer. The layer decodes and paces the frames itself; this
/// view only keeps it sized to the panel. Re-hosting it (the glasses scene coming back) moves
/// the same layer, so the picture carries on.
public struct DesktopVideoView: UIViewRepresentable {
    public let layer: AVSampleBufferDisplayLayer

    public init(layer: AVSampleBufferDisplayLayer) {
        self.layer = layer
    }

    public func makeUIView(context: Context) -> LayerHost {
        let view = LayerHost()
        view.host(layer)
        return view
    }

    public func updateUIView(_ view: LayerHost, context: Context) {
        view.host(layer)
    }

    public final class LayerHost: UIView {
        private weak var hosted: CALayer?

        func host(_ layer: CALayer) {
            guard hosted !== layer else { return }
            layer.removeFromSuperlayer()
            self.layer.addSublayer(layer)
            hosted = layer
            setNeedsLayout()
        }

        public override func layoutSubviews() {
            super.layoutSubviews()
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            hosted?.frame = bounds
            CATransaction.commit()
        }

        public override init(frame: CGRect) {
            super.init(frame: frame)
            backgroundColor = .black
            isUserInteractionEnabled = false
        }

        required init?(coder: NSCoder) { fatalError() }
    }
}
#endif
