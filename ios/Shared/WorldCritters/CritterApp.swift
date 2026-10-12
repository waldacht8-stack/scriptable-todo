import SwiftUI

// MARK: - アプリの背景の住人（世界観ごとの配置と動き）
// 通り道（lane）は画面の高さの 81%。フォーカスの構成では「完了」の行とタブバーの間で、ここは中身が置かれにくい。
// 一覧の構成ではカードの裏に隠れるが、隠れるだけで文字にはかからない。風船と泡は左右の余白（16pt）を上っていく。

enum CritterArt {
    enum Layer { case idle, reaction }

    typealias D = CritterDraw
    typealias C = Critters

    /// 一巡の秒数（横切る速さ。止まった絵では -motionphase × この秒数の時刻で描く）
    @_optimize(none)
    static func period(_ w: World) -> Double {
        switch w {
        case .strata: 46
        case .galaxy: 48
        case .sky: 26
        case .mist: 75
        case .deepsea: 70
        case .aurora: 15
        default: 30
        }
    }

    /// 完了の反応の長さ（秒）
    @_optimize(none)
    static func reactionDuration(_ w: World) -> Double {
        switch w {
        case .sky: 6
        case .deepsea: 3.2
        case .galaxy: 1.6
        case .aurora: 2.6
        default: 2
        }
    }

    @_optimize(none)
    static func laneY(_ size: CGSize) -> Double { Double(size.height) * 0.81 }

    @_optimize(none)
    static func drawApp(_ world: World, _ ctx: GraphicsContext, size: CGSize, k: CritterKnobs, layer: Layer) {
        switch world {
        case .strata: strata(ctx, size: size, k: k, layer: layer)
        case .galaxy: galaxy(ctx, size: size, k: k, layer: layer)
        case .sky: sky(ctx, size: size, k: k, layer: layer)
        case .mist: mist(ctx, size: size, k: k, layer: layer)
        case .deepsea: deepsea(ctx, size: size, k: k, layer: layer)
        case .aurora: aurora(ctx, size: size, k: k, layer: layer)
        case .none: break
        }
    }

    // MARK: 地層：モグラがトンネルを掘り進む。完了で顔を出し、土がこぼれる

    @_optimize(none)
    static func tunnelY(_ x: Double, w: Double, lane: Double) -> Double {
        lane + sin(x / max(w, 1) * Double.pi * 3) * 4
    }

    /// モグラが掘り進む右の端（右下の＋ボタンと親指にかからないよう、画面の 6 割まで）
    @_optimize(none)
    static func moleReach(_ w: Double) -> Double { w * 0.6 }

