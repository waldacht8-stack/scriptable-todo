// アプリのアイコン「日の窓」を描いて PNG にする（GitHub Actions の macOS で実行）。
// 使い方: swift Tools/MakeIcon.swift <出力先.png> <地の色 #RRGGBB> [鳥の色 #RRGGBB]
// 絵柄：「日」の形の窓。角丸の窓に上は空と太陽と鳥、下は海と波。真ん中の横線を地の色で塗って「日」の字に見せる。
// 下書きは 180 四方・上が y=0 で、1024 四方に広げて描く。角は丸めない（iOS が形を切り抜く）。
// 設定の「アプリのアイコン」の見本（App/AppIconPicker.swift の HiyoriIconMark）も同じ絵を描く。
import AppKit
import CoreGraphics

/// "#F08A6A" や "F08A6A" を数にする
func parseHex(_ text: String) -> UInt32 {
    let body: String = text.hasPrefix("#") ? String(text.dropFirst()) : text
    guard body.count == 6, let v = UInt32(body, radix: 16) else { fatalError("色は #RRGGBB で: \(text)") }
    return v
}

let args: [String] = CommandLine.arguments
guard args.count >= 3 else { fatalError("使い方: swift Tools/MakeIcon.swift <出力先.png> <地の色> [鳥の色]") }
let out: String = args[1]
let ground: UInt32 = parseHex(args[2])
let birdColor: UInt32 = args.count > 3 ? parseHex(args[3]) : 0x24345E

let size: Int = 1024
let cs: CGColorSpace = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
guard let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                          space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { fatalError("context") }

func rgb(_ hex: UInt32, _ a: CGFloat = 1) -> CGColor {
    let comps: [CGFloat] = [CGFloat((hex >> 16) & 0xFF) / 255, CGFloat((hex >> 8) & 0xFF) / 255, CGFloat(hex & 0xFF) / 255, a]
    return CGColor(colorSpace: cs, components: comps) ?? CGColor(gray: 0, alpha: 1)
}
func gradient(_ colors: [CGColor]) -> CGGradient {
    let locations: [CGFloat] = [0, 1]
    guard let g = CGGradient(colorsSpace: cs, colors: colors as CFArray, locations: locations) else { fatalError("gradient") }
    return g
}

// 180 四方・上が y=0 の座標で描けるよう、上下を返して広げる
let s: CGFloat = CGFloat(size)
ctx.translateBy(x: 0, y: s)
ctx.scaleBy(x: s / 180, y: -s / 180)

/// 縦のグラデーションで四角を塗る
func fillVertical(_ r: CGRect, _ top: UInt32, _ bottom: UInt32) {
    ctx.saveGState()
    ctx.clip(to: r)
    ctx.drawLinearGradient(gradient([rgb(top), rgb(bottom)]), start: CGPoint(x: r.midX, y: r.minY),
                           end: CGPoint(x: r.midX, y: r.maxY), options: [])
    ctx.restoreGState()
}
/// 波の上の縁（52 から 19 ずつ、上・下・上・下にうねる。SVG の q 9.5 -8 19 0 t 19 0 …）
func crest(_ y: CGFloat) -> CGMutablePath {
    let path = CGMutablePath()
    path.move(to: CGPoint(x: 52, y: y))
    for i in 0..<4 {
        let x0: CGFloat = 52 + CGFloat(i) * 19
        let dy: CGFloat = i % 2 == 0 ? -8 : 8
        path.addQuadCurve(to: CGPoint(x: x0 + 19, y: y), control: CGPoint(x: x0 + 9.5, y: y + dy))
    }
    return path
}
/// 波（縁から下を塗り、縁に明るい線を引く）
func wave(_ y: CGFloat, _ fill: UInt32, crestAlpha: CGFloat) {
    let body: CGMutablePath = crest(y)
    body.addLine(to: CGPoint(x: 128, y: 150))
    body.addLine(to: CGPoint(x: 52, y: 150))
    body.closeSubpath()
    ctx.addPath(body)
    ctx.setFillColor(rgb(fill))
    ctx.fillPath()
    ctx.addPath(crest(y))
    ctx.setStrokeColor(rgb(0xCDEBFB, crestAlpha))
    ctx.setLineWidth(2)
    ctx.setLineCap(.round)
    ctx.strokePath()
}
/// 鳥（ふたつの山の線）。w は山ひとつの幅
func bird(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ width: CGFloat) {
    ctx.beginPath()
    ctx.move(to: CGPoint(x: x, y: y))
    ctx.addQuadCurve(to: CGPoint(x: x + w, y: y), control: CGPoint(x: x + w / 2, y: y - w / 2))
    ctx.addQuadCurve(to: CGPoint(x: x + w * 2, y: y), control: CGPoint(x: x + w * 1.5, y: y - w / 2))
    ctx.setStrokeColor(rgb(birdColor))
    ctx.setLineWidth(width)
    ctx.setLineCap(.round)
    ctx.setLineJoin(.round)
    ctx.strokePath()
}

// 地（全面）
ctx.setFillColor(rgb(ground))
ctx.fill(CGRect(x: 0, y: 0, width: 180, height: 180))

// 窓（角丸）の中だけに描く
let window = CGPath(roundedRect: CGRect(x: 52, y: 30, width: 76, height: 120), cornerWidth: 18, cornerHeight: 18, transform: nil)
ctx.saveGState()
ctx.addPath(window)
ctx.clip()

// 空・太陽のぼんやりした光・太陽・鳥
fillVertical(CGRect(x: 52, y: 30, width: 76, height: 60), 0x7EC6F2, 0xCDEBFB)
let sun = CGPoint(x: 108, y: 54)
ctx.drawRadialGradient(gradient([rgb(0xFFF1B8, 0.9), rgb(0xFFF1B8, 0)]), startCenter: sun, startRadius: 0,
                       endCenter: sun, endRadius: 24, options: [])
ctx.setFillColor(rgb(0xFFC94D))
ctx.fillEllipse(in: CGRect(x: sun.x - 11, y: sun.y - 11, width: 22, height: 22))
bird(64, 64, 8, 2.4)
bird(80, 75, 6, 2)

// 海と波
fillVertical(CGRect(x: 52, y: 90, width: 76, height: 60), 0x3F95CC, 0x1B5590)
wave(116, 0x2C73AE, crestAlpha: 0.7)
wave(134, 0x1B5590, crestAlpha: 0.5)
ctx.restoreGState()

// 「日」の横線：地の色で窓を上下に分ける
ctx.setFillColor(rgb(ground))
ctx.fill(CGRect(x: 52, y: 84, width: 76, height: 12))

guard let image = ctx.makeImage() else { fatalError("image") }
let rep = NSBitmapImageRep(cgImage: image)
guard let png = rep.representation(using: .png, properties: [:]) else { fatalError("png") }
try png.write(to: URL(fileURLWithPath: out))
print("wrote \(out)")
