"""Production App sources prepared for standalone `swiftc` fixtures.

Fixtures compile a few App views without AirdraftCore. These helpers copy the
production definitions they depend on instead of hand-written stand-ins, so a
fixture keeps exercising the real type scale.
"""
from pathlib import Path
import re

# AirdraftCore resolves its catalog through SwiftPM's generated accessor.
BUNDLE_MODULE_SHIM = "import Foundation\nextension Bundle { static let module = Bundle.main }\n"


def typography(repo: Path) -> str:
    """`Typography.swift` with the production `TextSizePreference` and no AirdraftCore."""
    source = (repo / "Sources/App/Views/Typography.swift").read_text()
    source = source.replace("import AirdraftCore\n", "", 1)
    # The settings overload reads AppSettings and RenderMode; fixtures pass a preference.
    source, removed = re.subn(r"\n    /// The saved preference[^\n]*\n    func textSize\(from settings: AppSettings\) -> some View \{\n.*?\n    \}\n",
                              "\n", source, count=1, flags=re.S)
    if removed != 1:
        raise RuntimeError("Typography.textSize(from:) not found")
    settings = (repo / "Packages/AirdraftCore/Sources/AirdraftCore/Settings/AppSettings.swift").read_text()
    preference = re.search(r"public enum TextSizePreference: .*?\n\}\n", settings, re.S)
    if preference is None:
        raise RuntimeError("TextSizePreference not found")
    return source + "\n" + preference.group(0)
