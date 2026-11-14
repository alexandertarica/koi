import CoreLocation
import KoiShared
import MapKit
import SwiftData
import SwiftUI

struct CardioJournalView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.runTracker) private var tracker
    @Environment(\.analyticsProvider) private var analyticsProvider
    @State private var model = CardioViewModel()
    @State private var showsManualEntry = false
    @State private var selectedActivity = "Class"
    @State private var selectedSession: KoiCardioSession?
    @State private var minutes = "30"
    @State private var miles = "3"
    @State private var detail = "Pilates"
    @State private var treadmillMiles = "0"

    private let classTypes = ["Pilates", "Yoga", "Spin", "HIIT", "Barre", "Boxing", "Dance", "Stretch"]
    private let otherTypes = ["Swim", "Hike", "Bike"]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: KoiTheme.space.s34) {
                runHero
                activityTiles
                if model.activeSession?.activity == "Treadmill" { treadmillSession }
                if !model.usualActivities.isEmpty { usualActivities }
                weeklyOverview
                mileageTrend
                bests
                if !model.activityCounts.isEmpty { activityList }
                if !model.recentSessions.isEmpty { recentSessions }
            }
            .padding(.horizontal, KoiTheme.space.s21)
            .padding(.vertical, KoiTheme.space.s21)
        }
        .background(KoiBackground().ignoresSafeArea())
        .foregroundStyle(KoiTheme.onBase)
        .task {
            if let tracker { model.load(context, tracker: tracker) }
        }
        .onChange(of: treadmillMiles) { _, value in model.setTreadmillDistance(miles: Double(value) ?? 0) }
        .sheet(isPresented: $showsManualEntry) { manualEntrySheet.presentationDetents([.medium, .large]) }
        .sheet(item: $selectedSession) { session in CardioSessionDetail(session: session, model: model).presentationDetents([.medium, .large]) }
        .alert("Cardio", isPresented: Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.clearError() } })) {
            Button("OK", role: .cancel) { model.clearError() }
        } message: { Text(model.errorMessage ?? "") }
    }

    private var runHero: some View {
        VStack(alignment: .leading, spacing: KoiTheme.space.s13) {
            HStack {
                VStack(alignment: .leading, spacing: KoiTheme.space.s5) {
                    Text("OUTDOOR RUN").font(KoiTheme.section).tracking(1.8)
                    Text("Find your pace.").font(KoiTheme.title)
                }
                Spacer()
                Image(systemName: "location.north.line").font(.system(size: 23, weight: .ultraLight))
            }
            if model.activeSession?.activity == "Outdoor run" {
                HStack(alignment: .firstTextBaseline, spacing: KoiTheme.space.s21) {
                    metric(model.liveDistanceMeters / 1_609.344, suffix: "mi", digits: 2)
                    metric(Double(model.elapsedSeconds) / 60, suffix: "min", digits: 0)
                    VStack(alignment: .leading, spacing: KoiTheme.space.s5) {
                        Text(model.livePaceSecondsPerMile.map(formatPace) ?? "—").font(KoiTheme.body)
                        Text("MIN / MI").font(KoiTheme.caption).tracking(0.7).opacity(0.68)
                    }
                }
                if model.liveRoute.count > 1 { RoutePreview(points: model.liveRoute).frame(height: 106) }
                HStack(spacing: KoiTheme.space.s8) {
                    KoiPrimaryButton(title: model.isTrackingRun ? "Finish run" : "Resume run") {
                        if model.isTrackingRun {
                            KoiHaptics.success()
                            model.finishActiveSession()
                            analyticsProvider.signal("Cardio.logged", parameters: ["activity": "outdoor_run"])
                        }
                        else { KoiHaptics.tap(); Task { await model.resumeOutdoorRun() } }
                    }
                    Button("Discard") { KoiHaptics.tap(); model.discardActiveSession() }.font(KoiTheme.caption).buttonStyle(.plain)
                }
            } else {
                Text("A quiet route, recorded as you move.").font(KoiTheme.caption).opacity(0.75)
                KoiPrimaryButton(title: "Start run") {
                    KoiHaptics.tap()
                    Task {
                        await model.startOutdoorRun()
                        if model.activeSession != nil { analyticsProvider.signal("Cardio.runStarted", parameters: ["kind": "outdoor"]) }
                    }
                }
            }
        }
        .padding(KoiTheme.space.s21)
        .background(.ultraThinMaterial.opacity(0.28), in: RoundedRectangle(cornerRadius: 22))
        .overlay(RoundedRectangle(cornerRadius: 22).stroke(KoiTheme.onBase.opacity(0.22), lineWidth: 1))
    }

    private var activityTiles: some View {
        HStack(spacing: KoiTheme.space.s8) {
            activityTile("Treadmill", hint: "Distance + time", symbol: "figure.run") {
                if model.activeSession == nil { KoiHaptics.tap(); treadmillMiles = "0"; model.startTreadmill(); analyticsProvider.signal("Cardio.runStarted", parameters: ["kind": "treadmill"]) }
            }
            activityTile("Class", hint: "Minutes only", symbol: "figure.cooldown") { openManual("Class", defaultDetail: "Pilates") }
            Menu {
                ForEach(otherTypes, id: \.self) { type in Button(type) { openManual(type) } }
            } label: { tileLabel("Other", hint: "Swim, hike, bike", symbol: "figure.outdoor.cycle") }.buttonStyle(.plain)
        }.disabled(model.activeSession != nil)
    }

    private var treadmillSession: some View {
        VStack(alignment: .leading, spacing: KoiTheme.space.s13) {
            Text("TREADMILL · IN PROGRESS").font(KoiTheme.section).tracking(1.5)
            TimelineView(.periodic(from: .now, by: 1)) { date in
                Text(clockString(max(model.elapsedSeconds, Int(date.date.timeIntervalSince(model.activeSession?.startedAt ?? date.date))))).font(KoiTheme.title).monospacedDigit()
            }
            HStack {
                TextField("Miles", text: $treadmillMiles).keyboardType(.decimalPad).font(KoiTheme.body).frame(width: 88)
                Text("mi · \(paceFromMiles)").font(KoiTheme.caption).opacity(0.75)
                Spacer()
                Button("Finish") { KoiHaptics.success(); model.finishActiveSession(); analyticsProvider.signal("Cardio.logged", parameters: ["activity": "treadmill"]) }.font(KoiTheme.caption).buttonStyle(.plain)
            }
            Button("Discard session", role: .destructive) { KoiHaptics.tap(); model.discardActiveSession() }.font(KoiTheme.caption).buttonStyle(.plain)
        }.padding(KoiTheme.space.s13).background(.ultraThinMaterial.opacity(0.22), in: RoundedRectangle(cornerRadius: 16))
    }

    private var usualActivities: some View {
        VStack(alignment: .leading, spacing: KoiTheme.space.s13) {
            Text("USUAL ACTIVITIES").font(KoiTheme.section).tracking(1.8)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: KoiTheme.space.s8) {
                    ForEach(model.usualActivities, id: \.self) { name in
                        Button(name) { model.repeatActivity(name) }.font(KoiTheme.caption).padding(.horizontal, KoiTheme.space.s13).padding(.vertical, KoiTheme.space.s8)
                            .overlay(Capsule().stroke(KoiTheme.onBase.opacity(0.25), lineWidth: 1)).buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private var weeklyOverview: some View {
        VStack(alignment: .leading, spacing: KoiTheme.space.s13) {
            Text("THIS WEEK").font(KoiTheme.section).tracking(1.8)
            HStack(spacing: KoiTheme.space.s21) {
                summaryMetric("\(model.weeklyStats.sessions)", label: "SESSIONS")
                summaryMetric("\(model.weeklyStats.minutes)", label: "MINUTES")
                summaryMetric(String(format: "%.1f", model.weeklyStats.miles), label: "MILES")
            }
        }
    }

    private var mileageTrend: some View {
        VStack(alignment: .leading, spacing: KoiTheme.space.s13) {
            Text("MILES · 8 WEEKS").font(KoiTheme.section).tracking(1.8)
            HStack(alignment: .bottom, spacing: 8) {
                ForEach(model.eightWeekMileage) { week in
                    VStack(spacing: 6) {
                        RoundedRectangle(cornerRadius: 5).fill(KoiTheme.onBase.opacity(week.miles > 0 ? 0.75 : 0.16))
                            .frame(maxWidth: .infinity).frame(height: max(4, CGFloat(week.miles / maxMileage) * 72))
                        Text(week.start.formatted(.dateTime.month(.narrow))).font(KoiTheme.caption).opacity(0.65)
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(week.label), \(String(format: "%.1f", week.miles)) miles")
                }
            }.frame(height: 94, alignment: .bottom)
        }
    }

    private var bests: some View {
        VStack(alignment: .leading, spacing: KoiTheme.space.s13) {
            Text("BESTS").font(KoiTheme.section).tracking(1.8)
            HStack(spacing: KoiTheme.space.s21) {
                summaryMetric(model.longestDistanceMiles > 0 ? String(format: "%.1f", model.longestDistanceMiles) : "—", label: "LONGEST · MI")
                summaryMetric(model.fastestPace.map(formatPace) ?? "—", label: "FASTEST · /MI")
                summaryMetric(model.bestFiveKSeconds.map(clockString) ?? "—", label: "BEST 5K")
            }
        }
    }

    private var activityList: some View {
        VStack(alignment: .leading, spacing: KoiTheme.space.s8) {
            Text("YOUR ACTIVITIES").font(KoiTheme.section).tracking(1.8)
            ForEach(model.activityCounts, id: \.name) { item in
                HStack { Text(item.name).font(KoiTheme.body); Spacer(); Text("\(item.count)").font(KoiTheme.caption).opacity(0.72) }
                    .padding(.vertical, KoiTheme.space.s8)
                    .overlay(alignment: .bottom) { Rectangle().fill(KoiTheme.divider).frame(height: 0.5) }
            }
        }
    }

    private var recentSessions: some View {
        VStack(alignment: .leading, spacing: KoiTheme.space.s8) {
            Text("RECENT").font(KoiTheme.section).tracking(1.8)
            ForEach(model.recentSessions) { session in
                Button { selectedSession = session } label: {
                    HStack(alignment: .center, spacing: KoiTheme.space.s13) {
                        if session.activity == "Outdoor run", !model.route(for: session).isEmpty { RoutePreview(points: model.route(for: session)).frame(width: 70, height: 48) }
                        VStack(alignment: .leading, spacing: 4) {
                            Text(session.detail.isEmpty ? session.activity : session.detail).font(KoiTheme.body)
                            Text(session.startedAt.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())).font(KoiTheme.caption).opacity(0.68)
                        }
                        Spacer()
                        Text(sessionDistanceAndTime(session)).font(KoiTheme.caption).opacity(0.8)
                    }.contentShape(Rectangle()).padding(.vertical, KoiTheme.space.s5)
                }.buttonStyle(.plain)
            }
        }
    }

    private var manualEntrySheet: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: KoiTheme.space.s21) {
                Text("Log an activity.").font(KoiTheme.title)
                Text(selectedActivity.uppercased()).font(KoiTheme.section).tracking(1.5).opacity(0.75)
                if selectedActivity == "Class" {
                    Menu { ForEach(classTypes, id: \.self) { type in Button(type) { detail = type } } } label: { fieldLabel(detail, symbol: "chevron.down") }.buttonStyle(.plain)
                } else { TextField("Activity name", text: $detail).font(KoiTheme.body).padding(KoiTheme.space.s13).background(.ultraThinMaterial.opacity(0.22), in: RoundedRectangle(cornerRadius: 12)) }
                HStack(spacing: KoiTheme.space.s13) {
                    numericField("Minutes", text: $minutes)
                    if selectedActivity != "Class" { numericField("Miles", text: $miles) }
                }
                if selectedActivity != "Class" { Text("Pace · \(paceFromManual)").font(KoiTheme.caption).opacity(0.75) }
                KoiPrimaryButton(title: "Save activity") {
                    model.logManualActivity(activity: selectedActivity, detail: detail, minutes: Int(minutes) ?? 0, miles: selectedActivity == "Class" ? 0 : Double(miles) ?? 0)
                    analyticsProvider.signal("Cardio.logged", parameters: ["activity": selectedActivity.lowercased().replacingOccurrences(of: " ", with: "_")])
                    showsManualEntry = false
                }
                Spacer()
            }.padding(KoiTheme.space.s21).background(KoiBackground().ignoresSafeArea()).foregroundStyle(KoiTheme.onBase)
                .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Close") { showsManualEntry = false }.font(KoiTheme.caption) } }
        }.preferredColorScheme(.dark)
    }

    private func activityTile(_ title: String, hint: String, symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { tileLabel(title, hint: hint, symbol: symbol) }.buttonStyle(.plain)
    }
    private func tileLabel(_ title: String, hint: String, symbol: String) -> some View {
        VStack(alignment: .leading, spacing: KoiTheme.space.s8) {
            Image(systemName: symbol).font(.system(size: 20, weight: .light))
            Text(title).font(KoiTheme.caption)
            Text(hint).font(KoiTheme.caption).opacity(0.68).lineLimit(1).minimumScaleFactor(0.75)
        }.foregroundStyle(KoiTheme.onBase).frame(maxWidth: .infinity, minHeight: 82, alignment: .leading).padding(KoiTheme.space.s8)
            .background(.ultraThinMaterial.opacity(0.22), in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(KoiTheme.onBase.opacity(0.22), lineWidth: 1))
    }
    private func metric(_ value: Double, suffix: String, digits: Int) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(String(format: "%.*f", digits, value)).font(.system(size: 28, weight: .medium, design: .rounded)).monospacedDigit()
            Text(suffix.uppercased()).font(KoiTheme.caption).tracking(0.8).opacity(0.68)
        }
    }
    private func summaryMetric(_ value: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: KoiTheme.space.s5) {
            Text(value).font(.system(size: 22, weight: .medium, design: .rounded)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.65)
            Text(label).font(KoiTheme.caption).tracking(0.5).opacity(0.68)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
    private func openManual(_ activity: String, defaultDetail: String? = nil) {
        selectedActivity = activity
        detail = defaultDetail ?? activity
        minutes = activity == "Class" ? "45" : "30"
        miles = "3"
        showsManualEntry = true
    }
    private func numericField(_ title: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title.uppercased()).font(KoiTheme.caption).tracking(0.8).opacity(0.68)
            TextField(title, text: text).keyboardType(.decimalPad).font(KoiTheme.body).padding(KoiTheme.space.s13)
                .background(.ultraThinMaterial.opacity(0.22), in: RoundedRectangle(cornerRadius: 12))
        }.frame(maxWidth: .infinity)
    }
    private func fieldLabel(_ value: String, symbol: String) -> some View {
        HStack { Text(value); Spacer(); Image(systemName: symbol) }.font(KoiTheme.body).padding(KoiTheme.space.s13).background(.ultraThinMaterial.opacity(0.22), in: RoundedRectangle(cornerRadius: 12))
    }
    private var maxMileage: Double { max(model.eightWeekMileage.map(\.miles).max() ?? 0, 1) }
    private var paceFromMiles: String { pace(miles: Double(treadmillMiles) ?? 0, minutes: model.elapsedSeconds / 60) }
    private var paceFromManual: String { pace(miles: Double(miles) ?? 0, minutes: Int(minutes) ?? 0) }
    private func pace(miles: Double, minutes: Int) -> String {
        guard miles > 0, minutes > 0 else { return "— /mi" }
        return "\(formatPace(Double(minutes * 60) / miles)) /mi"
    }
    private func formatPace(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds > 0 else { return "—" }
        return String(format: "%d:%02d", Int(seconds) / 60, Int(seconds) % 60)
    }
    private func clockString(_ seconds: Int) -> String { String(format: "%d:%02d", max(seconds, 0) / 60, max(seconds, 0) % 60) }
    private func sessionDistanceAndTime(_ session: KoiCardioSession) -> String {
        let miles = session.distanceMeters / 1_609.344
        let distance = miles > 0 ? String(format: "%.1f mi", miles) : "\(session.durationSeconds / 60) min"
        return distance
    }
}

