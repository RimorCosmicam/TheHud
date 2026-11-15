#if canImport(MetalKit)
import SwiftUI
import MetalKit
import QuartzCore
import simd

/// The halftone surface, live.
///
/// Written for both platforms on purpose: MetalKit is cross-platform, so the macOS branch
/// compiles and runs on a development machine that has no Xcode and therefore no iOS SDK. That
/// makes almost all of this path verifiable here rather than only on a device.
public final class HalftoneSurfaceCoordinator: NSObject, MTKViewDelegate {
    private let renderer: HalftoneRenderer?
    private let impulses = TouchImpulseHistory()
    private let start = CACurrentMediaTime()

    public var config: HalftoneConfig
    /// Live contacts, in the surface's own points. Converted to the shader's space per frame,
    /// because the conversion depends on the drawable size.
    public var contacts: [TouchPoint] = []
    public var surfaceSize: CGSize = .zero

    public init(renderer: HalftoneRenderer?, config: HalftoneConfig = .miniMateDefault) {
        self.renderer = renderer
        self.config = config
    }

    public func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        renderer?.cachedSceneTexture = nil
    }

    public func draw(in view: MTKView) {
        // No Metal means no surface. The view stays black rather than taking the app down.
        guard let renderer,
              let drawable = view.currentDrawable,
              let descriptor = view.currentRenderPassDescriptor,
              let buffer = renderer.queue.makeCommandBuffer() else { return }

        let width = drawable.texture.width
        let height = drawable.texture.height
        guard width > 0, height > 0 else { return }

        let now = CACurrentMediaTime() - start
        var frameConfig = config
        frameConfig.time = Float(now)

        // Impulse ids are kept independent of platform pointer ids, so a released contact keeps
        // decaying while a new finger reusing its id starts its own ripple.
        let points = impulses.update(active: contacts, now: now)
        let pixelScale = CGFloat(width) / max(surfaceSize.width, 1)
        let size = SIMD2<Float>(Float(width), Float(height))
        let touches: [SceneTouch] = points.map { point in
            SceneTouch.fromPixels(SIMD2(Float(point.x * pixelScale), Float(point.y * pixelScale)),
                                  size: size,
                                  age: Float(now - point.startedAtSeconds),
                                  active: point.active ? 1 : 0)
        }

        var uniforms = renderer.uniforms(width: width, height: height,
                                         config: frameConfig, touches: touches)

        let sceneTexture: MTLTexture
        if let cached = renderer.cachedSceneTexture,
           cached.width == width, cached.height == height {
            sceneTexture = cached
        } else {
            guard let fresh = try? renderer.makeTexture(width: width, height: height,
                                                        readable: true) else { return }
            renderer.cachedSceneTexture = fresh
            sceneTexture = fresh
        }

        let scenePass = MTLRenderPassDescriptor()
        scenePass.colorAttachments[0].texture = sceneTexture
        scenePass.colorAttachments[0].loadAction = .clear
        scenePass.colorAttachments[0].storeAction = .store
        scenePass.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 0, 1)

        if let encoder = buffer.makeRenderCommandEncoder(descriptor: scenePass) {
            encoder.setRenderPipelineState(renderer.scenePipeline)
            encoder.setFragmentBytes(&uniforms,
                                     length: MemoryLayout<HalftoneUniforms>.stride, index: 0)
            encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
            encoder.endEncoding()
        }

        var lens = LensUniforms(size: size, amount: frameConfig.aberration)
        if let encoder = buffer.makeRenderCommandEncoder(descriptor: descriptor) {
            encoder.setRenderPipelineState(renderer.lensPipeline)
            encoder.setFragmentTexture(sceneTexture, index: 0)
            encoder.setFragmentBytes(&lens, length: MemoryLayout<LensUniforms>.stride, index: 0)
            encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
            encoder.endEncoding()
        }

        buffer.present(drawable)
        buffer.commit()
    }
}

#if os(iOS)
public typealias HudViewRepresentable = UIViewRepresentable
#else
public typealias HudViewRepresentable = NSViewRepresentable
#endif

/// SwiftUI wrapper for the live surface.
public struct HalftoneSurfaceView: HudViewRepresentable {
    public var config: HalftoneConfig
    public var contacts: [TouchPoint]
    public var surfaceSize: CGSize

    public init(config: HalftoneConfig = .miniMateDefault,
                contacts: [TouchPoint] = [],
                surfaceSize: CGSize = .zero) {
        self.config = config
        self.contacts = contacts
        self.surfaceSize = surfaceSize
    }

    public func makeCoordinator() -> HalftoneSurfaceCoordinator {
        HalftoneSurfaceCoordinator(renderer: try? HalftoneRenderer(), config: config)
    }

    private func makeView(context: Context) -> MTKView {
        let view = MTKView(frame: .zero, device: context.coordinator.deviceForView)
        view.delegate = context.coordinator
        view.colorPixelFormat = .bgra8Unorm   // deliberately not _sRGB: see Colorway
        view.framebufferOnly = true
        view.isPaused = false
        view.enableSetNeedsDisplay = false
        view.preferredFramesPerSecond = 60
#if os(iOS)
        // Drawing only. Touches belong to the capture view laid over it.
        view.isUserInteractionEnabled = false
#endif
        return view
    }

    private func update(_ view: MTKView, context: Context) {
        context.coordinator.config = config
        context.coordinator.contacts = contacts
        context.coordinator.surfaceSize = surfaceSize
    }

#if os(iOS)
    public func makeUIView(context: Context) -> MTKView { makeView(context: context) }
    public func updateUIView(_ view: MTKView, context: Context) { update(view, context: context) }
#else
    public func makeNSView(context: Context) -> MTKView { makeView(context: context) }
    public func updateNSView(_ view: MTKView, context: Context) { update(view, context: context) }
#endif
}

extension HalftoneSurfaceCoordinator {
    var deviceForView: MTLDevice? { MTLCreateSystemDefaultDevice() }
}
#endif
