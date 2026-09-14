import Foundation

public enum CloudProvider: String, Codable, CaseIterable, Sendable { case disabled, openAI, anthropic, gemini }

public struct AppConfiguration: Codable, Sendable {
    public var artifactDirectory: String
    public var projects: [ProjectProfile]
    /// Existing Obsidian project-note directory used as the local registry.
    public var obsidianProjectsDirectory: String?
    public init(artifactDirectory: String = "artifacts", projects: [ProjectProfile], obsidianProjectsDirectory: String? = nil) {
        self.artifactDirectory = artifactDirectory; self.projects = projects; self.obsidianProjectsDirectory = obsidianProjectsDirectory
    }
}

public struct ProjectProfile: Codable, Identifiable, Sendable {
    public var id: String
    public var displayName: String
    public var allowedRoots: [String]
    public var allowedExtensions: [String]
    public var provider: CloudProvider
    public var obsidian: ObsidianTarget?
    /// A filename in `AppConfiguration.obsidianProjectsDirectory`, resolved only to an existing note.
    public var obsidianProjectNote: String?
    public var reportDirectory: String?
    /// Optional local Git repository used only for repository state inspection.
    public var repositoryRoot: String?
    /// Explicit local verification commands, run from `repositoryRoot` during preparation.
    public var verificationCommands: [String]
    public init(id: String, displayName: String, allowedRoots: [String], allowedExtensions: [String] = ["md", "txt", "swift", "py", "js", "ts"], provider: CloudProvider = .disabled, obsidian: ObsidianTarget? = nil, obsidianProjectNote: String? = nil, reportDirectory: String? = nil, repositoryRoot: String? = nil, verificationCommands: [String] = []) {
        self.id = id; self.displayName = displayName; self.allowedRoots = allowedRoots; self.allowedExtensions = allowedExtensions; self.provider = provider; self.obsidian = obsidian; self.obsidianProjectNote = obsidianProjectNote; self.reportDirectory = reportDirectory; self.repositoryRoot = repositoryRoot; self.verificationCommands = verificationCommands
    }
    private enum CodingKeys: String, CodingKey { case id, displayName, allowedRoots, allowedExtensions, provider, obsidian, obsidianProjectNote, reportDirectory, repositoryRoot, verificationCommands }
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        displayName = try container.decode(String.self, forKey: .displayName)
        allowedRoots = try container.decode([String].self, forKey: .allowedRoots)
        allowedExtensions = try container.decode([String].self, forKey: .allowedExtensions)
        provider = try container.decode(CloudProvider.self, forKey: .provider)
        obsidian = try container.decodeIfPresent(ObsidianTarget.self, forKey: .obsidian)
        obsidianProjectNote = try container.decodeIfPresent(String.self, forKey: .obsidianProjectNote)
        reportDirectory = try container.decodeIfPresent(String.self, forKey: .reportDirectory)
        repositoryRoot = try container.decodeIfPresent(String.self, forKey: .repositoryRoot)
        verificationCommands = try container.decodeIfPresent([String].self, forKey: .verificationCommands) ?? []
    }
}

public struct ObsidianTarget: Codable, Sendable { public var vaultRoot: String; public var existingNote: String }

public struct EvidenceItem: Codable, Identifiable, Sendable {
    public var id: String { sourceID }
    public var sourceID: String
    public var relativePath: String
    public var modifiedAt: Date
    public var excerpt: String
    public var sha256: String
}

public struct EvidenceBundle: Codable, Sendable {
    public var sessionID: String
    public var profileID: String
    public var createdAt: Date
    public var items: [EvidenceItem]
    public var excludedCount: Int
    public var repository: RepositorySnapshot?
    public init(sessionID: String, profileID: String, createdAt: Date, items: [EvidenceItem], excludedCount: Int, repository: RepositorySnapshot? = nil) {
        self.sessionID = sessionID; self.profileID = profileID; self.createdAt = createdAt; self.items = items; self.excludedCount = excludedCount; self.repository = repository
    }
}

public struct VerificationResult: Codable, Sendable, Hashable {
    public var command: String
    public var exitCode: Int32
    /// Kept only in the local artifact session; never copied to the reviewed note.
    public var output: String
    public init(command: String, exitCode: Int32, output: String) {
        self.command = command; self.exitCode = exitCode; self.output = output
    }
}

public struct RepositorySnapshot: Codable, Sendable {
    public var branch: String?
    public var latestCommit: String?
    public var changes: [String]
    public var verificationResults: [VerificationResult]
    public init(branch: String?, latestCommit: String?, changes: [String], verificationResults: [VerificationResult]) {
        self.branch = branch; self.latestCommit = latestCommit; self.changes = changes; self.verificationResults = verificationResults
    }
}

public struct CloseoutDraft: Codable, Sendable {
    public var title: String
    public var summary: String
    public var accomplishments: [String]
    public var pending: [String]
    public var blockers: [String]
    public var nextSteps: [String]
    public var sourceIDs: [String]
}

public struct CloseoutSession: Codable, Sendable {
    public var id: String
    public var profileID: String
    public var createdAt: Date
    public var bundle: EvidenceBundle
    public var draft: CloseoutDraft
    public var externalTransmissionApproved: Bool
    public var writesApproved: Bool
}

public enum CloseoutError: LocalizedError, Sendable {
    case unsafePath(String), invalidConfiguration(String), noMatchingProfile, invalidDraft(String), writeTargetsNotConfigured, userApprovalRequired, sessionAlreadyApplied
    public var errorDescription: String? {
        switch self {
        case .unsafePath(let detail): return "Unsafe path: \(detail)"
        case .invalidConfiguration(let detail): return "Invalid configuration: \(detail)"
        case .noMatchingProfile: return "No project profile matches that identifier."
        case .invalidDraft(let detail): return "Invalid draft: \(detail)"
        case .writeTargetsNotConfigured: return "No Obsidian note or report directory has been configured."
        case .userApprovalRequired: return "Explicit approval is required before writing."
        case .sessionAlreadyApplied: return "This closeout session has already been applied."
        }
    }
}
