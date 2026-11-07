import AppKit
import ServiceManagement

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    static private(set) var shared: AppDelegate?

    private var statusItem: NSStatusItem!

    func applicationDidFinishLaunching(_ notification: Notification) {
        AppDelegate.shared = self
        NSApp.setActivationPolicy(.accessory)

        buildStatusItem()

        HotKeyCenter.shared.onTrigger = {
            PopupController.shared.toggle()
        }
        HotKeyCenter.shared.start()
        ClipboardMonitor.shared.start()

        if !Paster.isTrusted {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                // Triggers the system dialog. That dialog — and nothing else —
                // registers the app in the Accessibility list with the code hash of
                // the binary now running. Ticking a stale entry does not do it.
                Paster.requestTrust()
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        ClipboardMonitor.shared.stop()
    }

    /// Relaunching the app while it is already running (double-click in the
    /// Finder, click on the Dock icon) simply opens the history.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        PopupController.shared.show()
        return true
    }

    // MARK: - Menu bar icon

    private func buildStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            let image = NSImage(systemSymbolName: "doc.on.clipboard", accessibilityDescription: "MultiPasty")
            image?.isTemplate = true
            button.image = image
        }
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        let open = NSMenuItem(title: L.t("Open history", "Ouvrir l'historique"),
                              action: #selector(openPopup), keyEquivalent: "")
        open.target = self
        menu.addItem(open)

        let count = HistoryStore.shared.items.count
        let n = L.count(count, en: "item", fr: "élément")
        let info = NSMenuItem(title: L.t("\(n) · shortcut \(HotKeyCenter.shared.current.label)",
                                         "\(n) · raccourci \(HotKeyCenter.shared.current.label)"),
                              action: nil, keyEquivalent: "")
        info.isEnabled = false
        menu.addItem(info)

        let trusted = Paster.isTrusted
        let status = NSMenuItem(title: trusted
                                    ? L.t("Accessibility: granted ✓", "Accessibilité : autorisée ✓")
                                    : L.t("Accessibility: NOT granted — click here",
                                          "Accessibilité : NON autorisée — cliquez ici"),
                                action: trusted ? nil : #selector(fixAccessibility),
                                keyEquivalent: "")
        status.target = trusted ? nil : self
        status.isEnabled = !trusted
        menu.addItem(status)

        menu.addItem(.separator())

        // Shortcut choice
        let shortcutItem = NSMenuItem(title: L.t("Global shortcut", "Raccourci global"),
                                      action: nil, keyEquivalent: "")
        let shortcutMenu = NSMenu()
        for (idx, preset) in HotKeyCenter.presets.enumerated() {
            let item = NSMenuItem(title: preset.label, action: #selector(selectShortcut(_:)), keyEquivalent: "")
            item.target = self
            item.tag = idx
            item.state = (HotKeyCenter.shared.currentPresetIndex == idx) ? .on : .off
            shortcutMenu.addItem(item)
        }
        shortcutItem.submenu = shortcutMenu
        menu.addItem(shortcutItem)

        // History size
        let sizeItem = NSMenuItem(title: L.t("Items kept", "Éléments conservés"),
                                  action: nil, keyEquivalent: "")
        let sizeMenu = NSMenu()
        for n in [10, 15, 20, 30, 50, 100] {
            let item = NSMenuItem(title: "\(n)", action: #selector(selectMaxItems(_:)), keyEquivalent: "")
            item.target = self
            item.tag = n
            item.state = (HistoryStore.shared.maxItems == n) ? .on : .off
            sizeMenu.addItem(item)
        }
        sizeItem.submenu = sizeMenu
        menu.addItem(sizeItem)

        let login = NSMenuItem(title: L.t("Launch at login", "Lancer au démarrage"),
                               action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
        login.target = self
        login.state = isLaunchAtLoginEnabled ? .on : .off
        menu.addItem(login)

        menu.addItem(.separator())

        let clear = NSMenuItem(title: L.t("Clear history", "Vider l'historique"),
                               action: #selector(clearHistory), keyEquivalent: "")
        clear.target = self
        menu.addItem(clear)

        menu.addItem(.separator())

        let quit = NSMenuItem(title: L.t("Quit MultiPasty", "Quitter MultiPasty"),
                              action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
    }

    // MARK: - Actions

    @objc private func openPopup() {
        PopupController.shared.show()
    }

    @objc private func selectShortcut(_ sender: NSMenuItem) {
        HotKeyCenter.shared.selectPreset(sender.tag)
    }

    @objc private func selectMaxItems(_ sender: NSMenuItem) {
        HistoryStore.shared.maxItems = sender.tag
    }

    @objc private func clearHistory() {
        let alert = NSAlert()
        alert.messageText = L.t("Clear the clipboard history?", "Vider l'historique du presse-papiers ?")
        alert.informativeText = L.t("Pinned items are kept.", "Les éléments épinglés seront conservés.")
        alert.addButton(withTitle: L.t("Clear", "Vider"))
        let cancel = alert.addButton(withTitle: L.t("Cancel", "Annuler"))
        cancel.keyEquivalent = "\u{1b}"
        alert.alertStyle = .warning
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn {
            HistoryStore.shared.clearAll(keepPinned: true)
        }
    }

    @objc private func openAccessibility() {
        Paster.openAccessibilitySettings()
    }

    /// Registers the app with the system again, then opens the Accessibility pane.
    /// If a stale "MultiPasty" entry is already in the list, remove it with the
    /// "−" button before switching the new one on.
    @objc private func fixAccessibility() {
        Paster.requestTrust()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            Paster.openAccessibilitySettings()
        }
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    // MARK: - Launch at login

    private var isLaunchAtLoginEnabled: Bool {
        if #available(macOS 13.0, *) {
            return SMAppService.mainApp.status == .enabled
        }
        return false
    }

    @objc private func toggleLaunchAtLogin() {
        guard #available(macOS 13.0, *) else { return }
        do {
            if isLaunchAtLoginEnabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            let alert = NSAlert()
            alert.messageText = L.t("Could not change the launch-at-login setting",
                                    "Impossible de modifier le lancement au démarrage")
            alert.informativeText = error.localizedDescription
            alert.runModal()
        }
    }

    // MARK: - Accessibility permission

    private var accessibilityAlertShown = false

    func showAccessibilityAlert(firstLaunch: Bool = false) {
        guard !accessibilityAlertShown else { return }
        accessibilityAlertShown = true
        defer {
            DispatchQueue.main.asyncAfter(deadline: .now() + 5) { self.accessibilityAlertShown = false }
        }

        let alert = NSAlert()
        alert.messageText = L.t("MultiPasty needs the Accessibility permission",
                                "MultiPasty a besoin de l'autorisation « Accessibilité »")
        alert.informativeText = L.t("""
        This permission lets MultiPasty press ⌘V for you, so your pick lands \
        straight in the application you were working in.

        Open System Settings → Privacy & Security → Accessibility, then switch \
        MultiPasty on.

        Without it the app still works: the item you pick goes to the clipboard, \
        you just press ⌘V yourself.
        """, """
        Cette autorisation permet à MultiPasty d'envoyer ⌘V à votre place, \
        pour coller directement dans l'application active.

        Ouvrez Réglages Système → Confidentialité et sécurité → Accessibilité, \
        puis cochez MultiPasty.

        Sans elle, l'app fonctionne quand même : le texte choisi est placé dans \
        le presse-papiers, il vous reste à faire ⌘V vous-même.
        """)
        alert.addButton(withTitle: L.t("Open Settings", "Ouvrir les réglages"))
        let later = alert.addButton(withTitle: firstLaunch ? L.t("Later", "Plus tard") : "OK")
        later.keyEquivalent = "\u{1b}"   // esc dismisses the alert
        alert.alertStyle = .informational

        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn {
            Paster.requestTrust()
            Paster.openAccessibilitySettings()
        }
    }
}
