import CloudKit
import Foundation
import SwiftData
import OSLog
import KoiShared

enum BackupError: LocalizedError {
    case noBackup
    case invalidArchive
    case accountUnavailable

    var errorDescription: String? {
        switch self {
        case .noBackup: "No iCloud backup is available yet."
        case .invalidArchive: "The iCloud backup couldn't be read."
        case .accountUnavailable: "Sign in to iCloud to back up Koi."
        }
    }
}

@MainActor
protocol BackupProviding: Sendable {
    func hasBackup() async throws -> Bool
    func backup(using context: ModelContext) async throws -> Date
    func restore(using context: ModelContext) async throws -> Date
}

enum BackupValue: Codable {
    case string(String?)
    case integer(Int?)
    case decimal(Double?)
    case flag(Bool?)
    case date(Date?)
    case data(Data?)
    case strings([String]?)
    case integers([Int]?)

    var stringValue: String? { if case .string(let value) = self { value } else { nil } }
    var integerValue: Int? { if case .integer(let value) = self { value } else { nil } }
    var decimalValue: Double? { if case .decimal(let value) = self { value } else { nil } }
    var flagValue: Bool? { if case .flag(let value) = self { value } else { nil } }
    var dateValue: Date? { if case .date(let value) = self { value } else { nil } }
    var dataValue: Data? { if case .data(let value) = self { value } else { nil } }
    var stringsValue: [String]? { if case .strings(let value) = self { value } else { nil } }
    var integersValue: [Int]? { if case .integers(let value) = self { value } else { nil } }
}

struct BackupRow: Codable {
    let type: String
    let fields: [String: BackupValue]
}

struct KoiBackupArchive: Codable {
    let version: Int
    let createdAt: Date
    let rows: [BackupRow]

