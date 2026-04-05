import SwiftUI
import AppKit

struct DownloadsView: View {
    @EnvironmentObject var vm: TranslationViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Header
                VStack(alignment: .leading, spacing: 4) {
                    Text("下載檔案")
                        .font(.title)
                        .fontWeight(.bold)
                    Text("取得已處理的影片和字幕檔案")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                if vm.downloads.isEmpty {
                    // Empty state
                    VStack(spacing: 14) {
                        Spacer()
                            .frame(height: 40)
                        Image(systemName: "arrow.down.circle")
                            .font(.system(size: 36))
                            .foregroundStyle(.tertiary)
                        Text("尚無可下載檔案")
                            .font(.headline)
                            .foregroundStyle(.secondary)
                        Text("處理完成後，檔案將顯示在此處")
                            .font(.subheadline)
                            .foregroundStyle(.tertiary)
                        Spacer()
                    }
                    .frame(maxWidth: .infinity)
                } else {
                    LazyVGrid(columns: [
                        GridItem(.flexible(), spacing: 12),
                        GridItem(.flexible(), spacing: 12)
                    ], spacing: 12) {
                        ForEach(vm.downloads) { item in
                            DownloadCard(item: item)
                        }
                    }
                }
            }
            .padding(28)
        }
    }
}

struct DownloadCard: View {
    let item: DownloadItem
    @State private var isHovering = false
    @State private var isDownloading = false

    private var iconColor: Color {
        switch item.color {
        case "blue": return .blue
        case "orange": return .orange
        case "green": return .green
        case "purple": return .purple
        default: return .blue
        }
    }

    var body: some View {
        Button(action: downloadFile) {
            HStack(spacing: 14) {
                // Icon
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(iconColor.opacity(0.1))
                        .frame(width: 42, height: 42)
                    Image(systemName: item.icon)
                        .font(.title3)
                        .foregroundStyle(iconColor)
                }

                // Info
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.label)
                        .font(.callout)
                        .fontWeight(.semibold)
                        .foregroundStyle(.primary)
                    Text(item.sublabel)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                // Download icon
                if isDownloading {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Image(systemName: "arrow.down.to.line")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(.background)
                    .shadow(color: .black.opacity(isHovering ? 0.08 : 0.04), radius: isHovering ? 8 : 4, y: isHovering ? 2 : 1)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(isHovering ? iconColor.opacity(0.3) : Color.gray.opacity(0.15), lineWidth: 1)
            )
            .scaleEffect(isHovering ? 1.01 : 1.0)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.2)) {
                isHovering = hovering
            }
        }
    }

    private func downloadFile() {
        // Open save panel
        let panel = NSSavePanel()
        panel.nameFieldStringValue = suggestedFilename
        panel.canCreateDirectories = true
        panel.title = "儲存 \(item.label)"

        panel.begin { response in
            guard response == .OK, let saveURL = panel.url else { return }
            isDownloading = true

            URLSession.shared.downloadTask(with: item.url) { tempURL, _, error in
                DispatchQueue.main.async { isDownloading = false }
                guard let tempURL = tempURL, error == nil else { return }
                try? FileManager.default.moveItem(at: tempURL, to: saveURL)
            }.resume()
        }
    }

    private var suggestedFilename: String {
        switch item.key {
        case "video": return "subtitle_video.mp4"
        case "original_srt": return "original.srt"
        case "translated_srt": return "translated.srt"
        case "dual_srt": return "dual.srt"
        default: return "download"
        }
    }
}
