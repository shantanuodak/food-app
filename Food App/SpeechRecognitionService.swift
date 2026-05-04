import Foundation
import Combine
import Speech
import AVFoundation

enum SpeechRecognitionError: LocalizedError {
    case notAuthorized
    case recognizerUnavailable
    case audioEngineError(String)
    case recognitionFailed(String)

    var errorDescription: String? {
        switch self {
        case .notAuthorized:
            return "Microphone or speech recognition permission was denied. Enable them in Settings."
        case .recognizerUnavailable:
            return "Voice recognition is not available on this device."
        case let .audioEngineError(message):
            return "Audio error: \(message)"
        case let .recognitionFailed(message):
            return "Recognition failed: \(message)"
        }
    }
}

@MainActor
final class SpeechRecognitionService: ObservableObject {

    // MARK: - Published State

    @Published private(set) var transcribedText: String = ""
    @Published private(set) var isListening: Bool = false
    @Published private(set) var error: String?
    @Published private(set) var audioLevel: Float = 0

    // MARK: - Private Properties

    private let speechRecognizer: SFSpeechRecognizer?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let audioEngine = AVAudioEngine()
    private var silenceTimer: Timer?
    private let silenceThreshold: TimeInterval = 2.0

    // MARK: - Init

    init(locale: Locale = .current) {
        self.speechRecognizer = SFSpeechRecognizer(locale: locale)
    }

    // MARK: - Permission