    static func capture(_ context: ModelContext, createdAt: Date = .now) throws -> KoiBackupArchive {
        var rows: [BackupRow] = []
        func add(_ type: String, _ fields: [String: BackupValue]) { rows.append(BackupRow(type: type, fields: fields)) }
        func uuid(_ value: UUID) -> BackupValue { .string(value.uuidString) }
        func optionalUUID(_ value: UUID?) -> BackupValue { .string(value?.uuidString) }

        for x in try context.fetch(FetchDescriptor<KoiProfile>()) { add("profile", ["name": .string(x.name), "joinedAt": .date(x.joinedAt), "focusKey": .string(x.focusKey), "avatarJPEG": .data(x.avatarJPEG)]) }
        for x in try context.fetch(FetchDescriptor<KoiOnboardingState>()) {
            add("onboarding", ["isComplete": .flag(x.isComplete), "hasSeenTour": .flag(x.hasSeenTour), "birthYear": .integer(x.birthYear), "heightCM": .decimal(x.heightCM), "sexAtBirth": .string(x.sexAtBirth), "healthConnected": .flag(x.healthConnected), "calendarConnected": .flag(x.calendarConnected), "notificationMode": .string(x.notificationMode), "dailyCheckInHour": .integer(x.dailyCheckInHour), "betaEmail": .string(x.betaEmail), "launchEmail": .string(x.launchEmail), "backupEnabled": .flag(x.backupEnabled), "lastBackupAt": .date(x.lastBackupAt)])
        }
        for x in try context.fetch(FetchDescriptor<KoiBodyWeightEntry>()) { add("weight", ["dayID": .string(x.dayID), "date": .date(x.date), "weightLB": .decimal(x.weightLB)]) }
        for x in try context.fetch(FetchDescriptor<KoiDay>()) { add("day", ["dayID": .string(x.dayID), "date": .date(x.date), "balance": .decimal(x.balance), "habitsScore": .decimal(x.habitsScore), "nutritionScore": .decimal(x.nutritionScore), "exerciseScore": .decimal(x.exerciseScore)]) }
        for x in try context.fetch(FetchDescriptor<KoiHabit>()) { add("habit", ["id": uuid(x.id), "title": .string(x.title), "note": .string(x.note), "isActive": .flag(x.isActive), "createdAt": .date(x.createdAt), "schedule": .string(x.schedule), "weekdays": .integers(x.weekdays), "reminderTime": .date(x.reminderTime), "minimumVersion": .string(x.minimumVersion), "stackingCue": .string(x.stackingCue), "identity": .string(x.identity), "pausedAt": .date(x.pausedAt), "graduatedAt": .date(x.graduatedAt)]) }
        for x in try context.fetch(FetchDescriptor<KoiHabitLog>()) { add("habitLog", ["id": uuid(x.id), "habitID": uuid(x.habitID), "date": .date(x.date), "completion": .integer(x.completion)]) }
        for x in try context.fetch(FetchDescriptor<KoiTask>()) { add("task", ["id": uuid(x.id), "title": .string(x.title), "notes": .string(x.notes), "dueAt": .date(x.dueAt), "quadrant": .integer(x.quadrant), "isComplete": .flag(x.isComplete), "createdAt": .date(x.createdAt), "important": .flag(x.important), "urgentOverride": .flag(x.urgentOverride), "completedAt": .date(x.completedAt), "archivedAt": .date(x.archivedAt), "lastTouchedAt": .date(x.lastTouchedAt), "timeMinutes": .integer(x.timeMinutes), "calendarEventID": .string(x.calendarEventID), "hasTime": .flag(x.hasTime)]) }
        for x in try context.fetch(FetchDescriptor<KoiFoodEntry>()) { add("food", ["id": uuid(x.id), "loggedAt": .date(x.loggedAt), "name": .string(x.name), "calories": .decimal(x.calories), "proteinGrams": .decimal(x.proteinGrams), "carbohydrateGrams": .decimal(x.carbohydrateGrams), "fatGrams": .decimal(x.fatGrams), "fiberGrams": .decimal(x.fiberGrams), "addedSugarGrams": .decimal(x.addedSugarGrams), "sodiumMilligrams": .decimal(x.sodiumMilligrams), "confidence": .decimal(x.confidence), "imageJPEG": .data(x.imageJPEG), "notes": .string(x.notes)]) }
        for x in try context.fetch(FetchDescriptor<KoiNutrientGoal>()) { add("nutrientGoal", ["key": .string(x.key), "name": .string(x.name), "unit": .string(x.unit), "goal": .decimal(x.goal), "step": .decimal(x.step), "goalType": .string(x.goalType), "isActive": .flag(x.isActive)]) }
        for x in try context.fetch(FetchDescriptor<KoiNutrientEntry>()) { add("nutrientEntry", ["id": .string(x.id), "dayID": .string(x.dayID), "nutrientKey": .string(x.nutrientKey), "value": .decimal(x.value)]) }
        for x in try context.fetch(FetchDescriptor<KoiSupplement>()) { add("supplement", ["id": uuid(x.id), "name": .string(x.name), "isActive": .flag(x.isActive)]) }
        for x in try context.fetch(FetchDescriptor<KoiSupplementLog>()) { add("supplementLog", ["id": .string(x.id), "supplementID": uuid(x.supplementID), "dayID": .string(x.dayID), "isTaken": .flag(x.isTaken)]) }
        for x in try context.fetch(FetchDescriptor<KoiMovementGoal>()) { add("movementGoal", ["id": .string(x.id), "stepGoal": .integer(x.stepGoal), "weeklyWorkoutGoal": .integer(x.weeklyWorkoutGoal), "healthEnabled": .flag(x.healthEnabled)]) }
        for x in try context.fetch(FetchDescriptor<KoiMovementDay>()) { add("movementDay", ["dayID": .string(x.dayID), "date": .date(x.date), "healthSteps": .integer(x.healthSteps), "manualStepAdjustment": .integer(x.manualStepAdjustment), "healthWorkoutCount": .integer(x.healthWorkoutCount), "didManuallyTrain": .flag(x.didManuallyTrain)]) }
        for x in try context.fetch(FetchDescriptor<KoiWorkoutRoutine>()) { add("routine", ["id": uuid(x.id), "name": .string(x.name), "muscleGroup": .string(x.muscleGroup), "createdAt": .date(x.createdAt), "plannedAt": .date(x.plannedAt)]) }
        for x in try context.fetch(FetchDescriptor<KoiRoutineLift>()) { add("routineLift", ["id": uuid(x.id), "routineID": uuid(x.routineID), "name": .string(x.name), "muscleGroup": .string(x.muscleGroup), "targetSets": .integer(x.targetSets), "targetReps": .integer(x.targetReps), "order": .integer(x.order), "restSeconds": .integer(x.restSeconds)]) }
        for x in try context.fetch(FetchDescriptor<KoiWorkoutSession>()) { add("workoutSession", ["id": uuid(x.id), "routineID": optionalUUID(x.routineID), "name": .string(x.name), "muscleGroup": .string(x.muscleGroup), "startedAt": .date(x.startedAt), "endedAt": .date(x.endedAt), "restUntil": .date(x.restUntil), "isComplete": .flag(x.isComplete)]) }
        for x in try context.fetch(FetchDescriptor<KoiWorkoutLift>()) { add("workoutLift", ["id": uuid(x.id), "sessionID": uuid(x.sessionID), "name": .string(x.name), "muscleGroup": .string(x.muscleGroup), "order": .integer(x.order), "targetSets": .integer(x.targetSets), "targetReps": .integer(x.targetReps), "restSeconds": .integer(x.restSeconds)]) }
        for x in try context.fetch(FetchDescriptor<KoiWorkoutSet>()) { add("workoutSet", ["id": uuid(x.id), "sessionID": uuid(x.sessionID), "liftID": uuid(x.liftID), "loggedAt": .date(x.loggedAt), "weightLB": .decimal(x.weightLB), "reps": .integer(x.reps), "isWarmUp": .flag(x.isWarmUp), "isBodyweight": .flag(x.isBodyweight)]) }
        for x in try context.fetch(FetchDescriptor<KoiCardioSession>()) { add("cardioSession", ["id": uuid(x.id), "activity": .string(x.activity), "detail": .string(x.detail), "startedAt": .date(x.startedAt), "endedAt": .date(x.endedAt), "durationSeconds": .integer(x.durationSeconds), "distanceMeters": .decimal(x.distanceMeters), "routeData": .data(x.routeData), "mileSplitsData": .data(x.mileSplitsData), "isComplete": .flag(x.isComplete)]) }
        return KoiBackupArchive(version: 1, createdAt: createdAt, rows: rows)
    }

