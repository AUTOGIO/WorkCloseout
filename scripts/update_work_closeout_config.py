#!/usr/bin/env python3
"""Auto-update work-closeout.json from configured project scan roots.

Reads the existing work-closeout.json to preserve artifactDirectory and
obsidianProjectsDirectory, then scans a list of root directories for Git
repositories and rebuilds the projects array with safe local verification
commands and allowlisted roots.

Usage:
    python3 scripts/update_work_closeout_config.py

Edit SCAN_ROOTS below to change which directories are inspected.
"""
import json
import os
import re
import subprocess
import sys
import tempfile
from pathlib import Path

# --- User-configurable scan roots ---------------------------------------------
SCAN_ROOTS = [
    Path("/Users/giovannini.eduardogmail.com/Automation"),
    Path("/Users/giovannini.eduardogmail.com/Documents/GitHub"),
]

# Projects that are not Git repositories but should still be tracked.
EXTRA_PROJECTS = [
    Path("/Users/giovannini.eduardogmail.com/Automation/spencer"),
]

# --- Constants ----------------------------------------------------------------
REPO_ROOT = Path(__file__).resolve().parents[1]
CONFIG_PATH = REPO_ROOT / "work-closeout.json"
OBSIDIAN_DIR = Path("/Users/giovannini.eduardogmail.com/Documents/Obsidian/Projects")

ALLOWED_EXTENSIONS = [
    "py", "md", "txt", "swift", "sh", "zsh", "json", "yaml", "yml", "toml"
]


# --- Helpers ------------------------------------------------------------------
def slugify(name: str) -> str:
    """Convert directory name to a config-friendly id."""
    s = name.lower().replace(" ", "-").replace("_", "-")
    s = re.sub(r"[^a-z0-9-]", "", s)
    s = re.sub(r"-+", "-", s).strip("-")
    return s or "project"


def display_name(name: str) -> str:
    """Convert directory name to a human-friendly display name."""
    return name.replace("_", " ").strip()


def has_target(makefile: Path, target: str) -> bool:
    """Check whether a Makefile defines a given target (exact name)."""
    try:
        text = makefile.read_text()
    except Exception:
        return False
    escaped = re.escape(target)
    # Direct target definition: "target:" at start of line.
    if re.search(rf"^{escaped}\s*:", text, re.M) is not None:
        return True
    # .PHONY line: split by whitespace and compare exact tokens.
    for line in text.splitlines():
        if line.strip().startswith(".PHONY"):
            parts = re.split(r"[\s:=]+", line.strip())
            if target in parts:
                return True
    return False


def find_verification_commands(repo: Path) -> list[str]:
    """Determine safe local verification command(s) for a repository."""
    # Swift package — only 'swift test' is accepted by WorkCloseout's validator.
    if (repo / "Package.swift").exists():
        return ["swift test"]

    # Makefile targets in priority order
    makefile = repo / "Makefile"
    if makefile.exists():
        for target in ("check", "check-categories", "test", "lint", "verify"):
            if has_target(makefile, target):
                return [f"make {target}"]

    # Python unittest discovery (must start with 'python3 -m unittest' to pass
    # WorkCloseout's command validator).
    for tests_dir in ("tests", "Tests"):
        tests_path = repo / tests_dir
        if tests_path.is_dir() and any(tests_path.rglob("*.py")):
            return [f"python3 -m unittest discover -s {tests_dir} -v"]

    return []


def find_allowed_roots(repo: Path) -> list[str]:
    """Build conservative allowlisted subdirectories for a repository."""
    candidates = [
        ("scripts", True),
        ("Sources", True),
        ("src", True),
        ("tests", True),
        ("Tests", True),
        ("docs", True),
        ("nfce", False),   # only if present (Personal_Finance)
        ("data", False),   # only if present (Personal_Finance)
        ("config", False),
    ]
    roots = []
    for subdir, always in candidates:
        path = repo / subdir
        if path.is_dir():
            roots.append(str(path))
    if not roots:
        roots.append(str(repo))
    return roots


def discover_projects(scan_roots: list[Path], extras: list[Path]) -> list[Path]:
    """Return immediate subdirectories of scan roots that are Git repositories,
    plus any explicitly listed extra project directories."""
    projects: list[Path] = []
    seen: set[Path] = set()

    for root in scan_roots:
        if not root.is_dir():
            print(f"[warn] scan root not found: {root}", file=sys.stderr)
            continue
        for entry in sorted(root.iterdir()):
            if entry.is_dir() and not entry.name.startswith(".") and (entry / ".git").is_dir():
                resolved = entry.resolve()
                if resolved not in seen:
                    projects.append(entry)
                    seen.add(resolved)

    for entry in extras:
        if entry.is_dir():
            resolved = entry.resolve()
            if resolved not in seen:
                projects.append(entry)
                seen.add(resolved)
        else:
            print(f"[warn] extra project not found: {entry}", file=sys.stderr)

    return sorted(projects, key=lambda p: p.name.lower())


def ensure_obsidian_note(name: str, repo: Path) -> str:
    """Create a minimal Obsidian project note if it does not exist."""
    note_name = f"{name}.md"
    note_path = OBSIDIAN_DIR / note_name
    if not note_path.exists():
        OBSIDIAN_DIR.mkdir(parents=True, exist_ok=True)
        note_path.write_text(
            f"---\n"
            f"type: project\n"
            f"status: active\n"
            f"repository: {repo}\n"
            f"---\n\n"
            f"# {display_name(name)}\n\n"
            f"Project note auto-generated by WorkCloseout config updater.\n"
        )
        print(f"[created] {note_path}")
    return note_name


# --- Main ----------------------------------------------------------------------
def main() -> int:
    if not CONFIG_PATH.exists():
        print(f"[error] existing config not found: {CONFIG_PATH}", file=sys.stderr)
        return 1

    with CONFIG_PATH.open("r", encoding="utf-8") as f:
        config = json.load(f)

    artifact_directory = config.get("artifactDirectory", str(REPO_ROOT / "artifacts"))
    obsidian_projects_directory = config.get(
        "obsidianProjectsDirectory",
        str(OBSIDIAN_DIR),
    )

    projects = []
    for repo in discover_projects(SCAN_ROOTS, EXTRA_PROJECTS):
        name = repo.name
        project_id = slugify(name)
        display = display_name(name)
        note_name = ensure_obsidian_note(name, repo)
        verification = find_verification_commands(repo)
        allowed_roots = find_allowed_roots(repo)

        project = {
            "id": project_id,
            "displayName": display,
            "repositoryRoot": str(repo),
            "allowedRoots": allowed_roots,
            "allowedExtensions": ALLOWED_EXTENSIONS,
            "obsidianProjectNote": note_name,
            "provider": "disabled",
        }
        if verification:
            project["verificationCommands"] = verification

        projects.append(project)
        print(f"[added] {display} ({project_id}) -> verification: {verification}")

    new_config = {
        "artifactDirectory": artifact_directory,
        "obsidianProjectsDirectory": obsidian_projects_directory,
        "projects": projects,
    }

    # Atomic write
    with tempfile.NamedTemporaryFile(
        mode="w", dir=REPO_ROOT, suffix=".json", delete=False, encoding="utf-8"
    ) as tmp:
        json.dump(new_config, tmp, indent=2, ensure_ascii=False)
        tmp_path = Path(tmp.name)

    tmp_path.replace(CONFIG_PATH)
    print(f"[updated] {CONFIG_PATH} ({len(projects)} projects)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
