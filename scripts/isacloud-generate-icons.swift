// Generates the isaCloud app icon, in-app logo and CallKit template from the source logo.
//
// usage (from the repository root):
//   swift scripts/isacloud-generate-icons.swift isaCloud/branding/logo-isacloud-im-transp-ico-balao-2000px.png
//
// writes:
//   Monal/Images.xcassets/AppIcon.appiconset/isaCloud-ios_1024.png   (opaque, white background)
//   Monal/Images.xcassets/AppLogo.imageset/isaCloud-logo_1024.png    (transparent background)
//   Monal/Images.xcassets/CallKitLogo.imageset/isaCloud-callkit.png  (black template, alpha = colored strokes)

import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

// share of the canvas width the logo occupies
let iconScale = 0.70        // app icon: leaves room for the rounded corners iOS applies
let logoScale = 0.92        // in-app logo
let callkitScale = 0.94     // CallKit template

let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: CommandLine.arguments[1]) as CFURL, nil)!
let logo = CGImageSourceCreateImageAtIndex(source, 0, nil)!
let srgb = CGColorSpace(name: CGColorSpace.sRGB)!
let assets = "Monal/Images.xcassets"

func context(_ size: Int, opaque: Bool) -> CGContext {
    let info = opaque ? CGImageAlphaInfo.noneSkipLast.rawValue : CGImageAlphaInfo.premultipliedLast.rawValue
    let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0, space: srgb, bitmapInfo: info)!
    ctx.interpolationQuality = .high
    return ctx
}

// draws the image centered, scaled to the given share of the canvas width (keeping the aspect ratio)
func drawCentered(_ image: CGImage, in ctx: CGContext, size: Int, scale: Double) {
    let w = Double(size) * scale
    let h = w * Double(image.height) / Double(image.width)
    ctx.draw(image, in: CGRect(x: (Double(size) - w) / 2, y: (Double(size) - h) / 2, width: w, height: h))
}

func save(_ ctx: CGContext, _ path: String) {
    let img = ctx.makeImage()!
    let dest = CGImageDestinationCreateWithURL(URL(fileURLWithPath: path) as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, img, nil)
    CGImageDestinationFinalize(dest)
    print("wrote \(path) (\(img.width)x\(img.height))")
}

// app icon: no alpha channel allowed
let icon = context(1024, opaque: true)
icon.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))
icon.fill(CGRect(x: 0, y: 0, width: 1024, height: 1024))
drawCentered(logo, in: icon, size: 1024, scale: iconScale)
save(icon, "\(assets)/AppIcon.appiconset/isaCloud-ios_1024.png")

// in-app logo
let applogo = context(1024, opaque: false)
drawCentered(logo, in: applogo, size: 1024, scale: logoScale)
save(applogo, "\(assets)/AppLogo.imageset/isaCloud-logo_1024.png")

// CallKit template: alpha = how "colored" a pixel is, so white and transparent areas become transparent
let w = logo.width, h = logo.height
let rgba = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4, space: srgb, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
rgba.draw(logo, in: CGRect(x: 0, y: 0, width: w, height: h))
let p = rgba.data!.bindMemory(to: UInt8.self, capacity: w * h * 4)
for i in 0..<(w * h) {
    let a = Double(p[i*4+3]) / 255
    let r = a > 0 ? Double(p[i*4]) / 255 / a : 1, g = a > 0 ? Double(p[i*4+1]) / 255 / a : 1, b = a > 0 ? Double(p[i*4+2]) / 255 / a : 1
    let m = max(0, min(1, (1 - min(r, g, b)) * 1.6)) * a
    p[i*4] = 0; p[i*4+1] = 0; p[i*4+2] = 0; p[i*4+3] = UInt8(m * 255)
}
let callkit = context(512, opaque: false)
drawCentered(rgba.makeImage()!, in: callkit, size: 512, scale: callkitScale)
save(callkit, "\(assets)/CallKitLogo.imageset/isaCloud-callkit.png")