    func restore(into context: ModelContext) throws {
        guard version == 1 else { throw BackupError.invalidArchive }
        try deleteAll(KoiProfile.self, from: context); try deleteAll(KoiOnboardingState.self, from: context); try deleteAll(KoiBodyWeightEntry.self, from: context)
        try deleteAll(KoiDay.self, from: context); try deleteAll(KoiHabit.self, from: context); try deleteAll(KoiHabitLog.self, from: context); try deleteAll(KoiTask.self, from: context)
        try deleteAll(KoiFoodEntry.self, from: context); try deleteAll(KoiNutrientGoal.self, from: context); try deleteAll(KoiNutrientEntry.self, from: context)
        try deleteAll(KoiSupplement.self, from: context); try deleteAll(KoiSupplementLog.self, from: context); try deleteAll(KoiMovementGoal.self, from: context); try deleteAll(KoiMovementDay.self, from: context)
        try deleteAll(KoiWorkoutRoutine.self, from: context); try deleteAll(KoiRoutineLift.self, from: context); try deleteAll(KoiWorkoutSession.self, from: context); try deleteAll(KoiWorkoutLift.self, from: context); try deleteAll(KoiWorkoutSet.self, from: context); try deleteAll(KoiCardioSession.self, from: context)
        try context.save()
        for row in rows {
            let f = row.fields
            func text(_ key: String, _ fallback: String = "") -> String { f[key]?.stringValue ?? fallback }
            func int(_ key: String, _ fallback: Int = 0) -> Int { f[key]?.integerValue ?? fallback }
            func number(_ key: String, _ fallback: Double = 0) -> Double { f[key]?.decimalValue ?? fallback }
            func bool(_ key: String, _ fallback: Bool = false) -> Bool { f[key]?.flagValue ?? fallback }
            func date(_ key: String, _ fallback: Date = .now) -> Date { f[key]?.dateValue ?? fallback }
            func uuid(_ key: String) -> UUID { UUID(uuidString: text(key)) ?? UUID() }
            func optionalUUID(_ key: String) -> UUID? { f[key]?.stringValue.flatMap(UUID.init(uuidString:)) }
            switch row.type {
            case "profile":
                context.insert(KoiProfile(name: text("name", "Friend"), joinedAt: date("joinedAt"), focusKey: text("focusKey", "allRounder"), avatarJPEG: f["avatarJPEG"]?.dataValue))
            case "onboarding":
                context.insert(KoiOnboardingState(isComplete: bool("isComplete"), hasSeenTour: bool("hasSeenTour"), birthYear: f["birthYear"]?.integerValue, heightCM: f["heightCM"]?.decimalValue, sexAtBirth: f["sexAtBirth"]?.stringValue, healthConnected: bool("healthConnected"), calendarConnected: bool("calendarConnected"), notificationMode: text("notificationMode", "smart"), dailyCheckInHour: int("dailyCheckInHour", 9), betaEmail: text("betaEmail"), launchEmail: text("launchEmail"), backupEnabled: bool("backupEnabled", true), lastBackupAt: f["lastBackupAt"]?.dateValue))
            case "weight":
                let x = KoiBodyWeightEntry(date: date("date"), weightLB: number("weightLB")); x.dayID = text("dayID", x.dayID); context.insert(x)
            case "day":
                let x = KoiDay(date: date("date"), balance: number("balance"), habitsScore: number("habitsScore"), nutritionScore: number("nutritionScore"), exerciseScore: number("exerciseScore")); x.dayID = text("dayID", x.dayID); context.insert(x)
            case "habit":
                let x = KoiHabit(title: text("title"), note: text("note"), isActive: bool("isActive", true), createdAt: date("createdAt"), schedule: text("schedule", "daily"), weekdays: f["weekdays"]?.integersValue ?? [], reminderTime: f["reminderTime"]?.dateValue, minimumVersion: text("minimumVersion"), stackingCue: text("stackingCue"), identity: text("identity")); x.id = uuid("id"); x.pausedAt = f["pausedAt"]?.dateValue; x.graduatedAt = f["graduatedAt"]?.dateValue; context.insert(x)
            case "habitLog":
                let x = KoiHabitLog(habitID: uuid("habitID"), date: date("date"), completion: int("completion")); x.id = uuid("id"); context.insert(x)
            case "task":
                let x = KoiTask(title: text("title"), notes: text("notes"), dueAt: f["dueAt"]?.dateValue, quadrant: int("quadrant"), isComplete: bool("isComplete"), createdAt: date("createdAt"), important: bool("important"), urgentOverride: f["urgentOverride"]?.flagValue, timeMinutes: int("timeMinutes", 30), hasTime: bool("hasTime")); x.id = uuid("id"); x.completedAt = f["completedAt"]?.dateValue; x.archivedAt = f["archivedAt"]?.dateValue; x.lastTouchedAt = date("lastTouchedAt", x.createdAt); x.calendarEventID = f["calendarEventID"]?.stringValue; context.insert(x)
            case "food":
                let x = KoiFoodEntry(name: text("name"), loggedAt: date("loggedAt"), calories: number("calories"), proteinGrams: number("proteinGrams"), carbohydrateGrams: number("carbohydrateGrams"), fatGrams: number("fatGrams"), fiberGrams: number("fiberGrams"), addedSugarGrams: number("addedSugarGrams"), sodiumMilligrams: number("sodiumMilligrams"), confidence: number("confidence", 1), imageJPEG: f["imageJPEG"]?.dataValue, notes: text("notes")); x.id = uuid("id"); context.insert(x)
            case "nutrientGoal":
                context.insert(KoiNutrientGoal(key: text("key"), name: text("name"), unit: text("unit"), goal: number("goal"), step: number("step", 1), goalType: text("goalType", "reach"), isActive: bool("isActive", true)))
            case "nutrientEntry":
                let x = KoiNutrientEntry(date: dateFromDayID(text("dayID")), nutrientKey: text("nutrientKey"), value: number("value")); x.dayID = text("dayID"); x.id = text("id"); context.insert(x)
            case "supplement":
                let x = KoiSupplement(name: text("name"), isActive: bool("isActive", true)); x.id = uuid("id"); context.insert(x)
            case "supplementLog":
                let x = KoiSupplementLog(supplementID: uuid("supplementID"), date: dateFromDayID(text("dayID")), isTaken: bool("isTaken")); x.dayID = text("dayID"); x.id = text("id"); context.insert(x)
            case "movementGoal":
                context.insert(KoiMovementGoal(stepGoal: int("stepGoal", 8_000), weeklyWorkoutGoal: int("weeklyWorkoutGoal", 4), healthEnabled: bool("healthEnabled")))
            case "movementDay":
                let x = KoiMovementDay(date: date("date"), healthSteps: f["healthSteps"]?.integerValue, manualStepAdjustment: int("manualStepAdjustment"), healthWorkoutCount: int("healthWorkoutCount"), didManuallyTrain: bool("didManuallyTrain")); x.dayID = text("dayID", x.dayID); context.insert(x)
            case "routine":
                let x = KoiWorkoutRoutine(name: text("name"), muscleGroup: text("muscleGroup"), createdAt: date("createdAt"), plannedAt: f["plannedAt"]?.dateValue); x.id = uuid("id"); context.insert(x)
            case "routineLift":
                let x = KoiRoutineLift(routineID: uuid("routineID"), name: text("name"), muscleGroup: text("muscleGroup"), targetSets: int("targetSets", 3), targetReps: int("targetReps", 8), order: int("order"), restSeconds: int("restSeconds", 90)); x.id = uuid("id"); context.insert(x)
            case "workoutSession":
                let x = KoiWorkoutSession(name: text("name"), muscleGroup: text("muscleGroup"), routineID: optionalUUID("routineID"), startedAt: date("startedAt")); x.id = uuid("id"); x.endedAt = f["endedAt"]?.dateValue; x.restUntil = f["restUntil"]?.dateValue; x.isComplete = bool("isComplete"); context.insert(x)
            case "workoutLift":
                let x = KoiWorkoutLift(sessionID: uuid("sessionID"), name: text("name"), muscleGroup: text("muscleGroup"), order: int("order"), targetSets: int("targetSets", 3), targetReps: int("targetReps", 8), restSeconds: int("restSeconds", 90)); x.id = uuid("id"); context.insert(x)
            case "workoutSet":
                let x = KoiWorkoutSet(sessionID: uuid("sessionID"), liftID: uuid("liftID"), loggedAt: date("loggedAt"), weightLB: number("weightLB"), reps: int("reps"), isWarmUp: bool("isWarmUp"), isBodyweight: bool("isBodyweight")); x.id = uuid("id"); context.insert(x)
            case "cardioSession":
                let x = KoiCardioSession(activity: text("activity"), detail: text("detail"), startedAt: date("startedAt"), durationSeconds: int("durationSeconds"), distanceMeters: number("distanceMeters")); x.id = uuid("id"); x.endedAt = f["endedAt"]?.dateValue; x.routeData = f["routeData"]?.dataValue; x.mileSplitsData = f["mileSplitsData"]?.dataValue; x.isComplete = bool("isComplete"); context.insert(x)
            default: throw BackupError.invalidArchive
            }
        }
        try context.save()
    }

