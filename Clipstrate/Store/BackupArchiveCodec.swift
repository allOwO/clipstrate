import Foundation

/// 使用 macOS 自带的 ditto 读写 ZIP；不引入压缩依赖，也不增加 App 包体。
struct BackupArchiveCodec: Sendable {
    func createArchive(from directory: URL, at destination: URL) throws {
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: destination.path) {
            try fileManager.removeItem(at: destination)
        }
        try run([
            "-c", "-k", "--norsrc",
            directory.path,
            destination.path,
        ])
    }

    func extractArchive(at archive: URL, to directory: URL) throws {
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        try run(["-x", "-k", archive.path, directory.path])
    }

    private func run(_ arguments: [String]) throws {
        let process = Process()
        let errorPipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = errorPipe
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            throw BackupError.archiveToolFailed(error.localizedDescription)
        }
        guard process.terminationStatus == 0 else {
            let data = errorPipe.fileHandleForReading.readDataToEndOfFile()
            let message = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            throw BackupError.archiveToolFailed(
                message.flatMap { $0.isEmpty ? nil : $0 }
                    ?? "ditto 退出码 \(process.terminationStatus)"
            )
        }
    }
}
