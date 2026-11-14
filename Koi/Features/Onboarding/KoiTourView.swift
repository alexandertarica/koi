import SwiftUI

private struct TourStop: Identifiable {
    let id: Int
    let title: String
    let detail: String
    let symbol: String
}

struct KoiTourView: View {
    @Environment(\.analyticsProvider) private var analyticsProvider
    let onFinish: () -> Void
    @State private var stopIndex = 0

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
        TourStop(id: 11, title: "Ready when you are", detail: "The smart note gesture will be introduced with Smart Notes.", symbol: "arrow.up.message")
    ]

    var body: some View {
        ZStack {
            KoiBackground().ignoresSafeArea()
            Color(red: 0.04, green: 0.11, blue: 0.22).opacity(0.74).ignoresSafeArea()
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
                KoiPrimaryButton(title: stopIndex == stops.count - 1 ? "Finish" : "Continue") {
                    if stopIndex == stops.count - 1 { finish(at: "finish") }
                    else { withAnimation(.spring(response: 0.36, dampingFraction: 0.86)) { stopIndex += 1 } }
                }
            }
            .padding(.horizontal, KoiTheme.space.s21)
            .padding(.top, KoiTheme.space.s21)
            .padding(.bottom, KoiTheme.space.s34)
            .foregroundStyle(KoiTheme.onBase)
        }
        .preferredColorScheme(.dark)
    }

    private func finish(at point: String) {
        analyticsProvider.signal("Tour.ended", parameters: ["at": point])
        onFinish()
    }
}
