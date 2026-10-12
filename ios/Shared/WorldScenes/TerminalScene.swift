import SwiftUI

/// MARK: - ターミナル：古いブラウン管の端末。黒地に燐光の緑がやわらかくにじみ、細い走査線と、丸みのある管面の縁の暗がり
// 管面（地・燐光・走査線・縁の暗がり）は動かないので一度だけ描く。動くのは、ごく淡い書き換えの帯がゆっくり下りるだけ。
// 住人の層は「$ 」のあとに人が打つ速さでコマンドが一字ずつ打たれ、四角いカーソルが点滅する。完了で「done ✓」が打ち出される。

enum TerminalScene {
    static let green: UInt32 = 0x5CF27A
    static let dim: UInt32 = 0x7FA889
    static let amber: UInt32 = 0xFFB547

    /// 動かない管面（地・燐光のにじみ・走査線・樽形の縁の暗がり）
    @_optimize(none)
    static func drawTube(_ ctx: GraphicsContext, size: CGSize, compact: Bool) {
        let w: Double = Double(size.width)
        let h: Double = Double(size.height)
        let rect = CGRect(origin: .zero, size: size)
        let base = Gradient(colors: [sceneColor(0x0B100C), sceneColor(0x070A07)])
        ctx.fill(Path(rect), with: .linearGradient(base, startPoint: CGPoint(x: 0, y: 0), endPoint: CGPoint(x: 0, y: h)))
        // 燐光のにじみ（管面の真ん中がほんのり明るい。楕円にのばす）
        var tube: GraphicsContext = ctx
        tube.translateBy(x: w * 0.5, y: h * 0.46)
        tube.scaleBy(x: w * 0.5, y: h * 0.5)
        let glowStops: [Gradient.Stop] = [
            Gradient.Stop(color: sceneColor(green, 0.075), location: 0),
            Gradient.Stop(color: sceneColor(green, 0.04), location: 0.45),
            Gradient.Stop(color: sceneColor(green, 0.012), location: 0.8),
            Gradient.Stop(color: sceneColor(green, 0), location: 1),
        ]
        let unit = CGRect(x: -1.6, y: -1.6, width: 3.2, height: 3.2)
        tube.fill(Path(unit), with: .radialGradient(Gradient(stops: glowStops), center: .zero, startRadius: 0, endRadius: 1.1))
        // 走査線（2pt ごとに細い暗い線。1つの Path にまとめて塗る）
        let pitch: Double = 2
        var lines = Path()
        var y: Double = 0
        while y < h {
            lines.addRect(CGRect(x: 0, y: y, width: w, height: 0.7))
            y += pitch
        }
        ctx.fill(lines, with: .color(Color.black.opacity(compact ? 0.16 : 0.22)))
        // 樽形の縁の暗がり（管面の丸みで四隅ほど暗く落ちる）
        var edge: GraphicsContext = ctx
        edge.translateBy(x: w * 0.5, y: h * 0.5)
        edge.scaleBy(x: w * 0.5, y: h * 0.5)
        let vignetteStops: [Gradient.Stop] = [
            Gradient.Stop(color: Color.black.opacity(0), location: 0),
            Gradient.Stop(color: Color.black.opacity(0), location: 0.5),
            Gradient.Stop(color: Color.black.opacity(0.18), location: 0.72),
            Gradient.Stop(color: Color.black.opacity(0.5), location: 0.9),
            Gradient.Stop(color: Color.black.opacity(0.75), location: 1),
        ]
        edge.fill(Path(unit), with: .radialGradient(Gradient(stops: vignetteStops), center: .zero, startRadius: 0, endRadius: 1.42))
    }

    /// 書き換えの帯（ごく淡い明るい帯が 16秒かけて上から下へ）
    @_optimize(none)
    static func drawRoll(_ ctx: GraphicsContext, size: CGSize, t: Double) {
        let w: Double = Double(size.width)
        let h: Double = Double(size.height)
        let bandH: Double = h * 0.16
        let roll: Double = (t / 16).truncatingRemainder(dividingBy: 1)
        let by: Double = roll * (h + bandH * 2) - bandH
        let bandStops: [Gradient.Stop] = [
            Gradient.Stop(color: sceneColor(green, 0), location: 0),
            Gradient.Stop(color: sceneColor(green, 0.022), location: 0.75),
            Gradient.Stop(color: sceneColor(green, 0), location: 1),
        ]
        let bandRect = CGRect(x: 0, y: by, width: w, height: bandH)
        ctx.fill(Path(bandRect), with: .linearGradient(Gradient(stops: bandStops),
                                                       startPoint: CGPoint(x: 0, y: by), endPoint: CGPoint(x: 0, y: by + bandH)))
    }

