import Foundation

nonisolated protocol VaultPreparing: Sendable {
    func prepare(_ vault: Vault, previous: Vault?) async -> VaultWorker.Prepared
}

/// Vault CPU work and vault-file IO share a serial queue. Saves and deletion are enqueued synchronously by the main
/// actor after its context/revision check: a logout's deletion always follows any already accepted save. Quick-note
/// durability stays synchronous and uses its separate file.
nonisolated final class VaultWorker: VaultPreparing {
    struct Prepared: Sendable {
        let vault: Vault
        let index: VaultIndex?
        let search: VaultSearch?
        let tabSearch: TabSearch?

        init(_ vault: Vault, previous: Vault?) {
            self.vault = vault
            let changed = vault != previous
            let index = changed ? VaultIndex(vault: vault) : nil
            self.index = index
            search = changed ? VaultSearch(vault: vault) : nil
            tabSearch = index.map { TabSearch(vault: vault, index: $0) }
        }
    }

    private let queue = DispatchQueue(label: "de.ares-empire.arestoteles.vault", qos: .userInitiated)
    private let persistence: any VaultPersistence

    init(persistence: any VaultPersistence) { self.persistence = persistence }

    func load() async -> CachedVault? { await run { self.persistence.loadVault() } }

    func prepare(_ vault: Vault, previous: Vault?) async -> Prepared {
        await run { Prepared(vault, previous: previous) }
    }

    func save(_ cached: CachedVault) {
        queue.async { try? self.persistence.saveVault(cached) }
    }

    func deleteVault() {
        queue.async { try? self.persistence.deleteVault() }
    }

    func settled() async { await run {} }

    private func run<T: Sendable>(_ work: @escaping @Sendable () -> T) async -> T {
        await withCheckedContinuation { continuation in
            queue.async { continuation.resume(returning: work()) }
        }
    }
}
