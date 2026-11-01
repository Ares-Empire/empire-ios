import SwiftUI

/// Where the files go (pushed inside the send sheet, brief 91): a search over every folder of the Mac, the recent
/// folders, Sort later (the Mac's fallback folder), then Documents and Downloads, each opened folder by folder
/// (`FolderPage`). The tree and the search are `DropFolderTree`'s.
struct FolderPickerScreen: View {
    let drops: DropsStore
    let draft: SendDraft
    let choose: (Target?) -> Void
    @State private var query = FolderPickerScreen.launchedQuery

    private var tree: DropFolderTree { draft.tree }
    /// The folder chosen now (with its new folder); nil = Sort later.
    private var chosen: Target? { draft.sendTarget }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                SearchCapsule(text: $query, prompt: String(localized: "Search folders"))
                if query.trimmingCharacters(in: .whitespaces).isEmpty { browse } else { results }
            }
            .padding(.horizontal, 18).padding(.top, 8).padding(.bottom, 30)
        }
        .scrollIndicators(.hidden)
        .scrollDismissesKeyboard(.immediately)
        .background { ProvinceWall(accent: .aresus) }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text("Folder").font(AppFont.text(17, weight: .bold)).foregroundStyle(Ink.primary)
            }
        }
        .task { if drops.folders == nil { await drops.load(.folders) } }
    }

    // MARK: browsing

    @ViewBuilder private var browse: some View {
        let recents = drops.recentFolders.targets
        if !recents.isEmpty {
            FolderSection(title: String(localized: "Recent")) {
                ForEach(Array(recents.enumerated()), id: \.offset) { index, target in
                    if index > 0 { RowDivider() }
                    Button { choose(target) } label: {
                        FolderRow(symbol: "clock", title: DropPathText.name(target),
                                  subtitle: DropPathText.path(target),
                                  trailing: DropFolderTree.resolve(target, in: tree) == chosen ? .chosen : .none)
                    }
                    .buttonStyle(PressedRow())
                }
            }
        }
        VStack(spacing: 0) {
            Button { choose(nil) } label: {
                FolderRow(symbol: "tray", title: String(localized: "Sort later"), subtitle: sortLaterLine,
                          trailing: chosen == nil ? .chosen : .none)
            }
            .buttonStyle(PressedRow())
        }
        .glassCard()
        .padding(.top, recents.isEmpty ? 22 : 18)
        if let folders = drops.folders {
            if folders.updated == nil {
                CalmMessage(text: String(localized: "The MacBook has not sent its folders yet. Files can still go to Sort later."))
                    .padding(.top, 48)
            } else {
                FolderSection(title: String(localized: "On the MacBook")) {
                    ForEach(Array(DropRoot.allCases.enumerated()), id: \.offset) { index, root in
                        if index > 0 { RowDivider() }
                        NavigationLink(value: SendRoute.folder(.init(root: root, path: ""))) {
                            FolderRow(symbol: root == .documents ? "doc" : "arrow.down.circle",
                                      title: DropPathText.root(root), trailing: .push)
                        }
                        .buttonStyle(PressedRow())
                    }
                }
                if let updated = folders.updated {
                    Text("Folders as of \(DropPathText.when(updated, now: .now))")
                        .font(AppFont.text(12)).foregroundStyle(Ink.muted)
                        .frame(maxWidth: .infinity).padding(.top, 22)
                }
            }
        } else if let error = drops.errors[.folders] {
            CalmMessage(text: error, actionTitle: String(localized: "Try again")) { Task { await drops.load(.folders) } }
                .padding(.top, 48)
        } else {
            CalmLoading().padding(.top, 60)
        }
    }

    /// "Documents › Zu sortieren · 2 files waiting".
    private var sortLaterLine: String? {
        guard let folders = drops.folders, !folders.fallback.isEmpty else { return nil }
        let place = DropPathText.path(.documents, folders.fallback)
        guard folders.fallbackCount > 0 else { return place }
        return place + " · " + String(localized: "\(folders.fallbackCount) files waiting")
    }

    // MARK: searching

    @ViewBuilder private var results: some View {
        let found = tree.search(query)
        if found.isEmpty {
            Text("No folder matches “\(query.trimmingCharacters(in: .whitespaces))”.")
                .font(AppFont.text(13)).foregroundStyle(Ink.muted)
                .frame(maxWidth: .infinity).multilineTextAlignment(.center).padding(.top, 40)
        } else {
            VStack(spacing: 0) {
                ForEach(Array(found.enumerated()), id: \.element) { index, folder in
                    if index > 0 { RowDivider() }
                    Button { choose(folder.target) } label: {
                        FolderRow(symbol: "folder", title: DropPathText.name(folder.root, folder.path),
                                  subtitle: DropPathText.path(folder.root, folder.path),
                                  trailing: folder.target == chosen ? .chosen : .none)
                    }
                    .buttonStyle(PressedRow())
                }
            }
            .glassCard()
            .padding(.top, 18)
        }
    }

    private static var launchedQuery: String {
        #if DEBUG
        LaunchArguments.value("-folderSearch") ?? ""
        #else
        ""
        #endif
    }
}

