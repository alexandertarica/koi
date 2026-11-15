import SwiftData
import SwiftUI

struct MovementView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.healthProvider) private var healthProvider
    @State private var model = MovementViewModel()
    @State private var showsWorkoutJournal = false
    @State private var stepsExpanded = false
    @State private var recovery: HealthRecoverySnapshot?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: KoiTheme.space.s21) {
                header.modifier(KoiIntroReveal(order: 0))
                hero.modifier(KoiIntroReveal(order: 1))
                if let recovery { readinessCard(recovery).modifier(KoiIntroReveal(order: 2)) }
                stepsSection.modifier(KoiIntroReveal(order: 3))
                statsSection.modifier(KoiIntroReveal(order: 4))
            }
            .padding(.horizontal, KoiTheme.space.s21)
            .padding(.top, KoiTheme.space.s13)
            .padding(.bottom, KoiTheme.space.s55)
        }
        .foregroundStyle(KoiTheme.onBase)
        .onAppear {
            model.load(modelContext)
            if ["workoutJournal", "workout", "workoutMode", "routineBuilder", "run"].contains(KoiLaunch.screen ?? "") || KoiLaunch.tourState == "workout" {
                showsWorkoutJournal = true
            }
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
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center) {
                Image("KoiWordmark").resizable().renderingMode(.template).scaledToFit()
                    .frame(width: 240, height: 28).foregroundStyle(Color(red: 0.91, green: 0.93, blue: 0.95))
                Spacer()
                Button { KoiHaptics.tap(); showsWorkoutJournal = true } label: {
                    Image(systemName: "dumbbell").font(.system(size: 21, weight: .light)).foregroundStyle(Color(red: 0.91, green: 0.93, blue: 0.95))
                        .frame(width: 44, height: 44).contentShape(Circle())
                }.buttonStyle(.plain).accessibilityLabel("Workout journal")
                    .padding(.vertical, -8)
            }
            VStack(alignment: .leading, spacing: 0) {
                Text(Date.now.formatted(.dateTime.weekday(.wide).month(.wide).day()).uppercased())
                    .font(KoiTheme.section).tracking(2.7).foregroundStyle(Color(red: 0.91, green: 0.93, blue: 0.95).opacity(0.88)).padding(.top, 7)
                Text("Movement").font(KoiTheme.title).foregroundStyle(Color(red: 0.91, green: 0.93, blue: 0.95)).padding(.top, 3)
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
                .accessibilityIdentifier("stage.workout.log")
                Text(model.isTrainingDay ? "LOGGED" : "LOG").font(KoiTheme.section).tracking(1.3)
            }.foregroundStyle(KoiTheme.onBase).padding(.trailing, KoiTheme.space.s21).padding(.bottom, 64).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
        }
        .frame(height: 380).padding(.top, -KoiTheme.space.s13)
        .accessibilityElement(children: .contain)
    }

    private var stepsSection: some View {
        VStack(alignment: .leading, spacing: KoiTheme.space.s8) {
            Button { withAnimation(KoiTheme.morph) { stepsExpanded.toggle() } } label: {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("STEPS").font(KoiTheme.section).tracking(1.8)
                    Image(systemName: "chevron.down").font(.system(size: 9, weight: .light)).rotationEffect(.degrees(stepsExpanded ? 180 : 0))
                    Spacer()
                    Text(model.steps.formatted()).font(.custom("RobotoMono-Light", size: 29)).monospacedDigit()
                    Text("/ \(model.stepGoal.formatted()) steps").font(KoiTheme.caption)
                }.foregroundStyle(KoiTheme.onBase).contentShape(Rectangle())
            }.buttonStyle(.plain)
            GeometryReader { proxy in
                let fraction = min(max(Double(model.steps) / Double(max(model.stepGoal, 1)), 0), 1)
                ZStack(alignment: .leading) {
                    Capsule().fill(KoiTheme.onBase.opacity(0.18)).frame(height: 2)
                    Capsule().fill(KoiTheme.onBase.opacity(0.64)).frame(width: proxy.size.width * fraction, height: 2)
                    Circle().fill(.ultraThinMaterial)
                        .overlay(Circle().stroke(KoiTheme.onBase.opacity(0.55), lineWidth: 0.7))
                        .frame(width: 12, height: 12).offset(x: max(0, proxy.size.width * fraction - 6))
                }
                .frame(maxHeight: .infinity)
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 0).onChanged { value in
                    let targetSteps = min(max(value.location.x / max(proxy.size.width, 1), 0), 1) * Double(max(model.stepGoal, 1))
                    model.setSteps(Int((targetSteps / 100).rounded()) * 100)
                })
            }
            .frame(height: 18)
            if stepsExpanded {
                HStack {
                    Text(model.stepSourceLabel.uppercased()).font(KoiTheme.section).tracking(1.8)
                    Spacer()
                    Button { model.changeSteps(by: -1_000) } label: { Image(systemName: "minus").frame(width: 38, height: 38) }
                        .buttonStyle(.plain).background(.ultraThinMaterial.opacity(0.28), in: Circle()).overlay(Circle().stroke(KoiTheme.onBase.opacity(0.25), lineWidth: 1))
                        .accessibilityLabel("Subtract 1,000 steps")
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
                    Button { Task { await model.connectHealth(using: healthProvider) } } label: {
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
                            Image(systemName: "arrow.clockwise").font(.system(size: 14, weight: .light)).frame(width: 34, height: 34)
                        }.buttonStyle(.plain).disabled(model.isRefreshingHealth).accessibilityLabel("Refresh Apple Health")
                    }.opacity(0.8)
                }
            }
        }
    }

    private var statsSection: some View {
        HStack(spacing: 0) {
            stat(value: "\(model.workoutsThisWeek)", title: "WORKOUTS")
            Spacer(minLength: 8)
            stat(value: model.averageSteps.formatted(), title: "AVG STEPS")
            Spacer(minLength: 8)
            stat(value: model.bestDaySteps.formatted(), title: "BEST DAY")
        }
        .padding(.top, KoiTheme.space.s8)
    }

    private func stat(value: String, title: String) -> some View {
        VStack(alignment: .leading, spacing: KoiTheme.space.s5) {
            Text(value).font(.system(size: 21, weight: .medium, design: .rounded)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.72)
            Text(title).font(KoiTheme.caption).tracking(1)
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
            let center = CGPoint(x: 0, y: proxy.size.height / 2)
            let radius = proxy.size.height / 2 - 14
            let progress = min(max(Double(steps) / Double(max(goal, 1)), 0), 1)
            ZStack(alignment: .topLeading) {
                Canvas { context, _ in
                    func point(_ t: Double, _ r: CGFloat) -> CGPoint {
                        let angle = -Double.pi / 2 + Double.pi * t
                        return CGPoint(x: center.x + r * cos(angle), y: center.y + r * sin(angle))
                    }
                    func barPoint(_ degrees: Double) -> CGPoint {
                        let angle = degrees * Double.pi / 180
                        return CGPoint(x: center.x + cos(angle) * (radius - 25), y: center.y + sin(angle) * (radius - 25))
                    }
                    func barDot(_ degrees: Double, opacity: Double) {
                        let p = barPoint(degrees)
                        context.fill(Path(ellipseIn: CGRect(x: p.x - 2, y: p.y - 2, width: 4, height: 4)), with: .color(.white.opacity(opacity)))
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
                        let start = -90 + Double(index) / Double(count) * 180 + 5
                        let span = 180 / Double(count) - 10
                        var track = Path(); track.addArc(center: center, radius: radius - 25, startAngle: .degrees(start), endAngle: .degrees(start + span), clockwise: false)
                        context.stroke(track, with: .color(.white.opacity(0.38)), lineWidth: 4)
                        barDot(start, opacity: 0.38); barDot(start + span, opacity: 0.38)
                        if index < workouts {
                            var fill = Path(); fill.addArc(center: center, radius: radius - 25, startAngle: .degrees(start), endAngle: .degrees(start + span), clockwise: false)
                            context.stroke(fill, with: .color(.white.opacity(0.78)), lineWidth: 4)
                            barDot(start, opacity: 0.78); barDot(start + span, opacity: 0.78)
                        }
                    }
                    if progress > 0 {
                        let bead = point(max(progress, 0.06), radius)
                        let circle = Path(ellipseIn: CGRect(x: bead.x - 10, y: bead.y - 10, width: 20, height: 20))
                        context.fill(circle, with: .radialGradient(Gradient(colors: [.white.opacity(0.36), .white.opacity(0.1), .white.opacity(0.18)]), center: CGPoint(x: bead.x - 3, y: bead.y - 4), startRadius: 0, endRadius: 13))
                        context.stroke(circle, with: .color(.white.opacity(0.74)), lineWidth: 1)
                    }
                }
                let labelAngle = (-Double.pi / 2 + Double.pi * (0.5 / Double(max(workoutGoal, 1)))) * 0.5
                VStack(alignment: .trailing, spacing: 2) {
                    Text("\(workouts) of \(workoutGoal)").font(.custom("RobotoMono-Light", size: 14))
                    Text("WORKOUTS").font(KoiTheme.section).tracking(0.8)
                }.foregroundStyle(KoiTheme.onBase.opacity(0.9)).position(x: (radius - 38) * cos(labelAngle) - 30, y: center.y + (radius - 38) * sin(labelAngle))
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
