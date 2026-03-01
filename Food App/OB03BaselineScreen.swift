import SwiftUI

struct OB03BaselineScreen: View {
    @Binding var draft: OnboardingDraft
    let isValid: Bool

    private var unitsSelection: Binding<UnitsOption?> {
        Binding(
            get: { draft.units },
            set: { selection in
                guard let option = selection else { return }
                draft.setUnitsPreservingBaseline(option)
            }
        )
    }

    private var ageBinding: Binding<Double> {
        Binding(
            get: { draft.ageValue },
            set: { draft.ageValue = $0 }
        )
    }

    private var heightCmBinding: Binding<Double> {
        Binding(
            get: { draft.heightMetricValue },
            set: { draft.heightMetricValue = $0 }
        )
    }

    private var weightBinding: Binding<Double> {
        Binding(
            get: { draft.weightValue },
            set: { draft.weightValue = $0 }
        )
    }

    private var feetBinding: Binding<Int> {
        Binding(
            get: { draft.imperialHeightFeetInches.feet },
            set: { newFeet in
                var composite = draft.imperialHeightFeetInches
                composite.feet = newFeet
                draft.imperialHeightFeetInches = composite
            }
        )
    }

    private var inchesBinding: Binding<Int> {
        Binding(
            get: { draft.imperialHeightFeetInches.inches },
            set: { newInches in
                var composite = draft.imperialHeightFeetInches
                composite.inches = newInches
                draft.imperialHeightFeetInches = composite
            }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("These details stay private and make your calorie target more realistic.")
                .font(.footnote)
                .foregroundStyle(OnboardingGlassTheme.textSecondary)
                .padding(.horizontal, 4)

            OnboardingSegmentedControl(
                title: "Units",
                options: UnitsOption.allCases,
                selection: unitsSelection,
                label: { L10n.unitsLabel($0) }
            )

            BaselineAgeCard(
                age: ageBinding,
                isTouched: $draft.baselineTouchedAge
            )

            if draft.units == .metric {
                BaselineMetricHeightCard(
                    heightCm: heightCmBinding,
                    isTouched: $draft.baselineTouchedHeight
                )
            } else {
                BaselineImperialHeightCard(
                    feet: feetBinding,
                    inches: inchesBinding,
                    isTouched: $draft.baselineTouchedHeight
                )
            }

            BaselineWeightCard(
                weight: weightBinding,
                units: draft.units ?? .imperial,
                isTouched: $draft.baselineTouchedWeight
            )

            OnboardingSegmentedControl(
                title: "Sex",
                options: SexOption.allCases,
                selection: $draft.sex,
                label: { $0.title }
            )

            if !isValid {
                Text("Please complete all fields.")
                    .font(.footnote)
                    .foregroundStyle(.red)
            } else {
                OnboardingValueCard(
                    title: "Baseline complete",
                    bodyText: "Nice. You can continue to calibrate your activity and pace.",
                    isSuccess: true
                )
            }
        }
    }
}
