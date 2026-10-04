import Foundation
import Testing
@testable import FoodDecisionAssistant

struct BackupImportReaderTests {
    @Test("Import reads selected bytes without modifying the original file")
    func readsBytesWithoutWritingSource() throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appending(path: "backup.json")
        let source = Data("{\"test\":true}".utf8)
        try source.write(to: url)
        #expect(try BackupImportReader.read(from: url) == source)
        #expect(try Data(contentsOf: url) == source)
    }

    @Test("An oversized selected file is rejected before an unbounded read")
    func rejectsOversizedFile() throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appending(path: "oversized.json")
        try Data().write(to: url)
        let handle = try FileHandle(forWritingTo: url)
        try handle.truncate(atOffset: 64 * 1_024 * 1_024 + 1)
        try handle.close()
        #expect(throws: LocalStoreBackupError.backupTooLarge) {
            try BackupImportReader.read(from: url)
        }
        #expect(try url.resourceValues(forKeys: [.fileSizeKey]).fileSize == 64 * 1_024 * 1_024 + 1)
    }

    private func makeDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appending(path: "import-reader-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}