    /// 等幅の文字（住人の層で使う）
    static func mono(_ s: String, size: CGFloat, color: Color, bold: Bool = false) -> Text {
        let weight: Font.Weight = bold ? .bold : .regular
        return Text(s).font(Font.system(size: size, weight: weight, design: .monospaced)).foregroundColor(color)
    }
}

/// ターミナルの全画面の背景
struct TerminalBackdrop: View {
    let p: Palette
    var still: Bool = false
    var compact: Bool = false
    /// 止まった絵の時刻（ウィジェット用。entry.date から）
    var stillT: Double = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { geo in
            let animated: Bool = SceneMotion.animated(reduceMotion: reduceMotion, size: geo.size, still: still)
            ZStack {
                Canvas { ctx, size in
                    TerminalScene.drawTube(ctx, size: size, compact: compact)
                }
                if animated {
                    SceneClock(fps: 12, animated: true) { t in
                        Canvas { ctx, size in
                            TerminalScene.drawRoll(ctx, size: size, t: t)
                        }
                    }
                }
            }
        }
        .allowsHitTesting(false)
    }
}

// ターミナルのカード：少し明るい黒の窓。緑の細い縁と、上にうっすら光る線
struct TerminalPane: View {
    let p: Palette
    var radius: CGFloat? = nil
    var light: Bool = false

    var body: some View {
        let r: CGFloat = radius ?? p.radius
        let shape = RoundedRectangle(cornerRadius: r, style: .continuous)
        let edge: Color = sceneColor(TerminalScene.green, light ? 0.28 : 0.32)
        let top = LinearGradient(colors: [sceneColor(TerminalScene.green, 0.10), sceneColor(TerminalScene.green, 0)],
                                 startPoint: .top, endPoint: .center)
        ZStack {
            shape.fill(p.card)
            if !light {
                shape.fill(top)
            }
            shape.strokeBorder(edge, lineWidth: 1)
        }
        .shadow(color: sceneColor(TerminalScene.green, light ? 0 : 0.12), radius: 8)
    }
}

/// MARK: - 住人：「$ 」のあとに、人が打つ速さ（1秒に6〜7字・ゆらぎあり）でコマンドが打たれ、カーソルが点滅する。完了で done ✓ を打ち出す

extension CritterArt {
    static let terminalCommands: [String] = ["todo list", "uptime", "date +%H:%M", "todo next"]

    /// 1つのコマンドの長さ（秒）。打つ前に少し待ち、打ち終わったら読む間だけ止まる
    static let terminalSlot: Double = 9

    /// 各コマンドの、i 字目を打ち終える時刻（打ち始めからの秒）。一字ごとの間は少しずつ違う（空白や記号の前は少し長い）
    static let terminalTiming: [[Double]] = {
        var rnd = SceneRandom(4242)
        var out: [[Double]] = []
        for cmd in terminalCommands {
            var at: Double = 0
            var times: [Double] = []
            for ch in cmd {
                let slow: Bool = ch == " " || ch == "+" || ch == "%" || ch == ":"
                let gap: Double = slow ? rnd.range(0.18, 0.32) : rnd.range(0.08, 0.19)
                at += gap
                times.append(at)
            }
            out.append(times)
        }
        return out
    }()

