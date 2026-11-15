import Foundation
import simd

/// MiniMate's palettes are ARGB literals. Only the colour channels reach the shader; the scene
/// output is treated as already sRGB-encoded, exactly as it is on Android, so nothing is
/// linearised on the way in and the render target is a plain (non-sRGB) format on the way out.
public struct Colorway: Sendable, Equatable {
    public let label: String
    public let stops: [UInt32]

    public init(label: String, _ stops: UInt32...) {
        precondition(stops.count == 4, "a colorway is four stops")
        self.label = label
        self.stops = stops
    }

    public func stop(_ i: Int) -> SIMD4<Float> {
        let argb = stops[i]
        return SIMD4(Float((argb >> 16) & 0xFF) / 255.0,
                     Float((argb >> 8) & 0xFF) / 255.0,
                     Float(argb & 0xFF) / 255.0,
                     1.0)
    }
}

public extension Colorway {
    /// `FLAT[0]` in MiniMate's shader catalog, and therefore the default halftone palette.
    /// "The onboarding's mustard, as a flat pair. Minimal is where it belongs: it is a poster colour."
    static let mustardFlat = Colorway(label: "Mustard", 0xFF141210, 0xFF4A3A10, 0xFFD8A628, 0xFFFFF1CE)

    static let paperFlat = Colorway(label: "Paper", 0xFFF4F1EA, 0xFFD9D2C4, 0xFF17171A, 0xFFE8433F)
    static let signal    = Colorway(label: "Signal", 0xFFFAFAF7, 0xFFE4E4DE, 0xFF17171A, 0xFF2F6BFF)
    static let mono      = Colorway(label: "Monochrome", 0xFF030303, 0xFF262626, 0xFFBFBFBF, 0xFFFFFFFF)
}

/// One contact on the surface, in the scene's own aspect-corrected space.
public struct SceneTouch: Sendable {
    /// Centred, divided by `min(width, height)` — the space MiniMate's `touchWarp` works in.
    public var position: SIMD2<Float>
    /// Seconds since the contact began. Released contacts keep ageing; that is what fades them.
    public var age: Float
    /// 1 while held, 0 once released.
    public var active: Float

    public init(position: SIMD2<Float>, age: Float, active: Float) {
        self.position = position
        self.age = age
        self.active = active
    }

    /// Converts a point in pixels to the shader's space, matching the footer's
    /// `(fragCoord - 0.5 * res) / min(res.x, res.y)`.
    public static func fromPixels(_ point: SIMD2<Float>, size: SIMD2<Float>,
                                  age: Float, active: Float) -> SceneTouch {
        SceneTouch(position: (point - 0.5 * size) / min(size.x, size.y), age: age, active: active)
    }
}

/// Everything the halftone scene is driven by. The defaults are MiniMate's stored defaults, so a
/// freshly constructed value renders what the app shows on first run.
public struct HalftoneConfig: Sendable {
    /// pitch, speed, contrast, angle — the order the scene declares its controls, which is the
    /// order they arrive as `uP0..uP3`.
    public var params: SIMD4<Float>
    public var colorway: Colorway
    public var aberration: Float
    public var grain: Float
    public var touchStrength: Float
    /// Seconds. Drives `uTime`; `speed` scales it inside the scene.
    public var time: Float

    public init(params: SIMD4<Float> = SIMD4(22, 0.5, 0.8, 0.4),
                colorway: Colorway = .mustardFlat,
                aberration: Float = 0.6,
                grain: Float = 0.3,
                touchStrength: Float = 1.0,
                time: Float = 0) {
        self.params = params
        self.colorway = colorway
        self.aberration = aberration
        self.grain = grain
        self.touchStrength = touchStrength
        self.time = time
    }

    public var pitch: Float {
        get { params.x } set { params.x = newValue }
    }
    public var speed: Float {
        get { params.y } set { params.y = newValue }
    }
    public var contrast: Float {
        get { params.z } set { params.z = newValue }
    }
    public var angle: Float {
        get { params.w } set { params.w = newValue }
    }

    /// MiniMate's own first-run state: halftone, Mustard, pitch 22, speed .5, contrast .8,
    /// angle .4, aberration .6, grain .3.
    public static let miniMateDefault = HalftoneConfig()
}
