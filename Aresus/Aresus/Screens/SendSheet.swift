import AVFoundation
import PhotosUI
import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// A page pushed inside the send sheet: the folder picker, and a folder of the Mac's opened in it.
enum SendRoute: Hashable {
    case folders
    case folder(DropFolderTree.Folder)
}

/// Send to MacBook (brief 91; the Aresync tab's header): pick photos, a photo from the camera, or files; then, on the
/// same sheet, where they go (a folder of the Mac, or Sort later), an optional new folder inside it, the name, and Send,
/// the sheet's one accent. It opens at medium height for the three choices and grows to large once something is
/// picked, staying large after that (also when the pick is changed). The work is `SendDraft`'s; the files go through `DropsStore.send`, which keeps them on the
/// phone until the server has them.
struct SendSheet: View {
    let drops: DropsStore
    @State private var draft = SendDraft()
    @State private var path: [SendRoute] = []
    @State private var photos: [PhotosPickerItem] = []
    @State private var picksPhotos = false
    @State private var picksFiles = false
    @State private var takesPhoto = false
    @State private var launched = false
    @State private var detent: PresentationDetent = SendSheet.startDetent
    @FocusState private var field: Field?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private enum Field { case newFolder, name }

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if draft.hasPicked { form } else { start }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background { ProvinceWall(accent: .aresus) }
            .navigationTitle(Text("Send to MacBook"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(role: .close) { dismiss() }.disabled(draft.isSending)
                }
            }
            .navigationDestination(for: SendRoute.self) { route in
                switch route {
                case .folders: FolderPickerScreen(drops: drops, draft: draft, choose: choose)
                case .folder(let folder): FolderPage(folder: folder, draft: draft, choose: choose)
                }
            }
        }
        .tint(Ink.primary)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: draft.hasPicked)
        .presentationDetents([.medium, .large], selection: $detent)
        .onChange(of: draft.hasPicked) { _, picked in if picked { detent = .large } }
        .presentationBackground(Ink.background)
        .interactiveDismissDisabled(draft.isSending)
        .photosPicker(isPresented: $picksPhotos, selection: $photos, selectionBehavior: .ordered,
                      matching: .any(of: [.images, .videos]), preferredItemEncoding: .current)
        .onChange(of: photos) { _, items in
            guard !items.isEmpty else { return }
            photos = []
            Task {
                await draft.load(items, with: { try await $0.loadTransferable(type: PickedLibraryFile.self)?.url },
                                 last: drops.recentFolders.lastBySource[.photo])
            }
        }
        .fileImporter(isPresented: $picksFiles, allowedContentTypes: [.item], allowsMultipleSelection: true) { result in
            switch result {
            case .success(let urls): draft.useFiles(urls, last: drops.recentFolders.lastBySource[.file])
            case .failure(let error): draft.show(error.localizedDescription)
            }
        }
        .fullScreenCover(isPresented: $takesPhoto) {
            CameraPicker { image in
                takesPhoto = false
                if let image { draft.useCamera(image, last: drops.recentFolders.lastBySource[.camera]) }
            }
            .ignoresSafeArea()
        }
        .onChange(of: drops.folders, initial: true) { _, folders in draft.tree = DropFolderTree(folders) }
        .task {
            #if DEBUG
            applyLaunchArguments()
            #endif
            await drops.refresh(olderThan: 30)
        }
    }

    /// Medium for the three choices; large when the sheet opens with a pick already there (the screenshots' `-samplePick`).
    private static var startDetent: PresentationDetent {
        #if DEBUG
        if LaunchArguments.value("-samplePick") != nil { return .large }
        #endif
        return .medium
    }

    private func choose(_ target: Target?) {
        draft.choose(target)
        path = []
    }

    // MARK: the three choices

    private var start: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 10) {
                    ChoiceTile(symbol: "photo.on.rectangle", title: String(localized: "Photos"), busy: draft.isLoading) {
                        picksPhotos = true
                    }
                    if CameraPicker.isAvailable {
                        ChoiceTile(symbol: "camera", title: String(localized: "Camera")) { Task { await openCamera() } }
                    }
                    ChoiceTile(symbol: "folder", title: String(localized: "Files")) { picksFiles = true }
                }
                .disabled(draft.isLoading)
                if let failure = draft.failure {
                    FormProblem(text: failure).padding(.top, 16)
                } else {
                    FormNote(text: String(localized: "Then choose the folder on the MacBook and the name."))
                        .padding(.top, 14)
                }
            }
            .padding(.horizontal, 18).padding(.top, 18).padding(.bottom, 24)
        }
        .scrollIndicators(.hidden)
    }

    private func openCamera() async {
        switch await CameraAccess.ask() {
        case .allowed: takesPhoto = true
        case .refused: draft.show(String(localized: "Aresus may not use the camera. Allow it in Settings → Apps → Aresus."))
        }
    }

    // MARK: what, where, the name

    private var form: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    pickedHeader
                    PickedStrip(draft: draft).padding(.top, 12)

                    SectionHeading(text: String(localized: "Folder")).padding(.leading, 4).padding(.top, 28)
                    folderCard.padding(.top, 10)
                    if let rule = draft.newFolderRule {
                        FormProblem(text: DropRuleWording.text(rule)).padding(.top, 10)
                    }

                    SectionHeading(text: draft.picked.count == 1 ? String(localized: "Name") : String(localized: "Names"))
                        .padding(.leading, 4).padding(.top, 28)
                    nameCard.padding(.top, 10)
                    if let rule = draft.nameRule {
                        FormProblem(text: DropRuleWording.text(rule)).padding(.top, 10)
                    }
                }
                .padding(.horizontal, 18).padding(.top, 14).padding(.bottom, 24)
                .disabled(draft.isSending)
            }
            .scrollIndicators(.hidden)
            .scrollDismissesKeyboard(.interactively)
            actions
        }
    }

    /// "PHOTOS 3" with Change, which goes back to the three choices.
    private var pickedHeader: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            SectionHeading(text: pickedTitle)
            if draft.picked.count > 1 {
                Text(verbatim: "\(draft.picked.count)").font(AppFont.number(11, weight: .regular)).foregroundStyle(Ink.muted)
            }
            Spacer(minLength: 8)
            Button { draft.startOver() } label: {
                Text("Change").font(AppFont.text(13, weight: .medium)).foregroundStyle(Ink.secondary)
                    .padding(.leading, 14).frame(minHeight: 32).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(draft.isSending)
        }
        .padding(.leading, 4)
    }

    private var pickedTitle: String {
        switch (draft.source, draft.picked.count == 1) {
        case (.file, true): String(localized: "File")
        case (.file, false): String(localized: "Files")
        case (_, true): String(localized: "Photo")
        case (_, false): String(localized: "Photos")
        }
    }

    /// Where it goes (a tap opens the folder picker) and, inside a chosen folder, a new one.
    private var folderCard: some View {
        VStack(spacing: 0) {
            NavigationLink(value: SendRoute.folders) {
                HStack(spacing: 12) {
                    Image(systemName: draft.target == nil ? "tray" : "folder")
                        .font(.system(size: 16, weight: .regular)).foregroundStyle(Ink.secondary).frame(width: 22)
                    Text(folderText).font(AppFont.text(15, weight: .medium)).lineSpacing(2)
                        .lineLimit(2).truncationMode(.head)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold)).foregroundStyle(Ink.muted)
                }
                .padding(.horizontal, 16).padding(.vertical, 12).frame(minHeight: 54)
                .contentShape(Rectangle())
            }
            .buttonStyle(PressedRow())
            .accessibilityLabel(Text("Folder"))
            .accessibilityValue(Text(folderText))
            if draft.target != nil {
                RowDivider()
                HStack(spacing: 12) {
                    Image(systemName: "folder.badge.plus").font(.system(size: 15, weight: .regular))
                        .foregroundStyle(Ink.muted).frame(width: 22)
                    TextField("", text: $draft.newFolder,
                              prompt: Text("New folder inside (optional)").foregroundStyle(Ink.muted))
                        .font(AppFont.text(15)).foregroundStyle(Ink.primary)
                        .textInputAutocapitalization(.sentences).autocorrectionDisabled()
                        .submitLabel(.done)
                        .focused($field, equals: .newFolder)
                }
                .padding(.horizontal, 16).frame(minHeight: 52)
            }
        }
        .glassCard()
        .focusRing(field == .newFolder)
    }

    /// "Documents › Studium › EIST" in ink, a new folder after it in the accent; "Sort later (Zu sortieren)".
    private var folderText: AttributedString {
        guard let target = draft.target else {
            var text = AttributedString(String(localized: "Sort later"))
            text.foregroundColor = Ink.primary
            if let fallback = drops.folders?.fallback, !fallback.isEmpty {
                var name = AttributedString(" (" + fallback + ")")
                name.foregroundColor = Ink.muted
                text += name
            }
            return text
        }
        var text = AttributedString(DropPathText.path(target))
        text.foregroundColor = Ink.primary
        let new = draft.newFolder.trimmingCharacters(in: .whitespacesAndNewlines)
        if !new.isEmpty {
            var part = AttributedString(DropPathText.separator + new)
            part.foregroundColor = AppAccent.aresus.color
            text += part
        }
        return text
    }

    @ViewBuilder private var nameCard: some View {
        if draft.picked.count == 1 {
            HStack(spacing: 4) {
                TextField("", text: $draft.name.stem, prompt: Text("Name").foregroundStyle(Ink.muted))
                    .font(AppFont.text(15)).foregroundStyle(Ink.primary)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                    .submitLabel(.done)
                    .focused($field, equals: .name)
                if !draft.name.ext.isEmpty {
                    Text(verbatim: "." + draft.name.ext).font(AppFont.text(15)).foregroundStyle(Ink.muted)
                        .lineLimit(1).fixedSize()
                }
            }
            .padding(.horizontal, 16).frame(minHeight: 52)
            .glassCard()
            .focusRing(field == .name)
        } else {
            VStack(spacing: 0) {
                ForEach(Array(draft.names.enumerated()), id: \.offset) { index, name in
                    if index > 0 { RowDivider() }
                    Text(verbatim: name).font(AppFont.text(14)).foregroundStyle(Ink.secondary)
                        .lineLimit(1).truncationMode(.middle)
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                        .padding(.horizontal, 16)
                }
            }
            .glassCard()
        }
    }

    // MARK: Send

    private var actions: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button(action: send) {
                BusyLabel(text: draft.isSending ? Text("Sending…", tableName: "Shared") : Text("Send", tableName: "Shared"),
                          busy: draft.isSending)
            }
            .buttonStyle(FormButtonStyle(accent: .aresus, busy: draft.isSending))
            .disabled(!draft.canSend && !draft.isSending)
            .allowsHitTesting(!draft.isSending)
            if let failure = draft.failure { FormProblem(text: failure) }
        }
        .padding(.horizontal, 18).padding(.top, 10).padding(.bottom, 10)
    }

    private func send() {
        field = nil
        Task { if await draft.send(with: drops) { dismiss() } }
    }
}

