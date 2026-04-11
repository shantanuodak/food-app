import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

enum BaselineScreenStep: Int, CaseIterable {
    case sex
    case height
    case weight

    var title: String {
        switch self {
        case .sex:
            return "Sex"
        case .height:
            return "Height"
        case .weight:
            return "Weight"
        }
    }

    var headline: String {
        switch self {
        case .sex:
            return "What sex should we use for your calorie estimate?"
        case .height:
            return "How tall are you?"
        case .weight:
            return "How much do you weigh today?"
        }
    }
}

struct OB03BaselineScreen: View {
    @Binding var draft: OnboardingDraft
    @Binding var step: BaselineScreenStep
    let onBack: () -> Void
    let onContinue: () -> Void

    private var isMetric: Bool {
        (draft.units ?? .metric) == .metric
    }

    private var titleText: String {
        step.title
    }

    private var headlineText: String {
        step.headline
    }

    private var subtitleText: String {
        switch step {
        case .sex:
            return "We use this together with age, height, and weight to estimate baseline calories."
        case .height:
            return "We will use this to calculate BMI"
        case .weight:
            return "We will use this to calculate BMI"
        }
    }

    private var continueLabel: String {
        "Continue"
    }

    private var selectedSex: SexOption? {
        draft.baselineTouchedSex ? draft.sex : nil
    }

    private var canContinueStep: Bool {
        switch step {
        case .sex:
            return draft.baselineTouchedSex && draft.sex != nil
        case .height:
            return !draft.height.isEmpty
        case .weight:
            return draft.baselineTouchedAge && !draft.age.isEmpty && !draft.weight.isEmpty
        }
    }

    private var metricHeights: [Int] {
        Array(OnboardingBaselineRange.heightCm)
    }

    private var imperialFeet: [Int] {
        Array(OnboardingBaselineRange.minImperialFeet ... OnboardingBaselineRange.maxImperialFeet)
    }

    private var imperialInches: [Int] {
        let feet = draft.imperialHeightFeetInches.feet
        let maxInches = feet == OnboardingBaselineRange.maxImperialFeet ? OnboardingBaselineRange.maxInchesForMaxFeet : 11
        return Array(0 ... maxInches)
    }

    private var metricWeights: [Int] {
        Array(Int(OnboardingBaselineRange.weightKg.lowerBound) ... Int(OnboardingBaselineRange.weightKg.upperBound))
    }

    private var imperialWeights: [Int] {
        Array(Int(OnboardingBaselineRange.weightLb.lowerBound) ... Int(OnboardingBaselineRange.weightLb.upperBound))
    }

    private var metricHeightSelection: Binding<Int> {
        Binding(
            get: { Int(draft.heightMetricValue.rounded()) },
            set: { newValue in
                draft.heightMetricValue = Double(newValue)
                draft.baselineTouchedHeight = true
            }
        )
    }

    private var imperialFeetSelection: Binding<Int> {
        Binding(
            get: { draft.imperialHeightFeetInches.feet },
            set: { newValue in
                var value = draft.imperialHeightFeetInches
                value.feet = newValue
                draft.imperialHeightFeetInches = value
                draft.baselineTouchedHeight = true
            }
        )
    }

    private var imperialInchesSelection: Binding<Int> {
        Binding(
            get: { min(draft.imperialHeightFeetInches.inches, imperialInches.last ?? 0) },
            set: { newValue in
                var value = draft.imperialHeightFeetInches
                value.inches = newValue
                draft.imperialHeightFeetInches = value
                draft.baselineTouchedHeight = true
            }
        )
    }

    private var metricWeightSelection: Binding<Int> {
        Binding(
            get: { Int(draft.weightValue.rounded()) },
            set: { newValue in
                draft.weight = String(newValue)
                draft.baselineTouchedWeight = true
            }
        )
    }

    private var imperialWeightSelection: Binding<Int> {
        Binding(
            get: { Int(draft.weightValue.rounded()) },
            set: { newValue in
                draft.weight = String(newValue)
                draft.baselineTouchedWeight = true
            }
        )
    }

