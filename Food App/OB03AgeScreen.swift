import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

struct OB03AgeScreen: View {
    @Binding var age: Double
    let onBack: () -> Void
    let onContinue: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @State private var appeared = false
    @State private var dragOffset: CGFloat = 0
    @State private var dragStartAge: Int?

    private let ageRange = OnboardingBaselineRange.age
    private let itemHeight: CGFloat = 90

    private var currentAge: Int {
        Int(age.rounded())
    }

    var body: some View {
        ZStack {
            OnboardingStaticBackground()

            VStack(spacing: 0) {
                topBar
                    .padding(.top, 12)
                    .padding(.horizontal, 16)

                // Headline
                Text("How young are you?")
                    .font(OnboardingTypography.instrumentSerif(style: .regular, size: 34))
                    .foregroundStyle(colorScheme == .dark ? .white : .black)
                    .multilineTextAlignment(.center)
                    .lineSpacing(2)
                    .opacity(appeared ? 1 : 0)
                    .offset(y: appeared ? 0 : 12)
                    .padding(.top, 20)

                Text("We'll use this to personalize your plan")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Color(red: 0.51, green: 0.51, blue: 0.51))
                    .opacity(appeared ? 1 : 0)
                    .padding(.top, 8)

                Spacer()

                // Hero age display
                heroAgeSelector
                    .opacity(appeared ? 1 : 0)
                    .scaleEffect(appeared ? 1 : 0.9)

                Spacer()

                // CTA
                Button(action: onContinue) {
                    HStack(spacing: 8) {
                        Text("Next")
                            .font(.system(size: 16, weight: .bold))
                        Image(systemName: "chevron.right")
                            .font(.system(size: 14, weight: .bold))
                    }
                    .foregroundStyle(.white)
                    .frame(width: 220, height: 60)
                    .background(Color.black)
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .padding(.bottom, 24)
            }
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.5)) {
                appeared = true
            }
        }
    }

    // MARK: - Hero Age Selector

    private var agePickerSelection: Binding<Int> {
        Binding(
            get: { currentAge },
            set: { age = Double($0) }
        )
    }

    private var heroAgeSelector: some View {
        SmoothScrollPicker(
            value: currentAge,
            range: ageRange.lowerBound...ageRange.upperBound,
            onSet: { age = Double($0) }
        )
    }

    // MARK: - Top Bar

    private var topBar: some View {
        ZStack {
            HStack {
                Button(action: onBack) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(colorScheme == .dark ? .white : .black)
                        .frame(width: 44, height: 44)
                        .background(
                            Circle()
                                .fill(colorScheme == .dark ? Color.white.opacity(0.12) : Color.white)
                                .shadow(color: Color.black.opacity(0.10), radius: 20, y: 10)
                        )
                }
                .buttonStyle(.plain)

                Spacer()
            }
        }
        .frame(height: 44)
    }

    // MARK: - Helpers

}

// MARK: - Custom Age Wheel Picker

#if canImport(UIKit)
private struct AgeWheelPickerRepresentable: UIViewRepresentable {
    let values: [Int]
    @Binding var selection: Int
    let width: CGFloat

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIView(context: Context) -> UIPickerView {
        let picker = UIPickerView()
        picker.delegate = context.coordinator
        picker.dataSource = context.coordinator
        picker.backgroundColor = .clear
        picker.subviews.forEach { subview in
            subview.backgroundColor = .clear
        }
        picker.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        if let selectedIndex = values.firstIndex(of: selection) {
            picker.selectRow(selectedIndex, inComponent: 0, animated: false)
        }
        return picker
    }

    func updateUIView(_ uiView: UIPickerView, context: Context) {
        context.coordinator.parent = self
        uiView.subviews.forEach { subview in
            subview.backgroundColor = .clear
        }
        uiView.reloadAllComponents()
        if let selectedIndex = values.firstIndex(of: selection),
           uiView.selectedRow(inComponent: 0) != selectedIndex {
            uiView.selectRow(selectedIndex, inComponent: 0, animated: false)
        }
    }

    final class Coordinator: NSObject, UIPickerViewDelegate, UIPickerViewDataSource {
        var parent: AgeWheelPickerRepresentable

        init(_ parent: AgeWheelPickerRepresentable) {
            self.parent = parent
        }

        func numberOfComponents(in pickerView: UIPickerView) -> Int { 1 }

        func pickerView(_ pickerView: UIPickerView, numberOfRowsInComponent component: Int) -> Int {
            parent.values.count
        }

        func pickerView(_ pickerView: UIPickerView, rowHeightForComponent component: Int) -> CGFloat {
            64
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
            label.frame = CGRect(x: 0, y: 0, width: parent.width, height: 64)

            if value == parent.selection {
                label.font = .systemFont(ofSize: 54, weight: .bold)
                label.textColor = .black
            } else if abs(value - parent.selection) == 1 {
                label.font = .systemFont(ofSize: 40, weight: .bold)
                label.textColor = UIColor(red: 0.55, green: 0.55, blue: 0.55, alpha: 1)
            } else if abs(value - parent.selection) == 2 {
                label.font = .systemFont(ofSize: 32, weight: .bold)
                label.textColor = UIColor(red: 0.75, green: 0.75, blue: 0.75, alpha: 1)
            } else {
                label.font = .systemFont(ofSize: 26, weight: .bold)
                label.textColor = UIColor(red: 0.85, green: 0.85, blue: 0.85, alpha: 1)
            }

            return label
        }
    }
}
#endif
