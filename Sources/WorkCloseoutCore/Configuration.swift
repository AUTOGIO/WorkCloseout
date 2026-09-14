import Foundation

public enum ConfigurationStore {
    public static func load(from url: URL) throws -> AppConfiguration {
        let configuration = try JSONDecoder.closeout.decode(AppConfiguration.self, from: Data(contentsOf: url))
        try validate(configuration)
        return configuration
    }
    public static func save(_ configuration: AppConfiguration, to url: URL) throws {
        let data = try JSONEncoder.pretty.encode(configuration)
        try data.write(to: url, options: .withoutOverwriting)
    }
    public static func profile(_ id: String, in configuration: AppConfiguration) throws -> ProjectProfile {
        guard let profile = configuration.projects.first(where: { $0.id == id }) else { throw CloseoutError.noMatchingProfile }
        return profile
    }
    public static func resolvedProfile(_ id: String, in configuration: AppConfiguration) throws -> ProjectProfile {
        var profile = try profile(id, in: configuration)
        guard let noteName = profile.obsidianProjectNote else { return profile }
        guard let directory = configuration.obsidianProjectsDirectory else { throw CloseoutError.invalidConfiguration("\(profile.id) requires obsidianProjectsDirectory") }
        let projectsDirectory = URL(fileURLWithPath: directory)
        let note = try ObsidianProjectRegistry.note(named: noteName, in: projectsDirectory)
        if let repositoryRoot = profile.repositoryRoot, let notedRepository = note.repositoryRoot {
            let configured = URL(fileURLWithPath: repositoryRoot).standardizedFileURL.resolvingSymlinksInPath()
            guard configured == notedRepository else { throw CloseoutError.invalidConfiguration("\(profile.id) repositoryRoot does not match \(noteName) frontmatter") }
        }
        profile.obsidian = ObsidianTarget(vaultRoot: projectsDirectory.deletingLastPathComponent().path, existingNote: note.fileURL.path)
        return profile
    }
    public static func validate(_ configuration: AppConfiguration) throws {
        guard !configuration.artifactDirectory.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw CloseoutError.invalidConfiguration("artifactDirectory is required") }
        let ids = configuration.projects.map(\.id)
        guard ids.allSatisfy({ !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }), Set(ids).count == ids.count else { throw CloseoutError.invalidConfiguration("project identifiers must be present and unique") }
        for profile in configuration.projects {
            guard !profile.allowedRoots.isEmpty else { throw CloseoutError.invalidConfiguration("\(profile.id) has no allowedRoots") }
            guard !profile.allowedExtensions.isEmpty else { throw CloseoutError.invalidConfiguration("\(profile.id) has no allowedExtensions") }
            guard profile.provider == .disabled else { throw CloseoutError.invalidConfiguration("network providers are not implemented; use disabled") }
            if profile.repositoryRoot == nil, !profile.verificationCommands.isEmpty { throw CloseoutError.invalidConfiguration("\(profile.id) has verification commands but no repositoryRoot") }
            if profile.obsidianProjectNote != nil, configuration.obsidianProjectsDirectory == nil { throw CloseoutError.invalidConfiguration("\(profile.id) has obsidianProjectNote but no obsidianProjectsDirectory") }
            for command in profile.verificationCommands { try LocalVerificationCommand.validate(command) }
        }
    }
}

public extension JSONEncoder {
    static var pretty: JSONEncoder { let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]; encoder.dateEncodingStrategy = .iso8601; return encoder }
}

public extension JSONDecoder {
    static var closeout: JSONDecoder { let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601; return decoder }
}
