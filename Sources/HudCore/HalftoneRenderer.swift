import Foundation
import Metal
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import simd

/// Mirrors the `Uniforms` struct in `halftoneShaderSource`. The stride is asserted at init so a
/// layout drift fails loudly instead of quietly rendering nonsense.
struct HalftoneUniforms {
    var resolution: SIMD2<Float> = .zero
    var time: Float = 0
    var now: Float = 0
    var params: SIMD4<Float> = .zero
    var c0: SIMD4<Float> = .zero
    var c1: SIMD4<Float> = .zero
    var c2: SIMD4<Float> = .zero
    var c3: SIMD4<Float> = .zero
    /// Eight packed `float4(x, y, age, active)` contacts.
    var touches: SIMD32<Float> = .zero
    var touchCount: Float = 0
    var touchStrength: Float = 0
    var aberration: Float = 0
    var grain: Float = 0
}

struct LensUniforms {
    var size: SIMD2<Float> = .zero
    var amount: Float = 0
}

public enum HalftoneRendererError: Error, CustomStringConvertible {
    case noDevice
    case shaderCompilation(String)
    case missingFunction(String)
    case textureAllocation
    case commandEncoding
    case imageCreation
    case uniformLayout(expected: Int, actual: Int)

    public var description: String {
        switch self {
        case .noDevice: return "no Metal device available"
        case .shaderCompilation(let m): return "shader compilation failed: \(m)"
        case .missingFunction(let n): return "shader function '\(n)' not found"
        case .textureAllocation: return "could not allocate a render target"
        case .commandEncoding: return "could not encode the render pass"
        case .imageCreation: return "could not build a CGImage from the render target"
        case .uniformLayout(let e, let a):
            return "Uniforms stride is \(a) bytes, shader expects \(e) — struct layout drifted"
        }
    }
}

/// Renders the halftone surface offscreen. Identical on macOS and iOS: the preview tool and the
/// app both go through this, so a difference between them would have to be a Metal difference
/// rather than a code difference.
public final class HalftoneRenderer {
    public let device: MTLDevice
    let queue: MTLCommandQueue
    let scenePipeline: MTLRenderPipelineState
    let lensPipeline: MTLRenderPipelineState

    /// Reused between frames by the live view, reallocated only when the drawable resizes.
    var cachedSceneTexture: MTLTexture?

    /// The shader declares `float4 touches[8]`, so eight is the ceiling the loop honours.
    public static let maxTouches = 8

    public init(device: MTLDevice? = nil) throws {
        guard let device = device ?? MTLCreateSystemDefaultDevice() else {
            throw HalftoneRendererError.noDevice
        }
        self.device = device

        // 240 bytes: 8 + 4 + 4, then float4 params/c0..c3 (16-aligned), 8 packed touch float4s,
        // then the four trailing scalars.
        let expected = 240
        let actual = MemoryLayout<HalftoneUniforms>.stride
        guard actual == expected else {
            throw HalftoneRendererError.uniformLayout(expected: expected, actual: actual)
        }

        guard let queue = device.makeCommandQueue() else { throw HalftoneRendererError.noDevice }
        self.queue = queue

        let library: MTLLibrary
        do {
            library = try device.makeLibrary(source: halftoneShaderSource, options: nil)
        } catch {
            throw HalftoneRendererError.shaderCompilation("\(error)")
        }

        func function(_ name: String) throws -> MTLFunction {
            guard let f = library.makeFunction(name: name) else {
                throw HalftoneRendererError.missingFunction(name)
            }
            return f
        }

        let vertexFunction = try function("fullscreen_vertex")

        func pipeline(fragment: String) throws -> MTLRenderPipelineState {
            let descriptor = MTLRenderPipelineDescriptor()
            descriptor.vertexFunction = vertexFunction
            descriptor.fragmentFunction = try function(fragment)
            descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
            return try device.makeRenderPipelineState(descriptor: descriptor)
        }

        self.scenePipeline = try pipeline(fragment: "scene_fragment")
        self.lensPipeline = try pipeline(fragment: "lens_fragment")
    }

    func makeTexture(width: Int, height: Int, readable: Bool) throws -> MTLTexture {
        let descriptor = MTLTextureDescriptor()
        descriptor.pixelFormat = .bgra8Unorm   // deliberately not _sRGB: see Colorway
        descriptor.width = width
        descriptor.height = height
        descriptor.usage = readable ? [.renderTarget, .shaderRead] : [.renderTarget]
        descriptor.storageMode = .shared
        guard let texture = device.makeTexture(descriptor: descriptor) else {
            throw HalftoneRendererError.textureAllocation
        }
        return texture
    }