    @_optimize(none)
    static func strata(_ ctx: GraphicsContext, size: CGSize, k: CritterKnobs, layer: Layer) {
        let w: Double = Double(size.width)
        let lane: Double = laneY(size)
        // 左から画面の 6 割まで掘り、そこで深く潜って消える（次の一巡はまた左から）
        let travel: Double = min(1, k.progress / 0.88)
        let dive: Double = D.span(k.progress, 0.88, 0.98)
        let mx: Double = -24 + travel * (moleReach(w) + 24)
        let my: Double = tunnelY(mx, w: w, lane: lane) + dive * 16
        switch layer {
        case .idle:
            var tunnel = Path()
            let start: Double = max(-12, mx - w * 0.55)
            var x: Double = start
            tunnel.move(to: D.pt(x, tunnelY(x, w: w, lane: lane)))
            while x < mx {
                x = min(mx, x + 8)
                tunnel.addLine(to: D.pt(x, tunnelY(x, w: w, lane: lane)))
            }
            let fadeStart = D.pt(start, lane)
            let fadeEnd = D.pt(mx, lane)
            let g1 = Gradient(colors: [sceneColor(0x7A5532, 0), sceneColor(0x7A5532, 0.4)])
            let g2 = Gradient(colors: [sceneColor(0x5E4129, 0), sceneColor(0x5E4129, 0.32)])
            ctx.stroke(tunnel, with: .linearGradient(g1, startPoint: fadeStart, endPoint: fadeEnd),
                       style: StrokeStyle(lineWidth: 13, lineCap: .round, lineJoin: .round))
            ctx.stroke(tunnel, with: .linearGradient(g2, startPoint: fadeStart, endPoint: fadeEnd),
                       style: StrokeStyle(lineWidth: 7, lineCap: .round, lineJoin: .round))
            // 掘った土くれ（後ろへ飛ぶ）
            for i in 0..<3 {
                let u: Double = (k.t * 1.3 + Double(i) / 3).truncatingRemainder(dividingBy: 1)
                let px: Double = mx - 8 - u * 14
                let py: Double = my - 2 - sin(u * Double.pi) * 6
                D.circle(ctx, px, py, 1.3, sceneColor(0x5E4129, 0.6 * (1 - u)))
            }
            if k.react == nil {
                var mc: GraphicsContext = D.local(ctx, at: D.pt(mx, my), scale: 1.05)
                mc.opacity = 1 - dive
                C.mole(mc, t: k.t, digging: true)
            }
        case .reaction:
            guard let r = k.react else { return }
            let up: Double = D.ease(D.span(r, 0, 0.18)) * (1 - D.ease(D.span(r, 0.78, 1))) * 15
            let moundAlpha: Double = min(1, r * 6) * (1 - D.span(r, 0.85, 1))
            var mound: GraphicsContext = D.local(ctx, at: D.pt(mx + 2, my - 4), scale: 1)
            mound.opacity = moundAlpha
            C.soilMound(mound, width: 26)
            C.mole(D.local(ctx, at: D.pt(mx + 2, my - 4 - up), scale: 1.05, angle: -1.15), t: 0, digging: false)
            // こぼれる土
            for i in 0..<6 {
                let u: Double = D.span(r, 0.12 + Double(i) * 0.04, 0.75 + Double(i) * 0.03)
                guard u > 0 && u < 1 else { continue }
                let side: Double = i % 2 == 0 ? -1 : 1
                let px: Double = mx + 2 + side * (5 + Double(i) * 1.6 + u * 8)
                let py: Double = my - 14 - up * 0.6 + u * u * 26 - sin(u * Double.pi) * 8
                D.circle(ctx, px, py, 1.2 + Double(i % 3) * 0.5, sceneColor(0x6B4A2C, 0.85 * (1 - u)))
            }
        }
    }

    // MARK: 銀河：宇宙飛行士がふわふわ漂う。完了で流れ星

    @_optimize(none)
    static func galaxy(_ ctx: GraphicsContext, size: CGSize, k: CritterKnobs, layer: Layer) {
        let w: Double = Double(size.width)
        let lane: Double = laneY(size)
        switch layer {
        case .idle:
            let h: Double = Double(size.height)
            // 手前の星（奥の星よりはやく流れて、奥行きが出る）
            nearStars(ctx, w: w, h: h, t: k.t)
            // 星雲のもや（通り道のあたりを、違う速さで2層ただよう）
            Fantasy.fogBank(ctx, width: w, y: lane - 16, height: 48, t: k.t, speed: 2.2, seed: 71, count: 6,
                            color: sceneColor(0x9C7BFF), alpha: 0.14)
            Fantasy.fogBank(ctx, width: w, y: lane + 16, height: 34, t: k.t, speed: -1.4, seed: 72, count: 5,
                            color: sceneColor(0xFF86C8), alpha: 0.1)
            // 宇宙飛行士は左から 7 割までを行き来する（右下の＋ボタンの裏に入らないように）
            let swing: Double = sin(k.progress * 2 * Double.pi)
            let ax: Double = w * (0.4 + 0.24 * swing)
            let ay: Double = lane - 10 + sin(k.t * 0.8) * 6
            let angle: Double = sin(k.progress * 4 * Double.pi) * 0.32 + sin(k.t * 0.5) * 0.06
            let scale: Double = 1.25
            astronautTether(ctx, at: D.pt(ax, ay), angle: angle, scale: scale, t: k.t, w: w, lane: lane)
            let ac: GraphicsContext = D.local(ctx, at: D.pt(ax, ay), scale: scale, angle: angle)
            thrusterPuff(ac, t: k.t)
            Fantasy.astronaut(ac, t: k.t)
        case .reaction:
            guard let r = k.react else { return }
            let u: Double = D.ease(D.span(r, 0, 0.85))
            let x0: Double = w * 0.94
            let y0: Double = lane - 74
            let x1: Double = w * 0.06
            let y1: Double = lane + 22
            let head = D.pt(x0 + (x1 - x0) * u, y0 + (y1 - y0) * u)
            let len: Double = hypot(x1 - x0, y1 - y0)
            let alpha: Double = min(1, r * 8) * (1 - D.span(r, 0.75, 1))
            C.shootingStar(ctx, head: head, dirX: (x1 - x0) / len, dirY: (y1 - y0) / len, length: 70, alpha: alpha)
        }
    }

