import PhotosUI
import SwiftData
import SwiftUI
import UIKit
import KoiShared
import Charts

struct KoiProfileView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.notificationProvider) private var notificationProvider
    @Environment(\.calendarProvider) private var calendarProvider
    @Environment(\.backupProvider) private var backupProvider
    @State private var model = ProfileViewModel()
    @State private var openSection: String? = "Body weight"
    @State private var photoItem: PhotosPickerItem?
    @State private var presentsTour = false
    @State private var confirmsRestore = false
    @State private var showsWeightHistory = false
    let onSelectTab: (KoiTab) -> Void
    let onPresentSmartNote: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: KoiTheme.space.s21) {
                    profileHeader
                    Button { presentsTour = true } label: {
                        HStack(spacing: KoiTheme.space.s8) {
                            Image(systemName: "sparkle.magnifyingglass")
                            Text("Replay the tour")
                            Spacer()
                            Image(systemName: "chevron.right").font(.system(size: 11, weight: .light)).opacity(0.65)
                        }
                        .font(KoiTheme.caption)
                        .foregroundStyle(KoiTheme.onBase)
                        .padding(.vertical, KoiTheme.space.s8)
                    }.buttonStyle(.plain)
                    fold("Body weight", summary: model.currentWeight.map { "\(Int($0.rounded())) lb · \(model.weightTrendText)" } ?? "Log a starting point") { bodyWeightSection }
                    fold("Your focus", summary: focusLine(model.focus)) { focusSection }
                    fold("Nutrition goals", summary: model.nutritionGoalSummary) {
                        VStack(alignment: .leading, spacing: KoiTheme.space.s13) {
                            Text("Every meal shapes your daily target.").font(KoiTheme.caption).opacity(0.75)
                            Button("Open Intake") { onSelectTab(.intake) }.font(KoiTheme.caption).buttonStyle(.plain)
                        }
                    }
                    fold("Exercise goals", summary: model.exerciseGoalSummary) { exerciseSection }
                    fold("Notifications", summary: model.notificationMode.title) { notificationSection }
                    fold("Apple Health", summary: model.healthConnected ? "Connected" : "Not connected") { healthSection }
                    fold("Apple Calendar", summary: model.calendarConnected ? "Connected" : "Not connected") { calendarSection }
                    fold("Smart notes", summary: "Write freely from the tab bar") {
                        Text("Turn a short note into a meal estimate, water log, habit check, to-do or workout.")
                            .font(KoiTheme.caption).opacity(0.72)
                    }
                    fold("iCloud backup", summary: backupSummary) { backupSection }
                    fold("Tips & gestures", summary: "A few quiet shortcuts") { tipsSection }
        }
        .foregroundStyle(KoiTheme.onBase)
        .task { model.load(context) }
        .fullScreenCover(isPresented: $presentsTour) {
            KoiTourView(onSelectTab: onSelectTab, onTrySmartNote: onPresentSmartNote, onFinish: { presentsTour = false })
        }
        .onChange(of: photoItem) { _, item in
            guard let item else { return }
            Task {
                guard let data = try? await item.loadTransferable(type: Data.self),
                      let image = UIImage(data: data),
                      let jpeg = image.jpegData(compressionQuality: 0.84) else { return }
                model.setAvatar(jpeg)
            }
        }
        .alert("Profile", isPresented: Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.clearError() } })) {
            Button("OK", role: .cancel) { model.clearError() }
        } message: { Text(model.errorMessage ?? "") }
        .confirmationDialog("Restore Koi?", isPresented: $confirmsRestore, titleVisibility: .visible) {
            Button("Replace this phone's Koi data", role: .destructive) { Task { await model.restoreBackup(using: backupProvider) } }
            Button("Cancel", role: .cancel) {}
        } message: { Text("This replaces the data on this phone with your latest private iCloud backup.") }
        .sheet(isPresented: $showsWeightHistory) {
            WeightHistorySheet(entries: Array(model.weightEntries.reversed()), onDelete: model.deleteWeight)
                .presentationDetents([.large])
        }
        .alert("iCloud backup", isPresented: Binding(get: { model.backupMessage != nil }, set: { if !$0 { model.clearBackupMessage() } })) {
            Button("OK", role: .cancel) { model.clearBackupMessage() }
        } message: { Text(model.backupMessage ?? "") }
    }

    private var profileHeader: some View {
        let avatarJPEG = model.profile?.avatarJPEG
        return HStack(spacing: KoiTheme.space.s13) {
            PhotosPicker(selection: $photoItem, matching: .images) {
                ZStack {
                    Circle().fill(.ultraThinMaterial.opacity(0.35)).frame(width: 64, height: 64)
                    if let data = avatarJPEG, let image = UIImage(data: data) {
                        Image(uiImage: image).resizable().scaledToFill().frame(width: 64, height: 64).clipShape(Circle())
                    } else {
                        Image(systemName: "person.crop.circle").font(.system(size: 36, weight: .ultraLight))
                    }
                }.overlay(Circle().stroke(KoiTheme.onBase.opacity(0.28), lineWidth: 1))
            }.buttonStyle(.plain).accessibilityLabel("Choose profile photo")
            VStack(alignment: .leading, spacing: KoiTheme.space.s5) {
                TextField("Your name", text: $model.nameDraft).font(KoiTheme.title).textInputAutocapitalization(.words).submitLabel(.done).onSubmit { model.saveName() }
                Text("Since \((model.profile?.joinedAt ?? .now).formatted(.dateTime.month(.abbreviated).day()))")
                    .font(KoiTheme.caption).opacity(0.72)
            }
            Spacer(minLength: 0)
            Button("Save") { model.saveName() }.font(KoiTheme.caption).buttonStyle(.plain)
        }
        .padding(KoiTheme.space.s13)
        .background(.ultraThinMaterial.opacity(0.22), in: RoundedRectangle(cornerRadius: 18))
    }

    private var bodyWeightSection: some View {
        VStack(alignment: .leading, spacing: KoiTheme.space.s13) {
            HStack(alignment: .firstTextBaseline) {
                Text(String(format: "%.1f", model.weightDraft)).font(.system(size: 34, weight: .medium, design: .rounded)).monospacedDigit()
                Text("LB").font(KoiTheme.caption).tracking(1.3).opacity(0.72)
                Spacer()
                if model.hasWeightToday { Text("LOGGED TODAY").font(KoiTheme.caption).tracking(1).opacity(0.7) }
            }
            ProfileWeightRuler(value: model.weightDraft) { model.setWeight($0) }
            HStack {
                Text(model.weightTrendText).font(KoiTheme.caption).opacity(0.76)
                Spacer()
                Button { showsWeightHistory = true; KoiHaptics.tap() } label: { Label("History", systemImage: "chart.xyaxis.line").font(KoiTheme.caption) }.buttonStyle(.plain)
                if let previousWeight = model.previousWeight {
                    Button("Same as last") { model.setWeight(previousWeight); KoiHaptics.change() }.font(KoiTheme.caption).buttonStyle(.plain).padding(.leading, KoiTheme.space.s8)
                }
                Button(model.hasWeightToday ? "Update today" : "Log today") { model.saveWeightToday(); KoiHaptics.success() }.font(KoiTheme.caption).buttonStyle(.plain).padding(.leading, KoiTheme.space.s8)
            }
            if model.weightChart.count > 1 {
                WeightTrendChart(entries: model.weightChart).frame(height: 76).padding(.top, KoiTheme.space.s8)
                HStack { Text(model.weightChart.first?.date.formatted(.dateTime.month(.abbreviated).day()) ?? ""); Spacer(); Text(model.weightChart.last?.date.formatted(.dateTime.month(.abbreviated).day()) ?? "") }
                    .font(KoiTheme.caption).opacity(0.56)
            } else {
                Text("Your history will grow with each entry.").font(KoiTheme.caption).opacity(0.64)
            }
        }
    }

    private var focusSection: some View {
        VStack(alignment: .leading, spacing: KoiTheme.space.s8) {
            ForEach(BalanceFocus.allCases, id: \.self) { focus in
                Button { model.setFocus(focus) } label: {
                    HStack(alignment: .center, spacing: KoiTheme.space.s13) {
                        Image(systemName: model.focus == focus ? "largecircle.fill.circle" : "circle").font(.system(size: 17, weight: .light))
                        VStack(alignment: .leading, spacing: 4) {
                            Text(focusLine(focus)).font(KoiTheme.body)
                            Text(focusDescription(focus)).font(KoiTheme.caption).opacity(0.7)
                        }
                        Spacer(minLength: 0)
                    }.contentShape(Rectangle()).padding(.vertical, KoiTheme.space.s5)
                }.buttonStyle(.plain)
            }
        }
    }

    private var exerciseSection: some View {
        VStack(alignment: .leading, spacing: KoiTheme.space.s13) {
            Stepper("\(model.movementGoal?.stepGoal ?? 8_000) steps", value: Binding(get: { model.movementGoal?.stepGoal ?? 8_000 }, set: { model.setMovementGoals(steps: $0) }), in: 1_000...30_000, step: 500)
                .font(KoiTheme.body)
            Stepper("\(model.movementGoal?.weeklyWorkoutGoal ?? 4) workouts a week", value: Binding(get: { model.movementGoal?.weeklyWorkoutGoal ?? 4 }, set: { model.setMovementGoals(weeklyWorkouts: $0) }), in: 1...14)
                .font(KoiTheme.body)
        }
    }

    private var tipsSection: some View {
        VStack(alignment: .leading, spacing: KoiTheme.space.s8) {
            tip("Hold the Balance dial and slide to look back seven days.")
            tip("Tap a pillar label once for its detail, then again to open that tab.")
            tip("Swipe a task right to finish it, or left to let it go.")
            tip("In a workout, tap a set chip to edit it. Hold a rest timer for 15 seconds.")
        }
    }

    private var notificationSection: some View {
        VStack(alignment: .leading, spacing: KoiTheme.space.s13) {
            HStack(spacing: KoiTheme.space.s8) {
                ForEach(KoiNotificationMode.allCases) { mode in
                    Button { Task { await model.setNotifications(mode, hour: model.dailyCheckInHour, provider: notificationProvider) } } label: {
                        GlassChip(title: mode.title, isOn: model.notificationMode == mode)
                    }.buttonStyle(.plain)
                }
            }
            if model.notificationMode == .onceDaily {
                Picker("Check-in time", selection: Binding(get: { model.dailyCheckInHour }, set: { hour in
                    Task { await model.setNotifications(model.notificationMode, hour: hour, provider: notificationProvider) }
                })) {
                    ForEach(6..<23, id: \.self) { hour in Text(timeLabel(hour)).tag(hour) }
                }.pickerStyle(.wheel).frame(height: 100).clipped()
            }
            Text("Smart reminders follow habit times and timed to-dos. Each reminder clears when you update your plan.")
                .font(KoiTheme.caption).opacity(0.68)
            if model.isUpdatingIntegrations { ProgressView().tint(KoiTheme.onBase) }
        }
    }

    private var healthSection: some View {
        VStack(alignment: .leading, spacing: KoiTheme.space.s13) {
            Text(model.healthConnected ? "Steps and workouts can appear in Movement." : "Connect Health to read steps and workouts.")
                .font(KoiTheme.caption).opacity(0.72)
            Button("Open Movement") { onSelectTab(.movement) }.font(KoiTheme.caption).buttonStyle(.plain)
        }
    }

    private var calendarSection: some View {
        VStack(alignment: .leading, spacing: KoiTheme.space.s13) {
            Text(model.calendarConnected ? "Timed to-dos can be added to your calendar." : "Allow Koi to create and update timed to-do events.")
                .font(KoiTheme.caption).opacity(0.72)
            Button {
                Task {
                    if model.calendarConnected { model.disconnectCalendar() }
                    else { await model.connectCalendar(using: calendarProvider) }
                }
            } label: {
                Text(model.calendarConnected ? "Disconnect Calendar" : "Connect Calendar").font(KoiTheme.caption)
            }.buttonStyle(.plain)
            if model.isUpdatingIntegrations { ProgressView().tint(KoiTheme.onBase) }
        }
    }

    private var backupSection: some View {
        VStack(alignment: .leading, spacing: KoiTheme.space.s13) {
            Toggle("Automatic private backup", isOn: Binding(get: { model.backupEnabled }, set: { model.setBackupEnabled($0) }))
                .font(KoiTheme.caption).tint(KoiTheme.onBase)
            Text(model.lastBackupAt.map { "Last backup · \($0.formatted(date: .abbreviated, time: .shortened))" } ?? "Koi backs up when you leave the app.")
                .font(KoiTheme.caption).opacity(0.68)
            HStack(spacing: KoiTheme.space.s21) {
                Button("Back up now") { Task { await model.createBackup(using: backupProvider) } }.font(KoiTheme.caption).buttonStyle(.plain)
                Button("Restore backup") { confirmsRestore = true }.font(KoiTheme.caption).buttonStyle(.plain)
            }
            if model.isBackingUp { ProgressView().tint(KoiTheme.onBase) }
            Text("Only Koi can access this backup in your private iCloud account.")
                .font(KoiTheme.caption).opacity(0.62)
        }
    }

    private var backupSummary: String {
        guard model.backupEnabled else { return "Off" }
        return model.lastBackupAt.map { "Updated \($0.formatted(.dateTime.month(.abbreviated).day()))" } ?? "Private · automatic"
    }

    private func timeLabel(_ hour: Int) -> String {
        var parts = DateComponents()
        parts.hour = hour
        return Calendar.current.date(from: parts)?.formatted(date: .omitted, time: .shortened) ?? "\(hour):00"
    }

    private func fold<Content: View>(_ title: String, summary: String, @ViewBuilder content: () -> Content) -> some View {
        let isOpen = openSection == title
        return VStack(alignment: .leading, spacing: KoiTheme.space.s13) {
            Button { KoiHaptics.tap(); withAnimation(KoiTheme.morph) { openSection = isOpen ? nil : title } } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(title.uppercased()).font(KoiTheme.section).tracking(1.7)
                        if !isOpen { Text(summary).font(KoiTheme.caption).opacity(0.68).lineLimit(1) }
                    }
                    Spacer()
                    Image(systemName: isOpen ? "chevron.up" : "chevron.down").font(.system(size: 12, weight: .light)).opacity(0.7)
                }.contentShape(Rectangle())
            }.buttonStyle(.plain)
            if isOpen { content().transition(.opacity.combined(with: .move(edge: .top))) }
            Rectangle().fill(KoiTheme.divider).frame(height: 0.5)
        }
    }

    private func tip(_ text: String) -> some View { Text(text).font(KoiTheme.caption).opacity(0.76).padding(.vertical, 4) }
    private func focusLine(_ focus: BalanceFocus) -> String {
        switch focus {
        case .allRounder: "The All-Rounder · equal focus"
        case .ritualist: "The Ritualist · habits lead"
        case .nourisher: "The Nourisher · nutrition leads"
        case .mover: "The Mover · movement leads"
        }
    }
    private func focusDescription(_ focus: BalanceFocus) -> String {
        switch focus {
        case .allRounder: "For a bit of everything, equally."
        case .ritualist: "For building routines. Habits are half."
        case .nourisher: "For eating well. Nutrition is half."
        case .mover: "For training. Exercise is half."
        }
    }
}

