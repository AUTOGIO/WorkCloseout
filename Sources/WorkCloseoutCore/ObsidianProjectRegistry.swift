import Foundation

/// A discovered, existing project note. Only the frontmatter and first heading are read.
public struct ObsidianProjectNote: Identifiable, Sendable {
    public var id: String { fileURL.path }
    public var fileURL: URL
    public var fileName: String
    public var title: String
    public var repositoryRoot: URL?
}

public enum ObsidianProjectRegistry {
    public static func discover(in projectsDirectory: URL) throws -> [ObsidianProjectNote] {
        let root = try existingDirectory(projectsDirectory)
        let urls = try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles])
        return try urls.compactMap { url in
            guard url.pathExtension.lowercased() == "md", !url.lastPathComponent.contains(".bak"), !url.lastPathComponent.contains(".work-closeout-") else { return nil }
            let text = try String(contentsOf: url, encoding: .utf8)
            let properties = frontmatter(in: text)
            guard properties["type"]?.lowercased() == "project" else { return nil }
            let title = heading(in: text) ?? url.deletingPathExtension().lastPathComponent
            return ObsidianProjectNote(fileURL: url.standardizedFileURL.resolvingSymlinksInPath(), fileName: url.lastPathComponent, title: title, repositoryRoot: properties["repository"].flatMap(expandedDirectory))
        }.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }

    public static func note(named fileName: String, in projectsDirectory: URL) throws -> ObsidianProjectNote {
        let candidate = URL(fileURLWithPath: fileName)
        guard fileName == candidate.lastPathComponent, candidate.pathExtension.lowercased() == "md", !fileName.hasPrefix(".") else {
            throw CloseoutError.invalidConfiguration("obsidianProjectNote must be a direct Markdown filename")
        }
        guard let note = try discover(in: projectsDirectory).first(where: { $0.fileName == fileName }) else {
            throw CloseoutError.invalidConfiguration("Obsidian project note is missing or is not marked type: project: \(fileName)")
        }
        return note
    }

    private static func existingDirectory(_ url: URL) throws -> URL {
        let resolved = url.standardizedFileURL.resolvingSymlinksInPath()
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: resolved.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw CloseoutError.invalidConfiguration("Obsidian projects directory does not exist: \(url.path)")
        }
        return resolved
    }

    private static func frontmatter(in text: String) -> [String: String] {
        guard text.hasPrefix("---\n"), let end = text.range(of: "\n---", range: text.index(text.startIndex, offsetBy: 4)..<text.endIndex) else { return [:] }
        return text[text.index(text.startIndex, offsetBy: 4)..<end.lowerBound].split(separator: "\n").reduce(into: [:]) { result, line in
            guard let separator = line.firstIndex(of: ":") else { return }
            result[String(line[..<separator]).trimmingCharacters(in: .whitespaces)] = String(line[line.index(after: separator)...]).trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
        }
    }

    private static func heading(in text: String) -> String? {
        text.split(separator: "\n").first(where: { $0.hasPrefix("# ") }).map { String($0.dropFirst(2)).trimmingCharacters(in: .whitespaces) }
    }

    private static func expandedDirectory(_ value: String) -> URL? {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let expanded: String
        if value == "$HOME" || value == "~" { expanded = home }
        else if value.hasPrefix("$HOME/") { expanded = home + String(value.dropFirst("$HOME".count)) }
        else if value.hasPrefix("~/") { expanded = home + String(value.dropFirst(1)) }
        else if value.hasPrefix("/") { expanded = value }
        else { return nil }
        let url = URL(fileURLWithPath: expanded).standardizedFileURL.resolvingSymlinksInPath()
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue else { return nil }
        return url
    }
}
