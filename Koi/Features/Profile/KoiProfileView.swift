import PhotosUI
import SwiftData
import SwiftUI
import UIKit
import KoiShared

struct KoiProfileView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var model = ProfileViewModel()
    @State private var openSection: String? = "Body weight"
    @State private var photoItem: PhotosPickerItem?
    @State private var presentsTour = false
    let onSelectTab: (KoiTab) -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
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
                            Button("Open Intake") { dismiss(); onSelectTab(.intake) }.font(KoiTheme.caption).buttonStyle(.plain)
                        }
                    }
                    fold("Exercise goals", summary: model.exerciseGoalSummary) { exerciseSection }
                    fold("Tips & gestures", summary: "A few quiet shortcuts") { tipsSection }
                }
                .padding(.horizontal, KoiTheme.space.s21)
                .padding(.top, KoiTheme.space.s13)
                .padding(.bottom, KoiTheme.space.s55)
            }
            .background(KoiBackground().ignoresSafeArea())
            .foregroundStyle(KoiTheme.onBase)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() }.font(KoiTheme.caption) } }
        }
        .preferredColorScheme(.dark)
        .task { model.load(context) }
        .fullScreenCover(isPresented: $presentsTour) {
            KoiTourView(onFinish: { presentsTour = false })
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
    }

    private var profileHeader: some View {
        HStack(spacing: KoiTheme.space.s13) {
            PhotosPicker(selection: $photoItem, matching: .images) {
                ZStack {
                    Circle().fill(.ultraThinMaterial.opacity(0.35)).frame(width: 64, height: 64)
                    if let data = model.profile?.avatarJPEG, let image = UIImage(data: data) {
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
            Slider(value: Binding(get: { model.weightDraft }, set: { model.setWeight($0) }), in: 50...600, step: 0.1).tint(KoiTheme.onBase)
                .accessibilityLabel("Body weight in pounds")
            HStack { Text("50 lb"); Spacer(); Text("300 lb"); Spacer(); Text("600 lb") }.font(KoiTheme.caption).opacity(0.56)
            HStack {
                Text(model.weightTrendText).font(KoiTheme.caption).opacity(0.76)
                Spacer()
                Button(model.hasWeightToday ? "Update today" : "Log today") { model.saveWeightToday() }.font(KoiTheme.caption).buttonStyle(.plain)
            }
            if model.weightChart.count > 1 {
                WeightTrendChart(entries: model.weightChart).frame(height: 76).padding(.top, KoiTheme.space.s8)
                HStack { Text(model.weightChart.first?.date.formatted(.dateTime.month(.abbreviated).day()) ?? ""); Spacer(); Text(model.weightChart.last?.date.formatted(.dateTime.month(.abbreviated).day()) ?? "") }
                    .font(KoiTheme.caption).opacity(0.56)
            } else {
                Text("Your history will grow with each entry.").font(KoiTheme.caption).opacity(0.64)
            }
            if !model.weightChart.isEmpty {
                Text("HISTORY").font(KoiTheme.section).tracking(1.5).padding(.top, KoiTheme.space.s8)
                ForEach(model.weightChart.suffix(4).reversed()) { entry in
                    HStack { Text(entry.date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())); Spacer(); Text(String(format: "%.1f lb", entry.weightLB)) }
                        .font(KoiTheme.caption).padding(.vertical, 4)
                }
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

    private func fold<Content: View>(_ title: String, summary: String, @ViewBuilder content: () -> Content) -> some View {
        let isOpen = openSection == title
        return VStack(alignment: .leading, spacing: KoiTheme.space.s13) {
            Button { withAnimation(.spring(response: 0.34, dampingFraction: 0.88)) { openSection = isOpen ? nil : title } } label: {
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
