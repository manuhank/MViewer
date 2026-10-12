import AppKit

/// A key plus modifier flags. `key` is the character the key types on the
/// current keyboard layout (lowercased), or a name for non-printing keys
/// ("left", "space"…), so bindings follow the layout like menu key equivalents.
struct KeyShortcut: Codable, Hashable {
    let key: String
    let modifiers: UInt

    static let relevantModifiers: NSEvent.ModifierFlags = [.control, .option, .shift, .command]

    init(_ key: String, _ modifiers: NSEvent.ModifierFlags = []) {
        self.key = key
        self.modifiers = modifiers.intersection(Self.relevantModifiers).rawValue
    }

    /// Nil when the event has no usable key (bare modifiers, dead keys…).
    init?(event: NSEvent) {
        var flags = event.modifierFlags.intersection(Self.relevantModifiers)
        if let special = Self.specialKeys[event.keyCode] {
            self.init(special.name, flags)
            return
        }
        guard let chars = event.charactersIgnoringModifiers?.lowercased(),
              chars.count == 1, let scalar = chars.unicodeScalars.first,
              scalar.value >= 0x20, scalar.value != 0x7F,
              !(0xF700...0xF8FF).contains(scalar.value) else { return nil }
        // Shift already shaped a non-letter ("?" is ⇧/), so it isn't part of the binding.
        if flags.contains(.shift), chars.uppercased() == chars {
            flags.remove(.shift)
        }
        self.init(chars, flags)
    }

    var modifierFlags: NSEvent.ModifierFlags { NSEvent.ModifierFlags(rawValue: modifiers) }

    var displayString: String {
        let flags = modifierFlags
        var out = ""
        if flags.contains(.control) { out += "⌃" }
        if flags.contains(.option) { out += "⌥" }
        if flags.contains(.shift) { out += "⇧" }
        if flags.contains(.command) { out += "⌘" }
        return out + (Self.specialKey(named: key)?.display ?? key.uppercased())
    }

    var menuKeyEquivalent: String {
        Self.specialKey(named: key)?.menu ?? key
    }

    // MARK: - Non-printing keys

    private struct SpecialKey {
        let name: String
        let display: String
        let menu: String
    }

    private static func function(_ code: Int) -> String { String(UnicodeScalar(code)!) }

    private static let specialKeys: [UInt16: SpecialKey] = {
        var keys: [UInt16: SpecialKey] = [
            123: SpecialKey(name: "left", display: "←", menu: function(NSLeftArrowFunctionKey)),
            124: SpecialKey(name: "right", display: "→", menu: function(NSRightArrowFunctionKey)),
            125: SpecialKey(name: "down", display: "↓", menu: function(NSDownArrowFunctionKey)),
            126: SpecialKey(name: "up", display: "↑", menu: function(NSUpArrowFunctionKey)),
            49: SpecialKey(name: "space", display: "Space", menu: " "),
            53: SpecialKey(name: "escape", display: "Esc", menu: "\u{1b}"),
            51: SpecialKey(name: "delete", display: "⌫", menu: "\u{8}"),
            117: SpecialKey(name: "forwardDelete", display: "⌦", menu: function(NSDeleteFunctionKey)),
            36: SpecialKey(name: "return", display: "↩", menu: "\r"),
            76: SpecialKey(name: "enter", display: "⌤", menu: "\u{3}"),
            48: SpecialKey(name: "tab", display: "⇥", menu: "\t"),
            115: SpecialKey(name: "home", display: "↖", menu: function(NSHomeFunctionKey)),
            119: SpecialKey(name: "end", display: "↘", menu: function(NSEndFunctionKey)),
            116: SpecialKey(name: "pageUp", display: "⇞", menu: function(NSPageUpFunctionKey)),
            121: SpecialKey(name: "pageDown", display: "⇟", menu: function(NSPageDownFunctionKey)),
        ]
        let fKeyCodes: [UInt16] = [122, 120, 99, 118, 96, 97, 98, 100, 101, 109, 103, 111]
        for (index, code) in fKeyCodes.enumerated() {
            keys[code] = SpecialKey(name: "f\(index + 1)", display: "F\(index + 1)",
                                    menu: function(NSF1FunctionKey + index))
        }
        return keys
    }()

    private static let specialKeysByName: [String: SpecialKey] =
        Dictionary(uniqueKeysWithValues: specialKeys.values.map { ($0.name, $0) })

    private static func specialKey(named name: String) -> SpecialKey? { specialKeysByName[name] }
}

