import SwiftUI

// MARK: - 住人の絵（どれも原点のまわりに、図形を数個だけで描く。向き・大きさは CritterDraw.local で決める）
// 色はこのファイルの中の決まった色だけ（sceneColor）。重い計算はしないが、型推論が重くならないよう最適化を外す。

enum Critters {
    typealias D = CritterDraw

    // MARK: 地層：モグラ（右向き。幅 24・高さ 14 くらい）

    @_optimize(none)
    static func mole(_ c: GraphicsContext, t: Double, digging: Bool) {
        let body: Color = sceneColor(0x4A3426)
        let pink: Color = sceneColor(0xF2A7A0)
        let dig: Double = digging ? sin(t * 10) * 1.6 : 0
        D.circle(c, -11, 1, 1.6, body)                       // しっぽ
        D.ellipse(c, 0, 0, 22, 14, body)                     // からだ
        D.ellipse(c, -2, -3, 12, 5, sceneColor(0x6B4E3A, 0.8))   // 背中のつや
        D.ellipse(c, 11, 1.2, 7, 5, pink)                    // 鼻先
        D.circle(c, 14.2, 0.6, 1.5, sceneColor(0xD9707A))    // 鼻
        D.circle(c, 6, -2.6, 1.1, Color.white.opacity(0.9))  // 目
        D.ellipse(c, 7 + dig, 6, 6, 3.6, pink)               // 前足（掘る）
        D.ellipse(c, 3 - dig, 6.4, 5, 3.2, pink)
    }

    /// 掘った土のかたまり（完了の反応で、顔を出した上にこぼれる）
    @_optimize(none)
    static func soilMound(_ c: GraphicsContext, width: Double) {
        var path = Path()
        path.move(to: D.pt(-width / 2, 0))
        path.addQuadCurve(to: D.pt(width / 2, 0), control: D.pt(0, -width * 0.55))
        path.closeSubpath()
        c.fill(path, with: .color(sceneColor(0x8E5F36)))
        D.circle(c, -width * 0.2, -width * 0.12, 1.4, sceneColor(0x5E4129))
        D.circle(c, width * 0.15, -width * 0.18, 1.1, sceneColor(0xC99A62))
    }

    // MARK: 銀河：宇宙飛行士（幅 20・高さ 28 くらい。原点はおなか）

    @_optimize(none)
    static func astronaut(_ c: GraphicsContext, t: Double) {
        let suit: Color = sceneColor(0xF4F4FA)
        let shade: Color = sceneColor(0xB8BEDD)
        let wave: Double = sin(t * 1.4) * 1.5
        let back = Path(roundedRect: CGRect(x: -7.5, y: -5, width: 15, height: 13), cornerRadius: 3)
        c.fill(back, with: .color(shade))                                       // 背中の装置
        D.line(c, D.pt(-6, -1), D.pt(-10.5, 4 + wave), suit, 3.6)               // 腕
        D.line(c, D.pt(6, -1), D.pt(10.5, -4 - wave), suit, 3.6)
        let legL = Path(roundedRect: CGRect(x: -5.2, y: 7, width: 4.6, height: 7.5), cornerRadius: 2.2)
        let legR = Path(roundedRect: CGRect(x: 0.6, y: 7, width: 4.6, height: 7.5), cornerRadius: 2.2)
        c.fill(legL, with: .color(suit))
        c.fill(legR, with: .color(suit))
        let torso = Path(roundedRect: CGRect(x: -6, y: -4, width: 12, height: 12.5), cornerRadius: 4)
        c.fill(torso, with: .color(suit))
        c.fill(Path(CGRect(x: -2, y: 0.5, width: 4, height: 3)), with: .color(sceneColor(0xFFD9A8)))   // 胸の印
        D.circle(c, 0, -10, 7.2, suit)                                          // ヘルメット
        D.ellipse(c, 1.2, -10, 9.5, 6.6, sceneColor(0x2E3A8C))                  // バイザー
        D.ellipse(c, -0.8, -11.6, 3.2, 1.8, Color.white.opacity(0.75))
    }