    @State private var appeared = false

    var body: some View {
        ZStack {
            OnboardingStaticBackground()

            VStack(spacing: 0) {
                topBar
                    .padding(.top, 12)
                    .padding(.horizontal, 16)

                if step == .weight {
                    heroStepLayout(
                        headline: "How much do you weigh?",
                        subtitle: "We'll use this to personalize your plan",
                        toggle: { UnitToggle(selection: weightUnitBinding, leftLabel: "Kg", rightLabel: "lbs") }
                    ) {
                        weightStepView
                    }
                } else if step == .height {
                    heroStepLayout(
                        headline: "How tall are you?",
                        subtitle: "We'll use this to personalize your plan",
                        toggle: { UnitToggle(selection: heightUnitBinding, leftLabel: "Cm", rightLabel: "Feet") }
                    ) {
                        heightStepView
                    }
                } else {
                    heroStepLayout(
                        headline: "What sex should we use?",
                        subtitle: "Used to estimate your baseline calories"
                    ) {
                        sexStepView
                            .padding(.horizontal, 16)
                    }
                }

                baselineFooter
                    .padding(.horizontal, 16)
                    .padding(.bottom, 24)
                    .opacity(appeared ? 1 : 0)
                    .animation(.easeOut(duration: 0.4).delay(0.28), value: appeared)
            }
        }
        .onAppear {
            hydrateCompatibilityDefaults()
            withAnimation(.easeOut(duration: 0.5)) {
                appeared = true
            }
        }
        .onChange(of: draft.units) { _, _ in
            clampImperialHeightIfNeeded()
        }
    }

