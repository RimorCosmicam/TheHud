import SwiftUI
import UIKit
import HudCore

/// A transparent view over the Metal surface that turns touches into frames.
///
/// Separate from the surface on purpose: the surface is shared with the macOS preview tool and
/// knows nothing about input, and UIKit touch handling has no business inside a renderer.
struct TrackpadTouchHost: UIViewRepresentable {
    let controller: HudController

    func makeUIView(context: Context) -> TouchCaptureView {
        let view = TouchCaptureView()
        view.backgroundColor = .clear
        view.isMultipleTouchEnabled = true
        view.bridge = UIKitTouchBridge(recognizer: controller.recognizer)
        view.onLayout = { size in
            Task { @MainActor in controller.surfaceSizeChanged(to: size) }
        }
        return view
    }

    func updateUIView(_ view: TouchCaptureView, context: Context) {}
}

final class TouchCaptureView: UIView {
    var bridge: UIKitTouchBridge?
    var onLayout: ((CGSize) -> Void)?
    private var lastReportedSize: CGSize = .zero

    override func layoutSubviews() {
        super.layoutSubviews()
        if bounds.size != lastReportedSize {
            lastReportedSize = bounds.size
            onLayout?(bounds.size)
        }
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        bridge?.began(touches, with: event, in: self)
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        bridge?.moved(touches, with: event, in: self)
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        bridge?.ended(touches, with: event, in: self)
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        bridge?.cancelled(touches, with: event, in: self)
    }
}
