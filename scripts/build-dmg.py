#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.12"
# dependencies = ["dmgbuild==1.6.7"]
# ///
"""Build Airdraft's Finder installer without launching Finder or modifying the app."""
import argparse
import json
from pathlib import Path
import subprocess
import tempfile

import dmgbuild
from ds_store import DSStore

from release_signing import inspect_app, inspect_dmg

SCRIPTS = Path(__file__).resolve().parent


def settings_for(app, artwork):
    layout = json.loads((SCRIPTS / "dmg-layout.json").read_text())
    return {
        "format": "UDZO",
        "filesystem": "HFS+",
        "files": [str(app), (str(artwork / "provenance.txt"), ".artwork-provenance.txt")],
        "symlinks": {"Applications": "/Applications"},
        # SetFile -a E adds com.apple.FinderInfo to the signed bundle and fails
        # codesign --strict. Leave Finder's normal app-extension behavior intact.
        "hide_extensions": [],
        "background": str(artwork / "background.tiff"),
        # Finder can retain the user's path/status bars even when bwsp disables
        # them. Keep the instructions inside the first 500 pt and allow chrome.
        "window_rect": ((180, 160), (layout["width"], layout["windowHeight"])),
        "icon_locations": {app.name: tuple(layout["appPosition"]),
                           "Applications": tuple(layout["applicationsPosition"])},
        "icon_size": layout["iconSize"],
        "text_size": layout["textSize"],
        "default_view": "icon-view",
        "arrange_by": None,
        "label_pos": "bottom",
        "show_status_bar": False,
        "show_tab_view": False,
        "show_toolbar": False,
        "show_pathbar": False,
        "show_sidebar": False,
        "show_icon_preview": False,
        "include_icon_view_settings": True,
        "include_list_view_settings": False,
    }


def verify_layout(archive, settings):
    """Read the final image, not a staging folder, before signing the update."""
    with tempfile.TemporaryDirectory(prefix="airdraft-layout-check-") as temporary:
        mount = Path(temporary)
        subprocess.run(["hdiutil", "attach", str(archive), "-readonly", "-nobrowse",
                        "-mountpoint", str(mount)], check=True, stdout=subprocess.DEVNULL)
        try:
            if (mount / "Applications").readlink() != Path("/Applications"):
                raise RuntimeError("Installer must link to /Applications")
            if not (mount / ".background.tiff").is_file():
                raise RuntimeError("Installer background is missing")
            with DSStore.open(str(mount / ".DS_Store"), "r") as store:
                for name, position in settings["icon_locations"].items():
                    if store[name]["Iloc"] != position:
                        raise RuntimeError(f"Incorrect installer icon position: {name}")
                view = store["."]["icvp"]
                if view["backgroundType"] != 2 or not view.get("backgroundImageAlias"):
                    raise RuntimeError("Finder has no image background")
                if view["iconSize"] != settings["icon_size"]:
                    raise RuntimeError("Incorrect installer icon size")
                width, height = settings["window_rect"][1]
                if f"{{{width}, {height}}}" not in store["."]["bwsp"]["WindowBounds"]:
                    raise RuntimeError("Incorrect installer window size")
        finally:
            subprocess.run(["hdiutil", "detach", str(mount)], check=True, stdout=subprocess.DEVNULL)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--app", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True, help="New .dmg file")
    args = parser.parse_args()
    app, archive = args.app.resolve(), args.output.resolve()
    if archive.exists():
        parser.error(f"Refusing to overwrite {archive}")
    if archive.suffix != ".dmg":
        parser.error("--output must end with .dmg")
    signing = inspect_app(app)
    archive.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix=".airdraft-dmg-", dir=archive.parent) as temporary:
        work = Path(temporary)
        artwork = work / "artwork"
        candidate = work / archive.name
        subprocess.run(["swift", str(SCRIPTS / "render-dmg-background.swift"), str(artwork)], check=True)
        settings = settings_for(app, artwork)
        dmgbuild.build_dmg(str(candidate), "Airdraft", settings=settings)
        subprocess.run(["hdiutil", "verify", str(candidate)], check=True)
        verify_layout(candidate, settings)
        if inspect_dmg(candidate) != signing:
            raise RuntimeError("Packaging changed the app's signing identity")
        candidate.rename(archive)
    print(f"Verified installer layout and app signature: {archive}")


if __name__ == "__main__":
    main()
