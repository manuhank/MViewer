import Foundation

/// Ordered list of viewable files with a cursor, either a whole directory
/// (when a single file is opened) or an explicit selection.
struct FileNavigator {
    private(set) var files: [URL]
    private(set) var index: Int

    var current: URL? { files.indices.contains(index) ? files[index] : nil }
    var count: Int { files.count }
    var position: Int { index + 1 }

    init?(url: URL) {
        let dir = url.deletingLastPathComponent()
        let contents = (try? FileManager.default.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])) ?? []
        var list = contents.filter(Media.isSupported).sorted(by: Self.nameOrder)
        if list.isEmpty { list = [url] }
        files = list
        index = list.firstIndex { $0.path == url.path } ?? 0
    }

    init?(directory: URL) {
        let contents = (try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])) ?? []
        let list = contents.filter(Media.isSupported).sorted(by: Self.nameOrder)
        guard !list.isEmpty else { return nil }
        files = list
        index = 0
    }

    init?(list: [URL]) {
        let filtered = list.filter(Media.isSupported)
        guard !filtered.isEmpty else { return nil }
        files = filtered
        index = 0
    }

    mutating func next() -> URL? {
        guard !files.isEmpty else { return nil }
        index = (index + 1) % files.count
        return files[index]
    }

    mutating func previous() -> URL? {
        guard !files.isEmpty else { return nil }
        index = (index - 1 + files.count) % files.count
        return files[index]
    }

    mutating func jump(to index: Int) -> URL? {
        guard files.indices.contains(index) else { return nil }
        self.index = index
        return files[index]
    }

    func peekNext() -> URL? {
        guard files.count > 1 else { return nil }
        return files[(index + 1) % files.count]
    }

    func peekPrevious() -> URL? {
        guard files.count > 1 else { return nil }
        return files[(index - 1 + files.count) % files.count]
    }

    /// Removes the current file (e.g. after trashing) and keeps the cursor
    /// on the file that took its place. Returns the new current file.
    mutating func removeCurrent() -> URL? {
        guard !files.isEmpty else { return nil }
        files.remove(at: index)
        guard !files.isEmpty else { return nil }
        if index >= files.count { index = 0 }
        return files[index]
    }

    private static func nameOrder(_ a: URL, _ b: URL) -> Bool {
        a.lastPathComponent.localizedStandardCompare(b.lastPathComponent) == .orderedAscending
    }
}
