import AppKit
import UniformTypeIdentifiers

final class AppDelegate: NSObject, NSApplicationDelegate {
    let viewer = ViewerWindowController()
    private var openedSomething = false

    func applicationWillFinishLaunching(_ notification: Notification) {
        NSApp.mainMenu = buildMenu()
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        openedSomething = true
        viewer.open(urls: urls)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)

        let cliURLs = CommandLine.arguments.dropFirst()
            .filter { !$0.hasPrefix("-") }
            .map { URL(fileURLWithPath: ($0 as NSString).expandingTildeInPath) }
            .filter { FileManager.default.fileExists(atPath: $0.path) }
        if !cliURLs.isEmpty {
            openedSomething = true
            viewer.open(urls: cliURLs)
        }

        // Give a launch-time open event a beat to arrive before showing the panel.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            guard let self, !self.openedSomething else { return }
            NSApp.activate(ignoringOtherApps: true)
            self.openDocument(nil)
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    @objc func openDocument(_ sender: Any?) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image, .movie, .folder]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = true
        guard panel.runModal() == .OK, !panel.urls.isEmpty else { return }
        openedSomething = true
        viewer.open(urls: panel.urls)
    }

    // MARK: - Menu

    private func buildMenu() -> NSMenu {
        let main = NSMenu()

        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "About MViewer",
                        action: #selector(ViewerWindowController.showAbout(_:)),
                        keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Hide MViewer",
                        action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Quit MViewer",
                        action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        main.addItem(submenu(appMenu, title: "MViewer"))

        let fileMenu = NSMenu(title: "File")
        fileMenu.addItem(withTitle: "Open…",
                         action: #selector(AppDelegate.openDocument(_:)), keyEquivalent: "o")
        fileMenu.addItem(.separator())
        fileMenu.addItem(withTitle: "Copy Image",
                         action: #selector(ViewerWindowController.copyImage(_:)), keyEquivalent: "c")
        fileMenu.addItem(withTitle: "Show in Finder",
                         action: #selector(ViewerWindowController.showInFinder(_:)), keyEquivalent: "")
        fileMenu.addItem(withTitle: "Get Info",
                         action: #selector(ViewerWindowController.getInfo(_:)), keyEquivalent: "i")
        fileMenu.addItem(.separator())
        let trash = fileMenu.addItem(withTitle: "Move to Trash",
                                     action: #selector(ViewerWindowController.moveToTrash(_:)),
                                     keyEquivalent: "\u{8}")
        trash.keyEquivalentModifierMask = [.command]
        fileMenu.addItem(.separator())
        fileMenu.addItem(withTitle: "Close Window",
                         action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        main.addItem(submenu(fileMenu, title: "File"))

        let viewMenu = NSMenu(title: "View")
        viewMenu.addItem(withTitle: "Zoom In",
                         action: #selector(ViewerWindowController.zoomIn(_:)), keyEquivalent: "+")
        viewMenu.addItem(withTitle: "Zoom Out",
                         action: #selector(ViewerWindowController.zoomOut(_:)), keyEquivalent: "-")
        viewMenu.addItem(withTitle: "Zoom to Fit",
                         action: #selector(ViewerWindowController.zoomToFit(_:)), keyEquivalent: "0")
        viewMenu.addItem(withTitle: "Actual Size",
                         action: #selector(ViewerWindowController.actualSize(_:)), keyEquivalent: "1")
        viewMenu.addItem(.separator())
        let thumbnails = viewMenu.addItem(withTitle: "Hide Thumbnails",
                                          action: #selector(ViewerWindowController.toggleThumbnails(_:)),
                                          keyEquivalent: "t")
        thumbnails.keyEquivalentModifierMask = [.option, .command]
        let fullscreen = viewMenu.addItem(withTitle: "Enter Full Screen",
                                          action: #selector(NSWindow.toggleFullScreen(_:)),
                                          keyEquivalent: "f")
        fullscreen.keyEquivalentModifierMask = [.command, .control]
        main.addItem(submenu(viewMenu, title: "View"))

        let goMenu = NSMenu(title: "Go")
        let next = goMenu.addItem(withTitle: "Next",
                                  action: #selector(ViewerWindowController.nextFile(_:)),
                                  keyEquivalent: String(UnicodeScalar(NSRightArrowFunctionKey)!))
        next.keyEquivalentModifierMask = []
        let prev = goMenu.addItem(withTitle: "Previous",
                                  action: #selector(ViewerWindowController.previousFile(_:)),
                                  keyEquivalent: String(UnicodeScalar(NSLeftArrowFunctionKey)!))
        prev.keyEquivalentModifierMask = []
        main.addItem(submenu(goMenu, title: "Go"))

        let windowMenu = NSMenu(title: "Window")
        windowMenu.addItem(withTitle: "Minimize",
                           action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        main.addItem(submenu(windowMenu, title: "Window"))
        NSApp.windowsMenu = windowMenu

        let helpMenu = NSMenu(title: "Help")
        helpMenu.addItem(withTitle: "Keyboard Shortcuts",
                         action: #selector(ViewerWindowController.showShortcuts(_:)),
                         keyEquivalent: "/")
        main.addItem(submenu(helpMenu, title: "Help"))
        NSApp.helpMenu = helpMenu

        return main
    }

    private func submenu(_ menu: NSMenu, title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.submenu = menu
        return item
    }
}