private struct WeightTrendChart: View {
    let entries: [KoiBodyWeightEntry]
    var body: some View {
        GeometryReader { geometry in
            chart(size: geometry.size).stroke(KoiTheme.onBase.opacity(0.82), style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
        }.accessibilityLabel("Body weight trend")
    }
    private func chart(size: CGSize) -> Path {
        guard entries.count > 1 else { return Path() }
        let values = entries.map(\.weightLB)
        let low = (values.min() ?? 0) - 1, high = max((values.max() ?? 1) + 1, low + 1)
        return Path { path in
            for (index, entry) in entries.enumerated() {
                let x = CGFloat(index) / CGFloat(max(entries.count - 1, 1)) * size.width
                let y = size.height - CGFloat((entry.weightLB - low) / (high - low)) * size.height
                if index == 0 { path.move(to: CGPoint(x: x, y: y)) } else { path.addLine(to: CGPoint(x: x, y: y)) }
            }
        }
    }
}

private struct ProfileWeightRuler: View {
    let value: Double
    let onChange: (Double) -> Void
    @State private var active = false
    @State private var dragStart: Double?
    private let pitch: CGFloat = 9

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let middle = width / 2
            Canvas { context, size in
                let count = Int(width / pitch) + 4
                let centerValue = (value * 5).rounded()
                let fractionalOffset = CGFloat(value * 5 - centerValue) * pitch
                for index in -count / 2...count / 2 {
                    let tickValue = centerValue + Double(index)
                    let x = middle + CGFloat(index) * pitch - fractionalOffset
                    let major = Int(tickValue).isMultiple(of: 5)
                    let distance = abs(x - middle) / max(middle, 1)
                    let fade = max(0, 1 - pow(distance, 1.6))
                    var tick = Path()
                    tick.move(to: CGPoint(x: x, y: size.height - 8 - (major ? 18 : 9) * (active ? 1.25 : 1)))
                    tick.addLine(to: CGPoint(x: x, y: size.height - 8))
                    context.stroke(tick, with: .color(KoiTheme.onBase.opacity((major ? 0.78 : 0.4) * fade)), style: StrokeStyle(lineWidth: major ? 1.4 : 1, lineCap: .round))
                }
                var marker = Path(); marker.move(to: CGPoint(x: middle, y: size.height - 38)); marker.addLine(to: CGPoint(x: middle, y: size.height - 2))
                context.stroke(marker, with: .color(KoiTheme.onBase), style: StrokeStyle(lineWidth: 2, lineCap: .round))
                let bead = CGRect(x: middle - (active ? 9 : 7), y: size.height - 49 - (active ? 2 : 0), width: (active ? 18 : 14), height: (active ? 18 : 14))
                context.fill(Path(ellipseIn: bead), with: .radialGradient(Gradient(colors: [.white.opacity(0.42), .white.opacity(0.12)]), center: CGPoint(x: middle - 3, y: bead.minY + 3), startRadius: 0, endRadius: 11))
            }
            .contentShape(Rectangle())
            .gesture(
                LongPressGesture(minimumDuration: 0.3)
                    .sequenced(before: DragGesture(minimumDistance: 0))
                    .onChanged { state in
                        guard case .second(true, let drag?) = state else { return }
                        if !active { KoiHaptics.land(); active = true; dragStart = value }
                        let raw = (dragStart ?? value) - Double(drag.translation.width / pitch) * 0.2
                        let adjusted = (raw * 5).rounded() / 5
                        guard abs(adjusted - value) >= 0.19 else { return }
                        KoiHaptics.tick()
                        onChange(min(max(adjusted, 50), 600))
                    }
                    .onEnded { _ in
                        if active { KoiHaptics.tap() }
                        withAnimation(.snappy) { active = false }
                        dragStart = nil
                    }
            )
        }
        .frame(height: 62)
        .accessibilityElement()
        .accessibilityLabel("Body weight")
        .accessibilityValue(String(format: "%.1f pounds", value))
        .accessibilityAdjustableAction { direction in
            onChange(min(max(value + (direction == .increment ? 0.2 : -0.2), 50), 600))
        }
    }
}

