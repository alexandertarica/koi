import ActivityKit
import AppIntents
import SwiftData
import SwiftUI
import WidgetKit
import KoiShared

private enum KoiWidgetColors {
    static let water = Color(red: 0.09, green: 0.16, blue: 0.27)
    static let ink = Color(red: 0.94, green: 0.91, blue: 0.86)
    static let muted = ink.opacity(0.68)
}

private enum KoiWidgetLinks {
    static let mealLog = URL(string: "koi://intake/log") ?? URL(fileURLWithPath: "/")
    static let mealCamera = URL(string: "koi://intake/camera") ?? URL(fileURLWithPath: "/")
    static let habits = URL(string: "koi://todo") ?? URL(fileURLWithPath: "/")
}

private struct KoiEntry: TimelineEntry {
    let date: Date
    let snapshot: KoiWidgetSnapshot
}

private struct KoiProvider: TimelineProvider {
    func placeholder(in context: Context) -> KoiEntry { KoiEntry(date: .now, snapshot: .empty) }
    func getSnapshot(in context: Context, completion: @escaping (KoiEntry) -> Void) {
        completion(KoiEntry(date: .now, snapshot: KoiWidgetSnapshotStore.read()))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<KoiEntry>) -> Void) {
        let entry = KoiEntry(date: .now, snapshot: KoiWidgetSnapshotStore.read())
        completion(Timeline(entries: [entry], policy: .after(.now.addingTimeInterval(60 * 30))))
    }
}

private struct KoiBalanceWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: KoiEntry

    var body: some View {
        Group {
            if family == .accessoryCircular {
                ZStack {
                    AccessoryWidgetBackground()
                    Gauge(value: Double(entry.snapshot.balance), in: 0...100) {
                        Text("KOI").font(.system(size: 7, weight: .medium, design: .monospaced))
                    } currentValueLabel: {
                        Text("\(entry.snapshot.balance)").font(.system(size: 14, weight: .medium, design: .rounded))
                    }.gaugeStyle(.accessoryCircular)
                }
            } else if family == .accessoryRectangular {
                VStack(alignment: .leading, spacing: 3) {
                    Text("KOI BALANCE").font(.system(size: 9, design: .monospaced)).tracking(1)
                    Text("\(entry.snapshot.balance)% · H \(entry.snapshot.habits) · N \(entry.snapshot.nutrition) · E \(entry.snapshot.exercise)").font(.system(size: 12, weight: .medium)).lineLimit(1)
                }
            } else if family == .accessoryInline {
                Text("\(entry.snapshot.balance)% Balance")
            } else if family == .systemSmall {
                VStack(alignment: .leading, spacing: 8) {
                    Text("BALANCE").font(.system(size: 9, design: .monospaced)).tracking(1.8).foregroundStyle(KoiWidgetColors.muted)
                    Spacer(minLength: 0)
                    Text("\(entry.snapshot.balance)%").font(.system(size: 36, weight: .light, design: .rounded)).monospacedDigit()
                    pillarBars
                }.padding(15)
            } else {
                HStack(spacing: 20) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("TODAY").font(.system(size: 9, design: .monospaced)).tracking(1.8).foregroundStyle(KoiWidgetColors.muted)
                        Text("\(entry.snapshot.balance)%").font(.system(size: 42, weight: .light, design: .rounded)).monospacedDigit()
                        Text("Balance").font(.system(size: 12)).foregroundStyle(KoiWidgetColors.muted)
                    }.frame(minWidth: 98, alignment: .leading)
                    VStack(alignment: .leading, spacing: 10) {
                        pillarRow("Habits", entry.snapshot.habits)
                        pillarRow("Nutrition", entry.snapshot.nutrition)
                        pillarRow("Exercise", entry.snapshot.exercise)
                    }
                }.padding(17)
            }
        }
        .foregroundStyle(KoiWidgetColors.ink)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .containerBackground(KoiWidgetColors.water.gradient, for: .widget)
        .widgetURL(URL(string: "koi://hub"))
    }

    private var pillarBars: some View {
        HStack(spacing: 5) {
            ForEach(Array([entry.snapshot.habits, entry.snapshot.nutrition, entry.snapshot.exercise].enumerated()), id: \.offset) { _, value in
                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule().fill(KoiWidgetColors.ink.opacity(0.16))
                        Capsule().fill(KoiWidgetColors.ink.opacity(0.78)).frame(width: proxy.size.width * CGFloat(value) / 100)
                    }
                }.frame(height: 4)
            }
        }
    }

    private func pillarRow(_ title: String, _ value: Int) -> some View {
        HStack(spacing: 8) {
            Text(title).font(.system(size: 11)).foregroundStyle(KoiWidgetColors.muted)
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(KoiWidgetColors.ink.opacity(0.16))
                    Capsule().fill(KoiWidgetColors.ink.opacity(0.78)).frame(width: proxy.size.width * CGFloat(value) / 100)
                }
            }.frame(height: 4)
            Text("\(value)").font(.system(size: 10, design: .monospaced)).frame(width: 22, alignment: .trailing)
        }
    }
}