// MARK: - pieces

/// One of the three choices: a symbol over its word on a glass tile.
private struct ChoiceTile: View {
    let symbol: String
    let title: String
    var busy = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 10) {
                ZStack {
                    if busy { ProgressView().tint(Ink.secondary) }
                    else { Image(systemName: symbol).font(.system(size: 22, weight: .regular)).foregroundStyle(Ink.secondary) }
                }
                .frame(height: 26)
                Text(verbatim: title).font(AppFont.text(14, weight: .medium)).foregroundStyle(Ink.primary).lineLimit(1)
            }
            .frame(maxWidth: .infinity, minHeight: 100)
            .contentShape(RoundedRectangle(cornerRadius: Ink.cardRadius, style: .continuous))
        }
        .buttonStyle(PressedBox())
        .glassCard()
    }
}

/// What was picked, in one row that scrolls sideways: photos as small pictures, files as their symbol and name.
private struct PickedStrip: View {
    let draft: SendDraft

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 10) {
                ForEach(draft.picked) { item in
                    if draft.source == .file { FileTile(item: item) } else { PhotoTile(item: item, draft: draft) }
                }
            }
            .padding(.horizontal, 18)
        }
        .scrollIndicators(.hidden)
        .scrollClipDisabled()
        .padding(.horizontal, -18)
    }
}