    /// 流れ星（head が先頭。dir の向きに進む）
    @_optimize(none)
    static func shootingStar(_ c: GraphicsContext, head: CGPoint, dirX: Double, dirY: Double, length: Double, alpha: Double) {
        let tail = CGPoint(x: head.x - dirX * length, y: head.y - dirY * length)
        var path = Path()
        path.move(to: tail)
        path.addLine(to: head)
        let g = Gradient(colors: [Color.white.opacity(0), sceneColor(0xFFE4B8, 0.9 * alpha)])
        c.stroke(path, with: .linearGradient(g, startPoint: tail, endPoint: head), style: StrokeStyle(lineWidth: 2.2, lineCap: .round))
        D.glow(c, head.x, head.y, 9, sceneColor(0xFFE4B8), 0.55 * alpha)
        D.circle(c, head.x, head.y, 2.2, Color.white.opacity(alpha))
    }

    // MARK: 空：鳥・紙飛行機・風船

    /// 鳥（羽ばたく「へ」の字。幅 10）
    static func bird(_ c: GraphicsContext, flap: Double, color: Color) {
        var path = Path()
        path.move(to: D.pt(-5, -1 - flap))
        path.addQuadCurve(to: D.pt(0, 0), control: D.pt(-2.6, -3 - flap))
        path.addQuadCurve(to: D.pt(5, -1 - flap), control: D.pt(2.6, -3 - flap))
        c.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
    }

    /// 紙飛行機（右向き。幅 20）
    @_optimize(none)
    static func paperPlane(_ c: GraphicsContext, dark: Bool) {
        let top: Color = dark ? sceneColor(0xEEF2FF, 0.85) : Color.white
        let under: Color = dark ? sceneColor(0xBAC3E8, 0.7) : sceneColor(0xD3DFEC)
        let fold: Color = dark ? sceneColor(0x6B76A8) : sceneColor(0x8FA3BA)
        D.polygon(c, [D.pt(10, 0), D.pt(-10, -6), D.pt(-4, 0)], top)
        D.polygon(c, [D.pt(10, 0), D.pt(-4, 0), D.pt(-7.5, 4.5)], under)
        D.line(c, D.pt(10, 0), D.pt(-4, 0), fold, 0.7)
    }

    /// 風船（原点は風船の中心。ひもは下へ）
    @_optimize(none)
    static func balloon(_ c: GraphicsContext, sway: Double) {
        D.curve(c, D.pt(0, 8.5), D.pt(3 + sway * 4, 17), D.pt(-1 + sway * 2, 27), sceneColor(0x6B6B78, 0.8), 0.8)
        D.polygon(c, [D.pt(-1.8, 9.4), D.pt(1.8, 9.4), D.pt(0, 7)], sceneColor(0xD94A5C))
        D.ellipse(c, 0, 0, 13, 16, sceneColor(0xFF6B7A))
        D.ellipse(c, -2.8, -3.4, 3.2, 4.6, Color.white.opacity(0.55))
    }

    // MARK: 霧：鹿と灯り

    /// 鹿のシルエット（左向き。足元が原点。幅 36・高さ 42 くらい）
    @_optimize(none)
    static func deer(_ c: GraphicsContext, walk: Double, color: Color) {
        let legs: [(Double, Double)] = [(-8, 0), (-5, 2.4), (6, 1.2), (9, 3.6)]
        for (x, off) in legs {
            let swing: Double = sin(walk + off) * 2.6
            D.line(c, D.pt(x, -14), D.pt(x + swing, 0), color, 1.9)
        }
        D.ellipse(c, 0.5, -18, 25, 11, color)                               // からだ
        D.ellipse(c, 12.5, -21, 3.4, 4.2, color)                            // しっぽ
        D.curve(c, D.pt(-8, -21), D.pt(-11, -26), D.pt(-13, -30), color, 5)  // 首
        D.ellipse(c, -15, -31.5, 8.5, 5.4, color)                           // 頭
        D.ellipse(c, -18.6, -30.4, 4.4, 3.2, color)                         // 鼻先
        D.ellipse(c, -11.6, -34.4, 4, 1.9, color)                           // 耳
        D.line(c, D.pt(-14.5, -34), D.pt(-14, -42), color, 1.2)             // 角
        D.line(c, D.pt(-14.2, -39), D.pt(-17.4, -41.5), color, 1.1)
        D.line(c, D.pt(-12.6, -33.6), D.pt(-9.6, -40.5), color, 1.2)
        D.line(c, D.pt(-11, -37.4), D.pt(-7.2, -38.4), color, 1.1)
    }

