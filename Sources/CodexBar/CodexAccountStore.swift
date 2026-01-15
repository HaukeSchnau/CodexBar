import CodexBarCore
import Foundation

struct CodexAccount: Hashable, Identifiable {
    let id: String
    let email: String?
    let path: URL
}

enum CodexAccountStore {
    private static let accountSelectionKey = "codexAccountID"
    private static let accountsFolderName = "codex-accounts"
    private static let legacyFolderName = "codex"

    static func bootstrapIfNeeded() {
        let raw = ProcessInfo.processInfo.environment["CODEX_HOME"]?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let raw, !raw.isEmpty { return }
        guard let baseDir = self.baseDirectory() else { return }
        let fm = FileManager.default
        do {
            try fm.createDirectory(at: baseDir, withIntermediateDirectories: true)
        } catch {
            CodexBarLog.logger("codex-accounts").error("Failed to create accounts directory: \(error)")
            return
        }

        var accounts = self.loadAccounts(from: baseDir, includeEmptySelected: true)
        if accounts.isEmpty {
            self.migrateLegacyAccounts(into: baseDir)
            accounts = self.loadAccounts(from: baseDir, includeEmptySelected: true)
        }
        if accounts.isEmpty {
            if let account = self.createAccount(in: baseDir) {
                accounts = [account]
            }
        }

        if let selected = self.selectedAccountID(), accounts.contains(where: { $0.id == selected }) {
            self.activateAccount(id: selected, accounts: accounts)
        } else if let first = accounts.first {
            self.activateAccount(id: first.id, accounts: accounts)
        }
    }

    static func accounts() -> [CodexAccount] {
        guard let baseDir = self.baseDirectory() else { return [] }
        return self.loadAccounts(from: baseDir, includeEmptySelected: true)
    }

    static func selectedAccountID() -> String? {
        UserDefaults.standard.string(forKey: self.accountSelectionKey)
    }

    static func selectedAccountInfo() -> AccountInfo? {
        self.accountInfo(for: self.selectedAccountID())
    }

    static func accountInfo(for id: String?) -> AccountInfo? {
        guard let account = self.account(for: id) else { return nil }
        return self.loadAccountInfo(from: account.path)
    }

    static func activateAccount(id: String) {
        let accounts = self.accounts()
        self.activateAccount(id: id, accounts: accounts)
    }

    static func createAccountAndActivate() -> CodexAccount? {
        guard let baseDir = self.baseDirectory() else { return nil }
        guard let account = self.createAccount(in: baseDir) else { return nil }
        self.activateAccount(id: account.id, accounts: [account])
        return account
    }

    static func account(for id: String?) -> CodexAccount? {
        guard let id else { return nil }
        return self.accounts().first(where: { $0.id == id })
    }

    // MARK: - Internals

