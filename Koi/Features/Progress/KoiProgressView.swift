import SwiftData
import SwiftUI

struct KoiProgressView: View {
    @Environment(\.modelContext) private var context
    @State private var model = ProgressViewModel()

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 5), count: 8)

    var body: some View {
        VStack(alignment: .leading, spacing: KoiTheme.space.s21) {
            header
            periodSummary
            if model.scope == .month { monthGrid } else { weekRow }
            Text("Balance uses \(model.focusLabel.lowercased()) weights. Tap a day to see its detail.")
                .font(KoiTheme.caption).opacity(0.66)
        }
        .foregroundStyle(KoiTheme.onBase)
        .task { model.load(context) }
        .alert("Progress", isPresented: Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.clearError() } })) {
            Button("OK", role: .cancel) { model.clearError() }
        } message: { Text(model.errorMessage ?? "") }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: KoiTheme.space.s13) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("PROGRESS").font(KoiTheme.section).tracking(2.2)
                    Text(model.scopeTitle.capitalized).font(KoiTheme.title)
                }
                Spacer()
                HStack(spacing: 4) {
                    ForEach(ProgressScope.allCases) { scope in
                        Button(scope.rawValue) { KoiHaptics.change(); model.setScope(scope) }
                            .font(KoiTheme.caption)
                            .padding(.horizontal, 12).padding(.vertical, 8)
                            .background(model.scope == scope ? KoiTheme.onBase.opacity(0.18) : Color.clear, in: Capsule())
                            .overlay(Capsule().stroke(KoiTheme.onBase.opacity(0.22), lineWidth: 1))
                            .buttonStyle(.plain)
                    }
                }
            }
            HStack(spacing: KoiTheme.space.s13) {
                Button { model.movePeriod(by: -1); KoiHaptics.change() } label: { Image(systemName: "chevron.left").frame(width: 36, height: 36) }.buttonStyle(.plain).accessibilityLabel("Previous \(model.scope.rawValue.lowercased())")
                Text(model.scope == .month ? model.monthLabel.uppercased() : model.weekMetrics.first?.date.formatted(.dateTime.month(.wide).day()).uppercased() ?? "THIS WEEK")
                    .font(KoiTheme.caption).tracking(1.5).opacity(0.78)
                Button { model.movePeriod(by: 1); KoiHaptics.change() } label: { Image(systemName: "chevron.right").frame(width: 36, height: 36) }.buttonStyle(.plain).accessibilityLabel("Next \(model.scope.rawValue.lowercased())")
                if !model.isCurrentPeriod {
                    Button("Today") { KoiHaptics.tap(); model.goToCurrentPeriod() }.font(KoiTheme.caption).buttonStyle(.plain)
                }
                Spacer(minLength: 0)
            }
        }
    }

    private var periodSummary: some View {
        VStack(alignment: .leading, spacing: KoiTheme.space.s13) {
            Text("BALANCE").font(KoiTheme.section).tracking(1.8).opacity(0.74)
            HStack(alignment: .firstTextBaseline, spacing: KoiTheme.space.s8) {
                Text("\(Int((model.currentSummary.averageBalance * 100).rounded()))%")
                    .font(.custom("KOINumerals", size: 42, relativeTo: .largeTitle)).monospacedDigit()
                Text("average").font(KoiTheme.caption).opacity(0.7)
                Spacer()
                let delta = Int(((model.currentSummary.averageBalance - model.previousSummary.averageBalance) * 100).rounded())
                Text(delta == 0 ? "Even" : "\(delta > 0 ? "↑" : "↓") \(abs(delta))")
                    .font(KoiTheme.caption).padding(.horizontal, 10).padding(.vertical, 6)
                    .overlay(Capsule().stroke(KoiTheme.onBase.opacity(0.26), lineWidth: 1))
            }
            HStack(spacing: KoiTheme.space.s8) {
                detailColumn("HABITS", value: "\(model.currentSummary.habitsDone) / \(model.currentSummary.habitsScheduled)", previous: "\(model.previousSummary.habitsDone) / \(model.previousSummary.habitsScheduled)")
                detailColumn("MOVEMENT", value: "\(model.currentSummary.trainingDays) of \(model.workoutGoalTarget)", previous: "\(model.previousSummary.trainingDays) of \(model.workoutGoalTarget)")
                detailColumn("INTAKE", value: "\(Int((model.currentSummary.nutritionAverage * 100).rounded()))%", previous: "\(Int((model.previousSummary.nutritionAverage * 100).rounded()))%")
            }
            HStack {
                Text("NOW · \(Int((model.currentSummary.averageBalance * 100).rounded()))%")
                Spacer()
                Text("\(model.previousTitle) · \(Int((model.previousSummary.averageBalance * 100).rounded()))%")
            }.font(KoiTheme.caption).opacity(0.62)
        }
        .padding(KoiTheme.space.s13)
        .background(.ultraThinMaterial.opacity(0.24), in: RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(KoiTheme.onBase.opacity(0.2), lineWidth: 1))
    }

    private var monthGrid: some View {
        VStack(alignment: .leading, spacing: KoiTheme.space.s13) {
            HStack { Text("DAILY BALANCE").font(KoiTheme.section).tracking(1.7); Spacer(); Text("AVG").font(.system(size: 9, design: .monospaced)).opacity(0.55) }
            LazyVGrid(columns: columns, spacing: KoiTheme.space.s8) {
                ForEach(model.weekdayLabels.indices, id: \.self) { index in
                    Text(model.weekdayLabels[index].uppercased()).font(KoiTheme.caption).opacity(0.55).frame(maxWidth: .infinity)
                }
                Color.clear.frame(width: 30, height: 1)
                ForEach(model.monthWeeks) { week in
                    ForEach(week.days.indices, id: \.self) { index in
                        if let day = week.days[index] { dayButton(day) }
                        else { Color.clear.frame(width: 30, height: 31) }
                    }
                    Text(week.average.map { "\(Int(($0 * 100).rounded()))" } ?? "—")
                        .font(.system(size: 10, design: .rounded)).opacity(0.66).frame(maxWidth: .infinity, minHeight: 31)
                        .accessibilityLabel(week.average.map { "Week average \(Int(($0 * 100).rounded())) percent" } ?? "No week data")
                }
            }
            HStack(spacing: 5) {
                Text("LOW").font(.system(size: 9, design: .monospaced)).opacity(0.55)
                ForEach(0..<5) { index in Circle().fill(KoiTheme.onBase.opacity(0.18 + Double(index) * 0.18)).frame(width: 8, height: 8) }
                Text("HIGH").font(.system(size: 9, design: .monospaced)).opacity(0.55)
            }.padding(.top, KoiTheme.space.s5)
        }
    }

    private var weekRow: some View {
        VStack(alignment: .leading, spacing: KoiTheme.space.s13) {
            Text("DAILY BALANCE").font(KoiTheme.section).tracking(1.7)
            HStack(alignment: .top, spacing: 5) { ForEach(model.weekMetrics) { day in dayButton(day) } }
        }
    }

    private func dayButton(_ day: ProgressDayMetric) -> some View {
        let selected = model.focusedDate.map { Calendar.current.isDate($0, inSameDayAs: day.date) } ?? false
        let scoreText = Int((day.balance * 100).rounded())
        return Button { model.select(day.date); KoiHaptics.tap() } label: {
            VStack(spacing: 4) {
                Text("\(day.dayNumber)").font(.system(size: 10, weight: selected ? .semibold : .regular, design: .rounded))
                ZStack {
                    Circle().trim(from: 0, to: 0.75).stroke(KoiTheme.onBase.opacity(0.2), style: StrokeStyle(lineWidth: 1.5, lineCap: .round)).rotationEffect(.degrees(135))
                    Circle().trim(from: 0, to: 0.75 * day.balance).stroke(KoiTheme.onBase.opacity(0.9), style: StrokeStyle(lineWidth: 1.8, lineCap: .round)).rotationEffect(.degrees(135))
                    if selected { Circle().fill(.ultraThinMaterial).frame(width: 24, height: 24) }
                }.frame(width: 28, height: 28).overlay(Circle().stroke(selected ? KoiTheme.onBase.opacity(0.85) : Color.clear, lineWidth: 1))
            }.frame(maxWidth: .infinity, minHeight: 34)
        }
        .buttonStyle(.plain)
        .disabled(day.date > Date.now)
        .accessibilityLabel("\(day.date.formatted(.dateTime.month(.wide).day())), Balance \(scoreText) percent, Habits \(Int((day.habits * 100).rounded())) percent, Intake \(Int((day.nutrition * 100).rounded())) percent, Movement \(Int((day.exercise * 100).rounded())) percent")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func detailColumn(_ title: String, value: String, previous: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.system(size: 9, design: .monospaced)).tracking(0.7).opacity(0.59)
            Text(value).font(KoiTheme.caption).lineLimit(1).minimumScaleFactor(0.65)
            Text("was \(previous)").font(.system(size: 9, design: .monospaced)).opacity(0.55).lineLimit(1).minimumScaleFactor(0.6)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}
