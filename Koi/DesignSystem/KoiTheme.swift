import SwiftUI
import UIKit

enum KoiTheme {
    static let morph = Animation.timingCurve(0.22, 1, 0.36, 1, duration: 0.8)
    static let onBase = Color(red: 0xF0 / 255, green: 0xE8 / 255, blue: 0xDB / 255)
    static let onBaseMuted = onBase.opacity(0.92)
    static let deepWater = Color(red: 0x2B / 255, green: 0x40 / 255, blue: 0x67 / 255)
    static let glassInk = Color(red: 0x21 / 255, green: 0x33 / 255, blue: 0x52 / 255)
    static let caution = Color(red: 0x99 / 255, green: 0x4D / 255, blue: 0x33 / 255)
    static let divider = onBase.opacity(0.3)
    static let legibilityShadow = Color(red: 0.06, green: 0.12, blue: 0.24).opacity(0.46)

    static let title = Font.custom("RobotoMono-Light", size: 24, relativeTo: .title)
    static let body = Font.custom("RobotoMono-Regular", size: 15, relativeTo: .body)
    static let caption = Font.custom("RobotoMono-Regular", size: 12, relativeTo: .caption)
    static let section = Font.custom("RobotoMono-Regular", size: 12, relativeTo: .caption)
    static let hero = Font.custom("KOINumerals", size: 48, relativeTo: .largeTitle)

    struct Space {
        let s3: CGFloat = 3
        let s5: CGFloat = 5
        let s8: CGFloat = 8
        let s13: CGFloat = 13
        let s21: CGFloat = 21
        let s34: CGFloat = 34
        let s55: CGFloat = 55
        let s89: CGFloat = 89
    }
    static let space = Space()
}

private struct KoiIntroRevealedKey: EnvironmentKey {
    static let defaultValue = true
}

extension EnvironmentValues {
    var koiIntroRevealed: Bool {
        get { self[KoiIntroRevealedKey.self] }
        set { self[KoiIntroRevealedKey.self] = newValue }
    }
}

struct KoiIntroReveal: ViewModifier {
    @Environment(\.koiIntroRevealed) private var introRevealed
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let order: Int
    @State private var visible = false

    func body(content: Content) -> some View {
        content
            .opacity(visible || reduceMotion ? 1 : 0)
            .blur(radius: visible || reduceMotion ? 0 : 8)
            .offset(y: visible || reduceMotion ? 0 : 10)
            .onChange(of: introRevealed, initial: true) { _, active in
                guard active else { visible = false; return }
                guard !reduceMotion else { visible = true; return }
                let delay = 50 + max(order, 0) * 120
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(delay))
                    withAnimation(.timingCurve(0.22, 1, 0.36, 1, duration: 0.7)) { visible = true }
                }
            }
    }
}

@MainActor
enum KoiHaptics {
    static func tap() { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
    static func change() { UISelectionFeedbackGenerator().selectionChanged() }
    static func tick() { UIImpactFeedbackGenerator(style: .soft).impactOccurred(intensity: 0.45) }
    static func check() { UIImpactFeedbackGenerator(style: .soft).impactOccurred(intensity: 0.7) }
    static func land() { UIImpactFeedbackGenerator(style: .rigid).impactOccurred(intensity: 0.8) }
    static func success() { UINotificationFeedbackGenerator().notificationOccurred(.success) }

    static func ringFill(duration: Double, beats: Int = 12) {
        guard duration > 0, beats > 0 else { return }
        let light = UIImpactFeedbackGenerator(style: .light)
        let finish = UIImpactFeedbackGenerator(style: .rigid)
        light.prepare()
        finish.prepare()
        Task { @MainActor in
            for beat in 0..<beats {
                light.impactOccurred(intensity: 0.25 + 0.55 * Double(beat) / Double(max(beats - 1, 1)))
                try? await Task.sleep(for: .seconds(duration / Double(beats)))
            }
            finish.impactOccurred(intensity: 0.9)
        }
    }

    static func dialSweep(score: Double, duration: Double) {
        guard duration > 0 else { return }
        let tickGenerator = UIImpactFeedbackGenerator(style: .soft)
        let endGenerator = UIImpactFeedbackGenerator(style: .rigid)
        tickGenerator.prepare()
        endGenerator.prepare()
        let count = 20
        let travel = duration * 0.8
        let marks = (1...count).map { mark in
            let fraction = Double(mark) / Double(count)
            return travel * (1 - pow(1 - fraction, 1 / 3))
        }
        Task { @MainActor in
            var elapsed = 0.0
            for (index, mark) in marks.enumerated() {
                try? await Task.sleep(for: .seconds(max(mark - elapsed, 0)))
                elapsed = mark
                if index == marks.count - 1 {
                    endGenerator.impactOccurred(intensity: 0.45 + 0.4 * min(max(score, 0), 1))
                } else {
                    tickGenerator.impactOccurred(intensity: 0.2 + 0.3 * Double(index) / Double(marks.count))
                }
            }
        }
    }
}