    private func heroStepLayout<Content: View, Toggle: View>(
        headline: String,
        subtitle: String,
        @ViewBuilder toggle: () -> Toggle = { EmptyView() },
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(spacing: 0) {
            Text(headline)
                .font(OnboardingTypography.instrumentSerif(style: .regular, size: 34))
                .foregroundStyle(.black)
                .multilineTextAlignment(.center)
                .padding(.top, 20)
                .opacity(appeared ? 1 : 0)
                .offset(y: appeared ? 0 : 12)

            Text(subtitle)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Color(red: 0.51, green: 0.51, blue: 0.51))
                .padding(.top, 8)
                .opacity(appeared ? 1 : 0)
                .animation(.easeOut(duration: 0.4).delay(0.08), value: appeared)

            toggle()
                .padding(.top, 16)
                .opacity(appeared ? 1 : 0)
                .animation(.easeOut(duration: 0.4).delay(0.14), value: appeared)

            Spacer()

            content()
                .opacity(appeared ? 1 : 0)

            Spacer()
        }
    }

    private var topBar: some View {
        ZStack {

            HStack {
                Button(action: onBack) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.black)
                        .frame(width: 44, height: 44)
                        .background(
                            Circle()
                                .fill(Color.white)
                                .shadow(color: Color.black.opacity(0.10), radius: 20, y: 10)
                        )
                }
                .buttonStyle(.plain)

                Spacer()
            }
        }
        .frame(height: 44)
    }

    private var mascot: some View {
        Circle()
            .stroke(Color.black, lineWidth: 1)
            .frame(width: 153, height: 153)
            .overlay(
                Text("MASCOT")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(.black)
            )
    }

    private var heightUnitBinding: Binding<UnitsOption> {
        Binding(
            get: { draft.units ?? .metric },
            set: { newUnit in
                draft.setUnitsPreservingBaseline(newUnit)
                draft.baselineTouchedHeight = true
            }
        )
    }

    @State private var heightDragOffset: CGFloat = 0
    @State private var heightDragStartValue: Int?

    private var currentMetricHeight: Int {
        Int(draft.heightMetricValue.rounded())
    }

    private var currentFeet: Int {
        draft.imperialHeightFeetInches.feet
    }

    private var currentInches: Int {
        draft.imperialHeightFeetInches.inches
    }

    private var heightStepView: some View {
        Group {
            if isMetric {
                metricHeightHero
            } else {
                imperialHeightHero
            }
        }
    }

    // MARK: - Metric Height Picker (native wheel)

    private var metricHeightHero: some View {
        VStack(spacing: 0) {
            SmoothScrollPicker(
                value: Int(draft.heightMetricValue.rounded()),
                range: OnboardingBaselineRange.heightCm.lowerBound...OnboardingBaselineRange.heightCm.upperBound,
                onSet: { newValue in
                    draft.heightMetricValue = Double(newValue)
                    draft.baselineTouchedHeight = true
                }
            )

            Text("cm")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Color(red: 0.51, green: 0.51, blue: 0.51))
                .padding(.top, 4)
        }
    }

    // MARK: - Imperial Height Picker (Feet + Inches wheels side by side)

    private var imperialHeightHero: some View {
        HStack(spacing: 8) {
            VStack(spacing: 0) {
                SmoothScrollPicker(
                    value: draft.imperialHeightFeetInches.feet,
                    range: OnboardingBaselineRange.minImperialFeet...OnboardingBaselineRange.maxImperialFeet,
                    onSet: { setFeet($0) },
                    pickerWidth: 100
                )

                Text("ft")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Color(red: 0.51, green: 0.51, blue: 0.51))
                    .padding(.top, 4)
            }

            VStack(spacing: 0) {
                SmoothScrollPicker(
                    value: draft.imperialHeightFeetInches.inches,
                    range: 0...(draft.imperialHeightFeetInches.feet == OnboardingBaselineRange.maxImperialFeet ? OnboardingBaselineRange.maxInchesForMaxFeet : 11),
                    onSet: { setInches($0) },
                    pickerWidth: 100
                )

                Text("in")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Color(red: 0.51, green: 0.51, blue: 0.51))
                    .padding(.top, 4)
            }
        }
    }

    private func setFeet(_ newFeet: Int) {
        var val = draft.imperialHeightFeetInches
        val.feet = newFeet
        withAnimation(.spring(response: 0.2, dampingFraction: 0.85)) {
            draft.imperialHeightFeetInches = val
            draft.baselineTouchedHeight = true
        }
    }

    private func setInches(_ newInches: Int) {
        var val = draft.imperialHeightFeetInches
        val.inches = newInches
        withAnimation(.spring(response: 0.2, dampingFraction: 0.85)) {
            draft.imperialHeightFeetInches = val
            draft.baselineTouchedHeight = true
        }
    }

    private func sexTheme(for option: SexOption) -> (icon: String, accent: Color, subtitle: String) {
        switch option {
        case .male:
            return ("figure.stand", Color(red: 0.20, green: 0.60, blue: 0.85), "Used for calorie calculation")
        case .female:
            return ("figure.stand.dress", Color(red: 0.85, green: 0.40, blue: 0.55), "Used for calorie calculation")
        case .other:
            return ("person.fill", Color(red: 0.55, green: 0.55, blue: 0.62), "We'll use an average estimate")
        }
    }

    private var sexStepView: some View {
        VStack(spacing: 12) {
            ForEach(SexOption.allCases) { option in
                let theme = sexTheme(for: option)
                let isSelected = selectedSex == option

                Button {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
                        draft.sex = option
                        draft.baselineTouchedSex = true
                    }
                    #if canImport(UIKit)
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    #endif
                } label: {
                    HStack(spacing: 14) {
                        Image(systemName: theme.icon)
                            .font(.system(size: 24))
                            .symbolRenderingMode(.hierarchical)
                            .foregroundStyle(theme.accent)
                            .frame(width: 36)

                        VStack(alignment: .leading, spacing: 3) {
                            Text(option.title)
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(.black)

                            Text(theme.subtitle)
                                .font(.system(size: 13, weight: .regular))
                                .foregroundStyle(OnboardingGlassTheme.textMuted)
                                .lineLimit(1)
                        }

                        Spacer()

                        if isSelected {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 22))
                                .symbolRenderingMode(.hierarchical)
                                .foregroundStyle(theme.accent)
                                .transition(.scale.combined(with: .opacity))
                        }
                    }
                    .padding(.horizontal, 18)
                    .padding(.vertical, 15)
                    .background(
                        ZStack {
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .fill(Color.white)

                            if isSelected {
                                RoundedRectangle(cornerRadius: 18, style: .continuous)
                                    .fill(theme.accent.opacity(0.10))
                            }
                        }
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(
                                isSelected ? theme.accent : Color.black.opacity(0.08),
                                lineWidth: isSelected ? 2 : 1
                            )
                    )
                    .shadow(
                        color: isSelected ? theme.accent.opacity(0.15) : Color.black.opacity(0.03),
                        radius: isSelected ? 10 : 3,
                        y: isSelected ? 3 : 1
                    )
                    .scaleEffect(isSelected ? 1.02 : 1.0)
                }
                .buttonStyle(.plain)
                .sensoryFeedback(.selection, trigger: isSelected)
            }
        }
    }

    @State private var weightDragOffset: CGFloat = 0
    @State private var weightDragStartValue: Int?

    private var weightUnitBinding: Binding<UnitsOption> {
        Binding(
            get: { draft.units ?? .metric },
            set: { newUnit in
                draft.setUnitsPreservingBaseline(newUnit)
                draft.baselineTouchedWeight = true
            }
        )
    }

    private var currentWeightInt: Int {
        Int(draft.weightValue.rounded())
    }

    private var weightRange: ClosedRange<Int> {
        if isMetric {
            return Int(OnboardingBaselineRange.weightKg.lowerBound)...Int(OnboardingBaselineRange.weightKg.upperBound)
        } else {
            return Int(OnboardingBaselineRange.weightLb.lowerBound)...Int(OnboardingBaselineRange.weightLb.upperBound)
        }
    }

    private var weightStepView: some View {
        weightHeroSelector
    }

    private var weightPickerSelection: Binding<Int> {
        Binding(
            get: { currentWeightInt },
            set: { newValue in
                draft.weight = String(newValue)
                draft.baselineTouchedWeight = true
            }
        )
    }

    private var weightHeroSelector: some View {
        let unitLabel = isMetric ? "kg" : "lbs"

        return VStack(spacing: 0) {
            SmoothScrollPicker(
                value: currentWeightInt,
                range: weightRange,
                onSet: { newValue in
                    draft.weight = String(newValue)
                    draft.baselineTouchedWeight = true
                }
            )

            Text(unitLabel)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Color(red: 0.51, green: 0.51, blue: 0.51))
                .padding(.top, 4)
        }
    }

    private var baselineFooter: some View {
        Button(action: onContinue) {
            HStack(spacing: 8) {
                Text("Next")
                    .font(.system(size: 16, weight: .bold))
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .bold))
            }
            .foregroundStyle(.white)
            .frame(width: 220, height: 60)
            .background(Color.black.opacity(canContinueStep ? 1 : 0.2))
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(!canContinueStep)
        .animation(.easeInOut(duration: 0.25), value: canContinueStep)
    }

    private func baselineUnitToggle(
        primary: String,
        secondary: String,
        metricSelected: Bool,
        onPrimary: @escaping () -> Void,
        onSecondary: @escaping () -> Void
    ) -> some View {
        HStack(spacing: 0) {
            baselineSegmentButton(
                title: primary,
                isSelected: metricSelected,
                action: onPrimary
            )
            baselineSegmentButton(
                title: secondary,
                isSelected: !metricSelected,
                action: onSecondary
            )
        }
        .padding(2)
        .background(Color(red: 0.93, green: 0.93, blue: 0.95))
        .clipShape(Capsule())
    }

    private func baselineSegmentButton(title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 20 / 1.5, weight: isSelected ? .semibold : .medium))
                .foregroundStyle(.black)
                .frame(maxWidth: .infinity)
                .frame(height: 36)
                .background(
                    Capsule()
                        .fill(isSelected ? Color.white : Color.clear)
                )
        }
        .buttonStyle(.plain)
    }

    private func baselineWheelFont(value: Int, selected: Int) -> Font {
        let distance = abs(value - selected)
        if distance == 0 {
            return .system(size: 48, weight: .bold)
        }
        if distance == 1 {
            return .system(size: 38, weight: .bold)
        }
        return .system(size: 30, weight: .bold)
    }

    private func baselineWheelColor(value: Int, selected: Int) -> Color {
        let distance = abs(value - selected)
        if distance == 0 {
            return .black
        }
        if distance == 1 {
            return Color(red: 0.62, green: 0.62, blue: 0.62)
        }
        return Color(red: 0.81, green: 0.81, blue: 0.81)
    }

    private func hydrateCompatibilityDefaults() {
        if draft.units == nil {
            draft.units = .metric
        }

        if draft.sex == nil {
            draft.sex = .female
            draft.baselineTouchedSex = true
        }

        if draft.height.isEmpty {
            switch draft.units ?? .metric {
            case .metric:
                draft.height = String(OnboardingBaselineRange.defaultHeightCm)
            case .imperial:
                draft.height = String(OnboardingBaselineRange.defaultImperialHeightInches)
            }
        }

        if draft.weight.isEmpty {
            switch draft.units ?? .metric {
            case .metric:
                draft.weight = String(Int(OnboardingBaselineRange.defaultWeightKg.rounded()))
            case .imperial:
                draft.weight = String(Int(OnboardingBaselineRange.defaultWeightLb.rounded()))
            }
        }

    }

    private func clampImperialHeightIfNeeded() {
        guard !isMetric else { return }
        var value = draft.imperialHeightFeetInches
        if value.feet == OnboardingBaselineRange.maxImperialFeet {
            value.inches = min(value.inches, OnboardingBaselineRange.maxInchesForMaxFeet)
            draft.imperialHeightFeetInches = value
        }
    }
}

