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

// MARK: - Body Wheel Pickers

struct AgePickerView: View {
    @Binding var draft: OnboardingDraft

    var body: some View {
        ProfileWheelPickerPage(
            title: "Age",
            headline: "How old are you?",
            subtitle: "Used with your body details to estimate baseline calories"
        ) {
            ProfileWheelPickerCard(unitLabel: "years") {
                FocalWheelPicker(
                    value: Int(draft.ageValue.rounded()),
                    range: OnboardingBaselineRange.age,
                    onSet: { newValue in
                        draft.ageValue = Double(newValue)
                        draft.baselineTouchedAge = true
                    }
                )
            }
            .padding(.horizontal)
        }
    }
}

struct HeightPickerView: View {
    @Binding var draft: OnboardingDraft

    var body: some View {
        ProfileWheelPickerPage(
            title: "Height",
            headline: "How tall are you?",
            subtitle: "We'll use this to personalize your plan",
            toggle: {
                ProfileUnitToggle(selection: unitsBinding, leftLabel: "Cm", rightLabel: "Feet")
            }
        ) {
            if (draft.units ?? .imperial) == .imperial {
                imperialBody
            } else {
                metricBody
            }
        }
    }

    private var imperialBody: some View {
        HStack(spacing: 8) {
            ProfileWheelPickerCard(unitLabel: "ft") {
                FocalWheelPicker(
                    value: draft.imperialHeightFeetInches.feet,
                    range: OnboardingBaselineRange.minImperialFeet...OnboardingBaselineRange.maxImperialFeet,
                    onSet: { setFeet($0) },
                    pickerWidth: 100
                )
            }

            ProfileWheelPickerCard(unitLabel: "in") {
                FocalWheelPicker(
                    value: draft.imperialHeightFeetInches.inches,
                    range: 0...maxInches,
                    onSet: { setInches($0) },
                    pickerWidth: 100
                )
            }
        }
        .padding(.horizontal)
    }

    private var metricBody: some View {
        ProfileWheelPickerCard(unitLabel: "cm") {
            FocalWheelPicker(
                value: Int(draft.heightMetricValue.rounded()),
                range: OnboardingBaselineRange.heightCm,
                onSet: { newValue in
                    draft.heightMetricValue = Double(newValue)
                    draft.baselineTouchedHeight = true
                }
            )
        }
        .padding(.horizontal)
    }

    private var unitsBinding: Binding<UnitsOption> {
        Binding(
            get: { draft.units ?? .imperial },
            set: { newUnit in
                draft.setUnitsPreservingBaseline(newUnit)
                draft.baselineTouchedHeight = true
            }
        )
    }

    private var maxInches: Int {
        draft.imperialHeightFeetInches.feet == OnboardingBaselineRange.maxImperialFeet
            ? OnboardingBaselineRange.maxInchesForMaxFeet
            : 11
    }

    private func setFeet(_ newFeet: Int) {
        var value = draft.imperialHeightFeetInches
        value.feet = newFeet
        let localMaxInches = newFeet == OnboardingBaselineRange.maxImperialFeet
            ? OnboardingBaselineRange.maxInchesForMaxFeet
            : 11
        if value.inches > localMaxInches {
            value.inches = localMaxInches
        }
        draft.imperialHeightFeetInches = value
        draft.baselineTouchedHeight = true
    }

    private func setInches(_ newInches: Int) {
        var value = draft.imperialHeightFeetInches
        value.inches = min(newInches, maxInches)
        draft.imperialHeightFeetInches = value
        draft.baselineTouchedHeight = true
    }
}

private struct ProfileWheelPickerPage<Content: View, Toggle: View>: View {
    let title: String
    let headline: String
    let subtitle: String
    @ViewBuilder let toggle: () -> Toggle
    @ViewBuilder let content: () -> Content

    init(
        title: String,
        headline: String,
        subtitle: String,
        @ViewBuilder toggle: @escaping () -> Toggle,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.title = title
        self.headline = headline
        self.subtitle = subtitle
        self.toggle = toggle
        self.content = content
    }

    var body: some View {
        ZStack {
            OnboardingStaticBackground()

            VStack(spacing: 0) {
                Text(headline)
                    .font(OnboardingTypography.instrumentSerif(style: .regular, size: 34))
                    .foregroundStyle(OnboardingGlassTheme.textPrimary)
                    .multilineTextAlignment(.center)
                    .padding(.top, 24)

                Text(subtitle)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(OnboardingGlassTheme.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.top, 8)
                    .padding(.horizontal, 28)

                toggle()
                    .padding(.top, 18)

                Spacer(minLength: 28)

                content()

                Spacer(minLength: 36)
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }
}

private extension ProfileWheelPickerPage where Toggle == EmptyView {
    init(
        title: String,
        headline: String,
        subtitle: String,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.title = title
        self.headline = headline
        self.subtitle = subtitle
        self.toggle = { EmptyView() }
        self.content = content
    }
}

private struct ProfileWheelPickerCard<Content: View>: View {
    let unitLabel: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(spacing: 0) {
            content()

            Text(unitLabel)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(OnboardingGlassTheme.textSecondary)
                .padding(.top, 4)
        }
        .padding(.vertical, 20)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(Color.white.opacity(0.86))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(OnboardingGlassTheme.panelStroke, lineWidth: 1)
        )
        .shadow(color: OnboardingGlassTheme.buttonShadow.opacity(0.35), radius: 18, y: 10)
    }
}

private struct ProfileUnitToggle: View {
    @Binding var selection: UnitsOption
    let leftLabel: String
    let rightLabel: String

    @Namespace private var toggleNamespace

    var body: some View {
        HStack(spacing: 0) {
            toggleTab(label: leftLabel, tag: .metric)
            toggleTab(label: rightLabel, tag: .imperial)
        }
        .padding(3)
        .frame(maxWidth: 220)
        .frame(height: 42)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.ultraThinMaterial)
        )
    }

    private func toggleTab(label: String, tag: UnitsOption) -> some View {
        Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                selection = tag
            }
        } label: {
            Text(label)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(selection == tag ? OnboardingGlassTheme.ctaForeground : OnboardingGlassTheme.textPrimary)
                .frame(maxWidth: .infinity)
                .frame(height: 34)
                .background {
                    if selection == tag {
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .fill(OnboardingGlassTheme.ctaBackground)
                            .matchedGeometryEffect(id: "profile-unit-pill", in: toggleNamespace)
                    }
                }
        }
        .buttonStyle(.plain)
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

        return ProfileWheelPickerPage(
            title: "Weight",
            headline: "How much do you weigh?",
            subtitle: "We'll use this to personalize your plan",
            toggle: {
                ProfileUnitToggle(selection: unitsBinding, leftLabel: "Kg", rightLabel: "lbs")
            }
        ) {
            ProfileWheelPickerCard(unitLabel: unit) {
                FocalWheelPicker(
                    value: weightBinding.wrappedValue,
                    range: range,
                    onSet: { newValue in
                        weightBinding.wrappedValue = newValue
                    }
                )
            }
            .padding(.horizontal)
        }
    }

    private var unitsBinding: Binding<UnitsOption> {
        Binding(
            get: { draft.units ?? .imperial },
            set: { newUnit in
                draft.setUnitsPreservingBaseline(newUnit)
                draft.baselineTouchedWeight = true
            }
        )
    }
}
