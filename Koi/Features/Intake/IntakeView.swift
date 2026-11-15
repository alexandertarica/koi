import PhotosUI
import SwiftData
import SwiftUI
import UIKit
import KoiShared

struct IntakeView: View {
    @Binding private var presentsMealComposer: Bool
    @Binding private var startsCamera: Bool
    @Environment(\.modelContext) private var modelContext
    @Environment(\.analyticsProvider) private var analyticsProvider
    @Environment(\.foodEstimator) private var foodEstimator
    @State private var model = IntakeViewModel()
    @State private var selectedMeal: KoiFoodEntry?
    @State private var showsNutrients = false
    @State private var showsSupplementComposer = false
    @State private var supplementName = ""
    @State private var showsEntrySheet = false
    @State private var selectedNutrient: String?
    @State private var composerActive = false
    @State private var foodRingLit = false
    @State private var composerID = UUID()

    init(presentsMealComposer: Binding<Bool> = .constant(false), startsCamera: Binding<Bool> = .constant(false)) {
        _presentsMealComposer = presentsMealComposer
        _startsCamera = startsCamera
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: KoiTheme.space.s21) {
                header.modifier(KoiIntroReveal(order: 0))
                if composerActive {
                    MealComposer(model: model, estimator: foodEstimator, startsCamera: $startsCamera, onClose: closeComposer)
                        .id(composerID)
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                } else {
                    calorieCard.modifier(KoiIntroReveal(order: 1))
                    if let note = model.adjustmentNote {
                        Text(note).font(KoiTheme.caption).opacity(0.78).padding(.horizontal, KoiTheme.space.s8)
                    }
                    nutrientsSection.modifier(KoiIntroReveal(order: 2))
                    supplementsSection.modifier(KoiIntroReveal(order: 3))
                    mealSection.modifier(KoiIntroReveal(order: 4))
                }
            }
            .padding(.horizontal, KoiTheme.space.s21)
            .padding(.top, KoiTheme.space.s13)
            .padding(.bottom, KoiTheme.space.s55)
        }
        .foregroundStyle(KoiTheme.onBase)
        .onAppear {
            model.load(modelContext)
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("-koiShowMealComposer") || KoiLaunch.tourState == "photoResult" { openComposer() }
            #endif
        }
        .onChange(of: presentsMealComposer) { _, presented in if presented { openComposer() } }
        .onChange(of: startsCamera) { _, starts in if starts { openComposer() } }
        .sheet(item: $selectedMeal) { meal in
            MealDetailSheet(meal: meal, model: model, estimator: foodEstimator)
                .presentationDetents([.large])
        }
        .sheet(isPresented: $showsNutrients) {
            NutrientEditor(model: model).presentationDetents([.large])
        }
        .sheet(isPresented: $showsEntrySheet) {
            NutrientQuickEntry(model: model).presentationDetents([.medium, .large])
        }
        .alert("Add a supplement", isPresented: $showsSupplementComposer) {
            TextField("Name", text: $supplementName)
            Button("Add") { model.addSupplement(name: supplementName); supplementName = "" }
            Button("Cancel", role: .cancel) { supplementName = "" }
        }
        .alert("", isPresented: Binding(get: { model.errorMessage != nil && !composerActive }, set: { if !$0 { model.clearEstimate() } })) {
            Button("OK", role: .cancel) { model.clearEstimate() }
        } message: { Text(model.errorMessage ?? "") }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center) {
                Image("KoiWordmark").resizable().renderingMode(.template).scaledToFit()
                    .frame(width: 240, height: 28).foregroundStyle(Color(red: 0.91, green: 0.93, blue: 0.95))
                Spacer()
                Button { KoiHaptics.tap(); if composerActive { closeComposer() } else { showsNutrients = true } } label: {
                    Image(systemName: composerActive ? "xmark" : "slider.horizontal.3").font(.system(size: 21, weight: .light))
                        .foregroundStyle(Color(red: 0.91, green: 0.93, blue: 0.95)).frame(width: 44, height: 44)
                }.padding(.vertical, -8).buttonStyle(.plain).accessibilityLabel(composerActive ? "Close meal entry" : "Edit nutrition goals")
            }
            VStack(alignment: .leading, spacing: 0) {
                Text(Date.now.formatted(.dateTime.weekday(.wide).month(.wide).day()).uppercased())
                    .font(KoiTheme.section).tracking(2.7).foregroundStyle(Color(red: 0.91, green: 0.93, blue: 0.95).opacity(0.88)).padding(.top, 7)
                Text(composerActive ? "Log food" : "Intake").font(KoiTheme.title).foregroundStyle(Color(red: 0.91, green: 0.93, blue: 0.95)).padding(.top, 3)
            }
        }
    }

    private var calorieCard: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .topLeading) {
                IntakeDialCanvas(calories: model.calories, goal: model.calorieGoal, nutrients: model.nutrientRows)
                    .padding(.horizontal, -KoiTheme.space.s21)
                VStack(alignment: .trailing, spacing: 0) {
                    Text(Int(model.calories.rounded()).formatted()).font(.system(size: 63, weight: .regular, design: .rounded)).contentTransition(.numericText())
                    Text("CALORIES").font(KoiTheme.section).tracking(1.5).opacity(0.78)
                    Text("of \(Int(model.calorieGoal).formatted()) kcal").font(KoiTheme.caption).opacity(0.78)
                }.frame(maxWidth: .infinity, alignment: .trailing).padding(.trailing, 8).padding(.top, 6)
                VStack(spacing: KoiTheme.space.s5) {
                    KoiTickRing(isOn: foodRingLit) {
                        KoiHaptics.ringFill(duration: 0.5, beats: 12)
                        withAnimation(.easeOut(duration: 0.25)) { foodRingLit = true }
                        Task { @MainActor in
                            try? await Task.sleep(for: .milliseconds(400))
                            openComposer()
                            withAnimation(.easeOut(duration: 0.2)) { foodRingLit = false }
                        }
                    }
                    Text(model.mealCount == 0 ? "LOG" : "\(model.mealCount) logged").font(KoiTheme.section).tracking(1.3)
                }
                .foregroundStyle(KoiTheme.onBase)
                .padding(.trailing, KoiTheme.space.s21)
                .padding(.bottom, 64)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
            }.frame(height: 380)
        }
        .frame(maxWidth: .infinity).padding(.vertical, -KoiTheme.space.s13)
    }

    private var nutrientsSection: some View {
        VStack(alignment: .leading, spacing: KoiTheme.space.s8) {
            // Nutrient rows stay printed on the water; the header control opens goal editing.
            VStack(spacing: 0) {
                ForEach(model.nutrientRows) { nutrient in
                    NutrientRow(nutrient: nutrient, expanded: selectedNutrient == nutrient.key, decrement: { model.changeNutrient(nutrient.key, by: -nutrient.step) }, increment: { model.changeNutrient(nutrient.key, by: nutrient.step) }, toggle: { withAnimation(KoiTheme.morph) { selectedNutrient = selectedNutrient == nutrient.key ? nil : nutrient.key } }, preset: { amount in model.changeNutrient(nutrient.key, by: amount) })
                    if nutrient.id != model.nutrientRows.last?.id { Divider().overlay(KoiTheme.onBase.opacity(0.16)).padding(.leading, KoiTheme.space.s13) }
                }
            }
            .padding(.horizontal, 0)
        }
    }

    private var supplementsSection: some View {
        VStack(alignment: .leading, spacing: KoiTheme.space.s8) {
            sectionHeading("SUPPLEMENTS", action: "+ Add") { showsSupplementComposer = true }
            if model.activeSupplements.isEmpty {
                Text("Keep your usuals here.").font(KoiTheme.caption).opacity(0.78).padding(.horizontal, KoiTheme.space.s13).padding(.vertical, KoiTheme.space.s8)
            } else {
                FlowLayout(spacing: KoiTheme.space.s8) {
                    ForEach(model.activeSupplements) { supplement in
                        Button { model.toggleSupplement(supplement) } label: {
                            GlassChip(title: supplement.name, symbol: model.isSupplementTaken(supplement) ? "checkmark" : nil, isOn: model.isSupplementTaken(supplement))
                        }.buttonStyle(.plain).contextMenu { Button("Remove", role: .destructive) { model.removeSupplement(supplement) } }
                    }
                }
            }
        }
    }

    private var mealSection: some View {
        VStack(alignment: .leading, spacing: KoiTheme.space.s8) {
            sectionHeading("TODAY", action: model.mealCount == 0 ? nil : "\(model.mealCount) meals") {}
            if model.meals.isEmpty {
                Text("Your meals will settle here.").font(KoiTheme.caption).opacity(0.78).padding(.horizontal, KoiTheme.space.s13).padding(.vertical, KoiTheme.space.s8)
            } else {
                VStack(spacing: 0) {
                    ForEach(model.meals) { meal in
                        Button { selectedMeal = meal } label: {
                            HStack(spacing: KoiTheme.space.s13) {
                                if let data = meal.imageJPEG, let image = UIImage(data: data) {
                                    Image(uiImage: image).resizable().scaledToFill().frame(width: 42, height: 42).clipShape(RoundedRectangle(cornerRadius: 10))
                                } else {
                                    Image(systemName: "leaf").frame(width: 42, height: 42).background(KoiTheme.onBase.opacity(0.1), in: RoundedRectangle(cornerRadius: 10))
                                }
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(meal.name).font(KoiTheme.body).lineLimit(1)
                                    Text("\(Int(meal.calories.rounded())) kcal · \(meal.loggedAt.formatted(date: .omitted, time: .shortened))").font(KoiTheme.caption).opacity(0.75)
                                }
                                Spacer()
                                Image(systemName: "chevron.right").font(.system(size: 11)).opacity(0.6)
                            }.padding(.horizontal, KoiTheme.space.s13).padding(.vertical, KoiTheme.space.s8).contentShape(Rectangle())
                        }.buttonStyle(.plain)
                        if meal.id != model.meals.last?.id { Divider().overlay(KoiTheme.onBase.opacity(0.16)).padding(.leading, 68) }
                    }
                }.background(.ultraThinMaterial.opacity(0.22), in: RoundedRectangle(cornerRadius: 20)).overlay(RoundedRectangle(cornerRadius: 20).stroke(KoiTheme.onBase.opacity(0.22), lineWidth: 1))
            }
        }
    }

    private func sectionHeading(_ title: String, action: String?, perform: @escaping () -> Void) -> some View {
        HStack {
            Text(title).font(KoiTheme.section).tracking(2)
            Spacer()
            if let action { Button(action, action: perform).font(KoiTheme.caption).foregroundStyle(KoiTheme.onBase.opacity(0.8)).buttonStyle(.plain) }
        }.padding(.horizontal, KoiTheme.space.s13)
    }

    private func openComposer() { composerID = UUID(); withAnimation(KoiTheme.morph) { composerActive = true }; presentsMealComposer = false }
    private func closeComposer() { withAnimation(KoiTheme.morph) { composerActive = false }; startsCamera = false; model.clearEstimate() }
}