private struct BaselineSingleWheelPicker: View {
    let values: [Int]
    @Binding var selection: Int
    let wheelWidth: CGFloat
    let font: (Int, Int) -> Font
    let color: (Int, Int) -> Color

    var body: some View {
#if canImport(UIKit)
        BaselineWheelPickerRepresentable(
            values: values,
            selection: $selection,
            width: wheelWidth,
            visibleRows: 5,
            font: font,
            color: color
        )
        .frame(width: wheelWidth, height: 280)
#else
        Picker("", selection: $selection) {
            ForEach(values, id: \.self) { value in
                Text("\(value)")
                    .font(font(value, selection))
                    .foregroundStyle(color(value, selection))
                    .frame(maxWidth: .infinity)
                    .tag(value)
            }
        }
        .pickerStyle(.wheel)
        .frame(width: wheelWidth)
        .frame(height: 280)
        .clipped()
#endif
    }
}

private struct BaselineDoubleWheelPicker: View {
    let leftValues: [Int]
    @Binding var leftSelection: Int
    let rightValues: [Int]
    @Binding var rightSelection: Int
    let leftSuffix: String
    let rightSuffix: String
    let font: (Int, Int) -> Font
    let color: (Int, Int) -> Color

    var body: some View {
        HStack(spacing: 16) {
            baselineColumn(values: leftValues, selection: $leftSelection, suffix: leftSuffix)
            baselineColumn(values: rightValues, selection: $rightSelection, suffix: rightSuffix)
        }
        .padding(.horizontal, 28)
    }

