import SwiftUI
import SwiftData
import KoiShared

struct HubView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.analyticsProvider) private var analyticsProvider
    @Environment(\.calendarProvider) private var calendarProvider
    @State private var model = HubViewModel()
    @State private var pondModel: PondViewModel
    let onSelectTab: (KoiTab) -> Void
    let onPresentSmartNote: () -> Void
    let onResetStageDemo: () -> Void
    let pondService: any PondService

    init(onSelectTab: @escaping (KoiTab) -> Void, onPresentSmartNote: @escaping () -> Void, onResetStageDemo: @escaping () -> Void = {}, pondService: any PondService = CloudKitPondService()) {
        self.onSelectTab = onSelectTab
        self.onPresentSmartNote = onPresentSmartNote
        self.onResetStageDemo = onResetStageDemo
        self.pondService = pondService
        _pondModel = State(initialValue: PondViewModel(service: pondService))
    }

    var body: some View {
        ZStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: KoiTheme.space.s13) {
                    header.modifier(KoiIntroReveal(order: 0))
                    if model.isProfileOpen { KoiProfileView(onSelectTab: onSelectTab, onPresentSmartNote: onPresentSmartNote, onResetStageDemo: onResetStageDemo).transition(.opacity) }
                    else if model.isProgressOpen { KoiProgressView().transition(.opacity) }
                    else if model.isPondOpen { PondScreen(model: pondModel, displayName: model.displayName, scores: model.balance).transition(.opacity) }
                    else {
                        hero.modifier(KoiIntroReveal(order: 2))
                        coachCard
                        todaySection.modifier(KoiIntroReveal(order: 5))
                    }
                }
                .padding(.horizontal, KoiTheme.space.s21)
                .padding(.top, KoiTheme.space.s13)
                .padding(.bottom, KoiTheme.space.s89)
            }
            .scrollClipDisabled()
            .contentMargins(.bottom, 18)
        }
        .onAppear {
            model.refresh(using: modelContext)
            Task { await pondModel.syncDailyScore(model.balance) }
            #if DEBUG
            if let state = KoiLaunch.tourState {
                switch state {
                case "coach": model.prepareTourCoach(run: false)
                case "runSuggestion": model.prepareTourCoach(run: true)
                case "pond": model.togglePond()
                default: break
                }
            } else {
                requestMorningCoachIfNeeded()
            }
            #else
            requestMorningCoachIfNeeded()
            #endif
            #if DEBUG
            if let panel = KoiLaunch.screen ?? launchPanelArgument {
                switch panel.lowercased() {
                case "progress": model.toggleProgress()
                case "profile": model.toggleProfile()
                case "pond": model.togglePond()
                default: break
                }
            }
            #endif
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                model.refresh(using: modelContext)
                requestMorningCoachIfNeeded()
                Task { await pondModel.syncDailyScore(model.balance) }
            }
        }
        .onChange(of: model.isPondOpen) { _, opened in
            #if DEBUG
            guard opened, KoiLaunch.stageEnabled else { return }
            Task {
                await pondModel.syncDailyScore(model.balance)
                await model.requestCoach(event: "pond", pondRank: pondModel.rankSummary ?? "3rd of 5 in your pond", using: calendarProvider)
            }
            #endif
        }
        .onReceive(NotificationCenter.default.publisher(for: .koiCoachRequested)) { note in
            model.refresh(using: modelContext)
            let event = note.userInfo?["event"] as? String ?? "morning"
            Task {
                await pondModel.syncDailyScore(model.balance)
                await model.requestCoach(event: event, pondRank: pondModel.rankSummary, using: calendarProvider)
            }
        }
        .animation(KoiTheme.morph, value: model.isProfileOpen)
        .animation(KoiTheme.morph, value: model.isProgressOpen)
        .animation(KoiTheme.morph, value: model.isPondOpen)
    }

    #if DEBUG
    private var launchPanelArgument: String? {
        let arguments = ProcessInfo.processInfo.arguments
        guard let marker = arguments.firstIndex(of: "-koiHubPanel"), arguments.indices.contains(marker + 1) else { return nil }
        return arguments[marker + 1]
    }
    #endif

    @MainActor
    private func requestMorningCoachIfNeeded() {
#if DEBUG
        guard !KoiLaunch.stageEnabled else { return }
#endif
        guard (try? modelContext.fetch(FetchDescriptor<KoiOnboardingState>()).first?.isComplete) == true else { return }
        let calendar = Calendar.autoupdatingCurrent
        let day = calendar.startOfDay(for: .now).timeIntervalSince1970
        let key = "koi.coach.morning.presentedDay"
        guard UserDefaults.standard.double(forKey: key) != day else { return }
        UserDefaults.standard.set(day, forKey: key)
        Task {
            await pondModel.syncDailyScore(model.balance)
            await model.requestCoach(event: "morning", pondRank: pondModel.rankSummary, using: calendarProvider)
        }
    }

    @ViewBuilder
    private var coachCard: some View {
        if model.isCoachLoading || model.coachSuggestion != nil {
            VStack(alignment: .leading, spacing: KoiTheme.space.s8) {
                HStack(spacing: KoiTheme.space.s5) {
                    Image(systemName: "sparkles").font(.system(size: 12))
                    Text("KOI COACH").font(KoiTheme.section).tracking(2)
                }.opacity(0.78)
                if model.isCoachLoading {
                    Text("Finding one small next step…").font(KoiTheme.body)
                } else if let suggestion = model.coachSuggestion {
                    Text(suggestion.message).font(KoiTheme.body).fixedSize(horizontal: false, vertical: true).accessibilityIdentifier("stage.coach.message")
                    HStack(spacing: KoiTheme.space.s13) {
                        Button {
                            KoiHaptics.success()
                            let action = suggestion.action.type
                            Task {
                                await model.acceptCoach(using: calendarProvider)
                                if action == .adjustGoal { onSelectTab(.intake) }
                                if action == .addTodo { onSelectTab(.toDo) }
                            }
                        } label: { Text("Accept").font(KoiTheme.caption).padding(.horizontal, 13).padding(.vertical, 7).background(KoiTheme.onBase.opacity(0.18), in: Capsule()) }
                            .buttonStyle(.plain).accessibilityIdentifier("stage.coach.accept")
                        Button("Not now") { KoiHaptics.tap(); model.dismissCoach() }
                            .font(KoiTheme.caption).opacity(0.75).buttonStyle(.plain).accessibilityIdentifier("stage.coach.dismiss")
                    }.padding(.top, 2)
                }
            }
            .foregroundStyle(KoiTheme.onBase)
            .padding(.horizontal, KoiTheme.space.s13)
            .padding(.vertical, KoiTheme.space.s13)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.ultraThinMaterial.opacity(0.28), in: RoundedRectangle(cornerRadius: 17))
            .overlay(RoundedRectangle(cornerRadius: 17).strokeBorder(KoiTheme.onBase.opacity(0.19), lineWidth: 1))
            .transition(.opacity.combined(with: .move(edge: .top)))
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center) {
                Image("KoiWordmark")
                    .resizable()
                    .renderingMode(.template)
                    .scaledToFit()
                    .frame(width: 240, height: 28)
                    .foregroundStyle(Color(red: 0.91, green: 0.93, blue: 0.95))
                    .accessibilityLabel("Koi")
                    .onTapGesture {
                        KoiHaptics.tap()
                        withAnimation(KoiTheme.morph) { model.closeInPlace() }
                    }
                Spacer()
                Button {
                    KoiHaptics.tap()
                    withAnimation(KoiTheme.morph) {
                        if model.isProfileOpen || model.isProgressOpen || model.isPondOpen { model.closeInPlace() }
                        else { model.toggleProfile() }
                    }
                } label: {
                    Image(systemName: model.isProfileOpen || model.isProgressOpen || model.isPondOpen ? "xmark" : "person")
                        .font(.system(size: 21, weight: .light))
                        .foregroundStyle(KoiTheme.onBase)
                        .frame(width: 44, height: 44)
                        .padding(.vertical, -8)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(model.isProfileOpen || model.isProgressOpen || model.isPondOpen ? "Close" : "Profile")
            }
            VStack(alignment: .leading, spacing: 0) {
                Text(model.dateLabel.uppercased())
                    .font(KoiTheme.section)
                    .tracking(2.7)
                    .foregroundStyle(Color(red: 0.91, green: 0.93, blue: 0.95).opacity(0.88))
                    .padding(.top, 7)
                Text(model.isProfileOpen ? "Profile" : (model.isProgressOpen ? "Progress" : (model.isPondOpen ? "Your Koi Pond" : model.greeting)))
                    .id(model.isProfileOpen ? "Profile" : (model.isProgressOpen ? "Progress" : (model.isPondOpen ? "Your Koi Pond" : model.greeting)))
                    .font(KoiTheme.title)
                    .foregroundStyle(Color(red: 0.91, green: 0.93, blue: 0.95))
                    .transition(.opacity.combined(with: .blurReplace))
                    .padding(.top, 3)
            }
        }
    }

    private var hero: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .topTrailing) {
            GeometryReader { proxy in
                KoiDial(
                    score: model.balance.score,
                    habits: model.balance.habits,
                    nutrition: model.balance.nutrition,
                    exercise: model.balance.exercise,
                    onScoreTap: {
                        KoiHaptics.tap()
                        withAnimation(KoiTheme.morph) { model.toggleProgress() }
                    },
                    onPillarTap: { pillar in
                        KoiHaptics.tap()
                        if model.selectedPillar == pillar {
                            analyticsProvider.signal("Hub.pillarOpened", parameters: ["pillar": pillar.rawValue.lowercased()])
                            onSelectTab(pillar.tab)
                        } else {
                            analyticsProvider.signal("Hub.pillarOpened", parameters: ["pillar": pillar.rawValue.lowercased()])
                            withAnimation(KoiTheme.morph) { model.selectPillar(pillar) }
                        }
                    },
                    weights: model.focusWeights
                )
                .contentShape(Rectangle())
                .simultaneousGesture(
                    LongPressGesture(minimumDuration: 0.3)
                        .sequenced(before: DragGesture(minimumDistance: 0))
                        .onChanged { state in
                            switch state {
                            case .first(true): model.beginScrub()
                            case .second(true, let drag?): model.updateScrub(translation: drag.translation.height)
                            default: break
                            }
                        }
                        .onEnded { _ in model.endScrub() }
                )
                .accessibilityAction(named: Text("Previous day")) {
                    model.selectDay(daysAgo: model.selectedDayOffset + 1)
                }
                .accessibilityAction(named: Text("Next day")) {
                    model.selectDay(daysAgo: model.selectedDayOffset - 1)
                }
            }
            .frame(height: coachIsVisible ? 390 : 470)
            .padding(.horizontal, -KoiTheme.space.s21)
            .padding(.top, -22)
            .padding(.bottom, -4)
            VStack(alignment: .trailing, spacing: 8) {
                Button {
                    KoiHaptics.tap()
                    withAnimation(KoiTheme.morph) { model.toggleProgress() }
                } label: {
                    HStack(spacing: 6) {
                        if model.hasWeekOfHistory { Image(systemName: model.trendIsPositive ? "arrow.up.right" : "arrow.down.right").font(.system(size: 10)).foregroundStyle(KoiTheme.onBase) }
                        Text(model.trendText).font(KoiTheme.caption).lineLimit(1).foregroundStyle(KoiTheme.onBase)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(.ultraThinMaterial.opacity(0.6), in: Capsule())
                    .overlay(Capsule().strokeBorder(.white.opacity(0.35), lineWidth: 1))
                    .frame(maxWidth: 160, alignment: .trailing)
                    .foregroundStyle(KoiTheme.onBase)
                }
                .buttonStyle(.plain)
                .foregroundColor(.white.opacity(0.9))
                .accessibilityLabel("Open progress. \(model.trendText)")
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
            .padding(.trailing, KoiTheme.space.s21)
            .padding(.top, 128)
            streakBlock
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                .padding(.trailing, KoiTheme.space.s21)
                .padding(.top, 273)
            Button {
                KoiHaptics.tap()
                withAnimation(KoiTheme.morph) { model.togglePond() }
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "person.2").font(.system(size: 10, weight: .regular))
                    Text("Go to pond").font(.custom("RobotoMono-Regular", size: 10))
                }
                .padding(.horizontal, 7)
                .padding(.vertical, 5)
                .background(.ultraThinMaterial.opacity(0.55), in: Capsule())
                .overlay(Capsule().strokeBorder(KoiTheme.onBase.opacity(0.3), lineWidth: 1))
            }
            .buttonStyle(.plain)
            .foregroundStyle(KoiTheme.onBase)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
            .padding(.trailing, 125)
            .padding(.top, 12)
            .accessibilityLabel("Go to your pond")
            .accessibilityIdentifier("stage.pond.open")
            if model.selectedDayOffset > 0 {
                Text(model.dateLabel.uppercased())
                    .font(KoiTheme.section).tracking(2.7)
                    .foregroundStyle(KoiTheme.onBase.opacity(0.8))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .padding(.leading, KoiTheme.space.s21)
                    .padding(.top, 128)
                    .allowsHitTesting(false)
            }
            }
            .frame(height: coachIsVisible ? 390 : 470)
            if let pillar = model.selectedPillar { pillarDetail(pillar).transition(.opacity.combined(with: .move(edge: .top))) }
        }
    }

    private var coachIsVisible: Bool { model.coachSuggestion != nil || model.isCoachLoading }

    private var streakBlock: some View {
        VStack(alignment: .trailing, spacing: -1) {
            HStack(spacing: 6) {
                Image("KoiFlame").resizable().renderingMode(.template).scaledToFit().frame(height: 27).foregroundStyle(KoiTheme.onBase)
                Text("\(model.streak.current)").font(.system(size: 39)).monospacedDigit()
            }
            Text("DAY STREAK").font(KoiTheme.section).tracking(2.7)
            Text("best \(model.streak.best)").font(KoiTheme.caption).opacity(0.78)
        }
        .foregroundStyle(KoiTheme.onBase.opacity(0.8))
        .accessibilityLabel("Streak \(model.streak.current), best \(model.streak.best), \(model.streak.freezes) freezes")
    }

    private var todaySection: some View {
        VStack(alignment: .leading, spacing: KoiTheme.space.s8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("TODAY")
                    .font(KoiTheme.section)
                    .tracking(2.7)
                    .foregroundStyle(KoiTheme.onBase.opacity(0.92))
                Spacer(minLength: 0)
                if model.hiddenItemCount > 0 {
                    Button {
                        KoiHaptics.tap()
                        withAnimation(KoiTheme.morph) { model.toggleExpandedItems() }
                    } label: {
                        HStack(spacing: 4) { Text(model.expandedItems ? "Less" : "+\(model.hiddenItemCount) more"); Image(systemName: "chevron.down").font(.system(size: 9, weight: .semibold)).rotationEffect(.degrees(model.expandedItems ? 180 : 0)) }
                            .font(KoiTheme.caption).foregroundStyle(KoiTheme.onBase).frame(minHeight: 24)
                    }.buttonStyle(.plain)
                }
            }

            if model.items.isEmpty {
                HStack {
                    Text("Nothing to carry today.")
                        .font(KoiTheme.body)
                        .foregroundStyle(KoiTheme.onBase.opacity(0.84))
                    Spacer()
                    Button("Open To-Do") { onSelectTab(.toDo) }
                        .buttonStyle(.plain)
                        .font(KoiTheme.caption)
                        .foregroundStyle(KoiTheme.onBase)
                }
                .padding(.vertical, 8)
            } else {
                VStack(spacing: KoiTheme.space.s8) {
                    ForEach(model.visibleItems) { item in
                        todayRow(item)
                    }
                }
            }
        }
    }

    private func todayRow(_ item: HubTodayItem) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: KoiTheme.space.s13) {
                Button {
                    KoiHaptics.check()
                    model.toggle(item)
                } label: {
                    ZStack {
                        Circle()
                            .strokeBorder(KoiTheme.onBase.opacity(item.isComplete ? 0.9 : 0.62), lineWidth: 1)
                        if item.isComplete {
                            Circle().fill(KoiTheme.onBase)
                            Image(systemName: "checkmark")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(KoiTheme.glassInk)
                        }
                    }
                    .frame(width: 22, height: 22)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(item.isComplete ? "Mark \(item.title) open" : "Complete \(item.title)")

                Button {
                    KoiHaptics.tap()
                    model.selectItem(item.id)
                } label: {
                    Text(item.title)
                            .font(.custom("RobotoMono-Light", size: 15))
                            .strikethrough(item.isComplete, color: KoiTheme.onBase.opacity(0.55))
                    .foregroundStyle(KoiTheme.onBase.opacity(item.isComplete ? 0.72 : 0.95))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                Spacer(minLength: 0)
                Text(item.kind == .habit ? "Daily" : "To-do")
                    .font(KoiTheme.caption)
                    .foregroundStyle(KoiTheme.onBase.opacity(0.86))
            }
            if model.selectedItemID == item.id {
                EmptyView()
            }
            Rectangle()
                .fill(KoiTheme.divider.opacity(0.72))
                .frame(height: 0.5)
        }
    }

    private func pillarDetail(_ pillar: HubPillar) -> some View {
        let value = switch pillar { case .habits: model.balance.habits; case .nutrition: model.balance.nutrition; case .exercise: model.balance.exercise }
        let detail = switch pillar {
        case .habits: "\(model.habitsDone) of \(model.habitsScheduled) habits done"
        case .nutrition: "\(model.caloriesText) / \(model.caloriesGoalText) kcal · protein \(model.proteinText)/\(model.proteinGoalText) g"
        case .exercise: "\(model.stepsText) / \(model.stepGoalText) steps · \(model.workoutsText) workouts"
        }
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(pillar.rawValue.uppercased()).font(KoiTheme.section).tracking(2.7)
                Spacer()
                Text("\(Int((value * 100).rounded()))%")
                    .font(.system(size: 22, weight: .semibold, design: .rounded)).monospacedDigit()
            }
            Text(detail).font(KoiTheme.caption).foregroundStyle(KoiTheme.onBase.opacity(0.92))
            HStack(spacing: 8) {
                if pillar == .nutrition { GlassChip(title: "Log food", symbol: "fork.knife").onTapGesture { onSelectTab(.intake) } }
                if pillar == .exercise { GlassChip(title: "Start workout", symbol: "dumbbell").onTapGesture { onSelectTab(.movement) } }
                Button("Open \(pillar.tab.title) →") { onSelectTab(pillar.tab) }.font(KoiTheme.caption).buttonStyle(.plain)
                Spacer()
                Button { withAnimation(KoiTheme.morph) { model.selectPillar(pillar) } } label: {
                    Image(systemName: "xmark").font(.system(size: 12, weight: .light)).frame(width: 32, height: 32)
                }.buttonStyle(.plain)
            }
        }
        .padding(.top, KoiTheme.space.s8)
        .foregroundStyle(KoiTheme.onBase)
    }
}

