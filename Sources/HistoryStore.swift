import AppKit

enum ClipKind: String, Codable {
    case text
    case image
}

struct ClipItem: Codable, Identifiable, Equatable {
    var id: String = UUID().uuidString
    var kind: ClipKind
    /// Full text for .text, a descriptive label for .image
    var text: String
    /// File name inside Images/ for .image
    var imageFile: String?
    var date: Date
    var sourceApp: String?
    var pinned: Bool = false

    static func == (a: ClipItem, b: ClipItem) -> Bool { a.id == b.id }

    /// One-line preview, for the list
    var preview: String {
        let collapsed = text
            .replacingOccurrences(of: "\r\n", with: " ⏎ ")
            .replacingOccurrences(of: "\n", with: " ⏎ ")
            .replacingOccurrences(of: "\r", with: " ⏎ ")
            .replacingOccurrences(of: "\t", with: "  ")
        let trimmed = collapsed.trimmingCharacters(in: .whitespaces)
        return trimmed.count > 300 ? String(trimmed.prefix(300)) + "…" : trimmed
    }

    var subtitle: String {
        var parts: [String] = []
        if let app = sourceApp, !app.isEmpty { parts.append(app) }
        parts.append(ClipItem.relativeFormatter.localizedString(for: date, relativeTo: Date()))
        if kind == .text {
            parts.append(L.count(text.count, en: "character", fr: "caractère"))
        }
        return parts.joined(separator: " · ")
    }

    static let relativeFormatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .short
        f.locale = L.dateLocale
        return f
    }()
}

/// History storage: in memory, persisted as JSON in Application Support.
final class HistoryStore {
    static let shared = HistoryStore()

    private(set) var items: [ClipItem] = []
    private let fileURL: URL
    let dir: URL
    let imagesDir: URL

    /// Maximum number of unpinned items kept.
    var maxItems: Int {
        get {
            let v = UserDefaults.standard.integer(forKey: "maxItems")
            return v == 0 ? 20 : v
        }
        set {
            UserDefaults.standard.set(newValue, forKey: "maxItems")
            trim()
            save()
        }
    }

    private init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        dir = base.appendingPathComponent("MultiPasty", isDirectory: true)
        imagesDir = dir.appendingPathComponent("Images", isDirectory: true)
        fileURL = dir.appendingPathComponent("history.json")
        try? FileManager.default.createDirectory(at: imagesDir, withIntermediateDirectories: true)
        load()
    }

    // MARK: - Disk read / write

    private func load() {
        guard let data = try? Data(contentsOf: fileURL) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        if let decoded = try? decoder.decode([ClipItem].self, from: data) {
            items = decoded
        }
    }

    private func save() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted]
        guard let data = try? encoder.encode(items) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    // MARK: - Mutations

    func addText(_ string: String, sourceApp: String?) {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        // Duplicate: move the existing item back to the top instead of adding a copy.
        if let idx = items.firstIndex(where: { $0.kind == .text && $0.text == string }) {
            var existing = items.remove(at: idx)
            existing.date = Date()
            existing.sourceApp = sourceApp ?? existing.sourceApp
            items.insert(existing, at: 0)
            sortPinnedFirst()
            save()
            NotificationCenter.default.post(name: .historyChanged, object: nil)
            return
        }

        let item = ClipItem(kind: .text, text: string, imageFile: nil, date: Date(), sourceApp: sourceApp)
        items.insert(item, at: 0)
        sortPinnedFirst()
        trim()
        save()
        NotificationCenter.default.post(name: .historyChanged, object: nil)
    }

    func addImage(_ image: NSImage, sourceApp: String?) {
        guard let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else { return }

        let filename = UUID().uuidString + ".png"
        let url = imagesDir.appendingPathComponent(filename)
        do { try png.write(to: url) } catch { return }

        let label = L.t("Image", "Image") + " \(rep.pixelsWide) × \(rep.pixelsHigh)"
        let item = ClipItem(kind: .image, text: label, imageFile: filename, date: Date(), sourceApp: sourceApp)
        items.insert(item, at: 0)
        sortPinnedFirst()
        trim()
        save()
        NotificationCenter.default.post(name: .historyChanged, object: nil)
    }

    func remove(_ item: ClipItem) {
        guard let idx = items.firstIndex(of: item) else { return }
        deleteImageFile(of: items[idx])
        items.remove(at: idx)
        save()
        NotificationCenter.default.post(name: .historyChanged, object: nil)
    }

    func togglePin(_ item: ClipItem) {
        guard let idx = items.firstIndex(of: item) else { return }
        items[idx].pinned.toggle()
        sortPinnedFirst()
        save()
        NotificationCenter.default.post(name: .historyChanged, object: nil)
    }

    func clearAll(keepPinned: Bool = true) {
        let survivors = keepPinned ? items.filter { $0.pinned } : []
        for item in items where !survivors.contains(item) {
            deleteImageFile(of: item)
        }
        items = survivors
        save()
        NotificationCenter.default.post(name: .historyChanged, object: nil)
    }

    /// Pinned items always stay on top, the rest sorted newest first.
    private func sortPinnedFirst() {
        items.sort { a, b in
            if a.pinned != b.pinned { return a.pinned }
            return a.date > b.date
        }
    }

    private func trim() {
        var kept = 0
        var survivors: [ClipItem] = []
        for item in items {
            if item.pinned {
                survivors.append(item)
                continue
            }
            if kept < maxItems {
                survivors.append(item)
                kept += 1
            } else {
                deleteImageFile(of: item)
            }
        }
        items = survivors
    }

    private func deleteImageFile(of item: ClipItem) {
        guard let file = item.imageFile else { return }
        try? FileManager.default.removeItem(at: imagesDir.appendingPathComponent(file))
    }

    func image(for item: ClipItem) -> NSImage? {
        guard let file = item.imageFile else { return nil }
        return NSImage(contentsOf: imagesDir.appendingPathComponent(file))
    }

    /// Filter, ignoring case and accents.
    func filtered(_ query: String) -> [ClipItem] {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return items }
        return items.filter {
            $0.text.range(of: q, options: [.caseInsensitive, .diacriticInsensitive]) != nil
        }
    }
}

extension Notification.Name {
    static let historyChanged = Notification.Name("MultiPastyHistoryChanged")
}
