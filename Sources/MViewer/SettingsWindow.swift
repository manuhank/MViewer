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
/// re-record it, + to add one, × to remove one.
final class ShortcutsSettingsViewController: NSViewController, NSTableViewDataSource, NSTableViewDelegate {
    private enum Row {
        case header(String)
        case action(ShortcutAction)
    }

    private let rows: [Row] = ShortcutAction.Category.allCases.flatMap { category -> [Row] in
        [.header(category.title)] +
            ShortcutAction.allCases.filter { $0.category == category }.map { .action($0) }
    }

    private let tableView = NSTableView()
    private let statusLabel = NSTextField(labelWithString: "")
    private var storeObserver: NSObjectProtocol?

    override func loadView() {
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 620, height: 560))

        let intro = NSTextField(wrappingLabelWithString:
            "Click a shortcut to change it, + to add another, or × to remove it. " +
            "Press Esc to cancel recording.")
        intro.textColor = .secondaryLabelColor
        intro.font = .systemFont(ofSize: 12)

        let actionColumn = NSTableColumn(identifier: .init("action"))
        actionColumn.width = 250
        actionColumn.minWidth = 200
        let shortcutsColumn = NSTableColumn(identifier: .init("shortcuts"))
        shortcutsColumn.minWidth = 260
        tableView.addTableColumn(actionColumn)
        tableView.addTableColumn(shortcutsColumn)
        tableView.headerView = nil
        tableView.style = .inset
        tableView.rowHeight = 30
        tableView.floatsGroupRows = false
        tableView.selectionHighlightStyle = .none
        tableView.columnAutoresizingStyle = .lastColumnOnlyAutoresizingStyle
        tableView.dataSource = self
        tableView.delegate = self

        let scrollView = NSScrollView()
        scrollView.documentView = tableView
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false

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

        storeObserver = NotificationCenter.default.addObserver(
            forName: ShortcutStore.didChange, object: nil, queue: .main
        ) { [weak self] _ in
            self?.tableView.reloadData()
        }
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
        if store.isReserved(shortcut) {
            NSSound.beep()
            statusLabel.stringValue = "\(shortcut.displayString) is reserved by macOS."
            return
        }
        if let owner = store.assign(shortcut, to: action, replacing: index) {
            statusLabel.stringValue = "\(shortcut.displayString) was removed from “\(owner.title)”."
        } else {
            statusLabel.stringValue = ""
        }
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

    // MARK: - Table

    func numberOfRows(in tableView: NSTableView) -> Int { rows.count }

    func tableView(_ tableView: NSTableView, isGroupRow row: Int) -> Bool {
        if case .header = rows[row] { return true }
        return false
    }

    func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool { false }

    func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
        if case .header = rows[row] { return 26 }
        return 30
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        switch rows[row] {
        case .header(let title):
            let label = NSTextField(labelWithString: title)
            label.font = .systemFont(ofSize: 12, weight: .semibold)
            label.textColor = .secondaryLabelColor
            return cell(containing: label)
        case .action(let action):
            if tableColumn?.identifier.rawValue == "action" {
                let label = NSTextField(labelWithString: action.title)
                label.lineBreakMode = .byTruncatingTail
                label.toolTip = action.title
                return cell(containing: label)
            }
            let list = ShortcutListView(action: action)
            list.onRecord = { [weak self] shortcut, index in
                self?.record(shortcut, for: action, replacing: index)
            }
            list.onRemove = { [weak self] index in
                self?.statusLabel.stringValue = ""
                ShortcutStore.shared.remove(at: index, from: action)
            }
            list.onReset = { [weak self] in
                self?.statusLabel.stringValue = ""
                ShortcutStore.shared.reset(action)
            }
            return list
        }
    }

    private func cell(containing label: NSTextField) -> NSView {
        let cell = NSTableCellView()
        label.translatesAutoresizingMaskIntoConstraints = false
        cell.addSubview(label)
        cell.textField = label
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 4),
            label.trailingAnchor.constraint(lessThanOrEqualTo: cell.trailingAnchor, constant: -4),
            label.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
        ])
        return cell
    }
}

/// One action's shortcuts as tokens, an add token and a reset button.
private final class ShortcutListView: NSView {
    var onRecord: ((KeyShortcut, Int?) -> Void)?
    var onRemove: ((Int) -> Void)?
    var onReset: (() -> Void)?

    init(action: ShortcutAction) {
        super.init(frame: .zero)
        let shortcuts = ShortcutStore.shared.shortcuts(for: action)

        var tokens: [NSView] = shortcuts.enumerated().map { index, shortcut in
            let token = ShortcutTokenView(shortcut: shortcut)
            token.onRecord = { [weak self] in self?.onRecord?($0, index) }
            token.onRemove = { [weak self] in self?.onRemove?(index) }
            return token
        }
        if shortcuts.count < ShortcutStore.maxShortcutsPerAction {
            let add = ShortcutTokenView(shortcut: nil)
            add.toolTip = "Add a shortcut"
            add.onRecord = { [weak self] in self?.onRecord?($0, nil) }
            tokens.append(add)
        }
        let stack = NSStackView(views: tokens)
        stack.orientation = .horizontal
        stack.spacing = 6
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        let reset = NSButton(image: NSImage(systemSymbolName: "arrow.counterclockwise",
                                            accessibilityDescription: "Restore default")!,
                             target: self, action: #selector(reset(_:)))
        reset.isBordered = false
        reset.contentTintColor = .secondaryLabelColor
        reset.toolTip = "Restore default"
        reset.isHidden = ShortcutStore.shared.isDefault(action)
        reset.translatesAutoresizingMaskIntoConstraints = false
        addSubview(reset)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
            reset.leadingAnchor.constraint(greaterThanOrEqualTo: stack.trailingAnchor, constant: 8),
            reset.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            reset.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

    @objc private func reset(_ sender: Any?) { onReset?() }
}

/// A clickable keycap that records a new shortcut. With no shortcut it is
/// the "+" add token.
final class ShortcutTokenView: NSView {
    var onRecord: ((KeyShortcut) -> Void)?
    var onRemove: (() -> Void)?

    private let shortcut: KeyShortcut?
    private let label = NSTextField(labelWithString: "")
    private var isRecording = false
    private var keyMonitor: Any?
    private var mouseMonitor: Any?
    private var resignObserver: NSObjectProtocol?

    private static weak var recording: ShortcutTokenView?

    static func cancelRecording() {
        recording?.stopRecording()
    }

    init(shortcut: KeyShortcut?) {
        self.shortcut = shortcut
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
            let remove = NSButton(image: NSImage(systemSymbolName: "xmark.circle.fill",
                                                 accessibilityDescription: "Remove shortcut")!,
                                  target: self, action: #selector(remove(_:)))
            remove.isBordered = false
            remove.imageScaling = .scaleProportionallyDown
            remove.contentTintColor = .tertiaryLabelColor
            remove.toolTip = "Remove shortcut"
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

        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, event.window === self.window else { return event }
            if event.keyCode == 53,
               event.modifierFlags.intersection(KeyShortcut.relevantModifiers).isEmpty {
                self.stopRecording()
            } else if let shortcut = KeyShortcut(event: event) {
                self.stopRecording()
                self.onRecord?(shortcut)
            } else {
                NSSound.beep()
            }
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
