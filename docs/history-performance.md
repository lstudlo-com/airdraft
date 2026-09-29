# History scrolling

History keeps a lazy stack with stable record IDs. Record preparation runs once
per database page, off the main actor. Scrolling only tracks visible IDs and
updates the timeline. Collapsed transcripts use bounded native text layout.

## Investigation

The previous renderer was already lazy, but every timeline selection change
invalidated the page. Both columns rebuilt their grouping arrays, repeatedly
formatted dates and scanned all records to find the first visible entry. Each
card also laid out a hidden, unlimited transcript and fed measured heights back
into SwiftUI state. Saved-audio checks acquired a filesystem lock from row
construction.

Apple documents these as separate performance concerns:

- Cache collection transformations and use cheap, stable IDs with one row per
  element. [Demystify SwiftUI performance, WWDC23](https://developer.apple.com/videos/play/wwdc2023/10160/).
- Narrow observation dependencies and cache formatted values.
  [Optimize SwiftUI performance with Instruments, WWDC25](https://developer.apple.com/videos/play/wwdc2025/306/).
- Lazy stacks prefetch custom scrolling content. Changing row height after
  appearance discards that work and can disturb programmatic scrolling.
  [Dive into lazy stacks and scrolling, WWDC26](https://developer.apple.com/videos/play/wwdc2026/321/).
- Expensive bodies and excessive short updates both cause hitches. Move work
  out of rendering and isolate frequently changing state.
  [SwiftUI performance guidance](https://developer.apple.com/documentation/xcode/understanding-and-improving-swiftui-performance).

`List` and `NSTableView` were considered. Apple improved large macOS lists in
[SwiftUI for macOS 26](https://developer.apple.com/videos/play/wwdc2025/256/),
and AppKit supports [reusable table views](https://developer.apple.com/documentation/appkit/nstableviewdelegate/tableview(_:viewfor:row:)).
Neither container removes expensive application work. Keeping the existing
custom card layout avoids replacing its timeline navigation and native actions;
measurements below confirm that scrolling no longer scales with loaded records.

## Implementation

`HistorySnapshot` prepares day headings, timestamps, metadata, trimmed text,
audio availability and the ID index outside view rendering. Appending a database
page reuses previously prepared entries. Search is debounced and stale loads
cannot replace newer results. Day, locale and time-zone changes refresh labels.

Timeline position lives separately from page data. Visibility lookup examines
only reported visible IDs. Row expansion and transcript-version state survive
lazy view eviction.

`HistoryTranscript` uses a selectable `NSTextField`. Collapsed text is limited
to 2,048 graphemes and six lines; a seven-line probe determines whether to offer
expansion. Copy and expansion retain the complete transcript. Width-dependent
measurements are cached and returned in the first SwiftUI size proposal, without
geometry-driven state updates. The text field explicitly clips drawing and native
selection to its measured bounds, keeping long paragraphs out of Show More and
the card's version picker and actions. A line limit alone does not establish that
drawing boundary. These use documented
[wrapping line limits](https://developer.apple.com/documentation/appkit/nstextfield/maximumnumberoflines)
and [native view sizing](https://developer.apple.com/documentation/swiftui/nsviewrepresentable/sizethatfits(_:nsview:context:)).

## Verification

Measured on macOS 27.0 with Xcode 27.0, in the Debug app, at 784 points wide.
The same 180 direct scroll-wheel steps ran in light and dark appearances with
isolated English, Chinese and emoji fixtures, including long transcripts.

| Loaded entries | Before p95 | After p95 | Grouping passes before / after | Card bodies before / after |
| --- | --- | --- | --- | --- |
| 200 | 55.8–60.3 ms | 30.9–33.4 ms | 360–364 / 0 | 1,039–1,041 / 59 |
| 2,000 | 84.3–89.6 ms | 32.9–33.4 ms | 364 / 0 | 1,030–1,045 / 58 |

These are end-to-end step timings including a 1/120-second run-loop allowance,
not display frame times or a Release-build FPS measurement. The reliable
regression checks assert zero grouping during scrolling and bounded row updates.
A separate sticky-header fix landed during this work, so timing differences are
comparative observations rather than an isolated microbenchmark.

Run the Debug executable with `AIRDRAFT_RENDER_HISTORY_COUNT=2000` and
`AIRDRAFT_RENDER_VERIFY_NAVIGATION=1`, followed by
`--render-window history /tmp/airdraft-history-check`. Fixtures use temporary
databases. Checks cover pagination across day boundaries, search, deletion,
visible-ID lookup, multilingual text, six-line truncation, expansion and cache
invalidation, real native selection and expansion after view recreation.
Drawing-boundary checks cover initial display, expansion/collapse, transcript
version changes and native selection at three widths in both appearances. The
unclipped implementation fails this check because its visible drawing rectangle
extends beyond the text field into the surrounding controls.
The core suite completed 266 tests with four skips and zero failures. All pages
were rendered at 784 × 600 and 784 × 1,000 in both appearances, with additional
History checks in the collapsed sidebar. The live window check covers both scroll columns, bottom-to-top
synchronization and pointer focus. No release or other Mac was verified.
