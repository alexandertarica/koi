import SwiftUI
import SwiftData
import KoiShared
import AppIntents
import UserNotifications
import OSLog

@main
struct KoiApp: App {
    private let modelContainer: ModelContainer
    private let runTracker: RunTracker
    private let notificationRouter: KoiNotificationRouter

    init() {
        runTracker = RunTracker()
        notificationRouter = KoiNotificationRouter()
        UNUserNotificationCenter.current().delegate = notificationRouter
        do {
            modelContainer = try KoiSchema.makeContainer()
        } catch {
            fatalError("Koi could not open its local data store: \(error.localizedDescription)")
        }
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-koiDemo") {
            do { try KoiDemoSeeder.seedForDemoLaunch(ModelContext(modelContainer)) }
            catch { Logger(subsystem: "com.alexandertarica.koi", category: "Demo").error("Unable to seed demo data before launch.") }
        }
        #endif
    }

    var body: some Scene {
        WindowGroup {
            KoiRootView().environment(\.runTracker, runTracker)
        }
        .modelContainer(modelContainer)
    }
}

enum KoiIntentStore {
    enum InputError: LocalizedError {
        case invalidAmount
        case invalidMeal
        case invalidWorkout

        var errorDescription: String? {
            switch self {
            case .invalidAmount: "Enter a positive amount to log."
            case .invalidMeal: "Add a meal name with valid nutrition amounts."
            case .invalidWorkout: "Add a workout name and a valid duration."
            }
        }
    }

    static func makeContext() throws -> ModelContext {
        ModelContext(try KoiSchema.makeContainer())
    }

    static func addNutrient(_ key: String, amount: Double, context suppliedContext: ModelContext? = nil) throws {
        guard ["water", "protein"].contains(key), amount.isFinite, (0.1...128).contains(amount) else {
            throw InputError.invalidAmount
        }
        let context = try suppliedContext ?? makeContext()
        let dayID = KoiNutrientEntry(date: .now, nutrientKey: key).dayID
        let entries = try context.fetch(FetchDescriptor<KoiNutrientEntry>())
        if let entry = entries.first(where: { $0.dayID == dayID && $0.nutrientKey == key }) {
            entry.value += amount
        } else {
            context.insert(KoiNutrientEntry(date: .now, nutrientKey: key, value: amount))
        }
        try context.save()
    }

    static func addMeal(name: String, calories: Double, protein: Double, context suppliedContext: ModelContext? = nil) throws {
        let cleanedName = String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(100))
        guard !cleanedName.isEmpty, calories.isFinite, protein.isFinite,
              (0...10_000).contains(calories), (0...1_000).contains(protein) else {
            throw InputError.invalidMeal
        }
        let context = try suppliedContext ?? makeContext()
        context.insert(KoiFoodEntry(name: cleanedName, calories: calories, proteinGrams: protein))
        try context.save()
        NotificationCenter.default.post(name: .koiCoachRequested, object: nil, userInfo: ["event": "meal"])
    }

    static func completeHabit(named phrase: String, allowToggle: Bool = false, context suppliedContext: ModelContext? = nil) throws -> Bool {
        let context = try suppliedContext ?? makeContext()
        let name = phrase.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return false }
        let habits = try context.fetch(FetchDescriptor<KoiHabit>())
        guard let habit = habits.first(where: {
            guard $0.isActive, $0.pausedAt == nil else { return false }
            return $0.title.localizedCaseInsensitiveCompare(name) == .orderedSame
                || name.localizedCaseInsensitiveContains($0.title)
                || ($0.title.count >= 3 && $0.title.localizedCaseInsensitiveContains(name))
        }) else { return false }
        let day = Calendar.autoupdatingCurrent.startOfDay(for: .now)
        let logs = try context.fetch(FetchDescriptor<KoiHabitLog>())
        var didComplete = true
        if let log = logs.first(where: { $0.habitID == habit.id && Calendar.autoupdatingCurrent.isDate($0.date, inSameDayAs: day) }) {
            log.completion = allowToggle && log.completion > 0 ? 0 : 2
            didComplete = log.completion > 0
        } else {
            context.insert(KoiHabitLog(habitID: habit.id, date: day, completion: 2))
        }
        try context.save()
        if didComplete { NotificationCenter.default.post(name: .koiCoachRequested, object: nil, userInfo: ["event": "habit"]) }
        return true
    }

    static func logWorkout(name: String, minutes: Int, context suppliedContext: ModelContext? = nil) throws {
        let cleanName = String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(80))
        guard !cleanName.isEmpty, (0...1_440).contains(minutes) else { throw InputError.invalidWorkout }
        let context = try suppliedContext ?? makeContext()
        let now = Date.now
        let session = KoiWorkoutSession(name: cleanName, startedAt: now.addingTimeInterval(-Double(minutes * 60)))
        session.endedAt = now
        session.isComplete = true
        context.insert(session)
        let today = Calendar.autoupdatingCurrent.startOfDay(for: now)
        let days = try context.fetch(FetchDescriptor<KoiMovementDay>())
        if let day = days.first(where: { Calendar.autoupdatingCurrent.isDate($0.date, inSameDayAs: today) }) {
            day.didManuallyTrain = true
        } else {
            context.insert(KoiMovementDay(date: today, didManuallyTrain: true))
        }
        try context.save()
        NotificationCenter.default.post(name: .koiCoachRequested, object: nil, userInfo: ["event": "workout"])
    }
}