private struct CardioSessionDetail: View {
    @Environment(\.dismiss) private var dismiss
    let session: KoiCardioSession
    let model: CardioViewModel

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: KoiTheme.space.s21) {
                    Text(session.detail.isEmpty ? session.activity : session.detail).font(KoiTheme.title)
                    Text(session.startedAt.formatted(.dateTime.weekday(.wide).month(.wide).day().hour().minute())).font(KoiTheme.caption).opacity(0.7)
                    if !model.route(for: session).isEmpty { RouteMap(points: model.route(for: session)).frame(height: 260).clipShape(RoundedRectangle(cornerRadius: 18)) }
                    HStack(spacing: KoiTheme.space.s21) {
                        Text(String(format: "%.2f mi", session.distanceMeters / 1_609.344))
                        Text("\(session.durationSeconds / 60) min")
                        Text(session.paceSecondsPerMile.map { "\(String(format: "%d:%02d", Int($0) / 60, Int($0) % 60)) /mi" } ?? "")
                    }.font(KoiTheme.body)
                    if !model.mileSplits(for: session).isEmpty {
                        Text("MILE SPLITS").font(KoiTheme.section).tracking(1.5)
                        ForEach(Array(model.mileSplits(for: session).enumerated()), id: \.offset) { index, seconds in
                            HStack { Text("Mile \(index + 1)"); Spacer(); Text(String(format: "%d:%02d", seconds / 60, seconds % 60)) }.font(KoiTheme.body)
                        }
                    }
                }.padding(KoiTheme.space.s21)
            }.background(KoiBackground().ignoresSafeArea()).foregroundStyle(KoiTheme.onBase)
                .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() }.font(KoiTheme.caption) } }
        }.preferredColorScheme(.dark)
    }
}

