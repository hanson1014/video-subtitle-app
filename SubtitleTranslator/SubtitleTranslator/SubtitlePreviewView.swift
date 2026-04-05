import SwiftUI

struct SubtitlePreviewView: View {
    @EnvironmentObject var vm: TranslationViewModel
    @State private var selectedTab = 0

    private var hasContent: Bool {
        !vm.srtOriginal.isEmpty || !vm.srtTranslated.isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            VStack(alignment: .leading, spacing: 4) {
                Text("字幕預覽")
                    .font(.title)
                    .fontWeight(.bold)
                Text("檢視轉錄與翻譯結果")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 28)
            .padding(.top, 28)
            .padding(.bottom, 20)

            if hasContent {
                // Tab bar
                HStack(spacing: 0) {
                    TabButton(title: "原文字幕", isSelected: selectedTab == 0) {
                        selectedTab = 0
                    }
                    .disabled(vm.srtOriginal.isEmpty)

                    TabButton(title: "翻譯字幕", isSelected: selectedTab == 1) {
                        selectedTab = 1
                    }
                    .disabled(vm.srtTranslated.isEmpty)
                }
                .padding(.horizontal, 28)

                Divider()
                    .padding(.top, 8)

                // Content
                ScrollView {
                    Text(selectedTab == 0 ? vm.srtOriginal : vm.srtTranslated)
                        .font(.system(.body, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(20)
                }
                .background(.background)
            } else {
                Spacer()
                VStack(spacing: 14) {
                    Image(systemName: "doc.text")
                        .font(.system(size: 36))
                        .foregroundStyle(.tertiary)
                    Text("尚無字幕資料")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                    Text("處理影片後，字幕將顯示在此處")
                        .font(.subheadline)
                        .foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity)
                Spacer()
            }
        }
        .onChange(of: vm.srtTranslated) {
            if !vm.srtTranslated.isEmpty {
                selectedTab = 1
            }
        }
    }
}

struct TabButton: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(isSelected ? .semibold : .regular)
                    .foregroundStyle(isSelected ? .primary : .secondary)

                Rectangle()
                    .fill(isSelected ? Color.accentColor : .clear)
                    .frame(height: 2)
                    .clipShape(Capsule())
            }
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 12)
    }
}