struct KoiTickRing: View {
    let isOn: Bool
    let action: () -> Void
    var label = "LOG"
    var what = "food"
    private let count = 48

    var body: some View {
        Button(action: action) {
            ZStack {
                ForEach(0..<count, id: \.self) { index in
                    Capsule().fill(KoiTheme.onBase.opacity(isOn ? 0.92 : 0.5))
                        .frame(width: 1, height: isOn ? 20 : 6)
                        .offset(y: -31)
                        .rotationEffect(.degrees(Double(index) * 360 / Double(count)))
                        .animation(.timingCurve(0.16, 1, 0.3, 1, duration: 0.5).delay(Double(index) * 0.01), value: isOn)
                }
                Text(label).font(KoiTheme.section).tracking(2)
            }
            .frame(width: 96, height: 96)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isOn ? "\(what.capitalized) logged" : "Log \(what)")
    }
}

private struct IntakeDialCanvas: View {
    let calories: Double
    let goal: Double
    let nutrients: [IntakeNutrient]

    var body: some View {
        GeometryReader { proxy in
            let radius = proxy.size.height / 2 - 14
            let center = CGPoint(x: 0, y: proxy.size.height / 2)
            let progress = min(max(calories / max(goal, 1), 0), 1)
            ZStack(alignment: .topLeading) {
                Canvas { context, _ in
                    let dialRadius = radius
                    func point(_ t: Double, _ r: CGFloat) -> CGPoint {
                        let angle = -Double.pi / 2 + Double.pi * t
                        return CGPoint(x: center.x + r * cos(angle), y: center.y + r * sin(angle))
                    }
                    func nutrientDot(_ degrees: Double, opacity: Double) {
                        let angle = degrees * Double.pi / 180
                        let p = CGPoint(x: center.x + cos(angle) * (dialRadius - 25), y: center.y + sin(angle) * (dialRadius - 25))
                        context.fill(Path(ellipseIn: CGRect(x: p.x - 2, y: p.y - 2, width: 4, height: 4)), with: .color(.white.opacity(opacity)))
                    }
                    for tick in 0...72 {
                        let t = Double(tick) / 72
                        let angle = -Double.pi / 2 + Double.pi * t
                        let length: CGFloat = tick.isMultiple(of: 5) ? 13 : 7
                        var mark = Path(); mark.move(to: point(t, dialRadius + 17)); mark.addLine(to: CGPoint(x: center.x + cos(angle) * (dialRadius + 17 + length), y: center.y + sin(angle) * (dialRadius + 17 + length)))
                        context.stroke(mark, with: .color(.white.opacity(t <= progress ? 0.86 : 0.45)), style: StrokeStyle(lineWidth: tick.isMultiple(of: 5) ? 1.7 : 1, lineCap: .round))
                    }
                    for i in 0..<90 {
                        let a = Double(i) / 90, b = Double(i + 1) / 90
                        var arc = Path(); arc.addArc(center: center, radius: dialRadius, startAngle: .degrees(-90 + a * 180), endAngle: .degrees(-90 + b * 180), clockwise: false)
                        let edge = max(0.3, min(a / 0.28, (1 - a) / 0.22, 1))
                        context.stroke(arc, with: .color(.white.opacity((b <= progress ? 0.88 : 0.55) * edge)), lineWidth: b <= progress ? 1.5 : 1.1)
                    }
                    let visible = nutrients.filter { ["protein", "fiber"].contains($0.key) && $0.goal > 0 }
                    for (index, nutrient) in visible.enumerated() {
                        let start = Double(index) / Double(max(visible.count, 1))
                        let span = 1 / Double(max(visible.count, 1))
                        let fill = min(max(nutrient.value / nutrient.goal, 0), 1)
                        let segmentStart = -90 + start * 180 + 5
                        let segmentSpan = span * 180 - 10
                        var track = Path(); track.addArc(center: center, radius: dialRadius - 25, startAngle: .degrees(segmentStart), endAngle: .degrees(segmentStart + segmentSpan), clockwise: false)
                        context.stroke(track, with: .color(.white.opacity(0.35)), style: StrokeStyle(lineWidth: 4, lineCap: .butt))
                        nutrientDot(segmentStart, opacity: 0.35); nutrientDot(segmentStart + segmentSpan, opacity: 0.35)
                        if fill > 0 {
                            var bar = Path(); bar.addArc(center: center, radius: dialRadius - 25, startAngle: .degrees(segmentStart), endAngle: .degrees(segmentStart + segmentSpan * fill), clockwise: false)
                            context.stroke(bar, with: .color(.white.opacity(0.72)), style: StrokeStyle(lineWidth: 4, lineCap: .butt))
                            nutrientDot(segmentStart, opacity: 0.72); nutrientDot(segmentStart + segmentSpan * fill, opacity: 0.72)
                        }
                    }
                    if progress > 0 {
                        let bead = point(max(progress, 0.06), dialRadius)
                        context.fill(Path(ellipseIn: CGRect(x: bead.x - 9, y: bead.y - 9, width: 18, height: 18)), with: .radialGradient(Gradient(colors: [.white.opacity(0.38), .white.opacity(0.12), .white.opacity(0.2)]), center: CGPoint(x: bead.x - 3, y: bead.y - 4), startRadius: 0, endRadius: 12))
                        context.stroke(Path(ellipseIn: CGRect(x: bead.x - 9, y: bead.y - 9, width: 18, height: 18)), with: .color(.white.opacity(0.75)), lineWidth: 1)
                    }
                }
                let visible = nutrients.filter { ["protein", "fiber"].contains($0.key) && $0.goal > 0 }
                ForEach(Array(visible.enumerated()), id: \.element.id) { index, nutrient in
                    let midpoint = (Double(index) + 0.5) / Double(max(visible.count, 1))
                    let angle = (-Double.pi / 2 + Double.pi * midpoint) * 0.5
                    let r = radius - 38
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("\(Int((nutrient.value / max(nutrient.goal, 1) * 100).rounded()))%")
                            .font(.custom("RobotoMono-Light", size: 15))
                        Text(nutrient.name.uppercased()).font(KoiTheme.section).tracking(1)
                    }
                    .foregroundStyle(KoiTheme.onBase.opacity(0.92))
                    .fixedSize()
                    .frame(width: 110, alignment: .trailing)
                    .position(x: center.x + CGFloat(cos(angle)) * r - 55, y: CGFloat(center.y) + CGFloat(sin(angle)) * r)
                }
            }
        }
    }
}

