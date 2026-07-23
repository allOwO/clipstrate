import Foundation

actor BackupService {
    private let historyStore: HistoryStore
    private let blobStore: BlobStore
    private let ignoreListStore: IgnoreListStore
    private let archiveCodec: BackupArchiveCodec
    private let fileManager: FileManager

    init(
        historyStore: HistoryStore,
        blobStore: BlobStore,
        ignoreListStore: IgnoreListStore,
        archiveCodec: BackupArchiveCodec = BackupArchiveCodec(),
        fileManager: FileManager = .default
    ) {
        self.historyStore = historyStore
        self.blobStore = blobStore
        self.ignoreListStore = ignoreListStore
        self.archiveCodec = archiveCodec
        self.fileManager = fileManager
    }

    @discardableResult
    func exportArchive(
        to destination: URL,
        selection: BackupSelection
    ) async throws -> BackupManifest {
        guard !selection.isEmpty else { throw BackupError.emptySelection }
        let temporaryRoot = try makeTemporaryDirectory()
        defer { try? fileManager.removeItem(at: temporaryRoot) }
        let package = temporaryRoot.appendingPathComponent("package", isDirectory: true)
        try fileManager.createDirectory(at: package, withIntermediateDirectories: true)

        if selection.settings {
            let document = Settings.makeBackupDocument()
            try Self.encoder.encode(document).write(
                to: package.appendingPathComponent("settings.json"),
                options: .atomic
            )
        }
        if selection.ignoreList {
            try await ignoreListStore.exportData().write(
                to: package.appendingPathComponent("ignore.json"),
                options: .atomic
            )
        }
        if selection.history {
            try await historyStore.createSnapshot(
                at: package.appendingPathComponent("history.sqlite")
            )
            try copyDirectory(
                from: blobStore.locations.blobs,
                to: package.appendingPathComponent("blobs", isDirectory: true)
            )
            try copyDirectory(
                from: blobStore.locations.thumbs,
                to: package.appendingPathComponent("thumbs", isDirectory: true)
            )
        }

        let manifest = BackupManifest(
            formatVersion: BackupManifest.currentFormatVersion,
            appVersion: Bundle.main.shortVersion,
            createdAt: Date(),
            deviceName: Host.current().localizedName ?? "Mac",
            contents: selection
        )
        try Self.encoder.encode(manifest).write(
            to: package.appendingPathComponent("manifest.json"),
            options: .atomic
        )
        try archiveCodec.createArchive(from: package, at: destination)
        return manifest
    }

    func importArchive(from source: URL) async throws -> BackupImportResult {
        let temporaryRoot = try makeTemporaryDirectory()
        defer { try? fileManager.removeItem(at: temporaryRoot) }
        let package = temporaryRoot.appendingPathComponent("package", isDirectory: true)
        try archiveCodec.extractArchive(at: source, to: package)

        let manifestURL = package.appendingPathComponent("manifest.json")
        guard fileManager.fileExists(atPath: manifestURL.path) else {
            throw BackupError.invalidArchive
        }
        let manifest = try Self.decoder.decode(
            BackupManifest.self,
            from: Data(contentsOf: manifestURL)
        )
        guard manifest.formatVersion == BackupManifest.currentFormatVersion else {
            throw BackupError.unsupportedFormat(manifest.formatVersion)
        }

        let database = package.appendingPathComponent("history.sqlite")
        let ignoreURL = package.appendingPathComponent("ignore.json")
        let settingsURL = package.appendingPathComponent("settings.json")
        try requireComponent(database, named: "history.sqlite", when: manifest.contents.history)
        try requireComponent(ignoreURL, named: "ignore.json", when: manifest.contents.ignoreList)
        try requireComponent(settingsURL, named: "settings.json", when: manifest.contents.settings)

        let settingsDocument: SettingsBackupDocument?
        if manifest.contents.settings {
            settingsDocument = try Self.decoder.decode(
                SettingsBackupDocument.self,
                from: Data(contentsOf: settingsURL)
            )
        } else {
            settingsDocument = nil
        }
        let ignoreData = manifest.contents.ignoreList ? try Data(contentsOf: ignoreURL) : nil

        var result = BackupImportResult()
        if manifest.contents.history {
            try mergeDirectory(
                from: package.appendingPathComponent("blobs", isDirectory: true),
                to: blobStore.locations.blobs
            )
            try mergeDirectory(
                from: package.appendingPathComponent("thumbs", isDirectory: true),
                to: blobStore.locations.thumbs
            )
            result.history = try await historyStore.mergeSnapshot(at: database)
        }
        if let ignoreData {
            try await ignoreListStore.replace(with: ignoreData)
            result.restoredIgnoreList = true
        }
        if let document = settingsDocument {
            try Settings.restore(from: document)
            result.restoredSettings = true
            result.requestedLaunchAtLogin = document.requestedLaunchAtLogin
        }
        return result
    }

    private func requireComponent(_ url: URL, named name: String, when required: Bool) throws {
        guard required else { return }
        guard fileManager.fileExists(atPath: url.path),
              let values = try? url.resourceValues(
                  forKeys: [.isRegularFileKey, .isSymbolicLinkKey]
              ),
              values.isRegularFile == true,
              values.isSymbolicLink != true else {
            throw BackupError.missingComponent(name)
        }
    }

    private func makeTemporaryDirectory() throws -> URL {
        let directory = fileManager.temporaryDirectory
            .appendingPathComponent("ClipstrateBackup-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func copyDirectory(from source: URL, to destination: URL) throws {
        guard fileManager.fileExists(atPath: source.path) else {
            try fileManager.createDirectory(at: destination, withIntermediateDirectories: true)
            return
        }
        try fileManager.copyItem(at: source, to: destination)
    }

    private func mergeDirectory(from source: URL, to destination: URL) throws {
        guard fileManager.fileExists(atPath: source.path) else { return }
        try fileManager.createDirectory(at: destination, withIntermediateDirectories: true)
        for entry in try fileManager.contentsOfDirectory(
            at: source,
            includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey],
            options: [.skipsHiddenFiles]
        ) {
            let values = try entry.resourceValues(
                forKeys: [.isRegularFileKey, .isSymbolicLinkKey]
            )
            guard values.isRegularFile == true, values.isSymbolicLink != true else { continue }
            let target = destination.appendingPathComponent(entry.lastPathComponent)
            if !fileManager.fileExists(atPath: target.path) {
                try fileManager.copyItem(at: entry, to: target)
            }
        }
    }

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }()

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}
