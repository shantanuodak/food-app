import SwiftUI
import Foundation

extension MainLoggingShellView {
    func handleQuickCameraStatusNotification(_ notification: Notification) {
        let title = notification.userInfo?["title"] as? String
        let body = notification.userInfo?["body"] as? String
        let kind = notification.userInfo?["kind"] as? String
        let message = [title, body]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: ": ")

        guard !message.isEmpty else { return }

        if kind == "error" {
            parseInfoMessage = nil
            saveSuccessMessage = nil
            parseError = message
        } else if title == "Food logged" {
            parseInfoMessage = nil
            parseError = nil
            saveSuccessMessage = body
        } else {
            parseError = nil
            saveSuccessMessage = nil
            parseInfoMessage = message
            if title == "Food detected",
               let pendingLogId = notification.userInfo?["pendingLogId"] as? String {
                quickCameraPrompt = QuickCameraPendingLogStore.load(id: pendingLogId)
            }
        }
    }
}

struct QuickCameraPromptDialogModifier: ViewModifier {
    @Binding var prompt: QuickCameraPendingLog?
    let onLog: (QuickCameraPendingLog) -> Void
    let onRetake: (QuickCameraPendingLog) -> Void
    let onDiscard: (QuickCameraPendingLog) -> Void

    func body(content: Content) -> some View {
        let isPresented = Binding<Bool>(
            get: { prompt != nil },
            set: { isPresented in
                if !isPresented {
                    prompt = nil
                }
            }
        )

        content.confirmationDialog(
            "Food detected",
            isPresented: isPresented,
            titleVisibility: .visible
        ) {
            if let pendingLog = prompt {
                if pendingLog.canSaveDirectly {
                    Button("Log") {
                        onLog(pendingLog)
                    }
                }
                Button("Retake") {
                    onRetake(pendingLog)
                }
                Button("Discard", role: .destructive) {
                    onDiscard(pendingLog)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            if let pendingLog = prompt {
                Text("\(pendingLog.displayName), about \(pendingLog.calories) cal.")
            }
        }
    }
}
