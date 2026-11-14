import SwiftData
import SwiftUI
import KoiShared

struct WorkoutJournalView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var model = WorkoutViewModel()
    @State private var showsRoutineBuilder = false
    @State private var editingRoutine: KoiWorkoutRoutine?
    @State private var showsWorkoutMode = false
    @State private var summary: WorkoutCompletionSummary?
    @State private var journalTab = "Strength"

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: KoiTheme.space.s34) {
                    header
                    if journalTab == "Strength" {
                        strengthJournal
                    } else {
                        cardioPreview
                    }
                }
                .padding(.horizontal, KoiTheme.space.s21)
                .padding(.top, KoiTheme.space.s21)
                .padding(.bottom, KoiTheme.space.s55)
            }
            .background(KoiBackground().ignoresSafeArea())
            .foregroundStyle(KoiTheme.onBase)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() }.font(KoiTheme.caption) } }
        }
        .preferredColorScheme(.dark)
        .onAppear { model.load(modelContext) }
        .onChange(of: model.activeSession?.id) { _, sessionID in if sessionID != nil { showsWorkoutMode = true } }
        .sheet(isPresented: $showsRoutineBuilder) {
            WorkoutRoutineBuilder(model: model, existing: editingRoutine)
                .presentationDetents([.large])
                .onDisappear { editingRoutine = nil }
        }
        .fullScreenCover(isPresented: $showsWorkoutMode) {
            WorkoutModeView(model: model) { result in
                summary = result
                showsWorkoutMode = false
            }
        }
        .sheet(item: $summary) { result in
            WorkoutSummarySheet(summary: result) {
                model.saveAsRoutine(result)
                summary = nil
            }.presentationDetents([.medium, .large])
        }
        .alert("Workout journal", isPresented: Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.clearError() } })) {
            Button("OK", role: .cancel) { model.clearError() }
        } message: { Text(model.errorMessage ?? "") }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: KoiTheme.space.s21) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: KoiTheme.space.s5) {
                    Text("WORKOUT JOURNAL").font(KoiTheme.section).tracking(2.4)
                    Text("Move with intention.").font(KoiTheme.title)
                }
                Spacer()
                Button { showsRoutineBuilder = true } label: {
                    Image(systemName: "plus").font(.system(size: 18, weight: .light))
                        .frame(width: 42, height: 42).background(.ultraThinMaterial.opacity(0.38), in: Circle())
                        .overlay(Circle().stroke(KoiTheme.onBase.opacity(0.25), lineWidth: 1))
                }.buttonStyle(.plain).accessibilityLabel("Build a routine")
            }
            HStack(spacing: KoiTheme.space.s8) {
                journalTabButton("Strength")
                journalTabButton("Cardio")
                Spacer()
            }
        }
    }

    private var strengthJournal: some View {
        VStack(alignment: .leading, spacing: KoiTheme.space.s34) {
            pickSection
            startTiles
            if !model.plannedRoutines.isEmpty { plannedSection }
            if !model.routinesByName.isEmpty { routinesSection }
            weeklySection
            if !model.liftHistory.isEmpty { liftSection }
            if !model.pastWorkouts.isEmpty { pastSection }
        }
    }

    private var pickSection: some View {
        VStack(alignment: .leading, spacing: KoiTheme.space.s13) {
            Text("TODAY").font(KoiTheme.section).tracking(2)
            if let activeSession = model.activeSession {
                VStack(alignment: .leading, spacing: KoiTheme.space.s13) {
                    Text("A session is in progress.").font(KoiTheme.body)
                    Text(activeSession.name).font(KoiTheme.title)
                    KoiPrimaryButton(title: "Resume workout") { showsWorkoutMode = true }
                }
            } else {
                VStack(alignment: .leading, spacing: KoiTheme.space.s8) {
                    HStack(spacing: KoiTheme.space.s8) {
                        Image(systemName: model.recommendation.suggestsRest ? "moon" : "sparkle").font(.system(size: 14, weight: .light))
                        Text(model.recommendation.suggestsRest ? "A lighter day" : "KOI'S PICK").font(KoiTheme.caption).tracking(1.6)
                    }.opacity(0.78)
                    Text(model.recommendation.suggestsRest ? "Rest or take it light." : (model.recommendation.routine?.name ?? "\(model.recommendation.group.capitalized) day"))
                        .font(KoiTheme.title)
                    Text(model.recommendation.reason).font(KoiTheme.caption).opacity(0.75)
                }
                HStack(spacing: KoiTheme.space.s8) {
                    KoiPrimaryButton(title: model.recommendation.suggestsRest ? "Go light" : "Start") {
                        model.startRecommendedWorkout()
                        showsWorkoutMode = true
                    }
                    if let recent = model.pastWorkouts.first {
                        Button("Go again") { model.repeatWorkout(recent); showsWorkoutMode = true }
                            .font(KoiTheme.caption).padding(.horizontal, KoiTheme.space.s13).frame(minHeight: 54)
                            .overlay(Capsule().stroke(KoiTheme.onBase.opacity(0.3), lineWidth: 1)).buttonStyle(.plain)
                    }
                }
                if model.canLogAlreadyDid {
                    Button("Already did it") { model.logAlreadyDid(); summary = model.completionSummary }
                        .font(KoiTheme.caption).padding(.leading, KoiTheme.space.s13).buttonStyle(.plain)
                }
            }
        }
    }

    private var startTiles: some View {
        HStack(spacing: KoiTheme.space.s8) {
            journalTile("Just go", hint: "Start empty", symbol: "figure.strengthtraining.traditional") {
                model.startEmptyWorkout(); showsWorkoutMode = true
            }
            journalTile("Build", hint: "Make a plan", symbol: "square.and.pencil") {
                editingRoutine = nil; showsRoutineBuilder = true
            }
            Menu {
                Button("Push day") { model.startPreset("push"); showsWorkoutMode = true }
                Button("Pull day") { model.startPreset("pull"); showsWorkoutMode = true }
                Button("Leg day") { model.startPreset("legs"); showsWorkoutMode = true }
                Button("Core day") { model.startPreset("core"); showsWorkoutMode = true }
            } label: { journalTileLabel("Koi presets", hint: "A starting point", symbol: "water.waves") }
            .buttonStyle(.plain)
        }
    }

    private var plannedSection: some View {
        VStack(alignment: .leading, spacing: KoiTheme.space.s13) {
            Text("PLANNED").font(KoiTheme.section).tracking(2)
            ForEach(model.plannedRoutines) { routine in
                Button { model.startRoutine(routine); showsWorkoutMode = true } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(routine.name).font(KoiTheme.body)
                            Text(routine.plannedAt?.formatted(.dateTime.weekday(.wide).month(.abbreviated).day()) ?? "Planned").font(KoiTheme.caption).opacity(0.7)
                        }
                        Spacer()
                        Image(systemName: "arrow.right").font(.system(size: 13, weight: .light))
                    }.padding(.vertical, KoiTheme.space.s8).contentShape(Rectangle())
                }.buttonStyle(.plain)
            }
        }
    }

    private var routinesSection: some View {
        VStack(alignment: .leading, spacing: KoiTheme.space.s13) {
            Text("YOUR ROUTINES").font(KoiTheme.section).tracking(2)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: KoiTheme.space.s8) {
                    ForEach(model.routinesByName) { routine in
                        Button { model.startRoutine(routine); showsWorkoutMode = true } label: {
                            GlassChip(title: routine.name, symbol: "play.fill")
                        }.buttonStyle(.plain)
                            .contextMenu {
                                Button("Edit") { editingRoutine = routine; showsRoutineBuilder = true }
                                Button("Delete", role: .destructive) { model.deleteRoutine(routine) }
                            }
                    }
                }
            }
        }
    }

    private var weeklySection: some View {
        VStack(alignment: .leading, spacing: KoiTheme.space.s13) {
            Text("THIS WEEK").font(KoiTheme.section).tracking(2)
            HStack(alignment: .firstTextBaseline, spacing: KoiTheme.space.s21) {
                journalStat("\(model.journalStats.workouts)", label: "WORKOUTS")
                journalStat("\(model.journalStats.sets)", label: "SETS")
                journalStat(model.journalStats.volumeLB.formatted(), label: "LB MOVED")
            }
        }
    }

    private var liftSection: some View {
        VStack(alignment: .leading, spacing: KoiTheme.space.s13) {
            Text("YOUR LIFTS").font(KoiTheme.section).tracking(2)
            ForEach(model.liftHistory) { lift in
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(lift.name).font(KoiTheme.body)
                        Text("\(lift.group.capitalized) · Last \(lift.lastSession)").font(KoiTheme.caption).opacity(0.7)
                    }
                    Spacer()
                    Text(lift.best).font(KoiTheme.caption).opacity(0.8)
                }.padding(.vertical, KoiTheme.space.s8)
                if lift.id != model.liftHistory.last?.id { Rectangle().fill(KoiTheme.divider).frame(height: 0.5) }
            }
        }
    }

    private var pastSection: some View {
        VStack(alignment: .leading, spacing: KoiTheme.space.s13) {
            Text("PAST WORKOUTS").font(KoiTheme.section).tracking(2)
            ForEach(model.pastWorkouts) { workout in
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(workout.name).font(KoiTheme.body)
                        Text(workout.startedAt.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())).font(KoiTheme.caption).opacity(0.7)
                    }
                    Spacer()
                    Button("Repeat") { model.repeatWorkout(workout); showsWorkoutMode = true }.font(KoiTheme.caption).buttonStyle(.plain)
                }.padding(.vertical, KoiTheme.space.s8)
            }
        }
    }

    private var cardioPreview: some View {
        VStack(alignment: .leading, spacing: KoiTheme.space.s13) {
            Text("A steady pace, your way.").font(KoiTheme.title)
            Text("Run, class, and distance sessions will live here.").font(KoiTheme.caption).opacity(0.78)
        }.padding(.top, KoiTheme.space.s34)
    }

    private func journalTabButton(_ title: String) -> some View {
        Button { journalTab = title } label: {
            Text(title.uppercased()).font(KoiTheme.caption).tracking(1.5)
                .padding(.horizontal, KoiTheme.space.s13).padding(.vertical, KoiTheme.space.s8)
                .background(journalTab == title ? KoiTheme.onBase.opacity(0.17) : .clear, in: Capsule())
                .overlay(Capsule().stroke(KoiTheme.onBase.opacity(0.27), lineWidth: 1))
        }.buttonStyle(.plain)
    }

    private func journalTile(_ title: String, hint: String, symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { journalTileLabel(title, hint: hint, symbol: symbol) }.buttonStyle(.plain)
    }

    private func journalTileLabel(_ title: String, hint: String, symbol: String) -> some View {
        VStack(alignment: .leading, spacing: KoiTheme.space.s8) {
            Image(systemName: symbol).font(.system(size: 20, weight: .light))
            Text(title).font(KoiTheme.caption)
            Text(hint).font(KoiTheme.caption).opacity(0.7).lineLimit(1).minimumScaleFactor(0.75)
        }.foregroundStyle(KoiTheme.onBase).frame(maxWidth: .infinity, minHeight: 82, alignment: .leading).padding(KoiTheme.space.s8)
            .background(.ultraThinMaterial.opacity(0.22), in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(KoiTheme.onBase.opacity(0.22), lineWidth: 1))
    }

    private func journalStat(_ value: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: KoiTheme.space.s5) {
            Text(value).font(.system(size: 23, weight: .medium, design: .rounded)).monospacedDigit()
            Text(label).font(KoiTheme.caption).tracking(0.8)
        }
    }
}