    func requestAuthorization() async -> Bool {
        let speechGranted = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status == .authorized)
            }
        }

        let micGranted: Bool
        if #available(iOS 17.0, *) {
            micGranted = await AVAudioApplication.requestRecordPermission()
        } else {
            micGranted = await withCheckedContinuation { continuation in
                AVAudioSession.sharedInstance().requestRecordPermission { granted in
                    continuation.resume(returning: granted)
                }
            }
        }

        return speechGranted && micGranted
    }

    var isAuthorized: Bool {
        SFSpeechRecognizer.authorizationStatus() == .authorized
    }

    // MARK: - Listening

    func startListening() throws {
        // Clean up any previous session
        stopListening()

        guard let speechRecognizer, speechRecognizer.isAvailable else {
            throw SpeechRecognitionError.recognizerUnavailable
        }

        // Reset state
        transcribedText = ""
        error = nil

        // Configure audio session
        let audioSession = AVAudioSession.sharedInstance()
        do {
            try audioSession.setCategory(.record, mode: .measurement, options: .duckOthers)
            try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            throw SpeechRecognitionError.audioEngineError(error.localizedDescription)
        }

        // Create recognition request
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        if #available(iOS 13, *) {
            request.requiresOnDeviceRecognition = true
        }
        self.recognitionRequest = request

        // Install audio tap. The audio engine invokes this closure on a
        // non-main thread for every buffer, so it must be Sendable. Two
        // patterns matter here:
        //
        //   1. Capture `request` directly (a local `let` from above) so
        //      the buffer-append path does NOT cross actor isolation.
        //      Going through `self?.recognitionRequest` would touch a
        //      `@MainActor`-isolated property from a Sendable closure
        //      and trigger the Swift 6 "captured var 'self' in
        //      concurrently-executing code" diagnostic.
        //
        //   2. The audio-level update hops back to the main actor via
        //      a single `Task { @MainActor in }` and accesses self
        //      through the outer `[weak self]` capture. Don't re-add
        //      `[weak self]` on the inner Task — it's redundant and
        //      Swift 6 flags the duplicate.
        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [weak self, request] buffer, _ in
            request.append(buffer)

            // Compute RMS audio level for visualization
            guard let channelData = buffer.floatChannelData?[0] else { return }
            let frameLength = Int(buffer.frameLength)
            var sum: Float = 0
            for i in 0..<frameLength { sum += channelData[i] * channelData[i] }
            let rms = sqrtf(sum / Float(max(frameLength, 1)))
            let db = 20 * log10f(max(rms, 1e-6))
            // Map -60dB...0dB → 0...1
            let normalized = max(0, min(1, (db + 60) / 60))
            Task { @MainActor in
                self?.audioLevel = normalized
            }
        }

        // Start audio engine
        do {
            audioEngine.prepare()
            try audioEngine.start()
        } catch {
            inputNode.removeTap(onBus: 0)
            throw SpeechRecognitionError.audioEngineError(error.localizedDescription)
        }

        isListening = true

        // Start recognition task. The closure passed here is @Sendable
        // and runs on the speech framework's internal queue. Capturing
        // `self` (a `@MainActor`-isolated reference) into a Sendable
        // closure is the source of the Swift 6 "Reference to captured
        // var 'self' in concurrently-executing code" diagnostic.
        //
        // Fix: extract every value we need from `result` and `error`
        // BEFORE the Task hop, so the outer closure captures only
        // `Sendable` value types. Then the inner `Task { @MainActor }`
        // is the single point where we cross into self's isolation.
        recognitionTask = speechRecognizer.recognitionTask(with: request) { result, error in
            let recognizedText: String? = result?.bestTranscription.formattedString
            let isFinal: Bool = result?.isFinal ?? false
            let nsError = error as NSError?
            let errorDomain: String? = nsError?.domain
            let errorCode: Int? = nsError?.code
            let errorMessage: String? = error?.localizedDescription
            Task { @MainActor [weak self] in
                guard let self else { return }

                if let recognizedText {
                    self.transcribedText = recognizedText
                    self.resetSilenceTimer()
                    if isFinal {
                        self.stopListening()
                    }
                }

                if let errorMessage {
                    // Ignore cancellation errors (happens on normal stopListening)
                    if errorDomain == "kAFAssistantErrorDomain" && errorCode == 216 {
                        // "Request was canceled" — this is expected when we stop
                        return
                    }
                    if errorCode == 1110 {
                        // "No speech detected" — not really an error for our use case
                        self.stopListening()
                        return
                    }
                    self.error = errorMessage
                    self.stopListening()
                }
            }
        }

        // Start initial silence timer — if user says nothing for 2s, stop
        resetSilenceTimer()

        // Observe audio session interruptions (phone calls, etc.).
        //
        // Known Swift 6 strict-concurrency pain point: closure-based
        // `addObserver` whose body reaches back into a `@MainActor`
        // class will emit "Reference to captured var 'self' in
        // concurrently-executing code" no matter how the captures are
        // arranged — explicit `[weak self]`, implicit capture via Task,
        // and "capture-via-handler-closure" all trip it. The proper
        // Swift 6 fix is to switch to `for await _ in
        // NotificationCenter.default.notifications(named:)` and store
        // the long-running Task — that's a meaningful refactor (Task
        // lifecycle, cancellation in `stopListening`, etc.) and out of
        // scope for tonight.
        //
        // Accepting the warning here: it's a pre-existing diagnostic,
        // build still succeeds, behavior is correct (audio interruption
        // stops listening as intended). Filed for the post-Tier-1
        // strict-concurrency cleanup.
        NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: audioSession,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.stopListening()
            }
        }
    }

    func stopListening() {
        silenceTimer?.invalidate()
        silenceTimer = nil

        if audioEngine.isRunning {
            audioEngine.stop()
            audioEngine.inputNode.removeTap(onBus: 0)
        }

        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        recognitionRequest = nil
        recognitionTask = nil

        isListening = false
        audioLevel = 0

        // Deactivate audio session (non-fatal if it fails)
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)

        NotificationCenter.default.removeObserver(self, name: AVAudioSession.interruptionNotification, object: nil)
    }

    // MARK: - Silence Detection

    private func resetSilenceTimer() {
        silenceTimer?.invalidate()
        silenceTimer = Timer.scheduledTimer(withTimeInterval: silenceThreshold, repeats: false) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.isListening else { return }
                self.stopListening()
            }
        }
    }
}