private struct NutrientRow: View {
    let nutrient: IntakeNutrient
    let expanded: Bool
    let decrement: () -> Void
    let increment: () -> Void
    let toggle: () -> Void
    let preset: (Double) -> Void
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: KoiTheme.space.s8) {
                Button(action: toggle) {
                    HStack(spacing: 5) {
                        Text(nutrient.key == "calories" ? "CALORIES EATEN" : nutrient.name.uppercased()).font(KoiTheme.section).tracking(1.8)
                        Image(systemName: "chevron.down").font(.system(size: 9, weight: .light)).rotationEffect(.degrees(expanded ? 180 : 0))
                    }.contentShape(Rectangle())
                }.buttonStyle(.plain)
                Spacer(minLength: 4)
                Button(action: toggle) {
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text("\(Int(nutrient.value.rounded()))").font(.custom("RobotoMono-Light", size: 25))
                        Text("/ \(Int(nutrient.goal)) \(nutrient.unit)").font(KoiTheme.caption)
                    }.monospacedDigit().frame(minWidth: 120, alignment: .trailing)
                }.buttonStyle(.plain).accessibilityLabel("Set \(nutrient.name) amount")
            }
            if expanded {
                HStack(spacing: KoiTheme.space.s8) {
                    ForEach(presets, id: \.0) { item in
                        Button("\(item.0) +\(Int(item.1))") { preset(item.1); KoiHaptics.change() }
                            .font(KoiTheme.caption).padding(.horizontal, 10).padding(.vertical, 7)
                            .background(.ultraThinMaterial.opacity(0.35), in: Capsule()).buttonStyle(.plain)
                    }
                    Spacer(minLength: 0)
                }.padding(.top, KoiTheme.space.s5).transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .foregroundStyle(KoiTheme.onBase).buttonStyle(.plain).padding(.top, KoiTheme.space.s5).padding(.bottom, 53)
        .overlay(alignment: .bottomLeading) {
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(KoiTheme.onBase.opacity(0.18)).frame(height: 3.5)
                    Capsule().fill(KoiTheme.onBase.opacity(0.72)).frame(width: proxy.size.width * fraction, height: 3.5)
                    Circle().fill(.ultraThinMaterial).overlay(Circle().stroke(KoiTheme.onBase.opacity(0.5), lineWidth: 0.7))
                        .frame(width: 14, height: 14).offset(x: max(0, proxy.size.width * fraction - 7))
                }
                .frame(height: 4)
            }
            .frame(height: 4)
            .offset(y: -34)
            .allowsHitTesting(false)
        }
    }
    private var presets: [(String, Double)] {
        switch nutrient.key {
        case "calories": [("Snack", 200), ("Meal", 600)]
        case "water": [("Glass", 8), ("Mug", 12), ("Bottle", 16)]
        case "protein": [("Snack", 10), ("Meal", 30)]
        case "fiber": [("Fruit", 4), ("Meal", 8)]
        default: [("Add", nutrient.step * 5), ("More", nutrient.step * 10)]
        }
    }
    private var goalCaption: String {
        switch nutrient.goalType {
        case .reach: "Goal · \(Int(nutrient.goal)) \(nutrient.unit)"
        case .limit: "Limit · \(Int(nutrient.goal)) \(nutrient.unit)"
        case .around: "Around · \(Int(nutrient.goal)) \(nutrient.unit)"
        case .track: "Tracked"
        }
    }
    private var fraction: CGFloat {
        guard nutrient.goal > 0 else { return 0 }
        switch nutrient.goalType {
        case .reach, .limit: return CGFloat(min(nutrient.value / nutrient.goal, 1))
        case .around: return CGFloat(max(0, 1 - abs(nutrient.value - nutrient.goal) / nutrient.goal))
        case .track: return CGFloat(min(nutrient.value / max(nutrient.goal, 1), 1))
        }
    }
}

