#!/usr/bin/env python3
"""Verify native Dock icon updates using an existing Xcode Debug app and temporary settings."""
import argparse
from pathlib import Path
import subprocess
import tempfile


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--app", type=Path, required=True)
    args = parser.parse_args()
    app = args.app.resolve(strict=True)
    build = app.parent
    derived = app.parents[3]
    packages = derived / "SourcePackages/checkouts"
    if not packages.is_dir() or not (build / "PackageFrameworks/AirdraftCore.framework").is_dir():
        parser.error("Use the Debug .app inside Xcode DerivedData/Build/Products/Debug.")
    repo = Path(__file__).resolve().parents[1]
    with tempfile.TemporaryDirectory(prefix="airdraft-icon-verification-") as temporary:
        executable = Path(temporary) / "verify-app-icons"
        command = ["xcrun", "swiftc", "-parse-as-library",
                   str(repo / "Sources/App/App/AppIconController.swift"),
                   str(repo / "scripts/verify-app-icons.swift"),
                   "-I", str(build), "-I", str(build / "include"),
                   "-F", str(build / "PackageFrameworks"), "-framework", "AirdraftCore",
                   "-Xlinker", "-rpath", "-Xlinker", str(build / "PackageFrameworks"),
                   "-Xlinker", "-rpath", "-Xlinker", str(app / "Contents/Frameworks"),
                   "-o", str(executable)]
        # Clang dependencies of the prebuilt Swift module need their module maps.
        yyjson = derived / "Build/Intermediates.noindex/yyjson.build/Debug/yyjson-t.build/yyjson.modulemap"
        command += ["-Xcc", "-fmodule-map-file=" + str(yyjson)]
        for module in sorted(packages.rglob("module.modulemap")):
            if ".build" not in module.parts and "Tests" not in module.parts:
                command += ["-I", str(module.parent)]
        subprocess.run(command, cwd=repo, check=True)
        subprocess.run([str(executable), str(app)], cwd=repo, check=True, timeout=30)


if __name__ == "__main__":
    main()
