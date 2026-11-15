import CloudKit
import Foundation

enum PondServiceError: LocalizedError, Equatable {
    case noAccount
    case offline
    case invalidUsername
    case usernameTaken
    case profileMissing
    case friendNotFound
    case cannotAddSelf
    case activeSprintExists
    case invalidSprint
    case unavailable

    var errorDescription: String? {
        switch self {
        case .noAccount: "Sign in to iCloud in Settings to use Your Koi Pond."
        case .offline: "You're offline. Showing saved pond data. Try again when you're back online."
        case .invalidUsername: "Use 3–20 letters, numbers, or underscores."
        case .usernameTaken: "That username is taken. Try another one."
        case .profileMissing: "Your pond profile could not be found. Try again."
        case .friendNotFound: "No one has that username yet. Check the spelling and try again."
        case .cannotAddSelf: "Add a friend with a different username."
        case .activeSprintExists: "Your pond already has an active sprint."
        case .invalidSprint: "Choose at least one pillar and a future end date."
        case .unavailable: "Your pond is taking a pause. Try again."
        }
    }
}

@MainActor
protocol PondService: AnyObject {
    var cachedSnapshot: PondSnapshot? { get }
    var currentUsername: String? { get }

    func usernameIsAvailable(_ username: String) async throws -> Bool
    func load() async throws -> PondSnapshot?
    func createProfile(username: String, displayName: String) async throws -> PondSnapshot
    func addFriend(username: String) async throws -> PondSnapshot
    func startSprint(pillars: Set<PondPillar>, endDate: Date, rule: String) async throws -> PondSnapshot
    func upsertDailyScore(_ score: PondDailyScore) async throws
}

@MainActor
final class CloudKitPondService: PondService {
    private let container: CKContainer
    private let database: CKDatabase
    private let defaults: UserDefaults
    private let usernameKey = "koi.pond.username"
    private let cacheKey = "koi.pond.cache"

    init(container: CKContainer = CKContainer(identifier: "iCloud.com.alexandertarica.koi"), defaults: UserDefaults = .standard) {
        self.container = container
        self.database = container.publicCloudDatabase
        self.defaults = defaults
    }

    var currentUsername: String? { defaults.string(forKey: usernameKey) }

    var cachedSnapshot: PondSnapshot? {
        guard let data = defaults.data(forKey: cacheKey) else { return nil }
        return try? JSONDecoder().decode(PondSnapshot.self, from: data)
    }

    func usernameIsAvailable(_ username: String) async throws -> Bool {
        let clean = username.trimmingCharacters(in: .whitespacesAndNewlines)
        guard PondEngine.isValidUsername(clean) else { throw PondServiceError.invalidUsername }
        try await requireAccount()
        do {
            _ = try await database.record(for: profileID(clean))
            return false
        } catch let error as CKError where error.code == .unknownItem {
            return true
        } catch {
            throw Self.map(error)
        }
    }

    func load() async throws -> PondSnapshot? {
        try await requireAccount()
        guard let username = currentUsername else { return nil }
        do {
            let profile = try await database.record(for: profileID(username))
            guard let pondRef = profile["pondRef"] as? CKRecord.Reference else { throw PondServiceError.profileMissing }
            let pond = try await database.record(for: pondRef.recordID)
            var usernames = (pond["memberUsernames"] as? [String] ?? []).map { $0.lowercased() }
            if !usernames.contains(username.lowercased()) { usernames.insert(username.lowercased(), at: 0) }
            let members = await fetchMembers(usernames)
            let sprint = try await fetchSprint(from: pond)
            let scores = try await fetchScores(usernames: usernames, sprint: sprint)
            let snapshot = PondSnapshot(
                currentUsername: username.lowercased(),
                name: pond["name"] as? String ?? "Your Koi Pond",
                members: members,
                sprint: sprint,
                dailyScores: scores
            )
            cache(snapshot)
            return snapshot
        } catch {
            throw Self.map(error)
        }
    }

