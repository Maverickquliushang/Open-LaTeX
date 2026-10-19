"""Package the local extension using only Python's standard library.

No marketplace, global npm installation or VS Code application state is touched.
"""
import argparse
import json
from pathlib import Path
from xml.sax.saxutils import escape
from zipfile import ZIP_DEFLATED, ZipFile, ZipInfo


def package(source: Path, destination: Path, license_path: Path) -> None:
    metadata = json.loads((source / "package.json").read_text(encoding="utf-8"))
    manifest = f'''<?xml version="1.0" encoding="utf-8"?>
<PackageManifest Version="2.0.0" xmlns="http://schemas.microsoft.com/developer/vsx-schema/2011">
  <Metadata>
    <Identity Language="en-US" Id="{escape(metadata['name'])}" Version="{escape(metadata['version'])}" Publisher="{escape(metadata['publisher'])}" />
    <DisplayName>{escape(metadata['displayName'])}</DisplayName>
    <Description xml:space="preserve">{escape(metadata['description'])}</Description>
    <Tags></Tags><Categories>Other</Categories><GalleryFlags>Public</GalleryFlags>
    <Properties>
      <Property Id="Microsoft.VisualStudio.Code.Engine" Value="{escape(metadata['engines']['vscode'])}" />
      <Property Id="Microsoft.VisualStudio.Code.ExtensionKind" Value="workspace" />
    </Properties>
  </Metadata>
  <Installation><InstallationTarget Id="Microsoft.VisualStudio.Code" /></Installation>
  <Dependencies />
  <Assets>
    <Asset Type="Microsoft.VisualStudio.Code.Manifest" Path="extension/package.json" Addressable="true" />
    <Asset Type="Microsoft.VisualStudio.Services.Content.License" Path="extension/LICENSE" Addressable="true" />
  </Assets>
</PackageManifest>
'''
    content_types = '''<?xml version="1.0" encoding="utf-8"?>
<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
  <Default Extension="json" ContentType="application/json" />
  <Default Extension="js" ContentType="application/javascript" />
  <Default Extension="py" ContentType="text/plain" />
  <Default Extension="html" ContentType="text/html" />
  <Default Extension="css" ContentType="text/css" />
  <Default Extension="svg" ContentType="image/svg+xml" />
  <Default Extension="vsixmanifest" ContentType="text/xml" />
  <Override PartName="/extension/LICENSE" ContentType="text/plain" />
</Types>
'''
    # Explicit source list prevents local caches or private files entering the VSIX.
    files = ["package.json", "extension.js", "backend.py", "media/app.js", "media/index.html", "media/style.css", "media/history.svg"]
    destination.parent.mkdir(parents=True, exist_ok=True)
    with ZipFile(destination, "w", compression=ZIP_DEFLATED) as archive:
        entries = [("extension.vsixmanifest", manifest.encode()), ("[Content_Types].xml", content_types.encode())]
        entries.append(("extension/LICENSE", license_path.read_bytes()))
        entries += [("extension/" + name, (source / name).read_bytes()) for name in files]
        for name, data in entries:
            info = ZipInfo(name, date_time=(2026, 1, 1, 0, 0, 0))
            info.compress_type = ZIP_DEFLATED
            info.external_attr = 0o100644 << 16
            archive.writestr(info, data)
    with ZipFile(destination) as archive:
        if archive.testzip():
            raise RuntimeError("VSIX integrity check failed")
    print(destination)


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--source", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--license", type=Path, default=Path(__file__).resolve().parents[2] / "LICENSE")
    args = parser.parse_args()
    package(args.source.resolve(), args.output.resolve(), args.license.resolve(strict=True))