/// A folder of the Mac: "Choose <folder>" at the top, then the folders inside it. A folder with folders inside opens
/// its own page; one without is chosen with a tap.
struct FolderPage: View {
    let folder: DropFolderTree.Folder
    let draft: SendDraft
    let choose: (Target?) -> Void

    private var tree: DropFolderTree { draft.tree }
    private var chosen: Target? { draft.sendTarget }

    private var name: String { DropPathText.name(folder.root, folder.path) }

    var body: some View {
        let inside = tree.folders(in: folder.root, under: folder.path)
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                VStack(spacing: 0) {
                    Button { choose(folder.target) } label: {
                        FolderRow(symbol: "checkmark.circle", title: String(localized: "Choose \(name)"),
                                  subtitle: folder.path.isEmpty ? nil : DropPathText.path(folder.root, folder.path),
                                  trailing: folder.target == chosen ? .chosen : .none,
                                  tint: AppAccent.aresus.color, symbolTint: AppAccent.aresus.color)
                    }
                    .buttonStyle(PressedRow())
                }
                .glassCard()
                .padding(.top, 8)
                if inside.isEmpty {
                    Text("No folders inside.").font(AppFont.text(13)).foregroundStyle(Ink.muted)
                        .frame(maxWidth: .infinity).padding(.top, 36)
                } else {
                    FolderSection(title: String(localized: "Inside")) {
                        ForEach(Array(inside.enumerated()), id: \.element) { index, child in
                            if index > 0 { RowDivider() }
                            if tree.hasFolders(in: child.root, under: child.path) {
                                NavigationLink(value: SendRoute.folder(child)) {
                                    FolderRow(symbol: "folder", title: DropPathText.name(child.root, child.path),
                                              trailing: .push)
                                }
                                .buttonStyle(PressedRow())
                            } else {
                                Button { choose(child.target) } label: {
                                    FolderRow(symbol: "folder", title: DropPathText.name(child.root, child.path),
                                              trailing: child.target == chosen ? .chosen : .none)
                                }
                                .buttonStyle(PressedRow())
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 18).padding(.bottom, 30)
        }
        .scrollIndicators(.hidden)
        .background { ProvinceWall(accent: .aresus) }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text(verbatim: name).font(AppFont.text(17, weight: .bold)).foregroundStyle(Ink.primary).lineLimit(1)
            }
        }
    }
}

// MARK: - pieces

/// A heading over one glass card of rows.
private struct FolderSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeading(text: title).padding(.leading, 4)
            VStack(spacing: 0) { content }.glassCard()
        }
        .padding(.top, 26)
    }
}

/// A row of the picker: a symbol, the folder's name over its path, and where a tap leads (deeper, or the chosen mark).
private struct FolderRow: View {
    enum Trailing { case push, chosen, none }

    let symbol: String
    let title: String
    var subtitle: String? = nil
    var trailing: Trailing = .none
    var tint: Color = Ink.primary
    var symbolTint: Color = Ink.muted

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol).font(.system(size: 15, weight: .regular)).foregroundStyle(symbolTint)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: title).font(AppFont.text(15, weight: .medium)).foregroundStyle(tint).lineLimit(1)
                if let subtitle {
                    Text(verbatim: subtitle).font(AppFont.text(12)).foregroundStyle(Ink.muted)
                        .lineLimit(1).truncationMode(.head)
                }
            }
            Spacer(minLength: 8)
            switch trailing {
            case .push:
                Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold)).foregroundStyle(Ink.muted)
            case .chosen:
                Image(systemName: "checkmark").font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(AppAccent.aresus.color)
                    .accessibilityLabel(Text("Chosen"))
            case .none:
                EmptyView()
            }
        }
        .padding(.horizontal, 16).frame(minHeight: subtitle == nil ? 50 : 58)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

/// The picker's search field: a quiet capsule with the magnifying glass and a clear button.
private struct SearchCapsule: View {
    @Binding var text: String
    let prompt: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").font(.system(size: 14, weight: .medium)).foregroundStyle(Ink.muted)
            TextField("", text: $text, prompt: Text(verbatim: prompt).foregroundStyle(Ink.muted))
                .font(AppFont.text(15)).foregroundStyle(Ink.primary)
                .textInputAutocapitalization(.never).autocorrectionDisabled().submitLabel(.search)
            if !text.isEmpty {
                Button { text = "" } label: {
                    Image(systemName: "xmark.circle.fill").font(.system(size: 15)).foregroundStyle(Ink.muted)
                        .frame(width: 30, height: 30).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("Clear"))
            }
        }
        .padding(.leading, 14).padding(.trailing, 6).frame(height: 44)
        .background(Ink.field, in: .capsule)
        .overlay(Capsule().strokeBorder(Ink.edge))
    }
}
