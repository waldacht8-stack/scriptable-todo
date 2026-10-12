import SwiftUI

// MARK: - 住人の小さな絵（モグラ・流れ星・鳥・紙飛行機・風船・泡・オーロラのカーテン）。宇宙飛行士・鹿・クジラ・狐は CritterFantasy.swift
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

    // MARK: 銀河：流れ星（宇宙飛行士は CritterFantasy.swift）

    /// 流れ星（head が先頭。dir の向きに進む）
    @_optimize(none)
    static func shootingStar(_ c: GraphicsContext, head: CGPoint, dirX: Double, dirY: Double, length: Double, alpha: Double) {
        let hx: Double = Double(head.x)
        let hy: Double = Double(head.y)
        let tail = CGPoint(x: hx - dirX * length, y: hy - dirY * length)
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

    // MARK: 深海：泡

    static func bubble(_ c: GraphicsContext, _ x: Double, _ y: Double, _ r: Double, _ alpha: Double) {
        let rect = CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2)
        c.stroke(Path(ellipseIn: rect), with: .color(sceneColor(0xE8F8FF, 0.7 * alpha)), lineWidth: 1)
        D.circle(c, x - r * 0.35, y - r * 0.35, max(0.6, r * 0.25), Color.white.opacity(0.7 * alpha))
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

}
