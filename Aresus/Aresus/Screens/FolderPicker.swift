import SwiftUI

/// Where the files go (pushed inside the send sheet, brief 91): a search over every folder of the Mac, the recent
/// folders, Sort later (the Mac's fallback folder), then Documents and Downloads, each opened folder by folder
/// (`FolderPage`, where a new folder is made too, brief 93). Recent folders and search results choose with one tap.
/// The tree and the search are `DropFolderTree`'s.
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
                                  isChosen: DropFolderTree.resolve(target, in: tree) == chosen)
                    }
                    .buttonStyle(PressedRow())
                }
            }
        }
        VStack(spacing: 0) {
            Button { choose(nil) } label: {
                FolderRow(symbol: "tray", title: String(localized: "Sort later"), subtitle: sortLaterLine,
                          isChosen: chosen == nil)
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
                                      title: DropPathText.root(root), pushes: true)
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
                                  isChosen: folder.target == chosen)
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

/// A folder of the Mac (brief 93): "Choose <folder>" at the top, then New folder, then every folder inside, each opening
/// its own page (one with no folders inside too: its page says so, quietly, under New folder). The page's words and
/// marks are `DropFolderPage`'s; New folder is `DropNewFolder` (checked as it is typed).
struct FolderPage: View {
    let folder: DropFolderTree.Folder
    let draft: SendDraft
    let choose: (Target?) -> Void
    /// New folder's field while it is open (a tap on the row opens it, in place, with the keyboard).
    @State private var entry: DropNewFolder?
    @FocusState private var typing: Bool

    private var tree: DropFolderTree { draft.tree }
    private var name: String { DropPathText.name(folder.root, folder.path) }