    private static func baseDirectory() -> URL? {
        guard let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return nil
        }
        return root
            .appendingPathComponent("com.steipete.codexbar", isDirectory: true)
            .appendingPathComponent(self.accountsFolderName, isDirectory: true)
    }

    private static func legacyDirectory() -> URL? {
        guard let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return nil
        }
        return root
            .appendingPathComponent("com.steipete.codexbar", isDirectory: true)
            .appendingPathComponent(self.legacyFolderName, isDirectory: true)
    }

    private static func loadAccounts(from baseDir: URL, includeEmptySelected: Bool) -> [CodexAccount] {
        let fm = FileManager.default
        guard let contents = try? fm.contentsOfDirectory(
            at: baseDir,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles])
        else {
            return []
        }

        let selectedID = includeEmptySelected ? self.selectedAccountID() : nil
        var accounts: [CodexAccount] = []

        for url in contents {
            guard (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else { continue }
            let id = url.lastPathComponent
            let hasAuth = fm.fileExists(atPath: url.appendingPathComponent("auth.json").path)
            let hasCredentials = fm.fileExists(atPath: url.appendingPathComponent(".credentials.json").path)
            guard hasAuth || hasCredentials || id == selectedID else { continue }
            let email = self.loadEmail(from: url)
            accounts.append(CodexAccount(id: id, email: email, path: url))
        }

        return accounts.sorted {
            let left = ($0.email ?? "~").lowercased()
            let right = ($1.email ?? "~").lowercased()
            if left == right { return $0.id < $1.id }
            return left < right
        }
    }

    private static func activateAccount(id: String, accounts: [CodexAccount]) {
        guard let account = accounts.first(where: { $0.id == id }) ?? self.account(for: id) else { return }
        UserDefaults.standard.set(id, forKey: self.accountSelectionKey)
        setenv("CODEX_HOME", account.path.path, 1)
    }

    private static func createAccount(in baseDir: URL) -> CodexAccount? {
        let id = UUID().uuidString.lowercased()
        let dir = baseDir.appendingPathComponent(id, isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            return CodexAccount(id: id, email: nil, path: dir)
        } catch {
            CodexBarLog.logger("codex-accounts").error("Failed to create account dir: \(error)")
            return nil
        }
    }

    private static func migrateLegacyAccounts(into baseDir: URL) {
        let logger = CodexBarLog.logger("codex-accounts")
        let fm = FileManager.default
        let legacyCandidates: [URL] = [
            self.legacyDirectory(),
            fm.homeDirectoryForCurrentUser.appendingPathComponent(".codex", isDirectory: true),
        ].compactMap(\.self)

        for legacy in legacyCandidates {
            let hasAuth = fm.fileExists(atPath: legacy.appendingPathComponent("auth.json").path)
            let hasCredentials = fm.fileExists(atPath: legacy.appendingPathComponent(".credentials.json").path)
            guard hasAuth || hasCredentials else { continue }
            guard let account = self.createAccount(in: baseDir) else { continue }
            self.copyIfExists(
                from: legacy.appendingPathComponent("auth.json"),
                to: account.path.appendingPathComponent("auth.json"),
                logger: logger)
            self.copyIfExists(
                from: legacy.appendingPathComponent(".credentials.json"),
                to: account.path.appendingPathComponent(".credentials.json"),
                logger: logger)
            if let migrated = self.loadEmail(from: account.path) {
                logger.info("Migrated Codex account for \(migrated).")
            } else {
                logger.info("Migrated Codex account into \(account.id).")
            }
        }
    }

    private static func copyIfExists(from source: URL, to destination: URL, logger: CodexBarLogger) {
        let fm = FileManager.default
        guard fm.fileExists(atPath: source.path) else { return }
        guard !fm.fileExists(atPath: destination.path) else { return }
        do {
            try fm.copyItem(at: source, to: destination)
        } catch {
            logger.error("Failed to copy \(source.lastPathComponent): \(error)")
        }
    }

    private static func loadEmail(from accountDir: URL) -> String? {
        self.loadAccountInfo(from: accountDir)?.email
    }

    private static func loadAccountInfo(from accountDir: URL) -> AccountInfo? {
        let authURL = accountDir.appendingPathComponent("auth.json")
        guard let data = try? Data(contentsOf: authURL),
              let auth = try? JSONDecoder().decode(AuthFile.self, from: data),
              let idToken = auth.tokens?.idToken,
              let payload = UsageFetcher.parseJWT(idToken)
        else {
            return nil
        }

        let authDict = payload["https://api.openai.com/auth"] as? [String: Any]
        let profileDict = payload["https://api.openai.com/profile"] as? [String: Any]
        let email = (payload["email"] as? String) ?? (profileDict?["email"] as? String)
        let plan = (authDict?["chatgpt_plan_type"] as? String)
            ?? (payload["chatgpt_plan_type"] as? String)

        return AccountInfo(
            email: email?.trimmingCharacters(in: .whitespacesAndNewlines),
            plan: plan?.trimmingCharacters(in: .whitespacesAndNewlines))
    }
}

private struct AuthFile: Decodable {
    struct Tokens: Decodable {
        let idToken: String?

        private enum CodingKeys: String, CodingKey {
            case idToken
            case id_token
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            self.idToken = try container.decodeIfPresent(String.self, forKey: .idToken)
                ?? container.decodeIfPresent(String.self, forKey: .id_token)
        }
    }

    let tokens: Tokens?
}