    struct Mote { let x: Double; let y: Double; let r: Double; let speed: Double; let phase: Double }

    /// 手前の星（画面全体。ゆっくり左へ流れる）
    static let galaxyNear: [Mote] = {
        var rnd = SceneRandom(4242)
        var out: [Mote] = []
        for _ in 0..<18 {
            out.append(Mote(x: rnd.next(), y: rnd.next(), r: rnd.range(0.6, 1.5), speed: rnd.range(2.5, 6), phase: rnd.range(0, 6.28)))
        }
        return out
    }()

    @_optimize(none)
    static func nearStars(_ ctx: GraphicsContext, w: Double, h: Double, t: Double) {
        let span: Double = w + 20
        for m in galaxyNear {
            let raw: Double = (m.x * span - t * m.speed).truncatingRemainder(dividingBy: span)
            let x: Double = (raw < 0 ? raw + span : raw) - 10
            let y: Double = m.y * h
            let tw: Double = 0.55 + 0.45 * sin(t * 1.7 + m.phase)
            D.glow(ctx, x, y, m.r * 4, sceneColor(0xDCD4FF), 0.35 * tw)
            D.circle(ctx, x, y, m.r * 0.6, Color.white.opacity(0.6 + 0.4 * tw))
        }
    }

    /// 命綱：背中から左下（タブバーの裏の、画面の外の船）へ。ゆるくたわんで揺れる
    @_optimize(none)
    static func astronautTether(_ ctx: GraphicsContext, at p: CGPoint, angle: Double, scale: Double, t: Double, w: Double, lane: Double) {
        let lx: Double = -12 * scale
        let ly: Double = 2 * scale
        let ca: Double = cos(angle)
        let sa: Double = sin(angle)
        let bx: Double = Double(p.x) + lx * ca - ly * sa
        let by: Double = Double(p.y) + lx * sa + ly * ca
        let start: CGPoint = D.pt(bx, by)
        let end: CGPoint = D.pt(-24, lane + 90)
        let c1: CGPoint = D.pt(bx - 34 + sin(t * 0.6) * 8, by + 26 + sin(t * 0.45) * 7)
        let c2: CGPoint = D.pt(w * 0.06 + sin(t * 0.35 + 1) * 12, lane + 36 + cos(t * 0.5) * 8)
        var path = Path()
        path.move(to: start)
        path.addCurve(to: end, control1: c1, control2: c2)
        let g = Gradient(colors: [sceneColor(0xE4DEFF, 0.6), sceneColor(0xB9A8FF, 0.25), sceneColor(0xB9A8FF, 0)])
        let shade = GraphicsContext.Shading.linearGradient(g, startPoint: start, endPoint: end)
        ctx.stroke(path, with: shade, style: StrokeStyle(lineWidth: 1.2, lineCap: .round))
        D.glow(ctx, bx, by, 5, sceneColor(0xE4DEFF), 0.5)
    }

    /// 背中の小さな噴射（6秒ごとに少しだけ。宇宙飛行士の座標で描く）
    @_optimize(none)
    static func thrusterPuff(_ c: GraphicsContext, t: Double) {
        let u: Double = (t / 6).truncatingRemainder(dividingBy: 1)
        guard u < 0.25 else { return }
        let k: Double = u / 0.25
        for i in 0..<4 {
            let ui: Double = k - Double(i) * 0.12
            guard ui > 0 && ui < 1 else { continue }
            let x: Double = -12 - ui * 14
            let y: Double = 8 + ui * 6 + Double(i % 2) * 2
            D.glow(c, x, y, 2 + ui * 4, sceneColor(0xCFE6FF), 0.5 * (1 - ui))
        }
    }