private struct WorkoutRoutineBuilder: View {
    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var lifts: [String]
    @State private var nextLift = ""
    @State private var sets = "3"
    @State private var reps = "8"
    @State private var plannedDate: Date
    @State private var when = "Any time"
    @State private var choosesDate = false
    let model: WorkoutViewModel
    let existing: KoiWorkoutRoutine?

    init(model: WorkoutViewModel, existing: KoiWorkoutRoutine?) {
        self.model = model
        self.existing = existing
        _name = State(initialValue: existing?.name ?? "New routine")
        _lifts = State(initialValue: existing.map { model.routineLiftNames($0) } ?? [])
        _plannedDate = State(initialValue: existing?.plannedAt ?? .now)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: KoiTheme.space.s21) {
                    Text(existing == nil ? "Build a routine." : "Shape this routine.").font(KoiTheme.title)
                    TextField("Routine name", text: $name).font(KoiTheme.body).padding(13).background(.ultraThinMaterial.opacity(0.22), in: RoundedRectangle(cornerRadius: 14))
                    VStack(alignment: .leading, spacing: KoiTheme.space.s8) {
                        Text("LIFTS").font(KoiTheme.section).tracking(1.7)
                        ForEach(lifts.indices, id: \.self) { index in
                            HStack(spacing: KoiTheme.space.s8) {
                                TextField("Lift", text: $lifts[index]).font(KoiTheme.body)
                                Text(WorkoutNameRules.guessGroup(lifts[index]).capitalized).font(KoiTheme.caption).opacity(0.7)
                                Button { lifts.remove(at: index) } label: { Image(systemName: "minus.circle").font(.system(size: 16, weight: .light)) }.buttonStyle(.plain).accessibilityLabel("Remove lift")
                            }.padding(.vertical, KoiTheme.space.s5)
                        }
                        HStack {
                            TextField("Add a lift", text: $nextLift).font(KoiTheme.body)
                            Button { addLift(nextLift) } label: { Image(systemName: "plus.circle").font(.system(size: 18, weight: .light)) }.buttonStyle(.plain).accessibilityLabel("Add lift")
                        }.padding(.vertical, KoiTheme.space.s8)
                        Menu("Suggestions") {
                            ForEach(suggestedLifts, id: \.self) { lift in Button(lift) { addLift(lift) } }
                        }.font(KoiTheme.caption).buttonStyle(.plain)
                    }
                    HStack(spacing: KoiTheme.space.s13) {
                        goalField("Sets", text: $sets)
                        Text("×").font(KoiTheme.body).opacity(0.8)
                        goalField("Target reps", text: $reps)
                    }
                    VStack(alignment: .leading, spacing: KoiTheme.space.s8) {
                        Text("WHEN").font(KoiTheme.section).tracking(1.7)
                        HStack(spacing: KoiTheme.space.s8) {
                            ForEach(["Any time", "Today", "Tomorrow", "Choose day"], id: \.self) { option in
                                Button(option) { when = option; choosesDate = option == "Choose day" }
                                    .font(KoiTheme.caption).padding(.horizontal, 10).padding(.vertical, 7)
                                    .background(when == option ? KoiTheme.onBase.opacity(0.18) : .clear, in: Capsule())
                                    .overlay(Capsule().stroke(KoiTheme.onBase.opacity(0.22), lineWidth: 1)).buttonStyle(.plain)
                            }
                        }
                        if choosesDate { DatePicker("Planned day", selection: $plannedDate, in: .now..., displayedComponents: .date).datePickerStyle(.compact).font(KoiTheme.caption).tint(KoiTheme.onBase) }
                    }
                    KoiPrimaryButton(title: "Start now") {
                        model.saveRoutine(existing: existing, name: name, liftNames: lifts, plannedAt: selectedPlannedDate, startNow: true, targetSets: Int(sets) ?? 3, targetReps: Int(reps) ?? 8)
                        dismiss()
                    }
                    Button("Save for later") {
                        model.saveRoutine(existing: existing, name: name, liftNames: lifts, plannedAt: selectedPlannedDate, startNow: false, targetSets: Int(sets) ?? 3, targetReps: Int(reps) ?? 8)
                        dismiss()
                    }.font(KoiTheme.caption).frame(maxWidth: .infinity).buttonStyle(.plain)
                }.padding(KoiTheme.space.s21)
            }
            .background(KoiBackground().ignoresSafeArea()).foregroundStyle(KoiTheme.onBase)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Close") { dismiss() }.font(KoiTheme.caption) } }
        }.preferredColorScheme(.dark)
    }

    private var selectedPlannedDate: Date? {
        switch when {
        case "Today": Calendar.current.startOfDay(for: .now)
        case "Tomorrow": Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: .now))
        case "Choose day": Calendar.current.startOfDay(for: plannedDate)
        default: nil
        }
    }
    private var suggestedLifts: [String] {
        switch WorkoutNameRules.guessRoutineGroup(name) {
        case "pull": ["Lat pulldown", "Seated row", "Dumbbell curl"]
        case "legs", "lower": ["Goblet squat", "Romanian deadlift", "Leg press"]
        case "core": ["Plank", "Dead bug", "Pallof press"]
        default: ["Bench press", "Shoulder press", "Triceps pushdown"]
        }
    }
    private func goalField(_ title: String, text: Binding<String>) -> some View {
        HStack { Text(title).font(KoiTheme.caption); TextField("", text: text).keyboardType(.numberPad).multilineTextAlignment(.trailing).font(KoiTheme.body).frame(width: 44) }
            .padding(KoiTheme.space.s8).background(.ultraThinMaterial.opacity(0.2), in: RoundedRectangle(cornerRadius: 12))
    }
    private func addLift(_ value: String) {
        let clean = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }
        lifts.append(clean); nextLift = ""
    }
}

