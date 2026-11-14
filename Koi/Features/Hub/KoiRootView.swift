import SwiftUI
import SwiftData
import KoiShared
import OSLog
import UserNotifications

enum KoiTab: Int, CaseIterable, Identifiable {
    case hub
    case toDo
    case movement
    case intake

    var id: Int { rawValue }
    static var launchSelection: KoiTab {
        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        if let marker = arguments.firstIndex(of: "-koiTab"), arguments.indices.contains(marker + 1) {
            switch arguments[marker + 1].lowercased() {
            case "todo": return .toDo
            case "movement": return .movement
            case "intake": return .intake
            default: break
            }
        }
        #endif
        return .hub
    }
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
    @Environment(\.analyticsProvider) private var analyticsProvider
    @Environment(\.notificationProvider) private var notificationProvider
    @Environment(\.healthProvider) private var healthProvider
    @State private var selectedTab: KoiTab = KoiTab.launchSelection
    @State private var isOnboardingPresented = false
    @State private var hasLoadedOnboarding = false
    @State private var isRestoreOfferPresented = false
    @State private var backupError: String?
    @State private var rootRefreshID = UUID()
    @State private var presentsMealComposer = false
    @State private var startsMealCamera = false
    @State private var presentsSmartNote = false
    @State private var opensSmartNoteAfterOnboarding = false
    @State private var launchVisible: Bool = {
        #if DEBUG
        !ProcessInfo.processInfo.arguments.contains("-koiDemo")
        #else
        true
        #endif
    }()