    // MARK: 空：鳥の群れと紙飛行機が横切る。完了で風船が上る

    @_optimize(none)
    static func sky(_ ctx: GraphicsContext, size: CGSize, k: CritterKnobs, layer: Layer) {
        let w: Double = Double(size.width)
        let h: Double = Double(size.height)
        let lane: Double = laneY(size)
        switch layer {
        case .idle:
            let birdColor: Color = k.dark ? sceneColor(0xBAC3E8, 0.6) : sceneColor(0x2B4560, 0.55)
            let bp: Double = (k.progress * 26 / 34 + 0.3).truncatingRemainder(dividingBy: 1)
            let bx: Double = -40 + bp * (w + 80)
            let by: Double = lane - 22 + sin(k.t * 0.5) * 4
            let flock: [(Double, Double)] = [(0, 0), (-10, -5), (-10, 6), (-20, -10), (-19, 11)]
            for (i, o) in flock.enumerated() {
                let flap: Double = sin(k.t * 9 + Double(i) * 1.3) * 2.2
                C.bird(D.local(ctx, at: D.pt(bx + o.0, by + o.1), scale: 1), flap: flap, color: birdColor)
            }
            let px: Double = w + 30 - k.progress * (w + 60)
            let py: Double = lane + 14 + sin(k.progress * 4 * Double.pi) * 7
            let tilt: Double = cos(k.progress * 4 * Double.pi) * 0.22
            C.paperPlane(D.local(ctx, at: D.pt(px, py), scale: 1.05, angle: -tilt, flip: true), dark: k.dark)
        case .reaction:
            guard let r = k.react else { return }
            let sway: Double = sin(r * 9)
            let x: Double = w - 10 + sway * 2.5
            let y: Double = h * 0.93 - D.ease(r) * (h * 0.93 + 40)
            var c: GraphicsContext = D.local(ctx, at: D.pt(x, y), scale: 1, angle: sway * 0.08)
            c.opacity = min(1, r * 10)
            C.balloon(c, sway: sway)
        }
    }

    // MARK: 霧：霧の奥を鹿が歩き、灯りが揺れる。完了で灯りがふっと明るく
    // 奥の霧 → 鹿 → 足もとの霧 → 灯り → 手前の霧、の順に重ねて、霧の中の奥行きを出す

    @_optimize(none)
    static func mistLantern(_ w: Double) -> Double { w * 0.09 }
    static let mistLanternHeight: Double = 46

    @_optimize(none)
    static func mistSwing(_ t: Double) -> Double { sin(t * 1.1) * 0.2 }