private struct IntakeCameraPicker: UIViewControllerRepresentable {
    @Environment(\.dismiss) private var dismiss
    let onImage: (UIImage) -> Void

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ picker: UIImagePickerController, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator(onImage: onImage, dismiss: dismiss) }

    final class Coordinator: NSObject, UINavigationControllerDelegate, UIImagePickerControllerDelegate {
        let onImage: (UIImage) -> Void
        let dismiss: DismissAction
        init(onImage: @escaping (UIImage) -> Void, dismiss: DismissAction) { self.onImage = onImage; self.dismiss = dismiss }
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let image = info[.originalImage] as? UIImage { onImage(image) }
            dismiss()
        }
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { dismiss() }
    }
}

private struct FlowLayout: Layout {
    var spacing: CGFloat = 8
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0 && x + size.width > width { x = 0; y += rowHeight + spacing; rowHeight = 0 }
            x += size.width + spacing; rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: width, height: y + rowHeight)
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX && x + size.width > bounds.maxX { x = bounds.minX; y += rowHeight + spacing; rowHeight = 0 }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing; rowHeight = max(rowHeight, size.height)
        }
    }
}

@MainActor
private struct MealComposer: View {
    @Environment(\.analyticsProvider) private var analyticsProvider
    @State private var description = ""
    @State private var photoItem: PhotosPickerItem?
    @State private var photoData: Data?
    @State private var showsLibraryPicker = false
    @State private var showsCameraPicker = false
    @Binding var startsCamera: Bool
    @State private var value = FoodEstimateValue(description: "", calories: 0, proteinGrams: 0, carbohydrateGrams: 0, fatGrams: 0, fiberGrams: 0, addedSugarGrams: 0, sodiumMilligrams: 0, confidence: 0)
    @State private var savedMeal: KoiFoodEntry?
    @State private var isFixingNumbers = false
    @State private var isManual = false
    let model: IntakeViewModel
    let estimator: any FoodEstimating
    let onClose: () -> Void