private struct PondScreen: View {
    @Bindable var model: PondViewModel
    let displayName: String
    let scores: BalanceResult

    var body: some View {
        VStack(alignment: .leading, spacing: KoiTheme.space.s21) {
            if snapshotNameIsSample {
                Text("SAMPLE FRIENDS · LOCAL DEMO")
                    .font(KoiTheme.section).tracking(1.8).opacity(0.78)
                    .accessibilityIdentifier("stage.pond.sample")
            }
            if model.isLoading && model.snapshot == nil {
                Text("Finding your pond…").font(KoiTheme.body).padding(.vertical, KoiTheme.space.s21)
            }
            if let error = model.errorMessage {
                VStack(alignment: .leading, spacing: KoiTheme.space.s8) {
                    Text(error).font(KoiTheme.caption)
                    Button("Retry") { Task { await model.retry(displayName: displayName, scores: scores) } }
                        .font(KoiTheme.caption).buttonStyle(.plain)
                }
                .padding(.vertical, KoiTheme.space.s8)
            }
            if model.needsUsername {
                usernameSetup
            } else if let snapshot = model.snapshot {
                community(snapshot)
            }
        }
        .foregroundStyle(KoiTheme.onBase)
        .onAppear { Task { await model.load(displayName: displayName, scores: scores) } }
        .animation(KoiTheme.morph, value: model.snapshot?.sprint?.recordName)
    }

