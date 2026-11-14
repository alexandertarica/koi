import SwiftData
import SwiftUI

struct MovementView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.healthProvider) private var healthProvider
    @State private var model = MovementViewModel()
    @State private var showsGoals = false
    @State private var showsWorkoutJournal = false
    @State private var recovery: HealthRecoverySnapshot?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: KoiTheme.space.s34) {
                header.modifier(KoiIntroReveal(order: 0))
                hero.modifier(KoiIntroReveal(order: 1))
                if let recovery { readinessCard(recovery).modifier(KoiIntroReveal(order: 2)) }
                stepsSection.modifier(KoiIntroReveal(order: 3))
                statsSection.modifier(KoiIntroReveal(order: 4))
            }
            .padding(.horizontal, KoiTheme.space.s21)
            .padding(.top, KoiTheme.space.s21)
            .padding(.bottom, KoiTheme.space.s55)
        }
        .background(KoiBackground().ignoresSafeArea())
        .foregroundStyle(KoiTheme.onBase)
        .onAppear {
            model.load(modelContext)
            Task {
                await model.refreshHealth(using: healthProvider)
                recovery = try? await healthProvider.recoveryData(for: .now, calendar: .autoupdatingCurrent)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .koiHealthMovementDidChange)) { _ in
            Task {
                await model.refreshHealth(using: healthProvider)
                recovery = try? await healthProvider.recoveryData(for: .now, calendar: .autoupdatingCurrent)
            }
        }
        .sheet(isPresented: $showsGoals) { MovementGoalEditor(model: model).presentationDetents([.medium]) }
        .sheet(isPresented: $showsWorkoutJournal) { WorkoutJournalView(readiness: recovery?.reading).presentationDetents([.large]) }
        .alert("Movement", isPresented: Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.clearError() } })) {
            Button("OK", role: .cancel) { model.clearError() }
        } message: { Text(model.errorMessage ?? "") }
    }

    private func readinessCard(_ recovery: HealthRecoverySnapshot) -> some View {
        VStack(alignment: .leading, spacing: KoiTheme.space.s8) {
            HStack {
                Text("READINESS").font(KoiTheme.section).tracking(1.7)
                Spacer()
                Text(recovery.reading.level.rawValue.uppercased()).font(KoiTheme.caption).tracking(1.2)
            }
            Text(recovery.reading.reasons.joined(separator: " · ")).font(KoiTheme.caption).opacity(0.75)
            if recovery.reading.level == .takeItEasy {
                Text("Koi’s pick: go light today and hold your usual weights.").font(KoiTheme.caption)
            }
        }
        .padding(KoiTheme.space.s13)
        .background(.ultraThinMaterial.opacity(0.2), in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(KoiTheme.onBase.opacity(0.2), lineWidth: 1))
        .accessibilityElement(children: .combine)
    }

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: KoiTheme.space.s5) {
                Text(Date.now.formatted(.dateTime.weekday(.wide).month(.abbreviated).day()).uppercased()).font(KoiTheme.section).tracking(1.6).opacity(0.72)
                Text("Movement").font(KoiTheme.title)
            }
            Spacer()
            HStack(spacing: KoiTheme.space.s8) {
                Button { KoiHaptics.tap(); showsWorkoutJournal = true } label: {
                    Image(systemName: "dumbbell").font(.system(size: 18, weight: .light))
                        .frame(width: 42, height: 42).background(.ultraThinMaterial.opacity(0.4), in: Circle())
                        .overlay(Circle().stroke(KoiTheme.onBase.opacity(0.24), lineWidth: 1))
                }.buttonStyle(.plain).accessibilityLabel("Workout journal")
                Button { KoiHaptics.tap(); showsGoals = true } label: {
                    Image(systemName: "slider.horizontal.3").font(.system(size: 18, weight: .light))
                        .frame(width: 42, height: 42).background(.ultraThinMaterial.opacity(0.45), in: Circle())
                        .overlay(Circle().stroke(KoiTheme.onBase.opacity(0.26), lineWidth: 1))
                }.buttonStyle(.plain).accessibilityLabel("Edit movement goals")
            }
        }
    }

    private var hero: some View {
        ZStack(alignment: .topLeading) {
            MovementDialCanvas(steps: model.steps, goal: model.stepGoal, workouts: model.workoutsThisWeek, workoutGoal: model.weeklyWorkoutGoal)
                .padding(.horizontal, -KoiTheme.space.s21)
            VStack(alignment: .trailing, spacing: -5) {
                Text(model.steps.formatted()).font(.system(size: 63, weight: .regular, design: .rounded)).contentTransition(.numericText())
                Text("STEPS").font(KoiTheme.section).tracking(1.6)
                Text("of \(model.stepGoal.formatted())").font(KoiTheme.caption).opacity(0.8)
            }.frame(maxWidth: .infinity, alignment: .trailing).padding(.trailing, 8).padding(.top, 6)
            VStack(spacing: KoiTheme.space.s5) {
            KoiTickRing(isOn: model.isTrainingDay, action: {
                    if model.isTrainingDay { KoiHaptics.tap() }
                    else { KoiHaptics.ringFill(duration: 0.65, beats: 14) }
                    model.toggleManualTraining()
                }, label: "LOG", what: "workout")
                Text(model.isTrainingDay ? "LOGGED" : "TODAY").font(KoiTheme.section).tracking(1.3)
            }.foregroundStyle(KoiTheme.onBase).padding(.trailing, KoiTheme.space.s21).padding(.bottom, 64).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
        }
        .frame(height: 380).padding(.top, -KoiTheme.space.s13)
        .accessibilityElement(children: .contain)
    }

    private var stepsSection: some View {
        VStack(alignment: .leading, spacing: KoiTheme.space.s13) {
            HStack {
                VStack(alignment: .leading, spacing: KoiTheme.space.s5) {
                    Text(model.stepSourceLabel.uppercased()).font(KoiTheme.section).tracking(1.8)
                    Text("\(model.stepsRemaining.formatted()) to your daily goal").font(KoiTheme.caption).opacity(0.76)
                }
                Spacer()
                Button { model.changeSteps(by: -1_000) } label: { Image(systemName: "minus").frame(width: 38, height: 38) }
                    .buttonStyle(.plain).background(.ultraThinMaterial.opacity(0.28), in: Circle()).overlay(Circle().stroke(KoiTheme.onBase.opacity(0.25), lineWidth: 1))
                    .accessibilityLabel("Subtract 1,000 steps")
                Text(model.steps.formatted()).font(KoiTheme.caption).monospacedDigit().frame(minWidth: 58, alignment: .trailing)
                Button { model.changeSteps(by: 1_000) } label: { Image(systemName: "plus").frame(width: 38, height: 38) }
                    .buttonStyle(.plain).background(.ultraThinMaterial.opacity(0.28), in: Circle()).overlay(Circle().stroke(KoiTheme.onBase.opacity(0.25), lineWidth: 1))
                    .accessibilityLabel("Add 1,000 steps")
            }
            HStack(spacing: KoiTheme.space.s8) {
                Button { model.changeSteps(by: 1_000) } label: { GlassChip(title: "Walk +1,000", symbol: "figure.walk") }.buttonStyle(.plain)
                Button { model.changeSteps(by: 4_000) } label: { GlassChip(title: "Run +4,000", symbol: "figure.run") }.buttonStyle(.plain)
                Spacer(minLength: 0)
            }
            if healthProvider.isAvailable && !model.healthEnabled {
                Button {
                    Task { await model.connectHealth(using: healthProvider) }
                } label: {
                    HStack(spacing: KoiTheme.space.s8) {
                        Image(systemName: "heart.text.square").font(.system(size: 15, weight: .light))
                        Text(model.isRefreshingHealth ? "Connecting to Apple Health" : "Connect Apple Health").font(KoiTheme.caption)
                        Spacer()
                        Image(systemName: "arrow.up.right").font(.system(size: 11, weight: .light)).opacity(0.72)
                    }.foregroundStyle(KoiTheme.onBase.opacity(0.85)).padding(.vertical, KoiTheme.space.s8)
                }.buttonStyle(.plain).disabled(model.isRefreshingHealth)
            } else if model.healthEnabled {
                HStack(spacing: KoiTheme.space.s8) {
                    Image(systemName: "heart.fill").font(.system(size: 13, weight: .light))
                    Text("Apple Health syncs when Koi opens.").font(KoiTheme.caption)
                    Spacer()
                    Button { Task { await model.refreshHealth(using: healthProvider) } } label: {
                        Image(systemName: model.isRefreshingHealth ? "arrow.clockwise" : "arrow.clockwise")
                            .font(.system(size: 14, weight: .light)).frame(width: 34, height: 34)
                    }.buttonStyle(.plain).disabled(model.isRefreshingHealth).accessibilityLabel("Refresh Apple Health")
                }.opacity(0.8)
            }
        }
    }

    private var statsSection: some View {
        HStack(spacing: 0) {
            stat(value: "\(model.workoutsThisWeek)", title: "WORKOUTS", detail: "LAST 7 DAYS")
            Spacer(minLength: 8)
            stat(value: model.averageSteps.formatted(), title: "AVG STEPS", detail: "PER DAY")
            Spacer(minLength: 8)
            stat(value: model.bestDaySteps.formatted(), title: "BEST DAY", detail: "STEPS")
        }
        .padding(.top, KoiTheme.space.s8)
    }

    private func stat(value: String, title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: KoiTheme.space.s5) {
            Text(value).font(.system(size: 21, weight: .medium, design: .rounded)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.72)
            Text(title).font(KoiTheme.caption).tracking(1)
            Text(detail).font(KoiTheme.caption).opacity(0.68)
        }
    }
}

