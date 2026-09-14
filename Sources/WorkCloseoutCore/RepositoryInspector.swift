import Foundation

/// Reads local Git metadata and runs explicitly configured, local verification commands.
/// It never contacts remotes and only records bounded command output in the artifact session.
public struct RepositoryInspector: Sendable {
    private let maximumOutputCharacters = 8_000
    private let maximumChanges = 200

    public init() {}

    public func inspect(profile: ProjectProfile) throws -> RepositorySnapshot? {
        guard let repositoryRoot = profile.repositoryRoot else { return nil }
        let root = try existingDirectory(repositoryRoot)
        let inside = try run(executable: "/usr/bin/git", arguments: ["-C", root.path, "rev-parse", "--is-inside-work-tree"], currentDirectory: root)
        guard inside.exitCode == 0, inside.output.trimmingCharacters(in: .whitespacesAndNewlines) == "true" else {
            throw CloseoutError.invalidConfiguration("\(profile.id) repositoryRoot is not a Git work tree")
        }

        let branch = try run(executable: "/usr/bin/git", arguments: ["-C", root.path, "branch", "--show-current"], currentDirectory: root)
        let commit = try run(executable: "/usr/bin/git", arguments: ["-C", root.path, "log", "-1", "--format=%h %s"], currentDirectory: root)
        let status = try run(executable: "/usr/bin/git", arguments: ["-C", root.path, "status", "--short"], currentDirectory: root)
        let verificationResults = try profile.verificationCommands.map { command in
            let result = try run(executable: "/bin/zsh", arguments: ["-lc", command], currentDirectory: root)
            return VerificationResult(command: command, exitCode: result.exitCode, output: result.output)
        }
        return RepositorySnapshot(
            branch: nonEmpty(branch.output),
            latestCommit: commit.exitCode == 0 ? nonEmpty(commit.output) : nil,
            changes: status.output.split(separator: "\n", omittingEmptySubsequences: true).prefix(maximumChanges).map(String.init),
            verificationResults: verificationResults
        )
    }

    private func existingDirectory(_ path: String) throws -> URL {
        let url = URL(fileURLWithPath: path).standardizedFileURL.resolvingSymlinksInPath()
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw CloseoutError.invalidConfiguration("repositoryRoot does not exist: \(path)")
        }
        return url
    }

    private func run(executable: String, arguments: [String], currentDirectory: URL) throws -> (exitCode: Int32, output: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.currentDirectoryURL = currentDirectory
        let output = Pipe()
        process.standardOutput = output
        process.standardError = output
        try process.run()
        process.waitUntilExit()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        let text = String(decoding: data, as: UTF8.self)
        return (process.terminationStatus, String(text.prefix(maximumOutputCharacters)))
    }

    private func nonEmpty(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

public enum LocalVerificationCommand {
    /// The configuration is local. Only simple test/check command forms are accepted;
    /// shell composition, network clients, privilege escalation, and app launchers are rejected.
    public static func validate(_ command: String) throws {
        let trimmed = command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw CloseoutError.invalidConfiguration("verification commands cannot be blank") }
        let unsafeSyntax = CharacterSet(charactersIn: ";|&$`><\n\r")
        guard trimmed.rangeOfCharacter(from: unsafeSyntax) == nil else {
            throw CloseoutError.invalidConfiguration("verification commands cannot use shell composition: \(trimmed)")
        }
        let prohibited = ["curl", "wget", "ssh", "scp", "rsync", "git push", "git pull", "git fetch", "sudo", "rm ", "launchctl", "osascript", "open "]
        let lower = " \(trimmed.lowercased()) "
        guard !prohibited.contains(where: { lower.contains($0) }) else {
            throw CloseoutError.invalidConfiguration("verification command is not local and read-only: \(trimmed)")
        }
        let approvedCommands = ["make check", "make check-categories", "make test", "make lint", "make verify", "swift test", "python -m unittest", "python3 -m unittest", "pytest", "npm test"]
        guard approvedCommands.contains(where: { trimmed == $0 || trimmed.hasPrefix($0 + " ") }) else {
            throw CloseoutError.invalidConfiguration("verification command is not an approved check/test form: \(trimmed)")
        }
    }
}