    private var snapshotNameIsSample: Bool { model.snapshot?.name == "Sample friends" }

    private var usernameSetup: some View {
        VStack(alignment: .leading, spacing: KoiTheme.space.s13) {
            Text("A small circle can make good days easier to keep.").font(KoiTheme.body)
            TextField("Choose a username", text: $model.username)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .font(.custom("RobotoMono-Regular", size: 15))
                .padding(.vertical, KoiTheme.space.s8)
                .overlay(alignment: .bottom) { Rectangle().fill(KoiTheme.onBase.opacity(0.34)).frame(height: 1) }
                .task(id: model.username) {
                    try? await Task.sleep(for: .milliseconds(350))
                    await model.checkUsername(model.username)
                }
            Text(usernameStatusText).font(KoiTheme.caption).opacity(0.76)
            KoiPrimaryButton(title: model.isSaving ? "Creating…" : "Create your pond") {
                Task { await model.createProfile(displayName: displayName) }
            }
            .disabled(model.usernameStatus != .available || model.isSaving)
            Text("Choose 3–20 letters, numbers, or underscores.").font(KoiTheme.caption).opacity(0.65)
        }
    }

    private var usernameStatusText: String {
        switch model.usernameStatus {
        case .idle: "Check that your username is available."
        case .checking: "Checking availability…"
        case .available: "Available"
        case .taken: "Taken. Try another one."
        case .invalid: "Use 3–20 letters, numbers, or underscores."
        }
    }