    @_optimize(none)
    static func mist(_ ctx: GraphicsContext, size: CGSize, k: CritterKnobs, layer: Layer) {
        let w: Double = Double(size.width)
        let lane: Double = laneY(size)
        let ground: Double = lane + 22
        let lanternX: Double = mistLantern(w)
        let swing: Double = mistSwing(k.t)
        let lamp: CGPoint = Fantasy.lanternLamp(height: mistLanternHeight, swing: swing)
        let lampX: Double = lanternX + Double(lamp.x)
        let lampY: Double = ground + Double(lamp.y)
        let t: Double = k.t
        switch layer {
        case .idle:
            let fogWhite: Color = sceneColor(0xEEF0F0)
            Fantasy.fogBank(ctx, width: w, y: ground - 38, height: 34, t: t, speed: 2.4, seed: 11, count: 7, color: fogWhite, alpha: 0.42)
            // 鹿：右から左へ。ときどき頭を下げてにおいをかぎ、耳としっぽがぴくっと動き、白い息を吐く
            let dx: Double = w + 50 - k.progress * (w + 100)
            let sniff: Double = Fantasy.bump((t / 23).truncatingRemainder(dividingBy: 1), 0.55, 0.85)
            let ear: Double = Fantasy.bump((t / 5.3).truncatingRemainder(dividingBy: 1), 0, 0.07)
            let tail: Double = Fantasy.bump((t / 4.1).truncatingRemainder(dividingBy: 1), 0, 0.09)
            let bu: Double = (t / 3.6).truncatingRemainder(dividingBy: 1)
            let breath: Double? = bu < 0.7 ? bu / 0.7 : nil
            let side: Double = lampX < dx ? -1 : 1
            let dist: Double = abs(dx - lampX)
            let light: Double = max(0.2, 1 - dist / (w * 0.7))
            let pose = Fantasy.DeerPose(walk: t * 2.4, headDown: sniff, ear: ear, tail: tail, breath: breath, lightSide: side, light: light)
            var dc: GraphicsContext = D.local(ctx, at: D.pt(dx, ground), scale: 1.05)
            dc.opacity = 0.9
            Fantasy.deer(dc, pose: pose, near: sceneColor(0x56626D), far: sceneColor(0x86909A), belly: sceneColor(0x3B454F),
                         rim: sceneColor(0xFFC98A))
            // 足もとをはう霧（脚がかすむ）
            Fantasy.fogBank(ctx, width: w, y: ground - 6, height: 20, t: t, speed: 6, seed: 12, count: 8, color: fogWhite, alpha: 0.5)
            let veil = Gradient(stops: [
                Gradient.Stop(color: sceneColor(0xECEEEE, 0), location: 0),
                Gradient.Stop(color: sceneColor(0xECEEEE, 0.38), location: 0.6),
                Gradient.Stop(color: sceneColor(0xECEEEE, 0), location: 1),
            ])
            let band = CGRect(x: 0, y: ground - 30, width: w, height: 44)
            ctx.fill(Path(band), with: .linearGradient(veil, startPoint: D.pt(0, band.minY), endPoint: D.pt(0, band.maxY)))
            // 灯り（炎がゆらぎ、虫が舞う）
            let flicker: Double = 0.5 + 0.3 * sin(t * 9.1) + 0.2 * sin(t * 13.7 + 1)
            Fantasy.lantern(D.local(ctx, at: D.pt(lanternX, ground), scale: 1), height: mistLanternHeight, swing: swing,
                            flicker: flicker, t: t)
            // 手前を速く流れるうすい霧
            Fantasy.fogBank(ctx, width: w, y: ground + 12, height: 16, t: t, speed: 11, seed: 13, count: 6, color: fogWhite, alpha: 0.32)
        case .reaction:
            guard let r = k.react else { return }
            let flare: Double = sin(D.span(r, 0, 1) * Double.pi)
            D.glow(ctx, lampX, lampY, 34 + flare * 40, sceneColor(0xFFC77A), 0.6 * flare)
            Fantasy.softEllipse(ctx, lampX, ground, 60 + flare * 30, 10, sceneColor(0xFFC77A), 0.4 * flare)
            // 灯りから小さな火の粉が昇る
            for i in 0..<6 {
                let u: Double = D.span(r, Double(i) * 0.07, 0.6 + Double(i) * 0.07)
                guard u > 0 && u < 1 else { continue }
                let px: Double = lampX + sin(u * 6 + Double(i)) * (4 + Double(i))
                let py: Double = lampY - 6 - u * 46
                D.glow(ctx, px, py, 3.5, sceneColor(0xFFC77A), 0.7 * (1 - u))
                D.circle(ctx, px, py, 1.1, sceneColor(0xFFE2B0, 0.95 * (1 - u)))
            }
        }
    }

    // MARK: 深海：大きなクジラがゆっくり通り、チョウチンアンコウが光る。完了で泡
    // 光の筋 → 発光の粒（奥） → クジラ → アンコウ、の順。クジラの通ったあとは粒が明るく光る

    static let seaMoteList: [Mote] = {
        var rnd = SceneRandom(2718)
        var out: [Mote] = []
        for _ in 0..<26 {
            out.append(Mote(x: rnd.next(), y: rnd.range(-1, 1), r: rnd.range(0.7, 1.6), speed: rnd.range(0.4, 1.4), phase: rnd.range(0, 6.28)))
        }
        return out
    }()

    @_optimize(none)
    static func anglerSpot(_ w: Double, lane: Double, t: Double) -> CGPoint {
        D.pt(w * 0.3, lane + 28 + sin(t * 0.9) * 2)
    }

