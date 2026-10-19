"""Create immutable local release archives from explicit, inspectable include lists."""
import argparse
import hashlib
import json
from pathlib import Path
import shutil
import zipfile

ROOT = Path(__file__).resolve().parents[2]
DIRECTORIES = ("code/src", "code/scripts", "code/tests", "code/config", "code/examples", "code/web", "docs", ".github", ".devcontainer")
FILES = ("README.md", "AGENTS.md", "CHANGELOG.md", "LICENSE", ".gitignore", "project-env.ps1",
         "code/project-env.ps1", "code/VERSION", "code/.dockerignore", "versions/INDEX.md")
EXCLUDED = {".git", "__pycache__", ".local", ".tmp", ".cache", "node_modules", ".venv", "bin", "obj"}


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def archive(destination, entries):
    with zipfile.ZipFile(destination, "x", compression=zipfile.ZIP_DEFLATED) as output:
        for path, name in entries:
            if path.is_symlink():
                raise ValueError(f"Cannot package symlink: {name}")
            output.write(path, name)
    with zipfile.ZipFile(destination) as result:
        if result.testzip() is not None:
            raise ValueError("Archive integrity check failed")
        if sorted(result.namelist()) != sorted(name for _, name in entries):
            raise ValueError("Archive include list mismatch")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--runtime", type=Path, required=True)
    parser.add_argument("--notes", type=Path, required=True)
    args = parser.parse_args()
    version = (ROOT / "code/VERSION").read_text().strip()
    target = ROOT / "versions" / ("v" + version)
    if target.exists():
        raise SystemExit("Version directory already exists; historical archives cannot be overwritten.")
    runtime = args.runtime.resolve(strict=True)
    if not runtime.is_relative_to(ROOT / "code"):
        raise SystemExit("Runtime must be produced inside this project's code directory.")
    entries = [(ROOT / name, name) for name in FILES]
    for directory in DIRECTORIES:
        for path in sorted((ROOT / directory).rglob("*")):
            if path.is_file() and not EXCLUDED.intersection(path.relative_to(ROOT).parts):
                entries.append((path, path.relative_to(ROOT).as_posix()))
    runtime_entries = [(p, p.relative_to(runtime).as_posix()) for p in sorted(runtime.rglob("*")) if p.is_file()]
    build_manifest = json.loads((runtime.parent / "build-manifest.json").read_text(encoding="utf-8-sig"))
    expected_runtime = {entry["path"]: entry["sha256"] for entry in build_manifest["files"]}
    actual_runtime = {name: digest(path) for path, name in runtime_entries}
    if actual_runtime != expected_runtime or build_manifest["productVersion"] != version:
        raise SystemExit("Runtime does not match its verified build manifest/version.")
    if any(EXCLUDED.intersection(Path(name).parts) or Path(name).name in {"runtime.json", ".env"}
           for _, name in runtime_entries):
        raise SystemExit("Private configuration or cache cannot enter the runtime archive.")
    if not runtime_entries or not any(name == "Start-LaTeX.exe" for _, name in runtime_entries):
        raise SystemExit("The runtime must include the real built launcher.")
    target.mkdir(parents=True)
    # On a partial error keep the incomplete directory for inspection, never silently overwrite it.
    archive(target / f"open-latex-{version}-source.zip", entries)
    archive(target / f"open-latex-{version}-windows-runtime.zip", runtime_entries)
    shutil.copyfile(args.notes, target / "RELEASE_NOTES.md")
    manifest = {"version": version, "source": [{"path": n, "sha256": digest(p)} for p, n in entries],
                "runtime": [{"path": n, "sha256": digest(p)} for p, n in runtime_entries]}
    (target / "CONTENTS.json").write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    sums = [f"{digest(p)}  {p.name}" for p in sorted(target.iterdir()) if p.is_file()]
    (target / "SHA256SUMS.txt").write_text("\n".join(sums) + "\n", encoding="utf-8")
    print(target)


if __name__ == "__main__":
    main()