/// Every action whose keyboard shortcuts can be customized in Settings.
enum ShortcutAction: String, CaseIterable {
    case previousFile, nextFile, playPause
    case toggleFullScreen, zoomToFit, actualSize, zoomIn, zoomOut, toggle360, getInfo
    case openFile, copyImage, showInFinder, moveToTrash
    case showShortcuts, showAbout, exitOrClose

    enum Category: CaseIterable {
        case navigation, view, file, general

        var title: String {
            switch self {
            case .navigation: return "Navigation"
            case .view: return "View"
            case .file: return "File"
            case .general: return "General"
            }
        }
    }

    var category: Category {
        switch self {
        case .previousFile, .nextFile, .playPause: return .navigation
        case .toggleFullScreen, .zoomToFit, .actualSize, .zoomIn, .zoomOut, .toggle360, .getInfo:
            return .view
        case .openFile, .copyImage, .showInFinder, .moveToTrash: return .file
        case .showShortcuts, .showAbout, .exitOrClose: return .general
        }
    }

    var title: String {
        switch self {
        case .previousFile: return "Previous file"
        case .nextFile: return "Next file"
        case .playPause: return "Play / pause video (next file for images)"
        case .toggleFullScreen: return "Full screen"
        case .zoomToFit: return "Zoom to fit"
        case .actualSize: return "Actual size (pixel-perfect)"
        case .zoomIn: return "Zoom in"
        case .zoomOut: return "Zoom out"
        case .toggle360: return "Toggle 360° video view"
        case .getInfo: return "Info sidebar"
        case .openFile: return "Open…"
        case .copyImage: return "Copy image"
        case .showInFinder: return "Show in Finder"
        case .moveToTrash: return "Move to Trash"
        case .showShortcuts: return "Keyboard shortcuts help"
        case .showAbout: return "About / version"
        case .exitOrClose: return "Exit full screen / close window"
        }
    }

    /// The first default with a modifier is the one shown in the menu bar.
    var defaultShortcuts: [KeyShortcut] {
        switch self {
        case .previousFile: return [KeyShortcut("left"), KeyShortcut("up")]
        case .nextFile: return [KeyShortcut("right"), KeyShortcut("down")]
        case .playPause: return [KeyShortcut("space")]
        case .toggleFullScreen: return [KeyShortcut("f", [.control, .command]), KeyShortcut("f")]
        case .zoomToFit: return [KeyShortcut("0", .command), KeyShortcut("0")]
        case .actualSize: return [KeyShortcut("1", .command), KeyShortcut("1")]
        case .zoomIn: return [KeyShortcut("+", .command), KeyShortcut("=", .command)]
        case .zoomOut: return [KeyShortcut("-", .command)]
        case .toggle360: return [KeyShortcut("3")]
        case .getInfo: return [KeyShortcut("i", .command)]
        case .openFile: return [KeyShortcut("o", .command)]
        case .copyImage: return [KeyShortcut("c", .command)]
        case .showInFinder: return []
        case .moveToTrash: return [KeyShortcut("delete", .command)]
        case .showShortcuts: return [KeyShortcut("/", .command), KeyShortcut("h"), KeyShortcut("?")]
        case .showAbout: return [KeyShortcut("a")]
        case .exitOrClose: return [KeyShortcut("escape")]
        }
    }
}

/// Current shortcut bindings. Only customized actions are persisted, so
/// untouched actions pick up new defaults in later versions.
final class ShortcutStore {
    static let shared = ShortcutStore()
    static let didChange = Notification.Name("ShortcutStoreDidChange")
    static let maxShortcutsPerAction = 4

    private static let defaultsKey = "KeyboardShortcuts"

    /// Standard app/window shortcuts that stay owned by the menu bar.
    private static let reserved: Set<KeyShortcut> = [
        KeyShortcut("q", .command), KeyShortcut("h", .command), KeyShortcut("h", [.option, .command]),
        KeyShortcut("w", .command), KeyShortcut("m", .command), KeyShortcut(",", .command),
    ]

    private var bindings: [ShortcutAction: [KeyShortcut]] = [:]

    /// Decodes one saved shortcut, so a bad entry doesn't discard the rest.
    private struct LossyShortcut: Decodable {
        let value: KeyShortcut?

        init(from decoder: Decoder) throws {
            value = try? KeyShortcut(from: decoder)
        }
    }