    /// 吊るした灯り（原点が吊り下げの点。swing はラジアン、flare は 0〜1 の明るさの上乗せ）
    @_optimize(none)
    static func lantern(_ c: GraphicsContext, swing: Double, flare: Double, ground: Double) {
        let post: Color = sceneColor(0x3E4A55, 0.6)
        D.line(c, D.pt(-7, ground), D.pt(-7, -3), post, 1.8)    // 柱
        D.line(c, D.pt(-7, -3), D.pt(1, -3), post, 1.4)         // 腕
        let lx: Double = 1 + sin(swing) * 10
        let ly: Double = -3 + cos(swing) * 10
        D.line(c, D.pt(1, -3), D.pt(lx, ly - 4), post, 0.8)
        D.glow(c, lx, ly, 24 + flare * 18, sceneColor(0xFFC77A), 0.5 + flare * 0.35)
        let body = Path(roundedRect: CGRect(x: lx - 3, y: ly - 4, width: 6, height: 8), cornerRadius: 1.6)
        c.fill(body, with: .color(sceneColor(0xFFD9A0)))
        c.stroke(body, with: .color(sceneColor(0x5A4A3A, 0.7)), lineWidth: 0.8)
    }

    // MARK: 深海：クジラ・チョウチンアンコウ・泡

    /// クジラ（左向き。長さ 96 くらい。原点はからだの中心）
    @_optimize(none)
    static func whale(_ c: GraphicsContext, t: Double) {
        var path = Path()
        path.move(to: D.pt(-46, 1))
        path.addQuadCurve(to: D.pt(-20, -14), control: D.pt(-45, -14))
        path.addQuadCurve(to: D.pt(26, -6), control: D.pt(6, -15))
        path.addQuadCurve(to: D.pt(40, -2), control: D.pt(34, -3))
        let flick: Double = sin(t * 0.9) * 2.5
        path.addQuadCurve(to: D.pt(50, -11 + flick), control: D.pt(45, -4))
        path.addQuadCurve(to: D.pt(45, 1), control: D.pt(51, -3))
        path.addQuadCurve(to: D.pt(50, 11 + flick), control: D.pt(49, 6))
        path.addQuadCurve(to: D.pt(38, 3), control: D.pt(43, 4))
        path.addQuadCurve(to: D.pt(-20, 12), control: D.pt(6, 13))
        path.addQuadCurve(to: D.pt(-46, 1), control: D.pt(-43, 11))
        path.closeSubpath()
        c.fill(path, with: .color(sceneColor(0x1B5C80, 0.78)))
        c.stroke(path, with: .color(sceneColor(0x7DF9E6, 0.18)), lineWidth: 1)
        for i in 0..<3 {
            let y: Double = 5.5 + Double(i) * 2
            D.line(c, D.pt(-36 + Double(i) * 2, y), D.pt(-2 - Double(i) * 4, y + 2), sceneColor(0xC8EAF5, 0.16), 0.8)
        }
        D.ellipse(c, -14, 9, 12, 4, sceneColor(0x154A68, 0.9))   // ひれ
        D.circle(c, -33, -1.5, 1.3, sceneColor(0xC8EAF5, 0.8))   // 目
    }

