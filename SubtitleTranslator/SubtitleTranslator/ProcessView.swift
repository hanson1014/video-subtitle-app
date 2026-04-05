import SwiftUI

struct ProcessView: View {
    @EnvironmentObject var vm: TranslationViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Header
                VStack(alignment: .leading, spacing: 4) {
                    Text("處理影片")
                        .font(.title)
                        .fontWeight(.bold)
                    Text("貼上影片網址，自動轉錄並翻譯字幕")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                // URL Input
                GroupBox {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("影片來源")
                            .font(.headline)
                            .fontWeight(.semibold)

                        HStack(spacing: 10) {
                            HStack(spacing: 8) {
                                Image(systemName: "link")
                                    .foregroundStyle(.tertiary)
                                    .font(.subheadline)
                                TextField("貼上影片網址（YouTube、Twitter 等）", text: $vm.videoURL)
                                    .textFieldStyle(.plain)
                                    .font(.body)
                                    .onSubmit { vm.startProcessing() }
                            }
                            .padding(8)
                            .background(.background, in: RoundedRectangle(cornerRadius: 8))
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .strokeBorder(.quaternary, lineWidth: 1)
                            )

                            Button(action: { vm.startProcessing() }) {
                                HStack(spacing: 5) {
                                    Image(systemName: "play.fill")
                                        .font(.caption)
                                    Text("開始處理")
                                        .fontWeight(.semibold)
                                }
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.large)
                            .disabled(vm.isProcessing || vm.videoURL.trimmingCharacters(in: .whitespaces).isEmpty)
                        }
                    }
                }

                // Options
                GroupBox {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("選項")
                            .font(.headline)
                            .fontWeight(.semibold)

                        HStack(spacing: 16) {
                            VStack(alignment: .leading, spacing: 5) {
                                Text("目標語言")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .fontWeight(.medium)
                                Picker("", selection: $vm.targetLanguage) {
                                    if vm.languages.isEmpty {
                                        Text("載入中…").tag("zh-TW")
                                    }
                                    ForEach(vm.languages) { lang in
                                        Text("\(lang.name) (\(lang.code))").tag(lang.code)
                                    }
                                }
                                .labelsHidden()
                                .frame(minWidth: 180)
                            }

                            VStack(alignment: .leading, spacing: 5) {
                                Text("Whisper 模型")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .fontWeight(.medium)
                                Picker("", selection: $vm.whisperModel) {
                                    Text("Tiny — 最快").tag("tiny")
                                    Text("Base").tag("base")
                                    Text("Small").tag("small")
                                    Text("Medium — 推薦").tag("medium")
                                    Text("Large V3 — 最準").tag("large-v3")
                                }
                                .labelsHidden()
                                .frame(minWidth: 180)
                            }

                            Spacer()
                        }
                    }
                }

                // Progress
                if vm.isProcessing || vm.isComplete || vm.errorMessage != nil {
                    GroupBox {
                        VStack(alignment: .leading, spacing: 14) {
                            HStack {
                                Text("處理進度")
                                    .font(.headline)
                                    .fontWeight(.semibold)
                                Spacer()
                                if vm.isProcessing {
                                    ProgressView()
                                        .controlSize(.small)
                                }
                            }

                            VStack(spacing: 2) {
                                ForEach(ProcessingStep.allCases) { step in
                                    StepRow(step: step, state: vm.steps[step] ?? StepState())
                                }
                            }

                            // Error
                            if let error = vm.errorMessage {
                                HStack(spacing: 10) {
                                    Image(systemName: "exclamationmark.triangle.fill")
                                        .foregroundStyle(.red)
                                    Text(error)
                                        .font(.callout)
                                        .foregroundStyle(.red)
                                }
                                .padding(12)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
                            }

                            // Completion
                            if vm.isComplete {
                                HStack(spacing: 12) {
                                    Image(systemName: "checkmark.circle.fill")
                                        .font(.title2)
                                        .foregroundStyle(.green)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("處理完成")
                                            .font(.callout)
                                            .fontWeight(.semibold)
                                        Text("字幕已成功轉錄並翻譯，可前往「下載檔案」取得結果")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Button("前往下載") {
                                        vm.selectedSidebar = .downloads
                                    }
                                    .buttonStyle(.bordered)
                                    .controlSize(.small)
                                }
                                .padding(12)
                                .background(.green.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
                                .transition(.move(edge: .bottom).combined(with: .opacity))
                            }
                        }
                    }
                    .animation(.spring(response: 0.4), value: vm.isComplete)
                }

                // Server Settings (collapsible)
                DisclosureGroup {
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("主機")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            TextField("localhost", text: $vm.serverHost)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 160)
                        }
                        VStack(alignment: .leading, spacing: 4) {
                            Text("埠號")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            TextField("8899", text: $vm.serverPort)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 80)
                        }
                        Spacer()
                    }
                    .padding(.top, 8)
                } label: {
                    Label("伺服器設定", systemImage: "server.rack")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(28)
        }
    }
}

// MARK: - Step Row

struct StepRow: View {
    let step: ProcessingStep
    let state: StepState

    var body: some View {
        HStack(spacing: 12) {
            // Indicator
            ZStack {
                Circle()
                    .fill(indicatorBackground)
                    .frame(width: 30, height: 30)

                switch state.status {
                case .waiting:
                    Text("\(step.index)")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(.tertiary)
                case .running:
                    ProgressView()
                        .controlSize(.small)
                        .tint(.white)
                case .done:
                    Image(systemName: "checkmark")
                        .font(.caption)
                        .fontWeight(.bold)
                        .foregroundStyle(.green)
                case .error:
                    Image(systemName: "xmark")
                        .font(.caption)
                        .fontWeight(.bold)
                        .foregroundStyle(.red)
                }
            }

            // Info
            VStack(alignment: .leading, spacing: 2) {
                Text(step.label)
                    .font(.callout)
                    .fontWeight(.medium)
                    .foregroundStyle(state.status == .waiting ? .tertiary : .primary)
                if !state.message.isEmpty {
                    Text(state.message)
                        .font(.caption)
                        .foregroundStyle(messageColor)
                        .lineLimit(1)
                }
            }

            Spacer()

            // Progress bar for translate step
            if let progress = state.progress, step == .translate {
                VStack(alignment: .trailing, spacing: 3) {
                    Text("\(Int(progress))%")
                        .font(.caption2)
                        .fontWeight(.medium)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                    ProgressView(value: progress, total: 100)
                        .frame(width: 100)
                        .tint(.blue)
                }
            }
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 10)
        .background(state.status == .running ? Color.blue.opacity(0.05) : .clear, in: RoundedRectangle(cornerRadius: 8))
        .animation(.easeInOut(duration: 0.3), value: state.status)
    }

    private var indicatorBackground: Color {
        switch state.status {
        case .waiting: return .gray.opacity(0.1)
        case .running: return .blue
        case .done: return .green.opacity(0.12)
        case .error: return .red.opacity(0.12)
        }
    }

    private var messageColor: Color {
        switch state.status {
        case .running: return .blue
        case .error: return .red
        default: return .secondary
        }
    }
}
