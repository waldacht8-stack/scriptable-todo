import SwiftUI

// MARK: - 結晶・墨流しの住人の層（完了の反応・ウィジェットの下の余白の小さな絵・起床の輪）
// 結晶：完了すると、かけらが下から飛んで結晶の次の面にはまり、きらりと光る（星が散る）。
// 墨流し：完了すると、しずくが水面に落ちて藍と朱の輪に広がる。
// ウィジェットは下の余白（16pt）だけを通る：結晶は小さな宝石と星、墨流しは小さな墨の輪。位置は entry.date で決まる。

extension CritterArt {
    /// 今日完了した数（反応の行き先の面を決める。1秒ごとに読み直す）
    nonisolated(unsafe) private static var doneCache: (at: Date, done: Int) = (Date.distantPast, 0)

    @_optimize(none)
    static func doneToday() -> Int {
        let now: Date = Date()
        if now.timeIntervalSince(doneCache.at) > 1 {
            doneCache = (now, WorldDayCount.now(now).done)
        }
        return doneCache.done
    }

    // MARK: 結晶：かけらが飛んで面にはまり、光る

    @_optimize(none)
    static func crystal(_ ctx: GraphicsContext, size: CGSize, k: CritterKnobs, layer: Layer) {
        guard layer == .reaction, let r = k.react else { return }
        let f = CrystalScene.frame(size, compact: false)
        let c: CGPoint = f.center
        let s: Double = f.scale
        let done: Int = max(1, doneToday())
        let slot: Int = min(CrystalScene.facetTotal, done) - 1
        let i: Int = CrystalScene.growOrder[slot]
        let a: CGPoint = CrystalScene.point(c, s, CrystalScene.rim[i])
        let b: CGPoint = CrystalScene.point(c, s, CrystalScene.rim[(i + 1) % CrystalScene.rim.count])
        let tx: Double = (Double(c.x) + Double(a.x) + Double(b.x)) / 3
        let ty: Double = (Double(c.y) + Double(a.y) + Double(b.y)) / 3
        let w: Double = Double(size.width)
        let h: Double = Double(size.height)
        // 「完了 →」のあたりから、弧を描いて結晶へ飛ぶ
        let sx: Double = w * 0.84
        let sy: Double = h * 0.735
        let mx: Double = (sx + tx) / 2
        let my: Double = min(sy, ty) - 36   // 低い弧（カードの裏に隠れないように）
        // 飛ぶ（0〜0.55）
        let u: Double = D.ease(D.span(r, 0, 0.55))
        if r < 0.56 {
            for j in stride(from: 7, through: 1, by: -1) {
                let v: Double = max(0, u - Double(j) * 0.035)
                let px: Double = bez(sx, mx, tx, v)
                let py: Double = bez(sy, my, ty, v)
                let fade: Double = 1 - Double(j) / 8
                D.glow(ctx, px, py, 10 * fade + 3, sceneColor(0xBFE6FF), 0.55 * fade)
                brightShard(ctx, px, py, 7 * fade + 2, v * 7, alpha: 0.35 * fade)
            }
            let x: Double = bez(sx, mx, tx, u)
            let y: Double = bez(sy, my, ty, u)
            D.glow(ctx, x, y, 30, sceneColor(0xE9F7FF), 0.85)
            brightShard(ctx, x, y, 13 - u * 4, u * 7, alpha: 1)
            CrystalScene.star(ctx, x + 9, y - 9, 6, Color.white.opacity(0.9))
        }
        // はまって光る（0.5〜1）
        let fl: Double = D.span(r, 0.5, 1)
        if fl > 0 && fl < 1 {
            let flash: Double = sin(fl * Double.pi) * (1 - fl * 0.4)
            let facet: Path = CrystalScene.facetPath(i, c: c, s: s)
            ctx.fill(facet, with: .color(Color.white.opacity(0.75 * flash)))
            ctx.stroke(facet, with: .color(sceneColor(0xFFD27A, flash)), lineWidth: 2)
            D.glow(ctx, tx, ty, s * 0.9, sceneColor(0xE9F7FF), 0.6 * flash)
            for j in 0..<7 {
                let ang: Double = Double(j) / 7 * 2 * Double.pi + 0.4
                let dist: Double = 10 + fl * s * 0.8
                let px: Double = tx + cos(ang) * dist
                let py: Double = ty + sin(ang) * dist
                CrystalScene.star(ctx, px, py, 5 * (1 - fl) + 1.5, sceneColor(j % 2 == 0 ? 0xFFFFFF : 0xD9CCFF, 1 - fl))
            }
        }
    }

