import SwiftUI
import UIKit

/// In-app feedback form. Submits to `POST /v1/feedback`; the testing
/// dashboard's Feedback tab surfaces submissions newest-first for triage.
///
/// Captures device + version metadata client-side so the team has full
/// context (which build, which OS, which device model) when reviewing.
/// All metadata fields are optional server-side — if reading them fails
/// for any reason, the message still goes through.
struct FeedbackView: View {
    @EnvironmentObject private var appStore: AppStore
    @Environment(\.dismiss) private var dismiss

    @State private var message: String = ""
    @State private var isSubmitting = false
    @State private var submissionError: String?
    @State private var showSuccessConfirmation = false
    @FocusState private var isMessageFocused: Bool

    private let messageMinChars = 1
    private let messageMaxChars = 4000

    private var trimmedMessage: String {
        message.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canSubmit: Bool {
        !isSubmitting
            && trimmedMessage.count >= messageMinChars
            && trimmedMessage.count <= messageMaxChars
    }

    var body: some View {
        Form {
            Section {
                ZStack(alignment: .topLeading) {
                    if message.isEmpty {
                        Text("What's on your mind? Bug, suggestion, or anything else.")
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 8)
                    }
                    TextEditor(text: $message)
                        .focused($isMessageFocused)
                        .frame(minHeight: 160)
                        .scrollContentBackground(.hidden)
                }
            } header: {
                Text("Your feedback")
            } footer: {
                HStack {
                    Text("\(trimmedMessage.count) / \(messageMaxChars)")
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                    Spacer()
                    if let email = appStore.authSessionStore.session?.email {
                        Text("Sent as \(email)")
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
                .font(.caption)
            }

            Section {
                Button {
                    Task { await submit() }
                } label: {
                    HStack {
                        if isSubmitting {
                            ProgressView()
                                .controlSize(.small)
                                .padding(.trailing, 4)
                        }
                        Text(isSubmitting ? "Sending…" : "Send feedback")
                            .frame(maxWidth: .infinity)
                    }
                }
                .disabled(!canSubmit)
            } footer: {
                if let submissionError {
                    Text(submissionError)
                        .foregroundStyle(.red)
                } else {
                    Text("We read every submission. Replies aren't guaranteed, but real bugs get fixed quickly.")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("Send feedback")
        .navigationBarTitleDisplayMode(.inline)
        .alert("Thanks for the feedback", isPresented: $showSuccessConfirmation) {
            Button("OK") { dismiss() }
        } message: {
            Text("We've received your message. If something looks broken, we'll dig into it.")
        }
        .onAppear { isMessageFocused = true }
    }

    private func submit() async {
        guard canSubmit else { return }
        isSubmitting = true
        submissionError = nil
        defer { isSubmitting = false }

        let request = SubmitFeedbackRequest(
            message: trimmedMessage,
            appVersion: Self.appVersion(),
            buildNumber: Self.buildNumber(),
            deviceModel: Self.deviceModel(),
            osVersion: Self.osVersion(),
            locale: Locale.current.identifier
        )

        do {
            _ = try await appStore.apiClient.submitFeedback(request)
            // Clear before dismissing so a re-open of the form doesn't show
            // the previous message.
            message = ""
            showSuccessConfirmation = true
        } catch {
            // Auth-failure recovery uses the same path as the rest of the app.
            _ = appStore.handleAuthFailureIfNeeded(error)
            submissionError = (error as? LocalizedError)?.errorDescription
                ?? error.localizedDescription
        }
    }

    // MARK: - Metadata helpers

    private static func appVersion() -> String? {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
    }

    private static func buildNumber() -> String? {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String
    }

    private static func deviceModel() -> String? {
        // `UIDevice.current.model` is the family ("iPhone"); for the actual
        // marketing name we'd need a lookup table by `utsname.machine`. The
        // family + the OS version + the app version are usually enough to
        // triage, so we stay simple here.
        UIDevice.current.model
    }

    private static func osVersion() -> String? {
        let v = UIDevice.current.systemVersion
        let name = UIDevice.current.systemName
        return "\(name) \(v)"
    }
}

#Preview {
    NavigationStack {
        FeedbackView()
            .environmentObject(AppStore())
    }
}
