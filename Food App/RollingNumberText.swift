import SwiftUI

struct RollingNumberText: View {
    let value: Double
    var fractionDigits: Int = 0
    var suffix: String = ""
    var useGrouping: Bool = false

    var body: some View {
        Text(formattedValue)
            .monospacedDigit()
            .contentTransition(.numericText())
            .animation(.easeInOut(duration: 0.25), value: formattedValue)
    }

    private var formattedValue: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = useGrouping
        formatter.minimumFractionDigits = fractionDigits
        formatter.maximumFractionDigits = fractionDigits
        let base = formatter.string(from: NSNumber(value: value)) ?? "0"
        return suffix.isEmpty ? base : "\(base)\(suffix)"
    }
}