private struct WeightHistorySheet: View {
    @Environment(\.dismiss) private var dismiss
    let entries: [KoiBodyWeightEntry]
    let onDelete: (KoiBodyWeightEntry) -> Void

    private var chronological: [KoiBodyWeightEntry] { entries.reversed() }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: KoiTheme.space.s21) {
                    if chronological.count > 1 {
                        VStack(alignment: .leading, spacing: KoiTheme.space.s13) {
                            Text("TREND").font(KoiTheme.section).tracking(1.7)
                            Chart(chronological) { entry in
                                AreaMark(x: .value("Date", entry.date), y: .value("Weight", entry.weightLB))
                                    .foregroundStyle(.linearGradient(colors: [KoiTheme.onBase.opacity(0.2), .clear], startPoint: .top, endPoint: .bottom))
                                LineMark(x: .value("Date", entry.date), y: .value("Weight", entry.weightLB))
                                    .interpolationMethod(.catmullRom).foregroundStyle(KoiTheme.onBase)
                                PointMark(x: .value("Date", entry.date), y: .value("Weight", entry.weightLB)).foregroundStyle(KoiTheme.onBase)
                            }
                            .chartYScale(domain: .automatic(includesZero: false))
                            .frame(height: 180)
                        }.padding(KoiTheme.space.s13).background(.ultraThinMaterial.opacity(0.2), in: RoundedRectangle(cornerRadius: 18))
                    } else {
                        Text(entries.isEmpty ? "No weigh-ins yet." : "Log a few days to see your trend.").font(KoiTheme.caption).opacity(0.7)
                    }
                    VStack(alignment: .leading, spacing: KoiTheme.space.s8) {
                        Text("ALL ENTRIES").font(KoiTheme.section).tracking(1.7)
                        ForEach(Array(entries.enumerated()), id: \.element.persistentModelID) { index, entry in
                            HStack {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(entry.date.formatted(.dateTime.weekday(.wide).month(.abbreviated).day())).font(KoiTheme.body)
                                    if index + 1 < entries.count {
                                        let change = entry.weightLB - entries[index + 1].weightLB
                                        Text(abs(change) < 0.05 ? "No change from previous" : "\(change > 0 ? "+" : "−")\(String(format: "%.1f", abs(change))) lb from previous")
                                            .font(KoiTheme.caption).opacity(0.65)
                                    }
                                }
                                Spacer()
                                Text(String(format: "%.1f lb", entry.weightLB)).font(KoiTheme.body).monospacedDigit()
                                Button { onDelete(entry) } label: { Image(systemName: "trash").frame(width: 38, height: 38) }.buttonStyle(.plain).accessibilityLabel("Delete weigh-in")
                            }
                            .padding(.vertical, KoiTheme.space.s5)
                            if index + 1 < entries.count { Rectangle().fill(KoiTheme.divider).frame(height: 0.5) }
                        }
                    }.padding(KoiTheme.space.s13).background(.ultraThinMaterial.opacity(0.18), in: RoundedRectangle(cornerRadius: 18))
                }.padding(KoiTheme.space.s21)
            }
            .background(KoiBackground().ignoresSafeArea())
            .foregroundStyle(KoiTheme.onBase)
            .navigationTitle("Weight history")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() }.font(KoiTheme.caption) } }
        }
        .preferredColorScheme(.dark)
    }
}
