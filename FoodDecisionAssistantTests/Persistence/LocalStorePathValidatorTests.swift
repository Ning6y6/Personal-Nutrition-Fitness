import Darwin
import Foundation
import Testing

@testable import FoodDecisionAssistant

@MainActor
struct LocalStorePathValidatorTests {
    @Test("A device sandbox is checked from its trusted root, never from inaccessible outer ancestors")
    func checksOnlyTrustedRootAndDescendants() throws {
        let fixture = AttributesFixture()
        let target = fixture.root.appendingPathComponent("Library/Application Support/default.store")
        let validator = fixture.validator()

        #expect(throws: Never.self) { try validator.validate(target) }
        #expect(fixture.canonicalVisited == fixture.storePathSequence)
        #expect(fixture.visited.contains("/private") == false)
        #expect(fixture.visited.contains("/private/var") == false)
        #expect(fixture.visited.contains("/private/var/mobile") == false)
    }

    @Test("Permissions within the trusted root fail closed with a stable error", arguments: [EPERM, EACCES])
    func internalPermissionFailure(code: Int32) {
        let fixture = AttributesFixture()
        let blocked = fixture.root.appendingPathComponent("Library").path
        fixture.failures[blocked] = NSError(domain: NSPOSIXErrorDomain, code: Int(code))

        #expect(throws: LocalStoreBootstrapError.storePathUnreadable) {
            try fixture.validator().validate(fixture.storeURL)
        }
        #expect(fixture.canonicalVisited == Array(fixture.storePathSequence.prefix(2)))
    }

    @Test("A missing trusted root is never accepted as a new child path", arguments: MissingFailure.allCases)
    func missingTrustedRoot(failure: MissingFailure) {
        let fixture = AttributesFixture()
        fixture.types.removeValue(forKey: fixture.root.path)
        fixture.missingFailure = failure

        #expect(throws: LocalStoreBootstrapError.storePathUnreadable) {
            try fixture.validator().validate(fixture.storeURL)
        }
        #expect(fixture.canonicalVisited == [fixture.root.path])
    }

    @Test("Only the operating-system var and tmp aliases are equivalent in either direction", arguments: [
        ("/var/mobile/Containers/Data/Application/FIXTURE", "/private/var/mobile/Containers/Data/Application/FIXTURE"),
        ("/private/var/mobile/Containers/Data/Application/FIXTURE", "/var/mobile/Containers/Data/Application/FIXTURE"),
        ("/tmp/shiheng-fixture", "/private/tmp/shiheng-fixture"),
        ("/private/tmp/shiheng-fixture", "/tmp/shiheng-fixture"),
    ])
    func systemAliases(rootPath: String, candidateRootPath: String) throws {
        let fixture = AttributesFixture(rootPath: rootPath)
        let candidate = URL(fileURLWithPath: candidateRootPath, isDirectory: true)
            .appendingPathComponent("Library/Application Support/default.store")

        #expect(throws: Never.self) { try fixture.validator().validate(candidate) }
        #expect(fixture.canonicalVisited == fixture.storePathSequence)
        #expect(try fixture.validator().relativeComponents(for: candidate) == ["Library", "Application Support", "default.store"])
    }

    @Test("Symlinks at the trusted root, an inner ancestor, or the leaf are rejected", arguments: [
        "", "Library", "Library/Application Support/default.store",
    ])
    func symbolicLinkAtEveryPosition(relativePath: String) {
        let fixture = AttributesFixture()
        let blocked = fixture.path(relativePath)
        fixture.types[blocked] = .typeSymbolicLink

        #expect(throws: LocalStoreBootstrapError.unsafeStorePath) {
            try fixture.validator().validate(fixture.storeURL)
        }
        #expect(fixture.canonicalVisited.last == blocked)
    }

    @Test("Literal or percent-encoded dot components cannot be standardized into acceptance", arguments: [
        "Library/../default.store", "./default.store", "Library/%2E%2E/default.store", "Library/%2E/default.store",
    ])
    func dotComponents(relativePath: String) throws {
        let fixture = AttributesFixture()
        let candidate = try #require(URL(string: "file://\(fixture.root.path)/\(relativePath)"))

        #expect(throws: LocalStoreBootstrapError.unsafeStorePath) {
            try fixture.validator().validate(candidate)
        }
        #expect(fixture.visited.isEmpty)
    }

    @Test("A sibling whose name has the root prefix is still outside the trusted directory", arguments: [
        "/private/var/mobile/Containers/Data/Application/FIXTURE-other/default.store",
        "/private/var/mobile/Containers/Data/Application/OTHER/default.store",
        "/var/mobile/Containers/Data/Application/FIXTURE2/default.store",
    ])
    func outsideDirectory(candidatePath: String) {
        let fixture = AttributesFixture()

        #expect(throws: LocalStoreBootstrapError.unsafeStorePath) {
            try fixture.validator().validate(URL(fileURLWithPath: candidatePath))
        }
        #expect(fixture.visited.isEmpty)
    }

    @Test("Missing inner directories and leaf are allowed under an existing trusted root", arguments: MissingFailure.allCases)
    func missingChildrenAreAllowed(failure: MissingFailure) {
        let fixture = AttributesFixture()
        fixture.types = [fixture.root.path: .typeDirectory]
        fixture.missingFailure = failure

        #expect(throws: Never.self) { try fixture.validator().validate(fixture.storeURL) }
        #expect(fixture.canonicalVisited == fixture.storePathSequence)
    }

    @Test("A regular file is not a directory at the root or an inner ancestor", arguments: [
        "", "Library", "Library/Application Support",
    ])
    func regularFileAncestor(relativePath: String) {
        let fixture = AttributesFixture()
        let blocked = fixture.path(relativePath)
        fixture.types[blocked] = .typeRegular

        #expect(throws: LocalStoreBootstrapError.unsafeStorePath) {
            try fixture.validator().validate(fixture.storeURL)
        }
        #expect(fixture.canonicalVisited.last == blocked)
    }

    @Test("An attribute response without a file type is unreadable, not safe or missing", arguments: [
        "", "Library", "Library/Application Support/default.store",
    ])
    func missingTypeAttribute(relativePath: String) {
        let fixture = AttributesFixture()
        let blocked = fixture.path(relativePath)
        fixture.typeOmitted.insert(blocked)

        #expect(throws: LocalStoreBootstrapError.storePathUnreadable) {
            try fixture.validator().validate(fixture.storeURL)
        }
        #expect(fixture.canonicalVisited.last == blocked)
    }

    @Test("Non-file or remote file candidates are rejected before attribute access", arguments: [
        "https://example.invalid/default.store",
        "file://remote.invalid/private/var/mobile/Containers/Data/Application/FIXTURE/default.store",
        "file:///private/var/mobile/Containers/Data/Application/FIXTURE/default.store?ignored=1",
        "file:///private/var/mobile/Containers/Data/Application/FIXTURE/default.store#ignored",
    ])
    func invalidCandidateURL(text: String) throws {
        let fixture = AttributesFixture()
        let candidate = try #require(URL(string: text))

        #expect(throws: LocalStoreBootstrapError.invalidConfiguration) {
            try fixture.validator().validate(candidate)
        }
        #expect(fixture.visited.isEmpty)
    }

    @Test("A filesystem-wide or traversal-containing trusted boundary is not a valid configuration", arguments: [
        "/", "/private/var/mobile/../FIXTURE", "/private/var/./FIXTURE",
    ])
    func invalidTrustedPath(path: String) throws {
        let fixture = AttributesFixture()
        let invalidRoot = try #require(URL(string: "file://\(path)"))
        let validator = LocalStorePathValidator(trustedDirectory: invalidRoot, attributes: fixture.attributes)

        #expect(throws: LocalStoreBootstrapError.invalidConfiguration) {
            try validator.validate(fixture.storeURL)
        }
        #expect(fixture.visited.isEmpty)
    }

    @Test("The trusted boundary itself must be a local file directory URL", arguments: [
        "https://example.invalid/root",
        "file://remote.invalid/private/var/mobile/Containers/Data/Application/FIXTURE",
    ])
    func invalidTrustedURL(text: String) throws {
        let fixture = AttributesFixture()
        let invalidRoot = try #require(URL(string: text))
        let validator = LocalStorePathValidator(trustedDirectory: invalidRoot, attributes: fixture.attributes)

        #expect(throws: LocalStoreBootstrapError.invalidConfiguration) {
            try validator.validate(fixture.storeURL)
        }
        #expect(fixture.visited.isEmpty)
    }

    @Test("Raw permission errors and simulated private paths do not leak into user-facing diagnostics")
    func permissionErrorDescriptionIsSanitized() {
        let fixture = AttributesFixture()
        let privatePath = "/private/var/mobile/Containers/Data/Application/PRIVATE-FIXTURE/secret.store"
        let rawDescription = "EPERM at \(privatePath); private-diagnostic-token"
        fixture.failures[fixture.root.appendingPathComponent("Library").path] = NSError(
            domain: NSPOSIXErrorDomain,
            code: Int(EPERM),
            userInfo: [NSLocalizedDescriptionKey: rawDescription, NSFilePathErrorKey: privatePath]
        )

        do {
            try fixture.validator().validate(fixture.storeURL)
            Issue.record("Expected the inaccessible child to fail closed.")
        } catch {
            #expect(error as? LocalStoreBootstrapError == .storePathUnreadable)
            #expect(error.localizedDescription.contains(privatePath) == false)
            #expect(error.localizedDescription.contains("private-diagnostic-token") == false)
            #expect(error.localizedDescription.contains("EPERM") == false)
        }
    }

    @Test("Validating the trusted root checks that root exactly once")
    func rootDirectoryItself() {
        let fixture = AttributesFixture()

        #expect(throws: Never.self) { try fixture.validator().validate(fixture.root) }
        #expect(fixture.canonicalVisited == [fixture.root.path])
    }

    enum MissingFailure: CaseIterable, Sendable {
        case cocoa, posix

        var error: NSError {
            switch self {
            case .cocoa: NSError(domain: NSCocoaErrorDomain, code: CocoaError.fileReadNoSuchFile.rawValue)
            case .posix: NSError(domain: NSPOSIXErrorDomain, code: Int(ENOENT))
            }
        }
    }

    /// No real filesystem access is used: attributes outside this simulated sandbox always fail.
    @MainActor
    private final class AttributesFixture {
        let root: URL
        var types: [String: FileAttributeType]
        var failures: [String: NSError] = [:]
        var typeOmitted: Set<String> = []
        var missingFailure = MissingFailure.cocoa
        private(set) var visited: [String] = []

        init(rootPath: String = "/private/var/mobile/Containers/Data/Application/FIXTURE") {
            let canonicalRoot = URL(fileURLWithPath: Self.canonicalPath(rootPath), isDirectory: true)
            root = canonicalRoot
            types = [
                canonicalRoot.path: .typeDirectory,
                canonicalRoot.appendingPathComponent("Library").path: .typeDirectory,
                canonicalRoot.appendingPathComponent("Library/Application Support").path: .typeDirectory,
                canonicalRoot.appendingPathComponent("Library/Application Support/default.store").path: .typeRegular,
            ]
            originalRoot = URL(fileURLWithPath: rootPath, isDirectory: true)
        }

        private let originalRoot: URL

        var storeURL: URL {
            root.appendingPathComponent("Library/Application Support/default.store")
        }

        var storePathSequence: [String] {
            [root.path, path("Library"), path("Library/Application Support"), storeURL.path]
        }

        var canonicalVisited: [String] {
            visited.map(Self.canonicalPath)
        }

        func path(_ relativePath: String) -> String {
            relativePath.isEmpty ? root.path : root.appendingPathComponent(relativePath).path
        }

        func validator() -> LocalStorePathValidator {
            LocalStorePathValidator(trustedDirectory: originalRoot, attributes: attributes)
        }

        func attributes(_ path: String) throws -> [FileAttributeKey: Any] {
            visited.append(path)
            let canonical = Self.canonicalPath(path)
            guard canonical == root.path || canonical.hasPrefix(root.path + "/") else {
                throw NSError(domain: NSPOSIXErrorDomain, code: Int(EPERM))
            }
            if let failure = failures[canonical] { throw failure }
            guard let type = types[canonical] else { throw missingFailure.error }
            if typeOmitted.contains(canonical) { return [:] }
            return [.type: type]
        }

        private static func canonicalPath(_ path: String) -> String {
            if path == "/var" || path.hasPrefix("/var/") { return "/private" + path }
            if path == "/tmp" || path.hasPrefix("/tmp/") { return "/private" + path }
            return path
        }
    }
}
