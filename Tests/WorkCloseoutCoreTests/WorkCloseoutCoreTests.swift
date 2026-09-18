import XCTest
@testable import WorkCloseoutCore

final class WorkCloseoutCoreTests: XCTestCase {
    func testPreparationWritesOnlyBelowArtifactRootAndExcludesFinancialFiles() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("WorkCloseoutTests-\(UUID().uuidString)")
        let approved = root.appendingPathComponent("approved"); let artifacts = root.appendingPathComponent("artifacts")
        try FileManager.default.createDirectory(at: approved, withIntermediateDirectories: true)
        try Data("finished a safe task\napi_key=sk-testsecretvalue000000".utf8).write(to: approved.appendingPathComponent("progress.md"))
        try Data("sensitive financial content".utf8).write(to: approved.appendingPathComponent("ledger.csv"))
        let profile = ProjectProfile(id: "test", displayName: "Test", allowedRoots: [approved.path])
        let session = try CloseoutService().prepareCloseout(profile: profile, artifactDirectory: artifacts, now: Date(timeIntervalSince1970: 0))
        XCTAssertEqual(session.bundle.items.count, 1)
        XCTAssertFalse(session.bundle.items[0].excerpt.contains("sk-testsecretvalue"))
        XCTAssertEqual(session.bundle.excludedCount, 1)
        XCTAssertTrue(FileManager.default.fileExists(atPath: artifacts.appendingPathComponent("sessions/\(session.id)/session.json").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: approved.appendingPathComponent("closeout.md").path))
    }
    func testDraftValidatorRejectsUnknownEvidence() throws {
        let bundle = EvidenceBundle(sessionID: "s", profileID: "p", createdAt: .now, items: [], excludedCount: 0)
        let draft = CloseoutDraft(title: "t", summary: "s", accomplishments: [], pending: [], blockers: [], nextSteps: [], sourceIDs: ["not-allowed"])
        XCTAssertThrowsError(try DraftValidator.validate(draft, against: bundle))
    }
    func testWritesRequireExplicitApprovalAndConfiguredTarget() throws {
        let profile = ProjectProfile(id: "p", displayName: "P", allowedRoots: [])
        let session = CloseoutSession(id: "s", profileID: "p", createdAt: .now, bundle: EvidenceBundle(sessionID: "s", profileID: "p", createdAt: .now, items: [], excludedCount: 0), draft: TemplateDraftingProvider().draft(bundle: EvidenceBundle(sessionID: "s", profileID: "p", createdAt: .now, items: [], excludedCount: 0)), externalTransmissionApproved: false, writesApproved: false)
        XCTAssertThrowsError(try CloseoutService().writeApprovedTargets(session: session, profile: profile, approval: false))
    }
    func testArtifactDirectoryCannotLiveInsideEvidenceRoot() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("WorkCloseoutArtifactBoundary-\(UUID().uuidString)")
        let source = root.appendingPathComponent("source"); let artifacts = source.appendingPathComponent("artifacts")
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        let profile = ProjectProfile(id: "test", displayName: "Test", allowedRoots: [source.path])
        XCTAssertThrowsError(try CloseoutService().prepareCloseout(profile: profile, artifactDirectory: artifacts))
    }
    func testApprovedObsidianAppendCreatesBackup() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("WorkCloseoutBackup-\(UUID().uuidString)")
        let source = root.appendingPathComponent("source"); let vault = root.appendingPathComponent("vault"); let artifacts = root.appendingPathComponent("artifacts")
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: vault, withIntermediateDirectories: true)
        try Data("completed work".utf8).write(to: source.appendingPathComponent("progress.md"))
        let note = vault.appendingPathComponent("Project.md"); try Data("# Project\n".utf8).write(to: note)
        let profile = ProjectProfile(id: "test", displayName: "Test", allowedRoots: [source.path], obsidian: ObsidianTarget(vaultRoot: vault.path, existingNote: note.path))
        let session = try CloseoutService().prepareCloseout(profile: profile, artifactDirectory: artifacts, now: Date(timeIntervalSince1970: 1))
        let destinations = try CloseoutService().writeApprovedTargets(session: session, profile: profile, approval: true)
        XCTAssertEqual(destinations, [note])
        let recorded = String(data: try Data(contentsOf: note), encoding: .utf8)!
        XCTAssertTrue(recorded.contains("Closeout"))
        XCTAssertTrue(recorded.contains("<!-- work-closeout-session: \(session.id) -->"))
        let names = try FileManager.default.contentsOfDirectory(atPath: vault.path)
        XCTAssertTrue(names.contains { $0.hasPrefix("Project.md.work-closeout-") && $0.hasSuffix(".bak") })
    }
    func testObsidianAppendIsIdempotentForTheSameSession() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("WorkCloseoutIdempotent-\(UUID().uuidString)")
        let source = root.appendingPathComponent("source"); let vault = root.appendingPathComponent("vault"); let artifacts = root.appendingPathComponent("artifacts")
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: vault, withIntermediateDirectories: true)
        try Data("completed work".utf8).write(to: source.appendingPathComponent("progress.md"))
        let note = vault.appendingPathComponent("Project.md"); try Data("# Project\n".utf8).write(to: note)
        let profile = ProjectProfile(id: "test", displayName: "Test", allowedRoots: [source.path], obsidian: ObsidianTarget(vaultRoot: vault.path, existingNote: note.path))
        let service = CloseoutService()
        let session = try service.prepareCloseout(profile: profile, artifactDirectory: artifacts, now: Date(timeIntervalSince1970: 3))
        _ = try service.writeApprovedTargets(session: session, profile: profile, approval: true)
        _ = try service.writeApprovedTargets(session: session, profile: profile, approval: true)
        let recorded = String(data: try Data(contentsOf: note), encoding: .utf8)!
        XCTAssertEqual(recorded.components(separatedBy: "<!-- work-closeout-session: \(session.id) -->").count - 1, 1)
    }
    func testNetworkProviderConfigurationIsRejected() throws {
        let configuration = AppConfiguration(projects: [ProjectProfile(id: "test", displayName: "Test", allowedRoots: ["/tmp"], provider: .openAI)])
        XCTAssertThrowsError(try ConfigurationStore.validate(configuration))
    }
    func testRepositoryContextAndVerificationFailuresAppearInDraftWithoutOutput() throws {
        let repository = RepositorySnapshot(branch: "main", latestCommit: "abc123 Complete closeout", changes: [" M Sources/App.swift"], verificationResults: [
            VerificationResult(command: "make check", exitCode: 1, output: "private failure detail"),
            VerificationResult(command: "swift test", exitCode: 124, output: "verification timed out after 900s")
        ])
        let bundle = EvidenceBundle(sessionID: "s", profileID: "p", createdAt: .now, items: [], excludedCount: 0, repository: repository)
        let draft = TemplateDraftingProvider().draft(bundle: bundle)
        XCTAssertTrue(draft.accomplishments.contains("Repository branch at preparation: main"))
        XCTAssertTrue(draft.pending.contains("Uncommitted change:  M Sources/App.swift"))
        XCTAssertTrue(draft.blockers.contains { $0.contains("Verification failed") })
        XCTAssertTrue(draft.blockers.contains { $0.contains("Verification timed out") })
        XCTAssertFalse(draft.summary.contains("private failure detail"))
    }
    func testLocalVerificationRejectsNetworkCommands() throws {
        XCTAssertThrowsError(try LocalVerificationCommand.validate("curl https://example.com"))
    }
    func testProfilesWithoutRepositoryFieldsRemainDecodable() throws {
        let data = Data("{\"artifactDirectory\":\"/tmp/artifacts\",\"projects\":[{\"id\":\"p\",\"displayName\":\"P\",\"allowedRoots\":[\"/tmp/source\"],\"allowedExtensions\":[\"md\"],\"provider\":\"disabled\"}]}".utf8)
        let configuration = try JSONDecoder.closeout.decode(AppConfiguration.self, from: data)
        XCTAssertEqual(configuration.projects[0].verificationCommands, [])
    }
    func testObsidianProjectRegistryDiscoversOnlyExistingProjectNotesAndResolvesProfile() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("WorkCloseoutObsidian-\(UUID().uuidString)")
        let vault = root.appendingPathComponent("vault"); let projects = vault.appendingPathComponent("Projects"); let repository = root.appendingPathComponent("repo")
        try FileManager.default.createDirectory(at: projects, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: repository, withIntermediateDirectories: true)
        let note = projects.appendingPathComponent("Sample.md")
        try Data("---\ntype: project\nstatus: active\nrepository: \(repository.path)\n---\n\n# Sample Project\n".utf8).write(to: note)
        try Data("---\ntype: index\n---\n# Index\n".utf8).write(to: projects.appendingPathComponent("GitHub Projects.md"))
        try Data("---\ntype: project\n---\n# Backup\n".utf8).write(to: projects.appendingPathComponent("Sample.md.work-closeout-test.bak"))
        let notes = try ObsidianProjectRegistry.discover(in: projects)
        XCTAssertEqual(notes.map(\.fileName), ["Sample.md"])
        XCTAssertEqual(notes[0].title, "Sample Project")
        let profile = ProjectProfile(id: "sample", displayName: "Sample", allowedRoots: [repository.path], obsidianProjectNote: "Sample.md", repositoryRoot: repository.path)
        let configuration = AppConfiguration(projects: [profile], obsidianProjectsDirectory: projects.path)
        let resolved = try ConfigurationStore.resolvedProfile("sample", in: configuration)
        XCTAssertEqual(resolved.obsidian?.existingNote, note.path)
        XCTAssertEqual(resolved.obsidian?.vaultRoot, vault.path)
    }
    func testApplyMarksSessionToPreventDuplicateWrites() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("WorkCloseoutApply-\(UUID().uuidString)")
        let source = root.appendingPathComponent("source"); let vault = root.appendingPathComponent("vault"); let artifacts = root.appendingPathComponent("artifacts")
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: vault, withIntermediateDirectories: true)
        try Data("done".utf8).write(to: source.appendingPathComponent("progress.md"))
        let note = vault.appendingPathComponent("Project.md"); try Data("# Project\n".utf8).write(to: note)
        let profile = ProjectProfile(id: "test", displayName: "Test", allowedRoots: [source.path], obsidian: ObsidianTarget(vaultRoot: vault.path, existingNote: note.path))
        let service = CloseoutService(); let session = try service.prepareCloseout(profile: profile, artifactDirectory: artifacts, now: Date(timeIntervalSince1970: 2))
        let applied = try service.apply(session: session, profile: profile, artifactDirectory: artifacts, approval: true)
        XCTAssertTrue(applied.session.writesApproved)
        XCTAssertThrowsError(try service.apply(session: applied.session, profile: profile, artifactDirectory: artifacts, approval: true))
    }
    func testBoundedProcessTimeoutTerminatesDescendantsWithoutHanging() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("WorkCloseoutTimeout-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let marker = root.appendingPathComponent("child-alive.txt")
        try Data("seed".utf8).write(to: marker)
        let script = """
        import os, time, pathlib
        marker = pathlib.Path('child-alive.txt')
        child = os.fork()
        if child == 0:
            while True:
                marker.write_text('alive:' + str(time.time()), encoding='utf-8')
                time.sleep(0.15)
        time.sleep(60)
        """
        let started = Date()
        let outcome = try BoundedProcess.run(
            executable: "/usr/bin/python3",
            arguments: ["-c", script],
            currentDirectory: root,
            timeout: 1.0,
            maximumOutputCharacters: 2_000
        )
        XCTAssertTrue(outcome.timedOut)
        XCTAssertEqual(outcome.exitCode, 124)
        XCTAssertLessThan(Date().timeIntervalSince(started), 5.0)
        Thread.sleep(forTimeInterval: 0.5)
        let first = try String(contentsOf: marker, encoding: .utf8)
        XCTAssertTrue(first.hasPrefix("alive:"), "expected child heartbeat, marker=\(first)")
        Thread.sleep(forTimeInterval: 0.7)
        let second = try String(contentsOf: marker, encoding: .utf8)
        XCTAssertEqual(first, second)
    }
    func testObsidianProjectRegistryReadsOnlyBoundedPrefix() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("WorkCloseoutBoundedNote-\(UUID().uuidString)")
        let projects = root.appendingPathComponent("Projects")
        try FileManager.default.createDirectory(at: projects, withIntermediateDirectories: true)
        let note = projects.appendingPathComponent("Large.md")
        var contents = "---\ntype: project\nstatus: active\n---\n\n# Large Project\n\n"
        contents += String(repeating: "BODY_PAYLOAD_SHOULD_REMAIN_UNREAD_BY_REGISTRY\n", count: 8_000)
        XCTAssertGreaterThan(contents.utf8.count, ObsidianProjectRegistry.maximumMetadataBytes)
        try Data(contents.utf8).write(to: note)
        let notes = try ObsidianProjectRegistry.discover(in: projects)
        XCTAssertEqual(notes.map(\.fileName), ["Large.md"])
        XCTAssertEqual(notes[0].title, "Large Project")
    }
}
