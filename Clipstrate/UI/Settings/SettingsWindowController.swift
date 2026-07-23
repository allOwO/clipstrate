import AppKit
import SwiftUI

@MainActor
final class SettingsWindowController: NSObject, NSWindowDelegate {
    private let window: NSWindow

    init(
        actions: SettingsActions = SettingsActions(),
        loginItemManager: any LoginItemManaging = SystemLoginItemManager(),
        ignoreListStore: IgnoreListStore = IgnoreListStore.makeDefault()
    ) {
        window = NSWindow(
            contentRect: NSRect(origin: .zero, size: SettingsCatalog.defaultWindowSize),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        super.init()

        window.title = SettingsSection.general.title
        window.minSize = CGSize(width: 680, height: 480)
        window.isReleasedWhenClosed = false
        window.center()
        _ = window.setFrameUsingName("Clipstrate.SettingsWindow")
        _ = window.setFrameAutosaveName("Clipstrate.SettingsWindow")
        window.delegate = self
        window.contentView = NSHostingView(
            rootView: SettingsView(
                actions: actions,
                loginItemManager: loginItemManager,
                ignoreListStore: ignoreListStore,
                onSectionChange: { [weak self] section in
                    self?.window.title = section.title
                }
            )
        )
    }

    func show() {
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    func close() {
        window.orderOut(nil)
    }
}