    init(model: IntakeViewModel, estimator: any FoodEstimating, startsCamera: Binding<Bool>, onClose: @escaping () -> Void) {
        self.model = model
        self.estimator = estimator
        _startsCamera = startsCamera
        self.onClose = onClose
    }

    var body: some View {
        VStack(alignment: .leading, spacing: KoiTheme.space.s21) {
            if let savedMeal {
                if isFixingNumbers { fixNumbers(for: savedMeal) }
                else { resultSummary(for: savedMeal) }
            } else {
                TextField("Describe your meal (optional)", text: $description, axis: .vertical)
                    .font(KoiTheme.body).lineLimit(1...3).padding(13)
                    .background(KoiTheme.onBase.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(KoiTheme.onBase.opacity(0.2), lineWidth: 1))
                    .accessibilityLabel("Describe your meal")

                photoAction(title: "Take a photo", symbol: "camera") {
                    #if targetEnvironment(simulator)
                    model.showCameraUnavailable()
                    #else
                    showsCameraPicker = true
                    #endif
                }
                photoAction(title: photoData == nil ? "Upload a photo" : "Photo added", symbol: photoData == nil ? "photo" : "checkmark") {
                    showsLibraryPicker = true
                }

                if let photoData, let image = UIImage(data: photoData) {
                    Image(uiImage: image).resizable().scaledToFit().frame(maxHeight: 190).clipShape(RoundedRectangle(cornerRadius: 12))
                }

                if model.isEstimating {
                    HStack(spacing: KoiTheme.space.s8) {
                        ProgressView().tint(KoiTheme.onBase)
                        Text("Reading your plate…").font(KoiTheme.caption)
                    }.frame(maxWidth: .infinity, alignment: .center).padding(.vertical, KoiTheme.space.s8)
                }

                if let error = model.errorMessage {
                    VStack(alignment: .leading, spacing: KoiTheme.space.s13) {
                        Text(error).font(KoiTheme.caption).foregroundStyle(KoiTheme.onBase.opacity(0.9))
                        HStack(spacing: KoiTheme.space.s13) {
                            if canEstimate { Button("Try again") { Task { await estimateAndSave() } }.buttonStyle(.plain) }
                            Button("Enter manually") { withAnimation(KoiTheme.morph) { isManual = true } }.buttonStyle(.plain)
                        }.font(KoiTheme.caption)
                    }
                }

                if isManual {
                    nutritionFields
                    KoiPrimaryButton(title: "Log meal") { saveManualMeal() }
                        .disabled(model.isEstimating || !canSaveManualMeal)
                } else if !model.isEstimating && canEstimate && !description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    KoiPrimaryButton(title: "Log from description") { Task { await estimateAndSave() } }
                        .disabled(model.isEstimating)
                }
            }
        }
        .foregroundStyle(KoiTheme.onBase)
        .photosPicker(isPresented: $showsLibraryPicker, selection: $photoItem, matching: .images)
        .onChange(of: photoItem) { _, item in loadPhoto(item) }
        .sheet(isPresented: $showsCameraPicker) {
            IntakeCameraPicker { image in
                photoData = image.jpegData(compressionQuality: 0.76)
                if description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { Task { await estimateAndSave() } }
            }
        }
        .onAppear {
            #if DEBUG
            if KoiLaunch.tourState == "photoResult" {
                if let meal = model.meals.first(where: { $0.name == "Protein bar" }) {
                    savedMeal = meal
                    description = meal.notes.isEmpty ? meal.name : meal.notes
                    value = FoodEstimateValue(description: meal.name, calories: meal.calories, proteinGrams: meal.proteinGrams, carbohydrateGrams: meal.carbohydrateGrams, fatGrams: meal.fatGrams, fiberGrams: meal.fiberGrams, addedSugarGrams: meal.addedSugarGrams, sodiumMilligrams: meal.sodiumMilligrams, confidence: meal.confidence)
                    photoData = meal.imageJPEG
                }
            }
            #endif
            guard startsCamera else { return }
            startsCamera = false
            #if targetEnvironment(simulator)
            model.showCameraUnavailable()
            #else
            if UIImagePickerController.isSourceTypeAvailable(.camera) { showsCameraPicker = true }
            #endif
        }
    }

    private var canEstimate: Bool {
        !description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || photoData != nil
    }

    private var canSaveManualMeal: Bool {
        canEstimate || value.calories > 0 || value.proteinGrams > 0 || value.carbohydrateGrams > 0 || value.fatGrams > 0 || value.fiberGrams > 0 || value.addedSugarGrams > 0 || value.sodiumMilligrams > 0
    }

    private func photoAction(title: String, symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: KoiTheme.space.s8) {
                Image(systemName: symbol)
                Text(title).font(KoiTheme.caption)
                Spacer()
                Image(systemName: "sparkles").font(.system(size: 12, weight: .regular))
            }
            .padding(.horizontal, KoiTheme.space.s13)
            .frame(maxWidth: .infinity, minHeight: 48)
            .contentShape(RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(style: StrokeStyle(lineWidth: 1, dash: [5, 4])).foregroundStyle(KoiTheme.onBase.opacity(0.55)))
        }
        .buttonStyle(.plain)
    }

    private func loadPhoto(_ item: PhotosPickerItem?) {
        guard let item else { return }
        Task {
            guard let data = try? await item.loadTransferable(type: Data.self), let jpeg = UIImage(data: data)?.jpegData(compressionQuality: 0.76) else { return }
            photoData = jpeg
            guard description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
            await estimateAndSave()
        }
    }

    private func estimateAndSave() async {
        guard canEstimate, !model.isEstimating, savedMeal == nil else { return }
        model.clearEstimate()
        await model.estimateMeal(text: description, jpegData: photoData, using: estimator)
        guard let estimate = model.estimate else { analyticsProvider.signal("Food.aiFailed"); return }
        value = estimate
        let note = description.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let meal = model.addMeal(estimate, note: note, jpegData: photoData) else { return }
        savedMeal = meal
        analyticsProvider.signal("Food.loggedWithAI")
        KoiHaptics.success()
    }

    private func saveManualMeal() {
        guard savedMeal == nil, canSaveManualMeal else { return }
        let clean = description.trimmingCharacters(in: .whitespacesAndNewlines)
        value.description = clean.isEmpty ? "Meal" : clean
        guard let meal = model.addMeal(value, note: clean, jpegData: photoData) else { return }
        savedMeal = meal
        KoiHaptics.success()
    }

    private func resultSummary(for meal: KoiFoodEntry) -> some View {
        VStack(alignment: .leading, spacing: KoiTheme.space.s13) {
            if let data = meal.imageJPEG, let image = UIImage(data: data) {
                Image(uiImage: image).resizable().scaledToFit().frame(maxHeight: 180).frame(maxWidth: .infinity, alignment: .center).clipShape(RoundedRectangle(cornerRadius: 12))
            }
            HStack(alignment: .firstTextBaseline) {
                Text("~\(Int(meal.calories.rounded())) kcal").font(.system(size: 30, weight: .regular, design: .rounded)).contentTransition(.numericText())
                Spacer()
                Text("\(Int((meal.confidence * 100).rounded()))% sure").font(KoiTheme.caption).opacity(0.78)
            }
            Text(meal.name).font(KoiTheme.body)
            Text("P \(Int(meal.proteinGrams.rounded()))g · C \(Int(meal.carbohydrateGrams.rounded()))g · F \(Int(meal.fatGrams.rounded()))g").font(KoiTheme.caption).opacity(0.82)
            Text("Added to today's totals.").font(KoiTheme.caption).opacity(0.78)
            HStack(spacing: KoiTheme.space.s8) {
                Button { withAnimation(KoiTheme.morph) { isFixingNumbers = true } } label: { GlassChip(title: "Fix numbers", symbol: "slider.horizontal.3") }.buttonStyle(.plain)
                Button(action: logAnother) { GlassChip(title: "Log another", symbol: "plus") }.buttonStyle(.plain)
            }
        }
    }

    private func fixNumbers(for meal: KoiFoodEntry) -> some View {
        VStack(alignment: .leading, spacing: KoiTheme.space.s13) {
            Text("Fix numbers").font(KoiTheme.title)
            TextField("Meal name", text: $value.description).font(KoiTheme.body)
            nutritionFields
            if let error = model.errorMessage { Text(error).font(KoiTheme.caption).foregroundStyle(KoiTheme.onBase.opacity(0.9)) }
            KoiPrimaryButton(title: "Save") {
                let note = description.trimmingCharacters(in: .whitespacesAndNewlines)
                if model.updateMeal(meal, value: value, note: note, jpegData: photoData) {
                    withAnimation(KoiTheme.morph) { isFixingNumbers = false }
                    KoiHaptics.success()
                }
            }
        }
    }

    private func logAnother() {
        description = ""
        photoItem = nil
        photoData = nil
        savedMeal = nil
        isFixingNumbers = false
        isManual = false
        value = FoodEstimateValue(description: "", calories: 0, proteinGrams: 0, carbohydrateGrams: 0, fatGrams: 0, fiberGrams: 0, addedSugarGrams: 0, sodiumMilligrams: 0, confidence: 0)
        model.clearEstimate()
    }

    private var nutritionFields: some View {
        VStack(spacing: KoiTheme.space.s8) {
            numberField("Calories", value: $value.calories, unit: "kcal")
            numberField("Protein", value: $value.proteinGrams, unit: "g")
            numberField("Carbs", value: $value.carbohydrateGrams, unit: "g")
            numberField("Fat", value: $value.fatGrams, unit: "g")
            numberField("Fiber", value: $value.fiberGrams, unit: "g")
            numberField("Added sugar", value: $value.addedSugarGrams, unit: "g")
            numberField("Sodium", value: $value.sodiumMilligrams, unit: "mg")
        }
    }

    private func numberField(_ label: String, value: Binding<Double>, unit: String) -> some View {
        HStack { Text(label).font(KoiTheme.caption); Spacer(); TextField("0", value: value, format: .number).keyboardType(.decimalPad).multilineTextAlignment(.trailing).font(KoiTheme.body).frame(width: 82); Text(unit).font(KoiTheme.caption).opacity(0.7) }
            .padding(.horizontal, KoiTheme.space.s13).padding(.vertical, KoiTheme.space.s8).background(.ultraThinMaterial.opacity(0.18), in: RoundedRectangle(cornerRadius: 14))
    }
}