    /// チョウチンアンコウ（右向き。原点はからだ。glow は提灯の明るさ 0〜1）
    @_optimize(none)
    static func angler(_ c: GraphicsContext, glow: Double) {
        D.polygon(c, [D.pt(-8, 0), D.pt(-15, -5), D.pt(-15, 5)], sceneColor(0x123247))   // 尾
        D.ellipse(c, 0, 0, 19, 15, sceneColor(0x123247))
        let rim = Path(ellipseIn: CGRect(x: -9.5, y: -7.5, width: 19, height: 15))
        c.stroke(rim, with: .color(sceneColor(0x2C6A88, 0.7)), lineWidth: 0.8)
        var teeth = Path()
        teeth.move(to: D.pt(5, 1.5))
        teeth.addLine(to: D.pt(6.5, 3.5))
        teeth.addLine(to: D.pt(7.5, 1.5))
        teeth.addLine(to: D.pt(8.5, 3.3))
        c.stroke(teeth, with: .color(Color.white.opacity(0.75)), lineWidth: 0.7)
        D.circle(c, 3.6, -2.8, 1.6, sceneColor(0xC8EAF5))
        D.curve(c, D.pt(1, -7), D.pt(7, -19), D.pt(12.5, -12.5), sceneColor(0x2C6A88), 0.9)
        D.glow(c, 12.5, -12.5, 13, sceneColor(0x7DF9E6), 0.35 + glow * 0.35)
        D.circle(c, 12.5, -12.5, 2.1, sceneColor(0xD8FFF8))
    }

