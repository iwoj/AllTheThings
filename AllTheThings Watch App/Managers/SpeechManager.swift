import Foundation
import Speech
import AVFoundation

/// Records speech via the microphone and transcribes it on-device using SFSpeechRecognizer.
///
/// Usage:
/// 1. Call ``requestAuthorisation()`` once at app launch.
/// 2. Call ``startRecording()`` when the wearer presses the mic button.
/// 3. Call ``stopRecording()`` → returns the final transcription string.
@MainActor
final class SpeechManager: ObservableObject {

    // MARK: - Published

    @Published private(set) var isRecording = false
    @Published private(set) var partialTranscription = ""
    @Published private(set) var authStatus: SFSpeechRecognizerAuthorizationStatus = .notDetermined
    @Published private(set) var micAuthStatus: AVAudioSession.RecordPermission = .undetermined

    // MARK: - Private

    private let recognizer: SFSpeechRecognizer?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask:    SFSpeechRecognitionTask?
    private let audioEngine = AVAudioEngine()

    // MARK: - Init

    init(locale: Locale = .current) {
        recognizer = SFSpeechRecognizer(locale: locale)
        authStatus     = SFSpeechRecognizer.authorizationStatus()
        micAuthStatus  = AVAudioSession.sharedInstance().recordPermission
    }

    // MARK: - Authorisation

    var isAvailable: Bool {
        authStatus == .authorized &&
        micAuthStatus == .granted &&
        recognizer?.isAvailable == true
    }

    func requestAuthorisation() async {
        // Speech recognition permission
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            SFSpeechRecognizer.requestAuthorization { [weak self] status in
                Task { @MainActor [weak self] in
                    self?.authStatus = status
                    cont.resume()
                }
            }
        }

        // Microphone permission
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            AVAudioSession.sharedInstance().requestRecordPermission { [weak self] granted in
                Task { @MainActor [weak self] in
                    self?.micAuthStatus = granted ? .granted : .denied
                    cont.resume()
                }
            }
        }
    }

    // MARK: - Recording

    /// Start capturing audio and producing partial transcriptions.
    /// - Throws: if the audio engine cannot be configured or started.
    func startRecording() throws {
        guard isAvailable else { return }

        // Cancel any in-flight task
        recognitionTask?.cancel()
        recognitionTask = nil

        let audioSession = AVAudioSession.sharedInstance()
        try audioSession.setCategory(.record, mode: .measurement,
                                     options: .duckOthers)
        try audioSession.setActive(true, options: .notifyOthersOnDeactivation)

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults    = true
        request.requiresOnDeviceRecognition   = true   // keep data on-device
        recognitionRequest = request

        partialTranscription = ""

        recognitionTask = recognizer?.recognitionTask(with: request) { [weak self] result, error in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if let result {
                    self.partialTranscription = result.bestTranscription.formattedString
                }
                if error != nil || result?.isFinal == true {
                    self.tearDownAudio()
                }
            }
        }

        let inputNode    = audioEngine.inputNode
        let inputFormat  = inputNode.outputFormat(forBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: inputFormat) { [weak self] buffer, _ in
            self?.recognitionRequest?.append(buffer)
        }

        audioEngine.prepare()
        try audioEngine.start()
        isRecording = true
    }

    /// Stop recording and return the final transcription.
    @discardableResult
    func stopRecording() -> String {
        let result = partialTranscription
        tearDownAudio()
        partialTranscription = ""
        return result
    }

    // MARK: - Private helpers

    private func tearDownAudio() {
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        recognitionRequest?.endAudio()
        recognitionRequest = nil
        recognitionTask    = nil
        isRecording        = false
        try? AVAudioSession.sharedInstance()
            .setActive(false, options: .notifyOthersOnDeactivation)
    }
}
