import SwiftUI

/// Toolbar indicator shown by editor screens. Reflects the
/// `ProfileDraftStore.saveStatus` value, with a tap-to-retry action
/// when in the failed state.
struct ProfileSaveStatusIndicator: View {
    let status: ProfileSaveStatus
    let onRetry: () -> Void

    var body: some View {
        switch status {
        case .idle:
            EmptyView()
        case .saving:
            ProgressView()
                .controlSize(.small)
        case .saved:
            Label("Saved", systemImage: "checkmark.circle.fill")
                .labelStyle(.iconOnly)
                .foregroundStyle(.green)
                .font(.system(size: 16, weight: .semibold))
                .accessibilityLabel("Saved")
        case .failed(let message):
            Button {
                onRetry()
            } label: {
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .labelStyle(.iconOnly)
                    .foregroundStyle(.red)
                    .font(.system(size: 16, weight: .semibold))
            }
            .accessibilityLabel("Save failed: \(message). Tap to retry.")
        }
    }
}
