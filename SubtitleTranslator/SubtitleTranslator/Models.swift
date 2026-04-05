import Foundation

enum SidebarItem: String, CaseIterable, Identifiable {
    case process = "process"
    case preview = "preview"
    case downloads = "downloads"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .process: return "處理影片"
        case .preview: return "字幕預覽"
        case .downloads: return "下載檔案"
        }
    }

    var icon: String {
        switch self {
        case .process: return "play.circle.fill"
        case .preview: return "doc.text.fill"
        case .downloads: return "arrow.down.circle.fill"
        }
    }
}

enum ProcessingStep: String, CaseIterable, Identifiable {
    case download, extract, transcribe, translate, burn

    var id: String { rawValue }

    var label: String {
        switch self {
        case .download: return "下載影片"
        case .extract: return "提取音頻"
        case .transcribe: return "語音轉錄"
        case .translate: return "翻譯字幕"
        case .burn: return "燒錄字幕到影片"
        }
    }

    var icon: String {
        switch self {
        case .download: return "arrow.down.circle"
        case .extract: return "waveform"
        case .transcribe: return "text.bubble"
        case .translate: return "globe"
        case .burn: return "film"
        }
    }

    var index: Int {
        switch self {
        case .download: return 1
        case .extract: return 2
        case .transcribe: return 3
        case .translate: return 4
        case .burn: return 5
        }
    }
}

enum StepStatus: Equatable {
    case waiting, running, done, error
}

struct StepState: Equatable {
    var status: StepStatus = .waiting
    var message: String = ""
    var progress: Double? = nil
}

struct DownloadItem: Identifiable {
    let id = UUID()
    let key: String
    let label: String
    let sublabel: String
    let icon: String
    let color: String
    let url: URL
}

struct LanguageItem: Identifiable, Hashable {
    var id: String { code }
    let code: String
    let name: String
}
