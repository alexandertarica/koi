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
        let screen = KoiLaunch.screen
        if let marker = arguments.firstIndex(of: "-koiTab"), arguments.indices.contains(marker + 1) {
            switch arguments[marker + 1].lowercased() {
            case "hub": return .hub
            case "todo": return .toDo
            case "movement": return .movement
            case "intake": return .intake
            default: break
            }
        }
        switch screen {
        case "todoNew", "newTodo", "newHabit": return .toDo
        case "workoutJournal", "workout", "workoutMode", "routineBuilder", "run": return .movement
        case "mealLog": return .intake
        case "profile", "progress": return .hub
        default: break
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
        case .hub: "circle.hexagongrid.fill"
        case .toDo: "checklist"
        case .movement: "figure.walk"
        case .intake: "leaf"
        }
    }
}

enum KoiLaunch {
    static var screen: String? {
        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: "-koiScreen"), arguments.indices.contains(index + 1) else { return nil }
        return arguments[index + 1]
        #else
        return nil
        #endif
    }
    static var directScreen: String? { screen }
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
    @State private var presentsTour = false
    @State private var showTourOffer = false
    @State private var didRouteDebugScreen = false
    @State private var launchVisible: Bool = {
        #if DEBUG
        !ProcessInfo.processInfo.arguments.contains("-koiDemo")
        #else
        true
        #endif
    }()

    var body: some View {
        ZStack {
        styledTabs
        .fullScreenCover(isPresented: $isOnboardingPresented, onDismiss: {
            refreshTourOffer()
        }) {
            OnboardingView()
        }
        .sheet(isPresented: $presentsTour, onDismiss: { markTourSeen() }) {
            AnyView(KoiTourView(onSelectTab: selectTab, onTrySmartNote: showSmartNote, onFinish: closeTour)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible))
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
            if !didRouteDebugScreen {
                didRouteDebugScreen = true
                switch KoiLaunch.screen {
                case "onboarding": isOnboardingPresented = true
                case "smartNote": presentsSmartNote = true
                case "mealLog": selectedTab = .intake; presentsMealComposer = true
                case "profile", "progress": selectedTab = .hub
                case "workoutJournal", "workout", "workoutMode", "routineBuilder", "run": selectedTab = .movement
                case "todoNew", "newTodo", "newHabit": selectedTab = .toDo
                default: break
                }
            }
            guard !hasLoadedOnboarding else { return }
            hasLoadedOnboarding = true
            do {
                let state = try modelContext.fetch(FetchDescriptor<KoiOnboardingState>()).first
                if state?.isComplete != true {
                    if try await backupProvider.hasBackup() { isRestoreOfferPresented = true }
                    else { isOnboardingPresented = true }
                } else { showTourOffer = !(state?.hasSeenTour ?? true) }
            } catch {
                isOnboardingPresented = true
            }
        }
        .onChange(of: scenePhase) { _, phase in handleScenePhase(phase) }
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
        .onReceive(NotificationCenter.default.publisher(for: KoiNotificationRouter.didOpen), perform: handleNotificationRoute)
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

    private var styledTabs: some View {
        AnyView(tabContent)
            .safeAreaInset(edge: .bottom, spacing: 0) { bottomControls }
            .compositingGroup()
            .shadow(color: KoiTheme.legibilityShadow, radius: 7)
            .background(KoiBackground().ignoresSafeArea())
            .tint(KoiTheme.onBase)
            .preferredColorScheme(.light)
            .environment(\.koiIntroRevealed, !launchVisible)
    }

    private var tabContent: some View {
        TabView(selection: $selectedTab) {
            HubView(onSelectTab: { selectedTab = $0 }, onPresentSmartNote: { presentsSmartNote = true }).tag(KoiTab.hub)
            TodoView().tag(KoiTab.toDo)
            MovementView().tag(KoiTab.movement)
            IntakeView(presentsMealComposer: $presentsMealComposer, startsCamera: $startsMealCamera).tag(KoiTab.intake)
        }
        .id(rootRefreshID)
        .tabViewStyle(.page(indexDisplayMode: .never))
    }

    private var bottomControls: some View {
            VStack(spacing: 0) {
                if showTourOffer {
                    Button {
                        presentsTour = true
                    } label: {
                        Text("Show me around").font(KoiTheme.caption)
                            .padding(.horizontal, KoiTheme.space.s13)
                            .padding(.vertical, KoiTheme.space.s5)
                            .background(.ultraThinMaterial.opacity(0.7), in: Capsule())
                            .overlay(Capsule().stroke(KoiTheme.onBase.opacity(0.3), lineWidth: 1))
                    }.buttonStyle(.plain).padding(.bottom, 5)
                }
                KoiSmartNoteHandle { presentsSmartNote = true }.padding(.bottom, 6)
                KoiTabBar(selection: $selectedTab) { presentsSmartNote = true }
            }
            .padding(.horizontal, KoiTheme.space.s21)
            .padding(.top, 4)
            .padding(.bottom, 3)
    }

    @MainActor
    private func selectTab(_ tab: KoiTab) { selectedTab = tab }

    private func showSmartNote() { presentsSmartNote = true }

    private func closeTour() { presentsTour = false }

    @MainActor
    private func handleNotificationRoute(_ notification: Notification) {
        let route = notification.userInfo?["tab"] as? Int ?? 0
        switch route {
        case 1: selectedTab = .toDo
        case 2: selectedTab = .movement
        case 3: selectedTab = .intake
        default: selectedTab = .hub
        }
    }

    @MainActor
    private func handleScenePhase(_ phase: ScenePhase) {
        if phase == .active { Task { await notificationProvider.refreshPlan(using: modelContext) } }
        if phase == .background { Task { await createAutomaticBackup() } }
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
    private func refreshTourOffer() {
        showTourOffer = (try? modelContext.fetch(FetchDescriptor<KoiOnboardingState>()).first)
            .map { $0.isComplete && !$0.hasSeenTour } ?? false
    }

    @MainActor
    private func markTourSeen() {
        guard let state = try? modelContext.fetch(FetchDescriptor<KoiOnboardingState>()).first,
              state.isComplete else { return }
        state.hasSeenTour = true
        do { try modelContext.save(); showTourOffer = false }
        catch { Logger(subsystem: "com.alexandertarica.koi", category: "Onboarding").error("Unable to save tour preference.") }
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
        VStack(spacing: 0) {
            HStack(spacing: 3) {
            ForEach(KoiTab.allCases) { tab in
                Button {
                    KoiHaptics.tap()
                    withAnimation(KoiTheme.morph) {
                        selection = tab
                    }
                } label: {
                    VStack(spacing: 5) {
                        Group {
                            if tab == .hub { KoiHoneycombMark().frame(width: 22, height: 22) }
                            else { Image(systemName: tab.symbol).font(.system(size: 20, weight: .light)).frame(height: 20) }
                        }
                        Text(tab.title)
                            .font(.system(size: 12, weight: .regular))
                    }
                    .foregroundStyle(KoiTheme.glassInk)
                            .frame(maxWidth: .infinity, minHeight: 56)
                    .background {
                        if selection == tab {
                            Capsule().fill(Color(red: 0.35, green: 0.52, blue: 0.76).opacity(0.55))
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
        .padding(4)
        .background {
            if #available(iOS 26.0, *) {
                Capsule().glassEffect(.regular, in: Capsule())
            } else {
                Capsule().fill(.ultraThinMaterial.opacity(0.68))
            }
        }
        .overlay(Capsule().strokeBorder(.white.opacity(0.42), lineWidth: 1))
        .shadow(color: KoiTheme.glassInk.opacity(0.32), radius: 14, y: 4)
    }
}

private struct KoiHoneycombMark: View {
    private let centers: [CGPoint] = [
        CGPoint(x: 11, y: 11), CGPoint(x: 11, y: 2), CGPoint(x: 18, y: 6.5),
        CGPoint(x: 18, y: 15.5), CGPoint(x: 11, y: 20), CGPoint(x: 4, y: 15.5),
        CGPoint(x: 4, y: 6.5)
    ]

    var body: some View {
        Canvas { context, _ in
            for center in centers {
                var path = Path()
                for corner in 0..<6 {
                    let angle = Double(corner) * .pi / 3
                    let point = CGPoint(x: center.x + 4.4 * cos(angle), y: center.y + 4.4 * sin(angle))
                    if corner == 0 { path.move(to: point) } else { path.addLine(to: point) }
                }
                path.closeSubpath()
                context.fill(path, with: .foreground)
            }
        }
        .accessibilityHidden(true)
    }
}

private struct KoiSmartNoteHandle: View {
    let onOpen: () -> Void
    var body: some View {
        Capsule()
            .fill(KoiTheme.onBase.opacity(0.62))
            .frame(width: 36, height: 4.5)
            .frame(width: 160, height: 13)
            .contentShape(Rectangle())
            .onTapGesture { KoiHaptics.tap(); onOpen() }
            .gesture(DragGesture(minimumDistance: 8).onEnded { value in if value.translation.height < -12 { onOpen() } })
            .accessibilityElement()
            .accessibilityLabel("Write a smart note")
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { onOpen() }
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

    private var action: SmartNoteAction? {
        guard !SmartNoteParser.isActivityWithoutFood(text) else { return nil }
        return aiAction ?? SmartNoteParser.parse(text)
    }

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
    static func seedForDemoLaunch(_ context: ModelContext, calendar: Calendar = .autoupdatingCurrent) throws {
        for item in try context.fetch(FetchDescriptor<KoiWorkoutSet>()) { context.delete(item) }
        for item in try context.fetch(FetchDescriptor<KoiWorkoutLift>()) { context.delete(item) }
        for item in try context.fetch(FetchDescriptor<KoiRoutineLift>()) { context.delete(item) }
        for item in try context.fetch(FetchDescriptor<KoiWorkoutSession>()) { context.delete(item) }
        for item in try context.fetch(FetchDescriptor<KoiWorkoutRoutine>()) { context.delete(item) }
        for item in try context.fetch(FetchDescriptor<KoiCardioSession>()) { context.delete(item) }
        for item in try context.fetch(FetchDescriptor<KoiSupplementLog>()) { context.delete(item) }
        for item in try context.fetch(FetchDescriptor<KoiSupplement>()) { context.delete(item) }
        for item in try context.fetch(FetchDescriptor<KoiNutrientEntry>()) { context.delete(item) }
        for item in try context.fetch(FetchDescriptor<KoiNutrientGoal>()) { context.delete(item) }
        for item in try context.fetch(FetchDescriptor<KoiFoodEntry>()) { context.delete(item) }
        for item in try context.fetch(FetchDescriptor<KoiHabitLog>()) { context.delete(item) }
        for item in try context.fetch(FetchDescriptor<KoiHabit>()) { context.delete(item) }
        for item in try context.fetch(FetchDescriptor<KoiTask>()) { context.delete(item) }
        for item in try context.fetch(FetchDescriptor<KoiMovementDay>()) { context.delete(item) }
        for item in try context.fetch(FetchDescriptor<KoiMovementGoal>()) { context.delete(item) }
        for item in try context.fetch(FetchDescriptor<KoiDay>()) { context.delete(item) }
        for item in try context.fetch(FetchDescriptor<KoiBodyWeightEntry>()) { context.delete(item) }
        for item in try context.fetch(FetchDescriptor<KoiQuickNote>()) { context.delete(item) }
        for item in try context.fetch(FetchDescriptor<KoiProfile>()) { context.delete(item) }
        for item in try context.fetch(FetchDescriptor<KoiOnboardingState>()) { context.delete(item) }
        try context.save()
        try seedIfEmpty(context, calendar: calendar)
        let today = calendar.startOfDay(for: .now)
        if let profile = try context.fetch(FetchDescriptor<KoiProfile>()).first, profile.name == "Maya",
           let todayRecord = try context.fetch(FetchDescriptor<KoiDay>()).first(where: { calendar.isDate($0.date, inSameDayAs: today) }) {
            todayRecord.habitsScore = 0.75
            todayRecord.nutritionScore = 0.64
            todayRecord.exerciseScore = 0.93
            todayRecord.balance = 0.77
        }
        try context.save()
    }

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
            context.fetch(FetchDescriptor<KoiCardioSession>()).isEmpty,
            context.fetch(FetchDescriptor<KoiQuickNote>()).isEmpty
        ].allSatisfy { $0 }
        guard isEmpty else { return }
        let today = calendar.startOfDay(for: .now)
        let created = calendar.date(byAdding: .day, value: -28, to: today) ?? today
        context.insert(KoiProfile(name: "Maya", joinedAt: created))
        context.insert(KoiOnboardingState(isComplete: true, hasSeenTour: true, notificationMode: "none", backupEnabled: false))
        context.insert(KoiMovementGoal(stepGoal: 8_000, weeklyWorkoutGoal: 4))
        for goal in [
            KoiNutrientGoal(key: "calories", name: "Calories", unit: "kcal", goal: 2_200, step: 50, goalType: "around"),
            KoiNutrientGoal(key: "protein", name: "Protein", unit: "g", goal: 140, step: 5),
            KoiNutrientGoal(key: "fiber", name: "Fiber", unit: "g", goal: 30, step: 1),
            KoiNutrientGoal(key: "water", name: "Water", unit: "oz", goal: 100, step: 8),
            KoiNutrientGoal(key: "added_sugar", name: "Added sugar", unit: "g", goal: 36, step: 1, goalType: "limit"),
            KoiNutrientGoal(key: "carbs", name: "Carbs", unit: "g", goal: 250, step: 5, goalType: "track"),
            KoiNutrientGoal(key: "fat", name: "Fat", unit: "g", goal: 70, step: 5, goalType: "track")
        ] { context.insert(goal) }
        let supplements = ["Vitamin D", "Omega-3", "Magnesium"].map { KoiSupplement(name: $0) }
        supplements.forEach { context.insert($0) }
        for (offset, pounds) in [(7, 152.4), (3, 151.8), (0, 151.2)] {
            if let date = calendar.date(byAdding: .day, value: -offset, to: today) {
                context.insert(KoiBodyWeightEntry(date: date, weightLB: pounds))
            }
        }

        let titles = ["Morning walk", "Stretch", "Read 10 pages", "Plan tomorrow", "Long training session"]
        let streakLengths = [9, 7, 4, 6, 5]
        let habits = titles.enumerated().map { index, title in
            let schedule = index == 4 ? "someDays" : "daily"
            let weekdays = index == 4 ? [2, 4, 6] : []
            let minimums = ["Step outside", "Stretch briefly", "Read one page", "Write one line", "Start training"]
            return KoiHabit(title: title, createdAt: created.addingTimeInterval(TimeInterval(index)), schedule: schedule, weekdays: weekdays, minimumVersion: minimums[index], stackingCue: index == 2 ? "morning coffee" : "", identity: index == 2 ? "a reader" : "")
        }
        habits.forEach { context.insert($0) }
        for offset in 0...32 {
            guard let date = calendar.date(byAdding: .day, value: -offset, to: today) else { continue }
            if offset <= 28 {
                for (index, habit) in habits.enumerated() {
                    let activeStreakDay = index == 2 ? (offset > 0 && offset <= streakLengths[index]) : offset < streakLengths[index]
                    let completion = activeStreakDay ? 2 : 0
                    context.insert(KoiHabitLog(habitID: habit.id, date: date, completion: completion))
                }
            }
            if offset == 0 {
                for (key, value) in [("calories", 1_450.0), ("protein", 92.0), ("fiber", 18.0), ("water", 60.0), ("added_sugar", 22.0)] {
                    context.insert(KoiNutrientEntry(date: date, nutrientKey: key, value: value))
                }
            } else {
                context.insert(KoiFoodEntry(name: ["Yogurt and fruit", "Chicken bowl", "Eggs and toast", "Tofu noodles", "Salmon rice bowl", "Turkey sandwich", "Oatmeal and berries"][offset % 7], loggedAt: date.addingTimeInterval(12 * 3_600), calories: [1_950.0, 2_280, 2_060, 2_390, 2_120, 1_880, 2_160][offset % 7], proteinGrams: 120 + Double(offset % 7 * 4), carbohydrateGrams: 210, fatGrams: 66, fiberGrams: 24 + Double(offset % 5), confidence: 0.84))
                context.insert(KoiNutrientEntry(date: date, nutrientKey: "water", value: [78.0, 96, 110, 84, 102, 72, 94][offset % 7]))
            }
            if offset <= 28 {
                for supplement in supplements {
                    context.insert(KoiSupplementLog(supplementID: supplement.id, date: date, isTaken: offset > 0 && offset % 3 != 0))
                }
            }
            let stepValues = [6_840, 7_400, 11_300, 6_100, 8_800, 10_400, 7_900, 9_200]
            let trained = [1, 3, 5].contains(offset % 7)
            context.insert(KoiMovementDay(date: date, healthSteps: stepValues[offset % stepValues.count], healthWorkoutCount: (offset == 0 || trained) ? 1 : 0))
            let qualifyingStreakDay = offset < 12 || (offset >= 15 && offset < 33)
            let score = qualifyingStreakDay ? 0.82 : 0.42
            context.insert(KoiDay(date: date, balance: score, habitsScore: 0.75, nutritionScore: 0.64, exerciseScore: (offset == 0 || trained) ? 0.93 : 0.53))
        }

        let tasks = [
            KoiTask(title: "Finish project draft", notes: "Second pass on the intro.", dueAt: today, quadrant: 1),
            KoiTask(title: "Grocery run", quadrant: 0),
            KoiTask(title: "Book dentist", notes: "Overdue.", quadrant: 0),
            KoiTask(title: "Call trainer", dueAt: calendar.date(byAdding: .day, value: 2, to: today), quadrant: 1)
        ]
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
        try context.save()
    }
}
