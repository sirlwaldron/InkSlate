import Foundation
import SwiftUI

#if canImport(UIKit)
import UIKit
public typealias PlatformImage = UIImage
#elseif canImport(AppKit)
import AppKit
public typealias PlatformImage = NSImage
#endif

// MARK: - Create from Data

var platformScreenWidth: CGFloat {
    #if canImport(UIKit)
    // UIScreen.main is deprecated; use the active window scene's screen instead.
    // Only called from view bodies / UI code, which run on the main actor.
    return MainActor.assumeIsolated {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let scene = scenes.first { $0.activationState == .foregroundActive } ?? scenes.first
        return scene?.screen.bounds.width ?? 390
    }
    #elseif canImport(AppKit)
    return NSScreen.main?.visibleFrame.width ?? 800
    #else
    return 800
    #endif
}

func platformImage(from data: Data) -> PlatformImage? {
    #if canImport(UIKit)
    return UIImage(data: data)
    #elseif canImport(AppKit)
    return NSImage(data: data)
    #else
    return nil
    #endif
}

// MARK: - NSImage JPEG/PNG helpers (macOS)

// MARK: - SwiftUI Image from PlatformImage
extension Image {
    init(platformImage: PlatformImage) {
        #if canImport(UIKit)
        self.init(uiImage: platformImage)
        #elseif canImport(AppKit)
        self.init(nsImage: platformImage)
        #else
        self.init(systemName: "photo")
        #endif
    }
}

#if canImport(AppKit)
extension NSImage {
    func jpegData(compressionQuality: CGFloat) -> Data? {
        guard let tiff = tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff) else { return nil }
        return bitmap.representation(using: .jpeg, properties: [.compressionFactor: compressionQuality])
    }
    func pngData() -> Data? {
        guard let tiff = tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff) else { return nil }
        return bitmap.representation(using: .png, properties: [:])
    }

    func inkSlateJPEGDataFitting(maxBytes: Int) -> Data? {
        let qualitySteps: [CGFloat] = [0.82, 0.74, 0.66, 0.58, 0.50, 0.42, 0.36]
        let scaleSteps: [CGFloat] = [1.0, 0.85, 0.72, 0.60, 0.50, 0.42, 0.35, 0.28]
        let originalSize = size
        let maxDimensionCap: CGFloat = 3600

        for scale in scaleSteps {
            let targetMaxDim = min(maxDimensionCap, max(originalSize.width, originalSize.height) * scale)
            let resized = Self.inkSlateResize(image: self, maxDimension: targetMaxDim) ?? self
            for q in qualitySteps {
                guard let data = resized.jpegData(compressionQuality: q) else { continue }
                if data.count <= maxBytes { return data }
            }
        }
        let tiny = Self.inkSlateResize(image: self, maxDimension: 1600) ?? self
        return tiny.jpegData(compressionQuality: 0.30).flatMap { $0.count <= maxBytes ? $0 : nil }
    }

    private static func inkSlateResize(image: NSImage, maxDimension: CGFloat) -> NSImage? {
        guard maxDimension.isFinite, maxDimension > 0 else { return nil }
        let sz = image.size
        let maxDim = max(sz.width, sz.height)
        guard maxDim > maxDimension else { return image }
        let scale = maxDimension / maxDim
        let newSize = NSSize(width: max(1, floor(sz.width * scale)), height: max(1, floor(sz.height * scale)))
        let output = NSImage(size: newSize)
        output.lockFocus()
        image.draw(in: NSRect(origin: .zero, size: newSize), from: .zero, operation: .copy, fraction: 1)
        output.unlockFocus()
        return output
    }
}
#endif

#if canImport(UIKit)
extension UIImage {
    /// Returns JPEG data that fits within `maxBytes` by lowering quality and downscaling dimensions
    func inkSlateJPEGDataFitting(maxBytes: Int) -> Data? {
        let qualitySteps: [CGFloat] = [0.82, 0.74, 0.66, 0.58, 0.50, 0.42, 0.36]
        let scaleSteps: [CGFloat] = [1.0, 0.85, 0.72, 0.60, 0.50, 0.42, 0.35, 0.28]
        
        // JPEG has no alpha: PNGs/screenshots with transparency would otherwise come out on black.
        let source = inkSlateFlattenedOnWhiteIfNeeded()
        let originalSize = source.size
        let maxDimensionCap: CGFloat = 3600
        
        for scale in scaleSteps {
            let targetMaxDim = min(maxDimensionCap, max(originalSize.width, originalSize.height) * scale)
            let resized = Self.inkSlateResize(image: source, maxDimension: targetMaxDim) ?? source
            
            for q in qualitySteps {
                guard let data = resized.jpegData(compressionQuality: q) else { continue }
                if data.count <= maxBytes { return data }
            }
        }
        
        let tiny = Self.inkSlateResize(image: source, maxDimension: 1600) ?? source
        return tiny.jpegData(compressionQuality: 0.30).flatMap { $0.count <= maxBytes ? $0 : nil }
    }
    
    /// Composites an image that has an alpha channel onto white; opaque images are returned as is.
    private func inkSlateFlattenedOnWhiteIfNeeded() -> UIImage {
        guard let cg = cgImage else { return self }
        switch cg.alphaInfo {
        case .none, .noneSkipFirst, .noneSkipLast:
            return self
        default:
            break
        }
        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        format.opaque = true
        return UIGraphicsImageRenderer(size: size, format: format).image { ctx in
            UIColor.white.setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
            draw(at: .zero)
        }
    }
    
    private static func inkSlateResize(image: UIImage, maxDimension: CGFloat) -> UIImage? {
        guard maxDimension.isFinite, maxDimension > 0 else { return nil }
        let sz = image.size
        let maxDim = max(sz.width, sz.height)
        guard maxDim > maxDimension else { return image }
        
        let scale = maxDimension / maxDim
        let newSize = CGSize(width: max(1, floor(sz.width * scale)), height: max(1, floor(sz.height * scale)))
        
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        
        let renderer = UIGraphicsImageRenderer(size: newSize, format: format)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: newSize))
        }
    }
}
#endif
