import SwiftUI
import UniformTypeIdentifiers

/// A provider-based drop target with caller-supplied acceptance and copying. Both apps use the same hover state,
/// copy proposal and exit handling; their screens draw their own hover feedback.
struct ProviderDropTarget: DropDelegate {
    /// The owning screen decides when dropping is available.
    let enabled: Bool
    let type: (ProviderFiles.Item) -> String?
    let copy: ([NSItemProvider], @escaping @MainActor ([URL], Int) -> Void) -> Void
    @Binding var hovering: ProviderFiles.Hover?
    let reduceMotion: Bool
    /// The copies of the dropped files, on the main actor once they are all copied, and how many could not be copied.
    let dropped: ([URL], Int) -> Void

    func validateDrop(info: DropInfo) -> Bool { enabled }

    func dropEntered(info: DropInfo) { show(hover(info)) }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        let hover = hover(info)
        if hover != hovering { show(hover) }
        return DropProposal(operation: hover == nil ? .forbidden : .copy)
    }

    func dropExited(info: DropInfo) { show(nil) }

    func performDrop(info: DropInfo) -> Bool {
        show(nil)
        let providers = info.itemProviders(for: [.item])
        guard enabled, providers.map(Self.item).contains(where: { type($0) != nil }) else { return false }
        copy(providers) { copies, failed in dropped(copies, failed) }
        return true
    }

    private func hover(_ info: DropInfo) -> ProviderFiles.Hover? {
        ProviderFiles.hover(info.itemProviders(for: [.item]).map(Self.item).filter { type($0) != nil })
    }

    private static func item(_ provider: NSItemProvider) -> ProviderFiles.Item {
        ProviderFiles.Item(types: provider.registeredTypeIdentifiers, name: provider.suggestedName)
    }

    /// A short fade in and out; nothing moves, so Reduce Motion keeps it (only quicker).
    private func show(_ hover: ProviderFiles.Hover?) {
        withAnimation(.easeOut(duration: reduceMotion ? 0.12 : 0.18)) { hovering = hover }
    }
}

