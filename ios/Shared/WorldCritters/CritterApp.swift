import SwiftUI

// MARK: - アプリの背景の住人（世界観ごとの配置と動き）
// 通り道（lane）は画面の高さの 81%。フォーカスの構成では「完了」の行とタブバーの間で、ここは中身が置かれにくい。
// 一覧の構成ではカードの裏に隠れるが、隠れるだけで文字にはかからない。風船と泡は左右の余白（16pt）を上っていく。

enum CritterArt {
    enum Layer { case idle, reaction }

    typealias D = CritterDraw
    typealias C = Critters

    /// 一巡の秒数（横切る速さ。止まった絵では -motionphase × この秒数の時刻で描く）
    static func period(_ w: World) -> Double {
        switch w {
        case .strata: 46
        case .galaxy: 48
        case .sky: 26
        case .mist: 75
        case .deepsea: 70
        case .hinata: 16
        case .aurora: 15
        case .bento: 19.2
        case .swiss: 60
        case .yohaku: 90
        case .terminal: 24
        default: 30
        }
    }

    /// 完了の反応の長さ（秒）
    static func reactionDuration(_ w: World) -> Double {
        switch w {
        case .sky: 6
        case .deepsea: 3.2
        case .galaxy: 1.6
        case .aurora: 2.6
        case .brutal: 2.2
        case .hinata: 3
        case .yohaku: 2.8
        case .terminal: 3.2
        default: 2
        }
    }

    static func laneY(_ size: CGSize) -> Double { Double(size.height) * 0.81 }

    static func drawApp(_ world: World, _ ctx: GraphicsContext, size: CGSize, k: CritterKnobs, layer: Layer) {
        switch world {
        case .strata: strata(ctx, size: size, k: k, layer: layer)
        case .galaxy: galaxy(ctx, size: size, k: k, layer: layer)
        case .sky: sky(ctx, size: size, k: k, layer: layer)
        case .mist: mist(ctx, size: size, k: k, layer: layer)
        case .deepsea: deepsea(ctx, size: size, k: k, layer: layer)
        case .hinata: hinata(ctx, size: size, k: k, layer: layer)
        case .brutal: brutal(ctx, size: size, k: k, layer: layer)
        case .aurora: aurora(ctx, size: size, k: k, layer: layer)
        case .bento: bento(ctx, size: size, k: k, layer: layer)
        case .swiss: swiss(ctx, size: size, k: k, layer: layer)
        case .yohaku: yohaku(ctx, size: size, k: k, layer: layer)
        case .terminal: terminal(ctx, size: size, k: k, layer: layer)
        case .none, .clay: break
        }
    }

    // MARK: 地層：モグラがトンネルを掘り進む。完了で顔を出し、土がこぼれる

    static func tunnelY(_ x: Double, w: Double, lane: Double) -> Double {
        lane + sin(x / max(w, 1) * Double.pi * 3) * 4
    }

