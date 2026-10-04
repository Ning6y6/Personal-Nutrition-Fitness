import Darwin
import Foundation

/// The OS-provided data-container boundary is trusted, not its filesystem ancestors.
/// Test fixtures must explicitly supply their own isolated boundary. Never resolve an entire
/// candidate path: that would hide a user-controlled symbolic link before it can be rejected.
@MainActor
struct LocalStorePathValidator {
    private let trustedDirectory: URL
    private let attributes: (String) throws -> [FileAttributeKey: Any]

    init(
        trustedDirectory: URL = URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true),
        attributes: @escaping (String) throws -> [FileAttributeKey: Any] = {
            try FileManager.default.attributesOfItem(atPath: $0)
        }
    ) {
        self.trustedDirectory = trustedDirectory
        self.attributes = attributes
    }

    func validate(_ url: URL) throws {
        let descendants = try relativeComponents(for: url)
        var checkedComponents = normalizeSystemPrefix(trustedDirectory.pathComponents)
        for depth in 0...descendants.count {
            if depth > 0 { checkedComponents.append(descendants[depth - 1]) }
            let path = NSString.path(withComponents: checkedComponents)
            let values: [FileAttributeKey: Any]
            do {
                values = try attributes(path)
            } catch {
                // A new child can be absent on first installation, but never silently accept a
                // missing boundary or a permission failure as evidence of a safe path.
                if depth > 0, isMissingFile(error) { continue }
                throw LocalStoreBootstrapError.storePathUnreadable
            }
            guard let type = values[.type] as? FileAttributeType else {
                throw LocalStoreBootstrapError.storePathUnreadable
            }
            guard type != .typeSymbolicLink,
                  (depth == descendants.count && depth > 0) || type == .typeDirectory else {
                throw LocalStoreBootstrapError.unsafeStorePath
            }
        }
    }

    /// Lexical containment also lets fixed restore layouts compare the same relative path when
    /// Foundation supplies either spelling of an OS-owned container prefix.
    func relativeComponents(for url: URL) throws -> [String] {
        guard isLocalFileURL(trustedDirectory), isLocalFileURL(url) else {
            throw LocalStoreBootstrapError.invalidConfiguration
        }
        let root = trustedDirectory.pathComponents
        let candidate = url.pathComponents
        guard root.count > 1, root.first == "/", !hasTraversal(root) else {
            throw LocalStoreBootstrapError.invalidConfiguration
        }
        guard candidate.first == "/", !hasTraversal(candidate) else {
            throw LocalStoreBootstrapError.unsafeStorePath
        }
        // These are OS-owned prefix aliases, not links chosen inside the app container. Lexical
        // normalization needs no metadata access to /, /private, /var or other external ancestors.
        let normalizedRoot = normalizeSystemPrefix(root)
        let normalizedCandidate = normalizeSystemPrefix(candidate)
        guard normalizedCandidate.starts(with: normalizedRoot) else {
            throw LocalStoreBootstrapError.unsafeStorePath
        }

        return Array(normalizedCandidate.dropFirst(normalizedRoot.count))
    }

    private func isLocalFileURL(_ url: URL) -> Bool {
        url.isFileURL && (url.host == nil || url.host == "" || url.host == "localhost")
            && url.query == nil && url.fragment == nil
    }

    private func hasTraversal(_ components: [String]) -> Bool {
        components.contains(".") || components.contains("..")
    }

    private func normalizeSystemPrefix(_ components: [String]) -> [String] {
        guard components.count > 1, components[0] == "/",
              components[1] == "var" || components[1] == "tmp" else { return components }
        return ["/", "private"] + components.dropFirst()
    }

    private func isMissingFile(_ error: any Error) -> Bool {
        let error = error as NSError
        if error.domain == NSCocoaErrorDomain {
            return error.code == NSFileReadNoSuchFileError || error.code == NSFileNoSuchFileError
        }
        return error.domain == NSPOSIXErrorDomain && error.code == Int(ENOENT)
    }
}
