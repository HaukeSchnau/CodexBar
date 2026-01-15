import CodexBarCore
import Foundation

@MainActor
extension UsageStore {
    /// Returns the login method (plan type) for the specified provider, if available.
    func loginMethod(for provider: UsageProvider) -> String? {
        self.snapshots[provider]?.loginMethod(for: provider)
    }

    /// Returns true if the Claude account appears to be a subscription (Max, Pro, Ultra, Team).
    /// Returns false for API users or when plan cannot be determined.
    func isClaudeSubscription() -> Bool {
        Self.isSubscriptionPlan(self.loginMethod(for: .claude))
    }

    /// Determines if a login method string indicates a Claude subscription plan.
    /// Known subscription indicators: Max, Pro, Ultra, Team (case-insensitive).
    nonisolated static func isSubscriptionPlan(_ loginMethod: String?) -> Bool {
        guard let method = loginMethod?.lowercased(), !method.isEmpty else {
            return false
        }
        let subscriptionIndicators = ["max", "pro", "ultra", "team"]
        return subscriptionIndicators.contains { method.contains($0) }
    }

    func version(for provider: UsageProvider) -> String? {
        switch provider {
        case .codex: self.codexVersion
        case .claude: self.claudeVersion
        case .zai: self.zaiVersion
        case .gemini: self.geminiVersion
        case .antigravity: self.antigravityVersion
        case .cursor: self.cursorVersion
        case .opencode: nil
        case .factory: nil
        case .copilot: nil
        case .minimax: nil
        case .vertexai: nil
        case .kiro: self.kiroVersion
        case .augment: nil
        case .jetbrains: nil
        case .kimi: nil
        case .kimik2: nil
        case .amp: nil
        case .synthetic: nil
        }
    }
}
