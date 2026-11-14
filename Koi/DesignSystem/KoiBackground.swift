import SwiftUI
import CoreMotion
import CoreImage
import CoreImage.CIFilterBuiltins
import UIKit
import Observation

struct KoiBackground: View {
    var isDoingScreen = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var motion = KoiMotionOffset()

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color(red: 0x4C / 255, green: 0x66 / 255, blue: 0x88 / 255)
                Image("KoiBackground")
                    .resizable()
                    .scaledToFill()
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .scaleEffect(1.04)
                    .offset(motion.offset)
                    .clipped()
                    .blur(radius: 5.5, opaque: true)
                    .contrast(1.2)
                    .saturation(1.12)
                    .brightness(-0.045)
                TimelineView(.periodic(from: .now, by: 300)) { timeline in
                    daylight(at: timeline.date)
                }
                KoiFilmGrain()
                backgroundDepth
                KoiTheme.deepWater.opacity(0.33)
                if isDoingScreen {
                    LinearGradient(
                        colors: [.clear, KoiTheme.deepWater.opacity(0.3), KoiTheme.deepWater.opacity(0.3), .clear],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .animation(.easeOut(duration: 0.3), value: motion.offset)
        }
        .ignoresSafeArea()
        .overlay(alignment: .bottom) {
            LinearGradient(colors: [.clear, KoiTheme.deepWater.opacity(0.24)], startPoint: .top, endPoint: .bottom)
                .frame(height: KoiTheme.space.s89).allowsHitTesting(false)
        }
        .task { if !reduceMotion { motion.start() } }
        .onDisappear { motion.stop() }
        .accessibilityHidden(true)
    }

    private func daylight(at date: Date) -> some View {
        let hour = Calendar.current.component(.hour, from: date)
        let color: Color
        let opacity: Double
        switch hour {
        case 5..<7: (color, opacity) = (Color(red: 0.56, green: 0.72, blue: 0.94), 0.22)
        case 7..<11: (color, opacity) = (Color(red: 0.72, green: 0.84, blue: 1), 0.18)
        case 11..<17: (color, opacity) = (.white, 0.025)
        case 17..<21: (color, opacity) = (Color(red: 1, green: 0.77, blue: 0.58), 0.19)
        default: (color, opacity) = (Color(red: 0.22, green: 0.24, blue: 0.46), 0.26)
        }
        return color.opacity(opacity).blendMode(.softLight)
    }

    private var backgroundDepth: some View {
        ZStack {
            RadialGradient(
                colors: [.white.opacity(0.12), .white.opacity(0.025), .clear],
                center: UnitPoint(x: 0.22, y: 0.12),
                startRadius: 0,
                endRadius: 520
            )
            LinearGradient(colors: [.clear, .black.opacity(0.04), .black.opacity(0.11)], startPoint: .top, endPoint: .bottom)
            RadialGradient(colors: [.clear, .clear, .black.opacity(0.12)], center: .center, startRadius: 240, endRadius: 680)
        }
        .allowsHitTesting(false)
    }
}

@MainActor
@Observable
private final class KoiMotionOffset {
    private let manager = CMMotionManager()
    private(set) var offset = CGSize.zero

    func start() {
        guard manager.isDeviceMotionAvailable, !manager.isDeviceMotionActive else { return }
        manager.deviceMotionUpdateInterval = 1.0 / 12.0
        manager.startDeviceMotionUpdates(to: .main) { [weak self] sample, _ in
            guard let attitude = sample?.attitude else { return }
            let x = min(max(-sin(attitude.roll) * 8, -8), 8)
            let y = min(max(sin(attitude.pitch) * 8, -8), 8)
            Task { @MainActor [weak self] in self?.offset = CGSize(width: x, height: y) }
        }
    }

    func stop() {
        guard manager.isDeviceMotionActive else { return }
        manager.stopDeviceMotionUpdates()
        offset = .zero
    }
}

private enum KoiGrainTexture {
    static let image: UIImage? = {
        let side = 256
        let context = CIContext(options: [.useSoftwareRenderer: false])
        guard let noise = CIFilter.randomGenerator().outputImage else { return nil }
        let grayscale = noise.applyingFilter("CIColorMatrix", parameters: [
            "inputRVector": CIVector(x: 0.33, y: 0.33, z: 0.33, w: 0),
            "inputGVector": CIVector(x: 0.33, y: 0.33, z: 0.33, w: 0),
            "inputBVector": CIVector(x: 0.33, y: 0.33, z: 0.33, w: 0),
            "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 0),
            "inputBiasVector": CIVector(x: 0, y: 0, z: 0, w: 1)
        ])
        let rect = CGRect(x: 0, y: 0, width: side, height: side)
        guard let bitmap = context.createCGImage(grayscale, from: rect) else { return nil }
        return UIImage(cgImage: bitmap)
    }()
}

private struct KoiFilmGrain: View {
    var body: some View {
        if let image = KoiGrainTexture.image {
            Image(uiImage: image)
                .resizable(resizingMode: .tile)
                .opacity(0.1)
                .blendMode(.softLight)
                .allowsHitTesting(false)
        }
    }
}