private struct MovementDialCanvas: View {
    let steps: Int
    let goal: Int
    let workouts: Int
    let workoutGoal: Int

    var body: some View {
        GeometryReader { proxy in
            let center = CGPoint(x: proxy.size.width * 0.14, y: proxy.size.height / 2)
            let radius = proxy.size.height / 2 - 14
            let progress = min(max(Double(steps) / Double(max(goal, 1)), 0), 1)
            ZStack(alignment: .topLeading) {
                Canvas { context, _ in
                    func point(_ t: Double, _ r: CGFloat) -> CGPoint {
                        let angle = -Double.pi / 2 + Double.pi * t
                        return CGPoint(x: center.x + r * cos(angle), y: center.y + r * sin(angle))
                    }
                    for tick in 0...72 {
                        let t = Double(tick) / 72
                        let angle = -Double.pi / 2 + Double.pi * t
                        let length: CGFloat = tick.isMultiple(of: 5) ? 14 : 8
                        var mark = Path(); mark.move(to: point(t, radius + 18)); mark.addLine(to: CGPoint(x: center.x + cos(angle) * (radius + 18 + length), y: center.y + sin(angle) * (radius + 18 + length)))
                        context.stroke(mark, with: .color(.white.opacity(t <= progress ? 0.86 : 0.5)), style: StrokeStyle(lineWidth: tick.isMultiple(of: 5) ? 1.8 : 1, lineCap: .round))
                    }
                    for index in 0..<90 {
                        let a = Double(index) / 90, b = Double(index + 1) / 90
                        var arc = Path(); arc.addArc(center: center, radius: radius, startAngle: .degrees(-90 + a * 180), endAngle: .degrees(-90 + b * 180), clockwise: false)
                        let edge = max(0.3, min(a / 0.28, (1 - a) / 0.22, 1))
                        context.stroke(arc, with: .color(.white.opacity((b <= progress ? 0.9 : 0.55) * edge)), lineWidth: b <= progress ? 1.6 : 1.1)
                    }
                    let count = min(max(workoutGoal, 1), 7)
                    for index in 0..<count {
                        let start = Double(index) / Double(count)
                        var track = Path(); track.addArc(center: center, radius: radius - 25, startAngle: .degrees(-90 + start * 180), endAngle: .degrees(-90 + (start + 1 / Double(count)) * 180), clockwise: false)
                        context.stroke(track, with: .color(.white.opacity(0.38)), lineWidth: 4)
                        if index < workouts {
                            var fill = Path(); fill.addArc(center: center, radius: radius - 25, startAngle: .degrees(-90 + start * 180), endAngle: .degrees(-90 + (start + 0.92 / Double(count)) * 180), clockwise: false)
                            context.stroke(fill, with: .color(.white.opacity(0.78)), lineWidth: 4)
                        }
                    }
                    if progress > 0 {
                        let bead = point(max(progress, 0.06), radius)
                        let circle = Path(ellipseIn: CGRect(x: bead.x - 10, y: bead.y - 10, width: 20, height: 20))
                        context.fill(circle, with: .radialGradient(Gradient(colors: [.white.opacity(0.36), .white.opacity(0.1), .white.opacity(0.18)]), center: CGPoint(x: bead.x - 3, y: bead.y - 4), startRadius: 0, endRadius: 13))
                        context.stroke(circle, with: .color(.white.opacity(0.74)), lineWidth: 1)
                    }
                }
                VStack(alignment: .trailing, spacing: 2) {
                    Text("\(workouts) / \(workoutGoal)").font(.custom("RobotoMono-Light", size: 14))
                    Text("WORKOUTS").font(KoiTheme.section).tracking(0.8)
                }.foregroundStyle(KoiTheme.onBase.opacity(0.9)).position(x: center.x + radius * 0.28 - 52, y: center.y)
            }
        }
    }
}

