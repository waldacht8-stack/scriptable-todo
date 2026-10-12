// アプリのアイコン「日和」を描いて PNG にする（GitHub Actions の macOS で実行）。
// 使い方: swift Tools/MakeIcon.swift <出力先.png> [dark]
// 絵柄：「日」の形の窓（枠は地の色に溶かし、4つの角丸の窓だけで「日」に見せる）。上の窓に空、下の窓に海。
//   ふつうの表示：キャメル色の地、青空に太陽と鳥、波
//   dark（ダークモード）：生成りの地、夜空に三日月と星、夜の波
// iPhone のダークモードを「自動」にしていれば、日没で夜、日の出で昼に切り替わる
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
func rect(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> CGRect {
    CGRect(x: x * k, y: s - (y + h) * k, width: w * k, height: h * k)
}
func circle(_ x: CGFloat, _ y: CGFloat, _ r: CGFloat, _ c: CGColor) {
    let c0 = p(x, y)
    ctx.setFillColor(c)
    ctx.fillEllipse(in: CGRect(x: c0.x - r * k, y: c0.y - r * k, width: r * 2 * k, height: r * 2 * k))
}
/// 波（y の高さから下を、4つのうねりで塗る）
func wave(_ y: CGFloat, _ c: CGColor) {
    ctx.beginPath()
    ctx.move(to: p(52, y))
    var x: CGFloat = 52
    for i in 0..<4 {
        let up: CGFloat = i % 2 == 0 ? -8 : 8
        ctx.addQuadCurve(to: p(x + 19, y), control: p(x + 9.5, y + up))
        x += 19
    }
    ctx.addLine(to: p(128, 150))
    ctx.addLine(to: p(52, 150))
    ctx.closePath()
    ctx.setFillColor(c)
    ctx.fillPath()
}
/// 鳥（ふたつの山の線）
func bird(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ c: CGColor, _ lw: CGFloat) {
    ctx.beginPath()
    ctx.move(to: p(x, y))
    ctx.addQuadCurve(to: p(x + w, y), control: p(x + w / 2, y - w / 2))
    ctx.addQuadCurve(to: p(x + w * 2, y), control: p(x + w * 1.5, y - w / 2))
    ctx.setStrokeColor(c)
    ctx.setLineWidth(lw * k)
    ctx.setLineCap(.round)
    ctx.strokePath()
}

// 地（枠も同じ色。窓のあいだの横線もこの色で、「日」の字になる）
let ground: UInt32 = dark ? 0xF3EBCF : 0xC29468
ctx.setFillColor(rgb(ground))
ctx.fill(CGRect(x: 0, y: 0, width: s, height: s))

// 窓（角丸の「日」の形）の中だけに描く
let window = CGPath(roundedRect: rect(52, 30, 76, 120), cornerWidth: 18 * k, cornerHeight: 18 * k, transform: nil)
ctx.saveGState()
ctx.addPath(window)
ctx.clip()

// 空
ctx.setFillColor(dark ? rgb(0x1B2045) : rgb(0x9ED2F5))
ctx.fill(rect(52, 30, 76, 60))
if dark {
    circle(108, 54, 11, rgb(0xF3EBCF))
    circle(113, 50, 9, rgb(0x1B2045))   // 欠いて三日月に
    circle(66, 44, 1.6, rgb(0xFFFFFF))
    circle(80, 66, 1.3, rgb(0xFFFFFF))
} else {
    circle(108, 54, 12, rgb(0xFFC94D))
    bird(66, 64, 8, rgb(0x24345E), 2.2)
    bird(80, 74, 6, rgb(0x24345E), 2.0)
}

// 海と波
ctx.setFillColor(dark ? rgb(0x0E1838) : rgb(0x3E8FC4))
ctx.fill(rect(52, 90, 76, 60))
wave(116, dark ? rgb(0x15214A) : rgb(0x2B6DA0))
wave(134, dark ? rgb(0x1C2A5C) : rgb(0x1D4F86))
if dark {
    // 月明かりの小さな波
    ctx.beginPath()
    ctx.move(to: p(98, 112))
    ctx.addQuadCurve(to: p(108, 112), control: p(103, 108))
    ctx.setStrokeColor(rgb(0xF3EBCF, 0.6))
    ctx.setLineWidth(2 * k)
    ctx.strokePath()
}
ctx.restoreGState()

// 「日」の横線（水平線）：地の色で窓を上下に分ける
ctx.setFillColor(rgb(ground))
ctx.fill(rect(52, 84, 76, 12))

guard let image = ctx.makeImage() else { fatalError("image") }
let rep = NSBitmapImageRep(cgImage: image)
guard let png = rep.representation(using: .png, properties: [:]) else { fatalError("png") }
try png.write(to: URL(fileURLWithPath: out))
print("wrote \(out)")
