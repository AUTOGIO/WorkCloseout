# Work Closeout

Work Closeout is a private, local-first macOS closeout assistant. One button creates a reviewable evidence bundle and a deterministic closeout draft. Closeout content never leaves the Mac: there is no telemetry, analytics, or cloud AI provider. A private Git remote may exist for source backup only — never commit live `work-closeout.json`, credentials, or evidence sessions.

## Production-ready local workflow

- A native SwiftUI review window and a `work-closeout` command-line entrypoint.
- A fully local closeout workflow with no API key or network provider.
- Optional local Git branch, latest-commit, working-tree, and configured verification results in each closeout. Verification output stays in the local evidence session; the recorded note shows only the outcome.
- Strict per-project allowlists, profile selection in the app, and a hard cap on evidence count and file size.
- Exclusion of CSV/XLSX/PDF and credential, finance, and binary-like files; excerpts are redacted for common key, token, private-key, GitHub, AWS, and Slack patterns.
- Configuration validation, atomic session publication, audit logs, and no-overwrite artifact directories.
- A mandatory approval control before any configured Obsidian/report write. Existing Obsidian notes are backed up beside the note before an atomic append. After recording, direct **Open updated file** and **Open evidence bundle** buttons provide the exact local destinations.
- An optional Obsidian project registry: the app discovers existing top-level `type: project` notes and offers direct opening of each note. A profile can reference a note filename instead of repeating its full path.
- Network providers are rejected by configuration validation. This release is intentionally local-only.

## Launch your configured closeout

```bash
cd /path/to/WorkCloseout
export WORK_CLOSEOUT_CONFIG="/absolute/path/to/work-closeout.json"
./script/build_and_run.sh
```

The launcher requires `WORK_CLOSEOUT_CONFIG` and packages that explicit local profile into the app. The app prepares a redacted evidence bundle and a closeout for review. It sends nothing externally; recording to an Obsidian note or report requires the in-app approval control.

To run the same flow without the window:

```bash
cd /path/to/WorkCloseout
swift run work-closeout prepare --config /absolute/path/to/work-closeout.json --project my-approved-project
```

Before using the CLI, copy the example to the ignored local file `work-closeout.json`, replace the placeholder with an absolute approved project path, and set the project identifier to `my-approved-project` (or adjust the command). The GUI accepts `WORK_CLOSEOUT_CONFIG` with that absolute path; when a configuration has multiple projects, the review window shows a project picker.

`artifactDirectory` must live outside every `allowedRoots` directory. This prevents a future closeout from collecting its own drafts and logs.

To include real repository context, configure an existing local Git repository and a supported verification command: `make check`, `make check-categories`, `make test`, `make lint`, `make verify`, `swift test`, Python unittest, `pytest`, or `npm test`. The app rejects shell composition, network clients named in the command string, privilege, destructive, and app-launch commands. Approved forms still run the target repository’s own scripts (for example a `Makefile` recipe or `npm test`), which are trusted project code and may perform network I/O — choose verification commands deliberately. Verification runs are capped at 15 minutes; on timeout the process group is terminated and preparation continues with a failed check. A failed verification is recorded as a blocker; it never records the command's raw output in the project note.

```json
"repositoryRoot": "/absolute/path/to/your/repository",
"verificationCommands": ["make check"]
```

## Apple Shortcut, one-click trigger

Create a Shortcut named **Work Closeout** with **Run Shell Script** set to
**zsh**, then paste this body. Replace both paths with absolute paths on your Mac.
Shortcuts runs shell actions from a temporary WorkflowKit directory, not from this project:

```zsh
export WORK_CLOSEOUT_CONFIG="/absolute/path/to/work-closeout.json"
cd -- "/absolute/path/to/WorkCloseout" || exit 1
exec /bin/bash "/absolute/path/to/WorkCloseout/script/build_and_run.sh"
```

It opens the local review window; review remains mandatory. Do not configure Shortcuts to pass project content or API keys.

## Obsidian onboarding and approval

Obsidian is deliberately deferred. After you identify a vault, add an `obsidian` section to a project profile only with an existing vault root and existing note path. Work Closeout refuses to create a vault or a note, and verifies that the registered note resolves inside that vault. To add an optional dated project report, configure an existing `reportDirectory`. Each destination is written only after the review checkbox and approval button (or the CLI `--approve` flag); file names are session-specific and never overwrite.

```json
"obsidian": {
  "vaultRoot": "/absolute/path/to/your/vault",
  "existingNote": "/absolute/path/to/your/vault/Projects/My Project.md"
},
"reportDirectory": "/absolute/path/to/an/existing/project/reports"
```

For an existing project-note directory, wire it once at the top of the configuration and reference a direct filename from each approved profile. The app reads at most 64 KB from the start of each note (YAML frontmatter and the first heading) while discovering the registry; it never creates, renames, or overwrites notes. When both are present, a profile's repository path must match that note's `repository:` property.

```json
"obsidianProjectsDirectory": "/absolute/path/to/your/vault/Projects",
"obsidianProjectNote": "My Project.md"
```

## Cloud adapters — intentionally disabled

The core defines provider names only for forward-compatible configuration, but ships no network adapter and rejects every provider other than `disabled`. No content can leave the Mac. Do not place credentials in `work-closeout.json`.

## Security boundary and limitations

This is a content-selection tool, not a secret scanner or data-loss-prevention product. It does not inspect browser history, system logs, application state, source-control history, raw financial files, or unapproved paths. Allowlisted text can still contain information that a simple pattern redactor does not recognize—review the exact preview before any future cloud transmission. Symlink resolution and root containment are enforced, but an allowlist owner remains responsible for selecting appropriate roots. The local deterministic draft is intentionally conservative and only says what its included sources support.

The `script/build_and_run.sh` launcher builds an ad-hoc, unsigned `.app` for private local use. There is no App Sandbox or notarization in this repository; Gatekeeper prompts on other Macs are expected unless you sign the bundle yourself.

The optional `scripts/update_work_closeout_config.py` helper only rewrites `work-closeout.json`. It never creates Obsidian notes and omits finance-sensitive roots such as `data/` from generated allowlists.

## Verify

```bash
cd /path/to/WorkCloseout
swift test
export WORK_CLOSEOUT_CONFIG="/absolute/path/to/work-closeout.json"
./script/build_and_run.sh --verify
```

Tests cover scope containment/no writes into an input root, artifact-root separation, financial-file exclusion, redaction, draft provenance validation, disabled-provider enforcement, backup-backed approved writes, idempotent session appends, and write approval enforcement. The launch check verifies the process; visual interaction still requires a manual review of the native window.
