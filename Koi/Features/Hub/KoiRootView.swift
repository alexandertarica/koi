import SwiftUI
import SwiftData
import KoiShared
import OSLog

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
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.backupProvider) private var backupProvider
    @State private var selectedTab: KoiTab = .hub
    @State private var isOnboardingPresented = false
    @State private var hasLoadedOnboarding = false
    @State private var isRestoreOfferPresented = false
    @State private var backupError: String?
    @State private var rootRefreshID = UUID()

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
        .id(rootRefreshID)
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
        .fullScreenCover(isPresented: $isOnboardingPresented) {
            OnboardingView()
        }
        .task {
            guard !hasLoadedOnboarding else { return }
            hasLoadedOnboarding = true
            do {
                let state = try modelContext.fetch(FetchDescriptor<KoiOnboardingState>()).first
                if state?.isComplete != true {
                    if try await backupProvider.hasBackup() { isRestoreOfferPresented = true }
                    else { isOnboardingPresented = true }
                }
            } catch {
                isOnboardingPresented = true
            }
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .background else { return }
            Task { await createAutomaticBackup() }
        }
        .alert("A Koi backup is available", isPresented: $isRestoreOfferPresented) {
            Button("Restore backup") { Task { await restoreStartupBackup() } }
            Button("Set up as new", role: .cancel) { isOnboardingPresented = true }
        } message: {
            Text("Restore the latest private iCloud backup to this phone?")
        }
        .alert("iCloud backup", isPresented: Binding(get: { backupError != nil }, set: { if !$0 { backupError = nil } })) {
            Button("Set up as new", role: .cancel) { backupError = nil; isOnboardingPresented = true }
        } message: { Text(backupError ?? "") }
    }

    @MainActor
    private func createAutomaticBackup() async {
        do {
            guard let state = try modelContext.fetch(FetchDescriptor<KoiOnboardingState>()).first,
                  state.isComplete, state.backupEnabled else { return }
            state.lastBackupAt = try await backupProvider.backup(using: modelContext)
            try modelContext.save()
        } catch {
            Logger(subsystem: "com.alexandertarica.koi", category: "Backup").error("Automatic backup didn't finish.")
        }
    }

    @MainActor
    private func restoreStartupBackup() async {
        do {
            _ = try await backupProvider.restore(using: modelContext)
            guard try modelContext.fetch(FetchDescriptor<KoiOnboardingState>()).first?.isComplete == true else {
                isOnboardingPresented = true
                return
            }
            rootRefreshID = UUID()
        } catch let error as LocalizedError {
            backupError = error.errorDescription ?? "Couldn't restore Koi. Try again."
        } catch {
            backupError = "Couldn't restore Koi. Try again."
        }
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
