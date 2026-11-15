import SwiftUI
import UIKit
import HudCore

/// A transparent view over the Metal surface that turns touches into frames.
///
/// Separate from the surface on purpose: the surface is shared with the macOS preview tool and
/// knows nothing about input, and UIKit touch handling has no business inside a renderer.
///
/// The rail and the right-click corner are routed here too, in UIKit, rather than as SwiftUI
/// gestures laid over the pad. Every touch is claimed by exactly one zone the moment it lands,
/// so a thumb on the rail and a finger on the pad can be down together without either one
/// stealing the other — the same split MiniMate makes.
struct TrackpadTouchHost: UIViewRepresentable {
    let controller: HudController

    func makeUIView(context: Context) -> TouchCaptureView {
        let view = TouchCaptureView()
        view.backgroundColor = .clear
        view.isMultipleTouchEnabled = true
        view.controller = controller
        let bridge = UIKitTouchBridge(recognizer: controller.recognizer)
        bridge.owns = { [weak view] touch in view?.isPadTouch(touch) ?? false }
        view.bridge = bridge
        return view
    }

    func updateUIView(_ view: TouchCaptureView, context: Context) {}
}

final class TouchCaptureView: UIView {
    var bridge: UIKitTouchBridge?
    weak var controller: HudController?

    /// MiniMate's reserved regions at its stored scales: 52pt x 1.32 for the rail, a 104pt x
    /// 1.28 box for the corner.
    private let railWidth: CGFloat = 52 * 1.32
    private let cornerBox: CGFloat = 104 * 1.28
    /// Further than this and a press on the corner was a drag that started there, not a click.
    private let cornerSlop: CGFloat = 24

    private var padTouches: Set<ObjectIdentifier> = []
    private var railTouch: ObjectIdentifier?
    private var cornerTouch: (id: ObjectIdentifier, start: CGPoint, moved: Bool)?
    private var lastReportedSize: CGSize = .zero

    func isPadTouch(_ touch: UITouch) -> Bool { padTouches.contains(ObjectIdentifier(touch)) }

    override func layoutSubviews() {
        super.layoutSubviews()
        if bounds.size != lastReportedSize {
            lastReportedSize = bounds.size
            controller?.surfaceSizeChanged(to: bounds.size)
        }
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in touches {
            let point = touch.location(in: self)
            let id = ObjectIdentifier(touch)
            if point.x < railWidth, railTouch == nil {
                railTouch = id
                controller?.railBegan(at: point.y)
            } else if point.x > bounds.width - cornerBox, point.y < cornerBox, cornerTouch == nil {
                cornerTouch = (id, point, false)
                controller?.cornerPressed = true
            } else {
                padTouches.insert(id)
            }
        }
        bridge?.began(touches, with: event, in: self)
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in touches {
            let id = ObjectIdentifier(touch)
            let point = touch.location(in: self)
            if id == railTouch {
                controller?.railMoved(to: point.y)
            } else if var corner = cornerTouch, corner.id == id {
                if hypot(point.x - corner.start.x, point.y - corner.start.y) > cornerSlop {
                    corner.moved = true
                    cornerTouch = corner
                    controller?.cornerPressed = false
                }
            }
        }
        bridge?.moved(touches, with: event, in: self)
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        bridge?.ended(touches, with: event, in: self)
        finish(touches, tapped: true)
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        bridge?.cancelled(touches, with: event, in: self)
        finish(touches, tapped: false)
    }

    private func finish(_ touches: Set<UITouch>, tapped: Bool) {
        for touch in touches {
            let id = ObjectIdentifier(touch)
            if id == railTouch {
                railTouch = nil
                controller?.railEnded()
            } else if let corner = cornerTouch, corner.id == id {
                cornerTouch = nil
                controller?.cornerPressed = false
                if tapped && !corner.moved { controller?.cornerTapped() }
            } else {
                padTouches.remove(id)
            }
        }
    }
}
