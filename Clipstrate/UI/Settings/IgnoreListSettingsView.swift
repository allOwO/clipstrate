import AppKit
import SwiftUI
import UniformTypeIdentifiers

@MainActor
struct IgnoreListSettingsView: View {
    let store: IgnoreListStore

    @State private var applications: [IgnoredApplication] = []
    @State private var isWorking = false
    @State private var errorMessage: String?

    var body: some View {
        Group {
            SettingsGroupTitle(title: "忽略名单")
            SettingsGroup {
                if applications.isEmpty {
                    HStack {
                        Text("暂无 App")
                            .foregroundStyle(DS.Colors.secondaryText)
                        Spacer()
                    }
                    .font(.system(size: 13))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 11)
                } else {
                    ForEach(Array(applications.enumerated()), id: \.element.id) { index, application in
                        if index > 0 { SettingsDivider() }
                        applicationRow(application)
                    }
                }
                SettingsDivider()
                HStack {
                    Button("添加 App…", action: chooseApplication)
                        .controlSize(.small)
                        .disabled(isWorking)
                    if isWorking { ProgressView().controlSize(.small) }
                    Spacer()
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
            }
            SettingsNote(text: "名单内 App 的新复制内容不会进入历史记录。")
            if let errorMessage {
                SettingsNote(text: "忽略名单更新失败：\(errorMessage)")
                    .foregroundStyle(.red)
            }
        }
        .task { await reload() }
    }

    private func applicationRow(_ application: IgnoredApplication) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "app.fill")
                .foregroundStyle(DS.Colors.secondaryText)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 2) {
                Text(application.displayName).font(.system(size: 13))
                Text(application.bundleIdentifier)
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }
            Spacer(minLength: 12)
            Button {
                mutate { try await store.remove(bundleIdentifier: application.bundleIdentifier) }
            } label: {
                Image(systemName: "minus.circle.fill")
                    .foregroundStyle(.red)
            }
            .buttonStyle(.plain)
            .help("从忽略名单移除")
            .disabled(isWorking)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }

    private func chooseApplication() {
        let panel = NSOpenPanel()
        panel.title = "选择要忽略的 App"
        panel.prompt = "添加"
        panel.allowedContentTypes = [.applicationBundle]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        guard panel.runModal() == .OK,
              let url = panel.url,
              let bundle = Bundle(url: url),
              let bundleIdentifier = bundle.bundleIdentifier,
              let application = IgnoredApplication(
                  bundleIdentifier: bundleIdentifier,
                  displayName: applicationName(bundle: bundle, url: url)
              ) else { return }

        mutate { try await store.add(application) }
    }

    private func applicationName(bundle: Bundle, url: URL) -> String {
        (bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
            ?? (bundle.object(forInfoDictionaryKey: "CFBundleName") as? String)
            ?? url.deletingPathExtension().lastPathComponent
    }

    private func mutate(_ operation: @escaping () async throws -> Bool) {
        guard !isWorking else { return }
        isWorking = true
        Task {
            do {
                _ = try await operation()
                await reload()
            } catch {
                errorMessage = error.localizedDescription
            }
            isWorking = false
        }
    }

    private func reload() async {
        do {
            applications = try await store.applications()
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
