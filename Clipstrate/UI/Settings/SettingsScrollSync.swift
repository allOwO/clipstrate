import Foundation

struct SettingsScrollSyncState: Equatable, Sendable {
    let section: SettingsSection
    let pendingTarget: SettingsSection?
}

extension SettingsScrollSpy {
    /// 程序化跳转期间，offset preference 可能先短暂上报旧分区。
    /// 在目标分区被实际观测到之前始终保持目标选中，避免侧栏高亮闪回。
    nonisolated static func synchronize(
        programmaticTarget: SettingsSection?,
        observed: SettingsSection
    ) -> SettingsScrollSyncState {
        guard let programmaticTarget else {
            return SettingsScrollSyncState(section: observed, pendingTarget: nil)
        }
        return SettingsScrollSyncState(
            section: programmaticTarget,
            pendingTarget: observed == programmaticTarget ? nil : programmaticTarget
        )
    }
}
