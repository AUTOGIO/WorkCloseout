import Foundation

public struct CloseoutService: Sendable {
    public init() {}
    public func prepareCloseout(profile: ProjectProfile, artifactDirectory: URL, now: Date = Date()) throws -> CloseoutSession {
        let root = artifactDirectory.standardizedFileURL.resolvingSymlinksInPath()
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try validateArtifactRoot(root, for: profile)
        let id = ISO8601DateFormatter().string(from: now).replacingOccurrences(of: ":", with: "-") + "-" + UUID().uuidString.prefix(8)
        var bundle = try EvidenceCollector().collect(profile: profile, sessionID: String(id), now: now)
        bundle.repository = try RepositoryInspector().inspect(profile: profile)
        let draft = TemplateDraftingProvider().draft(bundle: bundle)
        try DraftValidator.validate(draft, against: bundle)
        let session = CloseoutSession(id: String(id), profileID: profile.id, createdAt: now, bundle: bundle, draft: draft, externalTransmissionApproved: false, writesApproved: false)
        try writePreparedSession(session, to: root)
        return session
    }
    public func writeApprovedTargets(session: CloseoutSession, profile: ProjectProfile, approval: Bool) throws -> [URL] {
        guard approval else { throw CloseoutError.userApprovalRequired }
        guard session.profileID == profile.id else { throw CloseoutError.invalidDraft("session profile does not match the selected profile") }
        guard !session.writesApproved else { throw CloseoutError.sessionAlreadyApplied }
        try DraftValidator.validate(session.draft, against: session.bundle)
        guard profile.obsidian != nil || profile.reportDirectory != nil else { throw CloseoutError.writeTargetsNotConfigured }
        var destinations: [URL] = []
        let text = markdown(session)
        if let obsidian = profile.obsidian {
            let url = try configuredFile(note: obsidian.existingNote, constrainedTo: obsidian.vaultRoot)
            try append(text, to: url, sessionID: session.id)
            destinations.append(url)
        }
        if let reportRoot = profile.reportDirectory {
            let root = try existingDirectory(reportRoot)
            let url = root.appendingPathComponent("closeout-\(session.id).md")
            if FileManager.default.fileExists(atPath: url.path) {
                destinations.append(url)
            } else {
                try text.data(using: .utf8)!.write(to: url, options: .withoutOverwriting)
                destinations.append(url)
            }
        }
        return destinations
    }
    public func apply(session: CloseoutSession, profile: ProjectProfile, artifactDirectory: URL, approval: Bool) throws -> (session: CloseoutSession, destinations: [URL]) {
        let destinations = try writeApprovedTargets(session: session, profile: profile, approval: approval)
        var applied = session
        applied.writesApproved = true
        let root = artifactDirectory.standardizedFileURL.resolvingSymlinksInPath()
        let sessionFile = root.appendingPathComponent("sessions/\(session.id)/session.json").standardizedFileURL
        guard sessionFile.path.hasPrefix(root.path + "/"), FileManager.default.fileExists(atPath: sessionFile.path) else { throw CloseoutError.unsafePath("session file is missing from the artifact directory") }
        try JSONEncoder.pretty.encode(applied).write(to: sessionFile, options: .atomic)
        return (applied, destinations)
    }
    private func writePreparedSession(_ session: CloseoutSession, to root: URL) throws {
        let sessions = root.appendingPathComponent("sessions", isDirectory: true)
        let directory = sessions.appendingPathComponent(session.id, isDirectory: true)
        let staging = sessions.appendingPathComponent(".\(session.id).staging-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: sessions, withIntermediateDirectories: true)
        guard !FileManager.default.fileExists(atPath: directory.path) else { throw CloseoutError.unsafePath("session already exists: \(session.id)") }
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: false)
        do {
            try JSONEncoder.pretty.encode(session).write(to: staging.appendingPathComponent("session.json"), options: .withoutOverwriting)
            try JSONEncoder.pretty.encode(session.bundle).write(to: staging.appendingPathComponent("redacted-evidence.json"), options: .withoutOverwriting)
            try JSONEncoder.pretty.encode(session.draft).write(to: staging.appendingPathComponent("draft.json"), options: .withoutOverwriting)
            try markdown(session).data(using: .utf8)!.write(to: staging.appendingPathComponent("draft.md"), options: .withoutOverwriting)
            try FileManager.default.moveItem(at: staging, to: directory)
        } catch {
            try? FileManager.default.removeItem(at: staging)
            throw error
        }
        let event = "{\"event\":\"closeout_prepared\",\"session\":\"\(session.id)\",\"at\":\"\(ISO8601DateFormatter().string(from: session.createdAt))\"}\n"
        let log = root.appendingPathComponent("logs/audit.jsonl"); try FileManager.default.createDirectory(at: log.deletingLastPathComponent(), withIntermediateDirectories: true)
        if FileManager.default.fileExists(atPath: log.path) { let handle = try FileHandle(forWritingTo: log); try handle.seekToEnd(); try handle.write(contentsOf: Data(event.utf8)); try handle.close() } else { try Data(event.utf8).write(to: log, options: .withoutOverwriting) }
    }
    private func configuredFile(note: String, constrainedTo root: String) throws -> URL { let rootURL = try existingDirectory(root); let url = URL(fileURLWithPath: note).standardizedFileURL.resolvingSymlinksInPath(); guard url.path.hasPrefix(rootURL.path + "/"), FileManager.default.fileExists(atPath: url.path) else { throw CloseoutError.unsafePath("Obsidian note must already exist inside the configured vault") }; return url }
    private func existingDirectory(_ path: String) throws -> URL { let url = URL(fileURLWithPath: path).standardizedFileURL.resolvingSymlinksInPath(); var directory: ObjCBool = false; guard FileManager.default.fileExists(atPath: url.path, isDirectory: &directory), directory.boolValue else { throw CloseoutError.unsafePath("Configured directory does not exist: \(path)") }; return url }
    /// Appends once per session id. If the note already contains the session marker, skip rewriting
    /// so a crash between append and `writesApproved` cannot duplicate content on retry.
    private func append(_ text: String, to url: URL, sessionID: String) throws {
        let originalText = String(decoding: try Data(contentsOf: url), as: UTF8.self)
        if originalText.contains(sessionMarker(sessionID)) { return }
        let backup = url.appendingPathExtension("work-closeout-\(UUID().uuidString).bak")
        try FileManager.default.copyItem(at: url, to: backup)
        let addition = Data("\n\n\(text)".utf8)
        try (Data(originalText.utf8) + addition).write(to: url, options: .atomic)
    }
    private func validateArtifactRoot(_ artifactRoot: URL, for profile: ProjectProfile) throws {
        for rootText in profile.allowedRoots {
            let sourceRoot = URL(fileURLWithPath: rootText).standardizedFileURL.resolvingSymlinksInPath()
            let prefix = sourceRoot.path.hasSuffix("/") ? sourceRoot.path : sourceRoot.path + "/"
            if artifactRoot.path == sourceRoot.path || artifactRoot.path.hasPrefix(prefix) { throw CloseoutError.unsafePath("artifactDirectory must not be inside an allowed source root") }
        }
    }
    public func markdown(_ session: CloseoutSession) -> String {
        "# \(session.draft.title)\n\n<!-- work-closeout-session: \(session.id) -->\n\n\(session.draft.summary)\n\n## Accomplishments\n\(session.draft.accomplishments.map { "- \($0)" }.joined(separator: "\n"))\n\n## Pending\n\(session.draft.pending.map { "- \($0)" }.joined(separator: "\n"))\n\n## Blockers\n\(session.draft.blockers.isEmpty ? "- None." : session.draft.blockers.map { "- \($0)" }.joined(separator: "\n"))\n\n## Next steps\n\(session.draft.nextSteps.map { "- \($0)" }.joined(separator: "\n"))\n\n## Evidence\n\(session.draft.sourceIDs.map { "- \($0)" }.joined(separator: "\n"))\n"
    }

    private func sessionMarker(_ sessionID: String) -> String { "<!-- work-closeout-session: \(sessionID) -->" }
}
