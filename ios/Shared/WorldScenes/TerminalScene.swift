import SwiftUI

// MARK: - ターミナル：黒地に燐光の緑。細い走査線、画面の縁の暗がり、ゆっくり下りる書き換えの帯
// 住人の層は「$ 」のあとにコマンドが一字ずつ打たれ、四角いカーソルが点滅する。完了で「done ✓」が打ち出される。

enum TerminalScene {
    static let green: UInt32 = 0x5CF27A
    static let dim: UInt32 = 0x7FA889
    static let amber: UInt32 = 0xFFB547

    @_optimize(none)
    static func draw(_ ctx: GraphicsContext, size: CGSize, t: Double, compact: Bool) {
        let w: Double = Double(size.width)
        let h: Double = Double(size.height)
        let rect = CGRect(origin: .zero, size: size)
        let base = Gradient(colors: [sceneColor(0x0B0F0B), sceneColor(0x060906)])
        ctx.fill(Path(rect), with: .linearGradient(base, startPoint: CGPoint(x: 0, y: 0), endPoint: CGPoint(x: 0, y: h)))
        // 管面のほのかな光（真ん中が少し明るい）
        let center = CGPoint(x: w * 0.5, y: h * 0.42)
        let glowStops: [Gradient.Stop] = [
            Gradient.Stop(color: sceneColor(green, 0.07), location: 0),
            Gradient.Stop(color: sceneColor(green, 0.02), location: 0.55),
            Gradient.Stop(color: sceneColor(green, 0), location: 1),
        ]
        let reach: Double = max(w, h) * 0.75
        ctx.fill(Path(rect), with: .radialGradient(Gradient(stops: glowStops), center: center, startRadius: 0, endRadius: reach))
        // ゆっくり下りる書き換えの帯
        let bandH: Double = compact ? 26 : 70
        let roll: Double = (t / 11).truncatingRemainder(dividingBy: 1)
        let by: Double = roll * (h + bandH * 2) - bandH
        let bandStops: [Gradient.Stop] = [
            Gradient.Stop(color: sceneColor(green, 0), location: 0),
            Gradient.Stop(color: sceneColor(green, 0.045), location: 0.8),
            Gradient.Stop(color: sceneColor(green, 0), location: 1),
        ]
        let bandRect = CGRect(x: 0, y: by, width: w, height: bandH)
        ctx.fill(Path(bandRect), with: .linearGradient(Gradient(stops: bandStops),
                                                       startPoint: CGPoint(x: 0, y: by), endPoint: CGPoint(x: 0, y: by + bandH)))
        // 走査線（3pt ごとに暗い線を1本。1つの Path にまとめて塗る）
        var lines = Path()
        var y: Double = 0
        while y < h {
            lines.addRect(CGRect(x: 0, y: y, width: w, height: 1))
            y += 3
        }
        ctx.fill(lines, with: .color(Color.black.opacity(0.28)))
        // 縁の暗がり
        let vignetteStops: [Gradient.Stop] = [
            Gradient.Stop(color: Color.black.opacity(0), location: 0.55),
            Gradient.Stop(color: Color.black.opacity(0.45), location: 1),
        ]
        let vCenter = CGPoint(x: w * 0.5, y: h * 0.5)
        let vReach: Double = hypot(w, h) * 0.55
        ctx.fill(Path(rect), with: .radialGradient(Gradient(stops: vignetteStops), center: vCenter, startRadius: 0, endRadius: vReach))
        // 右上の小さな表示灯（ゆっくり明滅）
        let lamp: Double = 0.45 + 0.35 * (0.5 + 0.5 * sin(t * 1.3))
        let lampX: Double = w - (compact ? 10 : 18)
        let lampY: Double = compact ? 8 : h * 0.065
        CritterDraw.glow(ctx, lampX, lampY, compact ? 6 : 9, sceneColor(green), 0.35 * lamp)
        CritterDraw.circle(ctx, lampX, lampY, 1.5, sceneColor(green, lamp))
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
            SceneClock(fps: 15, animated: animated, stillT: stillT) { t in
                Canvas { ctx, size in
                    TerminalScene.draw(ctx, size: size, t: t, compact: compact)
                }
            }
        }
        .allowsHitTesting(false)
    }
}

/// ターミナルのカード：少し明るい黒の窓。緑の細い縁と、上にうっすら光る線
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