    private func baselineColumn(values: [Int], selection: Binding<Int>, suffix: String) -> some View {
        HStack(alignment: .center, spacing: 6) {
#if canImport(UIKit)
            BaselineWheelPickerRepresentable(
                values: values,
                selection: selection,
                width: 96,
                visibleRows: 5,
                font: font,
                color: color
            )
            .frame(width: 96, height: 280)
#else
            Picker("", selection: selection) {
                ForEach(values, id: \.self) { value in
                    Text("\(value)")
                        .font(font(value, selection.wrappedValue))
                        .foregroundStyle(color(value, selection.wrappedValue))
                        .frame(maxWidth: .infinity)
                        .tag(value)
                }
            }
            .pickerStyle(.wheel)
            .frame(width: 96)
            .frame(height: 280)
            .clipped()
#endif

            Text(suffix)
                .font(.system(size: 24, weight: .bold))
                .foregroundStyle(.black)
                .frame(minWidth: suffix == "inch" ? 54 : 30, alignment: .leading)
        }
        .frame(maxWidth: .infinity)
    }
}

#if canImport(UIKit)
private struct BaselineWheelPickerRepresentable: UIViewRepresentable {
    let values: [Int]
    @Binding var selection: Int
    let width: CGFloat
    let visibleRows: Int
    let font: (Int, Int) -> Font
    let color: (Int, Int) -> Color

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIView(context: Context) -> UIPickerView {
        let picker = UIPickerView()
        picker.delegate = context.coordinator
        picker.dataSource = context.coordinator
        picker.backgroundColor = .clear
        picker.subviews.forEach { $0.backgroundColor = .clear }
        picker.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        if let selectedIndex = values.firstIndex(of: selection) {
            picker.selectRow(selectedIndex, inComponent: 0, animated: false)
        }
        return picker
    }

