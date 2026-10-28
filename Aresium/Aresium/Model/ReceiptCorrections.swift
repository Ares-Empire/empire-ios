import Foundation

// What Aresium learns when the person corrects a receipt (brief 33, D9 in ares-empire/docs/ARESIUM-FOR-OTHERS.md):
//
// - **The shop's name.** A name the person changed is remembered for the shop as it was read: the next receipt read
//   the same way shows the name they typed ("Corrected by you before"). Kept in the ledger (`StoredShopName`, schema 3)
//   and in the export.
// - **The category** is learned for the shop as a Switch learns a payment's merchant (`PhoneBackend.learnShop`): the
//   next receipt of that shop gets it preset, and the shop's bank payments are sorted into it.
// - **Not learned: the total and card or cash.** A misread total is a misread of that one print (faded paper, a fold),
//   not something the next receipt repeats, and one shop takes both card and cash, so a remembered answer would be a
//   silent guess (D8: card or cash is never guessed).

/// A shop-name correction: the shop as read (normalised, `ShopNames.key`) and the name the person typed for it. Also
/// its shape in an export (schema 3).
nonisolated struct ShopNameCorrection: Codable, Equatable, Sendable {
    /// The shop as the engine read it, normalised.
    let read: String
    /// The name the person typed.
    let name: String
}

/// The rules for shop-name corrections, pure so tests pin them.
nonisolated enum ShopNames {
    /// The shop as read, normalised so the same print read again finds it: lower case, letters and digits only
    /// ("MUSTERMARKT  LINDE." → "mustermarktlinde"). Empty when nothing of it is a letter or digit.
    static func key(_ read: String) -> String {
        String(read.lowercased().filter { $0.isLetter || $0.isNumber })
    }

    /// What saving a receipt means for the corrections.
    enum Change: Equatable {
        /// The person typed another name for this read shop: remember it.
        case remember(ShopNameCorrection)
        /// The person kept the name exactly as read: a correction for it (from before) is dropped.
        case forget(read: String)
    }

    /// `read`: the shop as the engine read it (nil when none was read); `saved`: the name the receipt is saved with
    /// (nil when the person left it empty). Nothing changes without a read name, or when the person emptied the field
    /// (that says nothing about the right name).
    static func change(read: String?, saved: String?) -> Change? {
        guard let read = read?.trimmingCharacters(in: .whitespacesAndNewlines), !read.isEmpty else { return nil }
        let key = key(read)
        guard !key.isEmpty else { return nil }
        guard let saved = saved?.trimmingCharacters(in: .whitespacesAndNewlines), !saved.isEmpty else { return nil }
        return saved == read ? .forget(read: key) : .remember(ShopNameCorrection(read: key, name: saved))
    }
}
