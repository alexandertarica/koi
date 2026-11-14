import SwiftUI

struct KoiDial: View {
    let score: Double
    let habits: Double
    let nutrition: Double
    let exercise: Double
    var weights = BalanceFocus.allRounder.weights
    @State private var revealProgress = 0.0

    private let ivory = KoiTheme.onBase

    var body: some View {
        GeometryReader { proxy in
            let safeScore = min(max(score.isFinite ? score : 0, 0), 1)
            ZStack(alignment: .topTrailing) {
                Canvas { context, size in
                    drawArc(in: &context, size: size, score: safeScore * revealProgress)
                }

                VStack(alignment: .trailing, spacing: 0) {
                    Text("\(Int((safeScore * 100).rounded()))%")
                        .font(KoiTheme.hero)
                        .foregroundStyle(ivory)
                        .contentTransition(.numericText())
                    Text("BALANCE")
                        .font(KoiTheme.section)
                        .tracking(2.4)
                        .foregroundStyle(ivory.opacity(0.82))
                }
                .padding(.top, 4)
                .padding(.trailing, KoiTheme.space.s21)

                VStack(spacing: 7) {
                    pillarRow("Habits", value: habits, weight: weights.habits)
                    pillarRow("Nutrition", value: nutrition, weight: weights.nutrition)
                    pillarRow("Exercise", value: exercise, weight: weights.exercise)
                }
                .frame(width: proxy.size.width * 0.68)
                .position(x: proxy.size.width * 0.40, y: proxy.size.height * 0.74)
            }
        }
        .onAppear {
            withAnimation(.easeOut(duration: 1.65)) {
                revealProgress = 1
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Balance \(Int((min(max(score, 0), 1) * 100).rounded())) percent. Habits \(Int(habits * 100)) percent, Nutrition \(Int(nutrition * 100)) percent, Exercise \(Int(exercise * 100)) percent.")
    }

    private func pillarRow(_ title: String, value: Double, weight: Double) -> some View {
        let safeValue = min(max(value.isFinite ? value : 0, 0), 1)
        return HStack(spacing: 7) {
            Text(title.uppercased())
                .font(KoiTheme.caption)
                .tracking(0.8)
                .frame(width: 82, alignment: .leading)
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(ivory.opacity(0.16))
                    Capsule().fill(ivory.opacity(0.88)).frame(width: proxy.size.width * safeValue)
                }
            }
            .frame(height: 2)
            Text("\(Int((safeValue * 100).rounded()))")
                .font(KoiTheme.caption)
                .monospacedDigit()
                .frame(width: 26, alignment: .trailing)
        }
        .foregroundStyle(ivory.opacity(0.92))
        .scaleEffect(x: 0.82 + min(max(weight, 0), 0.5) * 0.36, y: 1, anchor: .leading)
    }

    private func drawArc(in context: inout GraphicsContext, size: CGSize, score: Double) {
        let radius = min(size.width * 0.52, size.height + 2)
        let center = CGPoint(x: size.width * 0.48, y: size.height + 2)
        let tickCount = 72
        let activeIndex = Int((score * Double(tickCount - 1)).rounded())

        var fullArc = Path()
        for index in 0...160 {
            let angle = Double.pi + Double.pi * Double(index) / 160
            let point = point(at: angle, radius: radius - 9, center: center)
            if index == 0 { fullArc.move(to: point) } else { fullArc.addLine(to: point) }
        }
        context.stroke(fullArc, with: .color(ivory.opacity(0.27)), lineWidth: 1)

        var activeArc = Path()
        for index in 0...max(activeIndex, 0) {
            let angle = Double.pi + Double.pi * Double(index) / Double(tickCount - 1)
            let point = point(at: angle, radius: radius - 9, center: center)
            if index == 0 { activeArc.move(to: point) } else { activeArc.addLine(to: point) }
        }
        context.stroke(activeArc, with: .color(ivory.opacity(0.88)), lineWidth: 1.6)

        for index in 0..<tickCount {
            let fraction = Double(index) / Double(tickCount - 1)
            let angle = Double.pi + Double.pi * fraction
            let isMajor = index.isMultiple(of: 5)
            let isValue = index == activeIndex
            let length = isValue ? 19.0 : (isMajor ? 12.0 : 6.0)
            let outer = point(at: angle, radius: radius, center: center)
            let inner = point(at: angle, radius: radius - length, center: center)
            var tick = Path()
            tick.move(to: inner)
            tick.addLine(to: outer)
            let color = index <= activeIndex ? ivory.opacity(0.92) : ivory.opacity(0.32)
            context.stroke(tick, with: .color(color), lineWidth: isValue ? 1.8 : (isMajor ? 1.3 : 0.8))
        }

        let beadAngle = Double.pi + Double.pi * score
        let bead = point(at: beadAngle, radius: radius - 9, center: center)
        let beadRect = CGRect(x: bead.x - 5.5, y: bead.y - 5.5, width: 11, height: 11)
        context.fill(Path(ellipseIn: beadRect.insetBy(dx: -4, dy: -4)), with: .color(.white.opacity(0.16)))
        context.fill(Path(ellipseIn: beadRect), with: .color(ivory))
        context.stroke(Path(ellipseIn: beadRect.insetBy(dx: -2, dy: -2)), with: .color(.white.opacity(0.65)), lineWidth: 1)
    }

    private func point(at angle: Double, radius: Double, center: CGPoint) -> CGPoint {
        CGPoint(x: center.x + radius * cos(angle), y: center.y + radius * sin(angle))
    }
}
