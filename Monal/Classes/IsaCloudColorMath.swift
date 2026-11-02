//
//  IsaCloudColorMath.swift
//  Monal
//
//  isaCloud: the pure part of the colours of the messages the user sends (see IsaCloudBubbleColors in GifPickerView.swift):
//  "#RRGGBB" text to Color and back, and the WCAG contrast between two colours. No state here, so the unit tests call it directly.
//

import SwiftUI
import UIKit

enum IsaCloudColorMath {

    /// WCAG AA for normal text: below this the text is hard to read on the bubble
    static let minimumReadableContrast = 4.5

    /// "#RRGGBB" or "RRGGBB" (any case) to a Color in sRGB; nil when the text is empty or is not six hexadecimal digits
    static func color(fromHex hex: String) -> Color? {
        var digits = hex.trimmingCharacters(in: .whitespaces)
        if digits.hasPrefix("#") {
            digits.removeFirst()
        }
        guard digits.count == 6, digits.allSatisfy({ $0.isHexDigit }), let value = UInt32(digits, radix: 16) else {
            return nil
        }
        return Color(
            red: Double((value >> 16) & 0xFF) / 255.0,
            green: Double((value >> 8) & 0xFF) / 255.0,
            blue: Double(value & 0xFF) / 255.0
        )
    }

    /// the colour as "#RRGGBB" (uppercase), in sRGB
    static func hex(from color: Color) -> String {
        let rgb = srgbComponents(of: color)
        return String(format: "#%02X%02X%02X", channel(rgb.red), channel(rgb.green), channel(rgb.blue))
    }

    /// WCAG contrast ratio between two colours: 1 (no contrast) up to 21 (white on black)
    static func contrastRatio(_ first: Color, _ second: Color) -> Double {
        let one = relativeLuminance(of: first)
        let two = relativeLuminance(of: second)
        let lighter = max(one, two)
        let darker = min(one, two)
        return (lighter + 0.05) / (darker + 0.05)
    }

    /// true when the text colour has enough contrast on the bubble colour
    static func isReadable(bubble: Color, text: Color) -> Bool {
        return contrastRatio(bubble, text) >= minimumReadableContrast
    }

    // MARK: - helpers

    private static func channel(_ value: Double) -> Int {
        return Int((min(max(value, 0), 1) * 255).rounded())
    }

    /// the red, green and blue of a colour in sRGB, from 0 to 1
    private static func srgbComponents(of color: Color) -> (red: Double, green: Double, blue: Double) {
        let uiColor = UIColor(color)
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        if uiColor.getRed(&red, green: &green, blue: &blue, alpha: &alpha) {
            return (Double(red), Double(green), Double(blue))
        }
        // not an RGB colour (gray, pattern): convert its CGColor to sRGB
        if let srgb = CGColorSpace(name: CGColorSpace.sRGB), let converted = uiColor.cgColor.converted(to: srgb, intent: .defaultIntent, options: nil), let components = converted.components {
            if components.count >= 3 {
                return (Double(components[0]), Double(components[1]), Double(components[2]))
            }
            if components.count == 2 {
                return (Double(components[0]), Double(components[0]), Double(components[0]))
            }
        }
        return (0, 0, 0)
    }

    /// WCAG relative luminance of a colour
    private static func relativeLuminance(of color: Color) -> Double {
        let rgb = srgbComponents(of: color)
        return 0.2126 * linear(rgb.red) + 0.7152 * linear(rgb.green) + 0.0722 * linear(rgb.blue)
    }

    private static func linear(_ value: Double) -> Double {
        return value <= 0.03928 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
    }
}