private struct PhotoTile: View {
    let item: PickedFile
    let draft: SendDraft
    private let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)

    var body: some View {
        ZStack {
            shape.fill(Ink.card2)
            if let thumbnail = item.thumbnail {
                Image(uiImage: thumbnail).resizable().scaledToFill()
            } else {
                Image(systemName: DropFileKind(name: item.displayName).symbol)
                    .font(.system(size: 20, weight: .regular)).foregroundStyle(Ink.muted)
            }
        }
        .frame(width: 88, height: 88)
        .clipShape(shape)
        .overlay(shape.strokeBorder(Ink.line))
        .accessibilityElement()
        .accessibilityLabel(Text(verbatim: item.displayName))
        .task(id: item.id) {
            guard item.thumbnail == nil, case .file(let url) = item.file.content,
                  let image = await DropThumbnail.make(url) else { return }
            draft.update(image, for: item.id)
        }
    }
}

private struct FileTile: View {
    let item: PickedFile

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Image(systemName: DropFileKind(name: item.displayName).symbol)
                .font(.system(size: 19, weight: .regular)).foregroundStyle(Ink.secondary)
            Spacer(minLength: 6)
            Text(verbatim: item.displayName).font(AppFont.text(12, weight: .medium)).foregroundStyle(Ink.primary)
                .lineLimit(2).multilineTextAlignment(.leading)
        }
        .padding(12)
        .frame(width: 136, height: 88, alignment: .topLeading)
        .glassCard(radius: 14)
        .accessibilityElement(children: .combine)
    }
}