    // MARK: 墨流し：しずくが落ちて輪に広がる

    @_optimize(none)
    static func ink(_ ctx: GraphicsContext, size: CGSize, k: CritterKnobs, layer: Layer) {
        guard layer == .reaction, let r = k.react else { return }
        let w: Double = Double(size.width)
        let h: Double = Double(size.height)
        let n: Double = Double(max(1, k.count))
        let fx: Double = (n * 0.618 + 0.31).truncatingRemainder(dividingBy: 1)
        let fy: Double = (n * 0.382 + 0.17).truncatingRemainder(dividingBy: 1)
        let cx: Double = w * (0.22 + 0.56 * fx)
        let cy: Double = h * (0.46 + 0.3 * fy)   // 見出しのボタンより下に落とす
        let indigo: UInt32 = InkScene.indigo
        let red: UInt32 = InkScene.vermilion
        // 落ちる（0〜0.18）
        let fall: Double = D.span(r, 0, 0.18)
        if fall < 1 {
            let y: Double = cy - 140 * (1 - fall * fall)
            var drop = Path()
            let dr: Double = 5
            drop.move(to: CGPoint(x: cx, y: y - dr * 2.6))
            drop.addQuadCurve(to: CGPoint(x: cx + dr, y: y), control: CGPoint(x: cx + dr * 0.9, y: y - dr * 1.2))
            drop.addArc(center: CGPoint(x: cx, y: y), radius: dr, startAngle: .degrees(0), endAngle: .degrees(180), clockwise: false)
            drop.addQuadCurve(to: CGPoint(x: cx, y: y - dr * 2.6), control: CGPoint(x: cx - dr * 0.9, y: y - dr * 1.2))
            ctx.fill(drop, with: .color(sceneColor(indigo, 0.9)))
        }
        // 広がる（0.15〜1）
        let u: Double = D.span(r, 0.15, 1)
        guard u > 0 else { return }
        let grow: Double = 1 - pow(1 - u, 2.4)
        let fade: Double = u < 0.75 ? 1 : 1 - (u - 0.75) / 0.25 * 0.6
        let t: Double = k.t
        let core: Double = 3 + 6 * grow
        ctx.fill(Path(ellipseIn: CGRect(x: cx - core, y: cy - core, width: core * 2, height: core * 2)),
                 with: .color(sceneColor(indigo, 0.8 * fade)))
        let widths: [Double] = [4, 2, 2.5, 3.5, 1.5, 2]
        for j in 0..<6 {
            let lag: Double = Double(j) * 0.07
            let g: Double = max(0, grow - lag) / (1 - lag)
            guard g > 0 else { continue }
            let rr: Double = 8 + g * (14 + Double(j) * 13)
            let path: Path = InkScene.ringPath(cx: cx, cy: cy, r: rr, twist: t * 0.1 + Double(j), t: t, amp: 2 + 3 * g)
            let color: Color = sceneColor(j % 3 == 1 ? red : indigo, 0.75 * fade * (1 - Double(j) * 0.08))
            ctx.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: widths[j], lineCap: .round, lineJoin: .round))
        }
    }
}