private struct WorkoutModeView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var nextLift = ""
    let model: WorkoutViewModel
    let onFinish: (WorkoutCompletionSummary?) -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: KoiTheme.space.s21) {
                    header
                    liftPicker
                    if let lift = model.currentLift {
                        currentSet(for: lift)
                        setHistory
                    } else {
                        emptyWorkout
                    }
                    finishButton
                }.padding(.horizontal, KoiTheme.space.s21).padding(.top, KoiTheme.space.s21).padding(.bottom, KoiTheme.space.s55)
            }
            .background(KoiBackground(isDoingScreen: true).ignoresSafeArea())
            .foregroundStyle(KoiTheme.onBase)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Close") { dismiss() }.font(KoiTheme.caption) } }
        }
        .preferredColorScheme(.dark)
        .alert("Workout", isPresented: Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.clearError() } })) {
            Button("OK", role: .cancel) { model.clearError() }
        } message: { Text(model.errorMessage ?? "") }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: KoiTheme.space.s5) {
                Text("KOI").font(KoiTheme.section).tracking(2.4)
                Text(model.activeSession?.name ?? "Workout").font(KoiTheme.title)
            }
            Spacer()
            TimelineView(.periodic(from: .now, by: 1)) { context in
                Text(durationText(from: model.activeSession?.startedAt ?? context.date, now: context.date))
                    .font(KoiTheme.caption).monospacedDigit().opacity(0.85)
            }
        }
    }

    private var liftPicker: some View {
        VStack(alignment: .leading, spacing: KoiTheme.space.s13) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: KoiTheme.space.s8) {
                    ForEach(model.activeLifts) { lift in
                        Button { model.selectLift(lift.id) } label: {
                            GlassChip(title: lift.name, symbol: model.setCount(for: lift) >= lift.targetSets ? "checkmark" : nil, isOn: model.currentLift?.id == lift.id)
                        }.buttonStyle(.plain)
                            .contextMenu {
                                Button("Remove lift", role: .destructive) { model.removeLift(lift) }
                            }
                    }
                }
            }
            HStack(spacing: KoiTheme.space.s8) {
                TextField("Add a lift", text: $nextLift).font(KoiTheme.body).padding(.vertical, KoiTheme.space.s8)
                Button { model.addLift(name: nextLift); nextLift = "" } label: { Image(systemName: "plus.circle").font(.system(size: 20, weight: .light)) }.buttonStyle(.plain).accessibilityLabel("Add lift")
                Menu("Up next") { ForEach(model.suggestedNextLifts, id: \.self) { name in Button(name) { model.addLift(name: name) } } }.font(KoiTheme.caption).buttonStyle(.plain)
            }.overlay(alignment: .bottom) { Rectangle().fill(KoiTheme.divider).frame(height: 0.5) }
        }
    }

    private func currentSet(for lift: KoiWorkoutLift) -> some View {
        VStack(alignment: .leading, spacing: KoiTheme.space.s21) {
            VStack(alignment: .leading, spacing: KoiTheme.space.s8) {
                Menu {
                    ForEach(["push", "pull", "legs", "core", "upper", "lower", "full body"], id: \.self) { group in
                        Button(group.capitalized) { model.changeMuscleGroup(of: lift, to: group) }
                    }
                } label: {
                    Label(lift.muscleGroup.uppercased(), systemImage: "chevron.down").font(KoiTheme.section).tracking(1.7).opacity(0.75)
                }.buttonStyle(.plain).accessibilityLabel("Change muscle group, currently \(lift.muscleGroup)")
                Text(lift.name).font(KoiTheme.title)
                HStack(spacing: KoiTheme.space.s8) {
                    ForEach(0..<min(lift.targetSets, 8), id: \.self) { index in
                        Circle().fill(index < model.setCount(for: lift) ? KoiTheme.onBase : KoiTheme.onBase.opacity(0.27)).frame(width: 8, height: 8)
                    }
                    Text("SET \(model.setCount(for: lift) + 1) OF \(lift.targetSets)").font(KoiTheme.caption).tracking(1.1).opacity(0.75)
                }
            }

            if !model.lastContext.isEmpty {
                Button { model.applyProgression() } label: {
                    HStack(spacing: KoiTheme.space.s8) { Image(systemName: "arrow.up.right"); Text(model.lastContext).lineLimit(2) }.font(KoiTheme.caption).frame(maxWidth: .infinity, alignment: .leading).padding(KoiTheme.space.s13).overlay(RoundedRectangle(cornerRadius: 14).stroke(KoiTheme.onBase.opacity(0.25), lineWidth: 1))
                }.buttonStyle(.plain)
            }

            HStack(alignment: .center, spacing: KoiTheme.space.s21) {
                valueControl(title: "WEIGHT", value: model.isCurrentLiftBodyweight ? "BW" : formatWeight(model.currentWeight), unit: "LB", minus: { model.changeWeight(by: model.currentWeight < 50 ? -2.5 : -5) }, plus: { model.changeWeight(by: model.currentWeight < 50 ? 2.5 : 5) }) {
                    if !model.isCurrentLiftBodyweight {
                        TextField("45", value: Binding(get: { model.currentWeight }, set: { model.setWeight($0) }), format: .number).keyboardType(.decimalPad).multilineTextAlignment(.center).font(.system(size: 40, weight: .semibold, design: .rounded)).frame(width: 112)
                    }
                }
                Text("×").font(.system(size: 30, weight: .light)).opacity(0.72)
                valueControl(title: "REPS", value: "\(model.currentReps)", unit: "REPS", minus: { model.changeReps(by: -1) }, plus: { model.changeReps(by: 1) }) {
                    TextField("8", value: Binding(get: { model.currentReps }, set: { model.setReps($0) }), format: .number).keyboardType(.numberPad).multilineTextAlignment(.center).font(.system(size: 40, weight: .semibold, design: .rounded)).frame(width: 74)
                }
            }
            if model.isNewBest { GlassChip(title: "New best", symbol: "sparkle", isOn: true) }
            if model.isResting {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    let remaining = max(Int(ceil((model.activeSession?.restUntil ?? context.date).timeIntervalSince(context.date))), 0)
                    Button { model.skipRest() } label: {
                        HStack { Text("REST").font(KoiTheme.caption).tracking(2); Spacer(); Text(timeString(remaining)).font(KoiTheme.title).monospacedDigit(); Image(systemName: "forward.end.fill").font(.system(size: 13)) }
                            .padding(KoiTheme.space.s13).background(.ultraThinMaterial.opacity(0.35), in: Capsule()).overlay(Capsule().stroke(KoiTheme.onBase.opacity(0.32), lineWidth: 1))
                    }.buttonStyle(.plain).onLongPressGesture { model.addRestSeconds(15) }.accessibilityLabel("Rest \(timeString(remaining)). Tap to skip. Hold to add 15 seconds.")
                }
            } else {
                KoiPrimaryButton(title: model.isEditingSet ? "Save set" : "Log set") { model.logSet() }
            }
            HStack {
                Button("Warm-up set") { model.logSet(isWarmUp: true) }.font(KoiTheme.caption).buttonStyle(.plain)
                Spacer()
                if let lift = model.currentLift {
                    Menu("Rest · \(lift.restSeconds / 60):\(String(format: "%02d", lift.restSeconds % 60))") {
                        ForEach([45, 60, 90, 120, 180], id: \.self) { seconds in
                            Button("\(seconds) seconds") { model.changeRestLength(seconds) }
                        }
                    }.font(KoiTheme.caption).buttonStyle(.plain)
                }
            }
        }
    }

    private var setHistory: some View {
        VStack(alignment: .leading, spacing: KoiTheme.space.s8) {
            Text("TODAY'S SETS").font(KoiTheme.section).tracking(1.7)
            if model.currentSets.isEmpty { Text("Your sets will settle here.").font(KoiTheme.caption).opacity(0.72) }
            else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: KoiTheme.space.s8) {
                        ForEach(model.currentSets) { set in
                            Button { model.selectSetForEditing(set) } label: {
                                GlassChip(title: set.isBodyweight ? "BW × \(set.reps)" : "\(formatWeight(set.weightLB)) × \(set.reps)", symbol: set.isWarmUp ? "sun.max" : nil, isOn: model.editingSetID == set.id)
                            }.buttonStyle(.plain).contextMenu {
                                Button(set.isWarmUp ? "Mark working set" : "Mark warm-up") { model.setWarmUp(set, value: !set.isWarmUp) }
                                Button("Delete set", role: .destructive) { model.deleteSet(set) }
                            }
                        }
                    }
                }
            }
        }.padding(.top, KoiTheme.space.s8)
    }

    private var emptyWorkout: some View {
        VStack(alignment: .leading, spacing: KoiTheme.space.s13) {
            Text("Add a lift when you're ready.").font(KoiTheme.body)
            Text("Your session saves as you go.").font(KoiTheme.caption).opacity(0.72)
        }.padding(.vertical, KoiTheme.space.s21)
    }

    private var finishButton: some View {
        Button {
            onFinish(model.endSession())
        } label: {
            Text("Finish workout").font(KoiTheme.caption).tracking(1.2).frame(maxWidth: .infinity).padding(.vertical, KoiTheme.space.s13)
                .overlay(Capsule().stroke(KoiTheme.onBase.opacity(0.32), lineWidth: 1))
        }.buttonStyle(.plain)
    }

    private func valueControl<Content: View>(title: String, value: String, unit: String, minus: @escaping () -> Void, plus: @escaping () -> Void, @ViewBuilder content: () -> Content) -> some View {
        VStack(spacing: KoiTheme.space.s8) {
            Text(title).font(KoiTheme.caption).tracking(1.4).opacity(0.72)
            content().foregroundStyle(KoiTheme.onBase)
            Text(unit).font(KoiTheme.caption).opacity(0.7)
            HStack(spacing: KoiTheme.space.s8) {
                Button(action: minus) { Image(systemName: "minus").frame(width: 30, height: 30) }
                Button(action: plus) { Image(systemName: "plus").frame(width: 30, height: 30) }
            }.buttonStyle(.plain)
        }.frame(maxWidth: .infinity).padding(.vertical, KoiTheme.space.s8)
    }

    private func durationText(from start: Date, now: Date) -> String {
        let seconds = max(Int(now.timeIntervalSince(start)), 0)
        return timeString(seconds)
    }
    private func timeString(_ seconds: Int) -> String { String(format: "%02d:%02d", max(seconds, 0) / 60, max(seconds, 0) % 60) }
    private func formatWeight(_ value: Double) -> String { value.rounded(.towardZero) == value ? String(Int(value)) : String(format: "%.1f", value) }
}

