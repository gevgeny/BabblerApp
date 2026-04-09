//
//  TISInputSourceExtension.swift
//  kawa
//
//  Created by Yonguk Jeong on 16/09/2017.
//  Copyright (c) 2017 utatti and project contributors.
//  Licensed under the MIT License.
//
import Foundation
import Carbon
import AppKit

extension TISInputSource {
    enum Category {
        static var keyboardInputSource: String {
            return kTISCategoryKeyboardInputSource as String
        }
    }

    private func getProperty(_ key: CFString) -> AnyObject? {
        let cfType = TISGetInputSourceProperty(self, key)
        if (cfType != nil) {
            return Unmanaged<AnyObject>.fromOpaque(cfType!).takeUnretainedValue()
        } else {
            return nil
        }
    }

    var id: String {
        return getProperty(kTISPropertyInputSourceID) as! String
    }

    var name: String {
        return getProperty(kTISPropertyLocalizedName) as! String
    }

    var category: String {
        return getProperty(kTISPropertyInputSourceCategory) as! String
    }

    var isSelectable: Bool {
        return getProperty(kTISPropertyInputSourceIsSelectCapable) as! Bool
    }

    var sourceLanguages: [String] {
        return getProperty(kTISPropertyInputSourceLanguages) as! [String]
    }
    
    
    var iconRef: IconRef? {
        return OpaquePointer(TISGetInputSourceProperty(self, kTISPropertyIconRef)) as IconRef?
    }

    var iconImageURL: URL? {
        guard let urlRef = getProperty(kTISPropertyIconImageURL) as? String else { return nil }
        return URL(fileURLWithPath: urlRef)
    }
    
    var iconImage: NSImage? {
        if let iconURL = iconImageURL,
           let image = NSImage(contentsOf: iconURL) {
            return image
        }
        guard let iconRef = iconRef else { return nil }
        let size: CGFloat = 36
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: nil, width: Int(size), height: Int(size),
            bitsPerComponent: 8, bytesPerRow: 0, space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue
        ) else { return nil }
        var rect = CGRect(x: 0, y: 0, width: size, height: size)
        PlotIconRefInContext(
            ctx, &rect,
            IconAlignmentType(kAlignAbsoluteCenter),
            IconTransformType(kTransformNone),
            nil,
            PlotIconRefFlags(kPlotIconRefNormalFlags),
            iconRef
        )
        guard let cgImage = ctx.makeImage() else { return nil }
        return NSImage(cgImage: cgImage, size: NSSize(width: size, height: size))
    }
}
