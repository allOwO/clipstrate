import Foundation

struct IgnoredApplication: Codable, Equatable, Identifiable, Sendable {
    let bundleIdentifier: String
    let displayName: String

    var id: String { bundleIdentifier }

    init?(bundleIdentifier: String, displayName: String) {
        let identifier = Self.canonicalIdentifier(bundleIdentifier)
        guard !identifier.isEmpty else { return nil }
        let name = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        self.bundleIdentifier = identifier
        self.displayName = name.isEmpty ? identifier : name
    }

    static func canonicalIdentifier(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}

/// 01 §7.3 忽略名单的本地持久层。独立 JSON 便于 M4 只备份小体积设置数据，
/// 文件 I/O 全在 actor 上执行；采集侧按来源 bundle id 查询。
actor IgnoreListStore {
    private struct Document: Codable {
        static let currentVersion = 1
        var version: Int
        var applications: [IgnoredApplication]
    }

    enum StoreError: Error, Equatable {
        case unsupportedVersion(Int)
    }

    private let fileURL: URL
    private let encoder: JSONEncoder
    private let decoder = JSONDecoder()

    init(fileURL: URL) {
        self.fileURL = fileURL
        encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    }

    nonisolated static func makeDefault() -> IgnoreListStore {
        let base = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
            .appendingPathComponent("Library/Application Support", isDirectory: true)
        return IgnoreListStore(
            fileURL: base
                .appendingPathComponent(AppPaths.appFolderName, isDirectory: true)
                .appendingPathComponent("ignore-list.json", isDirectory: false)
        )
    }

    func applications() throws -> [IgnoredApplication] {
        try readDocument().applications.sorted(by: Self.sortApplications)
    }

    func contains(bundleIdentifier: String?) throws -> Bool {
        guard let bundleIdentifier else { return false }
        let identifier = IgnoredApplication.canonicalIdentifier(bundleIdentifier)
        guard !identifier.isEmpty else { return false }
        return try readDocument().applications.contains { $0.bundleIdentifier == identifier }
    }

    func exportData() throws -> Data {
        try encoder.encode(readDocument())
    }

    /// 备份恢复语义为覆盖。先完整解码和校验版本，再原子写入，避免坏文件
    /// 清空现有忽略名单。
    func replace(with data: Data) throws {
        var document = try decoder.decode(Document.self, from: data)
        guard document.version == Document.currentVersion else {
            throw StoreError.unsupportedVersion(document.version)
        }
        document.applications = Dictionary(
            document.applications.map { ($0.bundleIdentifier, $0) },
            uniquingKeysWith: { _, latest in latest }
        ).values.sorted(by: Self.sortApplications)
        try write(document)
    }

    /// 同 bundle id 去重；再次添加会刷新显示名。
    @discardableResult
    func add(_ application: IgnoredApplication) throws -> Bool {
        var document = try readDocument()
        if let index = document.applications.firstIndex(where: {
            $0.bundleIdentifier == application.bundleIdentifier
        }) {
            guard document.applications[index] != application else { return false }
            document.applications[index] = application
        } else {
            document.applications.append(application)
        }
        document.applications.sort(by: Self.sortApplications)
        try write(document)
        return true
    }

    @discardableResult
    func remove(bundleIdentifier: String) throws -> Bool {
        let identifier = IgnoredApplication.canonicalIdentifier(bundleIdentifier)
        var document = try readDocument()
        let oldCount = document.applications.count
        document.applications.removeAll { $0.bundleIdentifier == identifier }
        guard document.applications.count != oldCount else { return false }
        try write(document)
        return true
    }

    private func readDocument() throws -> Document {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return Document(version: Document.currentVersion, applications: [])
        }
        let document = try decoder.decode(Document.self, from: Data(contentsOf: fileURL))
        guard document.version == Document.currentVersion else {
            throw StoreError.unsupportedVersion(document.version)
        }
        return document
    }

    private func write(_ document: Document) throws {
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try encoder.encode(document).write(to: fileURL, options: .atomic)
    }

    private nonisolated static func sortApplications(
        _ lhs: IgnoredApplication,
        _ rhs: IgnoredApplication
    ) -> Bool {
        let nameOrder = lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName)
        if nameOrder == .orderedSame {
            return lhs.bundleIdentifier < rhs.bundleIdentifier
        }
        return nameOrder == .orderedAscending
    }
}
