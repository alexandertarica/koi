import SwiftUI

struct KoiDial: View {
    let score: Double
    let habits: Double
    let nutrition: Double
    let exercise: Double
    let onScoreTap: () -> Void
    let onPillarTap: (HubPillar) -> Void
    let weights: BalanceWeights
    @AppStorage("koiDialRevealDay") private var revealDay = ""
    @State private var revealProgress = 0.0

    private let ivory = KoiTheme.onBase

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            let scale = min(max(size.height / 470, 0.6), 1)
            let radius = size.height / 2 - 14 * scale
            let barRadius = radius - 24 * scale
            let safeScore = min(max(score.isFinite ? score : 0, 0), 1)
            ZStack(alignment: .topLeading) {
                Canvas { context, canvasSize in
                    drawDial(in: &context, size: canvasSize, scale: scale, radius: radius, barRadius: barRadius, score: safeScore * revealProgress)
                }
                hero(score: safeScore)
                    .contentShape(Rectangle())
                    .onTapGesture(perform: onScoreTap)
                pillarLabels(size: size, scale: scale, barRadius: barRadius)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .onAppear {
            let today = Date.now.formatted(.iso8601.year().month().day())
            guard revealDay != today else { revealProgress = 1; return }
            withAnimation(.timingCurve(0.22, 1, 0.36, 1, duration: 1.65)) { revealProgress = 1 }
            revealDay = today
            KoiHaptics.dialSweep(score: score, duration: 1.65)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Balance dial")
    }

    private func hero(score: Double) -> some View {
        VStack(alignment: .trailing, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 0) {
                Text("\(Int((score * 100 * revealProgress).rounded()))")
                    .font(.system(size: 80, weight: .regular))
                    .contentTransition(.numericText())
                Text("%")
                    .font(.system(size: 40, weight: .regular))
                    .baselineOffset(10)
            }
            .foregroundStyle(ivory.opacity(0.8))
            .shadow(color: ivory.opacity(0.2), radius: 12)
            Text("BALANCE")
                .font(KoiTheme.section)
                .tracking(2.7)
                .foregroundStyle(ivory.opacity(0.8))
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
        .padding(.top, 4)
        .padding(.trailing, KoiTheme.space.s21)
    }

    @ViewBuilder private func pillarLabels(size: CGSize, scale: CGFloat, barRadius: CGFloat) -> some View {
        let values: [(HubPillar, Double, Double)] = [(.habits, habits, weights.habits), (.nutrition, nutrition, weights.nutrition), (.exercise, exercise, weights.exercise)]
        ForEach(Array(values.enumerated()), id: \.offset) { _, item in
            let start = values.prefix { $0.0 != item.0 }.reduce(0.0) { $0 + $1.2 }
            let mid = start + item.2 / 2
            let midpointAngle = -Double.pi / 2 + Double.pi * mid
            let angle = midpointAngle * 0.5
            let r = barRadius - 14 * scale
            let point = CGPoint(x: r * cos(angle), y: size.height / 2 + r * sin(angle))
            Button { onPillarTap(item.0) } label: {
                VStack(alignment: .trailing, spacing: 2) {
                    Text("\(Int((item.1 * 100).rounded()))%")
                        .font(.custom("RobotoMono-Light", size: 15))
                    HStack(spacing: 2) {
                        Text(item.0.rawValue.uppercased())
                        Text("›")
                    }
                    .font(.custom("RobotoMono-Regular", size: 12))
                    .tracking(1)
                }
                .foregroundStyle(ivory.opacity(0.88))
                .frame(width: 110, alignment: .trailing)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .position(x: point.x - 55, y: point.y)
            .accessibilityLabel("\(item.0.rawValue), \(Int(item.1 * 100)) percent")
        }
    }

    private func drawDial(in context: inout GraphicsContext, size: CGSize, scale: CGFloat, radius: CGFloat, barRadius: CGFloat, score: Double) {
        let center = CGPoint(x: 0, y: size.height / 2)
        let active = min(max(score, 0), 1)
        let valueIndex = Int((active * 72).rounded())
        for index in 0...72 {
            let t = Double(index) / 72
            let angle = -Double.pi / 2 + Double.pi * t
            let fade = fadeOpacity(t)
            let isValue = index == valueIndex
            let isMajor = index.isMultiple(of: 5)
            let length = (isValue ? 20 : (isMajor ? 14 : 8)) * scale
            let outer = point(angle, radius + 18 * scale, center)
            let inner = point(angle, radius + 18 * scale - length, center)
            var tick = Path(); tick.move(to: inner); tick.addLine(to: outer)
            let lit = t <= active
            let opacity = (isValue ? 1 : (lit ? (isMajor ? 0.88 : 0.70) : 0.55)) * fade
            context.stroke(tick, with: .color(.white.opacity(opacity)), style: StrokeStyle(lineWidth: isValue ? 2.2 : (lit ? (isMajor ? 2 : 1.4) : 1), lineCap: .round))
        }

        for segment in 0..<90 {
            let t0 = Double(segment) / 90, t1 = Double(segment + 1) / 90
            let mid = (t0 + t1) / 2
            if abs(mid - active) < 0.014 { continue }
            let p0 = point(-Double.pi / 2 + Double.pi * t0, radius, center)
            let p1 = point(-Double.pi / 2 + Double.pi * t1, radius, center)
            var line = Path(); line.move(to: p0); line.addLine(to: p1)
            context.stroke(line, with: .color(.white.opacity((mid <= active ? 1 : 0.6) * fadeOpacity(mid))), lineWidth: mid <= active ? 1.5 : 1.2)
        }

        let pillars: [(Double, Double)] = [(habits, weights.habits), (nutrition, weights.nutrition), (exercise, weights.exercise)]
        var accumulated = 0.0
        for (index, (value, weight)) in pillars.enumerated() {
            let inset = 5.0 / 180
            let begin = accumulated + inset
            let finish = accumulated + weight - inset
            let delay = Double(index) * 0.08 / 1.65
            let fillProgress = min(max((revealProgress - delay) / (1 - delay), 0), 1)
            let fillEnd = begin + max(0, finish - begin) * min(max(value * fillProgress, 0), 1)
            strokeBar(&context, from: begin, to: finish, radius: barRadius, center: center, scale: scale, opacity: 0.45)
            strokeBar(&context, from: begin, to: fillEnd, radius: barRadius, center: center, scale: scale, opacity: 0.62)
            accumulated += weight
        }

        let beadT = max(active, 0.06)
        let bead = point(-Double.pi / 2 + Double.pi * beadT, radius, center)
        let beadRadius = 10 * scale
        let rect = CGRect(x: bead.x - beadRadius, y: bead.y - beadRadius, width: beadRadius * 2, height: beadRadius * 2)
        context.addFilter(.shadow(color: .black.opacity(0.18), radius: 6, x: 0, y: 3))
        context.fill(Path(ellipseIn: rect), with: .radialGradient(Gradient(colors: [.white.opacity(0.32), .white.opacity(0.10), .white.opacity(0.18)]), center: CGPoint(x: bead.x - beadRadius * 0.3, y: bead.y - beadRadius * 0.4), startRadius: 0, endRadius: beadRadius * 1.4))
        context.stroke(Path(ellipseIn: rect), with: .linearGradient(Gradient(colors: [.white.opacity(0.7), .white.opacity(0.15)]), startPoint: CGPoint(x: rect.minX, y: rect.minY), endPoint: CGPoint(x: rect.maxX, y: rect.maxY)), lineWidth: 1)
        let dot = beadRadius * 0.3
        context.fill(Path(ellipseIn: CGRect(x: bead.x - dot, y: bead.y - dot, width: dot * 2, height: dot * 2)), with: .color(.white))
    }

    private func strokeBar(_ context: inout GraphicsContext, from start: Double, to end: Double, radius: CGFloat, center: CGPoint, scale: CGFloat, opacity: Double) {
        guard end > start else { return }
        let segments = max(1, Int((end - start) * 90))
        for step in 0..<segments {
            let t0 = start + (end - start) * Double(step) / Double(segments)
            let t1 = start + (end - start) * Double(step + 1) / Double(segments)
            let p0 = point(-Double.pi / 2 + Double.pi * t0, radius, center)
            let p1 = point(-Double.pi / 2 + Double.pi * t1, radius, center)
            var path = Path(); path.move(to: p0); path.addLine(to: p1)
            let fade = max(0.3, fadeOpacity((t0 + t1) / 2))
            context.stroke(path, with: .color(.white.opacity(opacity * fade)), style: StrokeStyle(lineWidth: 4 * scale, lineCap: .butt))
        }
        for t in [start, end] {
            let location = point(-Double.pi / 2 + Double.pi * t, radius, center)
            let diameter = 4 * scale
            let dot = CGRect(x: location.x - diameter / 2, y: location.y - diameter / 2, width: diameter, height: diameter)
            context.fill(Path(ellipseIn: dot), with: .color(.white.opacity(opacity * max(0.3, fadeOpacity(t)))))
        }
    }

    private func fadeOpacity(_ t: Double) -> Double {
        smooth(t / 0.28) * smooth((1 - t) / 0.22)
    }
    private func smooth(_ value: Double) -> Double {
        let x = min(max(value, 0), 1); return x * x * (3 - 2 * x)
    }
    private func point(_ angle: Double, _ radius: CGFloat, _ center: CGPoint) -> CGPoint {
        CGPoint(x: center.x + radius * cos(angle), y: center.y + radius * sin(angle))
    }
}
