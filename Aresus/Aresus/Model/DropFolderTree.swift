import Foundation

/// The Mac's folders (`FolderList`'s flat paths, "Studium/EIST") as a tree to drill down folder by folder, and the
/// folder picker's search over every path. Built once per folder list; pure, so the tests pin both.
nonisolated struct DropFolderTree: Equatable, Sendable {
    /// A folder on the Mac: a root and a path inside it ("" = the root itself).
    struct Folder: Hashable, Identifiable, Sendable {
        let root: DropRoot
        let path: String
        var id: String { root.rawValue + "/" + path }
        var target: Target { Target(root: root, folder: path, newFolder: nil) }
        var depth: Int { path.isEmpty ? 0 : path.split(separator: "/").count }
    }

    /// Per root: a folder's path ("" = the root) → its folders' paths, in Finder's order.
    private let children: [DropRoot: [String: [String]]]

    init(_ list: FolderList?) {
        var children: [DropRoot: [String: [String]]] = [:]
        for root in DropRoot.allCases {
            var tree: [String: Set<String>] = [:]
            for path in list.map({ root == .documents ? $0.documents : $0.downloads }) ?? [] {
                // Every folder above a listed one exists on the Mac too, listed or not.
                let parts = path.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
                for index in parts.indices {
                    let parent = parts[..<index].joined(separator: "/")
                    tree[parent, default: []].insert(parts[...index].joined(separator: "/"))
                }
            }
            children[root] = tree.mapValues { $0.sorted(by: Self.finderOrder) }
        }
        self.children = children
    }

    /// The folders inside one, in Finder's order.
    func folders(in root: DropRoot, under path: String = "") -> [Folder] {
        (children[root]?[path] ?? []).map { Folder(root: root, path: $0) }
    }

    func hasFolders(in root: DropRoot, under path: String) -> Bool { !(children[root]?[path] ?? []).isEmpty }

    func contains(_ root: DropRoot, _ path: String) -> Bool {
        if path.isEmpty { return true }
        let parent = path.split(separator: "/").dropLast().joined(separator: "/")
        return children[root]?[parent]?.contains(path) == true
    }

    /// Every folder whose path (the root's name included) holds each word of the query, ignoring case and accents:
    /// a folder named like the query first, then one starting with it, one holding it, then any path holding it; within
    /// each the shallower first, Documents before Downloads, then Finder's order. At most `limit`.
    func search(_ query: String, limit: Int = 50, language: AppLanguage = .current) -> [Folder] {
        let words = Self.fold(query).split(whereSeparator: { $0.isWhitespace || $0 == "/" }).map(String.init)
        guard !words.isEmpty else { return [] }
        let whole = words.joined(separator: " ")
        var found: [(tier: Int, folder: Folder)] = []
        for root in DropRoot.allCases {
            let rootName = Self.fold(DropPathText.root(root, language: language))
            for path in Set((children[root] ?? [:]).values.joined()) {
                let haystack = rootName + "/" + Self.fold(path)
                guard words.allSatisfy(haystack.contains) else { continue }
                let name = Self.fold(String(path.split(separator: "/").last ?? ""))
                let tier = name == whole ? 0 : name.hasPrefix(whole) ? 1 : words.allSatisfy(name.contains) ? 2 : 3
                found.append((tier, Folder(root: root, path: path)))
            }
        }
        return found.sorted { left, right in
            if left.tier != right.tier { return left.tier < right.tier }
            if left.folder.depth != right.folder.depth { return left.folder.depth < right.folder.depth }
            if left.folder.root != right.folder.root { return left.folder.root == .documents }
            return Self.finderOrder(left.folder.path, right.folder.path)
        }
        .prefix(limit).map(\.folder)
    }

    private static func fold(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
    }

    /// Finder's order: case-insensitive, numbers by value ("Week 2" before "Week 10").
    private static func finderOrder(_ left: String, _ right: String) -> Bool {
        let order = left.compare(right, options: [.caseInsensitive, .numeric, .diacriticInsensitive])
        return order == .orderedSame ? left < right : order == .orderedAscending
    }
}

extension DropFolderTree {
    /// A folder chosen from the recent ones (or the last one for this kind of file, where the sheet starts): a new
    /// folder made last time that is now in the Mac's list is chosen as that folder; one not listed yet stays a new
    /// folder inside its parent.
    static func start(from target: Target?, in tree: DropFolderTree) -> (target: Target?, newFolder: String) {
        guard let target = resolve(target, in: tree) else { return (nil, "") }
        return (Target(root: target.root, folder: target.folder), target.newFolder ?? "")
    }

    /// The same as one target: the new folder folded into the folder once the Mac lists it.
    static func resolve(_ target: Target?, in tree: DropFolderTree) -> Target? {
        guard let target else { return nil }
        guard let new = target.newFolder, !new.isEmpty else { return Target(root: target.root, folder: target.folder) }
        let path = target.folder.isEmpty ? new : target.folder + "/" + new
        if tree.contains(target.root, path) { return Target(root: target.root, folder: path) }
        return target
    }
}

extension Target {
    nonisolated init(root: DropRoot, folder: String) { self.init(root: root, folder: folder, newFolder: nil) }
}