struct KoiBalanceWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "KoiBalance", provider: KoiProvider()) { entry in
            KoiBalanceWidgetView(entry: entry)
        }
        .configurationDisplayName("Koi Balance")
        .description("A quiet look at today's Balance.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}

private struct KoiHabitsView: View {
    @Environment(\.widgetFamily) private var family
    let entry: KoiEntry

    private var nextHabit: KoiWidgetHabit? { entry.snapshot.habitItems.first(where: { !$0.isComplete }) ?? entry.snapshot.habitItems.first }

    var body: some View {
        Group {
            if family == .accessoryInline {
                if let nextHabit {
                    Button(intent: ToggleKoiHabitIntent(habitID: nextHabit.id.uuidString)) {
                        Label(nextHabit.title, systemImage: nextHabit.isComplete ? "checkmark.circle.fill" : "circle")
                    }.buttonStyle(.plain)
                } else {
                    Text("No habits today")
                }
            } else if family == .accessoryRectangular {
                if let nextHabit {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("NEXT HABIT").font(.system(size: 9, design: .monospaced)).tracking(1).foregroundStyle(KoiWidgetColors.muted)
                        Button(intent: ToggleKoiHabitIntent(habitID: nextHabit.id.uuidString)) {
                            Label(nextHabit.title, systemImage: nextHabit.isComplete ? "checkmark.circle.fill" : "circle").font(.system(size: 12, weight: .medium)).lineLimit(1)
                        }.buttonStyle(.plain)
                    }
                } else {
                    Text("No habits today").font(.system(size: 12))
                }
            } else {
                habitList
            }
        }
        .foregroundStyle(KoiWidgetColors.ink)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .containerBackground(KoiWidgetColors.water.gradient, for: .widget)
        .widgetURL(URL(string: "koi://todo"))
    }

    private var habitList: some View {
        VStack(alignment: .leading, spacing: family == .systemLarge ? 12 : 7) {
            HStack(alignment: .firstTextBaseline) {
                Text("TODAY'S HABITS").font(.system(size: 9, design: .monospaced)).tracking(1.3).foregroundStyle(KoiWidgetColors.muted)
                Spacer()
                Text("\(entry.snapshot.habitsCompleted)/\(entry.snapshot.habitsTotal) done").font(.system(size: 11, weight: .medium, design: .rounded))
            }
            if entry.snapshot.habitItems.isEmpty {
                Text("Your habits will settle here.").font(.system(size: 12)).foregroundStyle(KoiWidgetColors.muted).frame(maxHeight: .infinity, alignment: .center)
            } else {
                ForEach(entry.snapshot.habitItems.prefix(family == .systemSmall ? 3 : 6)) { habit in
                    Button(intent: ToggleKoiHabitIntent(habitID: habit.id.uuidString)) {
                        HStack(spacing: 8) {
                            Image(systemName: habit.isComplete ? "checkmark.circle.fill" : "circle").font(.system(size: 15, weight: .light))
                            Text(habit.title).font(.system(size: family == .systemLarge ? 13 : 11)).lineLimit(1)
                            Spacer(minLength: 0)
                        }.foregroundStyle(KoiWidgetColors.ink.opacity(habit.isComplete ? 0.7 : 1))
                    }.buttonStyle(.plain)
                }
            }
        }
        .padding(14)
    }
}

