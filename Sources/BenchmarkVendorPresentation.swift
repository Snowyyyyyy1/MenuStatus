import SwiftUI

enum BenchmarkVendorPresentation {
    private static let displayNames: [String: String] = [
        "anthropic": "Anthropic",
        "deepseek": "DeepSeek",
        "glm": "GLM",
        "google": "Google",
        "kimi": "Kimi",
        "openai": "OpenAI",
        "xai": "xAI",
    ]

    private static let chipAliases: [String: String] = [
        "anthropic": "ANT",
        "deepseek": "DSK",
        "glm": "GLM",
        "google": "GOO",
        "kimi": "KMI",
        "openai": "OAI",
        "xai": "XAI",
    ]

    static func displayName(for rawVendor: String) -> String {
        let normalized = normalizedID(for: rawVendor)
        if let explicit = displayNames[normalized] {
            return explicit
        }
        guard !normalized.isEmpty else { return rawVendor }
        return normalized.prefix(1).uppercased() + normalized.dropFirst()
    }

    static func orderedVendorIDs(from vendors: [String]) -> [String] {
        Array(Set(vendors.map(normalizedID).filter { !$0.isEmpty }))
            .sorted {
                displayName(for: $0).localizedCaseInsensitiveCompare(displayName(for: $1)) == .orderedAscending
            }
    }

    static func chipText(for rawVendor: String) -> String {
        let normalized = normalizedID(for: rawVendor)
        if let alias = chipAliases[normalized] {
            return alias
        }
        return String(displayName(for: normalized).prefix(3)).uppercased()
    }

    static func color(for rawVendor: String) -> Color {
        switch normalizedID(for: rawVendor) {
        case "openai": return .green
        case "anthropic": return .orange
        case "google": return .blue
        case "xai": return .purple
        case "deepseek": return .cyan
        case "kimi": return .pink
        case "glm": return .indigo
        default: return .gray
        }
    }

    static func matches(_ lhs: String?, _ rhs: String?) -> Bool {
        guard let lhs, let rhs else { return false }
        let normalizedLHS = normalizedID(for: lhs)
        let normalizedRHS = normalizedID(for: rhs)
        guard !normalizedLHS.isEmpty, !normalizedRHS.isEmpty else { return false }
        return normalizedLHS == normalizedRHS
    }

    static func normalizedID(for rawVendor: String) -> String {
        rawVendor.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}
