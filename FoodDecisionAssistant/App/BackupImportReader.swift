import Foundation

enum BackupImportReader {
    static func read(from url: URL) throws -> Data {
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard size <= 64 * 1_024 * 1_024 else { throw LocalStoreBackupError.backupTooLarge }
        // Do not rely on an earlier file size alone: a provider can change the file while reading.
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var data = Data()
        let limit = 64 * 1_024 * 1_024
        while let chunk = try handle.read(upToCount: min(1_024 * 1_024, limit + 1 - data.count)), !chunk.isEmpty {
            data.append(chunk)
            guard data.count <= limit else { throw LocalStoreBackupError.backupTooLarge }
        }
        return data
    }
}