    static func bubble(_ c: GraphicsContext, _ x: Double, _ y: Double, _ r: Double, _ alpha: Double) {
        let rect = CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2)
        c.stroke(Path(ellipseIn: rect), with: .color(sceneColor(0xE8F8FF, 0.7 * alpha)), lineWidth: 1)
        D.circle(c, x - r * 0.35, y - r * 0.35, max(0.6, r * 0.25), Color.white.opacity(0.7 * alpha))
    }

    // MARK: 日なた：猫

    /// 丸くなった猫 ⇄ 伸び（stretch 0 = 丸く、1 = 伸び）。左向き。足元が原点。幅 32 くらい
    @_optimize(none)
    static func cat(_ c: GraphicsContext, stretch s: Double, breathe: Double) {
        let fur: Color = sceneColor(0xE39B52)
        let dark: Color = sceneColor(0xB86A2C)
        let lerp: (Double, Double) -> Double = { a, b in a + (b - a) * s }
        let bodyW: Double = lerp(30, 34) + breathe * 0.6
        let bodyH: Double = lerp(14, 10) + breathe * 0.5
        let bodyX: Double = lerp(1, 3)
        let bodyY: Double = lerp(-7, -10)
        // 伸びの足（伸びるほど見える）
        if s > 0.05 {
            let legColor: Color = fur.opacity(min(1, s * 1.6))
            D.line(c, D.pt(-8, -7), D.pt(lerp(-8, -22), lerp(-2, -1)), legColor, 3)
            D.line(c, D.pt(13, -8), D.pt(14, -1), legColor, 3)
        }
        // しっぽ（丸いときは体に巻き、伸びると上へ）
        let tailEnd = D.pt(lerp(-7, 24), lerp(-1.5, -24))
        let tailControl = D.pt(lerp(9, 22), lerp(2, -14))
        D.curve(c, D.pt(14, lerp(-5, -11)), tailControl, tailEnd, dark, 3.6)
        D.ellipse(c, bodyX, bodyY, bodyW, bodyH, fur)
        for i in 0..<3 {
            let x: Double = bodyX - 2 + Double(i) * 5.5
            D.curve(c, D.pt(x, bodyY - bodyH / 2 + 1), D.pt(x + 1.5, bodyY - 1), D.pt(x, bodyY + 1.5), dark.opacity(0.7), 1.3)
        }
        let hx: Double = lerp(-11, -18)
        let hy: Double = lerp(-9.5, -12)
        D.polygon(c, [D.pt(hx - 5, hy - 3), D.pt(hx - 3.5, hy - 9.5), D.pt(hx - 0.5, hy - 4.5)], fur)
        D.polygon(c, [D.pt(hx + 0.5, hy - 4.5), D.pt(hx + 3.5, hy - 9.5), D.pt(hx + 5, hy - 3)], fur)
        D.circle(c, hx, hy, 6.4, fur)
        D.ellipse(c, hx - 1, hy + 2.6, 5, 3, sceneColor(0xFFE3B8))   // 口もと
        // 目（丸いときは閉じた目、伸びたときも気持ちよさそうに細め）
        D.curve(c, D.pt(hx - 4, hy - 0.5), D.pt(hx - 3, hy + 0.8), D.pt(hx - 1.8, hy - 0.5), dark, 1)
        D.curve(c, D.pt(hx + 0.6, hy - 0.5), D.pt(hx + 1.7, hy + 0.8), D.pt(hx + 2.8, hy - 0.5), dark, 1)
    }

    /// 座った猫（正面寄り。足元が原点。高さ 22）
    @_optimize(none)
    static func catSitting(_ c: GraphicsContext) {
        let fur: Color = sceneColor(0xE39B52)
        let dark: Color = sceneColor(0xB86A2C)
        D.curve(c, D.pt(5, -2), D.pt(13, -2), D.pt(11, -10), dark, 3)
        D.ellipse(c, 0, -6.5, 13, 13, fur)
        D.polygon(c, [D.pt(-5, -16), D.pt(-4, -23), D.pt(-0.5, -18.5)], fur)
        D.polygon(c, [D.pt(0.5, -18.5), D.pt(4, -23), D.pt(5, -16)], fur)
        D.circle(c, 0, -16, 5.4, fur)
        D.circle(c, -2, -16.4, 0.8, dark)
        D.circle(c, 2, -16.4, 0.8, dark)
        D.ellipse(c, 0, -1.5, 8, 3, sceneColor(0xFFE3B8))
    }

    // MARK: オーロラ：狐

    /// 走る狐（右向き。足元が原点。幅 40）
    @_optimize(none)
    static func fox(_ c: GraphicsContext, run: Double) {
        let fur: Color = sceneColor(0xFF9D5C)
        let dark: Color = sceneColor(0xC45E2A)
        let a: Double = sin(run) * 4
        D.line(c, D.pt(-7, -6), D.pt(-9 - a, 0), dark, 2)
        D.line(c, D.pt(-4, -6), D.pt(-2 + a, 0), dark, 2)
        D.line(c, D.pt(5, -6), D.pt(3 + a, 0), dark, 2)
        D.line(c, D.pt(8, -6), D.pt(11 - a, 0), dark, 2)
        var tail = Path()
        tail.move(to: D.pt(-9, -9))
        tail.addQuadCurve(to: D.pt(-25, -13 - a * 0.4), control: D.pt(-17, -17))
        tail.addQuadCurve(to: D.pt(-9, -6), control: D.pt(-18, -6))
        tail.closeSubpath()
        c.fill(tail, with: .color(fur))
        D.ellipse(c, -24, -12.8 - a * 0.4, 5, 4, Color.white.opacity(0.92))   // しっぽの先
        D.ellipse(c, 0, -9, 21, 8.5, fur)
        D.polygon(c, [D.pt(8, -13), D.pt(19, -9.5), D.pt(8, -6.5)], fur)       // 鼻先
        D.circle(c, 10, -10.5, 4.6, fur)
        D.polygon(c, [D.pt(7.5, -13.5), D.pt(8.5, -19), D.pt(11, -14)], dark)
        D.polygon(c, [D.pt(11, -14), D.pt(13.5, -18.5), D.pt(14, -13)], dark)
        D.ellipse(c, 13, -8, 6, 2.6, Color.white.opacity(0.8))                // 白いあご
        D.circle(c, 12, -11.4, 0.9, sceneColor(0x1E1638))
        D.circle(c, 19, -9.5, 0.9, sceneColor(0x1E1638))
    }

    // MARK: ネオブルータル：シールとはんこ

    /// シール（kind 0 星・1 ハート・2 丸・3 いなずま）。太い黒枠とずらした影。大きさ 24
    @_optimize(none)
    static func sticker(_ c: GraphicsContext, kind: Int) {
        let colors: [UInt32] = [0xFFD23F, 0xFF7EB6, 0x3BCEAC, 0xFF8A3D]
        let fill: Color = sceneColor(colors[kind % colors.count])
        let path: Path = stickerPath(kind % 4)
        var shadow: GraphicsContext = c
        shadow.translateBy(x: 2.5, y: 2.5)
        shadow.fill(path, with: .color(Color.black))
        c.fill(path, with: .color(fill))
        c.stroke(path, with: .color(Color.black), style: StrokeStyle(lineWidth: 2.2, lineJoin: .round))
    }

    static func stickerPath(_ kind: Int) -> Path {
        var p = Path()
        switch kind {
        case 0:
            for i in 0..<10 {
                let r: Double = i % 2 == 0 ? 12 : 5.4
                let a: Double = Double(i) * Double.pi / 5 - Double.pi / 2
                let pt = CGPoint(x: cos(a) * r, y: sin(a) * r)
                if i == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
            }
            p.closeSubpath()
        case 1:
            p.move(to: CGPoint(x: 0, y: 10))
            p.addCurve(to: CGPoint(x: 0, y: -5), control1: CGPoint(x: -14, y: 1), control2: CGPoint(x: -8, y: -13))
            p.addCurve(to: CGPoint(x: 0, y: 10), control1: CGPoint(x: 8, y: -13), control2: CGPoint(x: 14, y: 1))
            p.closeSubpath()
        case 2:
            p.addEllipse(in: CGRect(x: -10, y: -10, width: 20, height: 20))
        default:
            p.move(to: CGPoint(x: 3, y: -12))
            p.addLine(to: CGPoint(x: -7, y: 2))
            p.addLine(to: CGPoint(x: -0.5, y: 2))
            p.addLine(to: CGPoint(x: -3, y: 12))
            p.addLine(to: CGPoint(x: 7, y: -2))
            p.addLine(to: CGPoint(x: 0.5, y: -2))
            p.closeSubpath()
        }
        return p
    }

    /// 「済」のはんこ（赤い二重丸。大きさ 26）
    @_optimize(none)
    static func stamp(_ c: GraphicsContext, alpha: Double) {
        let red: Color = sceneColor(0xD7263D, 0.9 * alpha)
        c.stroke(Path(ellipseIn: CGRect(x: -13, y: -13, width: 26, height: 26)), with: .color(red), lineWidth: 2.4)
        c.stroke(Path(ellipseIn: CGRect(x: -9.5, y: -9.5, width: 19, height: 19)), with: .color(red), lineWidth: 0.9)
        let label = Text("済").font(.system(size: 12, weight: .black)).foregroundColor(red)
        c.draw(label, at: CGPoint(x: 0, y: 0.5))
    }

    // MARK: オーロラ：光のカーテン（横に流れる帯。ぼかさず縦のグラデーションで）

    @_optimize(none)
    static func auroraCurtain(_ ctx: GraphicsContext, width w: Double, top: Double, amp: Double, thick: Double,
                              wave: Double, phase: Double, color: Color, alpha: Double) {
        let steps: Int = 24
        var path = Path()
        var lower: [CGPoint] = []
        for s in 0...steps {
            let fx: Double = Double(s) / Double(steps)
            let a: Double = sin(fx * wave * 2 * Double.pi + phase) * amp
            let b: Double = sin(fx * wave * 4.6 * Double.pi - phase * 1.3) * amp * 0.35
            let y: Double = top + a + b
            let pt = CGPoint(x: fx * w, y: y)
            if s == 0 { path.move(to: pt) } else { path.addLine(to: pt) }
            let fold: Double = sin(fx * 9 + phase * 0.7) * thick * 0.18
            lower.append(CGPoint(x: fx * w, y: y + thick + fold))
        }
        for pt in lower.reversed() { path.addLine(to: pt) }
        path.closeSubpath()
        let g = Gradient(stops: [
            Gradient.Stop(color: color.opacity(0), location: 0),
            Gradient.Stop(color: color.opacity(alpha), location: 0.22),
            Gradient.Stop(color: color.opacity(alpha * 0.35), location: 0.6),
            Gradient.Stop(color: color.opacity(0), location: 1),
        ])
        let start = CGPoint(x: 0, y: top - amp * 1.4)
        let end = CGPoint(x: 0, y: top + amp + thick * 1.2)
        ctx.fill(path, with: .linearGradient(g, startPoint: start, endPoint: end))
    }

    // MARK: ベント：小さなタイルの箱

    /// タイルの色（5枚。6つ目の枠は空き）
    static let bentoColors: [UInt32] = [0x1F3D36, 0xE9B44C, 0xD9643A, 0xA7C4A0, 0xF4EFE6]

    /// 6つの枠への並べ方（タイル i をどの枠に置くか）
    static let bentoOrders: [[Int]] = [
        [0, 1, 2, 3, 4], [1, 0, 2, 3, 5], [1, 0, 4, 3, 5],
        [3, 0, 4, 1, 5], [3, 2, 4, 1, 0], [0, 2, 3, 1, 4],
    ]

    /// 枠 slot の左上（3列×2段。cell は1枠の大きさ）
    static func bentoSlot(_ slot: Int, cell: Double, gap: Double) -> CGPoint {
        let col: Int = slot % 3
        let row: Int = slot / 3
        return CGPoint(x: Double(col) * (cell + gap), y: Double(row) * (cell + gap))
    }

    /// 1枚のタイル（中心 c、大きさ size、ぽこっと膨らむ pop）
    static func bentoTile(_ ctx: GraphicsContext, center: CGPoint, size: Double, color: Color, pop: Double) {
        let s: Double = size * (1 + pop)
        let rect = CGRect(x: center.x - s / 2, y: center.y - s / 2, width: s, height: s)
        let path = Path(roundedRect: rect, cornerRadius: s * 0.24)
        ctx.fill(path, with: .color(color))
        ctx.stroke(path, with: .color(sceneColor(0x1E1B16, 0.14)), lineWidth: 0.8)
    }

    // MARK: スイス：時計の針のように回る図形

    /// 円と針（hour・minute・second はラジアン。12時が 0）。原点が中心。半径 18
    @_optimize(none)
    static func swissDial(_ c: GraphicsContext, hour: Double, minute: Double, second: Double?, radius r: Double) {
        let ink: Color = sceneColor(0x111111)
        let red: Color = sceneColor(0xD71F16)
        c.stroke(Path(ellipseIn: CGRect(x: -r, y: -r, width: r * 2, height: r * 2)), with: .color(ink), lineWidth: max(1, r * 0.08))
        for i in 0..<4 {
            let a: Double = Double(i) * Double.pi / 2
            let outer = CGPoint(x: sin(a) * r * 0.9, y: -cos(a) * r * 0.9)
            let inner = CGPoint(x: sin(a) * r * 0.72, y: -cos(a) * r * 0.72)
            D.line(c, inner, outer, ink, max(1, r * 0.07))
        }
        D.line(c, D.pt(0, 0), D.pt(sin(hour) * r * 0.5, -cos(hour) * r * 0.5), ink, max(1.6, r * 0.14))
        D.line(c, D.pt(0, 0), D.pt(sin(minute) * r * 0.78, -cos(minute) * r * 0.78), ink, max(1, r * 0.08))
        if let second {
            D.line(c, D.pt(-sin(second) * r * 0.2, cos(second) * r * 0.2), D.pt(sin(second) * r * 0.86, -cos(second) * r * 0.86), red, max(0.8, r * 0.05))
        }
        D.circle(c, 0, 0, max(1.2, r * 0.09), red)
    }
}