    @_optimize(none)
    static func deepsea(_ ctx: GraphicsContext, size: CGSize, k: CritterKnobs, layer: Layer) {
        let w: Double = Double(size.width)
        let h: Double = Double(size.height)
        let lane: Double = laneY(size)
        let t: Double = k.t
        let angler: CGPoint = anglerSpot(w, lane: lane, t: t)
        let anglerX: Double = Double(angler.x)
        let anglerY: Double = Double(angler.y)
        switch layer {
        case .idle:
            seaShafts(ctx, w: w, h: h, lane: lane, t: t)
            let L: Double = min(200, w * 0.5)
            let wx: Double = w + L * 0.7 - k.progress * (w + L * 1.4)
            let wy: Double = lane - 28 + sin(t * 0.4) * 5
            seaMotes(ctx, w: w, lane: lane, t: t, wakeX: wx + L * 0.45, wakeY: wy)
            let pitch: Double = sin(t * 0.4 + 1.2) * 0.04
            Fantasy.whale(D.local(ctx, at: D.pt(wx, wy), scale: 1, angle: pitch), t: t, length: L, haze: 0.22)
            let glow: Double = 0.5 + 0.5 * sin(t * 2.2)
            Fantasy.angler(D.local(ctx, at: angler, scale: 1.05), t: t, glow: glow)
        case .reaction:
            guard let r = k.react else { return }
            for i in 0..<12 {
                let d: Double = Double(i) * 0.05
                let u: Double = D.span(r, d, d + 0.7)
                guard u > 0 && u < 1 else { continue }
                let fromAngler: Bool = i % 3 == 0
                let baseX: Double = fromAngler ? anglerX + 16 : (i % 2 == 0 ? 9 : w - 9)
                let rise: Double = fromAngler ? 120 : h * 0.7
                let x: Double = baseX + sin(u * 8 + Double(i)) * 3
                let y: Double = (fromAngler ? anglerY - 4 : h * 0.9) - u * rise
                let rr: Double = 2 + Double(i % 3) * 1.2
                C.bubble(ctx, x, y, rr, 1 - u * 0.8)
            }
        }
    }

    /// 上から通り道まで届く、うすい光の筋（ゆっくり揺れる）
    @_optimize(none)
    static func seaShafts(_ ctx: GraphicsContext, w: Double, h: Double, lane: Double, t: Double) {
        let bottom: Double = lane + 40
        for i in 0..<3 {
            let fi: Double = Double(i)
            let x0: Double = w * (0.2 + 0.3 * fi) + sin(t * 0.12 + fi * 2) * 16
            let top: Double = h * 0.2
            let spread: Double = 14 + fi * 6
            let lean: Double = (bottom - top) * 0.32
            var shaft = Path()
            shaft.move(to: D.pt(x0 - spread * 0.4, top))
            shaft.addLine(to: D.pt(x0 + spread * 0.4, top))
            shaft.addLine(to: D.pt(x0 + lean + spread * 1.6, bottom))
            shaft.addLine(to: D.pt(x0 + lean - spread * 1.6, bottom))
            shaft.closeSubpath()
            let a: Double = 0.06 + 0.03 * sin(t * 0.3 + fi * 1.7)
            let g = Gradient(stops: [
                Gradient.Stop(color: sceneColor(0xBFF4FF, 0), location: 0),
                Gradient.Stop(color: sceneColor(0xBFF4FF, a), location: 0.45),
                Gradient.Stop(color: sceneColor(0xBFF4FF, 0), location: 1),
            ])
            ctx.fill(shaft, with: .linearGradient(g, startPoint: D.pt(0, top), endPoint: D.pt(0, bottom)))
        }
    }

