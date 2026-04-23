//
//  PlatformImage.swift
//  InkSlate
//
//  Cross-platform image type: UIImage on iOS, NSImage on macOS.
//

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

/// Main screen width (UIScreen on iOS, NSScreen on macOS).
var platformScreenWidth: CGFloat {
    #if canImport(UIKit)
    return UIScreen.main.bounds.width
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

// MARK: - NSImage JPEG/PNG (macOS); UIImage has these built-in on iOS

// MARK: - SwiftUI Image from PlatformImage
extension Image {
    init(platformImage: PlatformImage) {
        #if canImport(UIKit)
        self.init(uiImage: platformImage)
        #elseif canImport(AppKit)
        self.init(nsImage: platformImage as! NSImage)
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
}
#endif
