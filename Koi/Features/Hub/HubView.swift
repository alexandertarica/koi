import SwiftUI
import SwiftData
import KoiShared

struct HubView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var model = HubViewModel()
    let onSelectTab: (KoiTab) -> Void

    var body: some View {
        ZStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: KoiTheme.space.s34) {
                    header
                    hero
                    scoreFooter
                    todaySection
                }
                .padding(.horizontal, KoiTheme.space.s21)
                .padding(.top, KoiTheme.space.s21)
                .padding(.bottom, KoiTheme.space.s34)
            }
            .scrollClipDisabled()
            .contentMargins(.bottom, 18)
            .mask {
                LinearGradient(stops: [
                    .init(color: .black, location: 0),
                    .init(color: .black, location: 0.82),
                    .init(color: .clear, location: 1)
                ], startPoint: .top, endPoint: .bottom)
            }
        }
        .task { model.refresh(using: modelContext) }
        .sheet(isPresented: $model.presentsProgress) {
            KoiProgressView()
                .presentationDetents([.large])
                .presentationBackground(.ultraThinMaterial)
        }
        .sheet(isPresented: $model.presentsProfile, onDismiss: { model.refresh(using: modelContext) }) {
            KoiProfileView(onSelectTab: onSelectTab)
                .presentationDetents([.large])
                .presentationBackground(.ultraThinMaterial)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: KoiTheme.space.s13) {
            HStack(alignment: .center) {
                Image("KoiWordmark")
                    .resizable()
                    .renderingMode(.template)
                    .scaledToFit()
                    .frame(width: 76, height: 30)
                    .foregroundStyle(KoiTheme.onBase)
                    .accessibilityLabel("Koi")
                Spacer()
                Button {
                    model.presentsProfile = true
                } label: {
                    Image(systemName: "person.crop.circle")
                        .font(.system(size: 22, weight: .light))
                        .foregroundStyle(KoiTheme.onBase)
                        .frame(width: 40, height: 40)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Profile")
            }
            VStack(alignment: .leading, spacing: 5) {
                Text(model.dateLabel.uppercased())
                    .font(KoiTheme.section)
                    .tracking(2.2)
                    .foregroundStyle(KoiTheme.onBase.opacity(0.8))
                Text(model.greeting)
                    .font(KoiTheme.title)
                    .foregroundStyle(KoiTheme.onBase)
            }
        }
    }

    private var hero: some View {
        VStack(spacing: KoiTheme.space.s5) {
            GeometryReader { proxy in
                KoiDial(
                    score: model.balance.score,
                    habits: model.balance.habits,
                    nutrition: model.balance.nutrition,
                    exercise: model.balance.exercise
                )
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 8).onChanged { value in
                    let width = max(proxy.size.width, 1)
                    let location = min(max(value.location.x, 0), width)
                    model.selectDay(daysAgo: Int(((1 - location / width) * 6).rounded()))
                })
                .accessibilityAction(named: Text("Previous day")) {
                    model.selectDay(daysAgo: model.selectedDayOffset + 1)
                }
                .accessibilityAction(named: Text("Next day")) {
                    model.selectDay(daysAgo: model.selectedDayOffset - 1)
                }
            }
            .frame(height: 238)
            if model.selectedDayOffset > 0 {
                Text(model.dateLabel)
                    .font(KoiTheme.caption)
                    .foregroundStyle(KoiTheme.onBase.opacity(0.78))
                    .transition(.opacity)
            }
            HStack(spacing: 13) {
                ForEach(HubPillar.allCases) { pillar in
                    Button {
                        if model.selectedPillar == pillar {
                            onSelectTab(pillar.tab)
                        } else {
                            withAnimation(.spring(response: 0.34, dampingFraction: 0.86)) {
                                model.selectPillar(pillar)
                            }
                        }
                    } label: {
                        Text(pillar.rawValue)
                            .font(KoiTheme.caption)
                            .foregroundStyle(model.selectedPillar == pillar ? KoiTheme.onBase : KoiTheme.onBase.opacity(0.78))
                            .underline(model.selectedPillar == pillar, color: KoiTheme.onBase.opacity(0.7))
                    }
                    .buttonStyle(.plain)
                }
            }
            .frame(maxWidth: .infinity)
            if let pillar = model.selectedPillar {
                pillarDetail(pillar)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    private var scoreFooter: some View {
        HStack(alignment: .center) {
            Button {
                model.presentsProgress = true
            } label: {
                KoiGlass(strength: .base) {
                    HStack(spacing: 6) {
                        Image(systemName: "chart.xyaxis.line")
                            .font(.system(size: 11, weight: .light))
                        Text(model.trendText)
                            .font(KoiTheme.caption)
                    }
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Open progress. \(model.trendText)")
            Spacer()
            HStack(spacing: 6) {
                Image("KoiFlame")
                    .resizable()
                    .renderingMode(.template)
                    .scaledToFit()
                    .frame(width: 15, height: 18)
                    .foregroundStyle(KoiTheme.onBase)
                Text("\(model.streak.current)")
                    .font(KoiTheme.body)
                    .monospacedDigit()
                Text("best \(model.streak.best)")
                    .font(KoiTheme.caption)
                    .foregroundStyle(KoiTheme.onBase.opacity(0.8))
            }
            .foregroundStyle(KoiTheme.onBase)
            .accessibilityLabel("Streak \(model.streak.current), best \(model.streak.best), \(model.streak.freezes) freezes")
        }
    }

    private var todaySection: some View {
        VStack(alignment: .leading, spacing: KoiTheme.space.s13) {
            HStack(alignment: .firstTextBaseline) {
                Text("TODAY")
                    .font(KoiTheme.section)
                    .tracking(2.4)
                    .foregroundStyle(KoiTheme.onBase.opacity(0.8))
                Spacer()
                if !model.items.isEmpty {
                    Text("\(model.items.filter(\.isComplete).count) / \(model.items.count)")
                        .font(KoiTheme.caption)
                        .monospacedDigit()
                        .foregroundStyle(KoiTheme.onBase.opacity(0.75))
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
                if !model.expandedItems, model.hiddenItemCount > 0 {
                    Button {
                        withAnimation(.spring(response: 0.34, dampingFraction: 0.86)) {
                            model.toggleExpandedItems()
                        }
                    } label: {
                        GlassChip(title: "+\(model.hiddenItemCount) more", symbol: "plus")
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func todayRow(_ item: HubTodayItem) -> some View {
        VStack(alignment: .leading, spacing: KoiTheme.space.s8) {
            HStack(spacing: KoiTheme.space.s13) {
                Button { model.toggle(item) } label: {
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

                Button { model.selectItem(item.id) } label: {
                    HStack(spacing: 8) {
                        Text(item.title)
                            .font(KoiTheme.body)
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
        let value: Double = switch pillar {
        case .habits: model.balance.habits
        case .nutrition: model.balance.nutrition
        case .exercise: model.balance.exercise
        }
        let explanation: String = switch pillar {
        case .habits: "\(Int((value * 100).rounded()))% of today's rituals are in place."
        case .nutrition: "Food and nutrients logged for this day."
        case .exercise: "Steps and training across the week."
        }
        let action: String = switch pillar {
        case .habits: "OPEN TO-DO"
        case .nutrition: "LOG FOOD"
        case .exercise: "START WORKOUT"
        }
        return HStack(alignment: .center, spacing: KoiTheme.space.s13) {
            VStack(alignment: .leading, spacing: 5) {
                Text("\(Int((value * 100).rounded()))%")
                    .font(KoiTheme.body)
                Text(explanation)
                    .font(KoiTheme.caption)
                    .foregroundStyle(KoiTheme.onBase.opacity(0.78))
            }
            Spacer(minLength: 0)
            Button(action) { onSelectTab(pillar.tab) }
                .font(KoiTheme.caption)
                .tracking(1.5)
                .buttonStyle(.plain)
                .foregroundStyle(KoiTheme.onBase)
        }
        .padding(.horizontal, KoiTheme.space.s8)
        .padding(.top, KoiTheme.space.s5)
        .foregroundStyle(KoiTheme.onBase)
    }
}