    func updateUIView(_ uiView: UIPickerView, context: Context) {
        context.coordinator.parent = self
        uiView.subviews.forEach { $0.backgroundColor = .clear }
        uiView.reloadAllComponents()
        if let selectedIndex = values.firstIndex(of: selection),
           uiView.selectedRow(inComponent: 0) != selectedIndex {
            uiView.selectRow(selectedIndex, inComponent: 0, animated: false)
        }
    }

    final class Coordinator: NSObject, UIPickerViewDelegate, UIPickerViewDataSource {
        var parent: BaselineWheelPickerRepresentable

        init(_ parent: BaselineWheelPickerRepresentable) {
            self.parent = parent
        }

        func numberOfComponents(in pickerView: UIPickerView) -> Int { 1 }

        func pickerView(_ pickerView: UIPickerView, numberOfRowsInComponent component: Int) -> Int {
            parent.values.count
        }

        func pickerView(_ pickerView: UIPickerView, rowHeightForComponent component: Int) -> CGFloat {
            56
        }

        func pickerView(_ pickerView: UIPickerView, widthForComponent component: Int) -> CGFloat {
            parent.width
        }

        func pickerView(_ pickerView: UIPickerView, didSelectRow row: Int, inComponent component: Int) {
            guard parent.values.indices.contains(row) else { return }
            let newValue = parent.values[row]
            if parent.selection != newValue {
                parent.selection = newValue
            }
            pickerView.reloadAllComponents()
        }

        func pickerView(_ pickerView: UIPickerView, viewForRow row: Int, forComponent component: Int, reusing view: UIView?) -> UIView {
            let label = (view as? UILabel) ?? UILabel()
            let value = parent.values[row]
            label.text = "\(value)"
            label.textAlignment = .center
            label.adjustsFontSizeToFitWidth = true
            label.minimumScaleFactor = 0.7
            label.baselineAdjustment = .alignCenters
            label.clipsToBounds = true
            label.frame = CGRect(x: 0, y: 0, width: parent.width, height: 56)

            if value == parent.selection {
                label.font = .systemFont(ofSize: 48, weight: .bold)
                label.textColor = .black
            } else if abs(value - parent.selection) == 1 {
                label.font = .systemFont(ofSize: 38, weight: .bold)
                label.textColor = UIColor(red: 0.62, green: 0.62, blue: 0.62, alpha: 1)
            } else {
                label.font = .systemFont(ofSize: 30, weight: .bold)
                label.textColor = UIColor(red: 0.81, green: 0.81, blue: 0.81, alpha: 1)
            }

            return label
        }
    }
}
#endif