    private func dateFromDayID(_ value: String) -> Date {
        let parts = value.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return .now }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .autoupdatingCurrent
        return calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2])) ?? .now
    }

    private func deleteAll<T: PersistentModel>(_ type: T.Type, from context: ModelContext) throws {
        for model in try context.fetch(FetchDescriptor<T>()) { context.delete(model) }
    }
}

@MainActor
final class BackupService: BackupProviding {
    private let container = CKContainer(identifier: "iCloud.com.alexandertarica.koi")
    private let logger = Logger(subsystem: "com.alexandertarica.koi", category: "Backup")
    private let recordID = CKRecord.ID(recordName: "latest-koi-backup")

    func hasBackup() async throws -> Bool {
        guard try await container.accountStatus() == .available else { return false }
        do { _ = try await container.privateCloudDatabase.record(for: recordID); return true }
        catch let error as CKError where error.code == .unknownItem { return false }
    }

    func backup(using context: ModelContext) async throws -> Date {
        guard try await container.accountStatus() == .available else { throw BackupError.accountUnavailable }
        let now = Date.now
        let archive = try KoiBackupArchive.capture(context, createdAt: now)
        let data = try JSONEncoder().encode(archive)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("koi-backup-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        try data.write(to: url, options: .atomic)

        let database = container.privateCloudDatabase
        let record: CKRecord
        if let existing = try? await database.record(for: recordID) { record = existing }
        else { record = CKRecord(recordType: "KoiPrivateBackup", recordID: recordID) }
        record["archive"] = CKAsset(fileURL: url)
        record["updatedAt"] = now as CKRecordValue
        record["schemaVersion"] = 1 as CKRecordValue
        _ = try await database.save(record)
        return now
    }

    func restore(using context: ModelContext) async throws -> Date {
        guard try await container.accountStatus() == .available else { throw BackupError.accountUnavailable }
        let record: CKRecord
        do { record = try await container.privateCloudDatabase.record(for: recordID) }
        catch let error as CKError where error.code == .unknownItem { throw BackupError.noBackup }
        guard let asset = record["archive"] as? CKAsset, let url = asset.fileURL,
              let data = try? Data(contentsOf: url), let archive = try? JSONDecoder().decode(KoiBackupArchive.self, from: data) else {
            throw BackupError.invalidArchive
        }
        try archive.restore(into: context)
        return archive.createdAt
    }
}
