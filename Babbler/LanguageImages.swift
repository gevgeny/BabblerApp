//
//  LanguageImages.swift
//  Babbler
//
//  Created by eugene gluhotorenko on 25/06/2022.
//  Copyright © 2022 Eugene Gluhotorenko. All rights reserved.
//

let LanguageImages: [String: String] = [
    // Latin
    "com.apple.keylayout.US":                          "🇺🇸",
    "com.apple.keylayout.USInternational-PC":          "🇺🇸",
    "com.apple.keylayout.British-PC":                  "🇬🇧",
    "com.apple.keylayout.British":                     "🇬🇧",
    // Cyrillic
    "com.apple.keylayout.Russian":                     "🇷🇺",
    "com.apple.keylayout.RussianWin":                  "🇷🇺",
    "com.apple.keylayout.Russian-Phonetic":            "🇷🇺",
    "com.apple.keylayout.Ukrainian":                   "🇺🇦",
    "com.apple.keylayout.Ukrainian-PC":                "🇺🇦",
    "com.apple.keylayout.Bulgarian":                   "🇧🇬",
    "com.apple.keylayout.Bulgarian-Phonetic":          "🇧🇬",
    "com.apple.keylayout.Serbian":                     "🇷🇸",
    "com.apple.keylayout.Serbian-Latin":               "🇷🇸",
    "com.apple.keylayout.Byelorussian":                "🇧🇾",
    "com.apple.keylayout.Macedonian":                  "🇲🇰",
    "com.apple.keylayout.Mongolian":                   "🇲🇳",
    "com.apple.keylayout.Kazakh":                      "🇰🇿",
]

// Override labels for specific layouts where the ISO 639-1 code isn't ideal.
// For everything else the first ISO 639-1 code from sourceLanguages is used.
let LanguageLabels: [String: String] = [:]

import AppKit
import Carbon

func makeInputSourceIcon(for source: TISInputSource) -> NSImage? {
    let text = (LanguageLabels[source.id]
        ?? source.sourceLanguages.first
        ?? String(source.name.prefix(2))).uppercased()
    
    let imageSize = NSSize(width: 22, height: 17)
    
    let image = NSImage(size: imageSize, flipped: false) { drawRect in
        let lineWidth: CGFloat = 1.0
        let cornerRadius: CGFloat = 2.5
        let rect = drawRect.insetBy(dx: lineWidth / 2, dy: lineWidth / 2)
        let path = NSBezierPath(roundedRect: rect, xRadius: cornerRadius, yRadius: cornerRadius)
        path.lineWidth = lineWidth
        NSColor.black.setStroke()
        path.stroke()
        
        let fontSize: CGFloat = text.count > 1 ? 9.5 : 11.5
        let font = NSFont.systemFont(ofSize: fontSize, weight: .medium)
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.black,
        ]
        let textSize = (text as NSString).size(withAttributes: attrs)
        let textPoint = CGPoint(
            x: (drawRect.width - textSize.width) / 2,
            y: (drawRect.height - textSize.height) / 2 - 0.5
        )
        (text as NSString).draw(at: textPoint, withAttributes: attrs)
        
        return true
    }
    
    image.isTemplate = true
    return image
}

