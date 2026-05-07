import SwiftUI
import UIKit

extension MainLoggingShellView {

    func handleVoiceModeTapped() {
        isNoteEditorFocused = false
        activeEditingRowID = nil
        voiceHandoffTask?.cancel()
        voiceRevealTask?.cancel()
        voiceOverlayPhase = .listening
        voiceCaptureCancelRequested = false
        NotificationCenter.default.post(name: .dismissKeyboardFromTabBar, object: nil)
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        Self.voiceHapticGenerator.prepare()
        Self.voiceHapticGenerator.impactOccurred(intensity: 0.58)

        Task {
            guard await speechService.requestAuthorization() else {
                parseError = "Microphone or speech recognition permission was denied. Enable them in Settings."
                inputMode = .text
                return
            }

            do {
                setVoiceOverlayPresented(true)
                try speechService.startListening()
            } catch {
                setVoiceOverlayPresented(false)
                parseError = "Could not start voice recognition: \(error.localizedDescription)"
                inputMode = .text
            }
        }
    }

    @MainActor
    func insertVoiceTranscription(_ text: String) {
        insertVoiceTranscription(text, revealInRow: false)
    }

    @MainActor
    func insertVoiceTranscription(_ text: String, revealInRow: Bool) {
        if let emptyIndex = inputRows.firstIndex(where: {
            !$0.isSaved && $0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }) {
            inputRows[emptyIndex].text = revealInRow ? "" : text
            inputRows[emptyIndex].showInsertShimmer = true
            if revealInRow {
                revealVoiceText(text, inRowAt: emptyIndex)
            }
        } else {
            var newRow = HomeLogRow.empty()
            newRow.text = revealInRow ? "" : text
            newRow.showInsertShimmer = true
            inputRows.append(newRow)
            if revealInRow {
                revealVoiceText(text, inRowAt: inputRows.count - 1)
            }
        }

        latestParseInputKind = "voice"
        inputMode = .text

        ensureDraftTimingStarted()
    }

    @MainActor
    private func revealVoiceText(_ text: String, inRowAt initialIndex: Int) {
        let rowID = inputRows[initialIndex].id
        voiceRevealTask?.cancel()
        voiceRevealTask = Task { @MainActor in
            defer { voiceRevealTask = nil }
            let characters = Array(text)
            guard !characters.isEmpty else {
                setVoiceOverlayPresented(false)
                return
            }

            var revealed = ""
            let chunkSize = max(1, Int(ceil(Double(characters.count) / 28.0)))
            for offset in stride(from: 0, to: characters.count, by: chunkSize) {
                guard let currentIndex = inputRows.firstIndex(where: { $0.id == rowID }) else { return }
                let end = min(offset + chunkSize, characters.count)
                revealed = String(characters[0..<end])
                suppressDebouncedParseOnce = true
                inputRows[currentIndex].text = revealed
                try? await Task.sleep(nanoseconds: 18_000_000)
            }

            if let currentIndex = inputRows.firstIndex(where: { $0.id == rowID }) {
                suppressDebouncedParseOnce = true
                inputRows[currentIndex].text = text
                inputRows[currentIndex].showInsertShimmer = true
                latestParseInputKind = "voice"
                triggerParseNow()
            }

            try? await Task.sleep(nanoseconds: 180_000_000)
            guard !Task.isCancelled else { return }
            setVoiceOverlayPresented(false)
        }
    }

    // MARK: - Voice Helpers

    func setVoiceOverlayPresented(_ presented: Bool) {
        isVoiceOverlayPresented = presented
        voiceOverlayPhase = presented ? voiceOverlayPhase : .listening
        NotificationCenter.default.post(
            name: .voiceRecordingStateChanged,
            object: nil,
            userInfo: ["isRecording": presented]
        )
    }

    @MainActor
    func cancelVoiceCapture() {
        voiceCaptureCancelRequested = true
        voiceHandoffTask?.cancel()
        voiceRevealTask?.cancel()
        voiceHandoffTask = nil
        voiceRevealTask = nil
        speechService.cancelListening()
        setVoiceOverlayPresented(false)
        inputMode = .text
    }

    @MainActor
    func completeVoiceCapture(with rawText: String) {
        voiceCaptureCancelRequested = false
        let initialText = rawText.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !initialText.isEmpty else {
            setVoiceOverlayPresented(false)
            parseInfoMessage = "No speech detected. Try again."
            inputMode = .text
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                if parseInfoMessage == "No speech detected. Try again." {
                    withAnimation { parseInfoMessage = nil }
                }
            }
            return
        }

        voiceHandoffTask?.cancel()
        voiceRevealTask?.cancel()
        voiceOverlayPhase = .handoff
        Self.voiceHapticGenerator.prepare()
        Self.voiceHapticGenerator.impactOccurred(intensity: 0.42)
        voiceHandoffTask = Task { @MainActor in
            defer { voiceHandoffTask = nil }
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard !Task.isCancelled else { return }
            let latestText = speechService.transcribedText
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let finalText = latestText.isEmpty ? initialText : latestText
            insertVoiceTranscription(finalText, revealInRow: true)
        }
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
