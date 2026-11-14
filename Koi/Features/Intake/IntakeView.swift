import PhotosUI
import SwiftData
import SwiftUI
import UIKit
import KoiShared

struct IntakeView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.foodEstimator) private var foodEstimator
    @State private var model = IntakeViewModel()
    @State private var showsMealComposer = false
    @State private var selectedMeal: KoiFoodEntry?
    @State private var showsNutrients = false
    @State private var showsSupplementComposer = false
    @State private var supplementName = ""
    @State private var showsEntrySheet = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: KoiTheme.space.s21) {
                header
                calorieCard
                nutrientsSection
                supplementsSection
                mealSection
            }
            .padding(.horizontal, KoiTheme.space.s21)
            .padding(.top, KoiTheme.space.s21)
            .padding(.bottom, KoiTheme.space.s55)
        }
        .background(KoiBackground().ignoresSafeArea())
        .foregroundStyle(KoiTheme.onBase)
        .onAppear { model.load(modelContext) }
        .sheet(isPresented: $showsMealComposer) {
            MealComposer(model: model, estimator: foodEstimator)
                .presentationDetents([.large])
        }
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
        .alert("", isPresented: Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.clearEstimate() } })) {
            Button("OK", role: .cancel) { model.clearEstimate() }
        } message: { Text(model.errorMessage ?? "") }
    }

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: KoiTheme.space.s5) {
                Text("INTAKE").font(KoiTheme.section).tracking(2.4)
                Text("Eat with ease.").font(KoiTheme.title)
            }
            Spacer()
            Button { showsNutrients = true } label: {
                Image(systemName: "slider.horizontal.3").font(.system(size: 18, weight: .light))
                    .frame(width: 44, height: 44).background(.ultraThinMaterial.opacity(0.45), in: Circle())
                    .overlay(Circle().stroke(KoiTheme.onBase.opacity(0.26), lineWidth: 1))
            }.buttonStyle(.plain).accessibilityLabel("Edit nutrition goals")
        }
    }

    private var calorieCard: some View {
        VStack(spacing: KoiTheme.space.s13) {
            ZStack {
                IntakeCalorieDial(progress: 1)
                    .stroke(KoiTheme.onBase.opacity(0.24), style: StrokeStyle(lineWidth: 12, lineCap: .round))
                    .overlay {
                        IntakeCalorieDial(progress: min(model.calories / max(model.calorieGoal, 1), 1))
                            .stroke(KoiTheme.onBase.opacity(0.83), style: StrokeStyle(lineWidth: 12, lineCap: .round))
                    }
                VStack(spacing: KoiTheme.space.s5) {
                    Text(Int(model.calories.rounded()).formatted()).font(KoiTheme.hero)
                    Text("OF \(Int(model.calorieGoal).formatted()) KCAL").font(KoiTheme.caption).tracking(1.6).opacity(0.78)
                }.offset(y: 14)
            }
            .frame(height: 176)
            Text("A steady guide, not a rulebook.").font(KoiTheme.caption).opacity(0.8)
            HStack(spacing: KoiTheme.space.s8) {
                KoiPrimaryButton(title: "Add food") { showsMealComposer = true }
                Button { showsEntrySheet = true } label: {
                    Image(systemName: "plus").font(.system(size: 17, weight: .regular))
                        .frame(width: 50, height: 50).background(.ultraThinMaterial.opacity(0.45), in: Circle())
                        .overlay(Circle().stroke(KoiTheme.onBase.opacity(0.3), lineWidth: 1))
                }.buttonStyle(.plain).accessibilityLabel("Adjust nutrition")
            }
        }
        .frame(maxWidth: .infinity).padding(.vertical, KoiTheme.space.s21)
        .background(.ultraThinMaterial.opacity(0.27), in: RoundedRectangle(cornerRadius: 25))
        .overlay(RoundedRectangle(cornerRadius: 25).stroke(KoiTheme.onBase.opacity(0.22), lineWidth: 1))
    }

    private var nutrientsSection: some View {
        VStack(alignment: .leading, spacing: KoiTheme.space.s8) {
            sectionHeading("NUTRIENTS", action: "Edit") { showsNutrients = true }
            VStack(spacing: 0) {
                ForEach(model.nutrientRows) { nutrient in
                    NutrientRow(nutrient: nutrient, decrement: { model.changeNutrient(nutrient.key, by: -nutrient.step) }, increment: { model.changeNutrient(nutrient.key, by: nutrient.step) })
                    if nutrient.id != model.nutrientRows.last?.id { Divider().overlay(KoiTheme.onBase.opacity(0.16)).padding(.leading, KoiTheme.space.s13) }
                }
            }
            .padding(.horizontal, KoiTheme.space.s13)
            .background(.ultraThinMaterial.opacity(0.22), in: RoundedRectangle(cornerRadius: 20))
            .overlay(RoundedRectangle(cornerRadius: 20).stroke(KoiTheme.onBase.opacity(0.22), lineWidth: 1))
            HStack { Text("NUTRITION BALANCE").font(KoiTheme.caption).tracking(1.4); Spacer(); Text("\(Int((model.score.score * 100).rounded()))%").font(KoiTheme.caption) }
                .opacity(0.8).padding(.horizontal, KoiTheme.space.s13).padding(.top, KoiTheme.space.s5)
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
}

private struct IntakeCalorieDial: Shape {
    var progress: Double
    func path(in rect: CGRect) -> Path {
        let radius = min(rect.width, rect.height) / 2 - 9
        let center = CGPoint(x: rect.midX, y: rect.midY + 5)
        var path = Path()
        path.addArc(center: center, radius: radius, startAngle: .degrees(205), endAngle: .degrees(335), clockwise: false)
        return path.trimmedPath(from: 0, to: progress)
    }
}

private struct NutrientRow: View {
    let nutrient: IntakeNutrient
    let decrement: () -> Void
    let increment: () -> Void
    var body: some View {
        HStack(spacing: KoiTheme.space.s8) {
            VStack(alignment: .leading, spacing: 3) {
                Text(nutrient.name).font(KoiTheme.body)
                Text(goalCaption).font(KoiTheme.caption).opacity(0.7)
            }
            Spacer(minLength: 4)
            Button(action: decrement) { Image(systemName: "minus").frame(width: 30, height: 36) }.accessibilityLabel("Decrease \(nutrient.name)")
            Text("\(Int(nutrient.value.rounded())) \(nutrient.unit)").font(KoiTheme.caption).monospacedDigit().frame(minWidth: 66, alignment: .trailing)
            Button(action: increment) { Image(systemName: "plus").frame(width: 30, height: 36) }.accessibilityLabel("Increase \(nutrient.name)")
        }
        .foregroundStyle(KoiTheme.onBase).buttonStyle(.plain).padding(.vertical, KoiTheme.space.s5)
        .overlay(alignment: .bottomLeading) {
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(KoiTheme.onBase.opacity(0.18))
                    Capsule().fill(KoiTheme.onBase.opacity(0.72)).frame(width: (proxy.size.width - 2 * KoiTheme.space.s13) * fraction)
                }
                .frame(height: 2)
                .padding(.horizontal, KoiTheme.space.s13)
            }
            .frame(height: 2)
            .offset(y: 1)
            .allowsHitTesting(false)
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
    @Environment(\.dismiss) private var dismiss
    @State private var description = ""
    @State private var photoItem: PhotosPickerItem?
    @State private var photoData: Data?
    @State private var showsLibraryPicker = false
    @State private var showsCameraPicker = false
    @State private var value = FoodEstimateValue(description: "", calories: 0, proteinGrams: 0, carbohydrateGrams: 0, fatGrams: 0, fiberGrams: 0, addedSugarGrams: 0, sodiumMilligrams: 0, confidence: 0)
    @State private var isManual = false
    let model: IntakeViewModel
    let estimator: any FoodEstimating

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: KoiTheme.space.s21) {
                    Text("Add a meal or snack.").font(KoiTheme.title)
                    TextField("What did you have?", text: $description, axis: .vertical)
                        .font(KoiTheme.body).lineLimit(2...4).padding(13).background(.ultraThinMaterial.opacity(0.28), in: RoundedRectangle(cornerRadius: 16))
                    Button { showsLibraryPicker = true } label: {
                        HStack(spacing: 8) { Image(systemName: photoData == nil ? "photo" : "checkmark"); Text(photoData == nil ? "Choose a photo" : "Photo added") }.font(KoiTheme.caption).padding(13).frame(maxWidth: .infinity).background(.ultraThinMaterial.opacity(0.28), in: RoundedRectangle(cornerRadius: 16))
                    }.buttonStyle(.plain)
                    .photosPicker(isPresented: $showsLibraryPicker, selection: $photoItem, matching: .images)
                    .onChange(of: photoItem) { _, item in
                        Task { if let data = try? await item?.loadTransferable(type: Data.self) { photoData = UIImage(data: data)?.jpegData(compressionQuality: 0.76) } }
                    }
                    if UIImagePickerController.isSourceTypeAvailable(.camera) {
                        Button { showsCameraPicker = true } label: {
                            HStack(spacing: 8) { Image(systemName: "camera"); Text("Take a photo") }.font(KoiTheme.caption).padding(13).frame(maxWidth: .infinity).background(.ultraThinMaterial.opacity(0.18), in: RoundedRectangle(cornerRadius: 16))
                        }.buttonStyle(.plain)
                    }
                    if let photoData, let image = UIImage(data: photoData) { Image(uiImage: image).resizable().scaledToFit().frame(maxHeight: 200).clipShape(RoundedRectangle(cornerRadius: 16)) }
                    if let estimate = model.estimate {
                        estimateSummary(estimate)
                        if estimate.confidence < 0.55 { Text("This is a rough estimate. You can adjust the numbers before saving.").font(KoiTheme.caption).opacity(0.8) }
                    }
                    if isManual || model.estimate != nil { nutritionFields }
                    KoiPrimaryButton(title: model.isEstimating ? "Estimating" : (model.estimate == nil && !isManual ? "Estimate meal" : "Save meal")) {
                        if model.estimate == nil && !isManual {
                            Task { await model.estimateMeal(text: description, jpegData: photoData, using: estimator); if let estimated = model.estimate { value = estimated } }
                        } else {
                            let cleanDescription = description.trimmingCharacters(in: .whitespacesAndNewlines)
                            let finalValue = FoodEstimateValue(description: cleanDescription.isEmpty ? value.description : cleanDescription, calories: value.calories, proteinGrams: value.proteinGrams, carbohydrateGrams: value.carbohydrateGrams, fatGrams: value.fatGrams, fiberGrams: value.fiberGrams, addedSugarGrams: value.addedSugarGrams, sodiumMilligrams: value.sodiumMilligrams, confidence: value.confidence)
                            model.addMeal(finalValue, note: cleanDescription, jpegData: photoData)
                            dismiss()
                        }
                    }.disabled(model.isEstimating || description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    if model.estimate == nil && !isManual {
                        Button("Enter numbers yourself") { isManual = true }.font(KoiTheme.caption).frame(maxWidth: .infinity).buttonStyle(.plain)
                    }
                    if let error = model.errorMessage { Text(error).font(KoiTheme.caption).foregroundStyle(KoiTheme.onBase.opacity(0.85)) }
                }.padding(KoiTheme.space.s21)
            }
            .background(KoiBackground().ignoresSafeArea())
            .foregroundStyle(KoiTheme.onBase)
            .sheet(isPresented: $showsCameraPicker) {
                IntakeCameraPicker { image in photoData = image.jpegData(compressionQuality: 0.76) }
            }
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Close") { dismiss() }.font(KoiTheme.caption) } }
        }.preferredColorScheme(.dark)
    }

    private func estimateSummary(_ estimate: FoodEstimateValue) -> some View {
        VStack(alignment: .leading, spacing: KoiTheme.space.s8) {
            Text(estimate.description).font(KoiTheme.body)
            Text("Estimate · \(Int(estimate.confidence * 100))% confidence").font(KoiTheme.caption).opacity(0.7)
        }.padding(KoiTheme.space.s13).frame(maxWidth: .infinity, alignment: .leading).background(.ultraThinMaterial.opacity(0.28), in: RoundedRectangle(cornerRadius: 16))
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