    private func community(_ snapshot: PondSnapshot) -> some View {
        VStack(alignment: .leading, spacing: KoiTheme.space.s21) {
            if snapshot.members.count <= 1 {
                Text("Add a friend by username to start your pond.")
                    .font(KoiTheme.body).fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 4)
            } else {
                friendEntry
            }
            if snapshot.name == "Sample friends" {
                Text("Sample schedule · Class tomorrow at 9:00 AM")
                    .font(KoiTheme.caption).opacity(0.72)
                    .accessibilityIdentifier("stage.pond.sampleSchedule")
            }
            if let sprint = snapshot.sprint {
                if model.isSprintFinished {
                    finishedSprint(sprint)
                } else {
                    activeSprint(sprint)
                }
            } else {
                Text("No sprint yet.").font(KoiTheme.caption).opacity(0.76)
                if snapshot.members.count > 1 { sprintBuilder() }
            }
            if snapshot.members.count <= 1 { friendEntry }
        }
    }

    private var friendEntry: some View {
        VStack(alignment: .leading, spacing: KoiTheme.space.s8) {
            Text("ADD FRIEND").font(KoiTheme.section).tracking(2).opacity(0.78)
            HStack(spacing: KoiTheme.space.s13) {
                TextField("Exact username", text: $model.friendUsername)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                    .font(.custom("RobotoMono-Regular", size: 14))
                    .padding(.vertical, KoiTheme.space.s8)
                    .overlay(alignment: .bottom) { Rectangle().fill(KoiTheme.onBase.opacity(0.34)).frame(height: 1) }
                Button("Add") { Task { await model.addFriend() } }
                    .font(KoiTheme.caption).buttonStyle(.plain).disabled(model.friendUsername.isEmpty || model.isSaving)
            }
        }
    }

    private func activeSprint(_ sprint: PondSprint) -> some View {
        VStack(alignment: .leading, spacing: KoiTheme.space.s13) {
            Text("ACTIVE SPRINT").font(KoiTheme.section).tracking(2).opacity(0.78)
            Text(sprintTitle(sprint)).font(KoiTheme.title).fixedSize(horizontal: false, vertical: true)
            if !sprint.rule.isEmpty { Text(sprint.rule).font(KoiTheme.caption).opacity(0.8) }
            Text("\(PondEngine.daysRemaining(until: sprint.endDate)) days left")
                .font(.custom("RobotoMono-Regular", size: 13)).opacity(0.82)
            Text("LEADERBOARD").font(KoiTheme.section).tracking(2).opacity(0.78).padding(.top, KoiTheme.space.s8)
            ForEach(model.leaderboard) { entry in leaderboardRow(entry, currentUsername: snapshotUsername) }
        }
    }

    private func finishedSprint(_ sprint: PondSprint) -> some View {
        VStack(alignment: .leading, spacing: KoiTheme.space.s13) {
            Text("SPRINT COMPLETE").font(KoiTheme.section).tracking(2).opacity(0.78)
            if let winner = model.winner {
                Text(sprint.rule.isEmpty ? "\(winner.member.displayName) wins." : "\(winner.member.displayName) wins. \(sprint.rule)")
                    .font(KoiTheme.title).fixedSize(horizontal: false, vertical: true)
            }
            Text("LEADERBOARD").font(KoiTheme.section).tracking(2).opacity(0.78).padding(.top, KoiTheme.space.s8)
            ForEach(model.leaderboard) { entry in leaderboardRow(entry, currentUsername: snapshotUsername) }
            sprintBuilder(buttonTitle: "Start another sprint")
        }
    }

    private func sprintBuilder(buttonTitle: String = "Start sprint") -> some View {
        VStack(alignment: .leading, spacing: KoiTheme.space.s13) {
            Text("START A SPRINT").font(KoiTheme.section).tracking(2).opacity(0.78)
            HStack(spacing: KoiTheme.space.s8) {
                ForEach(PondPillar.allCases) { pillar in
                    Button { model.toggle(pillar) } label: {
                        Text(pillar.title).font(.custom("RobotoMono-Regular", size: 11))
                            .padding(.horizontal, 9).padding(.vertical, 7)
                            .background(model.pillars.contains(pillar) ? KoiTheme.onBase.opacity(0.22) : .clear, in: Capsule())
                            .overlay(Capsule().strokeBorder(KoiTheme.onBase.opacity(0.34), lineWidth: 1))
                    }.buttonStyle(.plain)
                }
            }
            DatePicker("Ends", selection: $model.endDate, in: Date.now..., displayedComponents: .date)
                .font(KoiTheme.caption).tint(KoiTheme.onBase)
            TextField("Losers buy the winner a coffee", text: $model.rule, axis: .vertical)
                .font(KoiTheme.caption).lineLimit(2...4)
                .padding(.vertical, KoiTheme.space.s8)
                .overlay(alignment: .bottom) { Rectangle().fill(KoiTheme.onBase.opacity(0.34)).frame(height: 1) }
            KoiPrimaryButton(title: model.isSaving ? "Starting…" : buttonTitle) { Task { await model.startSprint() } }
                .disabled(model.pillars.isEmpty || model.endDate <= .now || model.isSaving)
        }
    }

    private func leaderboardRow(_ entry: PondLeaderboardEntry, currentUsername: String) -> some View {
        let isCurrent = entry.member.username.lowercased() == currentUsername.lowercased()
        return VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: KoiTheme.space.s8) {
                Text(entry.rank == 1 ? "♛" : "\(entry.rank)").font(.custom("RobotoMono-Regular", size: 13)).frame(width: 20, alignment: .leading)
                    .accessibilityIdentifier(entry.member.username == "jasmine" ? "stage.pond.rank.jasmine" : "stage.pond.rank.\(entry.rank)")
                Text(entry.member.displayName).font(.custom("RobotoMono-Regular", size: 14)).lineLimit(1)
                    .accessibilityIdentifier(entry.member.username == "jasmine" ? "stage.pond.jasmine" : "stage.pond.member.\(entry.member.username)")
                Spacer()
                Text("\(Int((entry.score * 100).rounded()))%").font(.custom("RobotoMono-Regular", size: 13)).monospacedDigit()
            }
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(KoiTheme.onBase.opacity(0.2)).frame(height: 2)
                    Capsule().fill(KoiTheme.onBase.opacity(0.6)).frame(width: max(2, proxy.size.width * entry.score), height: 2)
                    Circle().fill(.white.opacity(0.9)).frame(width: 7, height: 7).offset(x: max(0, proxy.size.width * entry.score - 3.5))
                }.frame(maxHeight: .infinity)
            }.frame(height: 7)
        }
        .padding(.horizontal, isCurrent ? KoiTheme.space.s8 : 0)
        .padding(.vertical, KoiTheme.space.s5)
        .background(isCurrent ? KoiTheme.onBase.opacity(0.11) : .clear, in: RoundedRectangle(cornerRadius: 9))
    }

    private var snapshotUsername: String { model.snapshot?.currentUsername ?? "" }

    private func sprintTitle(_ sprint: PondSprint) -> String {
        let names = PondPillar.allCases.filter(sprint.pillars.contains).map(\.title).joined(separator: " + ")
        return "Highest \(names) by \(sprint.endDate.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()))"
    }
}

