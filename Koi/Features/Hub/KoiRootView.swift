import SwiftUI

enum KoiTab: Int, CaseIterable, Identifiable {
    case hub
    case toDo
    case movement
    case intake

    var id: Int { rawValue }
    var title: String {
        switch self {
        case .hub: "Hub"
        case .toDo: "To-Do"
        case .movement: "Movement"
        case .intake: "Intake"
        }
    }
    var symbol: String {
        switch self {
        case .hub: "hexagon.fill"
        case .toDo: "checklist"
        case .movement: "figure.walk"
        case .intake: "leaf"
        }
    }
}

struct KoiRootView: View {
    @State private var selectedTab: KoiTab = .hub

    var body: some View {
        TabView(selection: $selectedTab) {
            HubView(onSelectTab: { selectedTab = $0 })
                .tag(KoiTab.hub)
            TodoView()
                .tag(KoiTab.toDo)
            MovementView()
                .tag(KoiTab.movement)
            IntakeView()
                .tag(KoiTab.intake)
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .safeAreaInset(edge: .bottom, spacing: 0) {
            KoiTabBar(selection: $selectedTab)
                .padding(.horizontal, KoiTheme.space.s21)
                .padding(.top, KoiTheme.space.s8)
                .padding(.bottom, KoiTheme.space.s8)
        }
        .background(KoiBackground().ignoresSafeArea())
        .tint(KoiTheme.onBase)
        .preferredColorScheme(.dark)
    }
}

private struct KoiTabBar: View {
    @Binding var selection: KoiTab

    var body: some View {
        HStack(spacing: 3) {
            ForEach(KoiTab.allCases) { tab in
                Button {
                    withAnimation(.spring(response: 0.38, dampingFraction: 0.84)) {
                        selection = tab
                    }
                } label: {
                    VStack(spacing: 5) {
                        Image(systemName: tab.symbol)
                            .font(.system(size: 20, weight: .light))
                            .frame(height: 23)
                        Text(tab.title)
                            .font(KoiTheme.caption)
                    }
                    .foregroundStyle(KoiTheme.onBase)
                    .frame(maxWidth: .infinity, minHeight: 58)
                    .background {
                        if selection == tab {
                            Capsule().fill(KoiTheme.onBase.opacity(0.18))
                        }
                    }
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(tab.title)
                .accessibilityAddTraits(selection == tab ? .isSelected : [])
            }
        }
        .padding(6)
        .background(.ultraThinMaterial.opacity(0.68), in: Capsule())
        .overlay(Capsule().strokeBorder(KoiTheme.onBase.opacity(0.28), lineWidth: 1))
        .shadow(color: KoiTheme.glassInk.opacity(0.32), radius: 14, y: 4)
    }
}