    private init() {
        var saved: [String: [LossyShortcut]] = [:]
        if let data = UserDefaults.standard.data(forKey: Self.defaultsKey),
           let decoded = try? JSONDecoder().decode([String: [LossyShortcut]].self, from: data) {
            saved = decoded
        }

        // Customized actions claim their shortcuts first, so a default added in
        // a later version never duplicates a shortcut the user picked.
        var claimed = Set<KeyShortcut>()
        for action in ShortcutAction.allCases {
            guard let entries = saved[action.rawValue] else { continue }
            let list = entries.compactMap(\.value)
                .map { KeyShortcut($0.key, $0.modifierFlags) }
                .filter { !$0.key.isEmpty && !Self.reserved.contains($0) && claimed.insert($0).inserted }
            bindings[action] = Array(list.prefix(Self.maxShortcutsPerAction))
        }
        for action in ShortcutAction.allCases where bindings[action] == nil {
            bindings[action] = action.defaultShortcuts.filter { claimed.insert($0).inserted }
        }
    }

    func shortcuts(for action: ShortcutAction) -> [KeyShortcut] {
        bindings[action] ?? []
    }

    func isDefault(_ action: ShortcutAction) -> Bool {
        shortcuts(for: action) == action.defaultShortcuts
    }

    func isReserved(_ shortcut: KeyShortcut) -> Bool {
        Self.reserved.contains(shortcut)
    }

    func action(for shortcut: KeyShortcut) -> ShortcutAction? {
        ShortcutAction.allCases.first { shortcuts(for: $0).contains(shortcut) }
    }

    /// Exact match first; otherwise Shift alone is ignored, so ⇧← still goes
    /// back unless ⇧← has a binding of its own.
    func action(matching event: NSEvent) -> ShortcutAction? {
        guard let shortcut = KeyShortcut(event: event) else { return nil }
        if let action = action(for: shortcut) { return action }
        guard shortcut.modifierFlags == .shift else { return nil }
        return action(for: KeyShortcut(shortcut.key))
    }

    /// Binds `shortcut` to `action`, replacing the shortcut at `index` or
    /// appending. A shortcut belongs to one action only: returns the action it
    /// was taken from, if any.
    @discardableResult
    func assign(_ shortcut: KeyShortcut, to action: ShortcutAction,
                replacing index: Int? = nil) -> ShortcutAction? {
        let previousOwner = takeAway([shortcut], except: action).first
        var list = shortcuts(for: action)
        if let index, list.indices.contains(index) {
            list[index] = shortcut
        } else {
            list.append(shortcut)
        }
        var seen = Set<KeyShortcut>()
        bindings[action] = list.filter { seen.insert($0).inserted }
        commit()
        return previousOwner
    }

    func remove(at index: Int, from action: ShortcutAction) {
        guard var list = bindings[action], list.indices.contains(index) else { return }
        list.remove(at: index)
        bindings[action] = list
        commit()
    }

    func reset(_ action: ShortcutAction) {
        takeAway(action.defaultShortcuts, except: action)
        bindings[action] = action.defaultShortcuts
        commit()
    }

    func resetAll() {
        for action in ShortcutAction.allCases {
            bindings[action] = action.defaultShortcuts
        }
        commit()
    }

    /// Removes `shortcuts` from every action but `keeper`; returns the actions touched.
    @discardableResult
    private func takeAway(_ shortcuts: [KeyShortcut], except keeper: ShortcutAction) -> [ShortcutAction] {
        var touched: [ShortcutAction] = []
        for other in ShortcutAction.allCases where other != keeper {
            let list = self.shortcuts(for: other)
            let kept = list.filter { !shortcuts.contains($0) }
            if kept.count != list.count {
                bindings[other] = kept
                touched.append(other)
            }
        }
        return touched
    }

    private func commit() {
        var custom: [String: [KeyShortcut]] = [:]
        for action in ShortcutAction.allCases where !isDefault(action) {
            custom[action.rawValue] = shortcuts(for: action)
        }
        if custom.isEmpty {
            UserDefaults.standard.removeObject(forKey: Self.defaultsKey)
        } else if let data = try? JSONEncoder().encode(custom) {
            UserDefaults.standard.set(data, forKey: Self.defaultsKey)
        }
        NotificationCenter.default.post(name: Self.didChange, object: self)
    }
}

extension NSMenuItem {
    /// Shows the action's first shortcut with a modifier (usable from any
    /// window), else its first shortcut, or none.
    func applyShortcut(of action: ShortcutAction) {
        let shortcuts = ShortcutStore.shared.shortcuts(for: action)
        let modified = shortcuts.first { !$0.modifierFlags.isDisjoint(with: [.command, .control, .option]) }
        if let shortcut = modified ?? shortcuts.first {
            keyEquivalent = shortcut.menuKeyEquivalent
            keyEquivalentModifierMask = shortcut.modifierFlags
        } else {
            keyEquivalent = ""
            keyEquivalentModifierMask = []
        }
    }
}