    var body: some View {
        let page = DropFolderPage(folder, tree: tree, chosen: draft.sendTarget)
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                VStack(spacing: 0) {
                    Button { choose(folder.target) } label: {
                        FolderRow(symbol: "checkmark.circle", title: String(localized: "Choose \(name)"),
                                  subtitle: folder.path.isEmpty ? nil : DropPathText.path(folder.root, folder.path),
                                  isChosen: page.isChosen,
                                  tint: AppAccent.aresus.color, symbolTint: AppAccent.aresus.color)
                    }
                    .buttonStyle(PressedRow())
                    RowDivider()
                    if entry != nil { field } else { newFolderRow(page) }
                }
                .glassCard()
                .padding(.top, 8)
                if let entry { entryLine(entry).padding(.top, 10) }
                if page.isLeaf {
                    Text("No folders inside.").font(AppFont.text(13)).foregroundStyle(Ink.muted)
                        .frame(maxWidth: .infinity).padding(.top, 36)
                } else {
                    FolderSection(title: String(localized: "Inside")) {
                        ForEach(Array(page.rows.enumerated()), id: \.element.id) { index, row in
                            if index > 0 { RowDivider() }
                            NavigationLink(value: SendRoute.folder(row.folder)) {
                                FolderRow(symbol: "folder", title: DropPathText.name(row.folder.root, row.folder.path),
                                          pushes: true, isChosen: row.isChosen)
                            }
                            .buttonStyle(PressedRow())
                        }
                    }
                }
            }
            .padding(.horizontal, 18).padding(.bottom, 30)
        }
        .scrollIndicators(.hidden)
        .scrollDismissesKeyboard(.interactively)
        .background { ProvinceWall(accent: .aresus) }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text(verbatim: name).font(AppFont.text(17, weight: .bold)).foregroundStyle(Ink.primary).lineLimit(1)
            }
        }
        // Leaving the field with nothing typed puts the row back.
        .onChange(of: typing) { _, now in
            if !now, entry?.name.isEmpty == true { entry = nil }
        }
        #if DEBUG
        .task { applyLaunchArguments() }
        #endif
    }

    /// "New folder", or the new folder already chosen here (a tap edits it).
    private func newFolderRow(_ page: DropFolderPage) -> some View {
        Button { open(page.newFolder ?? "") } label: {
            if let new = page.newFolder {
                FolderRow(symbol: "folder.badge.plus", title: new, subtitle: String(localized: "New folder"),
                          isChosen: true, plainSubtitle: true)
            } else {
                FolderRow(symbol: "folder.badge.plus", title: String(localized: "New folder"))
            }
        }
        .buttonStyle(PressedRow())
    }

    /// New folder's name, typed where it stands: the field in the row's place, Create (Choose for a folder that is
    /// there already) at its end; Return does the same.
    private var field: some View {
        let entry = entry ?? DropNewFolder(parent: folder)
        let existing = entry.existing(in: tree)
        let target = entry.target(in: tree)
        return HStack(spacing: 12) {
            Image(systemName: "folder.badge.plus").font(.system(size: 15, weight: .regular)).foregroundStyle(Ink.muted)
                .frame(width: 22)
            TextField("", text: Binding(get: { self.entry?.text ?? "" }, set: { self.entry?.text = $0 }),
                      prompt: Text("Folder name").foregroundStyle(Ink.muted))
                .font(AppFont.text(15, weight: .medium)).foregroundStyle(Ink.primary)
                .textInputAutocapitalization(.sentences).autocorrectionDisabled()
                .submitLabel(.done)
                .focused($typing)
                .onSubmit(create)
                .accessibilityLabel(Text("New folder"))
            Button(action: create) {
                Text(existing == nil ? String(localized: "Create") : String(localized: "Choose"))
                    .font(AppFont.text(15, weight: .semibold))
                    .foregroundStyle(target == nil ? Ink.muted : AppAccent.aresus.color)
                    .padding(.horizontal, 10).frame(minHeight: 44).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(target == nil)
        }
        .padding(.leading, 16).padding(.trailing, 6).frame(minHeight: 50)
    }

    /// Under the card: the rule the name breaks, else that the folder is there already, else when the Mac makes it.
    @ViewBuilder private func entryLine(_ entry: DropNewFolder) -> some View {
        if let rule = entry.rule(in: tree) {
            FormProblem(text: DropRuleWording.text(rule))
        } else if let existing = entry.existing(in: tree) {
            FormNote(text: String(localized: "“\(DropPathText.name(existing.root, existing.path))” is already here."))
        } else {
            FormNote(text: draft.picked.count > 1 ? String(localized: "The MacBook makes it when the files arrive.")
                                                   : String(localized: "The MacBook makes it when the file arrives."))
        }
    }

    private func open(_ text: String) {
        entry = DropNewFolder(parent: folder, text: text)
        focusField()
    }

    /// The keyboard for the field once it is on screen (it is made in the same update as the tap).
    private func focusField() {
        Task {
            await Task.yield()
            typing = true
        }
    }

    /// Chooses this folder with the new one in it (or the one of that name already here) and goes back to the sheet.
    /// Return with a name that cannot be made only puts the keyboard away; the line under the card says why.
    private func create() {
        guard let target = entry?.target(in: tree) else { return }
        typing = false
        choose(target)
    }

    #if DEBUG
    /// Screenshots: `-newFolderText <text>` opens New folder with that text on the page `-folderPath` opens.
    private func applyLaunchArguments() {
        guard entry == nil, let text = LaunchArguments.value("-newFolderText"),
              let path = LaunchArguments.value("-folderPath") else { return }
        let parts = path.split(separator: "/", maxSplits: 1).map(String.init)
        guard parts.first == folder.root.rawValue, (parts.count > 1 ? parts[1] : "") == folder.path else { return }
        entry = DropNewFolder(parent: folder, text: text)
        if !LaunchArguments.current.contains("-newFolderKeyboardDown") { focusField() }
    }
    #endif
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

/// A row of the picker: a symbol, the folder's name over its path, the chosen mark, and the chevron of a folder that
/// opens its page.
private struct FolderRow: View {
    let symbol: String
    let title: String
    var subtitle: String? = nil
    var pushes = false
    var isChosen = false
    var tint: Color = Ink.primary
    var symbolTint: Color = Ink.muted
    /// The subtitle is words, not a path: cut at its end.
    var plainSubtitle = false

    var body: some View {
        HStack(spacing: 12) {
            // Decoration: read out, "checkmark.circle" said "Selected" on every Choose row.
            Image(systemName: symbol).font(.system(size: 15, weight: .regular)).foregroundStyle(symbolTint)
                .frame(width: 22)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: title).font(AppFont.text(15, weight: .medium)).foregroundStyle(tint).lineLimit(1)
                if let subtitle {
                    Text(verbatim: subtitle).font(AppFont.text(12)).foregroundStyle(Ink.muted)
                        .lineLimit(1).truncationMode(plainSubtitle ? .tail : .head)
                }
            }
            Spacer(minLength: 8)
            if isChosen {
                Image(systemName: "checkmark").font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(AppAccent.aresus.color)
                    .accessibilityLabel(Text("Chosen"))
            }
            if pushes {
                Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold)).foregroundStyle(Ink.muted)
                    .accessibilityHidden(true)
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
