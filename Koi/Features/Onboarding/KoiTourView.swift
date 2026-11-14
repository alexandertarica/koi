import SwiftUI

private struct TourStop: Identifiable {
    let id: Int
    let title: String
    let detail: String
    let symbol: String
}

struct KoiTourView: View {
    @Environment(\.analyticsProvider) private var analyticsProvider
    let onSelectTab: (KoiTab) -> Void
    let onTrySmartNote: () -> Void
    let onFinish: () -> Void
    @State private var stopIndex = 0
    @GestureState private var swipeOffset = CGSize.zero

    init(onSelectTab: @escaping (KoiTab) -> Void = { _ in }, onTrySmartNote: @escaping () -> Void = {}, onFinish: @escaping () -> Void) {
        self.onSelectTab = onSelectTab
        self.onTrySmartNote = onTrySmartNote
        self.onFinish = onFinish
    }

    private let stops = [
        TourStop(id: 0, title: "Your Balance", detail: "One number for habits, nutrition and exercise.", symbol: "circle.lefthalf.filled"),
        TourStop(id: 1, title: "Three pillars", detail: "Each part still counts, whatever your focus.", symbol: "chart.bar.xaxis"),
        TourStop(id: 2, title: "A little history", detail: "Open Progress to see how your days add up.", symbol: "chart.xyaxis.line"),
        TourStop(id: 3, title: "Your space", detail: "Your name, goals and body-weight history live in Profile.", symbol: "person.crop.circle"),
        TourStop(id: 4, title: "Four places", detail: "Move between Hub, To-Do, Movement and Intake.", symbol: "square.grid.2x2"),
        TourStop(id: 5, title: "To-Do", detail: "Keep habits and tasks close to today.", symbol: "checklist"),
        TourStop(id: 6, title: "Archive", detail: "Completed tasks and paused habits can return here.", symbol: "archivebox"),
        TourStop(id: 7, title: "Movement", detail: "Log your steps and training in one place.", symbol: "figure.walk"),
        TourStop(id: 8, title: "Your journal", detail: "Build a workout, set by set, at your own pace.", symbol: "dumbbell"),
        TourStop(id: 9, title: "Intake", detail: "See food and nutrients against your daily goals.", symbol: "leaf"),
        TourStop(id: 10, title: "Edit your targets", detail: "Open a nutrient row to adjust its goal.", symbol: "slider.horizontal.3"),
        TourStop(id: 11, title: "A note, your way", detail: "Swipe the handle up to open a note. Write what happened, then let Koi find the right place for it.", symbol: "arrow.up.message")
    ]

