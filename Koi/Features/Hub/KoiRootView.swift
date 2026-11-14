import SwiftUI

struct KoiRootView: View {
    var body: some View {
        TabView {
            KoiHomePlaceholder(title: "Hub", symbol: "hexagon")
                .tabItem { Label("Hub", systemImage: "hexagon") }
            KoiHomePlaceholder(title: "To-Do", symbol: "checklist")
                .tabItem { Label("To-Do", systemImage: "checklist") }
            KoiHomePlaceholder(title: "Movement", symbol: "figure.walk")
                .tabItem { Label("Movement", systemImage: "figure.walk") }
            KoiHomePlaceholder(title: "Intake", symbol: "leaf")
                .tabItem { Label("Intake", systemImage: "leaf") }
        }
        .tint(KoiTheme.onBase)
        .background(KoiBackground())
        .preferredColorScheme(.dark)
    }
}

private struct KoiHomePlaceholder: View {
    let title: String
    let symbol: String

    var body: some View {
        ZStack {
            KoiBackground()
            VStack(spacing: KoiTheme.space.s34) {
                HStack {
                    Image(systemName: symbol)
                        .font(.system(size: 20, weight: .light))
                    Text(title.uppercased())
                        .font(KoiTheme.section)
                        .tracking(2.4)
                    Spacer()
                    Text(Date.now.formatted(date: .abbreviated, time: .omitted))
                        .font(KoiTheme.caption)
                }
                .foregroundStyle(KoiTheme.onBase)
                Spacer()
                Text("Still water")
                    .font(KoiTheme.title)
                    .foregroundStyle(KoiTheme.onBase)
                Spacer()
            }
            .padding(.horizontal, KoiTheme.space.s21)
            .padding(.top, KoiTheme.space.s21)
        }
    }
}
