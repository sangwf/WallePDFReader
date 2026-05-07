import Foundation
import CoreGraphics
import CoreText
import ImageIO
import UniformTypeIdentifiers

let outDir = "Build/AppIcon.iconset"
try? FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)

let sizes: [(String, Int)] = [
    ("icon_16x16",       16),
    ("icon_16x16@2x",    32),
    ("icon_32x32",       32),
    ("icon_32x32@2x",    64),
    ("icon_128x128",    128),
    ("icon_128x128@2x", 256),
    ("icon_256x256",    256),
    ("icon_256x256@2x", 512),
    ("icon_512x512",    512),
    ("icon_512x512@2x",1024),
]

func makeIcon(_ px: Int) -> CGImage? {
    let s = CGFloat(px)
    let space = CGColorSpace(name: CGColorSpace.sRGB)!
    guard let ctx = CGContext(
        data: nil, width: px, height: px,
        bitsPerComponent: 8, bytesPerRow: 0,
        space: space,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else { return nil }

    // ---- background: rounded square with warm gradient ----
    let radius = s * 0.225
    let bgRect = CGRect(x: 0, y: 0, width: s, height: s)
    ctx.addPath(CGPath(roundedRect: bgRect, cornerWidth: radius, cornerHeight: radius, transform: nil))
    ctx.clip()

    let colors = [
        CGColor(srgbRed: 1.00, green: 0.64, blue: 0.34, alpha: 1.0), // top: warm orange
        CGColor(srgbRed: 1.00, green: 0.37, blue: 0.51, alpha: 1.0), // bottom: pink-coral
    ] as CFArray
    let grad = CGGradient(colorsSpace: space, colors: colors, locations: [0, 1])!
    ctx.drawLinearGradient(grad,
        start: CGPoint(x: 0, y: s),
        end:   CGPoint(x: 0, y: 0),
        options: [])
    ctx.resetClip()

    // ---- document with folded top-right corner ----
    let m = s * 0.21
    let dr = CGRect(x: m, y: m, width: s - 2*m, height: s - 2*m)
    let r = s * 0.04
    let fold = s * 0.18

    let doc = CGMutablePath()
    doc.move(to: CGPoint(x: dr.minX, y: dr.maxY - r))
    doc.addArc(tangent1End: CGPoint(x: dr.minX, y: dr.maxY),
               tangent2End: CGPoint(x: dr.minX + r, y: dr.maxY), radius: r)
    doc.addLine(to: CGPoint(x: dr.maxX - fold, y: dr.maxY))
    doc.addLine(to: CGPoint(x: dr.maxX,        y: dr.maxY - fold))
    doc.addLine(to: CGPoint(x: dr.maxX,        y: dr.minY + r))
    doc.addArc(tangent1End: CGPoint(x: dr.maxX, y: dr.minY),
               tangent2End: CGPoint(x: dr.maxX - r, y: dr.minY), radius: r)
    doc.addLine(to: CGPoint(x: dr.minX + r, y: dr.minY))
    doc.addArc(tangent1End: CGPoint(x: dr.minX, y: dr.minY),
               tangent2End: CGPoint(x: dr.minX, y: dr.minY + r), radius: r)
    doc.closeSubpath()

    // shadow + white fill
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -s * 0.012),
                  blur: s * 0.05,
                  color: CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 0.30))
    ctx.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))
    ctx.addPath(doc)
    ctx.fillPath()
    ctx.restoreGState()

    // fold triangle (slightly grey)
    let fpath = CGMutablePath()
    fpath.move(to: CGPoint(x: dr.maxX - fold, y: dr.maxY))
    fpath.addLine(to: CGPoint(x: dr.maxX - fold, y: dr.maxY - fold))
    fpath.addLine(to: CGPoint(x: dr.maxX,        y: dr.maxY - fold))
    fpath.closeSubpath()
    ctx.setFillColor(CGColor(srgbRed: 0.91, green: 0.91, blue: 0.93, alpha: 1.0))
    ctx.addPath(fpath)
    ctx.fillPath()

    // ---- "PDF" + "Walle" text on document (skip for tiny sizes) ----
    if px >= 64 {
        let pdfFontSize   = s * 0.20
        let walleFontSize = s * 0.085
        let gap           = s * 0.02

        let pdfFont   = CTFontCreateWithName("Helvetica-Bold"        as CFString, pdfFontSize,   nil)
        let walleFont = CTFontCreateWithName("Helvetica-BoldOblique" as CFString, walleFontSize, nil)

        let pdfColor   = CGColor(srgbRed: 0.94, green: 0.30, blue: 0.40, alpha: 1.0)
        let walleColor = CGColor(srgbRed: 0.50, green: 0.20, blue: 0.30, alpha: 1.0)

        let pdfAttrs: [CFString: Any] = [
            kCTFontAttributeName:            pdfFont,
            kCTForegroundColorAttributeName: pdfColor,
            kCTKernAttributeName:            pdfFontSize * 0.04 as CFNumber,
        ]
        let walleAttrs: [CFString: Any] = [
            kCTFontAttributeName:            walleFont,
            kCTForegroundColorAttributeName: walleColor,
            kCTKernAttributeName:            walleFontSize * 0.10 as CFNumber,
        ]

        let pdfLine   = CTLineCreateWithAttributedString(
            CFAttributedStringCreate(nil, "PDF"   as CFString, pdfAttrs   as CFDictionary)!)
        let walleLine = CTLineCreateWithAttributedString(
            CFAttributedStringCreate(nil, "Walle" as CFString, walleAttrs as CFDictionary)!)

        let pdfBounds   = CTLineGetBoundsWithOptions(pdfLine,   .useOpticalBounds)
        let walleBounds = CTLineGetBoundsWithOptions(walleLine, .useOpticalBounds)

        // Stack PDF on top, Walle below; center the whole stack on the document.
        let total      = pdfBounds.height + gap + walleBounds.height
        let stackTopY  = dr.midY + total / 2  // CG y-up: top has higher y

        let pdfBaseY   = stackTopY - pdfBounds.maxY
        ctx.textPosition = CGPoint(x: dr.midX - pdfBounds.midX, y: pdfBaseY)
        CTLineDraw(pdfLine, ctx)

        let walleBaseY = pdfBaseY + pdfBounds.minY - gap - walleBounds.maxY
        ctx.textPosition = CGPoint(x: dr.midX - walleBounds.midX, y: walleBaseY)
        CTLineDraw(walleLine, ctx)
    }

    return ctx.makeImage()
}

func writePNG(_ img: CGImage, to path: String) {
    let url = URL(fileURLWithPath: path) as CFURL
    let type = UTType.png.identifier as CFString
    guard let dest = CGImageDestinationCreateWithURL(url, type, 1, nil) else {
        FileHandle.standardError.write(Data("✗ failed to create \(path)\n".utf8))
        return
    }
    CGImageDestinationAddImage(dest, img, nil)
    CGImageDestinationFinalize(dest)
}

for (name, px) in sizes {
    guard let img = makeIcon(px) else { continue }
    writePNG(img, to: "\(outDir)/\(name).png")
    print("✓ \(name).png")
}