    var body: some View {
        GeometryReader { geometry in
        ZStack {
            Color.clear.ignoresSafeArea()
            TourSpotlightMask(stop: stopIndex).ignoresSafeArea()
            VStack(spacing: KoiTheme.space.s34) {
                HStack {
                    Text("A QUICK LOOK").font(KoiTheme.section).tracking(2).opacity(0.74)
                    Spacer()
                    Button("Skip") { finish(at: "skip") }.font(KoiTheme.caption).buttonStyle(.plain)
                }
                Spacer()
                Image(systemName: stops[stopIndex].symbol)
                    .font(.system(size: 44, weight: .ultraLight))
                    .frame(width: 110, height: 110)
                    .background(.ultraThinMaterial.opacity(0.45), in: Circle())
                    .overlay(Circle().stroke(KoiTheme.onBase.opacity(0.4), lineWidth: 1))
                    .accessibilityHidden(true)
                VStack(spacing: KoiTheme.space.s13) {
                    Text(stops[stopIndex].title).font(KoiTheme.title).multilineTextAlignment(.center)
                    Text(stops[stopIndex].detail).font(KoiTheme.body).multilineTextAlignment(.center).opacity(0.78)
                        .frame(maxWidth: 320)
                }
                Spacer()
                HStack(spacing: KoiTheme.space.s5) {
                    ForEach(stops) { stop in
                        Capsule().fill(stop.id == stopIndex ? KoiTheme.onBase : KoiTheme.onBase.opacity(0.3)).frame(width: stop.id == stopIndex ? 21 : 5, height: 5)
                    }
                }
                if stopIndex == stops.count - 1 {
                    HStack(spacing: KoiTheme.space.s8) {
                        Image(systemName: "line.3.horizontal").font(.system(size: 14, weight: .regular))
                        Text("SWIPE UP TO TRY IT").font(KoiTheme.section).tracking(1.6)
                        Image(systemName: "arrow.up").font(.system(size: 14, weight: .regular))
                    }
                    .frame(maxWidth: .infinity, minHeight: 54)
                    .background(.ultraThinMaterial.opacity(0.38), in: Capsule())
                    .overlay(Capsule().stroke(KoiTheme.onBase.opacity(0.44), lineWidth: 1))
                    .offset(y: min(swipeOffset.height, 0) * 0.15)
                    .gesture(DragGesture(minimumDistance: 12).updating($swipeOffset) { value, state, _ in state = value.translation }.onEnded { value in
                        guard value.translation.height < -42 else { return }
                        finish(at: "hands-on")
                    })
                    .accessibilityAction(named: Text("Try Smart Note")) { finish(at: "hands-on") }
                } else {
                    KoiPrimaryButton(title: "Continue") {
                        withAnimation(.spring(response: 0.36, dampingFraction: 0.86)) { stopIndex += 1 }
                    }
                }
            }
            .padding(.horizontal, KoiTheme.space.s21)
            .padding(.top, KoiTheme.space.s21)
            .padding(.bottom, KoiTheme.space.s34)
            .foregroundStyle(KoiTheme.onBase)
        }
        .onAppear { onSelectTab(.hub) }
        .onChange(of: stopIndex) { _, index in onSelectTab(tab(for: index)) }
        }
        .preferredColorScheme(.dark)
    }

    private func finish(at point: String) {
        analyticsProvider.signal("Tour.ended", parameters: ["at": point])
        onFinish()
        if point == "hands-on" {
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(450))
                onTrySmartNote()
            }
        }
    }

    private func tab(for index: Int) -> KoiTab {
        switch index {
        case 5, 6: .toDo
        case 7, 8: .movement
        case 9, 10: .intake
        default: .hub
        }
    }
}

private struct TourSpotlightMask: View {
    let stop: Int

    var body: some View {
        Canvas { context, size in
            let rect = CGRect(origin: .zero, size: size)
            var mask = Path(); mask.addRect(rect)
            let aperture = target(in: size)
            mask.addRoundedRect(in: aperture, cornerSize: CGSize(width: 24, height: 24))
            context.fill(mask, with: .color(Color(red: 0.04, green: 0.11, blue: 0.22).opacity(0.8)), style: FillStyle(eoFill: true))
            context.stroke(Path(roundedRect: aperture, cornerRadius: 24), with: .color(KoiTheme.onBase.opacity(0.75)), lineWidth: 1)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func target(in size: CGSize) -> CGRect {
        switch stop {
        case 0: CGRect(x: 0, y: size.height * 0.19, width: size.width * 0.74, height: size.height * 0.42)
        case 1: CGRect(x: 0, y: size.height * 0.29, width: size.width * 0.62, height: size.height * 0.28)
        case 2: CGRect(x: size.width * 0.55, y: size.height * 0.17, width: size.width * 0.42, height: 90)
        case 3: CGRect(x: size.width * 0.7, y: 42, width: size.width * 0.3, height: 82)
        case 4: CGRect(x: size.width * 0.04, y: size.height * 0.82, width: size.width * 0.92, height: 100)
        case 5, 6: CGRect(x: 0, y: size.height * 0.18, width: size.width, height: size.height * 0.57)
        case 7: CGRect(x: size.width * 0.65, y: size.height * 0.48, width: size.width * 0.34, height: 180)
        case 8: CGRect(x: size.width * 0.66, y: 40, width: size.width * 0.34, height: 88)
        case 9: CGRect(x: 0, y: size.height * 0.28, width: size.width, height: size.height * 0.42)
        case 10: CGRect(x: size.width * 0.68, y: 40, width: size.width * 0.32, height: 88)
        default: CGRect(x: size.width * 0.03, y: size.height * 0.86, width: size.width * 0.94, height: 86)
        }
    }
}
