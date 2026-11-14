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
                header
                if let recovery { readinessCard(recovery) }
                hero
                stepsSection
                statsSection
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
                Text("MOVEMENT").font(KoiTheme.section).tracking(2.4)
                Text("Find your pace.").font(KoiTheme.title)
            }
            Spacer()
            HStack(spacing: KoiTheme.space.s8) {
                Button { showsWorkoutJournal = true } label: {
                    Image(systemName: "dumbbell").font(.system(size: 18, weight: .light))
                        .frame(width: 42, height: 42).background(.ultraThinMaterial.opacity(0.4), in: Circle())
                        .overlay(Circle().stroke(KoiTheme.onBase.opacity(0.24), lineWidth: 1))
                }.buttonStyle(.plain).accessibilityLabel("Workout journal")
                Button { showsGoals = true } label: {
                    Image(systemName: "slider.horizontal.3").font(.system(size: 18, weight: .light))
                        .frame(width: 42, height: 42).background(.ultraThinMaterial.opacity(0.45), in: Circle())
                        .overlay(Circle().stroke(KoiTheme.onBase.opacity(0.26), lineWidth: 1))
                }.buttonStyle(.plain).accessibilityLabel("Movement goals")
            }
        }
    }

    private var hero: some View {
        VStack(spacing: KoiTheme.space.s21) {
            ZStack {
                MovementStepArc(progress: 1)
                    .stroke(KoiTheme.onBase.opacity(0.22), style: StrokeStyle(lineWidth: 11, lineCap: .round))
                MovementStepArc(progress: model.stepScore)
                    .stroke(KoiTheme.onBase.opacity(0.88), style: StrokeStyle(lineWidth: 11, lineCap: .round))
                VStack(spacing: KoiTheme.space.s5) {
                    Text(model.steps.formatted()).font(KoiTheme.hero).contentTransition(.numericText())
                    Text("OF \(model.stepGoal.formatted()) STEPS").font(KoiTheme.caption).tracking(1.5).opacity(0.78)
                }.offset(y: 17)
            }
            .frame(height: 190)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(model.steps) of \(model.stepGoal) steps")

            VStack(spacing: KoiTheme.space.s8) {
                HStack { Text("THIS WEEK").font(KoiTheme.caption).tracking(1.6); Spacer(); Text("\(model.workoutsThisWeek) OF \(model.weeklyWorkoutGoal) WORKOUTS").font(KoiTheme.caption).opacity(0.8) }
                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule().fill(KoiTheme.onBase.opacity(0.2))
                        Capsule().fill(KoiTheme.onBase.opacity(0.84)).frame(width: proxy.size.width * min(Double(model.workoutsThisWeek) / Double(max(model.weeklyWorkoutGoal, 1)), 1))
                    }
                }.frame(height: 2)
                HStack(spacing: 0) {
                    ForEach(model.week) { day in
                        VStack(spacing: KoiTheme.space.s5) {
                            Capsule().fill(day.didTrain ? KoiTheme.onBase.opacity(0.9) : KoiTheme.onBase.opacity(0.22))
                                .frame(width: day.didTrain ? 9 : 5, height: day.didTrain ? 9 : 5)
                                .frame(height: 9)
                            Text(day.dayLetter).font(KoiTheme.caption).opacity(0.68)
                        }.frame(maxWidth: .infinity)
                    }
                }.padding(.top, KoiTheme.space.s5)
            }

            HStack {
                Text("EXERCISE BALANCE").font(KoiTheme.caption).tracking(1.4)
                Spacer()
                Text("\(Int((model.exerciseScore * 100).rounded()))%").font(KoiTheme.caption).monospacedDigit()
            }.opacity(0.82)

            KoiPrimaryButton(title: model.isTrainingDay ? "Trained today" : "Log trained") {
                withAnimation(.spring(response: 0.36, dampingFraction: 0.82)) { model.toggleManualTraining() }
            }
        }
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

private struct MovementStepArc: Shape {
    var progress: Double
    func path(in rect: CGRect) -> Path {
        let radius = min(rect.width, rect.height) * 0.44
        let center = CGPoint(x: rect.midX, y: rect.midY + 8)
        var path = Path()
        path.addArc(center: center, radius: radius, startAngle: .degrees(205), endAngle: .degrees(335), clockwise: false)
        return path.trimmedPath(from: 0, to: min(max(progress, 0), 1))
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
