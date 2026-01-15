import CodexBarCore

extension UsageStore {
    func snapshot(for provider: UsageProvider) -> UsageSnapshot? {
        self.snapshots[provider]
    }

    func snapshot(for provider: UsageProvider, codexAccountID: String?) -> UsageSnapshot? {
        guard provider == .codex, let codexAccountID else {
            return self.snapshots[provider]
        }
        if let cached = self.codexSnapshot(for: codexAccountID) {
            return cached
        }
        if codexAccountID == CodexAccountStore.selectedAccountID() {
            return self.snapshots[.codex]
        }
        return nil
    }
}