private struct WorkoutSummarySheet: View {
    @Environment(\.dismiss) private var dismiss
    let summary: WorkoutCompletionSummary
    let onSaveAsRoutine: () -> Void

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: KoiTheme.space.s21) {
                Text("Well done.").font(KoiTheme.title)
                Text(summary.name).font(KoiTheme.body)
                HStack(spacing: KoiTheme.space.s21) {
                    summaryStat("\(summary.minutes)", label: "MINUTES")
                    summaryStat("\(summary.sets)", label: "SETS")
                    summaryStat(summary.volumeLB.formatted(), label: "LB MOVED")
                }
                if !summary.bestLifts.isEmpty { GlassChip(title: "New best · \(summary.bestLifts.joined(separator: ", "))", symbol: "sparkle", isOn: true) }
                KoiPrimaryButton(title: "Save as routine") { onSaveAsRoutine(); dismiss() }
                ShareLink(item: "\(summary.name) · \(summary.minutes) min · \(summary.sets) sets · \(summary.volumeLB) lb moved") {
                    Text("Share summary").font(KoiTheme.caption).frame(maxWidth: .infinity).padding(.vertical, KoiTheme.space.s8)
                }.buttonStyle(.plain)
                Spacer()
            }.padding(KoiTheme.space.s21).background(KoiBackground().ignoresSafeArea()).foregroundStyle(KoiTheme.onBase)
                .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() }.font(KoiTheme.caption) } }
        }.preferredColorScheme(.dark)
    }
    private func summaryStat(_ value: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: KoiTheme.space.s5) {
            Text(value).font(.system(size: 26, weight: .medium, design: .rounded)).monospacedDigit()
            Text(label).font(KoiTheme.caption).tracking(0.9)
        }
    }
}
