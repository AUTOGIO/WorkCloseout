import Foundation

public protocol CloudDraftingProvider: Sendable {
    var provider: CloudProvider { get }
    func draft(preview: EvidenceBundle, approvedForTransmission: Bool) async throws -> CloseoutDraft
}

/// The production boundary intentionally has no network implementation. Integrations must retrieve a key from Keychain and require a fresh, user-visible approval.
public struct DisabledCloudProvider: CloudDraftingProvider {
    public let provider: CloudProvider = .disabled
    public init() {}
    public func draft(preview: EvidenceBundle, approvedForTransmission: Bool) async throws -> CloseoutDraft { TemplateDraftingProvider().draft(bundle: preview) }
}

public struct TemplateDraftingProvider: Sendable {
    public init() {}
    public func draft(bundle: EvidenceBundle) -> CloseoutDraft {
        let fileNames = bundle.items.map(\.relativePath)
        var accomplishments = fileNames.isEmpty ? ["No approved evidence files were found."] : fileNames.map { "Reviewed approved evidence: \($0)" }
        var pending = ["Review this closeout before recording it."]
        var blockers: [String] = []
        var repositorySummary = ""
        if let repository = bundle.repository {
            if let branch = repository.branch { accomplishments.append("Repository branch at preparation: \(branch)"); repositorySummary += " Git branch: \(branch)." }
            if let commit = repository.latestCommit { accomplishments.append("Latest local commit: \(commit)"); repositorySummary += " Latest local commit: \(commit)." }
            if repository.changes.isEmpty { accomplishments.append("Working tree was clean at preparation.") }
            else { pending.append(contentsOf: repository.changes.map { "Uncommitted change: \($0)" }) }
            for result in repository.verificationResults {
                if result.exitCode == 0 { accomplishments.append("Verification passed: \(result.command)") }
                else if result.exitCode == 124 { blockers.append("Verification timed out: \(result.command). Inspect the local evidence bundle for its output.") }
                else { blockers.append("Verification failed (exit \(result.exitCode)): \(result.command). Inspect the local evidence bundle for its output.") }
            }
        }
        return CloseoutDraft(title: "Closeout — \(bundle.profileID)", summary: "Prepared from \(bundle.items.count) approved local text file(s); no cloud provider received data.\(repositorySummary)", accomplishments: accomplishments, pending: pending, blockers: blockers, nextSteps: ["Record this reviewed closeout only with explicit approval.", "Review the generated evidence bundle before expanding its scope."], sourceIDs: bundle.items.map(\.sourceID))
    }
}

public enum DraftValidator {
    public static func validate(_ draft: CloseoutDraft, against bundle: EvidenceBundle) throws {
        guard !draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, !draft.summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw CloseoutError.invalidDraft("title and summary are required") }
        let known = Set(bundle.items.map(\.sourceID)); let unknown = draft.sourceIDs.filter { !known.contains($0) }
        guard unknown.isEmpty else { throw CloseoutError.invalidDraft("unknown evidence identifiers: \(unknown.joined(separator: ", "))") }
    }
}
