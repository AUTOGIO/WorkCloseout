import Foundation
import CryptoKit

public struct EvidenceCollector: Sendable {
    private static let maximumFiles = 500
    private static let maximumFileBytes = 64_000
    private static let maximumExcerptCharacters = 12_000
    private static let forbiddenExtensions: Set<String> = ["csv", "tsv", "xlsx", "xls", "numbers", "pdf", "doc", "docx", "key", "pem", "p12", "mobileprovision", "sqlite", "db"]
    private static let forbiddenNames = [".env", "secret", "credential", "token", "password", "wallet", "ledger", "bank", "financial"]
    private static let secretPatterns = ["sk-[A-Za-z0-9_-]{12,}", "AKIA[0-9A-Z]{16}", "gh[pousr]_[A-Za-z0-9_]{20,}", "github_pat_[A-Za-z0-9_]{20,}", "xox[baprs]-[A-Za-z0-9-]{10,}", "(?i)(api[_ -]?key|password|token|secret)\\s*[:=]\\s*[^\\s]+", "-----BEGIN [A-Z ]*PRIVATE KEY-----[\\s\\S]*?-----END [A-Z ]*PRIVATE KEY-----"]

    public init() {}

    public func collect(profile: ProjectProfile, sessionID: String, now: Date = Date()) throws -> EvidenceBundle {
        var items: [EvidenceItem] = []; var excluded = 0
        let extensions = Set(profile.allowedExtensions.map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased().trimmingCharacters(in: CharacterSet(charactersIn: ".")) })
        guard !extensions.isEmpty else { throw CloseoutError.invalidConfiguration("\(profile.id) has no usable allowedExtensions") }
        var roots: Set<String> = []
        for (rootIndex, rootText) in profile.allowedRoots.enumerated() {
            let root = try canonicalAllowedRoot(rootText)
            guard roots.insert(root.path).inserted else { throw CloseoutError.invalidConfiguration("duplicate allowed root: \(root.path)") }
            let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey, .contentModificationDateKey], options: [.skipsHiddenFiles, .skipsPackageDescendants])
            while let file = enumerator?.nextObject() as? URL {
                guard items.count < Self.maximumFiles else { throw CloseoutError.invalidConfiguration("evidence limit of \(Self.maximumFiles) files reached; narrow the allowlist") }
                guard try file.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true else { continue }
                let name = file.lastPathComponent.lowercased(); let extensionName = file.pathExtension.lowercased()
                guard extensions.contains(extensionName), !Self.forbiddenExtensions.contains(extensionName), !Self.forbiddenNames.contains(where: name.contains) else { excluded += 1; continue }
                guard let relative = relativePath(file, under: root) else { excluded += 1; continue }
                let raw = try Data(contentsOf: file, options: .mappedIfSafe)
                guard raw.count <= Self.maximumFileBytes, let text = String(data: raw, encoding: .utf8) else { excluded += 1; continue }
                let redacted = redact(String(text.prefix(Self.maximumExcerptCharacters)))
                let date = try file.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate ?? now
                items.append(EvidenceItem(sourceID: "\(profile.id):\(rootIndex):\(relative)", relativePath: relative, modifiedAt: date, excerpt: redacted, sha256: SHA256.hash(data: raw).compactMap { String(format: "%02x", $0) }.joined()))
            }
        }
        return EvidenceBundle(sessionID: sessionID, profileID: profile.id, createdAt: now, items: items.sorted { $0.relativePath < $1.relativePath }, excludedCount: excluded)
    }

    private func canonicalAllowedRoot(_ text: String) throws -> URL {
        let root = URL(fileURLWithPath: text).standardizedFileURL.resolvingSymlinksInPath()
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: root.path, isDirectory: &isDirectory), isDirectory.boolValue else { throw CloseoutError.unsafePath("Allowlisted root does not exist: \(text)") }
        return root
    }
    private func relativePath(_ file: URL, under root: URL) -> String? {
        let filePath = file.standardizedFileURL.resolvingSymlinksInPath().path; let rootPath = root.path.hasSuffix("/") ? root.path : root.path + "/"
        guard filePath.hasPrefix(rootPath) else { return nil }; return String(filePath.dropFirst(rootPath.count))
    }
    private func redact(_ input: String) -> String {
        Self.secretPatterns.reduce(input) { value, pattern in value.replacingOccurrences(of: pattern, with: "[REDACTED]", options: .regularExpression) }
    }
}
