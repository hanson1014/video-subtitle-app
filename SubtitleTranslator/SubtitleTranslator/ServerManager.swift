import Foundation
import SwiftUI

@MainActor
class ServerManager: ObservableObject {
    enum ServerState: Equatable {
        case stopped
        case starting
        case running
        case error(String)
    }

    @Published var state: ServerState = .stopped

    @AppStorage("projectPath") var projectPath: String = ""

    private var process: Process?
    private var outputPipe: Pipe?
    private var healthCheckTimer: Timer?

    var detectedProjectPath: String {
        if !projectPath.isEmpty { return projectPath }

        // Try to find the project relative to the app bundle
        let candidates = [
            // Same directory as the Xcode project
            URL(fileURLWithPath: #file)
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .path,
            // Common default
            NSHomeDirectory() + "/video-subtitle-app",
        ]

        for path in candidates {
            let mainPy = (path as NSString).appendingPathComponent("main.py")
            if FileManager.default.fileExists(atPath: mainPy) {
                return path
            }
        }

        return NSHomeDirectory() + "/video-subtitle-app"
    }

    var pythonPath: String {
        let venvPython = (detectedProjectPath as NSString).appendingPathComponent("venv/bin/python3")
        if FileManager.default.fileExists(atPath: venvPython) {
            return venvPython
        }
        return "/usr/bin/python3"
    }

    var mainPyPath: String {
        (detectedProjectPath as NSString).appendingPathComponent("main.py")
    }

    var isProjectValid: Bool {
        FileManager.default.fileExists(atPath: mainPyPath) &&
        FileManager.default.fileExists(atPath: pythonPath)
    }

    func startServer() {
        guard state != .running && state != .starting else { return }
        guard isProjectValid else {
            state = .error("找不到項目文件，請設定正確嘅項目路徑")
            return
        }

        state = .starting

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: pythonPath)
        proc.arguments = [mainPyPath]
        proc.currentDirectoryURL = URL(fileURLWithPath: detectedProjectPath)

        // Set environment so Python can find venv packages
        var env = ProcessInfo.processInfo.environment
        let venvPath = (detectedProjectPath as NSString).appendingPathComponent("venv")
        env["VIRTUAL_ENV"] = venvPath
        env["PATH"] = "\(venvPath)/bin:" + (env["PATH"] ?? "")
        // Remove PYTHONHOME if set (can interfere with venv)
        env.removeValue(forKey: "PYTHONHOME")
        proc.environment = env

        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = pipe
        outputPipe = pipe

        proc.terminationHandler = { [weak self] process in
            DispatchQueue.main.async {
                if self?.state == .running || self?.state == .starting {
                    self?.state = .error("伺服器意外停止（退出碼：\(process.terminationStatus)）")
                }
            }
        }

        do {
            try proc.run()
            process = proc
            startHealthCheck()
        } catch {
            state = .error("無法啟動伺服器：\(error.localizedDescription)")
        }
    }

    func stopServer() {
        healthCheckTimer?.invalidate()
        healthCheckTimer = nil

        if let proc = process, proc.isRunning {
            proc.terminate()
            // Give it a moment, then force kill if needed
            DispatchQueue.global().asyncAfter(deadline: .now() + 2) {
                if proc.isRunning {
                    proc.interrupt()
                }
            }
        }
        process = nil
        state = .stopped
    }

    func restartServer() {
        stopServer()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            self.startServer()
        }
    }

    // MARK: - Health Check

    private func startHealthCheck() {
        // Poll the server until it responds
        var attempts = 0
        let maxAttempts = 60 // 30 seconds (model loading can take time)

        healthCheckTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] timer in
            guard let self = self else { timer.invalidate(); return }
            attempts += 1

            if attempts > maxAttempts {
                timer.invalidate()
                DispatchQueue.main.async {
                    self.state = .error("伺服器啟動超時")
                }
                return
            }

            self.checkHealth()
        }
    }

    private func checkHealth() {
        guard let url = URL(string: "http://localhost:8899/api/languages") else { return }
        var request = URLRequest(url: url)
        request.timeoutInterval = 2

        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            guard let self = self else { return }
            if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 {
                DispatchQueue.main.async {
                    self.healthCheckTimer?.invalidate()
                    self.healthCheckTimer = nil
                    self.state = .running
                }
            }
        }.resume()
    }
}