// MARK: - Smooth Scroll Picker (drag-based, numericText transition)

struct SmoothScrollPicker: View {
    let value: Int
    let range: ClosedRange<Int>
    let onSet: (Int) -> Void
    var pickerWidth: CGFloat = 220

    @State private var dragStartValue: Int?
    @State private var lastReportedStep: Int = 0
    @State private var dragOffset: CGFloat = 0

    private let rowHeight: CGFloat = 68
    private let stepSize: CGFloat = 50

    var body: some View {
        ZStack {
            // -2
            if value - 2 >= range.lowerBound {
                Text("\(value - 2)")
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.black.opacity(0.15))
                    .offset(y: -rowHeight * 2 + dragOffset)
            }

            // -1
            if value - 1 >= range.lowerBound {
                Text("\(value - 1)")
                    .font(.system(size: 40, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.black.opacity(0.25))
                    .offset(y: -rowHeight + dragOffset)
            }

            // Selected (center)
            Text("\(value)")
                .font(.system(size: 86, weight: .bold, design: .rounded))
                .foregroundStyle(.black)
                .offset(y: dragOffset)

            // +1
            if value + 1 <= range.upperBound {
                Text("\(value + 1)")
                    .font(.system(size: 40, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.black.opacity(0.25))
                    .offset(y: rowHeight + dragOffset)
            }

            // +2
            if value + 2 <= range.upperBound {
                Text("\(value + 2)")
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.black.opacity(0.15))
                    .offset(y: rowHeight * 2 + dragOffset)
            }
        }
        .frame(width: pickerWidth, height: rowHeight * 5)
        .clipped()
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 5)
                .onChanged { gesture in
                    if dragStartValue == nil {
                        dragStartValue = value
                        lastReportedStep = 0
                    }

                    let rawSteps = -gesture.translation.height / stepSize
                    let snappedStep = Int(rawSteps.rounded())
                    let fractional = -gesture.translation.height - CGFloat(snappedStep) * stepSize

                    // Smooth inter-step offset (clamped so it doesn't overshoot)
                    dragOffset = min(max(fractional * 0.4, -rowHeight * 0.4), rowHeight * 0.4)

                    if snappedStep != lastReportedStep {
                        let target = (dragStartValue ?? value) + snappedStep
                        let clamped = min(max(target, range.lowerBound), range.upperBound)
                        if clamped != value {
                            onSet(clamped)
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        }
                        lastReportedStep = snappedStep
                    }
                }
                .onEnded { _ in
                    dragStartValue = nil
                    lastReportedStep = 0
                    withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                        dragOffset = 0
                    }
                }
        )
    }
}

// MARK: - Custom Unit Toggle (50% width, black selected state)

private struct UnitToggle: View {
    @Binding var selection: UnitsOption
    let leftLabel: String
    let rightLabel: String

    @Namespace private var toggleNamespace

    var body: some View {
        GeometryReader { geo in
            let halfWidth = geo.size.width / 2

            HStack(spacing: 0) {
                toggleTab(label: leftLabel, tag: .metric, width: halfWidth)
                toggleTab(label: rightLabel, tag: .imperial, width: halfWidth)
            }
            .frame(height: 40)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(.ultraThinMaterial)
            )
        }
        .frame(height: 40)
        .frame(maxWidth: UIScreen.main.bounds.width * 0.5)
    }

    private func toggleTab(label: String, tag: UnitsOption, width: CGFloat) -> some View {
        Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                selection = tag
            }
        } label: {
            Text(label)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(selection == tag ? .white : .primary)
                .frame(width: width, height: 34)
                .background {
                    if selection == tag {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color.black)
                            .matchedGeometryEffect(id: "unit-pill", in: toggleNamespace)
                    }
                }
        }
        .buttonStyle(.plain)
    }
}