// MARK: - 住人：「$ 」のあとにコマンドが一字ずつ打たれ、カーソルが点滅する。完了で done ✓ を打ち出す

extension CritterArt {
    static let terminalCommands: [String] = ["todo list", "uptime", "date +%H:%M", "echo 日和", "ls ~/today", "todo next"]

    @_optimize(none)
    static func terminal(_ ctx: GraphicsContext, size: CGSize, k: CritterKnobs, layer: Layer) {
        let lane: Double = laneY(size)
        let x0: Double = 24
        let fontSize: CGFloat = 12
        let lineH: Double = 18
        switch layer {
        case .idle:
            let slot: Double = 6
            let index: Int = Int(k.t / slot) % terminalCommands.count
            let local: Double = k.t.truncatingRemainder(dividingBy: slot)
            let cmd: String = terminalCommands[max(0, index)]
            let shown: Int = min(cmd.count, max(0, Int(local * 9) - 3))
            let typed: String = String(cmd.prefix(shown))
            let prompt: GraphicsContext.ResolvedText = ctx.resolve(TerminalScene.mono("$", size: fontSize, color: sceneColor(TerminalScene.green, 0.75), bold: true))
            let promptSize: CGSize = prompt.measure(in: CGSize(width: 400, height: 40))
            ctx.draw(prompt, at: D.pt(x0, lane), anchor: .leading)
            let textX: Double = x0 + Double(promptSize.width) + 7
            let body: GraphicsContext.ResolvedText = ctx.resolve(TerminalScene.mono(typed, size: fontSize, color: sceneColor(TerminalScene.dim, 0.85)))
            let bodySize: CGSize = body.measure(in: CGSize(width: 600, height: 40))
            ctx.draw(body, at: D.pt(textX, lane), anchor: .leading)
            // 四角いカーソル（打っている間はつきっぱなし、止まると点滅）
            let typing: Bool = shown < cmd.count && shown > 0
            let blinkOn: Bool = typing || Int(k.t * 2).isMultiple(of: 2)
            if blinkOn {
                let cx: Double = textX + Double(bodySize.width) + (shown > 0 ? 1.5 : 0)
                let cursor = CGRect(x: cx, y: lane - 7, width: 7, height: 14)
                ctx.fill(Path(cursor), with: .color(sceneColor(TerminalScene.green, 0.8)))
                D.glow(ctx, cx + 3.5, lane, 12, sceneColor(TerminalScene.green), 0.18)
            }
        case .reaction:
            guard let r = k.react else { return }
            let full: String = "todo done …… done ✓"
            let typedCount: Int = Int(D.span(r, 0.02, 0.55) * Double(full.count) + 0.5)
            let typed: String = String(full.prefix(typedCount))
            let alpha: Double = min(1, r * 10) * (1 - D.span(r, 0.82, 1))
            let y: Double = lane - lineH * 1.6
            // ほのかに光る行の地（打ち出した瞬間だけ明るい）
            let flash: Double = 0.10 * (1 - D.span(r, 0, 0.35)) + 0.04
            let rowRect = CGRect(x: x0 - 8, y: y - lineH / 2, width: Double(size.width) - (x0 - 8) * 2, height: lineH)
            ctx.fill(Path(roundedRect: rowRect, cornerRadius: 3), with: .color(sceneColor(TerminalScene.green, flash * alpha)))
            var lit: GraphicsContext = ctx
            lit.opacity = alpha
            lit.addFilter(.shadow(color: sceneColor(TerminalScene.green, 0.8), radius: 4))
            let gt: GraphicsContext.ResolvedText = lit.resolve(TerminalScene.mono("> " + typed, size: fontSize, color: sceneColor(0xE9FFEC), bold: true))
            let gs: CGSize = gt.measure(in: CGSize(width: 600, height: 40))
            lit.draw(gt, at: D.pt(x0, y), anchor: .leading)
            // 打ち終わるまでは先頭に琥珀のカーソル
            if typedCount < full.count {
                let cursor = CGRect(x: x0 + Double(gs.width) + 1.5, y: y - 7, width: 7, height: 14)
                lit.fill(Path(cursor), with: .color(sceneColor(TerminalScene.amber, 0.9)))
            }
        }
    }
}

/// ウィジェット：下の余白に「$」と、一日かけて右へ進むカーソル。通った跡は点線（15分ごとにカーソルが明滅する）
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
