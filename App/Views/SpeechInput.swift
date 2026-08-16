import SwiftUI
import Speech
import AVFoundation

/// Apple Dictation (SFSpeechRecognizer) voice input — free, first-party,
/// on-device capable, no API key. Third-party keyboards (Wispr Flow, Tablas, …)
/// also work in any standard TextField with zero integration.
final class SpeechInput: ObservableObject {
    @Published var isRecording = false
    @Published var liveText = ""
    @Published var errorMessage: String?

    private let audioEngine = AVAudioEngine()
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var onStop: ((String) -> Void)?
    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "zh-CN")) ?? SFSpeechRecognizer()

    func toggle(onStop: @escaping (String) -> Void) {
        if isRecording { stop() } else { start(onStop: onStop) }
    }

    private func start(onStop: @escaping (String) -> Void) {
        self.onStop = onStop
        liveText = ""
        errorMessage = nil

        guard let recognizer, recognizer.isAvailable else {
            errorMessage = "语音识别暂不可用"
            return
        }

        SFSpeechRecognizer.requestAuthorization { [weak self] status in
            DispatchQueue.main.async {
                guard status == .authorized else {
                    self?.errorMessage = "请在设置中允许语音识别权限"
                    return
                }
                self?.beginRecording(recognizer)
            }
        }
    }

    private func beginRecording(_ recognizer: SFSpeechRecognizer) {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.record, mode: .measurement, options: .duckOthers)
            try session.setActive(true, options: .notifyOthersOnDeactivation)

            let request = SFSpeechAudioBufferRecognitionRequest()
            request.shouldReportPartialResults = true
            recognitionRequest = request

            let inputNode = audioEngine.inputNode
            let format = inputNode.outputFormat(forBus: 0)
            inputNode.removeTap(onBus: 0)
            inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
                self?.recognitionRequest?.append(buffer)
            }

            audioEngine.prepare()
            try audioEngine.start()
            isRecording = true

            recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
                DispatchQueue.main.async {
                    if let result {
                        self?.liveText = result.bestTranscription.formattedString
                    }
                    if error != nil {
                        self?.errorMessage = error?.localizedDescription
                    }
                }
            }
        } catch {
            errorMessage = "录音启动失败: \(error.localizedDescription)"
        }
    }

    private func stop() {
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest = nil
        isRecording = false

        let text = liveText.trimmingCharacters(in: .whitespacesAndNewlines)
        liveText = ""
        onStop?(text)
        onStop = nil

        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}
