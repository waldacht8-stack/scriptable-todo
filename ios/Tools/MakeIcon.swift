// アプリのアイコン「日和」を描いて PNG にする（GitHub Actions の macOS で実行）。
// 使い方: swift Tools/MakeIcon.swift <出力先.png>
// 絵柄：朝焼けの空に、地平線から昇る朝日。朝日の上に、光の筋のようなチェックマーク。
import AppKit
import CoreGraphics

let size = 1024
let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icon.png"

let cs = CGColorSpaceCreateDeviceRGB()
guard let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                          space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { fatalError("context") }

func rgb(_ hex: UInt32, _ a: CGFloat = 1) -> CGColor {
    CGColor(red: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: a)
}

let s = CGFloat(size)
// CoreGraphics は下が y=0。地平線は下から 34% の高さ
let horizon = s * 0.34

// 空：上の藍色から地平線の朝焼け色へ
let sky = CGGradient(colorsSpace: cs, colors: [rgb(0xF6A27A), rgb(0xE9767A), rgb(0x5A4A9C), rgb(0x2A2E6E)] as CFArray,
                     locations: [0, 0.22, 0.62, 1])!
ctx.drawLinearGradient(sky, start: CGPoint(x: 0, y: horizon), end: CGPoint(x: 0, y: s), options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])

// 朝日（地平線の上に半分出ている）とまわりの光
let sunCenter = CGPoint(x: s / 2, y: horizon)
let glow = CGGradient(colorsSpace: cs, colors: [rgb(0xFFE7A0, 0.85), rgb(0xFFC97A, 0)] as CFArray, locations: [0, 1])!
ctx.drawRadialGradient(glow, startCenter: sunCenter, startRadius: 0, endCenter: sunCenter, endRadius: s * 0.48, options: [])
ctx.setFillColor(rgb(0xFFD65C))
ctx.fillEllipse(in: CGRect(x: sunCenter.x - s * 0.22, y: sunCenter.y - s * 0.22, width: s * 0.44, height: s * 0.44))

// 光の筋（左右に短い線）
ctx.setStrokeColor(rgb(0xFFE9B0, 0.9))
ctx.setLineCap(.round)
ctx.setLineWidth(s * 0.028)
for angle in [168.0, 145.0, 35.0, 12.0] {
    let a = angle * .pi / 180
    let r1 = s * 0.28, r2 = s * 0.36
    ctx.move(to: CGPoint(x: sunCenter.x + cos(a) * r1, y: sunCenter.y + sin(a) * r1))
    ctx.addLine(to: CGPoint(x: sunCenter.x + cos(a) * r2, y: sunCenter.y + sin(a) * r2))
}
ctx.strokePath()

// 大地（地平線から下）：やわらかいクリーム色の丘
ctx.setFillColor(rgb(0xFFF3E2))
ctx.move(to: CGPoint(x: 0, y: horizon + s * 0.02))
ctx.addQuadCurve(to: CGPoint(x: s, y: horizon + s * 0.02), control: CGPoint(x: s / 2, y: horizon - s * 0.05))
ctx.addLine(to: CGPoint(x: s, y: 0))
ctx.addLine(to: CGPoint(x: 0, y: 0))
ctx.closePath()
ctx.fillPath()

// チェックマーク（朝日の上に、光の筋のように）
ctx.setStrokeColor(rgb(0xFFFFFF))
ctx.setLineWidth(s * 0.075)
ctx.setLineJoin(.round)
ctx.move(to: CGPoint(x: s * 0.33, y: s * 0.64))
ctx.addLine(to: CGPoint(x: s * 0.45, y: s * 0.52))
ctx.addLine(to: CGPoint(x: s * 0.70, y: s * 0.80))
ctx.strokePath()

guard let image = ctx.makeImage() else { fatalError("image") }
let rep = NSBitmapImageRep(cgImage: image)
guard let png = rep.representation(using: .png, properties: [:]) else { fatalError("png") }
try png.write(to: URL(fileURLWithPath: out))
print("wrote \(out)")
