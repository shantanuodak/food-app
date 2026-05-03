import SwiftUI
import UIKit


struct HM00BottomActionDock: View {
    let selectedMode: HomeInputMode
    let needsClarification: Bool
    let onSelectMode: (HomeInputMode) -> Void
    let onOpenDetails: () -> Void

    init(
        selectedMode: HomeInputMode,
        needsClarification: Bool,
        onSelectMode: @escaping (HomeInputMode) -> Void,
        onOpenDetails: @escaping () -> Void
    ) {
        self.selectedMode = selectedMode
        self.needsClarification = needsClarification
        self.onSelectMode = onSelectMode
        self.onOpenDetails = onOpenDetails
    }

    var body: some View {
        HStack(spacing: 12) {
            dockButton(mode: .voice)
            dockButton(mode: .camera)
            dockButton(mode: .manualAdd)
            detailsButton
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity)
    }

    private func dockButton(mode: HomeInputMode) -> some View {
        let isActive = selectedMode == mode

        return Button {
            onSelectMode(isActive ? .text : mode)
        } label: {
            Image(systemName: mode.icon)
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .foregroundStyle(isActive ? Color.white : Color.primary)
                .glassyBackground(in: .rect(cornerRadius: 14, style: .continuous), tint: isActive ? Color.accentColor : nil)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(mode.title))
    }

    private var detailsButton: some View {
        Button {
            onOpenDetails()
        } label: {
            ZStack(alignment: .topTrailing) {
                Image(systemName: "message")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .foregroundStyle(Color.primary)
                    .glassyBackground(in: .rect(cornerRadius: 14, style: .continuous))

                if needsClarification {
                    Circle()
                        .fill(Color.orange)
                        .frame(width: 8, height: 8)
                        .offset(x: -2, y: 2)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("Open details"))
    }

}
struct HM03ParseSummarySection: View {
    let totals: NutritionTotals
    let hasEditedItems: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L10n.estimatedTotalsTitle)
                .font(.headline)

            HStack(spacing: 10) {
                statPill(title: L10n.totalsCalories, value: totals.calories, fractionDigits: 0)
                statPill(title: L10n.totalsProtein, value: totals.protein, fractionDigits: 1, unit: "g")
            }
            HStack(spacing: 10) {
                statPill(title: L10n.totalsCarbs, value: totals.carbs, fractionDigits: 1, unit: "g")
                statPill(title: L10n.totalsFat, value: totals.fat, fractionDigits: 1, unit: "g")
            }

            if hasEditedItems {
                Text(L10n.totalsEditedHint)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.blue.opacity(0.08))
        )
    }

    private func statPill(title: String, value: Double, fractionDigits: Int, unit: String = "") -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack(spacing: 0) {
                RollingNumberText(value: value, fractionDigits: fractionDigits)
                if !unit.isEmpty {
                    Text(unit)
                }
            }
                .font(.subheadline.bold())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.white.opacity(0.8))
        )
    }
}

