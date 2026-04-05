import SwiftUI

@main
struct SubtitleTranslatorApp: App {
    @StateObject private var vm = TranslationViewModel()
    @StateObject private var server = ServerManager()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(vm)
                .environmentObject(server)
                .frame(minWidth: 780, minHeight: 520)
                .onAppear {
                    server.startServer()
                }
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified(showsTitle: false))
        .defaultSize(width: 920, height: 640)
        .commands {
            CommandGroup(after: .appSettings) {
                Button("重新啟動伺服器") {
                    server.restartServer()
                }
                .keyboardShortcut("r", modifiers: [.command, .shift])
            }
        }
    }
}

struct RootView: View {
    @EnvironmentObject var server: ServerManager
    @EnvironmentObject var vm: TranslationViewModel

    var body: some View {
        Group {
            switch server.state {
            case .stopped, .starting:
                StartingView()
            case .running:
                ContentView()
                    .onAppear { vm.loadLanguages() }
            case .error(let msg):
                ErrorView(message: msg)
            }
        }
        .animation(.easeInOut(duration: 0.3), value: server.state == .running)
    }
}

// MARK: - Starting View

struct StartingView: View {
    @State private var dots = ""
    private let timer = Timer.publish(every: 0.5, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: "text.bubble.fill")
                .font(.system(size: 48))
                .foregroundStyle(.blue)
                .symbolEffect(.pulse, options: .repeating)

            Text("字幕翻譯工具")
                .font(.title)
                .fontWeight(.bold)

            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                Text("正在啟動伺服器\(dots)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Text("首次啟動需要載入模型，可能需要較長時間")
                .font(.caption)
                .foregroundStyle(.tertiary)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onReceive(timer) { _ in
            dots = dots.count >= 3 ? "" : dots + "."
        }
    }
}

// MARK: - Error View

struct ErrorView: View {
    let message: String
    @EnvironmentObject var server: ServerManager
    @State private var showPathEditor = false
    @State private var editingPath = ""

    var body: some View {
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 44))
                .foregroundStyle(.orange)

            Text("伺服器啟動失敗")
                .font(.title2)
                .fontWeight(.bold)

            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 400)

            HStack(spacing: 12) {
                Button("設定項目路徑") {
                    editingPath = server.detectedProjectPath
                    showPathEditor = true
                }
                .buttonStyle(.bordered)

                Button("重新啟動") {
                    server.restartServer()
                }
                .buttonStyle(.borderedProminent)
            }

            if showPathEditor {
                GroupBox {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("項目路徑")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        HStack {
                            TextField("路徑", text: $editingPath)
                                .textFieldStyle(.roundedBorder)

                            Button("選擇") {
                                let panel = NSOpenPanel()
                                panel.canChooseDirectories = true
                                panel.canChooseFiles = false
                                panel.allowsMultipleSelection = false
                                panel.message = "選擇包含 main.py 嘅項目資料夾"
                                if panel.runModal() == .OK, let url = panel.url {
                                    editingPath = url.path
                                }
                            }
                        }

                        Button("儲存並重新啟動") {
                            server.projectPath = editingPath
                            showPathEditor = false
                            server.restartServer()
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                    }
                    .padding(4)
                }
                .frame(maxWidth: 450)
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
