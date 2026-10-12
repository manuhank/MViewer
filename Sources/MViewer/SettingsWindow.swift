import AppKit

/// Settings window (⌘,) with toolbar-style panes.
final class SettingsWindowController: NSWindowController {
    init() {
        let tabs = NSTabViewController()
        tabs.tabStyle = .toolbar

        let shortcuts = NSTabViewItem(viewController: ShortcutsSettingsViewController())
        shortcuts.label = "Shortcuts"
        shortcuts.image = NSImage(systemSymbolName: "keyboard", accessibilityDescription: "Shortcuts")
        tabs.addTabViewItem(shortcuts)

        let window = NSWindow(contentViewController: tabs)
        window.styleMask = [.titled, .closable]
        window.toolbarStyle = .preference
        window.title = "Settings"
        window.isReleasedWhenClosed = false
        super.init(window: window)
        window.center()
    }

    required init?(coder: NSCoder) { fatalError() }
}

/// Lists every customizable action with its shortcuts. Click a shortcut to
/// re-record it, + to add one, × to remove one. A plain stack of rows (not a
/// table) so every row exists and Tab walks through them in order.
final class ShortcutsSettingsViewController: NSViewController {
    private enum Row {
        case header(String)
        case action(ShortcutAction)
    }

    private let rows: [Row] = ShortcutAction.Category.allCases.flatMap { category -> [Row] in
        [.header(category.title)] +
            ShortcutAction.allCases.filter { $0.category == category }.map { .action($0) }
    }

    private let rowsStack = NSStackView()
    private var listViews: [ShortcutAction: ShortcutListView] = [:]
    private var actionRows: [ShortcutAction: NSView] = [:]
    private let statusLabel = NSTextField(labelWithString: "")
    private var storeObserver: NSObjectProtocol?

