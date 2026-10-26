#!/usr/bin/env python3
"""Package an unsigned device .app, preserving executable bits and symlinks."""
import os
from pathlib import Path
import plistlib
import stat
import sys
import zipfile


def package(app, output):
    app, output = Path(app).resolve(), Path(output).resolve()
    info = plistlib.loads((app / "Info.plist").read_bytes())
    executable = info["CFBundleExecutable"]
    if "iPhoneOS" not in info.get("CFBundleSupportedPlatforms", []):
        raise ValueError("Expected an iPhoneOS device build, not a simulator build")
    if not (app / executable).is_file() or not os.access(app / executable, os.X_OK):
        raise ValueError("Missing executable or executable permissions")
    if (app / "embedded.mobileprovision").exists() or (app / "_CodeSignature").exists():
        raise ValueError("Expected an unsigned app without a provisioning profile/signature")
    output.parent.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(output, "w", zipfile.ZIP_DEFLATED) as archive:
        for root, dirs, files in os.walk(app, followlinks=False):
            for name in sorted(dirs + files):
                source = Path(root) / name
                target = "Payload/" + str(source.relative_to(app.parent))
                if source.is_symlink():
                    entry = zipfile.ZipInfo(target)
                    entry.create_system = 3
                    entry.external_attr = (stat.S_IFLNK | 0o777) << 16
                    archive.writestr(entry, os.readlink(source))
                elif source.is_file():
                    archive.write(source, target)
    with zipfile.ZipFile(output) as archive:
        if archive.testzip() is not None:
            raise ValueError("Corrupt IPA archive")
        entry = archive.getinfo(f"Payload/{app.name}/{executable}")
        if not (entry.external_attr >> 16) & 0o111:
            raise ValueError("Executable permission lost in archive")
    print(output)


if __name__ == "__main__":
    if len(sys.argv) != 3:
        raise SystemExit("usage: package_ipa.py device.app output.ipa")
    package(sys.argv[1], sys.argv[2])
