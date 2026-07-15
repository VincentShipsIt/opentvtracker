import AVFoundation
import Observation
import Speech

@MainActor
@Observable
final class VoiceSearchTranscriber {
    private(set) var isRecording = false
    private(set) var transcript = ""
    private(set) var errorMessage: String?

    private let audioEngine = AVAudioEngine()
    private let speechRecognizer: SFSpeechRecognizer?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var hasInstalledTap = false

    init(locale: Locale = .current) {
        speechRecognizer = SFSpeechRecognizer(locale: locale)
        speechRecognizer?.queue = .main
    }

    func toggleRecording() async {
        if isRecording {
            stopRecording()
        } else {
            await startRecording()
        }
    }

    func startRecording() async {
        guard !isRecording else { return }
        errorMessage = nil

        guard await requestSpeechPermission() else {
            errorMessage = "Allow Speech Recognition in Settings to use voice search."
            return
        }
        guard await requestMicrophonePermission() else {
            errorMessage = "Allow Microphone access in Settings to use voice search."
            return
        }
        guard let speechRecognizer, speechRecognizer.isAvailable else {
            errorMessage = "Voice recognition is unavailable right now. You can still type your request."
            return
        }

        stopRecognitionResources()

        do {
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.record, mode: .measurement, options: [.duckOthers])
            try audioSession.setActive(true, options: .notifyOthersOnDeactivation)

            let request = SFSpeechAudioBufferRecognitionRequest()
            request.shouldReportPartialResults = true
            request.taskHint = .dictation
            if speechRecognizer.supportsOnDeviceRecognition {
                request.requiresOnDeviceRecognition = true
            }

            let inputNode = audioEngine.inputNode
            let recordingFormat = inputNode.outputFormat(forBus: 0)
            inputNode.installTap(onBus: 0, bufferSize: 1_024, format: recordingFormat) { buffer, _ in
                request.append(buffer)
            }
            hasInstalledTap = true
            recognitionRequest = request
            transcript = ""

            recognitionTask = speechRecognizer.recognitionTask(with: request) { [weak self] result, error in
                let text = result?.bestTranscription.formattedString
                let isFinal = result?.isFinal ?? false
                let failed = error != nil
                Task { @MainActor [weak self] in
                    self?.consume(text: text, isFinal: isFinal, failed: failed)
                }
            }

            audioEngine.prepare()
            try audioEngine.start()
            isRecording = true
        } catch {
            stopRecognitionResources()
            errorMessage = "The microphone could not start. You can still type your request."
        }
    }

    func stopRecording() {
        guard isRecording || recognitionRequest != nil else { return }
        isRecording = false
        audioEngine.stop()
        recognitionRequest?.endAudio()
        removeInputTapIfNeeded()
        deactivateAudioSession()
    }

    private func consume(text: String?, isFinal: Bool, failed: Bool) {
        if let text, !text.isEmpty {
            transcript = text
        }
        if isFinal || failed {
            stopRecognitionResources()
            if failed, transcript.isEmpty {
                errorMessage = "I couldn't hear that clearly. Try again or type your request."
            }
        }
    }

    private func stopRecognitionResources() {
        isRecording = false
        if audioEngine.isRunning { audioEngine.stop() }
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest = nil
        removeInputTapIfNeeded()
        deactivateAudioSession()
    }

    private func removeInputTapIfNeeded() {
        guard hasInstalledTap else { return }
        audioEngine.inputNode.removeTap(onBus: 0)
        hasInstalledTap = false
    }

    private func deactivateAudioSession() {
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private func requestSpeechPermission() async -> Bool {
        let status = SFSpeechRecognizer.authorizationStatus()
        if status == .authorized { return true }
        if status != .notDetermined { return false }
        return await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { updatedStatus in
                continuation.resume(returning: updatedStatus == .authorized)
            }
        }
    }

    private func requestMicrophonePermission() async -> Bool {
        switch AVAudioApplication.shared.recordPermission {
        case .granted:
            return true
        case .denied:
            return false
        case .undetermined:
            return await withCheckedContinuation { continuation in
                AVAudioApplication.requestRecordPermission { granted in
                    continuation.resume(returning: granted)
                }
            }
        @unknown default:
            return false
        }
    }
}