    var body: some View {
        ZStack {
        TabView(selection: $selectedTab) {
            HubView(onSelectTab: { selectedTab = $0 }, onPresentSmartNote: { presentsSmartNote = true })
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
        .compositingGroup()
        .shadow(color: KoiTheme.legibilityShadow, radius: 7)
        .background(KoiBackground().ignoresSafeArea())
        .tint(KoiTheme.onBase)
        .preferredColorScheme(.light)
        .environment(\.koiIntroRevealed, !launchVisible)
        .fullScreenCover(isPresented: $isOnboardingPresented, onDismiss: {
            guard opensSmartNoteAfterOnboarding else { return }
            opensSmartNoteAfterOnboarding = false
            presentsSmartNote = true
        }) {
            OnboardingView(onSelectTab: { selectedTab = $0 }, onTrySmartNote: { opensSmartNoteAfterOnboarding = true })
        }
        .sheet(isPresented: $presentsSmartNote) {
            SmartNoteSheet()
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .task {
            analyticsProvider.signal("Screen.opened", parameters: ["screen": selectedTab.title])
            healthProvider.observeMovementChanges {
                NotificationCenter.default.post(name: .koiHealthMovementDidChange, object: nil)
            }
            await notificationProvider.refreshPlan(using: modelContext)
            if ProcessInfo.processInfo.arguments.contains("-koiDemo") {
                do { try KoiDemoSeeder.seedIfEmpty(modelContext) }
                catch { Logger(subsystem: "com.alexandertarica.koi", category: "Demo").error("Unable to seed demo data.") }
            }
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
            if phase == .active { Task { await notificationProvider.refreshPlan(using: modelContext) } }
            if phase == .background { Task { await createAutomaticBackup() } }
        }
        .onReceive(NotificationCenter.default.publisher(for: .koiHealthMovementDidChange)) { _ in
            Task { await notificationProvider.refreshPlan(using: modelContext) }
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
        .onReceive(NotificationCenter.default.publisher(for: KoiNotificationRouter.didOpen)) { notification in
            let tab = notification.userInfo?["tab"] as? Int ?? 0
            switch tab {
            case 1: selectedTab = .toDo
            case 2: selectedTab = .movement
            case 3: selectedTab = .intake
            default: selectedTab = .hub
            }
        }
        .onChange(of: selectedTab) { _, tab in analyticsProvider.signal("Screen.opened", parameters: ["screen": tab.title]) }
        .alert("A Koi backup is available", isPresented: $isRestoreOfferPresented) {
            Button("Restore backup") { Task { await restoreStartupBackup() } }
            Button("Set up as new", role: .cancel) { isOnboardingPresented = true }
        } message: {
            Text("Restore the latest private iCloud backup to this phone?")
        }
        .alert("iCloud backup", isPresented: Binding(get: { backupError != nil }, set: { if !$0 { backupError = nil } })) {
            Button("Set up as new", role: .cancel) { backupError = nil; isOnboardingPresented = true }
        } message: { Text(backupError ?? "") }
        if launchVisible {
            KoiSplashScreen { withAnimation(.easeOut(duration: 0.25)) { launchVisible = false } }
                .transition(.opacity)
                .zIndex(10)
        }
        }
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
                    KoiHaptics.tap()
                    withAnimation(KoiTheme.morph) {
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
                    .foregroundStyle(KoiTheme.glassInk)
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
        .background {
            if #available(iOS 26.0, *) {
                Capsule().glassEffect(.regular, in: Capsule())
            } else {
                Capsule().fill(.ultraThinMaterial.opacity(0.68))
            }
        }
        .overlay(Capsule().strokeBorder(KoiTheme.onBase.opacity(0.28), lineWidth: 1))
        .shadow(color: KoiTheme.glassInk.opacity(0.32), radius: 14, y: 4)
    }

    private var smartNoteHandle: some View {
        Capsule()
            .fill(KoiTheme.glassInk.opacity(0.52))
            .frame(width: 36, height: 4.5)
            .frame(width: 160, height: 44)
            .contentShape(Rectangle())
            .onTapGesture { KoiHaptics.tap(); onSmartNote() }
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

private struct KoiSplashScreen: View {
    let onFinish: () -> Void
    @State private var wordmarkVisible = false

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .topLeading) {
                KoiBackground()
                Image("KoiWordmark")
                    .resizable()
                    .renderingMode(.template)
                    .scaledToFit()
                    .frame(width: 240, height: 28)
                    .foregroundStyle(KoiTheme.onBase.opacity(0.8))
                    .opacity(wordmarkVisible ? 1 : 0)
                    .blur(radius: wordmarkVisible ? 0 : 10)
                    .padding(.top, geometry.safeAreaInsets.top + 13)
                    .padding(.horizontal, KoiTheme.space.s21)
                    .shadow(color: KoiTheme.legibilityShadow, radius: 7)
            }
            .ignoresSafeArea()
        }
        .task {
            try? await Task.sleep(for: .milliseconds(50))
            withAnimation(.timingCurve(0.22, 1, 0.36, 1, duration: 0.85)) { wordmarkVisible = true }
            try? await Task.sleep(for: .milliseconds(560))
            onFinish()
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Koi")
    }
}

private struct SmartNoteSheet: View {
    @Environment(\.modelContext) private var context
    @Environment(\.foodEstimator) private var estimator
    @Environment(\.analyticsProvider) private var analyticsProvider
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var isSaving = false
    @State private var isSaved = false
    @State private var noteIsPersisted = false
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
                if isSaved {
                    ShareLink(item: appleNotesText, subject: Text("Koi quick note")) {
                        Label("Send to Apple Notes", systemImage: "square.and.arrow.up").font(KoiTheme.caption)
                    }
                    .tint(KoiTheme.onBase)
                }
                Spacer(minLength: 0)
                KoiPrimaryButton(title: isSaved ? "Saved" : (isSaving ? "Saving…" : "Save")) {
                    if isSaved { dismiss() }
                    else { Task { await save() } }
                }
                .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSaving)
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
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        isSaving = true
        defer { isSaving = false }
        do {
            if !noteIsPersisted {
                context.insert(KoiQuickNote(text: text, action: action.map(actionKind) ?? "reflection"))
                try context.save()
                noteIsPersisted = true
            }
            if let action {
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
            }
            try context.save()
            analyticsProvider.signal("Note.saved")
            isSaved = true
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

    private func actionKind(_ action: SmartNoteAction) -> String {
        switch action {
        case .food: "food"
        case .water: "water"
        case .habit: "habit"
        case .task: "task"
        case .workout: "workout"
        case .planLift: "planned_lift"
        }
    }

    private var appleNotesText: String {
        let date = Date.now.formatted(.dateTime.month(.abbreviated).day().hour().minute())
        return "Koi · \(date)\n\n\(text.trimmingCharacters(in: .whitespacesAndNewlines))"
    }
}

@MainActor
enum KoiDemoSeeder {
    static func seedIfEmpty(_ context: ModelContext, calendar: Calendar = .autoupdatingCurrent) throws {
        let isEmpty = try [
            context.fetch(FetchDescriptor<KoiProfile>()).isEmpty,
            context.fetch(FetchDescriptor<KoiOnboardingState>()).isEmpty,
            context.fetch(FetchDescriptor<KoiBodyWeightEntry>()).isEmpty,
            context.fetch(FetchDescriptor<KoiDay>()).isEmpty,
            context.fetch(FetchDescriptor<KoiHabit>()).isEmpty,
            context.fetch(FetchDescriptor<KoiHabitLog>()).isEmpty,
            context.fetch(FetchDescriptor<KoiTask>()).isEmpty,
            context.fetch(FetchDescriptor<KoiFoodEntry>()).isEmpty,
            context.fetch(FetchDescriptor<KoiNutrientGoal>()).isEmpty,
            context.fetch(FetchDescriptor<KoiNutrientEntry>()).isEmpty,
            context.fetch(FetchDescriptor<KoiSupplement>()).isEmpty,
            context.fetch(FetchDescriptor<KoiSupplementLog>()).isEmpty,
            context.fetch(FetchDescriptor<KoiMovementGoal>()).isEmpty,
            context.fetch(FetchDescriptor<KoiMovementDay>()).isEmpty,
            context.fetch(FetchDescriptor<KoiWorkoutRoutine>()).isEmpty,
            context.fetch(FetchDescriptor<KoiRoutineLift>()).isEmpty,
            context.fetch(FetchDescriptor<KoiWorkoutSession>()).isEmpty,
            context.fetch(FetchDescriptor<KoiWorkoutLift>()).isEmpty,
            context.fetch(FetchDescriptor<KoiWorkoutSet>()).isEmpty,
            context.fetch(FetchDescriptor<KoiCardioSession>()).isEmpty
        ].allSatisfy { $0 }
        guard isEmpty else { return }
        let today = calendar.startOfDay(for: .now)
        let created = calendar.date(byAdding: .day, value: -120, to: today) ?? today
        context.insert(KoiProfile(name: "Taylor", joinedAt: calendar.date(byAdding: .day, value: -28, to: today) ?? today))
        context.insert(KoiOnboardingState(isComplete: true, hasSeenTour: true, notificationMode: "none", backupEnabled: false))
        context.insert(KoiMovementGoal(stepGoal: 8_500, weeklyWorkoutGoal: 4))
        for goal in [
            KoiNutrientGoal(key: "calories", name: "Calories", unit: "kcal", goal: 2_200, step: 50, goalType: "around"),
            KoiNutrientGoal(key: "protein", name: "Protein", unit: "g", goal: 140, step: 5),
            KoiNutrientGoal(key: "fiber", name: "Fiber", unit: "g", goal: 30, step: 1),
            KoiNutrientGoal(key: "water", name: "Water", unit: "oz", goal: 100, step: 8),
            KoiNutrientGoal(key: "carbs", name: "Carbs", unit: "g", goal: 250, step: 5, goalType: "track"),
            KoiNutrientGoal(key: "fat", name: "Fat", unit: "g", goal: 70, step: 5, goalType: "track")
        ] { context.insert(goal) }

        let titles = ["Make the bed", "Read a little", "Take a walk"]
        let habits = titles.enumerated().map { index, title in
            KoiHabit(title: title, createdAt: created, schedule: "daily", minimumVersion: ["Straighten the pillow", "One page", "Step outside"][index])
        }
        habits.forEach { context.insert($0) }
        let balanceSamples = [0.78, 0.74, 0.84, 0.72, 0.91, 0.73, 0.86]
        let foods = ["Salmon rice bowl", "Yogurt and fruit", "Chicken wrap", "Eggs and toast", "Tofu noodle bowl", "Turkey sandwich", "Oatmeal and berries"]
        for offset in 0..<7 {
            guard let date = calendar.date(byAdding: .day, value: -offset, to: today) else { continue }
            for (index, habit) in habits.enumerated() {
                let completion = offset == 2 && index == 1 ? 0 : (offset == 4 && index == 2 ? 1 : 2)
                context.insert(KoiHabitLog(habitID: habit.id, date: date, completion: completion))
            }
            context.insert(KoiFoodEntry(name: foods[offset], loggedAt: date.addingTimeInterval(12 * 3_600), calories: [1_950.0, 2_280, 2_060, 2_390, 2_120, 1_880, 2_160][offset], proteinGrams: 120 + Double(offset * 4), carbohydrateGrams: 210, fatGrams: 66, fiberGrams: 24 + Double(offset % 5), confidence: 0.84))
            context.insert(KoiNutrientEntry(date: date, nutrientKey: "water", value: [78.0, 96, 110, 84, 102, 72, 94][offset]))
            let trained = [1, 3, 5].contains(offset)
            context.insert(KoiMovementDay(date: date, healthSteps: 6_400 + offset * 615, healthWorkoutCount: trained ? 1 : 0))
            let demoHabits = completionScore(offset: offset)
            context.insert(KoiDay(date: date, balance: balanceSamples[offset], habitsScore: demoHabits, nutritionScore: 0.72, exerciseScore: trained ? 0.86 : 0.53))
        }

        let tasks = [
            KoiTask(title: "Plan the week", dueAt: today, quadrant: 1),
            KoiTask(title: "Pick up groceries", dueAt: calendar.date(byAdding: .day, value: 1, to: today), quadrant: 0),
            KoiTask(title: "Send the note", dueAt: calendar.date(byAdding: .day, value: -1, to: today), quadrant: 1, isComplete: true)
        ]
        tasks[2].completedAt = calendar.date(byAdding: .hour, value: -4, to: .now)
        tasks.forEach { context.insert($0) }

        for offset in [1, 3, 5] {
            guard let date = calendar.date(byAdding: .day, value: -offset, to: today) else { continue }
            let legDay = offset == 3
            let session = KoiWorkoutSession(name: legDay ? "Lower strength" : "Upper strength", muscleGroup: legDay ? "legs" : "push", startedAt: date.addingTimeInterval(17 * 3_600))
            session.endedAt = session.startedAt.addingTimeInterval(2_700)
            session.isComplete = true
            context.insert(session)
            let lift = KoiWorkoutLift(sessionID: session.id, name: legDay ? "Goblet squat" : "Bench press", muscleGroup: legDay ? "legs" : "push", targetSets: 3, targetReps: 8)
            context.insert(lift)
            for setIndex in 0..<3 {
                context.insert(KoiWorkoutSet(sessionID: session.id, liftID: lift.id, loggedAt: session.startedAt.addingTimeInterval(TimeInterval(setIndex * 180)), weightLB: legDay ? 55 : 95, reps: setIndex == 2 ? 7 : 8))
            }
        }
        let runDate = calendar.date(byAdding: .day, value: -4, to: today) ?? today
        let run = KoiCardioSession(activity: "Run", detail: "Outdoor", startedAt: runDate.addingTimeInterval(7 * 3_600), durationSeconds: 1_920, distanceMeters: 4_800)
        run.endedAt = run.startedAt.addingTimeInterval(1_920)
        run.isComplete = true
        context.insert(run)
        for offset in stride(from: 28, through: 0, by: -7) {
            guard let date = calendar.date(byAdding: .day, value: -offset, to: today) else { continue }
            context.insert(KoiBodyWeightEntry(date: date, weightLB: 158.2 - Double((28 - offset) / 7) * 0.35))
        }
        try context.save()
    }

    private static func completionScore(offset: Int) -> Double {
        if offset == 2 { return 5.0 / 6.0 }
        if offset == 4 { return 5.0 / 6.0 }
        return 1
    }
}
