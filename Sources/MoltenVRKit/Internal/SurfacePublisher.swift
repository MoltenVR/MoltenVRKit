import Foundation
import IOSurface
import CoreVideo
import Metal
import ScreenCaptureKit

/// One global IOSurface per panel, with each captured frame blitted into it. MoltenVR looks
/// the ID up once and samples the same surface every frame, so only a resize needs a new one.
final class SurfacePublisher {
    private static let device = MTLCreateSystemDefaultDevice()
    private static let queue = device?.makeCommandQueue()
    private static var texCache: CVMetalTextureCache? = {
        guard let dev = device else { return nil }
        var cache: CVMetalTextureCache?
        CVMetalTextureCacheCreate(nil, nil, dev, nil, &cache)
        return cache
    }()

    private(set) var surface: IOSurfaceRef?
    private(set) var surfaceId: UInt32 = 0
    private(set) var pixelSize: CGSize = .zero
    private var dstTexture: MTLTexture?

    @discardableResult
    func prepare(pixelSize: CGSize) -> Bool {
        guard let dev = Self.device else { return false }
        if surface != nil, self.pixelSize == pixelSize { return true }
        let w = Int(pixelSize.width), h = Int(pixelSize.height)
        let props: [IOSurfacePropertyKey: Any] = [
            .width: w, .height: h, .bytesPerElement: 4,
            .pixelFormat: UInt32(kCVPixelFormatType_32BGRA),
            IOSurfacePropertyKey(rawValue: "IOSurfaceIsGlobal" as CFString as String): true,
        ]
        guard let s = IOSurfaceCreate(props as CFDictionary) else { return false }
        let td = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm,
                                                          width: w, height: h, mipmapped: false)
        td.usage = [.shaderRead, .shaderWrite]
        guard let tex = dev.makeTexture(descriptor: td, iosurface: s, plane: 0) else { return false }
        surface = s
        surfaceId = IOSurfaceGetID(s)
        dstTexture = tex
        self.pixelSize = pixelSize
        return true
    }

    func publish(_ pb: CVPixelBuffer) {
        guard let dst = dstTexture, let cache = Self.texCache,
              let cq = Self.queue else { return }
        let w = CVPixelBufferGetWidth(pb), h = CVPixelBufferGetHeight(pb)
        guard w > 0, h > 0 else { return }
        var cvTex: CVMetalTexture?
        guard CVMetalTextureCacheCreateTextureFromImage(nil, cache, pb, nil, .bgra8Unorm,
                                                        w, h, 0, &cvTex) == kCVReturnSuccess,
              let src = cvTex.flatMap(CVMetalTextureGetTexture) else { return }
        guard let cmd = cq.makeCommandBuffer(), let blit = cmd.makeBlitCommandEncoder() else { return }
        let cw = min(w, dst.width), ch = min(h, dst.height)
        blit.copy(from: src, sourceSlice: 0, sourceLevel: 0,
                  sourceOrigin: MTLOrigin(x: 0, y: 0, z: 0),
                  sourceSize: MTLSize(width: cw, height: ch, depth: 1),
                  to: dst, destinationSlice: 0, destinationLevel: 0,
                  destinationOrigin: MTLOrigin(x: 0, y: 0, z: 0))
        blit.endEncoding()
        cmd.commit()
    }
}
