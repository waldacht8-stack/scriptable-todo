// アプリのアイコン「日和」を描いて PNG にする（GitHub Actions の macOS で実行）。
// 使い方: swift Tools/MakeIcon.swift <出力先.png> [dark]
// 絵柄：地平線から昇る朝日（ふつうの表示）。dark を付けると、同じ地平線から昇る三日月と星（ダークモード）。
// iPhone のダークモードを「自動」にしていれば、日没で月、日の出で太陽に切り替わる
import AppKit
import CoreGraphics

let size = 1024
let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icon.png"
let dark = CommandLine.arguments.count > 2 && CommandLine.arguments[2] == "dark"

let cs = CGColorSpaceCreateDeviceRGB()
guard let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                          space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { fatalError("context") }

func rgb(_ hex: UInt32, _ a: CGFloat = 1) -> CGColor {
    CGColor(red: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: a)
}

let s = CGFloat(size)
// 下書きは 180 四方・上が y=0。CoreGraphics は下が y=0 なので変換する
let k = s / 180
func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x * k, y: s - y * k) }
func circle(_ x: CGFloat, _ y: CGFloat, _ r: CGFloat, _ c: CGColor) {
    let c0 = p(x, y)
    ctx.setFillColor(c)
    ctx.fillEllipse(in: CGRect(x: c0.x - r * k, y: c0.y - r * k, width: r * 2 * k, height: r * 2 * k))
}
/// 角の丸い横線（水面の光）
func bar(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ c: CGColor) {
    let r = CGRect(x: x * k, y: s - (y + 6) * k, width: w * k, height: 6 * k)
    ctx.addPath(CGPath(roundedRect: r, cornerWidth: 3 * k, cornerHeight: 3 * k, transform: nil))
    ctx.setFillColor(c)
    ctx.fillPath()
}

let horizon: CGFloat = 112   // 地平線（下書きの y）

// 空
let skyColors: [CGColor] = dark ? [rgb(0x2A2F5E), rgb(0x151832)] : [rgb(0xFFB25B), rgb(0xF0603A)]
let sky = CGGradient(colorsSpace: cs, colors: skyColors as CFArray, locations: [0, 1])!
ctx.drawLinearGradient(sky, start: CGPoint(x: 0, y: s), end: CGPoint(x: 0, y: 0), options: [])

if dark {
    // 星
    for (x, y, r) in [(40.0, 44.0, 2.5), (138.0, 36.0, 2.0), (150.0, 70.0, 1.6), (62.0, 24.0, 1.4), (24.0, 84.0, 1.4)] as [(CGFloat, CGFloat, CGFloat)] {
        circle(x, y, r, rgb(0xFFFFFF, 0.9))
    }
    // 月のまわりの淡い光
    let glow = CGGradient(colorsSpace: cs, colors: [rgb(0xF3EBCF, 0.28), rgb(0xF3EBCF, 0)] as CFArray, locations: [0, 1])!
    ctx.drawRadialGradient(glow, startCenter: p(90, horizon), startRadius: 0, endCenter: p(90, horizon), endRadius: 70 * k, options: [])
    // 三日月：満月から、空の色の円で右上を欠く
    circle(90, horizon, 40, rgb(0xF3EBCF))
    circle(106, 100, 34, rgb(0x22274F))
} else {
    // 朝日のまわりの光
    let glow = CGGradient(colorsSpace: cs, colors: [rgb(0xFFF4E0, 0.45), rgb(0xFFF4E0, 0)] as CFArray, locations: [0, 1])!
    ctx.drawRadialGradient(glow, startCenter: p(90, horizon), startRadius: 0, endCenter: p(90, horizon), endRadius: 72 * k, options: [])
    circle(90, horizon, 40, rgb(0xFFF4E0))
}

// 地平線から下（水面）
ctx.setFillColor(dark ? rgb(0x0E1026) : rgb(0xC9402A))
ctx.fill(CGRect(x: 0, y: 0, width: s, height: s - horizon * k))
let shine: UInt32 = dark ? 0xF3EBCF : 0xFFF4E0
bar(28, 124, 124, rgb(shine, dark ? 0.35 : 0.55))
bar(48, 140, 84, rgb(shine, dark ? 0.2 : 0.35))

guard let image = ctx.makeImage() else { fatalError("image") }
let rep = NSBitmapImageRep(cgImage: image)
guard let png = rep.representation(using: .png, properties: [:]) else { fatalError("png") }
try png.write(to: URL(fileURLWithPath: out))
print("wrote \(out)")