    func createProfile(username: String, displayName: String) async throws -> PondSnapshot {
        let clean = username.trimmingCharacters(in: .whitespacesAndNewlines)
        guard PondEngine.isValidUsername(clean) else { throw PondServiceError.invalidUsername }
        try await requireAccount()
        let ownerID: CKRecord.ID
        do { ownerID = try await container.userRecordID() }
        catch { throw Self.map(error) }

        let profileRecordID = profileID(clean)
        if let existing = try await existingRecord(profileRecordID) {
            if existing["owner"] as? String == ownerID.recordName {
                defaults.set(clean.lowercased(), forKey: usernameKey)
                if let snapshot = try await load() { return snapshot }
            }
            throw PondServiceError.usernameTaken
        }

        let pondID = CKRecord.ID(recordName: "pond-\(UUID().uuidString.lowercased())")
        let pondName = displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "\(clean)'s pond"
            : "\(displayName.trimmingCharacters(in: .whitespacesAndNewlines))'s pond"
        let pondRecord = CKRecord(recordType: "Pond", recordID: pondID)
        pondRecord["name"] = pondName as CKRecordValue
        pondRecord["memberUsernames"] = [clean.lowercased()] as CKRecordValue
        pondRecord["ownerUsername"] = clean.lowercased() as CKRecordValue

        let profileRecord = CKRecord(recordType: "Profile", recordID: profileRecordID)
        profileRecord["username"] = clean.lowercased() as CKRecordValue
        profileRecord["displayName"] = (displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? clean : displayName) as CKRecordValue
        profileRecord["owner"] = ownerID.recordName as CKRecordValue
        profileRecord["pondRef"] = CKRecord.Reference(recordID: pondID, action: .none)

        do {
            _ = try await database.save(pondRecord)
            do { _ = try await database.save(profileRecord) }
            catch {
                _ = try? await database.deleteRecord(withID: pondID)
                throw error
            }
            defaults.set(clean.lowercased(), forKey: usernameKey)
            guard let snapshot = try await load() else { throw PondServiceError.profileMissing }
            return snapshot
        } catch {
            throw Self.map(error)
        }
    }

    func addFriend(username: String) async throws -> PondSnapshot {
        guard let ownUsername = currentUsername else { throw PondServiceError.profileMissing }
        let friend = username.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard PondEngine.isValidUsername(friend) else { throw PondServiceError.invalidUsername }
        guard friend != ownUsername.lowercased() else { throw PondServiceError.cannotAddSelf }
        try await requireAccount()
        do {
            _ = try await database.record(for: profileID(friend))
            let profile = try await database.record(for: profileID(ownUsername))
            guard let pondRef = profile["pondRef"] as? CKRecord.Reference else { throw PondServiceError.profileMissing }
            let pond = try await database.record(for: pondRef.recordID)
            var members = (pond["memberUsernames"] as? [String] ?? []).map { $0.lowercased() }
            if !members.contains(friend) {
                members.append(friend)
                pond["memberUsernames"] = members as CKRecordValue
                _ = try await database.save(pond)
            }
            guard let snapshot = try await load() else { throw PondServiceError.profileMissing }
            return snapshot
        } catch let error as CKError where error.code == .unknownItem {
            throw PondServiceError.friendNotFound
        } catch {
            throw Self.map(error)
        }
    }

    func startSprint(pillars: Set<PondPillar>, endDate: Date, rule: String) async throws -> PondSnapshot {
        guard !pillars.isEmpty, endDate > .now, let username = currentUsername else { throw PondServiceError.invalidSprint }
        try await requireAccount()
        do {
            let profile = try await database.record(for: profileID(username))
            guard let pondRef = profile["pondRef"] as? CKRecord.Reference else { throw PondServiceError.profileMissing }
            let pond = try await database.record(for: pondRef.recordID)
            if let activeRef = pond["activeSprintRef"] as? CKRecord.Reference,
               let existing = try await existingRecord(activeRef.recordID),
               let activeEnd = existing["endDate"] as? Date,
               activeEnd > .now {
                throw PondServiceError.activeSprintExists
            }

            let sprintID = CKRecord.ID(recordName: "sprint-\(UUID().uuidString.lowercased())")
            let sprint = CKRecord(recordType: "Sprint", recordID: sprintID)
            sprint["pondRef"] = CKRecord.Reference(recordID: pondRef.recordID, action: .none)
            sprint["pillars"] = pillars.map(\.rawValue).sorted() as CKRecordValue
            sprint["startDate"] = Date.now as CKRecordValue
            sprint["endDate"] = endDate as CKRecordValue
            let cleanRule = String(rule.trimmingCharacters(in: .whitespacesAndNewlines).prefix(120))
            sprint["rule"] = cleanRule as CKRecordValue
            sprint["createdBy"] = username.lowercased() as CKRecordValue
            _ = try await database.save(sprint)

            pond["activeSprintRef"] = CKRecord.Reference(recordID: sprintID, action: .none)
            do { _ = try await database.save(pond) }
            catch {
                _ = try? await database.deleteRecord(withID: sprintID)
                throw error
            }
            guard let snapshot = try await load() else { throw PondServiceError.profileMissing }
            return snapshot
        } catch {
            throw Self.map(error)
        }
    }