struct HM02ParseAndSaveActionsSection: View {
    let isNetworkReachable: Bool
    let networkQualityHint: String
    let isParsing: Bool
    let isSaving: Bool
    let parseDisabled: Bool
    let openDetailsDisabled: Bool
    let saveDisabled: Bool
    let retryDisabled: Bool
    let showSaveDisabledHint: Bool
    let saveSuccessMessage: String?
    let lastTimeToLogLabel: String?
    let saveError: String?
    let idempotencyKeyLabel: String?
    let onParseNow: () -> Void
    let onOpenDetails: () -> Void
    let onSave: () -> Void
    let onRetry: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if !isNetworkReachable {
                Text(L10n.offlineBanner)
                    .font(.footnote)
                    .foregroundStyle(.orange)
            } else if networkQualityHint != L10n.networkOnline {
                Text(networkQualityHint)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 12) {
                Button(L10n.parseNowButton) {
                    onParseNow()
                }
                .buttonStyle(.borderedProminent)
                .disabled(parseDisabled)
                .accessibilityLabel(Text(L10n.parseNowButton))
                .accessibilityHint(Text(L10n.parseNowHint))

                Button(L10n.openDetailsButton) {
                    onOpenDetails()
                }
                .buttonStyle(.bordered)
                .disabled(openDetailsDisabled)
                .accessibilityLabel(Text(L10n.openDetailsButton))
                .accessibilityHint(Text(L10n.openDetailsHint))

                if isParsing {
                    ProgressView()
                    Text(L10n.parseInProgress)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            HStack(spacing: 12) {
                Button(L10n.saveLogButton) {
                    onSave()
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
                .disabled(saveDisabled)
                .accessibilityLabel(Text(L10n.saveLogButton))
                .accessibilityHint(Text(L10n.saveLogHint))

                Button(L10n.retryLastSaveButton) {
                    onRetry()
                }
                .buttonStyle(.bordered)
                .disabled(retryDisabled)
                .accessibilityLabel(Text(L10n.retryLastSaveButton))
                .accessibilityHint(Text(L10n.retryLastSaveHint))

                if isSaving {
                    ProgressView()
                    Text(L10n.saveInProgress)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if showSaveDisabledHint {
                Text(L10n.saveDisabledNeedsClarification)
                    .font(.caption)
                    .foregroundStyle(.orange)
            }

            if let saveSuccessMessage {
                Text(saveSuccessMessage)
                    .font(.footnote)
                    .foregroundStyle(.green)
            }

            if let lastTimeToLogLabel {
                Text(lastTimeToLogLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let saveError {
                Text(saveError)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }

            if let idempotencyKeyLabel {
                Text(idempotencyKeyLabel)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
        }
    }
}

struct HM06DaySummarySection: View {
    @Binding var selectedDate: Date
    let maximumDate: Date
    let isLoading: Bool
    let daySummaryError: String?
    let daySummary: DaySummaryResponse?
    let onRetry: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(L10n.daySummaryTitle)
                    .font(.headline)
                Spacer()
                if isLoading {
                    ProgressView()
                        .scaleEffect(0.9)
                }
            }

            HStack {
                DatePicker(
                    L10n.daySummaryDateLabel,
                    selection: $selectedDate,
                    in: ...Calendar.current.startOfDay(for: maximumDate),
                    displayedComponents: .date
                )
                    .labelsHidden()
                Text(Self.summaryDisplayFormatter.string(from: selectedDate))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            if let daySummaryError {
                Text(daySummaryError)
                    .font(.footnote)
                    .foregroundStyle(.red)

                Button(L10n.retrySummaryButton) {
                    onRetry()
                }
                .buttonStyle(.bordered)
            } else if let daySummary {
                if isSummaryEmpty(daySummary) {
                    Text(L10n.daySummaryZeroTotals)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                summaryProgressRow(
                    title: L10n.totalsCalories,
                    consumed: daySummary.totals.calories,
                    target: daySummary.targets.calories,
                    remaining: daySummary.remaining.calories,
                    unit: "kcal"
                )

                summaryProgressRow(
                    title: L10n.totalsProtein,
                    consumed: daySummary.totals.protein,
                    target: daySummary.targets.protein,
                    remaining: daySummary.remaining.protein,
                    unit: "g"
                )

                summaryProgressRow(
                    title: L10n.totalsCarbs,
                    consumed: daySummary.totals.carbs,
                    target: daySummary.targets.carbs,
                    remaining: daySummary.remaining.carbs,
                    unit: "g"
                )

                summaryProgressRow(
                    title: L10n.totalsFat,
                    consumed: daySummary.totals.fat,
                    target: daySummary.targets.fat,
                    remaining: daySummary.remaining.fat,
                    unit: "g"
                )
            } else {
                Text(L10n.loadingDaySummary)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.green.opacity(0.08))
        )
    }

    private func summaryProgressRow(
        title: String,
        consumed: Double,
        target: Double,
        remaining: Double,
        unit: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Spacer()
                HStack(spacing: 0) {
                    RollingNumberText(value: consumed, fractionDigits: 1)
                    Text("/")
                    RollingNumberText(value: target, fractionDigits: 1)
                    Text(" \(unit)")
                }
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            ProgressView(value: progressFraction(consumed: consumed, target: target))
                .tint(.green)

            Text(L10n.remainingLabel(max(remaining, 0), unit: unit))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.white.opacity(0.85))
        )
    }

    private func progressFraction(consumed: Double, target: Double) -> Double {
        guard target > 0 else { return 0 }
        return min(max(consumed / target, 0), 1)
    }

    private func isSummaryEmpty(_ summary: DaySummaryResponse) -> Bool {
        summary.totals.calories <= 0.05 &&
            summary.totals.protein <= 0.05 &&
            summary.totals.carbs <= 0.05 &&
            summary.totals.fat <= 0.05
    }

    private func formatOneDecimal(_ value: Double) -> String {
        String(format: "%.1f", value)
    }

    private static let summaryDisplayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter
    }()
}

struct HM04ClarificationEscalationSection: View {
    let parseResult: ParseLogResponse
    let isEscalating: Bool
    let escalationInfoMessage: String?
    let escalationError: String?
    let disabledReason: String?
    let canEscalate: Bool
    let onEscalate: () -> Void

    var body: some View {
        if parseResult.needsClarification {
            VStack(alignment: .leading, spacing: 8) {
                Text(L10n.clarificationNeededTitle)
                    .font(.headline)

                ForEach(Array(parseResult.clarificationQuestions.enumerated()), id: \.offset) { index, question in
                    Text("\(index + 1). \(question)")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Button(L10n.escalateParseButton) {
                    onEscalate()
                }
                .buttonStyle(.borderedProminent)
                .tint(.orange)
                .disabled(!canEscalate)
                .accessibilityLabel(Text(L10n.escalateParseButton))
                .accessibilityHint(Text(L10n.escalateParseHint))

                if isEscalating {
                    HStack(spacing: 8) {
                        ProgressView()
                        Text(L10n.escalatingInProgress)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                if let escalationInfoMessage {
                    Text(escalationInfoMessage)
                        .font(.footnote)
                        .foregroundStyle(.green)
                }

                if let escalationError {
                    Text(escalationError)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }

                if let disabledReason {
                    Text(disabledReason)
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.orange.opacity(0.08))
            )
        } else if let escalationInfoMessage {
            Text(escalationInfoMessage)
                .font(.footnote)
                .foregroundStyle(.green)
        }
    }
}