    @_optimize(none)
    static func strata(_ ctx: GraphicsContext, size: CGSize, k: CritterKnobs, layer: Layer) {
        let w: Double = Double(size.width)
        let lane: Double = laneY(size)
        let mx: Double = -24 + k.progress * (w + 48)
        let my: Double = tunnelY(mx, w: w, lane: lane)
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
                C.mole(D.local(ctx, at: D.pt(mx, my), scale: 1.05), t: k.t, digging: true)
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
            let swing: Double = sin(k.progress * 2 * Double.pi)
            let ax: Double = w * (0.5 + 0.34 * swing)
            let ay: Double = lane - 4 + sin(k.t * 0.8) * 6
            let angle: Double = sin(k.progress * 4 * Double.pi) * 0.55
            // つなぎ綱のような細い光の尾
            D.curve(ctx, D.pt(ax - 10, ay + 6), D.pt(ax - 26, ay + 18), D.pt(ax - 44, ay + 8), sceneColor(0xC9C5EA, 0.25), 0.8)
            C.astronaut(D.local(ctx, at: D.pt(ax, ay), scale: 1.1, angle: angle), t: k.t)
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

    @_optimize(none)
    static func mist(_ ctx: GraphicsContext, size: CGSize, k: CritterKnobs, layer: Layer) {
        let w: Double = Double(size.width)
        let lane: Double = laneY(size)
        let ground: Double = lane + 18
        let lanternX: Double = w * 0.12
        let lanternY: Double = lane - 18
        let lanternAt = D.pt(lanternX, lanternY)
        let swing: Double = sin(k.t * 1.1) * 0.22
        switch layer {
        case .idle:
            let dx: Double = w + 30 - k.progress * (w + 60)
            C.deer(D.local(ctx, at: D.pt(dx, ground), scale: 1.05), walk: k.t * 3.2, color: sceneColor(0x3E4A55, 0.55))
            // 手前の霧（鹿を奥にかすませる）
            let veil = Gradient(stops: [
                Gradient.Stop(color: sceneColor(0xECEEEE, 0), location: 0),
                Gradient.Stop(color: sceneColor(0xECEEEE, 0.42), location: 0.55),
                Gradient.Stop(color: sceneColor(0xECEEEE, 0), location: 1),
            ])
            let band = CGRect(x: 0, y: ground - 34, width: w, height: 46)
            ctx.fill(Path(band), with: .linearGradient(veil, startPoint: D.pt(0, band.minY), endPoint: D.pt(0, band.maxY)))
            C.lantern(D.local(ctx, at: lanternAt, scale: 1), swing: swing, flare: 0, ground: ground - lanternY)
        case .reaction:
            guard let r = k.react else { return }
            let flare: Double = sin(D.span(r, 0, 1) * Double.pi)
            let lx: Double = lanternX + 1 + sin(swing) * 10
            let ly: Double = lanternY - 3 + cos(swing) * 10
            D.glow(ctx, lx, ly, 26 + flare * 24, sceneColor(0xFFC77A), 0.55 * flare)
            // 灯りから小さな火の粉が昇る
            for i in 0..<4 {
                let u: Double = D.span(r, Double(i) * 0.1, 0.6 + Double(i) * 0.1)
                guard u > 0 && u < 1 else { continue }
                let px: Double = lx + sin(u * 6 + Double(i)) * 5
                let py: Double = ly - 6 - u * 34
                D.circle(ctx, px, py, 1.3, sceneColor(0xFFD9A0, 0.9 * (1 - u)))
            }
        }
    }

    // MARK: 深海：クジラがゆっくり通り、チョウチンアンコウが光る。完了で泡

    @_optimize(none)
    static func deepsea(_ ctx: GraphicsContext, size: CGSize, k: CritterKnobs, layer: Layer) {
        let w: Double = Double(size.width)
        let h: Double = Double(size.height)
        let lane: Double = laneY(size)
        let anglerX: Double = w * 0.34   // 背景のクラゲ（左下）と重ならないように
        let anglerY: Double = lane + 20 + sin(k.t * 0.9) * 2
        let anglerAt = D.pt(anglerX, anglerY)
        switch layer {
        case .idle:
            let wx: Double = w + 60 - k.progress * (w + 120)
            let wy: Double = lane - 8 + sin(k.t * 0.4) * 4
            C.whale(D.local(ctx, at: D.pt(wx, wy), scale: 0.95), t: k.t)
            let glow: Double = 0.5 + 0.5 * sin(k.t * 2.2)
            C.angler(D.local(ctx, at: anglerAt, scale: 1.05), glow: glow)
        case .reaction:
            guard let r = k.react else { return }
            for i in 0..<10 {
                let d: Double = Double(i) * 0.06
                let u: Double = D.span(r, d, d + 0.7)
                guard u > 0 && u < 1 else { continue }
                let fromAngler: Bool = i % 3 == 0
                let baseX: Double = fromAngler ? anglerX + 8 : (i % 2 == 0 ? 9 : w - 9)
                let rise: Double = fromAngler ? 110 : h * 0.7
                let x: Double = baseX + sin(u * 8 + Double(i)) * 3
                let y: Double = (fromAngler ? anglerY - 6 : h * 0.9) - u * rise
                let rr: Double = 2 + Double(i % 3) * 1.2
                C.bubble(ctx, x, y, rr, 1 - u * 0.8)
            }
        }
    }

    // MARK: 日なた：日だまりで猫が丸くなり、ときどき伸びをする。完了でも伸び

    @_optimize(none)
    static func hinata(_ ctx: GraphicsContext, size: CGSize, k: CritterKnobs, layer: Layer) {
        let w: Double = Double(size.width)
        let lane: Double = laneY(size)
        let cx: Double = w * 0.3
        let cy: Double = lane + 16
        switch layer {
        case .idle:
            var pool: GraphicsContext = ctx
            pool.translateBy(x: cx + 4, y: cy - 2)
            pool.scaleBy(x: 1, y: 0.32)
            D.glow(pool, 0, 0, 64, sceneColor(0xFFD08A), 0.7)
            let u: Double = (k.t / 16).truncatingRemainder(dividingBy: 1)
            let auto: Double = sin(D.span(u, 0.8, 1) * Double.pi)
            let byReact: Double = k.react.map { sin($0 * Double.pi) } ?? 0
            let stretch: Double = D.ease(max(auto, byReact))
            let breathe: Double = sin(k.t * 1.6)
            C.cat(D.local(ctx, at: D.pt(cx, cy), scale: 1.15), stretch: stretch, breathe: breathe)
            if stretch < 0.05 {
                let zu: Double = (k.t / 3).truncatingRemainder(dividingBy: 1)
                let z = Text("z").font(.system(size: 9, weight: .bold, design: .rounded))
                    .foregroundColor(sceneColor(0xB4461E, 0.55 * sin(zu * Double.pi)))
                ctx.draw(z, at: D.pt(cx - 20 + zu * 4, cy - 26 - zu * 10))
            }
        case .reaction:
            guard let r = k.react else { return }
            // 伸びは idle の側で描く。ここでは小さな光の粒
            for i in 0..<3 {
                let u: Double = D.span(r, Double(i) * 0.12, 0.6 + Double(i) * 0.12)
                guard u > 0 && u < 1 else { continue }
                let px: Double = cx - 18 + Double(i) * 16
                let py: Double = cy - 30 - u * 12
                D.glow(ctx, px, py, 6, sceneColor(0xFFB347), 0.9 * sin(u * Double.pi))
            }
        }
    }

    // MARK: ネオブルータル：完了で「ペタッ」とシールが貼られ、はんこが押される

    static func stickerSpot(_ i: Int, w: Double, lane: Double) -> (CGPoint, Double) {
        let x: Double = w * 0.09 + Double(i) * 34
        let y: Double = lane + (i % 2 == 0 ? -4 : 9)
        let angle: Double = i % 2 == 0 ? -0.2 : 0.16
        return (D.pt(x, y), angle)
    }

    @_optimize(none)
    static func brutal(_ ctx: GraphicsContext, size: CGSize, k: CritterKnobs, layer: Layer) {
        let w: Double = Double(size.width)
        let lane: Double = laneY(size)
        let shown: Int = min(6, k.count + 1)
        let newest: Int = shown - 1
        switch layer {
        case .idle:
            for i in 0..<shown {
                let spot = stickerSpot(i, w: w, lane: lane)
                var scale: Double = 1
                if i == newest, i > 0, let r = k.react {
                    scale = 1.9 - 0.9 * D.bounce(D.span(r, 0, 0.45))
                }
                C.sticker(D.local(ctx, at: spot.0, scale: scale, angle: spot.1), kind: i)
            }
        case .reaction:
            guard k.react != nil, let r = k.react else { return }
            let spot = stickerSpot(newest, w: w, lane: lane)
            let pa: Double = D.span(r, 0.05, 0.15) * (1 - D.span(r, 0.55, 0.75))
            let peta = Text("ペタッ").font(.system(size: 12, weight: .black)).foregroundColor(Color.black.opacity(pa))
            let sx: Double = Double(spot.0.x)
            let sy: Double = Double(spot.0.y)
            ctx.draw(peta, at: D.pt(sx + 6, sy - 22))
            let press: Double = D.span(r, 0.35, 0.5)
            guard press > 0 else { return }
            let stampScale: Double = 1.45 - 0.45 * D.bounce(press)
            let stampAlpha: Double = min(1, press * 3) * (1 - D.span(r, 0.85, 1))
            C.stamp(D.local(ctx, at: D.pt(sx + 26, sy + 2), scale: stampScale, angle: -0.22), alpha: stampAlpha)
        }
    }

    // MARK: オーロラ：光のカーテンが揺れ、狐が駆け抜ける（完了でも駆ける）

    @_optimize(none)
    static func aurora(_ ctx: GraphicsContext, size: CGSize, k: CritterKnobs, layer: Layer) {
        let w: Double = Double(size.width)
        let h: Double = Double(size.height)
        let lane: Double = laneY(size)
        switch layer {
        case .idle:
            let colors: [UInt32] = [0x5CF2C8, 0x9EF0E6, 0xB28CFF]
            for i in 0..<3 {
                let fi: Double = Double(i)
                let top: Double = h * (0.05 + 0.075 * fi)
                let phase: Double = k.t * 0.22 * (1 + fi * 0.3) + fi * 1.7
                C.auroraCurtain(ctx, width: w, top: top, amp: 14, thick: 64 - fi * 10, wave: 1.1 + fi * 0.35,
                                phase: phase, color: sceneColor(colors[i]), alpha: 0.24)
            }
            // うっすら雪の地面
            D.line(ctx, D.pt(-10, lane + 13), D.pt(w + 10, lane + 13), Color.white.opacity(0.1), 1)
            guard k.react == nil else { return }
            let u: Double = (k.t / period(.aurora)).truncatingRemainder(dividingBy: 1)
            let dash: Double = D.span(u, 0.4, 0.6)
            guard dash > 0 && dash < 1 else { return }
            let fx: Double = -30 + dash * (w + 60)
            let hop: Double = abs(sin(k.t * 7)) * 2
            C.fox(D.local(ctx, at: D.pt(fx, lane + 12 - hop), scale: 1.05), run: k.t * 14)
        case .reaction:
            guard let r = k.react else { return }
            let fx: Double = -30 + D.span(r, 0, 0.9) * (w + 60)
            let hop: Double = abs(sin(r * 40)) * 2
            C.fox(D.local(ctx, at: D.pt(fx, lane + 12 - hop), scale: 1.05), run: r * 70)
        }
    }

    // MARK: ベント：小さなタイルの箱。ときどき「ぽこっ」と入れ替わる。完了で新しいタイルが入る

    @_optimize(none)
    static func bento(_ ctx: GraphicsContext, size: CGSize, k: CritterKnobs, layer: Layer) {
        let w: Double = Double(size.width)
        let lane: Double = laneY(size)
        let cell: Double = 16
        let gap: Double = 3
        let ox: Double = w * 0.07
        let oy: Double = lane - 14
        let orders: [[Int]] = C.bentoOrders
        switch layer {
        case .idle:
            let boxRect = CGRect(x: ox - 4, y: oy - 4, width: cell * 3 + gap * 2 + 8, height: cell * 2 + gap + 8)
            ctx.fill(Path(roundedRect: boxRect, cornerRadius: 8), with: .color(Color.white.opacity(0.75)))
            ctx.stroke(Path(roundedRect: boxRect, cornerRadius: 8), with: .color(sceneColor(0x1E1B16, 0.12)), lineWidth: 1)
            let step: Double = 3.2
            let n: Int = Int(floor(k.t / step))
            let u: Double = k.t / step - Double(n)
            let now: [Int] = orders[((n % orders.count) + orders.count) % orders.count]
            let before: [Int] = orders[(((n - 1) % orders.count) + orders.count) % orders.count]
            let move: Double = D.ease(D.span(u, 0, 0.22))
            for i in 0..<C.bentoColors.count {
                let a: CGPoint = C.bentoSlot(before[i], cell: cell, gap: gap)
                let b: CGPoint = C.bentoSlot(now[i], cell: cell, gap: gap)
                let x: Double = ox + Double(a.x) + Double(b.x - a.x) * move + cell / 2
                let y: Double = oy + Double(a.y) + Double(b.y - a.y) * move + cell / 2
                let moved: Bool = before[i] != now[i]
                let pop: Double = moved ? sin(D.span(u, 0.12, 0.34) * Double.pi) * 0.22 : 0
                C.bentoTile(ctx, center: D.pt(x, y), size: cell, color: sceneColor(C.bentoColors[i]), pop: pop)
            }
        case .reaction:
            guard let r = k.react else { return }
            // 箱の右に、完了のタイルがぽこっと入る
            let x: Double = ox + cell * 3 + gap * 2 + 18
            let y: Double = oy + cell / 2 + 2
            let grow: Double = D.bounce(D.span(r, 0, 0.4))
            let alpha: Double = 1 - D.span(r, 0.8, 1)
            var c: GraphicsContext = ctx
            c.opacity = alpha
            C.bentoTile(c, center: D.pt(x, y), size: cell * 1.3 * grow, color: sceneColor(0x1F3D36), pop: 0)
            if grow > 0.5 {
                let check = Text(Image(systemName: "checkmark")).font(.system(size: 11, weight: .black)).foregroundColor(.white)
                c.draw(check, at: D.pt(x, y))
            }
            let pa: Double = D.span(r, 0.1, 0.2) * (1 - D.span(r, 0.55, 0.75))
            let poko = Text("ぽこっ").font(.system(size: 10, weight: .heavy)).foregroundColor(sceneColor(0x1F3D36, pa))
            ctx.draw(poko, at: D.pt(x, y - 22))
        }
    }

    // MARK: スイス：円と針・四角・三角が時計の針のように回る。完了で1回転

    @_optimize(none)
    static func swiss(_ ctx: GraphicsContext, size: CGSize, k: CritterKnobs, layer: Layer) {
        let w: Double = Double(size.width)
        let lane: Double = laneY(size)
        guard layer == .idle else { return }
        let spin: Double = k.react.map { D.ease($0) * 2 * Double.pi } ?? 0
        let hour: Double = k.day * 2 * 2 * Double.pi
        let minute: Double = k.day * 24 * 2 * Double.pi
        let second: Double = (k.t / 60).truncatingRemainder(dividingBy: 1) * 2 * Double.pi + spin
        let dx: Double = w * 0.1 + 6
        let dialAt = D.pt(dx, lane)
        C.swissDial(D.local(ctx, at: dialAt, scale: 1), hour: hour, minute: minute, second: second, radius: 18)
        // 赤い四角（秒の半分の速さ）と黒い三角（逆回り）
        let sq: GraphicsContext = D.local(ctx, at: D.pt(dx + 42, lane + 2), scale: 1, angle: second / 2 + spin)
        sq.fill(Path(CGRect(x: -7, y: -7, width: 14, height: 14)), with: .color(sceneColor(0xD71F16)))
        sq.fill(Path(CGRect(x: -1, y: -7, width: 2, height: 7)), with: .color(Color.white))
        let tri: GraphicsContext = D.local(ctx, at: D.pt(dx + 74, lane + 1), scale: 1, angle: -second / 3 - spin)
        D.polygon(tri, [D.pt(0, -9), D.pt(8, 6), D.pt(-8, 6)], sceneColor(0x111111))
        D.line(ctx, D.pt(dx + 24, lane + 16), D.pt(dx + 92, lane + 16), sceneColor(0x111111, 0.35), 1)
    }
}
