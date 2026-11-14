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
    @State private var presentsMealComposer = false
    @State private var startsMealCamera = false
    @State private var presentsSmartNote = false

    var body: some View {
        TabView(selection: $selectedTab) {
            HubView(onSelectTab: { selectedTab = $0 })
                .tag(KoiTab.hub)
            TodoView()
                .tag(KoiTab.toDo)
            MovementView()
                .tag(KoiTab.movement)
            IntakeView(presentsMealComposer: $presentsMealComposer, startsCamera: $startsMealCamera)
                .tag(KoiTab.intake)
        }
        .id(rootRefreshID)
        .tabViewStyle(.page(indexDisplayMode: .never))
        .safeAreaInset(edge: .bottom, spacing: 0) {
            KoiTabBar(selection: $selectedTab) { presentsSmartNote = true }
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
        .sheet(isPresented: $presentsSmartNote) {
            SmartNoteSheet()
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
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
        .onOpenURL { url in
            guard url.scheme == "koi" else { return }
            switch url.host {
            case "intake":
                selectedTab = .intake
                if url.path == "/log" || url.path == "/camera" { presentsMealComposer = true }
                if url.path == "/camera" { startsMealCamera = true }
            case "todo": selectedTab = .toDo
            default: selectedTab = .hub
            }
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
    let onSmartNote: () -> Void

    var body: some View {
        VStack(spacing: KoiTheme.space.s5) {
            smartNoteHandle
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
        }
        .padding(6)
        .background(.ultraThinMaterial.opacity(0.68), in: Capsule())
        .overlay(Capsule().strokeBorder(KoiTheme.onBase.opacity(0.28), lineWidth: 1))
        .shadow(color: KoiTheme.glassInk.opacity(0.32), radius: 14, y: 4)
    }

    private var smartNoteHandle: some View {
        Capsule()
            .fill(KoiTheme.onBase.opacity(0.52))
            .frame(width: 38, height: 4)
            .frame(maxWidth: .infinity)
            .frame(height: 12)
            .contentShape(Rectangle())
            .onTapGesture { onSmartNote() }
            .gesture(DragGesture(minimumDistance: 8).onEnded(openWhenSwipedUp))
            .accessibilityElement()
            .accessibilityLabel("Write a smart note")
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { onSmartNote() }
    }

    private func openWhenSwipedUp(_ value: DragGesture.Value) {
        guard value.translation.height < -12 else { return }
        onSmartNote()
    }
}

private struct SmartNoteSheet: View {
    @Environment(\.modelContext) private var context
    @Environment(\.foodEstimator) private var estimator
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var isSaving = false
    @State private var error: String?
    @State private var confirmation: String?
    @State private var aiAction: SmartNoteAction?
    @State private var isClassifying = false

    private var action: SmartNoteAction? { aiAction ?? SmartNoteParser.parse(text) }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: KoiTheme.space.s13) {
                Text("Write it as it happened.").font(KoiTheme.title)
                if SmartNoteClassifier.isAvailable { Text("Koi sorts this note on device.").font(KoiTheme.caption).opacity(0.66) }
                TextEditor(text: $text)
                    .font(KoiTheme.body)
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: 110)
                    .padding(10)
                    .background(.ultraThinMaterial.opacity(0.2), in: RoundedRectangle(cornerRadius: 14))
                    .accessibilityLabel("Smart note")
                if let action { Text(actionTitle(action)).font(KoiTheme.caption).opacity(0.76) }
                if isClassifying { Text("Reading on device…").font(KoiTheme.caption).opacity(0.62) }
                if let confirmation { Text(confirmation).font(KoiTheme.caption).opacity(0.76) }
                if let error { Text(error).font(KoiTheme.caption).foregroundStyle(.orange) }
                Spacer(minLength: 0)
                KoiPrimaryButton(title: isSaving ? "Saving…" : "Save") { Task { await save() } }
                    .disabled(action == nil || isSaving)
            }
            .padding(KoiTheme.space.s21)
            .background(KoiBackground().ignoresSafeArea())
            .foregroundStyle(KoiTheme.onBase)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Close") { dismiss() }.font(KoiTheme.caption) } }
        }
        .preferredColorScheme(.dark)
        .task(id: text) {
            aiAction = nil
            guard SmartNoteClassifier.isAvailable, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
            isClassifying = true
            defer { isClassifying = false }
            do { try await Task.sleep(for: .milliseconds(450)) }
            catch { return }
            aiAction = await SmartNoteClassifier.classify(text)
        }
    }

    @MainActor private func save() async {
        guard let action else { return }
        isSaving = true
        defer { isSaving = false }
        do {
            switch action {
            case .food(let description):
                let estimate = try await estimator.estimate(text: description, jpegData: nil)
                context.insert(KoiFoodEntry(name: estimate.description, calories: estimate.calories, proteinGrams: estimate.proteinGrams, carbohydrateGrams: estimate.carbohydrateGrams, fatGrams: estimate.fatGrams, fiberGrams: estimate.fiberGrams, addedSugarGrams: estimate.addedSugarGrams, sodiumMilligrams: estimate.sodiumMilligrams, confidence: estimate.confidence))
                confirmation = "Meal added."
            case .water(let ounces):
                let date = Date.now
                let entries = try context.fetch(FetchDescriptor<KoiNutrientEntry>())
                if let existing = entries.first(where: { $0.nutrientKey == "water" && $0.dayID == KoiNutrientEntry(date: date, nutrientKey: "water").dayID }) {
                    existing.value += ounces
                } else { context.insert(KoiNutrientEntry(date: date, nutrientKey: "water", value: ounces)) }
                confirmation = "Water added."
            case .habit(let phrase):
                let habits = try context.fetch(FetchDescriptor<KoiHabit>()).filter { $0.isActive && $0.pausedAt == nil }
                guard let habit = habits.first(where: { phrase.localizedCaseInsensitiveContains($0.title) }) else {
                    error = "Name the habit you finished."; return
                }
                let day = Calendar.current.startOfDay(for: .now)
                let logs = try context.fetch(FetchDescriptor<KoiHabitLog>())
                if let log = logs.first(where: { $0.habitID == habit.id && Calendar.current.isDate($0.date, inSameDayAs: day) }) { log.completion = 2 }
                else { context.insert(KoiHabitLog(habitID: habit.id, date: day, completion: 2)) }
                confirmation = "\(habit.title) checked off."
            case .task(let title, let dueAt):
                context.insert(KoiTask(title: title, dueAt: dueAt, quadrant: 1))
                confirmation = "To-do added."
            case .workout(let name, let weight, let reps, let sets):
                let session = KoiWorkoutSession(name: "Smart note", muscleGroup: WorkoutNameRules.guessGroup(name), startedAt: .now)
                session.endedAt = .now; session.isComplete = true
                context.insert(session)
                let lift = KoiWorkoutLift(sessionID: session.id, name: name, muscleGroup: WorkoutNameRules.guessGroup(name), targetSets: min(max(sets, 1), 12), targetReps: min(max(reps, 1), 100))
                context.insert(lift)
                for _ in 0..<min(max(sets, 1), 12) { context.insert(KoiWorkoutSet(sessionID: session.id, liftID: lift.id, weightLB: weight, reps: reps)) }
                let day = try context.fetch(FetchDescriptor<KoiMovementDay>()).first(where: { Calendar.current.isDate($0.date, inSameDayAs: .now) })
                if let day { day.didManuallyTrain = true } else { context.insert(KoiMovementDay(date: .now, didManuallyTrain: true)) }
                confirmation = "Workout added."
            case .planLift(let name):
                let routine = KoiWorkoutRoutine(name: "Today", muscleGroup: WorkoutNameRules.guessGroup(name), plannedAt: Calendar.current.startOfDay(for: .now))
                context.insert(routine)
                context.insert(KoiRoutineLift(routineID: routine.id, name: name, muscleGroup: WorkoutNameRules.guessGroup(name)))
                confirmation = "Added to today’s plan."
            }
            try context.save()
            dismiss()
        } catch let error as LocalizedError {
            self.error = error.errorDescription ?? "Couldn't save that note. Try again."
        } catch { self.error = "Couldn't save that note. Try again." }
    }

    private func actionTitle(_ action: SmartNoteAction) -> String {
        switch action {
        case .food(let value): "Estimate meal · \(value)"
        case .water(let value): "Add \(value.formatted()) oz water"
        case .habit(let value): "Check off a matching habit · \(value)"
        case .task(let value, _): "Add a to-do · \(value)"
        case .workout(let name, let weight, let reps, let sets): "Log \(name) · \(weight.formatted()) × \(reps) × \(sets)"
        case .planLift(let value): "Plan \(value) for today"
        }
    }
}
