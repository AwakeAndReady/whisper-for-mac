import AppKit

final class WindowDragAccessoryView: NSView {
    override var mouseDownCanMoveWindow: Bool {
        true
    }
}

final class WindowToolbarAccessoryController: NSTitlebarAccessoryViewController {
    init(height: CGFloat) {
        super.init(nibName: nil, bundle: nil)
        let dragView = WindowDragAccessoryView(frame: NSRect(x: 0, y: 0, width: 10, height: height))
        dragView.translatesAutoresizingMaskIntoConstraints = false
        dragView.frame.size.height = height
        view = dragView
        layoutAttribute = .bottom
        fullScreenMinHeight = height
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func updateHeight(_ height: CGFloat) {
        view.frame.size.height = height
        fullScreenMinHeight = height
    }
}
