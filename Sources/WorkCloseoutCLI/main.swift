import Foundation
import WorkCloseoutCore

@main struct WorkCloseoutCLI {
    static func main() {
        do { try run(Array(CommandLine.arguments.dropFirst())) }
        catch { FileHandle.standardError.write(Data("error: \(error.localizedDescription)\n".utf8)); exit(1) }
    }
    static func run(_ arguments: [String]) throws {
        guard let command = arguments.first else { print(usage); return }
        let options = try parseOptions(Array(arguments.dropFirst()))
        guard let configText = options["--config"], let projectID = options["--project"] else { print(usage); return }
        let configURL = URL(fileURLWithPath: configText).standardizedFileURL
        let config = try ConfigurationStore.load(from: configURL)
        let profile = try ConfigurationStore.resolvedProfile(projectID, in: config)
        let artifactRoot = absolute(config.artifactDirectory, relativeTo: configURL.deletingLastPathComponent())
        switch command {
        case "prepare":
            let session = try CloseoutService().prepareCloseout(profile: profile, artifactDirectory: artifactRoot)
            print("Closeout prepared: \(session.id)\nRedacted evidence: \(session.bundle.items.count) item(s)\nNo external data was sent. Review: \(artifactRoot.path)/sessions/\(session.id)/draft.md")
        case "apply":
            guard arguments.contains("--approve"), let sessionID = options["--session"] else { throw CloseoutError.userApprovalRequired }
            let url = artifactRoot.appendingPathComponent("sessions/\(sessionID)/session.json")
            let session = try JSONDecoder.closeout.decode(CloseoutSession.self, from: Data(contentsOf: url))
            let result = try CloseoutService().apply(session: session, profile: profile, artifactDirectory: artifactRoot, approval: true)
            print("Approved write complete:\n\(result.destinations.map(\.path).joined(separator: "\n"))")
        default: print(usage)
        }
    }
    static func parseOptions(_ arguments: [String]) throws -> [String: String] {
        var options: [String: String] = [:]
        var index = 0
        while index < arguments.count {
            let key = arguments[index]
            if key == "--approve" {
                guard options[key] == nil else { throw CloseoutError.invalidConfiguration("duplicate command-line option: \(key)") }
                options[key] = "true"; index += 1; continue
            }
            guard key.hasPrefix("--"), index + 1 < arguments.count else { throw CloseoutError.invalidConfiguration("invalid command-line option: \(key)") }
            guard options[key] == nil else { throw CloseoutError.invalidConfiguration("duplicate command-line option: \(key)") }
            options[key] = arguments[index + 1]
            index += 2
        }
        return options
    }
    static func absolute(_ text: String, relativeTo base: URL) -> URL { URL(fileURLWithPath: text, relativeTo: base).standardizedFileURL }
    static let usage = """
    Usage:
      work-closeout prepare --config /absolute/path/work-closeout.json --project project-id
      work-closeout apply --config /absolute/path/work-closeout.json --project project-id --session SESSION_ID --approve
    """
}