private struct MovementGoalEditor: View {
    @Environment(\.dismiss) private var dismiss
    @State private var steps: String
    @State private var workouts: String
    let model: MovementViewModel

    init(model: MovementViewModel) {
        self.model = model
        _steps = State(initialValue: String(model.stepGoal))
        _workouts = State(initialValue: String(model.weeklyWorkoutGoal))
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: KoiTheme.space.s21) {
                Text("Set a steady goal.").font(KoiTheme.title)
                goalField("Daily steps", value: $steps, unit: "steps")
                goalField("Workouts each week", value: $workouts, unit: "days")
                KoiPrimaryButton(title: "Save goals") {
                    if let steps = Int(steps) { model.setStepGoal(steps) }
                    if let workouts = Int(workouts) { model.setWeeklyWorkoutGoal(workouts) }
                    dismiss()
                }
                Text("Steps stay gentle. A walk counts.").font(KoiTheme.caption).opacity(0.75)
                Spacer()
            }.padding(KoiTheme.space.s21).background(KoiBackground().ignoresSafeArea()).foregroundStyle(KoiTheme.onBase)
                .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() }.font(KoiTheme.caption) } }
        }.preferredColorScheme(.dark)
    }

    private func goalField(_ title: String, value: Binding<String>, unit: String) -> some View {
        HStack {
            Text(title).font(KoiTheme.body)
            Spacer()
            TextField("", text: value).keyboardType(.numberPad).multilineTextAlignment(.trailing).font(KoiTheme.body).frame(width: 100)
            Text(unit).font(KoiTheme.caption).opacity(0.72)
        }.padding(.vertical, KoiTheme.space.s8)
    }
}