@MainActor
private struct MealDetailSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var detail = ""
    @State private var estimate: FoodEstimateValue
    @State private var note: String
    @State private var isEstimating = false
    let meal: KoiFoodEntry
    let model: IntakeViewModel
    let estimator: any FoodEstimating

    init(meal: KoiFoodEntry, model: IntakeViewModel, estimator: any FoodEstimating) {
        self.meal = meal; self.model = model; self.estimator = estimator
        _note = State(initialValue: meal.notes)
        _estimate = State(initialValue: FoodEstimateValue(description: meal.name, calories: meal.calories, proteinGrams: meal.proteinGrams, carbohydrateGrams: meal.carbohydrateGrams, fatGrams: meal.fatGrams, fiberGrams: meal.fiberGrams, addedSugarGrams: meal.addedSugarGrams, sodiumMilligrams: meal.sodiumMilligrams, confidence: meal.confidence))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: KoiTheme.space.s13) {
                    TextField("Meal name", text: $estimate.description).font(KoiTheme.title)
                    TextField("Notes", text: $note, axis: .vertical).font(KoiTheme.caption).lineLimit(1...3).padding(13).background(.ultraThinMaterial.opacity(0.2), in: RoundedRectangle(cornerRadius: 14))
                    TextField("A little more detail for a better estimate", text: $detail, axis: .vertical).font(KoiTheme.caption).lineLimit(2...4).padding(13).background(.ultraThinMaterial.opacity(0.28), in: RoundedRectangle(cornerRadius: 16))
                    KoiPrimaryButton(title: isEstimating ? "Estimating" : "Refine estimate") {
                        isEstimating = true
                        Task { if let updated = await model.refineMeal(meal, detail: detail, using: estimator) { estimate = updated }; isEstimating = false }
                    }.disabled(detail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isEstimating)
                    ForEach(Array(fields.enumerated()), id: \.offset) { _, item in item }
                    KoiPrimaryButton(title: "Save changes") { model.updateMeal(meal, value: estimate, note: note, jpegData: meal.imageJPEG); dismiss() }
                    Button("Delete meal", role: .destructive) { model.deleteMeal(meal); dismiss() }.font(KoiTheme.caption).frame(maxWidth: .infinity).padding(.top, 8)
                }.padding(KoiTheme.space.s21)
            }.background(KoiBackground().ignoresSafeArea()).foregroundStyle(KoiTheme.onBase)
                .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Close") { dismiss() }.font(KoiTheme.caption) } }
        }.preferredColorScheme(.dark)
    }

    private var fields: [AnyView] {
        [field("Calories", \FoodEstimateValue.calories, "kcal"), field("Protein", \FoodEstimateValue.proteinGrams, "g"), field("Carbs", \FoodEstimateValue.carbohydrateGrams, "g"), field("Fat", \FoodEstimateValue.fatGrams, "g"), field("Fiber", \FoodEstimateValue.fiberGrams, "g"), field("Added sugar", \FoodEstimateValue.addedSugarGrams, "g"), field("Sodium", \FoodEstimateValue.sodiumMilligrams, "mg")]
    }
    private func field(_ name: String, _ keyPath: WritableKeyPath<FoodEstimateValue, Double>, _ unit: String) -> AnyView {
        AnyView(HStack { Text(name).font(KoiTheme.caption); Spacer(); TextField("0", value: Binding(get: { estimate[keyPath: keyPath] }, set: { estimate[keyPath: keyPath] = max(0, $0) }), format: .number).keyboardType(.decimalPad).multilineTextAlignment(.trailing).font(KoiTheme.body).frame(width: 85); Text(unit).font(KoiTheme.caption).opacity(0.7) }.padding(13).background(.ultraThinMaterial.opacity(0.18), in: RoundedRectangle(cornerRadius: 14)))
    }
}

