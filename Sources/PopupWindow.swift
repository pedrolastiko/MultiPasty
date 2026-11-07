import AppKit

// MARK: - Panel

final class PopupPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

/// Root view: captures every key (the panel has no text field, typing feeds
/// the filter directly).
final class KeyCatchingView: NSView {
    weak var controller: PopupController?
    override var acceptsFirstResponder: Bool { true }

    override func keyDown(with event: NSEvent) {
        if controller?.handleKey(event) != true {
            NSSound.beep()
        }
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        controller?.handleKeyEquivalent(event) ?? false
    }
}

// MARK: - List row

final class RoundedRowView: NSTableRowView {
    override func drawSelection(in dirtyRect: NSRect) {
        guard selectionHighlightStyle != .none else { return }
        let r = bounds.insetBy(dx: 6, dy: 2)
        let path = NSBezierPath(roundedRect: r, xRadius: 8, yRadius: 8)
        NSColor.controlAccentColor.setFill()
        path.fill()
    }
}

final class ClipRowView: NSView {
    let badge = NSTextField(labelWithString: "")
    let title = NSTextField(labelWithString: "")
    let subtitle = NSTextField(labelWithString: "")
    let thumb = NSImageView()
    let pin = NSTextField(labelWithString: "")

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)

        badge.font = .monospacedDigitSystemFont(ofSize: 11, weight: .semibold)
        badge.alignment = .center
        badge.wantsLayer = true
        badge.layer?.cornerRadius = 5
        badge.layer?.masksToBounds = true

        title.font = .systemFont(ofSize: 13)
        title.lineBreakMode = .byTruncatingTail
        title.maximumNumberOfLines = 1

        subtitle.font = .systemFont(ofSize: 10)
        subtitle.lineBreakMode = .byTruncatingTail
        subtitle.maximumNumberOfLines = 1

        pin.font = .systemFont(ofSize: 10)
        pin.alignment = .right

        thumb.imageScaling = .scaleProportionallyUpOrDown
        thumb.wantsLayer = true
        thumb.layer?.cornerRadius = 4
        thumb.layer?.masksToBounds = true

        for v in [badge, thumb, title, subtitle, pin] { addSubview(v) }
    }

    required init?(coder: NSCoder) { fatalError() }

    override func layout() {
        super.layout()
        let h = bounds.height
        badge.frame = NSRect(x: 14, y: (h - 18) / 2, width: 22, height: 18)

        let hasThumb = thumb.image != nil
        if hasThumb {
            thumb.frame = NSRect(x: 44, y: (h - 32) / 2, width: 40, height: 32)
        } else {
            thumb.frame = .zero
        }
        let textX: CGFloat = hasThumb ? 92 : 44
        let pinW: CGFloat = pin.stringValue.isEmpty ? 0 : 20
        let textW = max(40, bounds.width - textX - 14 - pinW)

        title.frame = NSRect(x: textX, y: h / 2 - 1, width: textW, height: 17)
        subtitle.frame = NSRect(x: textX, y: h / 2 - 17, width: textW, height: 14)
        pin.frame = NSRect(x: bounds.width - 14 - pinW, y: (h - 16) / 2, width: pinW, height: 16)
    }

    func configure(with item: ClipItem, index: Int, selected: Bool) {
        badge.stringValue = index < 9 ? "\(index + 1)" : "•"
        title.stringValue = item.preview.isEmpty ? L.t("(empty)", "(vide)") : item.preview
        subtitle.stringValue = item.subtitle
        pin.stringValue = item.pinned ? "📌" : ""
        thumb.image = item.kind == .image ? HistoryStore.shared.image(for: item) : nil
        applyColors(selected: selected)
        needsLayout = true
    }

    func applyColors(selected: Bool) {
        if selected {
            title.textColor = .white
            subtitle.textColor = NSColor.white.withAlphaComponent(0.75)
            badge.textColor = .white
            badge.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.25).cgColor
        } else {
            title.textColor = .labelColor
            subtitle.textColor = .secondaryLabelColor
            badge.textColor = .secondaryLabelColor
            badge.layer?.backgroundColor = NSColor.quaternaryLabelColor.withAlphaComponent(0.35).cgColor
        }
    }
}

// MARK: - Popup controller

final class PopupController: NSObject, NSTableViewDataSource, NSTableViewDelegate {
    static let shared = PopupController()

