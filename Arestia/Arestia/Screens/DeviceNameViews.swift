import SwiftUI

// Renaming a device on Home (owner, 2026-11-20) ("can we make the names of things changable so I can name rename
// things?"). The name lives in flatd (contract v1.3), so the app, its Shortcuts and controls, the 3D page, the desktop
// viewer and Claude show one name. A long press on a device's row offers Rename (and, once renamed, its original name
// back); the name then turns into a field where it stands, as Arestemis's and Aresium's names do: in the name's own
// font, in a well that reaches into the margin, the name selected and the keyboard up, Cancel beside it. Return
// (Done) or scrolling away saves; an empty field shows flatd's config name in grey, which saving brings back.

/// Which device's name is being edited on Home, and what is typed: one at a time.
@MainActor @Observable
final class RenameEditor {
    private(set) var deviceID: String?
    var text = ""
    /// The name the field opened with. Saving sends nothing unless what is typed differs from it: an untouched field
    /// that loses the keyboard (a scroll) would otherwise send the name it opened with, undoing a rename made elsewhere
    /// meanwhile, or cutting a config name longer than flatd takes (Codex's review of the renaming, finding 1).
    private var opening = ""

    func isEditing(_ id: String) -> Bool { deviceID == id }

    /// Opens a device's name for editing (a name still open elsewhere is saved first); not while a name of it is on
    /// its way to flatd (`FlatStore.isRenaming`), from the menu and VoiceOver's action alike.
    func begin(_ device: Device, in store: FlatStore) {
        guard deviceID != device.id, !store.isRenaming(device.id) else { return }
        save(in: store)
        deviceID = device.id
        text = device.label
        opening = device.label
    }

    /// Sends what is typed, only when it was edited (`opening`; and then nothing when it is the name the device has
    /// now, `DeviceNames.change`), and closes the field.
    func save(in store: FlatStore) {
        guard let id = deviceID else { return }
        let typed = text, edited = DeviceNames.cleaned(text) != DeviceNames.cleaned(opening)
        cancel()
        if edited { store.rename(id, to: typed) }
    }

    /// Closes the field; the name stays as it was.
    func cancel() {
        deviceID = nil
        text = ""
        opening = ""
    }
}

/// A device's name in its row: flatd's name (the own one once renamed), quieter while a new one is on its way to
/// flatd; while it is renamed, the field with Cancel beside it.
struct DeviceName: View {
    let store: FlatStore
    let device: Device
    var size: CGFloat = 16
    @Environment(RenameEditor.self) private var editor
    @FocusState private var focused: Bool
    @State private var selection: TextSelection?
    @State private var selectsAll = false

    var body: some View {
        if editor.isEditing(device.id) {
            field
        } else {
            let sending = store.renaming[device.id]
            Text(verbatim: sending ?? device.label)
                .font(AppFont.text(size, weight: .semibold))
                .foregroundStyle(sending == nil ? Ink.primary : Ink.muted)
                .lineLimit(1)
                .contentTransition(.opacity)
        }
    }

    private var field: some View {
        let shape = RoundedRectangle(cornerRadius: 10, style: .continuous)
        let text = Binding(get: { editor.text }, set: { editor.text = DeviceNames.typed($0) })
        return HStack(spacing: 18) {
            HStack(spacing: 6) {
                TextField(text: text, selection: $selection,
                          prompt: Text(verbatim: device.defaultLabel ?? device.label).foregroundStyle(Ink.muted)) {
                    Text("Name")
                }
                .font(AppFont.text(size, weight: .semibold)).foregroundStyle(Ink.primary)
                .tint(AppAccent.arestia.color)
                .focused($focused)
                .autocorrectionDisabled()          // a name is a name: no keyboard turning a brand into a word
                .submitLabel(.done)
                .onSubmit { editor.save(in: store) }
                if !editor.text.isEmpty {
                    // The field's clear button, as UIKit's: flatd's own name shows as the placeholder then.
                    Button { editor.text = "" } label: {
                        Image(systemName: "xmark.circle.fill").font(.system(size: 16)).foregroundStyle(Ink.muted)
                            .frame(width: 44, height: 44).contentShape(Rectangle()).padding(-14)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text("Clear"))
                }
            }
            .padding(.horizontal, 10).padding(.vertical, 5)
            .background(Ink.field, in: shape)
            .overlay(shape.strokeBorder(Ink.edge, lineWidth: 1))
            .contentShape(shape)
            .onTapGesture { focused = true }
            .padding(.horizontal, -10).padding(.vertical, -5)   // the name stays where it stood; the well reaches out
            Button { editor.cancel() } label: {
                Text("Cancel").font(AppFont.text(15)).foregroundStyle(Ink.primary)
                    .frame(minHeight: 44).contentShape(Rectangle())
                    .padding(.vertical, -12)            // the 44 pt area, without moving the line under the name
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.cancelAction)
        }
        .onAppear {
            selectsAll = true
            focused = true
        }
        .onChange(of: focused) { _, isFocused in
            if isFocused {
                selectAll()
            } else if editor.isEditing(device.id) {
                // The keyboard went away (a scroll, another app): what is typed counts, as Return would.
                editor.save(in: store)
            }
        }
    }

    /// Once the field has the keyboard: the whole name selected, so typing replaces it.
    private func selectAll() {
        guard selectsAll else { return }
        selectsAll = false
        Task { @MainActor in
            await Task.yield()
            selection = TextSelection(range: editor.text.startIndex..<editor.text.endIndex)
        }
    }
}

extension View {
    /// A device's row: its long press offers Rename, and while it has an own name, Original name (flatd's config name,
    /// shown under it). Nothing while its name is being edited (the field's own text menu is then the long press's).
    func renamable(_ device: Device, store: FlatStore) -> some View {
        modifier(RenameMenu(store: store, device: device))
    }
}

private struct RenameMenu: ViewModifier {
    let store: FlatStore
    let device: Device
    @Environment(RenameEditor.self) private var editor

    func body(content: Content) -> some View {
        content
            // The whole row takes the long press, its empty middle too; it lifts as a rounded card.
            .contentShape(.interaction, Rectangle())
            .contentShape(.contextMenuPreview, RoundedRectangle(cornerRadius: Ink.cardRadius, style: .continuous))
            .contextMenu {
                if !editor.isEditing(device.id) {
                    Button { editor.begin(device, in: store) } label: {
                        Label { Text("Rename") } icon: { Image(systemName: "pencil") }
                    }
                    .disabled(store.isRenaming(device.id))
                    if device.hasOwnName, let original = device.defaultLabel {
                        Button { store.rename(device.id, to: "") } label: {
                            Text("Original name")
                            Text(verbatim: original)
                            Image(systemName: "arrow.uturn.backward")
                        }
                        .disabled(store.isRenaming(device.id))
                    }
                }
            }
            .accessibilityAction(named: Text("Rename")) { editor.begin(device, in: store) }
    }
}