extension CritterWidgetArt {
    /// 結晶：小さな宝石が下の余白を進み、そばで星がまたたく（一日で左から右へ）
    @_optimize(none)
    static func crystalLane(size: CGSize, k: CritterKnobs) -> AnyView {
        let w: CGFloat = size.width
        let lane: CGFloat = laneY(size.height)
        let x: CGFloat = 12 + (w - 24) * CGFloat(k.progress)
        let starX: CGFloat = x + (k.progress > 0.8 ? -16 : 16)
        let twinkle: Double = 0.4 + 0.6 * (0.5 + 0.5 * sin(k.day * 96 * 1.7))
        return AnyView(ZStack {
            sprite(16, 14, x: x, y: lane, angle: 0) { c, s in
                let cx: Double = Double(s.width) / 2
                let cy: Double = Double(s.height) / 2
                let pts: [CGPoint] = [D.pt(cx, cy - 6), D.pt(cx + 6, cy - 1), D.pt(cx, cy + 6), D.pt(cx - 6, cy - 1)]
                var path = Path()
                path.addLines(pts)
                path.closeSubpath()
                let g = Gradient(colors: [sceneColor(0xE9F7FF), sceneColor(0x8F7BE8)])
                c.fill(path, with: .linearGradient(g, startPoint: pts[0], endPoint: pts[2]))
                c.stroke(path, with: .color(Color.white.opacity(0.8)), lineWidth: 0.7)
                D.line(c, D.pt(cx - 6, cy - 1), D.pt(cx + 6, cy - 1), Color.white.opacity(0.6), 0.5)
            }
            sprite(10, 10, x: starX, y: lane - 2, angle: 0) { c, s in
                CrystalScene.star(c, Double(s.width) / 2, Double(s.height) / 2, 4.5, sceneColor(0xFFFFFF, twinkle))
            }
        })
    }

    /// 墨流し：小さな墨の輪が下の余白を流れ、15分ごとに輪の大きさが変わる
    @_optimize(none)
    static func inkLane(size: CGSize, k: CritterKnobs) -> AnyView {
        let w: CGFloat = size.width
        let lane: CGFloat = laneY(size.height)
        let x: CGFloat = w - 12 - (w - 24) * CGFloat(k.progress)
        let slot: Double = (k.day * 96).truncatingRemainder(dividingBy: 4)
        let spread: Double = 0.75 + 0.08 * slot
        return AnyView(sprite(26, 14, x: x, y: lane, angle: 0) { c, s in
            let cx: Double = Double(s.width) / 2
            let cy: Double = Double(s.height) / 2
            let radii: [Double] = [1.6, 3.4, 5.2, 6.8]
            for (i, r) in radii.enumerated() {
                let rr: Double = r * spread
                let rect = CGRect(x: cx - rr * 1.6, y: cy - rr, width: rr * 3.2, height: rr * 2)
                let color: Color = sceneColor(i == 2 ? InkScene.vermilion : InkScene.indigo, i == 0 ? 0.85 : 0.6)
                c.stroke(Path(ellipseIn: rect), with: .color(color), lineWidth: i == 0 ? 2 : 1)
            }
        })
    }
}

// MARK: - 起床・習慣の輪（WidgetWorldRing から）

/// 結晶：氷の輪。進むほど（朝が近づくほど）輪の上の星が増えてきらめく
struct CrystalWakeRing: View {
    let p: Palette
    let fraction: Double
    var lineWidth: CGFloat = 8

    var body: some View {
        let shown: Double = max(0, min(1, fraction))
        let grad = AngularGradient(colors: [sceneColor(0x9FE8FF), sceneColor(0xD9CCFF), sceneColor(0xFFD27A), sceneColor(0x9FE8FF)],
                                   center: .center)
        let n: Int = 2 + Int(shown * 6)
        return ZStack {
            Circle().stroke(sceneColor(0x9FB4D8, 0.18), lineWidth: lineWidth)
            Circle().trim(from: 0, to: shown)
                .stroke(grad, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .opacity(shown > 0 ? 1 : 0)
            Canvas { c, s in CrystalWakeRing.stars(c, size: s, shown: shown, n: n, lineWidth: Double(lineWidth)) }
        }
        .shadow(color: sceneColor(0x7FD4F5, 0.35 + 0.3 * shown), radius: 4)
    }
}

/// 墨流し：藍の輪。進むほど（朝が近づくほど）外の朱の輪が広がる
struct InkWakeRing: View {
    let p: Palette
    let fraction: Double
    var lineWidth: CGFloat = 8

