import SwiftUI
import UIKit

/// The Airdraft keyboard. It types spaces, deletions and returns on its own;
/// its microphone asks the Airdraft app, which records during a keyboard
/// session, and inserts the finished text here. It never opens other apps.
final class KeyboardViewController: UIInputViewController {
    private var model: KeyboardModel?

    override func viewDidLoad() {
        super.viewDidLoad()
        let model = KeyboardModel(proxy: { [weak self] in self?.textDocumentProxy },
                                  hasFullAccess: { [weak self] in self?.hasFullAccess ?? false },
                                  nextKeyboard: { [weak self] in self?.advanceToNextInputMode() })
        self.model = model
        let host = UIHostingController(rootView: KeyboardView(model: model,
                                                              showsGlobe: needsInputModeSwitchKey))
        host.view.backgroundColor = .clear
        host.sizingOptions = [.intrinsicContentSize]
        addChild(host)
        view.addSubview(host.view)
        host.view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            host.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            host.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            host.view.topAnchor.constraint(equalTo: view.topAnchor),
            host.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        host.didMove(toParent: self)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        model?.refresh()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        // A recording requested here must not finish into another app's field.
        model?.leave()
    }
}
