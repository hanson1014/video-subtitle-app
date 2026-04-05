import Foundation
import SwiftUI

@MainActor
class TranslationViewModel: ObservableObject {
    @Published var serverHost = "localhost"
    @Published var serverPort = "8899"
    @Published var videoURL = ""
    @Published var targetLanguage = "zh-TW"
    @Published var whisperModel = "medium"
    @Published var languages: [LanguageItem] = []
    @Published var isProcessing = false
    @Published var isComplete = false
    @Published var steps: [ProcessingStep: StepState] = [:]
    @Published var srtOriginal = ""
    @Published var srtTranslated = ""
    @Published var downloads: [DownloadItem] = []
    @Published var errorMessage: String? = nil
    @Published var selectedSidebar: SidebarItem = .process

    private var webSocketTask: URLSessionWebSocketTask?

    var serverURL: String { "http://\(serverHost):\(serverPort)" }

    var runningStepCount: Int {
        steps.values.filter { $0.status == .running }.count
    }

    var doneStepCount: Int {
        steps.values.filter { $0.status == .done }.count
    }

    init() {
        resetSteps()
        loadLanguages()
    }

    func resetSteps() {
        steps = Dictionary(uniqueKeysWithValues: ProcessingStep.allCases.map { ($0, StepState()) })
    }

    func loadLanguages() {
        guard let url = URL(string: "\(serverURL)/api/languages") else { return }
        URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
            guard let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let langs = json["languages"] as? [String: String] else { return }
            DispatchQueue.main.async {
                self?.languages = langs.map { LanguageItem(code: $0.key, name: $0.value) }
                    .sorted { $0.code < $1.code }
            }
        }.resume()
    }

    func startProcessing() {
        guard !videoURL.trimmingCharacters(in: .whitespaces).isEmpty else { return }

        resetSteps()
        isProcessing = true
        isComplete = false
        errorMessage = nil
        downloads = []
        srtOriginal = ""
        srtTranslated = ""

        let wsURL = "ws://\(serverHost):\(serverPort)/ws/process"
        guard let url = URL(string: wsURL) else { return }

        let session = URLSession(configuration: .default)
        webSocketTask = session.webSocketTask(with: url)
        webSocketTask?.resume()

        let params: [String: String] = [
            "url": videoURL.trimmingCharacters(in: .whitespaces),
            "target_lang": targetLanguage,
            "whisper_model": whisperModel
        ]
        if let data = try? JSONSerialization.data(withJSONObject: params),
           let str = String(data: data, encoding: .utf8) {
            webSocketTask?.send(.string(str)) { _ in }
        }

        receiveMessage()
    }

    func cancelProcessing() {
        webSocketTask?.cancel(with: .goingAway, reason: nil)
        isProcessing = false
    }

    // MARK: - Private

    private func receiveMessage() {
        webSocketTask?.receive { [weak self] result in
            DispatchQueue.main.async {
                switch result {
                case .success(let message):
                    if case .string(let text) = message {
                        self?.handleMessage(text)
                    }
                    self?.receiveMessage()
                case .failure:
                    self?.isProcessing = false
                }
            }
        }
    }

    private func handleMessage(_ text: String) {
        guard let data = text.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let stepStr = json["step"] as? String else { return }

        let status = json["status"] as? String ?? ""
        let message = json["message"] as? String ?? ""

        if stepStr == "error" {
            errorMessage = message
            isProcessing = false
            return
        }

        if let step = ProcessingStep(rawValue: stepStr) {
            switch status {
            case "started":
                steps[step] = StepState(status: .running, message: message)
            case "done":
                steps[step] = StepState(status: .done, message: message)
            case "error":
                steps[step] = StepState(status: .error, message: message)
            case "progress":
                let prog = json["progress"] as? Double
                steps[step] = StepState(status: .running, message: message, progress: prog)
            default:
                break
            }
        }

        // SRT preview
        if let srt = json["srt_preview"] as? String {
            if stepStr == "transcribe" {
                srtOriginal = srt
            } else {
                srtTranslated = srt
            }
        }

        // Downloads
        if let dlMap = json["downloads"] as? [String: String] {
            var items: [DownloadItem] = []
            let configs: [(String, String, String, String, String)] = [
                ("video", "字幕影片", "MP4 格式", "film", "blue"),
                ("original_srt", "原文字幕", "SRT 格式", "doc.text", "orange"),
                ("translated_srt", "翻譯字幕", "SRT 格式", "globe", "green"),
                ("dual_srt", "雙語字幕", "SRT 格式", "doc.on.doc", "purple")
            ]
            for (key, label, sub, icon, color) in configs {
                if let path = dlMap[key], let url = URL(string: "\(serverURL)\(path)") {
                    items.append(DownloadItem(key: key, label: label, sublabel: sub, icon: icon, color: color, url: url))
                }
            }
            downloads = items
        }

        // Complete
        if stepStr == "complete" {
            isProcessing = false
            isComplete = true
        }
    }
}
