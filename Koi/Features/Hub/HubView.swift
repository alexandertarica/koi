import SwiftUI
import SwiftData
import KoiShared

struct HubView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @State private var model = HubViewModel()
    let onSelectTab: (KoiTab) -> Void

    var body: some View {
        ZStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: KoiTheme.space.s21) {
                    header.modifier(KoiIntroReveal(order: 0))
                    if model.isProfileOpen { KoiProfileView(onSelectTab: onSelectTab).transition(.opacity) }
                    else if model.isProgressOpen { KoiProgressView().transition(.opacity) }
                    else {
                        hero.modifier(KoiIntroReveal(order: 2))
                        todaySection.modifier(KoiIntroReveal(order: 5))
                    }
                }
                .padding(.horizontal, KoiTheme.space.s21)
                .padding(.top, KoiTheme.space.s21)
                .padding(.bottom, KoiTheme.space.s89)
            }
            .scrollClipDisabled()
            .contentMargins(.bottom, 18)
            .mask {
                VStack(spacing: 0) {
                    Rectangle().fill(.black)
                    LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom)
                        .frame(height: 89)
                }
            }
        }
        .onAppear { model.refresh(using: modelContext) }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { model.refresh(using: modelContext) }
        }
        .animation(KoiTheme.morph, value: model.isProfileOpen)
        .animation(KoiTheme.morph, value: model.isProgressOpen)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center) {
                Image("KoiWordmark")
                    .resizable()
                    .renderingMode(.template)
                    .scaledToFit()
                    .frame(width: 240, height: 28)
                    .foregroundStyle(KoiTheme.onBase)
                    .accessibilityLabel("Koi")
                    .onTapGesture {
                        KoiHaptics.tap()
                        withAnimation(KoiTheme.morph) { model.closeInPlace() }
                    }
                Spacer()
                Button {
                    KoiHaptics.tap()
                    withAnimation(KoiTheme.morph) { model.toggleProfile() }
                } label: {
                    Image(systemName: model.isProfileOpen || model.isProgressOpen ? "xmark" : "person")
                        .font(.system(size: 21, weight: .light))
                        .foregroundStyle(KoiTheme.onBase)
                        .frame(width: 44, height: 44)
                        .padding(.vertical, -8)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(model.isProfileOpen || model.isProgressOpen ? "Close" : "Profile")
            }
            VStack(alignment: .leading, spacing: 0) {
                Text(model.dateLabel.uppercased())
                    .font(KoiTheme.section)
                    .tracking(2.7)
                    .foregroundStyle(KoiTheme.onBase.opacity(0.8))
                    .padding(.top, 7)
                Text(model.isProfileOpen ? "Profile" : (model.isProgressOpen ? "Progress" : model.greeting))
                    .id(model.isProfileOpen ? "Profile" : (model.isProgressOpen ? "Progress" : model.greeting))
                    .font(KoiTheme.title)
                    .foregroundStyle(KoiTheme.onBase)
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
                        if model.selectedPillar == pillar { onSelectTab(pillar.tab) }
                        else { withAnimation(KoiTheme.morph) { model.selectPillar(pillar) } }
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
            .frame(height: 470)
            .padding(.horizontal, -KoiTheme.space.s21)
            .padding(.top, -22)
            .padding(.bottom, -4)
            VStack(alignment: .trailing, spacing: 8) {
                Button {
                    KoiHaptics.tap()
                    withAnimation(KoiTheme.morph) { model.toggleProgress() }
                } label: {
                    HStack(spacing: 6) {
                        if model.hasWeekOfHistory { Image(systemName: model.trendIsPositive ? "arrow.up.right" : "arrow.down.right").font(.system(size: 10)) }
                        Text(model.trendText).font(KoiTheme.caption).lineLimit(1)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(.ultraThinMaterial.opacity(0.6), in: Capsule())
                    .overlay(Capsule().strokeBorder(.white.opacity(0.35), lineWidth: 1))
                    .frame(maxWidth: 160, alignment: .trailing)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Open progress. \(model.trendText)")
                streakBlock
                    .padding(.top, 100)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
            .padding(.trailing, KoiTheme.space.s21)
            .padding(.top, 128)
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
            .frame(height: 470)
            if let pillar = model.selectedPillar { pillarDetail(pillar).transition(.opacity.combined(with: .move(edge: .top))) }
        }
    }

    private var streakBlock: some View {
        VStack(alignment: .trailing, spacing: -1) {
            HStack(spacing: 6) {
                Image("KoiFlame").resizable().renderingMode(.template).scaledToFit().frame(height: 27).foregroundStyle(KoiTheme.onBase)
                Text("\(model.streak.current)").font(.system(size: 39)).monospacedDigit()
            }
            Text("DAY STREAK").font(KoiTheme.section).tracking(2.7)
            Text("best \(model.streak.best)").font(KoiTheme.caption).opacity(0.78)
            if model.streak.freezes > 0 { Text("❄ \(model.streak.freezes) freezes").font(.system(size: 11, weight: .light)) }
        }
        .foregroundStyle(KoiTheme.onBase.opacity(0.8))
        .accessibilityLabel("Streak \(model.streak.current), best \(model.streak.best), \(model.streak.freezes) freezes")
    }

    private var todaySection: some View {
        VStack(alignment: .leading, spacing: KoiTheme.space.s13) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("TODAY")
                    .font(KoiTheme.section)
                    .tracking(2.7)
                    .foregroundStyle(KoiTheme.onBase.opacity(0.92))
                if model.hiddenItemCount > 0 {
                    Button {
                        KoiHaptics.tap()
                        withAnimation(KoiTheme.morph) { model.toggleExpandedItems() }
                    } label: {
                        HStack(spacing: 4) { Text(model.expandedItems ? "Less" : "+\(model.hiddenItemCount) more"); Image(systemName: "chevron.down").font(.system(size: 9, weight: .semibold)).rotationEffect(.degrees(model.expandedItems ? 180 : 0)) }
                            .font(KoiTheme.caption).foregroundStyle(KoiTheme.onBase).frame(minHeight: 30)
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
        VStack(alignment: .leading, spacing: KoiTheme.space.s8) {
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
                    HStack(spacing: 8) {
                        Text(item.title)
                            .font(.custom("RobotoMono-Light", size: 15))
                            .strikethrough(item.isComplete, color: KoiTheme.onBase.opacity(0.55))
                        if item.kind == .habit {
                            Text(item.completion == 1 ? "MINIMUM" : "HABIT")
                                .font(KoiTheme.caption)
                                .tracking(1)
                                .foregroundStyle(KoiTheme.onBase.opacity(0.62))
                        }
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.down")
                            .font(.system(size: 10, weight: .light))
                            .rotationEffect(.degrees(model.selectedItemID == item.id ? 180 : 0))
                    }
                    .foregroundStyle(KoiTheme.onBase.opacity(item.isComplete ? 0.72 : 0.95))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            if model.selectedItemID == item.id {
                HStack(spacing: 8) {
                    Text(item.kind == .habit ? "A small ritual, kept today." : item.dueAt?.formatted(date: .abbreviated, time: .omitted) ?? "No date")
                        .font(KoiTheme.caption)
                        .foregroundStyle(KoiTheme.onBase.opacity(0.75))
                    Spacer()
                    Text(item.kind == .habit ? "EDIT" : "DETAILS")
                        .font(KoiTheme.caption)
                        .tracking(1.4)
                        .foregroundStyle(KoiTheme.onBase)
                }
                .padding(.leading, 35)
                .transition(.opacity)
            }
            Rectangle()
                .fill(KoiTheme.divider.opacity(0.72))
                .frame(height: 0.5)
                .padding(.leading, 35)
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