    /// Packs the uniform block the shader reads.
    func uniforms(width: Int, height: Int,
                  config: HalftoneConfig, touches: [SceneTouch]) -> HalftoneUniforms {
        var uniforms = HalftoneUniforms()
        uniforms.resolution = SIMD2<Float>(Float(width), Float(height))
        uniforms.time = config.time
        uniforms.now = config.time
        uniforms.params = config.params
        uniforms.c0 = config.colorway.stop(0)
        uniforms.c1 = config.colorway.stop(1)
        uniforms.c2 = config.colorway.stop(2)
        uniforms.c3 = config.colorway.stop(3)
        uniforms.touchStrength = config.touchStrength
        uniforms.aberration = config.aberration
        uniforms.grain = config.grain

        let used = min(touches.count, Self.maxTouches)
        uniforms.touchCount = Float(used)
        for i in 0..<used {
            let t = touches[i]
            uniforms.touches[i * 4 + 0] = t.position.x
            uniforms.touches[i * 4 + 1] = t.position.y
            uniforms.touches[i * 4 + 2] = t.age
            uniforms.touches[i * 4 + 3] = t.active
        }
        return uniforms
    }

    /// Renders one frame and hands back the final texture's pixels as a `CGImage`.
    public func render(width: Int,
                       height: Int,
                       config: HalftoneConfig = .miniMateDefault,
                       touches: [SceneTouch] = []) throws -> CGImage {
        var uniforms = self.uniforms(width: width, height: height,
                                     config: config, touches: touches)
        let size = SIMD2<Float>(Float(width), Float(height))

        let sceneTexture = try makeTexture(width: width, height: height, readable: true)
        let finalTexture = try makeTexture(width: width, height: height, readable: false)

        guard let buffer = queue.makeCommandBuffer() else {
            throw HalftoneRendererError.commandEncoding
        }

        func pass(into texture: MTLTexture,
                  _ body: (MTLRenderCommandEncoder) -> Void) throws {
            let descriptor = MTLRenderPassDescriptor()
            descriptor.colorAttachments[0].texture = texture
            descriptor.colorAttachments[0].loadAction = .clear
            descriptor.colorAttachments[0].storeAction = .store
            descriptor.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 0, 1)
            guard let encoder = buffer.makeRenderCommandEncoder(descriptor: descriptor) else {
                throw HalftoneRendererError.commandEncoding
            }
            body(encoder)
            encoder.endEncoding()
        }

        try pass(into: sceneTexture) { encoder in
            encoder.setRenderPipelineState(scenePipeline)
            encoder.setFragmentBytes(&uniforms,
                                     length: MemoryLayout<HalftoneUniforms>.stride,
                                     index: 0)
            encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        }

        var lens = LensUniforms(size: size, amount: config.aberration)
        try pass(into: finalTexture) { encoder in
            encoder.setRenderPipelineState(lensPipeline)
            encoder.setFragmentTexture(sceneTexture, index: 0)
            encoder.setFragmentBytes(&lens, length: MemoryLayout<LensUniforms>.stride, index: 0)
            encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        }

        buffer.commit()
        buffer.waitUntilCompleted()

        return try image(from: finalTexture)
    }

    private func image(from texture: MTLTexture) throws -> CGImage {
        let width = texture.width, height = texture.height
        let rowBytes = width * 4
        var pixels = [UInt8](repeating: 0, count: rowBytes * height)
        pixels.withUnsafeMutableBytes { raw in
            texture.getBytes(raw.baseAddress!,
                             bytesPerRow: rowBytes,
                             from: MTLRegionMake2D(0, 0, width, height),
                             mipmapLevel: 0)
        }

        // bgra8Unorm in memory is B,G,R,A — little-endian 32-bit with alpha first.
        let info = CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipFirst.rawValue
                                | CGBitmapInfo.byteOrder32Little.rawValue)
        guard let provider = CGDataProvider(data: Data(pixels) as CFData),
              let image = CGImage(width: width,
                                  height: height,
                                  bitsPerComponent: 8,
                                  bitsPerPixel: 32,
                                  bytesPerRow: rowBytes,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: info,
                                  provider: provider,
                                  decode: nil,
                                  shouldInterpolate: false,
                                  intent: .defaultIntent)
        else {
            throw HalftoneRendererError.imageCreation
        }
        return image
    }
}

public extension CGImage {
    /// Writes a PNG. Used by the preview tool and usable from the app for snapshot tests.
    func writePNG(to url: URL) throws {
        guard let destination = CGImageDestinationCreateWithURL(
            url as CFURL, UTType.png.identifier as CFString, 1, nil
        ) else {
            throw HalftoneRendererError.imageCreation
        }
        CGImageDestinationAddImage(destination, self, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw HalftoneRendererError.imageCreation
        }
    }
}
