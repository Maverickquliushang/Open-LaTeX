"""Prepare an independent writing folder in a GitHub Codespaces container.

No host mounts, credentials, ports or uploads. Existing writing files are preserved.
"""
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys

SOURCE = Path(__file__).resolve().parents[2]


def setup():
    if sys.platform != "linux" or not Path("/workspaces").is_dir():
        raise SystemExit("Run this helper inside the configured Linux Codespaces environment.")
    writing = Path("/workspaces/open-latex-writing")
    if writing.is_symlink():
        raise SystemExit("Writing directory is a symlink; refusing to change it.")
    mount = Path("/work")
    if mount.exists() or mount.is_symlink():
        if not mount.is_symlink() or mount.resolve() != writing.resolve():
            raise SystemExit("/work already exists and points elsewhere; no changes made.")
    writing.mkdir(exist_ok=True)
    if not mount.is_symlink():
        mount.symlink_to(writing, target_is_directory=True)
    tools = writing / ".latex-tools"
    tools.mkdir(exist_ok=True)
    for name in ("fast_build.py", "audit_latex.py", "paper_history.py"):
        target = tools / name
        if not target.exists():
            shutil.copyfile(SOURCE / "code/src/tools" / name, target)
    (writing / "papers").mkdir(exist_ok=True)
    for name in ("hello-en", "hello-zh"):
        destination = writing / "papers" / name
        if not destination.exists():
            shutil.copytree(SOURCE / "code/examples" / name, destination)
    settings = writing / ".vscode/settings.json"
    settings.parent.mkdir(exist_ok=True)
    if not settings.exists():
        settings.write_text((SOURCE / "code/config/vscode-settings.json").read_text(encoding="utf-8"), encoding="utf-8")
    cache = SOURCE / "code/.tmp/codespaces"
    cache.mkdir(parents=True, exist_ok=True)
    metadata = json.loads((SOURCE / "code/src/extension/package.json").read_text(encoding="utf-8"))
    vsix = cache / ("paper-history-" + metadata["version"] + ".vsix")
    subprocess.run([sys.executable, str(SOURCE / "code/scripts/package-extension.py"), "--source", str(SOURCE / "code/src/extension"), "--output", str(vsix)], check=True)
    code = shutil.which("code")
    if code:
        result = subprocess.run([code, "--install-extension", str(vsix)], check=False)
        if result.returncode:
            print("Install from VSIX manually if the extension is not listed: " + str(vsix))
    print("Ready. In the browser editor choose File > Open Folder > /work")
    print("English: python3 /work/.latex-tools/fast_build.py --engine pdf --document /work/papers/hello-en/main.tex")
    print("Chinese: python3 /work/.latex-tools/fast_build.py --engine xe --document /work/papers/hello-zh/main.tex")
    print("History: python3 /work/.latex-tools/paper_history.py sweep")
    print("Writing files persist under /workspaces/open-latex-writing, separately from the source repository.")


if __name__ == "__main__":
    setup()
