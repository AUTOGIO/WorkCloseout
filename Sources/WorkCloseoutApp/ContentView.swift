import AppKit
import SwiftUI
import WorkCloseoutCore

@MainActor final class CloseoutStore: ObservableObject {
    @Published var status = "Ready to prepare a local closeout. Cloud AI is disabled."
    @Published var session: CloseoutSession?
    @Published var approved = false
    @Published var profile: ProjectProfile?
    @Published var canWrite = false
    @Published var profiles: [ProjectProfile] = []
    @Published var selectedProfileID = ""
    @Published var recordedDestinations: [URL] = []
    @Published var connectedProjectNotes: [ObsidianProjectNote] = []
    private var artifactRoot: URL?
    func prepareCloseout() {
        do {
            let url = try configurationURL(); let config = try ConfigurationStore.load(from: url)
            profiles = config.projects
            connectedProjectNotes = try discoveredNotes(in: config)
            let selected = try selectedProfile(in: config)
            profile = selected; let root = URL(fileURLWithPath: config.artifactDirectory, relativeTo: url.deletingLastPathComponent()).standardizedFileURL
            artifactRoot = root; session = try CloseoutService().prepareCloseout(profile: selected, artifactDirectory: root); recordedDestinations = []; canWrite = selected.obsidian != nil || selected.reportDirectory != nil
            status = "Closeout prepared. Review the evidence and closeout below. No external data was sent."
        } catch { status = error.localizedDescription }
    }
    func prepare() {
        do {
            let config = try ConfigurationStore.load(from: configurationURL())
            profiles = config.projects
            connectedProjectNotes = try discoveredNotes(in: config)
            if selectedProfileID.isEmpty { selectedProfileID = config.projects.first?.id ?? "" }
        } catch { status = error.localizedDescription }
    }
    func approveWrites() {
        guard let session, let profile, let artifactRoot else { return }
        do { let result = try CloseoutService().apply(session: session, profile: profile, artifactDirectory: artifactRoot, approval: approved); self.session = result.session; recordedDestinations = result.destinations; status = "Approved write completed: \(result.destinations.map(\.path).joined(separator: ", "))" } catch { status = error.localizedDescription }
    }
    var evidenceDirectory: URL? {
        guard let artifactRoot, let session else { return nil }
        return artifactRoot.appendingPathComponent("sessions/\(session.id)", isDirectory: true)
    }
    var updatedFile: URL? { recordedDestinations.first ?? profile?.obsidian.map { URL(fileURLWithPath: $0.existingNote) } }
    func open(_ url: URL) { NSWorkspace.shared.open(url) }
    private func configurationURL() throws -> URL {
        if let environment = ProcessInfo.processInfo.environment["WORK_CLOSEOUT_CONFIG"] { return URL(fileURLWithPath: environment) }
        if let bundled = Bundle.main.url(forResource: "work-closeout", withExtension: "json") { return bundled }
        throw CloseoutError.unsafePath("No configuration. Set WORK_CLOSEOUT_CONFIG to an absolute configuration path.")
    }
    private func selectedProfile(in config: AppConfiguration) throws -> ProjectProfile {
        if selectedProfileID.isEmpty { selectedProfileID = config.projects.first?.id ?? "" }
        return try ConfigurationStore.resolvedProfile(selectedProfileID, in: config)
    }
    private func discoveredNotes(in config: AppConfiguration) throws -> [ObsidianProjectNote] {
        guard let directory = config.obsidianProjectsDirectory else { return [] }
        return try ObsidianProjectRegistry.discover(in: URL(fileURLWithPath: directory))
    }
}

struct ContentView: View {
    @StateObject private var store = CloseoutStore()
    var body: some View {
        NavigationSplitView {
            List { Label("Prepare", systemImage: "checklist").tag("prepare"); Label("Review", systemImage: "doc.text.magnifyingglass").tag("review"); Label("Record", systemImage: "checkmark.seal").tag("record") }.listStyle(.sidebar)
        } detail: {
            VStack(alignment: .leading, spacing: 16) {
                Text("Work Closeout").font(.largeTitle).fontWeight(.semibold)
                Text(store.status).foregroundStyle(.secondary)
                if store.profiles.count > 1 { Picker("Project", selection: $store.selectedProfileID) { ForEach(store.profiles) { Text($0.displayName).tag($0.id) } }.pickerStyle(.menu) }
                if !store.connectedProjectNotes.isEmpty {
                    HStack {
                        Menu("Open Obsidian project note") {
                            ForEach(store.connectedProjectNotes) { note in Button(note.title) { store.open(note.fileURL) } }
                        }
                        Text("\(store.connectedProjectNotes.count) existing project notes connected.").font(.caption).foregroundStyle(.secondary)
                    }
                }
                HStack { Button("Prepare closeout", action: store.prepareCloseout).keyboardShortcut("r", modifiers: [.command]); Text("Evidence stays local until you explicitly record this closeout.").font(.caption).foregroundStyle(.secondary) }
                Divider()
                if let session = store.session {
                    if let repository = session.bundle.repository {
                        GroupBox("Repository state") {
                            VStack(alignment: .leading, spacing: 4) {
                                if let branch = repository.branch { Text("Branch: \(branch)") }
                                if let commit = repository.latestCommit { Text("Latest commit: \(commit)") }
                                Text(repository.changes.isEmpty ? "Working tree: clean" : "Working tree: \(repository.changes.count) uncommitted change(s)")
                                if !repository.verificationResults.isEmpty { Text("Verification: \(repository.verificationResults.filter { $0.exitCode == 0 }.count)/\(repository.verificationResults.count) passed") }
                            }.font(.callout).frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    GroupBox("Redacted evidence — \(session.bundle.items.count) item(s)") { List(session.bundle.items) { item in VStack(alignment: .leading) { Text(item.relativePath).fontWeight(.medium); Text(item.excerpt.prefix(260)).font(.caption).foregroundStyle(.secondary).lineLimit(4) } }.frame(minHeight: 180) }
                    GroupBox("Prepared closeout") { ScrollView { Text(CloseoutService().markdown(session)).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }.frame(minHeight: 160) }
                    if store.canWrite { Toggle("I reviewed this closeout and approve recording it", isOn: $store.approved); Button("Record reviewed closeout", action: store.approveWrites).disabled(!store.approved || session.writesApproved) } else { Text("No record destination is configured. This closeout remains local until one is added.").font(.callout).foregroundStyle(.secondary) }
                    HStack {
                        if let destination = store.updatedFile {
                            Button(session.writesApproved ? "Open updated file" : "Open project note") { store.open(destination) }
                        }
                        if let evidenceDirectory = store.evidenceDirectory {
                            Button("Open evidence bundle") { store.open(evidenceDirectory) }
                        }
                    }
                } else { ContentUnavailableView("No closeout prepared", systemImage: "doc.badge.clock", description: Text("Prepare a closeout from the configured local evidence.")) }
            }.padding(24)
        }.onAppear { store.prepare() }
    }
}
