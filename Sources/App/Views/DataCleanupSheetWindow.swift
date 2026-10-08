import AppKit
import SwiftUI

/// AppKit otherwise rejects Quit before the delegate runs while this sheet is open.
/// Only a cleanup currently writing data needs to prevent termination.
struct DataCleanupSheetWindow: NSViewRepresentable {
    let isRunning: Bool

    final class BackingView: NSView {
        var isRunning = false {
            didSet { configureWindow() }
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            configureWindow()
        }

        private func configureWindow() {
            window?.preventsApplicationTerminationWhenModal = isRunning
        }
    }

    func makeNSView(context: Context) -> BackingView {
        let view = BackingView()
        view.isRunning = isRunning
        return view
    }

    func updateNSView(_ view: BackingView, context: Context) {
        view.isRunning = isRunning
    }
}