    override func loadView() {
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 620, height: 560))

        let intro = NSTextField(wrappingLabelWithString:
            "Click a shortcut to change it, + to add another, or × to remove it. " +
            "Every key can be recorded, Esc included; click elsewhere or press ⌘. to cancel. " +
            "From the keyboard: Tab to a shortcut, then Space to record or Delete to remove it.")
        intro.textColor = .secondaryLabelColor
        intro.font = .systemFont(ofSize: 12)

        rowsStack.orientation = .vertical
        rowsStack.alignment = .leading
        rowsStack.spacing = 0
        rowsStack.edgeInsets = NSEdgeInsets(top: 0, left: 20, bottom: 12, right: 12)
        rowsStack.translatesAutoresizingMaskIntoConstraints = false
        let document = FlippedView()
        document.translatesAutoresizingMaskIntoConstraints = false
        document.addSubview(rowsStack)

        let scrollView = NSScrollView()
        scrollView.documentView = document
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false
        NSLayoutConstraint.activate([
            rowsStack.topAnchor.constraint(equalTo: document.topAnchor),
            rowsStack.leadingAnchor.constraint(equalTo: document.leadingAnchor),
            rowsStack.trailingAnchor.constraint(equalTo: document.trailingAnchor),
            rowsStack.bottomAnchor.constraint(equalTo: document.bottomAnchor),
            document.topAnchor.constraint(equalTo: scrollView.contentView.topAnchor),
            document.leadingAnchor.constraint(equalTo: scrollView.contentView.leadingAnchor),
            document.widthAnchor.constraint(equalTo: scrollView.contentView.widthAnchor),
        ])

        let restore = NSButton(title: "Restore Defaults", target: self,
                               action: #selector(restoreDefaults(_:)))

        statusLabel.textColor = .secondaryLabelColor
        statusLabel.font = .systemFont(ofSize: 12)
        statusLabel.lineBreakMode = .byTruncatingTail
        statusLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        for view in [intro, scrollView, restore, statusLabel] {
            view.translatesAutoresizingMaskIntoConstraints = false
            root.addSubview(view)
        }
        NSLayoutConstraint.activate([
            intro.topAnchor.constraint(equalTo: root.topAnchor, constant: 16),
            intro.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 20),
            intro.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -20),

            scrollView.topAnchor.constraint(equalTo: intro.bottomAnchor, constant: 8),
            scrollView.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: root.trailingAnchor),

            restore.topAnchor.constraint(equalTo: scrollView.bottomAnchor, constant: 12),
            restore.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 20),
            restore.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -16),

            statusLabel.centerYAnchor.constraint(equalTo: restore.centerYAnchor),
            statusLabel.leadingAnchor.constraint(equalTo: restore.trailingAnchor, constant: 12),
            statusLabel.trailingAnchor.constraint(lessThanOrEqualTo: root.trailingAnchor, constant: -20),
        ])

        view = root
        preferredContentSize = root.frame.size

        buildRows()
        // Synchronous (no queue), so rows are updated before focus is restored.
        storeObserver = NotificationCenter.default.addObserver(
            forName: ShortcutStore.didChange, object: nil, queue: nil
        ) { [weak self] _ in
            self?.updateChangedRows()
        }
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        updateKeyViewLoop()
    }

    deinit {
        if let storeObserver { NotificationCenter.default.removeObserver(storeObserver) }
    }

    override func viewWillDisappear() {
        super.viewWillDisappear()
        ShortcutTokenView.cancelRecording()
        statusLabel.stringValue = ""
    }

    // MARK: - Editing

    private func record(_ shortcut: KeyShortcut, for action: ShortcutAction, replacing index: Int?) {
        let store = ShortcutStore.shared
        let hadFocus = focusIsInTable
        if store.isReserved(shortcut) {
            NSSound.beep()
            statusLabel.stringValue = "\(shortcut.displayString) is reserved for the system."
            return
        }
        if let owner = store.assign(shortcut, to: action, replacing: index) {
            statusLabel.stringValue = "\(shortcut.displayString) was removed from “\(owner.title)”."
        } else {
            statusLabel.stringValue = ""
        }
        let list = store.shortcuts(for: action)
        if hadFocus { restoreFocus(to: action, tokenIndex: list.firstIndex(of: shortcut) ?? list.count) }
    }

    private func remove(at index: Int, from action: ShortcutAction) {
        let hadFocus = focusIsInTable
        statusLabel.stringValue = ""
        ShortcutStore.shared.remove(at: index, from: action)
        if hadFocus { restoreFocus(to: action, tokenIndex: index) }
    }

    private func reset(_ action: ShortcutAction) {
        let hadFocus = focusIsInTable
        let touched = ShortcutStore.shared.reset(action)
        let names = touched.map { "“\($0.title)”" }.joined(separator: ", ")
        statusLabel.stringValue = touched.isEmpty ? "" :
            "Restored “\(action.title)”; its defaults were removed from \(names)."
        if hadFocus { restoreFocus(to: action, tokenIndex: 0) }
    }

    private var focusIsInTable: Bool {
        (view.window?.firstResponder as? NSView)?.isDescendant(of: rowsStack) == true
    }

    /// Rows are rebuilt after each change, which drops keyboard focus; put it
    /// back on the same action so keyboard users keep their place.
    private func restoreFocus(to action: ShortcutAction, tokenIndex: Int) {
        guard let list = listViews[action] else { return }
        view.window?.makeFirstResponder(list.token(at: tokenIndex))
    }

    /// Shortcut lists are replaced on change: relink the Tab order top to bottom,
    /// starting at the first shortcut (the tab view controller otherwise
    /// points the first Tab at a view that can't take focus).
    private func updateKeyViewLoop() {
        guard let window = view.window else { return }
        window.recalculateKeyViewLoop()
        let first = ShortcutAction.Category.allCases.first.flatMap { category in
            ShortcutAction.allCases.first { $0.category == category }
        }
        window.initialFirstResponder = first.flatMap { listViews[$0]?.token(at: 0) }
    }

    @objc private func restoreDefaults(_ sender: Any?) {
        guard let window = view.window else { return }
        let alert = NSAlert()
        alert.messageText = "Restore all shortcuts to their defaults?"
        alert.informativeText = "Your custom shortcuts will be lost."
        alert.addButton(withTitle: "Restore Defaults")
        alert.addButton(withTitle: "Cancel")
        alert.beginSheetModal(for: window) { [weak self] response in
            guard response == .alertFirstButtonReturn else { return }
            ShortcutStore.shared.resetAll()
            self?.statusLabel.stringValue = ""
        }
    }

    // MARK: - Rows

    private func buildRows() {
        for row in rows {
            let rowView = NSView()
            switch row {
            case .header(let title):
                let label = NSTextField(labelWithString: title)
                label.font = .systemFont(ofSize: 12, weight: .semibold)
                label.textColor = .secondaryLabelColor
                label.translatesAutoresizingMaskIntoConstraints = false
                rowView.addSubview(label)
                NSLayoutConstraint.activate([
                    rowView.heightAnchor.constraint(equalToConstant: rowsStack.arrangedSubviews.isEmpty ? 24 : 36),
                    label.leadingAnchor.constraint(equalTo: rowView.leadingAnchor),
                    label.bottomAnchor.constraint(equalTo: rowView.bottomAnchor, constant: -4),
                ])
            case .action(let action):
                let label = NSTextField(labelWithString: action.title)
                label.lineBreakMode = .byTruncatingTail
                label.toolTip = action.title
                label.translatesAutoresizingMaskIntoConstraints = false
                rowView.addSubview(label)
                NSLayoutConstraint.activate([
                    rowView.heightAnchor.constraint(equalToConstant: 30),
                    label.leadingAnchor.constraint(equalTo: rowView.leadingAnchor),
                    label.widthAnchor.constraint(equalToConstant: 240),
                    label.centerYAnchor.constraint(equalTo: rowView.centerYAnchor),
                ])
                actionRows[action] = rowView
                installList(for: action)
            }
            rowsStack.addArrangedSubview(rowView)
            rowView.widthAnchor.constraint(equalTo: rowsStack.widthAnchor, constant: -32).isActive = true
        }
        updateKeyViewLoop()
    }

    /// Replaces only the lists whose shortcuts changed; an edit touches one
    /// to three actions, and rebuilding every row stalls for ~100 ms.
    private func updateChangedRows() {
        let store = ShortcutStore.shared
        let changed = ShortcutAction.allCases.filter { listViews[$0]?.shortcuts != store.shortcuts(for: $0) }
        guard !changed.isEmpty else { return }
        changed.forEach(installList(for:))
        updateKeyViewLoop()
    }

    private func installList(for action: ShortcutAction) {
        guard let rowView = actionRows[action] else { return }
        listViews[action]?.removeFromSuperview()

        let list = ShortcutListView(action: action)
        list.onRecord = { [weak self] shortcut, index in
            self?.record(shortcut, for: action, replacing: index)
        }
        list.onRemove = { [weak self] index in self?.remove(at: index, from: action) }
        list.onReset = { [weak self] in self?.reset(action) }
        listViews[action] = list

        list.translatesAutoresizingMaskIntoConstraints = false
        rowView.addSubview(list)
        NSLayoutConstraint.activate([
            list.leadingAnchor.constraint(equalTo: rowView.leadingAnchor, constant: 246),
            list.trailingAnchor.constraint(equalTo: rowView.trailingAnchor),
            list.topAnchor.constraint(equalTo: rowView.topAnchor),
            list.bottomAnchor.constraint(equalTo: rowView.bottomAnchor),
        ])
    }
}

