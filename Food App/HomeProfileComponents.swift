import SwiftUI

struct ProfileHubRow: View {
    let title: String
    let systemImage: String

    var body: some View {
        Label(title, systemImage: systemImage)
    }
}

struct PlanProfileDetailView<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        Form { content }
            .navigationTitle("Plan & Goals")
            .navigationBarTitleDisplayMode(.inline)
    }
}

struct BodyProfileDetailView<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        Form { content }
            .navigationTitle("Body Details")
            .navigationBarTitleDisplayMode(.inline)
    }
}

struct FoodPreferencesProfileDetailView<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        Form { content }
            .navigationTitle("Food Preferences")
            .navigationBarTitleDisplayMode(.inline)
    }
}

struct HealthInsightsProfileDetailView<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        Form { content }
            .navigationTitle("Health & Insights")
            .navigationBarTitleDisplayMode(.inline)
    }
}

struct AccountProfileDetailView<Content: View>: View {
    let title: String
    let content: Content

    init(title: String = "Account & App", @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        Form { content }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
    }
}

struct AdminProfileDetailView<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        Form { content }
            .navigationTitle("Admin")
            .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Height / Weight Wheel Pickers

struct HeightPickerView: View {
    @Binding var draft: OnboardingDraft

    var body: some View {
        Group {
            if (draft.units ?? .imperial) == .imperial {
                imperialBody
            } else {
                metricBody
            }
        }
        .navigationTitle("Height")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var imperialBody: some View {
        let fi = draft.imperialHeightFeetInches
        let feetBinding = Binding<Int>(
            get: { fi.feet },
            set: { newFeet in
                draft.imperialHeightFeetInches = (newFeet, draft.imperialHeightFeetInches.inches)
                draft.baselineTouchedHeight = true
            }
        )
        let inchesBinding = Binding<Int>(
            get: { fi.inches },
            set: { newInches in
                draft.imperialHeightFeetInches = (draft.imperialHeightFeetInches.feet, newInches)
                draft.baselineTouchedHeight = true
            }
        )
        return HStack(spacing: 0) {
            Picker("Feet", selection: feetBinding) {
                ForEach(OnboardingBaselineRange.minImperialFeet ... OnboardingBaselineRange.maxImperialFeet, id: \.self) { f in
                    Text("\(f) ft").tag(f)
                }
            }
            .pickerStyle(.wheel)
            .frame(maxWidth: .infinity)

            Picker("Inches", selection: inchesBinding) {
                ForEach(0 ... 11, id: \.self) { i in
                    Text("\(i) in").tag(i)
                }
            }
            .pickerStyle(.wheel)
            .frame(maxWidth: .infinity)
        }
        .padding(.horizontal)
    }

    private var metricBody: some View {
        let cmBinding = Binding<Int>(
            get: { Int(draft.heightMetricValue) },
            set: { newValue in
                draft.heightMetricValue = Double(newValue)
                draft.baselineTouchedHeight = true
            }
        )
        return Picker("Height", selection: cmBinding) {
            ForEach(OnboardingBaselineRange.heightCm, id: \.self) { cm in
                Text("\(cm) cm").tag(cm)
            }
        }
        .pickerStyle(.wheel)
        .padding(.horizontal)
    }
}

struct WeightPickerView: View {
    @Binding var draft: OnboardingDraft

    var body: some View {
        let isMetric = (draft.units ?? .imperial) == .metric
        let range: ClosedRange<Int>
        let unit: String
        if isMetric {
            range = Int(OnboardingBaselineRange.weightKg.lowerBound) ... Int(OnboardingBaselineRange.weightKg.upperBound)
            unit = "kg"
        } else {
            range = Int(OnboardingBaselineRange.weightLb.lowerBound) ... Int(OnboardingBaselineRange.weightLb.upperBound)
            unit = "lbs"
        }

        let weightBinding = Binding<Int>(
            get: { Int(draft.weightValue) },
            set: { newValue in
                draft.weightValue = Double(newValue)
                draft.baselineTouchedWeight = true
            }
        )

        return Picker("Weight", selection: weightBinding) {
            ForEach(range, id: \.self) { w in
                Text("\(w) \(unit)").tag(w)
            }
        }
        .pickerStyle(.wheel)
        .padding(.horizontal)
        .navigationTitle("Weight")
        .navigationBarTitleDisplayMode(.inline)
    }
}