    var body: some View {
        let shown: Double = max(0, min(1, fraction))
        return ZStack {
            Circle().stroke(sceneColor(InkScene.indigo, 0.12), lineWidth: lineWidth)
            Circle().trim(from: 0, to: shown)
                .stroke(sceneColor(InkScene.indigo), style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .opacity(shown > 0 ? 1 : 0)
            Canvas { c, s in InkWakeRing.ring(c, size: s, shown: shown, lineWidth: Double(lineWidth)) }
        }
    }
}

extension CrystalWakeRing {
    /// 輪の上の星（進んだところまで並べ、先頭をいちばん大きく）
    @_optimize(none)
    static func stars(_ c: GraphicsContext, size s: CGSize, shown: Double, n: Int, lineWidth: Double) {
        let cx: Double = Double(s.width) / 2
        let cy: Double = Double(s.height) / 2
        let rad: Double = Double(min(s.width, s.height)) / 2 - lineWidth / 2
        for i in 0..<n {
            let f: Double = shown * Double(i + 1) / Double(n)
            let ang: Double = f * 2 * Double.pi - Double.pi / 2
            let r: Double = lineWidth * (i == n - 1 ? 0.9 : 0.5)
            let x: Double = cx + cos(ang) * rad
            let y: Double = cy + sin(ang) * rad
            CrystalScene.star(c, x, y, r, Color.white.opacity(i == n - 1 ? 1 : 0.75))
        }
    }
}

extension InkWakeRing {
    /// 内側の朱の輪（進むほど外へ広がる）
    @_optimize(none)
    static func ring(_ c: GraphicsContext, size s: CGSize, shown: Double, lineWidth: Double) {
        let cx: Double = Double(s.width) / 2
        let cy: Double = Double(s.height) / 2
        let outer: Double = Double(min(s.width, s.height)) / 2
        let rr: Double = outer - lineWidth * (1.4 - 0.4 * shown)
        let path: Path = InkScene.ringPath(cx: cx, cy: cy, r: max(4, rr), twist: shown * 3, t: shown * 40, amp: 0.8)
        let color: Color = sceneColor(InkScene.vermilion, 0.35 + 0.5 * shown)
        c.stroke(path, with: .color(color), lineWidth: max(1, lineWidth * 0.22))
    }
}

extension CritterArt {
    /// 2次ベジェ曲線の1軸
    @_optimize(none)
    static func bez(_ a: Double, _ m: Double, _ b: Double, _ u: Double) -> Double {
        let v: Double = 1 - u
        let p: Double = v * v * a
        let q: Double = 2 * v * u * m
        let s: Double = u * u * b
        return p + q + s
    }

    /// 飛んでいくかけら（明るい氷の色に金の縁。完了の反応で目立つように）
    @_optimize(none)
    static func brightShard(_ ctx: GraphicsContext, _ cx: Double, _ cy: Double, _ r: Double, _ rot: Double, alpha: Double) {
        let pts: [(Double, Double)] = [(-0.9, 0.4), (-0.1, -1.0), (0.9, -0.3), (0.4, 1.0)]
        var path = Path()
        for (i, p) in pts.enumerated() {
            let x: Double = p.0 * cos(rot) - p.1 * sin(rot)
            let y: Double = p.0 * sin(rot) + p.1 * cos(rot)
            let q = CGPoint(x: cx + x * r, y: cy + y * r)
            if i == 0 { path.move(to: q) } else { path.addLine(to: q) }
        }
        path.closeSubpath()
        let g = Gradient(colors: [sceneColor(0xFFFFFF, alpha), sceneColor(0x9FD8FF, alpha)])
        let top = CGPoint(x: cx - r, y: cy - r)
        let bottom = CGPoint(x: cx + r, y: cy + r)
        ctx.fill(path, with: .linearGradient(g, startPoint: top, endPoint: bottom))
        ctx.stroke(path, with: .color(sceneColor(0xFFD27A, alpha)), lineWidth: 1.4)
    }
}