    /// 発光する粒（クジラの通ったあと＝wake の近くほど明るい）
    @_optimize(none)
    static func seaMotes(_ ctx: GraphicsContext, w: Double, lane: Double, t: Double, wakeX: Double, wakeY: Double) {
        for (i, m) in seaMoteList.enumerated() {
            let x: Double = m.x * w + sin(t * 0.2 * m.speed + m.phase) * 10
            let y: Double = lane - 10 + m.y * 70 + sin(t * 0.5 + m.phase) * 4
            let dx: Double = x - wakeX
            let dy: Double = y - wakeY
            let near: Double = exp(-(dx * dx + dy * dy) / (2 * 70 * 70))
            let tw: Double = 0.5 + 0.5 * sin(t * 1.3 * m.speed + m.phase)
            let a: Double = 0.16 + 0.24 * tw + 0.6 * near
            let color: Color = i % 3 == 0 ? sceneColor(0x9FD8FF) : sceneColor(0x7DF9E6)
            D.glow(ctx, x, y, m.r * (3.5 + near * 4), color, a * 0.6)
            D.circle(ctx, x, y, m.r * 0.55, color.opacity(min(1, a + 0.2)))
        }
    }

    // MARK: オーロラ：光のカーテンの下、雪の吹きだまりで狐が座って空を見上げる。完了で駆け抜ける

    static let snowFlakes: [Mote] = {
        var rnd = SceneRandom(1717)
        var out: [Mote] = []
        for _ in 0..<20 {
            out.append(Mote(x: rnd.next(), y: rnd.next(), r: rnd.range(0.6, 1.4), speed: rnd.range(0.01, 0.025), phase: rnd.range(0, 6.28)))
        }
        return out
    }()

    @_optimize(none)
    static func aurora(_ ctx: GraphicsContext, size: CGSize, k: CritterKnobs, layer: Layer) {
        let w: Double = Double(size.width)
        let h: Double = Double(size.height)
        let lane: Double = laneY(size)
        let ground: Double = lane + 16
        let rim: Color = sceneColor(0x86FBDD)
        let t: Double = k.t
        switch layer {
        case .idle:
            auroraStars(ctx, w: w, h: h, t: t)
            let colors: [UInt32] = [0x5CF2C8, 0x9EF0E6, 0xB28CFF]
            for i in 0..<3 {
                let fi: Double = Double(i)
                let top: Double = h * (0.05 + 0.075 * fi)
                let phase: Double = t * 0.22 * (1 + fi * 0.3) + fi * 1.7
                C.auroraCurtain(ctx, width: w, top: top, amp: 18, thick: 104 - fi * 18, wave: 1.1 + fi * 0.35,
                                phase: phase, color: sceneColor(colors[i]), alpha: 0.24)
            }
            snowfall(ctx, w: w, h: h, t: t)
            treeline(ctx, w: w, ground: ground, rim: rim)
            snowDrift(ctx, w: w, h: h, ground: ground, t: t)
            guard k.react == nil else { return }
            let look: Double = 0.5 + 0.5 * sin(t * 0.3)
            let ear: Double = Fantasy.bump((t / 4.7).truncatingRemainder(dividingBy: 1), 0, 0.08)
            let bu: Double = (t / 4.2).truncatingRemainder(dividingBy: 1)
            let puff: Double? = bu < 0.65 ? bu / 0.65 : nil
            Fantasy.foxSit(D.local(ctx, at: D.pt(w * 0.2, ground + 1), scale: 1.15), look: look, tail: sin(t * 1.1),
                           ear: ear, puff: puff, rim: rim)
        case .reaction:
            guard let r = k.react else { return }
            let fx: Double = -50 + D.span(r, 0, 0.9) * (w + 100)
            let run: Double = r * 70
            let hop: Double = abs(sin(run)) * 2.4
            // 蹴り上げた雪
            for i in 0..<5 {
                let fi: Double = Double(i)
                let age: Double = fi * 0.18
                let px: Double = fx - 26 - fi * 9
                let py: Double = ground - 2 - sin(min(1, age) * Double.pi) * 5
                D.glow(ctx, px, py, 3 + fi * 1.4, Color.white, 0.4 * (1 - fi / 5))
            }
            Fantasy.foxRun(D.local(ctx, at: D.pt(fx, ground + 1 - hop), scale: 1.1), run: run, rim: rim)
        }
    }

