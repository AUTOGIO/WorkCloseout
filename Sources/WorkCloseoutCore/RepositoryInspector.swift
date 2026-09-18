import Foundation

/// Reads local Git metadata and runs explicitly configured, local verification commands.
/// It never contacts remotes and only records bounded command output in the artifact session.
public struct RepositoryInspector: Sendable {
    private let maximumOutputCharacters = 8_000
    private let maximumChanges = 200
    /// Caps hung `make` / `swift test` / `npm test` runs during closeout preparation.
    public static let verificationTimeoutSeconds: TimeInterval = 900

    public init() {}

    public func inspect(profile: ProjectProfile) throws -> RepositorySnapshot? {
        guard let repositoryRoot = profile.repositoryRoot else { return nil }
        let root = try existingDirectory(repositoryRoot)
        let inside = try run(executable: "/usr/bin/git", arguments: ["-C", root.path, "rev-parse", "--is-inside-work-tree"], currentDirectory: root, timeout: 30)
        guard inside.exitCode == 0, inside.output.trimmingCharacters(in: .whitespacesAndNewlines) == "true" else {
            throw CloseoutError.invalidConfiguration("\(profile.id) repositoryRoot is not a Git work tree")
        }

        let branch = try run(executable: "/usr/bin/git", arguments: ["-C", root.path, "branch", "--show-current"], currentDirectory: root, timeout: 30)
        let commit = try run(executable: "/usr/bin/git", arguments: ["-C", root.path, "log", "-1", "--format=%h %s"], currentDirectory: root, timeout: 30)
        let status = try run(executable: "/usr/bin/git", arguments: ["-C", root.path, "status", "--short"], currentDirectory: root, timeout: 60)
        let verificationResults = try profile.verificationCommands.map { command in
            let result = try run(
                executable: "/bin/zsh",
                arguments: ["-lc", command],
                currentDirectory: root,
                timeout: Self.verificationTimeoutSeconds
            )
            let output = result.timedOut
                ? "verification timed out after \(Int(Self.verificationTimeoutSeconds))s\n" + result.output
                : result.output
            let exitCode = result.timedOut ? Int32(124) : result.exitCode
            return VerificationResult(command: command, exitCode: exitCode, output: output)
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

    private func run(executable: String, arguments: [String], currentDirectory: URL, timeout: TimeInterval) throws -> (exitCode: Int32, output: String, timedOut: Bool) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.currentDirectoryURL = currentDirectory
        let output = Pipe()
        process.standardOutput = output
        process.standardError = output
        try process.run()

        let deadline = Date().addingTimeInterval(timeout)
        while process.isRunning {
            if Date() >= deadline {
                process.terminate()
                let graceDeadline = Date().addingTimeInterval(2)
                while process.isRunning, Date() < graceDeadline {
                    Thread.sleep(forTimeInterval: 0.05)
                }
                if process.isRunning {
                    process.interrupt()
                }
                let data = output.fileHandleForReading.readDataToEndOfFile()
                let text = String(decoding: data, as: UTF8.self)
                return (124, String(text.prefix(maximumOutputCharacters)), true)
            }
            Thread.sleep(forTimeInterval: 0.05)
        }

        let data = output.fileHandleForReading.readDataToEndOfFile()
        let text = String(decoding: data, as: UTF8.self)
        return (process.terminationStatus, String(text.prefix(maximumOutputCharacters)), false)
    }

    private func nonEmpty(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

public enum LocalVerificationCommand {
    /// The configuration is local. Only simple test/check command forms are accepted;
    /// shell composition, network clients, privilege escalation, and app launchers are rejected.
    ///
    /// Approved forms still execute the target repository's scripts (for example `npm test` or
    /// `make check`). Those scripts are trusted project code and may perform network I/O; this
    /// validator only constrains the configured command string, not runtime sandboxing.
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