    func upsertDailyScore(_ score: PondDailyScore) async throws {
        guard let username = currentUsername, score.username.lowercased() == username.lowercased() else { return }
        try await requireAccount()
        let id = scoreID(username: username, dayKey: score.dayKey)
        do {
            let record = try await existingRecord(id) ?? CKRecord(recordType: "DailyScore", recordID: id)
            record["username"] = username.lowercased() as CKRecordValue
            record["dayKey"] = score.dayKey as CKRecordValue
            record["date"] = Calendar.autoupdatingCurrent.startOfDay(for: Date.now) as CKRecordValue
            record["habits"] = score.habits as CKRecordValue
            record["nutrition"] = score.nutrition as CKRecordValue
            record["exercise"] = score.exercise as CKRecordValue
            _ = try await database.save(record)
            if var snapshot = cachedSnapshot {
                snapshot.dailyScores.removeAll { $0.id == score.id }
                snapshot.dailyScores.append(score)
                cache(snapshot)
            }
        } catch {
            throw Self.map(error)
        }
    }

    private func requireAccount() async throws {
        do {
            guard try await container.accountStatus() == .available else { throw PondServiceError.noAccount }
        } catch {
            throw Self.map(error)
        }
    }

    private func profileID(_ username: String) -> CKRecord.ID {
        CKRecord.ID(recordName: "user-\(username.lowercased())")
    }

    private func scoreID(username: String, dayKey: String) -> CKRecord.ID {
        CKRecord.ID(recordName: "score-\(username.lowercased())-\(dayKey)")
    }

    private func existingRecord(_ id: CKRecord.ID) async throws -> CKRecord? {
        do { return try await database.record(for: id) }
        catch let error as CKError where error.code == .unknownItem { return nil }
        catch { throw Self.map(error) }
    }

    private func fetchMembers(_ usernames: [String]) async -> [PondMember] {
        var members: [PondMember] = []
        for username in usernames {
            guard let record = try? await database.record(for: profileID(username)) else {
                members.append(PondMember(username: username, displayName: username))
                continue
            }
            members.append(PondMember(
                username: username,
                displayName: record["displayName"] as? String ?? username
            ))
        }
        return members.sorted { $0.username.localizedCaseInsensitiveCompare($1.username) == .orderedAscending }
    }

    private func fetchSprint(from pond: CKRecord) async throws -> PondSprint? {
        guard let reference = pond["activeSprintRef"] as? CKRecord.Reference else { return nil }
        guard let record = try await existingRecord(reference.recordID) else { return nil }
        let pillars = Set((record["pillars"] as? [String] ?? []).compactMap(PondPillar.init(rawValue:)))
        guard let startDate = record["startDate"] as? Date,
              let endDate = record["endDate"] as? Date,
              let createdBy = record["createdBy"] as? String else { return nil }
        return PondSprint(
            recordName: record.recordID.recordName,
            pillars: pillars,
            startDate: startDate,
            endDate: endDate,
            rule: record["rule"] as? String ?? "",
            createdBy: createdBy
        )
    }

    private func fetchScores(usernames: [String], sprint: PondSprint?) async throws -> [PondDailyScore] {
        guard let sprint else { return [] }
        let through = min(Date.now, sprint.endDate)
        let days = PondEngine.dateKeys(from: sprint.startDate, through: through)
        var scores: [PondDailyScore] = []
        for username in usernames {
            for day in days {
                guard let record = try await existingRecord(scoreID(username: username, dayKey: day)) else { continue }
                scores.append(PondDailyScore(
                    username: record["username"] as? String ?? username,
                    dayKey: record["dayKey"] as? String ?? day,
                    habits: record["habits"] as? Double ?? 0,
                    nutrition: record["nutrition"] as? Double ?? 0,
                    exercise: record["exercise"] as? Double ?? 0
                ))
            }
        }
        return scores
    }

    private func cache(_ snapshot: PondSnapshot) {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        defaults.set(data, forKey: cacheKey)
    }

    private static func map(_ error: Error) -> PondServiceError {
        if let pondError = error as? PondServiceError { return pondError }
        guard let cloudError = error as? CKError else { return .unavailable }
        return switch cloudError.code {
        case .notAuthenticated, .accountTemporarilyUnavailable: .noAccount
        case .networkUnavailable, .networkFailure, .serviceUnavailable, .requestRateLimited, .serverResponseLost, .zoneBusy: .offline
        case .serverRecordChanged: .activeSprintExists
        case .unknownItem: .friendNotFound
        default: .unavailable
        }
    }
}

@MainActor
final class InMemoryPondService: PondService {
    private(set) var cachedSnapshot: PondSnapshot?
    private(set) var currentUsername: String?
    private var knownProfiles: [String: PondMember]