    /// 北の空の星（上のほうだけ。ゆっくりまたたく）
    static let auroraStarList: [Mote] = {
        var rnd = SceneRandom(5150)
        var out: [Mote] = []
        for _ in 0..<40 {
            out.append(Mote(x: rnd.next(), y: rnd.range(0, 0.5), r: rnd.range(0.4, 1.1), speed: rnd.range(0.8, 2), phase: rnd.range(0, 6.28)))
        }
        return out
    }()

    @_optimize(none)
    static func auroraStars(_ ctx: GraphicsContext, w: Double, h: Double, t: Double) {
        for m in auroraStarList {
            let tw: Double = 0.45 + 0.55 * (0.5 + 0.5 * sin(t * m.speed + m.phase))
            D.circle(ctx, m.x * w, m.y * h, m.r, Color.white.opacity(0.75 * tw))
        }
    }

    /// 地平の針葉樹の影（吹きだまりの奥。上のふちにオーロラの光）
    @_optimize(none)
    static func treeline(_ ctx: GraphicsContext, w: Double, ground: Double, rim: Color) {
        var rnd = SceneRandom(808)
        var x: Double = -6
        let dark: Color = sceneColor(0x0D0A20, 0.88)
        while x < w + 6 {
            let tw: Double = rnd.range(7, 13)
            let th: Double = rnd.range(10, 30) * (x > w * 0.3 && x < w * 0.7 ? 0.55 : 1)
            let cx: Double = x + tw / 2
            let base: Double = ground + 2
            let tree: Path = Fantasy.smooth([D.pt(cx, base - th), D.pt(cx + tw * 0.28, base - th * 0.55), D.pt(cx + tw / 2, base),
                                             D.pt(cx - tw / 2, base), D.pt(cx - tw * 0.28, base - th * 0.55)], closed: true)
            ctx.fill(tree, with: .color(dark))
            var top = Path()
            top.move(to: D.pt(cx - tw * 0.2, base - th * 0.7))
            top.addLine(to: D.pt(cx, base - th))
            top.addLine(to: D.pt(cx + tw * 0.2, base - th * 0.7))
            ctx.stroke(top, with: .color(rim.opacity(0.35)), lineWidth: 0.8)
            x += tw * rnd.range(0.55, 0.9)
        }
    }

    /// 雪（画面全体にゆっくり降る）
    @_optimize(none)
    static func snowfall(_ ctx: GraphicsContext, w: Double, h: Double, t: Double) {
        for m in snowFlakes {
            let y: Double = (m.y + t * m.speed).truncatingRemainder(dividingBy: 1) * h
            let x: Double = m.x * w + sin(t * 0.6 + m.phase) * 8
            D.circle(ctx, x, y, m.r, Color.white.opacity(0.4))
        }
    }

    /// 雪の吹きだまり（オーロラの色がうっすら映る）
    @_optimize(none)
    static func snowDrift(_ ctx: GraphicsContext, w: Double, h: Double, ground: Double, t: Double) {
        let pts: [CGPoint] = [
            D.pt(-20, ground + 4), D.pt(w * 0.1, ground - 3), D.pt(w * 0.3, ground - 1), D.pt(w * 0.55, ground + 5),
            D.pt(w * 0.8, ground + 2), D.pt(w + 20, ground + 6), D.pt(w + 20, h + 10), D.pt(-20, h + 10),
        ]
        let drift: Path = Fantasy.smooth(pts, closed: true)
        let g = Gradient(colors: [sceneColor(0xE8F4FF, 0.2), sceneColor(0xB9C8F0, 0.06)])
        ctx.fill(drift, with: .linearGradient(g, startPoint: D.pt(0, ground - 4), endPoint: D.pt(0, ground + 60)))
        let edge = Gradient(colors: [sceneColor(0x86FBDD, 0.0), sceneColor(0x86FBDD, 0.4), sceneColor(0xC6A8FF, 0.3), sceneColor(0xC6A8FF, 0)])
        ctx.stroke(drift, with: .linearGradient(edge, startPoint: D.pt(0, ground), endPoint: D.pt(w, ground)), lineWidth: 1)
        let glowA: Double = 0.1 + 0.04 * sin(t * 0.4)
        Fantasy.softEllipse(ctx, w * 0.42, ground + 6, w * 0.5, 12, sceneColor(0x5CF2C8), glowA)
    }
}
