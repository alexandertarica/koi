import SwiftData
import SwiftUI
import KoiShared

struct OnboardingView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(\.healthProvider) private var healthProvider
    @State private var model = OnboardingViewModel()
    @State private var startsTour = false
    @State private var isConnectingHealth = false
    @State private var connectionMessage: String?

    var body: some View {
        ZStack {
            KoiBackground().ignoresSafeArea()
            VStack(spacing: 0) {
                navigationHeader
                ProgressView(value: model.progress)
                    .tint(KoiTheme.onBase)
                    .padding(.top, KoiTheme.space.s21)
                    .padding(.horizontal, KoiTheme.space.s21)
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: KoiTheme.space.s21) {
                        Text(model.step.title).font(KoiTheme.title)
                        Text(model.step.detail).font(KoiTheme.body).opacity(0.78)
                        stepContent
                    }
                    .padding(.horizontal, KoiTheme.space.s21)
                    .padding(.top, KoiTheme.space.s34)
                    .padding(.bottom, KoiTheme.space.s34)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                footer
            }
            .foregroundStyle(KoiTheme.onBase)
        }
        .preferredColorScheme(.dark)
        .task { model.load(context) }
        .onChange(of: model.shouldShowTour) { _, shouldShow in
            guard shouldShow else { return }
            startsTour = true
        }
        .fullScreenCover(isPresented: $startsTour, onDismiss: {
            model.markTourSeen()
            if model.isCompleted { dismiss() }
        }) {
            KoiTourView(onFinish: { startsTour = false })
        }
        .onChange(of: model.isCompleted) { _, complete in
            if complete && !model.shouldShowTour { dismiss() }
        }
        .alert("Setup", isPresented: Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.clearError() } })) {
            Button("OK", role: .cancel) { model.clearError() }
        } message: { Text(model.errorMessage ?? "") }
        .alert("Apple Health", isPresented: Binding(get: { connectionMessage != nil }, set: { if !$0 { connectionMessage = nil } })) {
            Button("OK", role: .cancel) { connectionMessage = nil }
        } message: { Text(connectionMessage ?? "") }
    }

    private var navigationHeader: some View {
        HStack {
            if model.step != .welcome {
                Button { model.goBack() } label: {
                    Label("Back", systemImage: "chevron.left").font(KoiTheme.caption)
                }.buttonStyle(.plain)
            } else {
                Image("KoiWordmark").resizable().renderingMode(.template).scaledToFit().frame(width: 72, height: 26)
            }
            Spacer()
                    if model.step != .welcome {
                        Text("\(model.step.rawValue + 1) OF 7").font(KoiTheme.caption).tracking(1.1).opacity(0.7)
                        Button("Skip") { model.skipToDefaults() }.font(KoiTheme.caption).buttonStyle(.plain).padding(.leading, KoiTheme.space.s8)
                    }
        }
        .padding(.horizontal, KoiTheme.space.s21)
        .padding(.top, KoiTheme.space.s13)
    }

    @ViewBuilder
    private var stepContent: some View {
        switch model.step {
        case .welcome: welcomeContent
        case .name: nameContent
        case .focus: focusContent
        case .habits: habitsContent
        case .about: aboutContent
        case .connect: connectContent
        case .ready: readyContent
        }
    }

    private var welcomeContent: some View {
        VStack(alignment: .leading, spacing: KoiTheme.space.s21) {
            Spacer(minLength: KoiTheme.space.s21)
            Image("KoiWordmark").resizable().renderingMode(.template).scaledToFit().foregroundStyle(KoiTheme.onBase).frame(width: 135, height: 48)
            Text("One day. Three parts. One place to begin.").font(KoiTheme.body).opacity(0.82)
            Spacer(minLength: KoiTheme.space.s21)
        }
    }

    private var nameContent: some View {
        VStack(alignment: .leading, spacing: KoiTheme.space.s21) {
            TextField("Your name", text: $model.name)
                .font(KoiTheme.title)
                .textContentType(.givenName)
                .textInputAutocapitalization(.words)
                .submitLabel(.continue)
                .padding(.vertical, KoiTheme.space.s13)
                .overlay(alignment: .bottom) { Rectangle().fill(KoiTheme.divider).frame(height: 1) }
            Toggle("I’d like to hear about the beta", isOn: $model.sendsBetaEmail).font(KoiTheme.caption).tint(KoiTheme.onBase)
            if model.sendsBetaEmail { emailField("Email address", text: $model.betaEmail) }
            if model.sendsBetaEmail && !model.canContinue { Text("Enter a valid email address to continue.").font(KoiTheme.caption).opacity(0.68) }
        }
    }

    private var focusContent: some View {
        VStack(alignment: .leading, spacing: KoiTheme.space.s8) {
            ForEach(BalanceFocus.allCases, id: \.self) { focus in
                Button { model.focus = focus } label: {
                    HStack(spacing: KoiTheme.space.s13) {
                        Image(systemName: model.focus == focus ? "largecircle.fill.circle" : "circle").font(.system(size: 20, weight: .light))
                        VStack(alignment: .leading, spacing: 5) {
                            Text(focusTitle(focus)).font(KoiTheme.body)
                            Text(focusDescription(focus)).font(KoiTheme.caption).opacity(0.72)
                        }
                        Spacer()
                    }
                    .padding(.vertical, KoiTheme.space.s8)
                    .contentShape(Rectangle())
                }.buttonStyle(.plain)
            }
        }
    }

    private var habitsContent: some View {
        VStack(alignment: .leading, spacing: KoiTheme.space.s13) {
            ForEach(model.habits) { habit in
                HStack(spacing: KoiTheme.space.s13) {
                    Button { model.toggleHabit(habit.id) } label: {
                        Image(systemName: habit.isSelected ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: 20, weight: .light)).foregroundStyle(KoiTheme.onBase)
                    }.buttonStyle(.plain).accessibilityLabel(habit.isSelected ? "Remove \(habit.title)" : "Choose \(habit.title)")
                    TextField("A small habit", text: Binding(get: { habit.title }, set: { model.setHabitTitle(habit.id, title: $0) }))
                        .font(KoiTheme.body).opacity(habit.isSelected ? 1 : 0.56)
                }
                .padding(.vertical, KoiTheme.space.s8)
                .overlay(alignment: .bottom) { Rectangle().fill(KoiTheme.divider.opacity(0.6)).frame(height: 1) }
            }
            Button { model.habits.append(OnboardingHabitDraft(title: "")) } label: {
                Label("Add a ritual", systemImage: "plus").font(KoiTheme.caption)
            }.buttonStyle(.plain)
            Text("Choose at least three. You can change them any time.").font(KoiTheme.caption).opacity(0.68)
        }
    }

    private var aboutContent: some View {
        VStack(alignment: .leading, spacing: KoiTheme.space.s21) {
            Toggle("Add a few details", isOn: $model.hasAboutDetails).font(KoiTheme.caption).tint(KoiTheme.onBase)
            if model.hasAboutDetails {
            HStack {
                Text("Birth year").font(KoiTheme.body)
                Spacer()
                Stepper("\(model.birthYear)", value: $model.birthYear, in: 1920...Calendar.current.component(.year, from: .now) - 13).font(KoiTheme.caption).fixedSize()
            }
            VStack(alignment: .leading, spacing: KoiTheme.space.s8) {
                Text("Height · \(Int(model.heightCM)) cm").font(KoiTheme.body)
                Slider(value: $model.heightCM, in: 120...220, step: 1).tint(KoiTheme.onBase)
            }
            VStack(alignment: .leading, spacing: KoiTheme.space.s8) {
                Text("Starting weight · \(Int(model.startingWeightLB)) lb").font(KoiTheme.body)
                Slider(value: $model.startingWeightLB, in: 50...600, step: 1).tint(KoiTheme.onBase)
            }
            Picker("Sex at birth", selection: $model.sexAtBirth) {
                ForEach(["Prefer not to say", "Female", "Male", "Intersex"], id: \.self) { Text($0).tag($0) }
            }.pickerStyle(.menu).font(KoiTheme.caption).tint(KoiTheme.onBase)
            Divider().overlay(KoiTheme.divider)
            }
            VStack(alignment: .leading, spacing: KoiTheme.space.s13) {
                Text("SUGGESTED TARGETS").font(KoiTheme.section).tracking(1.5).opacity(0.72)
                goalStepper("Steps a day", value: $model.stepGoal, range: 1_000...30_000, step: 500)
                goalStepper("Workouts a week", value: $model.weeklyWorkoutGoal, range: 1...14, step: 1)
                Text("You can change these in Profile.").font(KoiTheme.caption).opacity(0.65)
            }
        }
    }

    private var connectContent: some View {
        VStack(alignment: .leading, spacing: KoiTheme.space.s21) {
            connectionRow(title: "Apple Health", detail: "Steps and workouts", isOn: $model.wantsHealth) {
                guard !model.wantsHealth else {
                    connectionMessage = "Apple Health access is managed in Settings."
                    return
                }
                isConnectingHealth = true
                Task {
                    do {
                        try await healthProvider.requestReadAccess()
                        model.wantsHealth = true
                        connectionMessage = "Apple Health is connected."
                    } catch {
                        model.wantsHealth = false
                        connectionMessage = (error as? LocalizedError)?.errorDescription ?? "Couldn't connect Apple Health. You can try again in Movement."
                    }
                    isConnectingHealth = false
                }
            }
            HStack(spacing: KoiTheme.space.s13) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Apple Calendar").font(KoiTheme.body)
                    Text("Timed to-dos and open time · Connect in Profile").font(KoiTheme.caption).opacity(0.68)
                }
                Spacer()
                Image(systemName: "calendar").font(.system(size: 18, weight: .light)).opacity(0.8)
            }.padding(.vertical, KoiTheme.space.s13)
            VStack(alignment: .leading, spacing: KoiTheme.space.s13) {
                Text("DAILY CHECK-IN").font(KoiTheme.section).tracking(1.5).opacity(0.72)
                Picker("Notifications", selection: $model.notificationMode) {
                    Text("Smart").tag("smart")
                    Text("Once a day").tag("onceDaily")
                    Text("None").tag("none")
                }.pickerStyle(.segmented)
                if model.notificationMode == "onceDaily" {
                    Picker("Time", selection: $model.dailyCheckInHour) {
                        ForEach(6..<23, id: \.self) { hour in Text(timeLabel(hour)).tag(hour) }
                    }.pickerStyle(.wheel).frame(height: 100).clipped()
                }
            }
            Text("Calendar and reminder permissions can be changed later in Profile.").font(KoiTheme.caption).opacity(0.68)
        }
    }

    private var readyContent: some View {
        VStack(alignment: .leading, spacing: KoiTheme.space.s21) {
            Image("KoiRay").resizable().scaledToFit().frame(maxWidth: 180, maxHeight: 120).frame(maxWidth: .infinity)
            Text("Your first day starts whenever you are ready.").font(KoiTheme.body).opacity(0.82)
            Toggle("Tell me when Koi officially drops", isOn: $model.sendsLaunchEmail).font(KoiTheme.caption).tint(KoiTheme.onBase)
            if model.sendsLaunchEmail { emailField("Email address", text: $model.launchEmail) }
            if model.sendsLaunchEmail && !model.canContinue { Text("Enter a valid email address to continue.").font(KoiTheme.caption).opacity(0.68) }
        }
    }

    private var footer: some View {
        VStack(spacing: KoiTheme.space.s13) {
            if !model.canContinue {
                Text(model.step == .habits ? "Choose at least three rituals to continue." : "Complete this step to continue.")
                    .font(KoiTheme.caption).opacity(0.68)
            }
            KoiPrimaryButton(title: model.step == .ready ? "Begin" : "Continue") { model.advance() }
                .disabled(!model.canContinue || isConnectingHealth)
                .opacity(model.canContinue ? 1 : 0.55)
                .padding(.horizontal, KoiTheme.space.s21)
                .padding(.bottom, KoiTheme.space.s21)
        }
    }

    private func emailField(_ prompt: String, text: Binding<String>) -> some View {
        TextField(prompt, text: text)
            .font(KoiTheme.body)
            .keyboardType(.emailAddress)
            .textContentType(.emailAddress)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .padding(.vertical, KoiTheme.space.s13)
            .overlay(alignment: .bottom) { Rectangle().fill(KoiTheme.divider).frame(height: 1) }
    }

    private func goalStepper(_ title: String, value: Binding<Int>, range: ClosedRange<Int>, step: Int) -> some View {
        HStack {
            Text(title).font(KoiTheme.body)
            Spacer()
            Button { value.wrappedValue = max(range.lowerBound, value.wrappedValue - step) } label: { Image(systemName: "minus.circle").font(.system(size: 20, weight: .light)) }.buttonStyle(.plain)
            Text("\(value.wrappedValue)").font(KoiTheme.caption).monospacedDigit().frame(minWidth: 60)
            Button { value.wrappedValue = min(range.upperBound, value.wrappedValue + step) } label: { Image(systemName: "plus.circle").font(.system(size: 20, weight: .light)) }.buttonStyle(.plain)
        }
    }

    private func connectionRow(title: String, detail: String, isOn: Binding<Bool>, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: KoiTheme.space.s13) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).font(KoiTheme.body)
                    Text(detail).font(KoiTheme.caption).opacity(0.68)
                }
                Spacer()
                if title == "Apple Health" && isConnectingHealth { ProgressView().tint(KoiTheme.onBase) }
                else { Image(systemName: isOn.wrappedValue ? "checkmark.circle.fill" : "circle").font(.system(size: 20, weight: .light)) }
            }.padding(.vertical, KoiTheme.space.s13).contentShape(Rectangle())
        }.buttonStyle(.plain)
    }

    private func timeLabel(_ hour: Int) -> String {
        var components = DateComponents()
        components.hour = hour
        components.minute = 0
        return Calendar.current.date(from: components)?.formatted(date: .omitted, time: .shortened) ?? "\(hour):00"
    }

    private func focusTitle(_ focus: BalanceFocus) -> String {
        switch focus {
        case .allRounder: "The All-Rounder"
        case .ritualist: "The Ritualist"
        case .nourisher: "The Nourisher"
        case .mover: "The Mover"
        }
    }

    private func focusDescription(_ focus: BalanceFocus) -> String {
        switch focus {
        case .allRounder: "For a bit of everything, equally."
        case .ritualist: "For building routines."
        case .nourisher: "For eating well."
        case .mover: "For training."
        }
    }
}