private struct RoutePreview: View {
    let points: [RunLocationPoint]
    var body: some View {
        GeometryReader { geometry in
            routePath(in: geometry.size).stroke(KoiTheme.onBase.opacity(0.85), style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
        }.accessibilityLabel("Run route preview")
    }
    private func routePath(in size: CGSize) -> Path {
        guard points.count > 1 else { return Path() }
        let latitudes = points.map(\.latitude)
        let longitudes = points.map(\.longitude)
        let minLat = latitudes.min() ?? 0, maxLat = latitudes.max() ?? 0
        let minLon = longitudes.min() ?? 0, maxLon = longitudes.max() ?? 0
        let latRange = max(maxLat - minLat, 0.00001), lonRange = max(maxLon - minLon, 0.00001)
        return Path { path in
            for (index, point) in points.enumerated() {
                let pointInView = CGPoint(x: 6 + (point.longitude - minLon) / lonRange * max(size.width - 12, 1), y: 6 + (maxLat - point.latitude) / latRange * max(size.height - 12, 1))
                if index == 0 { path.move(to: pointInView) } else { path.addLine(to: pointInView) }
            }
        }
    }
}

private struct RouteMap: View {
    let points: [RunLocationPoint]
    var body: some View {
        let coordinates = points.map { CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude) }
        Map {
            if coordinates.count > 1 { MapPolyline(coordinates: coordinates).stroke(.cyan, lineWidth: 5) }
        }.mapControlVisibility(.hidden)
    }
}