/// Borderless symbol button. Built without `NSButton(image:target:action:)`,
/// whose sizeToFit measures the symbol slowly (~5x the cost of this).
private func symbolButton(_ symbol: String, target: AnyObject, action: Selector) -> NSButton {
    let button = NSButton(frame: NSRect(x: 0, y: 0, width: 16, height: 16))
    button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
    button.imagePosition = .imageOnly
    button.isBordered = false
    button.target = target
    button.action = action
    return button
}

private final class FlippedView: NSView {
    override var isFlipped: Bool { true }
}

/// One action's shortcuts as tokens, an add token and a reset button.
private final class ShortcutListView: NSView {
    var onRecord: ((KeyShortcut, Int?) -> Void)?
    var onRemove: ((Int) -> Void)?
    var onReset: (() -> Void)?

    /// The shortcuts this list shows, to tell when it is out of date.
    let shortcuts: [KeyShortcut]
    private var tokens: [ShortcutTokenView] = []

    init(action: ShortcutAction) {
        shortcuts = ShortcutStore.shared.shortcuts(for: action)
        super.init(frame: .zero)

        tokens = shortcuts.enumerated().map { index, shortcut in
            let token = ShortcutTokenView(shortcut: shortcut, actionTitle: action.title)
            token.onRecord = { [weak self] in self?.onRecord?($0, index) }
            token.onRemove = { [weak self] in self?.onRemove?(index) }
            return token
        }
        if shortcuts.count < ShortcutStore.maxShortcutsPerAction {
            let add = ShortcutTokenView(shortcut: nil, actionTitle: action.title)
            add.toolTip = "Add a shortcut"
            add.onRecord = { [weak self] in self?.onRecord?($0, nil) }
            tokens.append(add)
        }
        let stack = NSStackView(views: tokens)
        stack.orientation = .horizontal
        stack.spacing = 6
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])

        // Only customized actions get a reset button.
        guard !ShortcutStore.shared.isDefault(action) else { return }
        let reset = symbolButton("arrow.counterclockwise", target: self, action: #selector(reset(_:)))
        reset.setAccessibilityLabel("Restore default shortcuts for \(action.title)")
        reset.contentTintColor = .secondaryLabelColor
        reset.toolTip = "Restore default"
        reset.translatesAutoresizingMaskIntoConstraints = false
        addSubview(reset)
        NSLayoutConstraint.activate([
            reset.leadingAnchor.constraint(greaterThanOrEqualTo: stack.trailingAnchor, constant: 8),
            reset.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            reset.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

    @objc private func reset(_ sender: Any?) { onReset?() }

    /// The token at `index`, clamped to the last one (the add token, if any).
    /// Never empty: with no shortcuts there is always the add token.
    func token(at index: Int) -> NSView {
        tokens[min(max(index, 0), tokens.count - 1)]
    }
}

/// A keycap that records a new shortcut when clicked, or with Space/Return
/// when focused (Delete removes it). With no shortcut it is the "+" add token.
final class ShortcutTokenView: NSView {
    var onRecord: ((KeyShortcut) -> Void)?
    var onRemove: (() -> Void)?

    private let shortcut: KeyShortcut?
    private let actionTitle: String
    private let label = NSTextField(labelWithString: "")
    private var isRecording = false
    private var keyMonitor: Any?
    private var mouseMonitor: Any?
    private var resignObserver: NSObjectProtocol?

    private static weak var recording: ShortcutTokenView?

    static func cancelRecording() {
        recording?.stopRecording()
    }

    private static let cancelShortcut = KeyShortcut(".", .command)

    init(shortcut: KeyShortcut?, actionTitle: String) {
        self.shortcut = shortcut
        self.actionTitle = actionTitle
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 5
        layer?.borderWidth = 1

        label.font = shortcut == nil ? .systemFont(ofSize: 13, weight: .medium)
                                     : .systemFont(ofSize: 12, weight: .medium)
        label.alignment = .center

        let stack = NSStackView(views: [label])
        stack.orientation = .horizontal
        stack.spacing = 2
        stack.edgeInsets = NSEdgeInsets(top: 0, left: 8, bottom: 0, right: shortcut == nil ? 8 : 4)
        if shortcut != nil {
            let remove = symbolButton("xmark.circle.fill", target: self, action: #selector(remove(_:)))
            remove.imageScaling = .scaleProportionallyDown
            remove.contentTintColor = .tertiaryLabelColor
            remove.toolTip = "Remove shortcut"
            remove.setAccessibilityLabel("Remove shortcut \(shortcut!.displayString) for \(actionTitle)")
            remove.widthAnchor.constraint(equalToConstant: 14).isActive = true
            remove.heightAnchor.constraint(equalToConstant: 14).isActive = true
            stack.addArrangedSubview(remove)
        }
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
            heightAnchor.constraint(equalToConstant: 22),
            widthAnchor.constraint(greaterThanOrEqualToConstant: shortcut == nil ? 28 : 44),
        ])
        refresh()
    }

    required init?(coder: NSCoder) { fatalError() }

    deinit {
        removeMonitors()
    }

    override var wantsUpdateLayer: Bool { true }

    override func updateLayer() {
        layer?.backgroundColor = (isRecording ? NSColor.controlAccentColor.withAlphaComponent(0.15)
                                              : NSColor.quaternaryLabelColor).cgColor
        layer?.borderColor = (isRecording ? NSColor.controlAccentColor : NSColor.clear).cgColor
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil { stopRecording() }
    }

    // MARK: - Keyboard

    /// Focusable from the keyboard only, like buttons: a click records
    /// without leaving a focus ring behind.
    override var acceptsFirstResponder: Bool {
        NSApp.currentEvent.map { ![.leftMouseDown, .rightMouseDown].contains($0.type) } ?? true
    }
    override var canBecomeKeyView: Bool { true }
    override var focusRingMaskBounds: NSRect { bounds }

    override func drawFocusRingMask() {
        NSBezierPath(roundedRect: bounds, xRadius: 5, yRadius: 5).fill()
    }

    override func becomeFirstResponder() -> Bool {
        scrollToVisible(bounds.insetBy(dx: 0, dy: -8))
        return true
    }

    override func keyDown(with event: NSEvent) {
        let plain = event.modifierFlags.intersection(KeyShortcut.relevantModifiers).isEmpty
        if plain, [49, 36, 76].contains(event.keyCode) { // space, return, enter
            startRecording()
        } else if plain, shortcut != nil, [51, 117].contains(event.keyCode) { // delete, forward delete
            onRemove?()
        } else {
            super.keyDown(with: event)
        }
    }

    // MARK: - Accessibility

    override func isAccessibilityElement() -> Bool { true }
    override func accessibilityRole() -> NSAccessibility.Role? { .button }

    override func accessibilityLabel() -> String? {
        if let shortcut { return "\(actionTitle) shortcut \(shortcut.displayString)" }
        return "Add shortcut for \(actionTitle)"
    }

    override func accessibilityValue() -> Any? {
        isRecording ? "Recording, type the new shortcut" : nil
    }

    override func accessibilityHelp() -> String? {
        shortcut == nil ? "Records an additional shortcut." :
            "Records a replacement shortcut. Press Delete to remove it."
    }

    override func accessibilityPerformPress() -> Bool {
        isRecording ? stopRecording() : startRecording()
        return true
    }

    // MARK: - Mouse

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard let hit = super.hitTest(point) else { return nil }
        return hit is NSButton ? hit : self
    }

    override func mouseDown(with event: NSEvent) {
        isRecording ? stopRecording() : startRecording()
    }

    @objc private func remove(_ sender: Any?) {
        stopRecording()
        onRemove?()
    }

    private func refresh() {
        if isRecording {
            label.stringValue = shortcut == nil ? "Type shortcut…" : "Type new shortcut…"
            label.textColor = .secondaryLabelColor
        } else {
            label.stringValue = shortcut?.displayString ?? "+"
            label.textColor = shortcut == nil ? .secondaryLabelColor : .labelColor
        }
        needsDisplay = true
    }

    private func startRecording() {
        Self.recording?.stopRecording()
        Self.recording = self
        isRecording = true
        refresh()
        NSAccessibility.post(element: self, notification: .valueChanged)

        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, event.window === self.window else { return event }
            guard let shortcut = KeyShortcut(event: event) else {
                NSSound.beep()
                return nil
            }
            self.stopRecording()
            if shortcut == Self.cancelShortcut { return nil }
            // ⌘Q, ⌘W… keep working: hand them to the menu instead of recording.
            if ShortcutStore.shared.isReserved(shortcut) { return event }
            self.onRecord?(shortcut)
            return nil
        }
        mouseMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]
        ) { [weak self] event in
            guard let self else { return event }
            let inside = event.window === self.window &&
                self.bounds.contains(self.convert(event.locationInWindow, from: nil))
            if !inside { self.stopRecording() }
            return event
        }
        resignObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didResignKeyNotification, object: window, queue: .main
        ) { [weak self] _ in
            self?.stopRecording()
        }
    }

    private func stopRecording() {
        guard isRecording else { return }
        isRecording = false
        if Self.recording === self { Self.recording = nil }
        removeMonitors()
        refresh()
        NSAccessibility.post(element: self, notification: .valueChanged)
    }

    private func removeMonitors() {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        if let mouseMonitor { NSEvent.removeMonitor(mouseMonitor) }
        if let resignObserver { NotificationCenter.default.removeObserver(resignObserver) }
        keyMonitor = nil
        mouseMonitor = nil
        resignObserver = nil
    }
}
