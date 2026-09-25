---
name: Airdraft Finder installer
description: The silver capsule frames a native drag-to-install action.
colors:
  silver-top: "#F1F4F9"
  silver-base: "#E6EAF1"
  silver-bottom: "#DCE1E9"
  capsule-top: "#F5F7FA"
  capsule-bottom: "#E2E7EE"
  ink: "#263146"
  muted: "#505C73"
  arrow: "#6879A5"
  shadow: "#8F9BB1"
  contact: "#5F6C87"
typography:
  headline:
    fontFamily: "SF Pro, system-ui, sans-serif"
    fontSize: "30pt"
    fontWeight: 500
    letterSpacing: "-0.6pt"
  body:
    fontFamily: "SF Pro, system-ui, sans-serif"
    fontSize: "16pt"
    fontWeight: 400
  caption:
    fontFamily: "SF Pro, system-ui, sans-serif"
    fontSize: "13pt"
    fontWeight: 400
components:
  installation-capsule:
    backgroundColor: "{colors.silver-base}"
    width: "574pt"
    height: "194pt"
---

# Design system: Airdraft Finder installer

## Overview

**Creative North Star: "The silver installation capsule"**

The app icon's silver capsule holds the app and its Applications destination. The
outlined Airdraft wordmark introduces the window; the arrow and two short instructions
explain the action. Finder owns the files, labels, selection and drag interaction.

This document describes the local preview built with an existing signed release app.
The mounted Finder review passed with both instructions visible, including with path
and status bars retained. The preview has not been published.

## Colors

Cool silver gradients carry the existing app identity. Slate ink gives the wordmark
and installation instruction clear contrast; muted slate marks the follow-up step.
The violet-blue arrow directs the drag without competing with the native icons.
The background stays light regardless of Finder's surrounding chrome.

## Typography

Use the macOS system font at the roles above. Emphasize only "Airdraft" and
"Applications" in the installation sentence with semibold weight. Finder supplies
its own labels at the configured 13 pt size. The wordmark is the existing vector
asset, never re-created with live text.

## Layout

The Finder window is 760 × 588 pt. Its 760 × 560 pt background extends below the
essential content so retained path and status bars can consume the bottom bleed.
Keep all instructions within the first 500 pt of the background.

The layout is fixed, with coordinates measured in Finder content points:

| Element | Position or size |
| --- | --- |
| Airdraft icon | 112 pt, at x 220 / y 270 |
| Applications link | 112 pt, at x 540 / y 270 |
| Outer / inner capsule | 574 × 194 / 544 × 164 pt, centered at x 380 / y 278 |
| Wordmark | 126 × 28 pt, centered at x 380 / y 51 |
| Welcome heading | Centered at x 380 / y 110 |
| Arrow | 54 × 20 pt, centered at x 380 / y 264 |
| Installation / opening instructions | Centered at x 380 / y 414 and y 443 |

`scripts/dmg-layout.json` owns the window, background and Finder icon measurements.
`scripts/render-dmg-background.swift` owns the artwork placement.

## Elevation & Depth

Upper-left light, a broad offset shadow and a short contact shadow lift the capsule
rim. Opposed inner shadows recess its center. Four faint capsule contours extend to
the window edges. Keep this lighting consistent with `scripts/render-app-icon.swift`.

## Shapes

Use continuous capsules with fully rounded ends. The direction arrow has a 2 pt
stroke and rounded ends and joins. Reuse the shared outlined wordmark from
`Sources/App/Assets.xcassets/SidebarWordmark.imageset/wordmark.svg`.

## Components

The background is static artwork. The app bundle and `/Applications` symbolic link
remain real Finder items with labels below them. Finder controls selection, focus,
dragging and file-copy feedback. Do not bake these items or labels into the artwork.

The renderer exports 1× and 2× PNG previews and a TIFF containing both representations
at the same point size. `scripts/build-dmg.py` embeds that TIFF and a hidden provenance
file, then verifies the finished image's layout and app signing identity.

## Do's and Don'ts

- Do inspect the mounted Finder window, including retained path and status bars.
- Do regenerate artwork from code and preserve its provenance file.
- Do keep native labels and installation behavior intact.
- Don't add FinderInfo to the signed app to hide its extension; strict signing rejects it.
- Don't claim a local preview is a published release.