    init(snapshot: PondSnapshot? = nil, knownProfiles: [PondMember] = []) {
        self.cachedSnapshot = snapshot
        self.currentUsername = snapshot?.currentUsername
        self.knownProfiles = Dictionary(uniqueKeysWithValues: (snapshot?.members ?? []).map { ($0.username.lowercased(), $0) })
        for profile in knownProfiles { self.knownProfiles[profile.username.lowercased()] = profile }
    }

    static func demo(now: Date = .now, calendar: Calendar = .autoupdatingCurrent) -> InMemoryPondService {
        let members = [
            PondMember(username: "alex", displayName: "Alex"),
            PondMember(username: "maya", displayName: "Maya"),
            PondMember(username: "jordan", displayName: "Jordan"),
            PondMember(username: "sam", displayName: "Sam"),
            PondMember(username: "riley", displayName: "Riley"),
        ]
        let start = calendar.date(byAdding: .day, value: -4, to: now) ?? now
        let sprint = PondSprint(
            recordName: "sprint-demo",
            pillars: [.habits, .nutrition, .exercise],
            startDate: start,
            endDate: PondEngine.nextThursday(after: now, calendar: calendar),
            rule: "Losers buy the winner a coffee",
            createdBy: "maya"
        )
        let values: [(Double, Double, Double)] = [(0.88, 0.91, 0.82), (0.80, 0.78, 0.75), (0.82, 0.80, 0.80), (0.66, 0.72, 0.68), (0.72, 0.70, 0.70)]
        var scores: [PondDailyScore] = []
        for offset in 0...4 {
            guard let date = calendar.date(byAdding: .day, value: offset - 4, to: now) else { continue }
            for (index, member) in members.enumerated() {
                let value = values[index]
                let variance = Double((offset + index) % 3) * 0.025
                scores.append(PondDailyScore(username: member.username, date: date, habits: value.0 - variance, nutrition: value.1 - variance, exercise: value.2 - variance, calendar: calendar))
            }
        }
        let snapshot = PondSnapshot(currentUsername: "maya", name: "Maya's pond", members: members, sprint: sprint, dailyScores: scores)
        return InMemoryPondService(snapshot: snapshot)
    }

    func usernameIsAvailable(_ username: String) async throws -> Bool {
        guard PondEngine.isValidUsername(username) else { throw PondServiceError.invalidUsername }
        return knownProfiles[username.lowercased()] == nil
    }

    func load() async throws -> PondSnapshot? { cachedSnapshot }

    func createProfile(username: String, displayName: String) async throws -> PondSnapshot {
        let clean = username.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard PondEngine.isValidUsername(clean) else { throw PondServiceError.invalidUsername }
        guard knownProfiles[clean] == nil else { throw PondServiceError.usernameTaken }
        let shownName = displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? clean : displayName
        let member = PondMember(username: clean, displayName: shownName)
        let snapshot = PondSnapshot(currentUsername: clean, name: "\(shownName)'s pond", members: [member], sprint: nil, dailyScores: [])
        knownProfiles[clean] = member
        currentUsername = clean
        cachedSnapshot = snapshot
        return snapshot
    }

    func addFriend(username: String) async throws -> PondSnapshot {
        guard var snapshot = cachedSnapshot, let own = currentUsername else { throw PondServiceError.profileMissing }
        let friend = username.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard friend != own.lowercased() else { throw PondServiceError.cannotAddSelf }
        guard let member = knownProfiles[friend] else { throw PondServiceError.friendNotFound }
        if !snapshot.members.contains(where: { $0.username.lowercased() == friend }) { snapshot.members.append(member) }
        cachedSnapshot = snapshot
        return snapshot
    }

    func startSprint(pillars: Set<PondPillar>, endDate: Date, rule: String) async throws -> PondSnapshot {
        guard !pillars.isEmpty, endDate > .now, var snapshot = cachedSnapshot, let username = currentUsername else { throw PondServiceError.invalidSprint }
        if let sprint = snapshot.sprint, sprint.endDate > .now { throw PondServiceError.activeSprintExists }
        snapshot.sprint = PondSprint(
            recordName: "sprint-\(UUID().uuidString.lowercased())",
            pillars: pillars,
            startDate: .now,
            endDate: endDate,
            rule: String(rule.trimmingCharacters(in: .whitespacesAndNewlines).prefix(120)),
            createdBy: username.lowercased()
        )
        snapshot.dailyScores.removeAll()
        cachedSnapshot = snapshot
        return snapshot
    }

    func upsertDailyScore(_ score: PondDailyScore) async throws {
        guard let username = currentUsername, score.username.lowercased() == username.lowercased(), var snapshot = cachedSnapshot else { return }
        snapshot.dailyScores.removeAll { $0.id == score.id }
        snapshot.dailyScores.append(score)
        cachedSnapshot = snapshot
    }
}