private extension View {
    /// The field being typed in: a faint accent line round its card (the support form's).
    func focusRing(_ focused: Bool) -> some View {
        overlay {
            RoundedRectangle(cornerRadius: Ink.cardRadius, style: .continuous)
                .strokeBorder(AppAccent.aresus.color.opacity(focused ? 0.45 : 0), lineWidth: 1)
                .allowsHitTesting(false)
        }
        .animation(.easeOut(duration: 0.15), value: focused)
    }
}

/// The iPhone's camera, for one photo (`UIImagePickerController`).
struct CameraPicker: UIViewControllerRepresentable {
    static var isAvailable: Bool { UIImagePickerController.isSourceTypeAvailable(.camera) }

    /// The photo taken, nil when the camera was closed.
    let taken: (UIImage?) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(taken: taken) }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let camera = UIImagePickerController()
        camera.sourceType = .camera
        camera.delegate = context.coordinator
        return camera
    }

    func updateUIViewController(_ camera: UIImagePickerController, context: Context) {}

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let taken: (UIImage?) -> Void

        init(taken: @escaping (UIImage?) -> Void) { self.taken = taken }

        func imagePickerController(_ picker: UIImagePickerController,
                                   didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            taken(info[.originalImage] as? UIImage)
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { taken(nil) }
    }
}

#if DEBUG
extension SendSheet {
    /// Screenshots (with `-sampleData -openSheet send`): `-samplePick photo|photos|file|files` (made-up pictures and
    /// files, as if picked), `-sendFolder <root>/<path>` (`documents/Examples`), `-sendNewFolder <text>`,
    /// `-sendName <text>`, `-sendNow` (Send at once), `-sampleRecents` (two recent folders), `-openFolders` (the folder picker), `-folderPath
    /// <root>/<path>` (opened down to it), `-folderSearch <text>` (typed in the picker's search).
    private func applyLaunchArguments() {
        guard !launched, drops.isSample else { return }
        launched = true
        func target(_ text: String) -> Target? {
            let parts = text.split(separator: "/", maxSplits: 1).map(String.init)
            guard let root = parts.first.flatMap(DropRoot.init(rawValue:)) else { return nil }
            return Target(root: root, folder: parts.count > 1 ? parts[1] : "")
        }
        if LaunchArguments.current.contains("-sampleRecents") {
            drops.recentFolders.use(Target(root: .downloads, folder: "Examples", newFolder: "Diagrams"), source: .file)
            drops.recentFolders.use(Target(root: .documents, folder: "Receipts"), source: .file)
        }
        if let kind = LaunchArguments.value("-samplePick") {
            draft.tree = DropFolderTree(try? AresusSamples.launched()?.folders())
            draft.use(SampleSendPicks.make(kind), source: kind.hasPrefix("file") ? .file : .photo,
                      last: LaunchArguments.value("-sendFolder").flatMap(target))
            if let new = LaunchArguments.value("-sendNewFolder") { draft.newFolder = new }
            if let name = LaunchArguments.value("-sendName") { draft.name.stem = name }
            if LaunchArguments.current.contains("-sendNow") { send() }
        }
        var route: [SendRoute] = LaunchArguments.current.contains("-openFolders") ? [.folders] : []
        if let opened = LaunchArguments.value("-folderPath").flatMap(target) {
            route = [.folders, .folder(.init(root: opened.root, path: ""))]
            var walked: [String] = []
            for part in opened.folder.split(separator: "/") {
                walked.append(String(part))
                route.append(.folder(.init(root: opened.root, path: walked.joined(separator: "/"))))
            }
        }
        path = route
    }
}