struct KoiHabitsWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "KoiHabits", provider: KoiProvider()) { entry in KoiHabitsView(entry: entry) }
            .configurationDisplayName("Koi Habits")
            .description("Check off today's habits.")
            .supportedFamilies([.systemSmall, .systemMedium, .systemLarge, .accessoryRectangular, .accessoryInline])
    }
}

private struct KoiQuickLogView: View {
    @Environment(\.widgetFamily) private var family

    var body: some View {
        Link(destination: KoiWidgetLinks.mealLog) {
            Group {
                if family == .accessoryInline {
                    Label("Log a meal", systemImage: "leaf")
                } else if family == .accessoryRectangular {
                    Label("Log a meal", systemImage: "leaf").font(.system(size: 13, weight: .medium))
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        Image(systemName: "leaf").font(.system(size: 20, weight: .light))
                        Spacer(minLength: 0)
                        Text("LOG A MEAL").font(.system(size: 9, design: .monospaced)).tracking(1.4)
                        Text("Add food to today.").font(.system(size: 12)).foregroundStyle(KoiWidgetColors.muted)
                    }.padding(15).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                }
            }
            .foregroundStyle(KoiWidgetColors.ink)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }
        .containerBackground(KoiWidgetColors.water.gradient, for: .widget)
    }
}

struct KoiQuickLogWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "KoiQuickLog", provider: KoiProvider()) { _ in KoiQuickLogView() }
            .configurationDisplayName("Quick log")
            .description("Open the meal composer from Home or Lock Screen.")
            .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular, .accessoryInline])
    }
}

private struct KoiNextActionView: View {
    let entry: KoiEntry
    private var nextHabit: KoiWidgetHabit? { entry.snapshot.habitItems.first(where: { !$0.isComplete }) }

    var body: some View {
        Group {
            if let nextHabit {
                Link(destination: KoiWidgetLinks.habits) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("NEXT UP").font(.system(size: 9, design: .monospaced)).tracking(1).foregroundStyle(KoiWidgetColors.muted)
                        Text(nextHabit.title).font(.system(size: 12, weight: .medium)).lineLimit(1)
                    }
                }
            } else {
                Link(destination: KoiWidgetLinks.mealLog) {
                    Label("Log a meal", systemImage: "leaf").font(.system(size: 12, weight: .medium))
                }
            }
        }
        .foregroundStyle(KoiWidgetColors.ink)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .containerBackground(.clear, for: .widget)
    }
}

struct KoiNextActionWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "KoiNextAction", provider: KoiProvider()) { entry in KoiNextActionView(entry: entry) }
            .configurationDisplayName("Next best action")
            .description("A small nudge for today.")
            .supportedFamilies([.accessoryRectangular])
    }
}

struct ToggleKoiHabitIntent: AppIntent {
    static let title: LocalizedStringResource = "Toggle Koi Habit"
    static let description = IntentDescription("Mark a Koi habit complete or reopen it for today.")
    @Parameter(title: "Habit ID") var habitID: String

    init() { habitID = "" }
    init(habitID: String) { self.habitID = habitID }

