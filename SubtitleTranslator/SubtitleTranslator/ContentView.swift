import SwiftUI

struct ContentView: View {
    @EnvironmentObject var vm: TranslationViewModel

    var body: some View {
        NavigationSplitView {
            SidebarView()
        } detail: {
            DetailView()
        }
        .navigationSplitViewStyle(.balanced)
    }
}

// MARK: - Sidebar

struct SidebarView: View {
    @EnvironmentObject var vm: TranslationViewModel

    var body: some View {
        List(SidebarItem.allCases, selection: $vm.selectedSidebar) { item in
            Label {
                HStack {
                    Text(item.label)
                    Spacer()
                    sidebarBadge(for: item)
                }
            } icon: {
                Image(systemName: item.icon)
                    .foregroundStyle(badgeColor(for: item))
            }
            .tag(item)
        }
        .listStyle(.sidebar)
        .navigationSplitViewColumnWidth(min: 180, ideal: 210, max: 260)
        .safeAreaInset(edge: .bottom) {
            VStack(alignment: .leading, spacing: 2) {
                Text("全部本地運行")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text("Whisper + Qwen 模型")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private func sidebarBadge(for item: SidebarItem) -> some View {
        switch item {
        case .process:
            if vm.isProcessing {
                Text("處理中")
                    .font(.caption2)
                    .fontWeight(.medium)
                    .foregroundStyle(.blue)
            } else if vm.isComplete {
                Image(systemName: "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.green)
            }
        case .downloads:
            if !vm.downloads.isEmpty {
                Text("\(vm.downloads.count)")
                    .font(.caption2)
                    .fontWeight(.bold)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1)
                    .background(.blue, in: Capsule())
            }
        default:
            EmptyView()
        }
    }

    private func badgeColor(for item: SidebarItem) -> Color {
        switch item {
        case .process: return .blue
        case .preview: return .orange
        case .downloads: return .green
        }
    }
}

// MARK: - Detail Router

struct DetailView: View {
    @EnvironmentObject var vm: TranslationViewModel

    var body: some View {
        switch vm.selectedSidebar {
        case .process:
            ProcessView()
        case .preview:
            SubtitlePreviewView()
        case .downloads:
            DownloadsView()
        }
    }
}
