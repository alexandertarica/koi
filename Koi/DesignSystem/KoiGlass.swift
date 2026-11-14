import SwiftUI

enum KoiGlassStrength {
    case quiet, base, strong
}

struct KoiGlass<Content: View>: View {
    let strength: KoiGlassStrength
    @ViewBuilder let content: Content

    var body: some View {
        content
            .padding(.horizontal, 13)
            .padding(.vertical, 8)
            .background {
                switch strength {
                case .quiet:
                    Capsule().fill(.clear)
                case .base:
                    Capsule().fill(.ultraThinMaterial.opacity(0.5))
                case .strong:
                    Capsule().fill(.regularMaterial.opacity(0.9))
                        .overlay(Capsule().fill(.white.opacity(0.26)))
                        .shadow(color: .white.opacity(0.3), radius: 14)
                }
            }
            .overlay {
                if strength == .strong {
                    Capsule().strokeBorder(
                        LinearGradient(colors: [.white.opacity(0.9), .white.opacity(0.35)], startPoint: .top, endPoint: .bottom),
                        lineWidth: 1.2
                    )
                } else {
                    Capsule().strokeBorder(strength == .quiet ? .white.opacity(0.3) : .white.opacity(0.35), lineWidth: 1)
                }
            }
            .foregroundStyle(strength == .strong ? KoiTheme.glassInk : KoiTheme.onBase)
    }
}

extension KoiGlassStrength: Equatable {}

struct GlassChip: View {
    let title: String
    var symbol: String? = nil
    var isOn = false

    var body: some View {
        KoiGlass(strength: isOn ? .base : .quiet) {
            HStack(spacing: 5) {
                if let symbol {
                    Image(systemName: symbol).font(.system(size: 11, weight: .light))
                }
                Text(title).font(KoiTheme.caption)
            }
            .frame(minHeight: 16)
        }
    }
}

struct KoiPrimaryButton: View {
    let title: String
    var uppercase = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            KoiGlass(strength: .strong) {
                Text(uppercase ? title.uppercased() : title)
                    .font(KoiTheme.caption)
                    .tracking(3)
                    .frame(maxWidth: .infinity, minHeight: 40)
            }
        }
        .buttonStyle(.plain)
    }
}
