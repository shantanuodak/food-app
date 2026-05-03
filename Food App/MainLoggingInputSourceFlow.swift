import SwiftUI

extension MainLoggingShellView {

    func handleVoiceModeTapped() {
        Task {
            guard await speechService.requestAuthorization() else {
                parseError = "Microphone or speech recognition permission was denied. Enable them in Settings."
                inputMode = .text
                return
            }

            do {
                try speechService.startListening()
                setVoiceOverlayPresented(true)
            } catch {
                parseError = "Could not start voice recognition: \(error.localizedDescription)"
                inputMode = .text
            }
        }
    }

    @MainActor
    func insertVoiceTranscription(_ text: String) {
        // Find the first empty unsaved row, or append a new one
        if let emptyIndex = inputRows.firstIndex(where: {
            !$0.isSaved && $0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }) {
            inputRows[emptyIndex].text = text
            inputRows[emptyIndex].showInsertShimmer = true
        } else {
            var newRow = HomeLogRow.empty()
            newRow.text = text
            newRow.showInsertShimmer = true
            inputRows.append(newRow)
        }

        // Track input source for save contract
        latestParseInputKind = "voice"

        // Switch back to text mode — rowTextSignature change triggers
        // scheduleDebouncedParse automatically via the existing onChange observer
        inputMode = .text

        ensureDraftTimingStarted()
    }

    // MARK: - Voice Helpers

    func setVoiceOverlayPresented(_ presented: Bool) {
        isVoiceOverlayPresented = presented
        NotificationCenter.default.post(
            name: .voiceRecordingStateChanged,
            object: nil,
            userInfo: ["isRecording": presented]
        )
    }

    func handleVoiceHaptic(level: Float) {
        guard level > 0.3 else { return }
        let now = Date()
        guard now.timeIntervalSince(lastHapticTime) > 0.3 else { return }
        lastHapticTime = now
        Self.voiceHapticGenerator.impactOccurred(intensity: CGFloat(min(level, 1.0)))
    }

    func handleCameraSourceSelection(_ source: CameraInputSource) {
        selectedCameraSource = source
        inputMode = .camera
        switch source {
        case .takePicture:
            isCustomCameraPresented = true
        case .photo:
            imagePickerSourceType = .photoLibrary
            isImagePickerPresented = true
        }
    }
}
