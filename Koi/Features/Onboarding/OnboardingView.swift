import SwiftData
import SwiftUI
import KoiShared

struct OnboardingView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(\.healthProvider) private var healthProvider
    @Environment(\.calendarProvider) private var calendarProvider
    @Environment(\.analyticsProvider) private var analyticsProvider
    @State private var model = OnboardingViewModel()
    @State private var screen = 0
    @State private var isConnecting = false
    @State private var errorMessage: String?

    private let sections = ["WELCOME", "CONNECT", "FOCUS"]

    var body: some View {
        ZStack {
            KoiBackground().ignoresSafeArea()
            VStack(alignment: .leading, spacing: KoiTheme.space.s21) {
                header
                Text("\(screen + 1) of 3")
                    .font(KoiTheme.caption).tracking(1).opacity(0.72)
                    .accessibilityIdentifier("onboardingProgress")
                Group {
                    switch screen {
                    case 0: welcome
                    case 1: connect
                    default: focus
                    }
                }
                Spacer(minLength: 0)
                KoiPrimaryButton(title: screen == 2 ? "Start" : "Next", uppercase: false) {
                    KoiHaptics.tap()
                    if screen < 2 {
                        analyticsProvider.signal("Onboarding.step", parameters: ["step": sections[screen]])
                        withAnimation(KoiTheme.morph) { screen += 1 }
                    } else {
                        model.finishQuickSetup()
                        if model.isCompleted {
                            analyticsProvider.signal("Onboarding.step", parameters: ["step": "FOCUS"])
                            analyticsProvider.signal("Onboarding.completed", parameters: ["method": "quick_setup"])
                        }
                    }
                }
                .disabled(isConnecting)
            }
            .padding(.horizontal, KoiTheme.space.s21)
            .padding(.top, KoiTheme.space.s13)
            .padding(.bottom, KoiTheme.space.s21)
            .foregroundStyle(KoiTheme.onBase)
        }
        .preferredColorScheme(.dark)
        .task {
            model.load(context)
            #if DEBUG
            let arguments = ProcessInfo.processInfo.arguments
            if let index = arguments.firstIndex(of: "-koiOnboardingStep"), arguments.indices.contains(index + 1),
               let requested = Int(arguments[index + 1]) {
                screen = min(max(requested, 0), 2)
            }
            #endif
        }
        .onChange(of: model.isCompleted) { _, complete in if complete { dismiss() } }
        .alert("Setup", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: { Text(errorMessage ?? "") }
    }

    private var header: some View {
        HStack {
            Image("KoiWordmark").resizable().renderingMode(.template).scaledToFit()
                .frame(width: 135, height: 30)
            Spacer()
            Text(sections[screen]).font(KoiTheme.section).tracking(2)
        }
    }

    private var welcome: some View {
        VStack(alignment: .leading, spacing: KoiTheme.space.s21) {
            Text("One score for your habits, food and movement.").font(KoiTheme.title)
            feature("calendar", "See your day at a glance")
            feature("camera", "Log food with a photo or a sentence")
            feature("arrow.right.circle", "Know what to do next")
            TextField("First name (optional)", text: $model.name)
                .font(KoiTheme.body).textContentType(.givenName)
                .textInputAutocapitalization(.words)
                .padding(.vertical, KoiTheme.space.s13)
                .overlay(alignment: .bottom) { Rectangle().fill(KoiTheme.divider).frame(height: 1) }
            Button("Skip setup, use the defaults") {
                KoiHaptics.success()
                model.skipQuickSetup()
                analyticsProvider.signal("Onboarding.skipped", parameters: ["step": "WELCOME"])
                analyticsProvider.signal("Onboarding.completed", parameters: ["method": "skip"])
            }.font(KoiTheme.caption).buttonStyle(.plain).opacity(0.78)
        }
    }

    private var connect: some View {
        VStack(alignment: .leading, spacing: KoiTheme.space.s21) {
            Text("Bring the useful parts of your day together.").font(KoiTheme.title)
            connectionRow("heart", "Apple Health", "Steps, workouts and sleep", isOn: model.wantsHealth) { enabled in toggleHealth(enabled) }
            connectionRow("calendar", "Calendar", "To-dos and plans", isOn: model.wantsCalendar) { enabled in toggleCalendar(enabled) }
            Text("Both are optional. You can connect them later in Profile.")
                .font(KoiTheme.caption).opacity(0.72)
        }
    }

    private var focus: some View {
        VStack(alignment: .leading, spacing: KoiTheme.space.s13) {
            Text("Choose what matters most. You can change this in Profile.").font(KoiTheme.title)
            focusChoice(.allRounder, title: "Balanced", detail: "All three count equally")
            focusChoice(.ritualist, title: "Habits", detail: "Give habits a little more weight")
            focusChoice(.nourisher, title: "Nutrition", detail: "Give nutrition a little more weight")
            focusChoice(.mover, title: "Exercise", detail: "Give movement a little more weight")
        }
    }

    private func feature(_ symbol: String, _ text: String) -> some View {
        Label(text, systemImage: symbol).font(KoiTheme.body).labelStyle(.titleAndIcon)
    }

    private func connectionRow(_ symbol: String, _ title: String, _ detail: String, isOn: Bool, setEnabled: @escaping (Bool) -> Void) -> some View {
        Toggle(isOn: Binding(get: { isOn }, set: setEnabled)) {
            HStack(spacing: KoiTheme.space.s13) {
                Image(systemName: symbol).frame(width: 28)
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).font(KoiTheme.body)
                    Text(detail).font(KoiTheme.caption).opacity(0.7)
                }
            }
        }
        .tint(KoiTheme.onBase)
        .disabled(isConnecting)
    }

    private func focusChoice(_ value: BalanceFocus, title: String, detail: String) -> some View {
        Button { KoiHaptics.change(); model.focus = value } label: {
            HStack(spacing: KoiTheme.space.s13) {
                Image(systemName: model.focus == value ? "largecircle.fill.circle" : "circle")
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).font(KoiTheme.body)
                    Text(detail).font(KoiTheme.caption).opacity(0.7)
                }
                Spacer()
            }.padding(.vertical, KoiTheme.space.s8).contentShape(Rectangle())
        }.buttonStyle(.plain)
    }

    private func toggleHealth(_ enabled: Bool) {
        guard enabled else { model.wantsHealth = false; return }
        isConnecting = true
        Task {
            do { try await healthProvider.requestReadAccess(); model.wantsHealth = true }
            catch { errorMessage = "Apple Health couldn't connect. You can try again in Profile." }
            isConnecting = false
        }
    }

    private func toggleCalendar(_ enabled: Bool) {
        guard enabled else { model.wantsCalendar = false; return }
        isConnecting = true
        Task {
            do { try await calendarProvider.requestAccess(); model.wantsCalendar = true }
            catch { errorMessage = "Calendar couldn't connect. You can try again in Profile." }
            isConnecting = false
        }
    }
}