    private var panel: PopupPanel!
    private var tableView: NSTableView!
    private var scrollView: NSScrollView!
    private var headerLabel: NSTextField!
    private var footerLabel: NSTextField!
    private var emptyLabel: NSTextField!
    private var rootView: KeyCatchingView!

    private var results: [ClipItem] = []
    private var filter: String = "" { didSet { refresh(resetSelection: true) } }
    private weak var previousApp: NSRunningApplication?
    private var shownAt: Date?

    private let rowHeight: CGFloat = 46
    private let headerHeight: CGFloat = 36
    private let footerHeight: CGFloat = 26
    private let panelWidth: CGFloat = 500
    private let maxVisibleRows = 10

    var isVisible: Bool { panel?.isVisible ?? false }

    private override init() {
        super.init()
        buildPanel()
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(historyChanged),
                                               name: .historyChanged,
                                               object: nil)
        // A click elsewhere takes key focus away from the panel: close it.
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(panelResignedKey),
                                               name: NSWindow.didResignKeyNotification,
                                               object: panel)
    }

    // MARK: Building the interface

    private func buildPanel() {
        panel = PopupPanel(contentRect: NSRect(x: 0, y: 0, width: panelWidth, height: 300),
                           styleMask: [.borderless, .nonactivatingPanel],
                           backing: .buffered,
                           defer: false)
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.animationBehavior = .utilityWindow

        rootView = KeyCatchingView(frame: panel.contentRect(forFrameRect: panel.frame))
        rootView.controller = self
        rootView.wantsLayer = true

        let effect = NSVisualEffectView(frame: rootView.bounds)
        effect.material = .popover
        effect.blendingMode = .behindWindow
        effect.state = .active
        effect.autoresizingMask = [.width, .height]
        effect.wantsLayer = true
        effect.layer?.cornerRadius = 12
        effect.layer?.masksToBounds = true
        rootView.addSubview(effect)

        headerLabel = NSTextField(labelWithString: "")
        headerLabel.font = .systemFont(ofSize: 12, weight: .medium)
        headerLabel.textColor = .secondaryLabelColor
        headerLabel.lineBreakMode = .byTruncatingTail
        rootView.addSubview(headerLabel)

        tableView = NSTableView()
        tableView.headerView = nil
        tableView.backgroundColor = .clear
        tableView.selectionHighlightStyle = .regular
        tableView.rowHeight = rowHeight
        tableView.intercellSpacing = NSSize(width: 0, height: 0)
        tableView.allowsEmptySelection = false
        tableView.allowsMultipleSelection = false
        tableView.dataSource = self
        tableView.delegate = self
        tableView.target = self
        tableView.action = #selector(rowClicked)
        tableView.style = .plain
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("main"))
        column.resizingMask = .autoresizingMask
        tableView.addTableColumn(column)

        scrollView = NSScrollView()
        scrollView.documentView = tableView
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false
        scrollView.backgroundColor = .clear
        scrollView.automaticallyAdjustsContentInsets = false
        scrollView.scrollerStyle = .overlay
        rootView.addSubview(scrollView)

        emptyLabel = NSTextField(labelWithString: "")
        emptyLabel.alignment = .center
        emptyLabel.font = .systemFont(ofSize: 12)
        emptyLabel.textColor = .tertiaryLabelColor
        emptyLabel.isHidden = true
        rootView.addSubview(emptyLabel)

        footerLabel = NSTextField(labelWithString: L.t(
            "↑↓ move · ⏎ paste · ⌘1–9 direct · ⌘⌫ delete · ⌘P pin · esc close",
            "↑↓ naviguer · ⏎ coller · ⌘1–9 direct · ⌘⌫ supprimer · ⌘P épingler · esc fermer"))
        footerLabel.font = .systemFont(ofSize: 10)
        footerLabel.textColor = .tertiaryLabelColor
        footerLabel.alignment = .center
        rootView.addSubview(footerLabel)

        panel.contentView = rootView
    }

    private func layoutViews(in size: NSSize) {
        rootView.frame = NSRect(origin: .zero, size: size)
        rootView.subviews.first?.frame = rootView.bounds
        headerLabel.frame = NSRect(x: 16, y: size.height - headerHeight + 10, width: size.width - 32, height: 18)
        let listTop = size.height - headerHeight
        let listHeight = max(0, listTop - footerHeight - 6)
        scrollView.frame = NSRect(x: 0, y: footerHeight + 6, width: size.width, height: listHeight)
        emptyLabel.frame = NSRect(x: 16, y: footerHeight + listHeight / 2 - 10, width: size.width - 32, height: 20)
        footerLabel.frame = NSRect(x: 8, y: 6, width: size.width - 16, height: 14)
    }

    // MARK: Showing

    func toggle() {
        isVisible ? hide() : show()
    }

    func show() {
        previousApp = NSWorkspace.shared.frontmostApplication
        filter = ""
        refresh(resetSelection: true)

        positionPanel()
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        panel.makeFirstResponder(rootView)
        shownAt = Date()
    }

    func hide() {
        panel.orderOut(nil)
    }

    @objc private func panelResignedKey() {
        guard panel.isVisible else { return }
        // Guard: a system alert appearing right after the panel opens must not
        // close it straight away.
        if let t = shownAt, Date().timeIntervalSince(t) < 0.4 { return }
        hide()
    }

    private func positionPanel() {
        let visibleCount = min(max(results.count, 1), maxVisibleRows)
        let height = headerHeight + CGFloat(visibleCount) * rowHeight + footerHeight + 6
        let size = NSSize(width: panelWidth, height: height)

        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
        let visible = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)

        var origin = NSPoint(x: mouse.x - size.width / 2, y: mouse.y - size.height - 12)
        origin.x = min(max(visible.minX + 8, origin.x), visible.maxX - size.width - 8)
        if origin.y < visible.minY + 8 {
            origin.y = min(mouse.y + 16, visible.maxY - size.height - 8)
        }
        origin.y = min(max(visible.minY + 8, origin.y), visible.maxY - size.height - 8)

        panel.setFrame(NSRect(origin: origin, size: size), display: false)
        layoutViews(in: size)
    }

    private func refresh(resetSelection: Bool) {
        results = HistoryStore.shared.filtered(filter)

        if filter.isEmpty {
            let total = HistoryStore.shared.items.count
            if total == 0 {
                headerLabel.stringValue = L.t("Clipboard", "Presse-papiers")
            } else {
                let n = L.count(total, en: "item", fr: "élément")
                headerLabel.stringValue = L.t("Clipboard — \(n) · type to filter",
                                              "Presse-papiers — \(n) · tapez pour filtrer")
            }
        } else {
            let n = L.count(results.count, en: "match", enPlural: "matches", fr: "résultat")
            headerLabel.stringValue = L.t("Filter: \u{201c}\(filter)\u{201d} — \(n)",
                                          "Filtre : « \(filter) » — \(n)")
        }

        emptyLabel.isHidden = !results.isEmpty
        emptyLabel.stringValue = filter.isEmpty
            ? L.t("Nothing copied yet.", "Aucun élément copié pour l'instant.")
            : L.t("No match for \u{201c}\(filter)\u{201d}.", "Aucun résultat pour « \(filter) ».")

        tableView.reloadData()
        if resetSelection, !results.isEmpty {
            tableView.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
            tableView.scrollRowToVisible(0)
        }
        if panel.isVisible { positionPanel() }
    }

    @objc private func historyChanged() {
        guard panel.isVisible else { return }
        let selected = tableView.selectedRow
        results = HistoryStore.shared.filtered(filter)
        tableView.reloadData()
        if !results.isEmpty {
            let row = min(max(0, selected), results.count - 1)
            tableView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        }
    }

    // MARK: Table

    func numberOfRows(in tableView: NSTableView) -> Int { results.count }

    func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
        RoundedRowView()
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let id = NSUserInterfaceItemIdentifier("ClipRow")
        let view = (tableView.makeView(withIdentifier: id, owner: self) as? ClipRowView) ?? {
            let v = ClipRowView(frame: NSRect(x: 0, y: 0, width: panelWidth, height: rowHeight))
            v.identifier = id
            return v
        }()
        view.configure(with: results[row], index: row, selected: tableView.selectedRow == row)
        return view
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        updateRowColors()
    }

    private func updateRowColors() {
        for row in 0..<results.count {
            guard let view = tableView.view(atColumn: 0, row: row, makeIfNecessary: false) as? ClipRowView else { continue }
            view.applyColors(selected: tableView.selectedRow == row)
        }
    }

    @objc private func rowClicked() {
        let row = tableView.clickedRow
        guard results.indices.contains(row) else { return }
        paste(results[row])
    }

    // MARK: Keyboard

    func handleKeyEquivalent(_ event: NSEvent) -> Bool {
        guard panel.isVisible else { return false }
        let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard mods.contains(.command) else { return false }
        let chars = event.charactersIgnoringModifiers ?? ""

        // ⌘1 … ⌘9: direct paste
        if let digit = Int(chars), digit >= 1, digit <= 9 {
            if results.indices.contains(digit - 1) {
                paste(results[digit - 1])
                return true
            }
            return true
        }
        // ⌘⌫: delete the selected item
        if event.keyCode == 51 {
            deleteSelected()
            return true
        }
        // ⌘P: pin / unpin
        if chars.lowercased() == "p" {
            if let item = selectedItem() {
                HistoryStore.shared.togglePin(item)
                refresh(resetSelection: false)
            }
            return true
        }
        // ⌘⌦ or ⌘K: clear the history
        if chars.lowercased() == "k" {
            HistoryStore.shared.clearAll()
            refresh(resetSelection: true)
            return true
        }
        return false
    }

    func handleKey(_ event: NSEvent) -> Bool {
        let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)

        switch event.keyCode {
        case 53: // esc
            if filter.isEmpty { hide() } else { filter = "" }
            return true
        case 36, 76: // return / enter
            if let item = selectedItem() { paste(item) }
            return true
        case 125: // arrow down
            move(by: 1)
            return true
        case 126: // arrow up
            move(by: -1)
            return true
        case 121: // page down
            move(by: maxVisibleRows)
            return true
        case 116: // page up
            move(by: -maxVisibleRows)
            return true
        case 115: // home
            moveTo(0)
            return true
        case 119: // end
            moveTo(results.count - 1)
            return true
        case 51: // backspace
            if !filter.isEmpty { filter = String(filter.dropLast()) }
            return true
        default:
            break
        }

        guard !mods.contains(.command), !mods.contains(.control), !mods.contains(.option) else { return false }
        guard let chars = event.characters, !chars.isEmpty else { return false }
        let printable = chars.unicodeScalars.filter { !CharacterSet.controlCharacters.contains($0) }
        guard !printable.isEmpty else { return false }
        filter += String(String.UnicodeScalarView(printable))
        return true
    }

    private func selectedItem() -> ClipItem? {
        let row = tableView.selectedRow
        return results.indices.contains(row) ? results[row] : nil
    }

    private func move(by delta: Int) {
        guard !results.isEmpty else { return }
        let current = tableView.selectedRow
        var next = current + delta
        if delta == 1, current == results.count - 1 { next = 0 }           // wrap at the bottom
        else if delta == -1, current <= 0 { next = results.count - 1 }     // wrap at the top
        moveTo(next)
    }

    private func moveTo(_ index: Int) {
        guard !results.isEmpty else { return }
        let row = min(max(0, index), results.count - 1)
        tableView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        tableView.scrollRowToVisible(row)
    }

    private func deleteSelected() {
        guard let item = selectedItem() else { return }
        let row = tableView.selectedRow
        HistoryStore.shared.remove(item)
        results = HistoryStore.shared.filtered(filter)
        refresh(resetSelection: false)
        if !results.isEmpty {
            moveTo(min(row, results.count - 1))
        }
    }

    // MARK: Pasting

    private func paste(_ item: ClipItem) {
        ClipboardMonitor.shared.write(item)
        hide()
        NSApp.hide(nil)   // hand control back to the previous application

        guard Paster.isTrusted else {
            // Without the Accessibility permission the content is still copied:
            // the user only has to press ⌘V themselves.
            AppDelegate.shared?.showAccessibilityAlert()
            return
        }

        let target = previousApp
        if let app = target, app.processIdentifier != ProcessInfo.processInfo.processIdentifier {
            if #available(macOS 14.0, *) {
                app.activate()
            } else {
                app.activate(options: [.activateIgnoringOtherApps])
            }
        }

        // A fixed delay is not enough: depending on the machine and the target
        // application, focus comes back anywhere from 50 ms to several hundred. So
        // wait until the target really is frontmost before sending ⌘V.
        waitForFocus(target, remaining: 30) {
            Paster.sendCommandV()
        }
    }

    private func waitForFocus(_ target: NSRunningApplication?,
                              remaining: Int,
                              then action: @escaping () -> Void) {
        let myPid = ProcessInfo.processInfo.processIdentifier
        let front = NSWorkspace.shared.frontmostApplication

        let ready = target == nil
            || front?.processIdentifier == target?.processIdentifier
            || (front?.processIdentifier != myPid && remaining <= 0)

        if ready || remaining <= 0 {
            // Small margin so the text field has taken the caret back.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.06, execute: action)
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.03) {
            self.waitForFocus(target, remaining: remaining - 1, then: action)
        }
    }
}