private struct NutrientQuickEntry: View {
    @Environment(\.dismiss) private var dismiss
    @State private var selectedKey = "calories"
    @State private var amount = ""
    let model: IntakeViewModel
    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: KoiTheme.space.s21) {
                Text("Adjust a total.").font(KoiTheme.title)
                Picker("Nutrient", selection: $selectedKey) { ForEach(model.nutrientRows) { Text($0.name).tag($0.key) } }.pickerStyle(.menu).tint(KoiTheme.onBase)
                TextField("Amount", text: $amount).keyboardType(.decimalPad).font(KoiTheme.body).padding(13).background(.ultraThinMaterial.opacity(0.28), in: RoundedRectangle(cornerRadius: 16))
                KoiPrimaryButton(title: "Set total") { if let value = Double(amount) { model.setValue(selectedKey, to: value); dismiss() } }
                Spacer()
            }.padding(KoiTheme.space.s21).background(KoiBackground().ignoresSafeArea()).foregroundStyle(KoiTheme.onBase)
                .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Close") { dismiss() }.font(KoiTheme.caption) } }
        }.preferredColorScheme(.dark)
    }
}

private struct NutrientEditor: View {
    @Environment(\.dismiss) private var dismiss
    @State private var showAdd = false
    @State private var customName = ""
    @State private var customUnit = "g"
    @State private var customGoal = "100"
    @State private var customStep = "5"
    let model: IntakeViewModel
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: KoiTheme.space.s13) {
                    Text("Choose what to follow.").font(KoiTheme.title)
                    ForEach(model.nutrientRows) { nutrient in
                        VStack(alignment: .leading, spacing: KoiTheme.space.s8) {
                            HStack {
                                TextField("Metric name", text: Binding(get: { nutrient.name }, set: { model.renameNutrient(nutrient.key, name: $0, unit: nutrient.unit) }))
                                    .font(KoiTheme.body)
                                Spacer()
                                Button("Remove") { model.removeNutrient(nutrient.key) }.font(KoiTheme.caption).buttonStyle(.plain)
                            }
                            HStack {
                                ForEach(NutrientGoalType.allCases, id: \.self) { type in
                                    goalTypeButton(type, for: nutrient)
                                }
                            }
                            HStack { Text("Daily target").font(KoiTheme.caption).opacity(0.8); Spacer(); TextField("\(Int(nutrient.goal))", value: Binding(get: { nutrient.goal }, set: { model.setGoal(nutrient.key, value: $0) }), format: .number).keyboardType(.decimalPad).multilineTextAlignment(.trailing).font(KoiTheme.body).frame(width: 95); Text(nutrient.unit).font(KoiTheme.caption) }
                        }.padding(13).background(.ultraThinMaterial.opacity(0.2), in: RoundedRectangle(cornerRadius: 16))
                    }
                    Button("Add a metric") { showAdd = true }.font(KoiTheme.caption).frame(maxWidth: .infinity).padding(13).overlay(RoundedRectangle(cornerRadius: 16).stroke(KoiTheme.onBase.opacity(0.3)))
                }.padding(KoiTheme.space.s21)
            }.background(KoiBackground().ignoresSafeArea()).foregroundStyle(KoiTheme.onBase)
                .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() }.font(KoiTheme.caption) } }
                .confirmationDialog("Add a metric", isPresented: $showAdd, titleVisibility: .visible) {
                    Button("Added sugar") { model.addPreset("added_sugar") }
                    Button("Carbs") { model.addPreset("carbs") }
                    Button("Fat") { model.addPreset("fat") }
                    Button("Sodium") { model.addPreset("sodium") }
                    Button("Custom metric") { showCustom = true }
                }
                .sheet(isPresented: $showCustom) { customSheet }
        }.preferredColorScheme(.dark)
    }

    private func goalTypeButton(_ type: NutrientGoalType, for nutrient: IntakeNutrient) -> some View {
        let selected = nutrient.goalType == type
        return Button(type.label) { model.setGoalType(nutrient.key, type: type) }
            .font(KoiTheme.caption)
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .background(selected ? KoiTheme.onBase.opacity(0.2) : Color.clear, in: Capsule())
            .overlay(Capsule().stroke(KoiTheme.onBase.opacity(0.2), lineWidth: 1))
            .buttonStyle(.plain)
    }
    @State private var showCustom = false
    private var customSheet: some View {
        NavigationStack {
            VStack(spacing: KoiTheme.space.s13) {
                TextField("Name", text: $customName).font(KoiTheme.body)
                TextField("Unit", text: $customUnit).font(KoiTheme.body)
                TextField("Daily target", text: $customGoal).keyboardType(.decimalPad).font(KoiTheme.body)
                TextField("Adjustment step", text: $customStep).keyboardType(.decimalPad).font(KoiTheme.body)
                KoiPrimaryButton(title: "Add metric") { model.addCustomNutrient(name: customName, unit: customUnit, goal: Double(customGoal) ?? 100, step: Double(customStep) ?? 5); showCustom = false }
            }.padding(KoiTheme.space.s21).background(KoiBackground().ignoresSafeArea()).foregroundStyle(KoiTheme.onBase)
        }.preferredColorScheme(.dark).presentationDetents([.medium])
    }
}

private extension NutrientGoalType {
    var label: String { switch self { case .reach: "Reach"; case .limit: "Limit"; case .around: "Around"; case .track: "Track" } }
}
