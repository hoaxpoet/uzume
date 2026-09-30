// render_text.swift — PROMO.1: draw text lines into a transparent PNG with macOS CoreText.
//
// Homebrew's ffmpeg is built without freetype (no `drawtext`), so cut_promo.py renders the end tag and
// the contact-sheet labels here and overlays the PNG with ffmpeg. macOS built-ins only; no dependency.
//
// Usage: swift render_text.swift <spec.json> <out.png>
// spec: {"width":1080,"height":1080,"font":"/path/Font.ttf","weight":600,"alpha":0.85,
//        "shadow_px":2,"tracking_em":-0.02,
//        "lines":[{"text":"Uzume","size":170,"center_y":790}, ...]}
// Positions are line centres in px from the top-left; "center_x" is optional (default: horizontal centre).

import AppKit
import CoreText
import Foundation

struct Line: Decodable { let text: String; let size: Double; let center_y: Double; let center_x: Double? }
struct Spec: Decodable {
    let width: Int, height: Int, font: String
    let weight: Double?, alpha: Double?, shadow_px: Double?, tracking_em: Double?
    let lines: [Line]
}

let args = CommandLine.arguments
guard args.count == 3 else { FileHandle.standardError.write(Data("usage: <spec.json> <out.png>\n".utf8)); exit(2) }
let spec = try JSONDecoder().decode(Spec.self, from: Data(contentsOf: URL(fileURLWithPath: args[1])))

// Register the font file for this process, then pin the variable font's weight axis.
let fontURL = URL(fileURLWithPath: spec.font) as CFURL
CTFontManagerRegisterFontsForURL(fontURL, .process, nil)
guard let descs = CTFontManagerCreateFontDescriptorsFromURL(fontURL) as? [CTFontDescriptor], let base = descs.first
else { FileHandle.standardError.write(Data("cannot load font \(spec.font)\n".utf8)); exit(1) }
let wghtTag = 0x7767_6874   // 'wght'
let desc = spec.weight.map {
    CTFontDescriptorCreateCopyWithAttributes(base, [kCTFontVariationAttribute: [wghtTag: $0]] as CFDictionary)
} ?? base

let ctx = CGContext(data: nil, width: spec.width, height: spec.height, bitsPerComponent: 8, bytesPerRow: 0,
                    space: CGColorSpace(name: CGColorSpace.sRGB)!,
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
let white = CGColor(srgbRed: 1, green: 1, blue: 1, alpha: spec.alpha ?? 1)
if let blur = spec.shadow_px, blur > 0 {
    ctx.setShadow(offset: .zero, blur: blur, color: CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 0.6))
}
for line in spec.lines {
    let font = CTFontCreateWithFontDescriptor(desc, line.size, nil)
    let attrs: [NSAttributedString.Key: Any] = [
        .font: font, .foregroundColor: white, .kern: (spec.tracking_em ?? 0) * line.size
    ]
    let ctLine = CTLineCreateWithAttributedString(NSAttributedString(string: line.text, attributes: attrs))
    let bounds = CTLineGetBoundsWithOptions(ctLine, .useGlyphPathBounds)
    let x = (line.center_x ?? Double(spec.width) / 2) - bounds.width / 2 - bounds.minX
    let y = Double(spec.height) - line.center_y - bounds.height / 2 - bounds.minY   // CG origin is bottom-left
    ctx.textPosition = CGPoint(x: x, y: y)
    CTLineDraw(ctLine, ctx)
}
let rep = NSBitmapImageRep(cgImage: ctx.makeImage()!)
try rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: args[2]))