/// Made-up picks for screenshots: soft pictures drawn here, files with made-up names (no real data).
enum SampleSendPicks {
    static func make(_ kind: String) -> [PickedFile] {
        let date = AresusFormat.date(day: "2026-11-01") ?? .now
        switch kind {
        case "file", "files":
            let names = kind == "file" ? ["Exercise sheet 3.pdf"] : ["Exercise sheet 3.pdf", "Floor plan sketch.png", "Notes.txt"]
            return names.map {
                PickedFile(file: DropFile(content: .data(Data("Made-up sample".utf8)), suggestedName: $0, source: .file),
                           displayName: $0)
            }
        default:
            let looks: [(UIColor, UIColor, UIColor)] = [
                (UIColor(red: 0.55, green: 0.70, blue: 0.86, alpha: 1), UIColor(red: 0.93, green: 0.84, blue: 0.72, alpha: 1),
                 UIColor(red: 0.36, green: 0.47, blue: 0.40, alpha: 1)),
                (UIColor(red: 0.95, green: 0.69, blue: 0.52, alpha: 1), UIColor(red: 0.72, green: 0.52, blue: 0.62, alpha: 1),
                 UIColor(red: 0.25, green: 0.27, blue: 0.38, alpha: 1)),
                (UIColor(red: 0.62, green: 0.80, blue: 0.84, alpha: 1), UIColor(red: 0.85, green: 0.92, blue: 0.90, alpha: 1),
                 UIColor(red: 0.30, green: 0.52, blue: 0.58, alpha: 1))
            ]
            return looks.prefix(kind == "photo" ? 1 : 3).enumerated().map { index, look in
                let image = picture(sky: look.0, glow: look.1, land: look.2)
                let taken = date.addingTimeInterval(Double(index) * 754 + 9_130)
                return PickedFile(file: DropFile(content: .data(image.jpegData(compressionQuality: 0.85) ?? Data()),
                                                 suggestedName: "IMG_04\(12 + index).HEIC", source: .photo, date: taken),
                                  displayName: "IMG_04\(12 + index).HEIC", thumbnail: image)
            }
        }
    }

    /// A calm made-up landscape: a sky fading into a glow, a sun, two hills.
    private static func picture(sky: UIColor, glow: UIColor, land: UIColor) -> UIImage {
        let size = CGSize(width: 240, height: 240)
        return UIGraphicsImageRenderer(size: size).image { context in
            let cg = context.cgContext
            let colors = [sky.cgColor, glow.cgColor] as CFArray
            if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1]) {
                cg.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: 0, y: size.height * 0.7), options: [.drawsAfterEndLocation])
            }
            UIColor.white.withAlphaComponent(0.75).setFill()
            cg.fillEllipse(in: CGRect(x: 150, y: 70, width: 38, height: 38))
            land.withAlphaComponent(0.65).setFill()
            cg.fillEllipse(in: CGRect(x: -60, y: 150, width: 260, height: 180))
            land.setFill()
            cg.fillEllipse(in: CGRect(x: 70, y: 168, width: 260, height: 160))
        }
    }
}
#endif