    @_optimize(none)
    static func terminal(_ ctx: GraphicsContext, size: CGSize, k: CritterKnobs, layer: Layer) {
        let lane: Double = laneY(size)
        let x0: Double = 24
        let fontSize: CGFloat = 12
        let lineH: Double = 18
        // 燐光のにじみ（文字のまわりに淡い緑の光）
        var lit: GraphicsContext = ctx
        lit.addFilter(.shadow(color: sceneColor(TerminalScene.green, 0.55), radius: 3.5))
        switch layer {
        case .idle:
            // 完了の反応の間は、反応の層が同じ行に打つ
            if k.react != nil { return }
            let slot: Double = terminalSlot
            let index: Int = Int(k.t / slot) % terminalCommands.count
            let local: Double = k.t.truncatingRemainder(dividingBy: slot)
            let cmd: String = terminalCommands[max(0, index)]
            let times: [Double] = terminalTiming[max(0, index)]
            let typingFrom: Double = 1.2
            let since: Double = local - typingFrom
            var shown: Int = 0
            for tm in times where tm <= since { shown += 1 }
            let typed: String = String(cmd.prefix(shown))
            let prompt: GraphicsContext.ResolvedText = lit.resolve(TerminalScene.mono("$", size: fontSize, color: sceneColor(TerminalScene.green, 0.8), bold: true))
            let promptSize: CGSize = prompt.measure(in: CGSize(width: 400, height: 40))
            lit.draw(prompt, at: D.pt(x0, lane), anchor: .leading)
            let textX: Double = x0 + Double(promptSize.width) + 7
            let body: GraphicsContext.ResolvedText = lit.resolve(TerminalScene.mono(typed, size: fontSize, color: sceneColor(0xB8EBC2, 0.9)))
            let bodySize: CGSize = body.measure(in: CGSize(width: 600, height: 40))
            lit.draw(body, at: D.pt(textX, lane), anchor: .leading)
            // 四角いカーソル（打っている間はつきっぱなし、止まると 0.53秒ずつ点滅）
            let lastTime: Double = times.last ?? 0
            let typing: Bool = since > 0 && since < lastTime + 0.3
            let blinkOn: Bool = typing || Int(local / 0.53).isMultiple(of: 2)
            if blinkOn {
                let cx: Double = textX + Double(bodySize.width) + (shown > 0 ? 1.5 : 0)
                let cursor = CGRect(x: cx, y: lane - 7, width: 7, height: 14)
                lit.fill(Path(cursor), with: .color(sceneColor(TerminalScene.green, 0.75)))
            }
        case .reaction:
            guard let r = k.react else { return }
            // 「$ todo done」を人の速さで打ち、少し置いて「done ✓」が返ってくる
            let cmd: String = "todo done"
            let typedCount: Int = Int(D.span(r, 0.04, 0.36) * Double(cmd.count) + 0.5)
            let typed: String = String(cmd.prefix(typedCount))
            let alpha: Double = min(1, r * 10) * (1 - D.span(r, 0.84, 1))
            let y: Double = lane - lineH * 0.5
            lit.opacity = alpha
            let line1: GraphicsContext.ResolvedText = lit.resolve(TerminalScene.mono("$ " + typed, size: fontSize, color: sceneColor(0xB8EBC2), bold: false))
            let s1: CGSize = line1.measure(in: CGSize(width: 600, height: 40))
            lit.draw(line1, at: D.pt(x0, y), anchor: .leading)
            let answered: Bool = r > 0.46
            if !answered {
                let cursor = CGRect(x: x0 + Double(s1.width) + 1.5, y: y - 7, width: 7, height: 14)
                lit.fill(Path(cursor), with: .color(sceneColor(TerminalScene.green, 0.75)))
            } else {
                let fresh: Double = 1 - D.span(r, 0.46, 0.62) * 0.35
                let line2: GraphicsContext.ResolvedText = lit.resolve(TerminalScene.mono("done ✓", size: fontSize, color: sceneColor(0xE9FFEC, fresh), bold: true))
                lit.draw(line2, at: D.pt(x0, y + lineH), anchor: .leading)
            }
        }
    }
}

// ウィジェット：下の余白に「$」と、一日かけて右へ進むカーソル。通った跡は点線（15分ごとにカーソルが明滅する）
struct WidgetTerminal: View {
    let size: CGSize
    let k: CritterKnobs

    var body: some View {
        let w: CGFloat = size.width
        let y: CGFloat = CritterWidgetArt.laneY(size.height)
        let left: CGFloat = 20
        let span: CGFloat = max(1, w - 34)
        let day: CGFloat = CGFloat(max(0.02, min(1, k.day)))
        let cx: CGFloat = left + span * day
        let trailW: CGFloat = max(1, cx - left - 4)
        let slot: Int = Int(k.day * 96)
        let lit: Double = slot.isMultiple(of: 2) ? 1 : 0.55
        let green: Color = sceneColor(TerminalScene.green)
        let dots = StrokeStyle(lineWidth: 1, lineCap: .round, dash: [1, 3])
        ZStack {
            Text("$").font(Font.system(size: 9, weight: .bold, design: .monospaced)).foregroundColor(green.opacity(0.8))
                .position(x: 11, y: y)
            Path { path in
                path.move(to: CGPoint(x: 0, y: 0.5))
                path.addLine(to: CGPoint(x: trailW, y: 0.5))
            }
            .stroke(sceneColor(TerminalScene.dim, 0.55), style: dots)
            .frame(width: trailW, height: 1)
            .position(x: left + trailW / 2, y: y)
            Rectangle().fill(green.opacity(lit)).frame(width: 5, height: 9)
                .shadow(color: green.opacity(0.6 * lit), radius: 3)
                .position(x: cx, y: y)
        }
    }
}