    func perform() async throws -> some IntentResult {
        guard let id = UUID(uuidString: habitID) else { return .result() }
        let container = try KoiSchema.makeContainer()
        let context = ModelContext(container)
        let habitID = id
        var descriptor = FetchDescriptor<KoiHabit>(predicate: #Predicate { $0.id == habitID })
        descriptor.fetchLimit = 1
        guard let habit = try context.fetch(descriptor).first, habit.isActive, habit.pausedAt == nil else { return .result() }
        let calendar = Calendar.autoupdatingCurrent
        guard calendar.startOfDay(for: habit.createdAt) <= calendar.startOfDay(for: .now) else { return .result() }
        let today = calendar.startOfDay(for: .now)
        let logs = try context.fetch(FetchDescriptor<KoiHabitLog>(predicate: #Predicate { $0.habitID == habitID }))
        let scheduled: Bool
        switch habit.schedule {
        case "weekly": scheduled = calendar.component(.weekday, from: today) == calendar.component(.weekday, from: habit.createdAt)
        case "monthly":
            let createdDay = calendar.component(.day, from: habit.createdAt)
            let monthEnd = calendar.range(of: .day, in: .month, for: today)?.upperBound.advanced(by: -1) ?? createdDay
            scheduled = calendar.component(.day, from: today) == min(createdDay, monthEnd)
        case "someDays": scheduled = habit.weekdays.contains(calendar.component(.weekday, from: today))
        default: scheduled = true
        }
        guard scheduled else { return .result() }
        if let log = logs.first(where: { calendar.isDate($0.date, inSameDayAs: today) }) {
            log.completion = log.completion > 0 ? 0 : 2
        } else {
            context.insert(KoiHabitLog(habitID: id, date: today, completion: 2))
        }
        try context.save()
        KoiWidgetSnapshotStore.write(KoiWidgetSnapshotStore.read().togglingHabit(id))
        WidgetCenter.shared.reloadAllTimelines()
        return .result()
    }
}

private extension KoiWidgetSnapshot {
    func togglingHabit(_ id: UUID) -> KoiWidgetSnapshot {
        let wasComplete = habitItems.first(where: { $0.id == id })?.isComplete ?? false
        let changed = habitItems.map { item in
            KoiWidgetHabit(id: item.id, title: item.title, isComplete: item.id == id ? !item.isComplete : item.isComplete)
        }
        return KoiWidgetSnapshot(day: day, balance: balance, habits: habits, nutrition: nutrition, exercise: exercise, habitItems: changed, habitsCompleted: habitsCompleted + (wasComplete ? -1 : 1), habitsTotal: habitsTotal)
    }
}

struct LogWorkoutSetIntent: AppIntent {
    static let title: LocalizedStringResource = "Log Workout Set"
    static let description = IntentDescription("Log the next set in the active Koi workout.")
    @Parameter(title: "Session ID") var sessionID: String
    @Parameter(title: "Lift ID") var liftID: String
    @Parameter(title: "Weight") var weightLB: Double
    @Parameter(title: "Reps") var reps: Int
    @Parameter(title: "Bodyweight") var isBodyweight: Bool

    init() { sessionID = ""; liftID = ""; weightLB = 0; reps = 0; isBodyweight = false }
    init(sessionID: String, liftID: String, weightLB: Double, reps: Int, isBodyweight: Bool) {
        self.sessionID = sessionID; self.liftID = liftID; self.weightLB = weightLB; self.reps = reps; self.isBodyweight = isBodyweight
    }

    func perform() async throws -> some IntentResult {
        guard let sessionUUID = UUID(uuidString: sessionID), let liftUUID = UUID(uuidString: liftID) else { return .result() }
        let container = try KoiSchema.makeContainer()
        let context = ModelContext(container)
        var sessionQuery = FetchDescriptor<KoiWorkoutSession>(predicate: #Predicate { $0.id == sessionUUID && !$0.isComplete })
        sessionQuery.fetchLimit = 1
        var liftQuery = FetchDescriptor<KoiWorkoutLift>(predicate: #Predicate { $0.id == liftUUID && $0.sessionID == sessionUUID })
        liftQuery.fetchLimit = 1
        guard let session = try context.fetch(sessionQuery).first,
              let lift = try context.fetch(liftQuery).first else { return .result() }
        context.insert(KoiWorkoutSet(sessionID: sessionUUID, liftID: liftUUID, weightLB: isBodyweight ? 0 : weightLB, reps: min(max(reps, 1), 1_000), isBodyweight: isBodyweight))
        session.restUntil = .now.addingTimeInterval(TimeInterval(lift.restSeconds))
        try context.save()
        let count = try context.fetch(FetchDescriptor<KoiWorkoutSet>(predicate: #Predicate { $0.sessionID == sessionUUID && $0.liftID == liftUUID && !$0.isWarmUp })).count
        let state = KoiWorkoutActivityAttributes.ContentState(liftID: liftUUID.uuidString, restUntil: session.restUntil, liftName: lift.name, completedSets: count, targetSets: lift.targetSets, weightLB: weightLB, reps: reps, isBodyweight: isBodyweight)
        for activity in Activity<KoiWorkoutActivityAttributes>.activities where activity.attributes.sessionID == sessionID {
            await activity.update(ActivityContent(state: state, staleDate: session.restUntil))
        }
        WidgetCenter.shared.reloadAllTimelines()
        return .result()
    }
}

struct KoiWorkoutLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: KoiWorkoutActivityAttributes.self) { context in
            workoutLockScreen(context)
                .activityBackgroundTint(KoiWidgetColors.water)
                .activitySystemActionForegroundColor(KoiWidgetColors.ink)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) { Image(systemName: "figure.strengthtraining.traditional") }
                DynamicIslandExpandedRegion(.center) { Text(context.state.liftName).lineLimit(1) }
                DynamicIslandExpandedRegion(.trailing) { setLabel(context.state) }
                DynamicIslandExpandedRegion(.bottom) {
                    HStack {
                        setInHand(context.state).font(.system(size: 11, design: .monospaced))
                        Spacer(minLength: 8)
                        restLabel(context.state)
                        Spacer()
                        logSetButton(context.attributes, context.state)
                    }
                }
            } compactLeading: {
                Image(systemName: "dumbbell.fill")
            } compactTrailing: {
                setLabel(context.state)
            } minimal: {
                Image(systemName: "dumbbell.fill")
            }
            .keylineTint(KoiWidgetColors.ink)
        }
    }

    private func workoutLockScreen(_ context: ActivityViewContext<KoiWorkoutActivityAttributes>) -> some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 5) {
                Text("WORKOUT · \(context.state.completedSets)/\(context.state.targetSets) SETS").font(.system(size: 9, design: .monospaced)).tracking(1.2).foregroundStyle(KoiWidgetColors.muted)
                Text(context.state.liftName).font(.system(size: 17, weight: .medium)).lineLimit(1)
                setInHand(context.state).font(.system(size: 12, design: .monospaced)).foregroundStyle(KoiWidgetColors.muted)
                restLabel(context.state).font(.system(size: 12, design: .monospaced)).foregroundStyle(KoiWidgetColors.muted)
            }
            Spacer()
            logSetButton(context.attributes, context.state)
        }
        .padding(16)
        .foregroundStyle(KoiWidgetColors.ink)
    }

    private func restLabel(_ state: KoiWorkoutActivityAttributes.ContentState) -> some View {
        Group {
            if let restUntil = state.restUntil, restUntil > .now {
                Text(timerInterval: .now...restUntil, countsDown: true, showsHours: false)
            } else {
                Text("Ready when you are")
            }
        }
    }

    private func setLabel(_ state: KoiWorkoutActivityAttributes.ContentState) -> some View {
        Text("\(state.completedSets)/\(state.targetSets)").font(.system(size: 12, design: .monospaced))
    }

    private func setInHand(_ state: KoiWorkoutActivityAttributes.ContentState) -> some View {
        Text(state.isBodyweight ? "BW × \(state.reps)" : "\(Int(state.weightLB.rounded())) × \(state.reps)")
    }

    private func logSetButton(_ attributes: KoiWorkoutActivityAttributes, _ state: KoiWorkoutActivityAttributes.ContentState) -> some View {
        Button(intent: LogWorkoutSetIntent(sessionID: attributes.sessionID, liftID: state.liftID, weightLB: state.weightLB, reps: state.reps, isBodyweight: state.isBodyweight)) {
            Label("Log set", systemImage: "checkmark.circle.fill").font(.system(size: 12, weight: .medium)).padding(.horizontal, 12).padding(.vertical, 9)
                .background(KoiWidgetColors.ink.opacity(0.14), in: Capsule())
        }.buttonStyle(.plain)
    }
}

struct KoiMealControl: ControlWidget {
    static let kind = "KoiLogMealControl"

    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: Self.kind) {
            ControlWidgetButton(action: OpenURLIntent(KoiWidgetLinks.mealCamera)) {
                Label("Log a meal", systemImage: "leaf")
            }
        }
        .displayName("Log a meal")
        .description("Open the camera to add a meal photo.")
    }
}

@main
struct KoiWidgetBundle: WidgetBundle {
    var body: some Widget {
        KoiBalanceWidget()
        KoiHabitsWidget()
        KoiQuickLogWidget()
        KoiNextActionWidget()
        KoiWorkoutLiveActivity()
        KoiMealControl()
    }
}