struct AddWaterIntent: AppIntent {
    static let title: LocalizedStringResource = "Add Water"
    static let description = IntentDescription("Add water to today's Koi intake.")
    @Parameter(title: "Ounces") var ounces: Double
    init() { ounces = 8 }
    init(ounces: Double) { self.ounces = ounces }
    func perform() async throws -> some IntentResult {
        try KoiIntentStore.addNutrient("water", amount: ounces)
        return .result(dialog: "Water added.")
    }
}

struct LogWaterIntent: AppIntent {
    static let title: LocalizedStringResource = "Log Water"
    static let description = IntentDescription("Log ounces of water in Koi.")
    @Parameter(title: "Ounces") var ounces: Double
    init() { ounces = 8 }
    func perform() async throws -> some IntentResult {
        try KoiIntentStore.addNutrient("water", amount: ounces)
        return .result(dialog: "Water logged.")
    }
}

struct LogProteinIntent: AppIntent {
    static let title: LocalizedStringResource = "Log Protein"
    static let description = IntentDescription("Add protein grams to today's Koi intake.")
    @Parameter(title: "Grams") var grams: Double
    init() { grams = 20 }
    func perform() async throws -> some IntentResult {
        try KoiIntentStore.addNutrient("protein", amount: grams)
        return .result(dialog: "Protein logged.")
    }
}

struct LogMealIntent: AppIntent {
    static let title: LocalizedStringResource = "Log a Meal"
    static let description = IntentDescription("Add a meal to Koi intake.")
    @Parameter(title: "Meal") var meal: String
    @Parameter(title: "Calories") var calories: Double
    @Parameter(title: "Protein grams") var protein: Double
    init() { meal = ""; calories = 0; protein = 0 }
    func perform() async throws -> some IntentResult {
        try KoiIntentStore.addMeal(name: meal, calories: calories, protein: protein)
        return .result(dialog: "Meal logged.")
    }
}

struct LogWorkoutIntent: AppIntent {
    static let title: LocalizedStringResource = "Log a Workout"
    static let description = IntentDescription("Record a completed workout in Koi Movement.")
    @Parameter(title: "Workout") var workout: String
    @Parameter(title: "Minutes") var minutes: Int
    init() { workout = "Workout"; minutes = 30 }
    func perform() async throws -> some IntentResult {
        try KoiIntentStore.logWorkout(name: workout, minutes: minutes)
        return .result(dialog: "Workout logged.")
    }
}

struct CompleteHabitIntent: AppIntent {
    static let title: LocalizedStringResource = "Complete a Habit"
    static let description = IntentDescription("Mark a named Koi habit complete for today.")
    @Parameter(title: "Habit") var habit: String
    init() { habit = "" }
    func perform() async throws -> some IntentResult {
        guard try KoiIntentStore.completeHabit(named: habit) else {
            return .result(dialog: "I couldn't find that active habit in Koi.")
        }
        return .result(dialog: "Habit complete.")
    }
}

struct ToggleHabitIntent: AppIntent {
    static let title: LocalizedStringResource = "Toggle a Habit"
    static let description = IntentDescription("Toggle a named Koi habit for today.")
    @Parameter(title: "Habit") var habit: String
    init() { habit = "" }
    func perform() async throws -> some IntentResult {
        guard try KoiIntentStore.completeHabit(named: habit, allowToggle: true) else {
            return .result(dialog: "I couldn't find that active habit in Koi.")
        }
        return .result(dialog: "Habit updated.")
    }
}

struct OpenMealCameraIntent: AppIntent {
    static let title: LocalizedStringResource = "Open Meal Camera"
    static let description = IntentDescription("Open Koi's meal camera.")
    func perform() async throws -> some IntentResult {
        guard let url = URL(string: "koi://intake/camera") else { return .result() }
        return .result(opensIntent: OpenURLIntent(url))
    }
}

struct KoiAppShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: AddWaterIntent(), phrases: ["Add water in \(.applicationName)"], shortTitle: "Add Water", systemImageName: "drop")
        AppShortcut(intent: LogWaterIntent(), phrases: ["Log water with \(.applicationName)"], shortTitle: "Log Water", systemImageName: "drop.fill")
        AppShortcut(intent: LogProteinIntent(), phrases: ["Log protein in \(.applicationName)"], shortTitle: "Log Protein", systemImageName: "fork.knife")
        AppShortcut(intent: LogMealIntent(), phrases: ["Log a meal in \(.applicationName)"], shortTitle: "Log Meal", systemImageName: "leaf")
        AppShortcut(intent: LogWorkoutIntent(), phrases: ["Log a workout in \(.applicationName)"], shortTitle: "Log Workout", systemImageName: "dumbbell")
        AppShortcut(intent: CompleteHabitIntent(), phrases: ["Complete a habit in \(.applicationName)"], shortTitle: "Complete Habit", systemImageName: "checkmark.circle")
        AppShortcut(intent: ToggleHabitIntent(), phrases: ["Toggle a habit in \(.applicationName)"], shortTitle: "Toggle Habit", systemImageName: "circle")
        AppShortcut(intent: OpenMealCameraIntent(), phrases: ["Open the meal camera in \(.applicationName)"], shortTitle: "Meal Camera", systemImageName: "camera")
    }
}
