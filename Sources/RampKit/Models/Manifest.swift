import Foundation

/// Root manifest structure fetched from CDN
public struct Manifest: Decodable {
    /// App identifier
    public let appId: String

    /// App display name
    public let appName: String

    /// Last update timestamp
    public let updatedAt: String

    /// Array of targeting configurations (evaluated in priority order)
    public let targets: [ManifestTarget]

    /// Array of all available onboardings (metadata reference)
    public let onboardings: [ManifestOnboarding]?
}

/// A target defines rules for matching users and which onboardings to show
public struct ManifestTarget: Decodable {
    /// Unique identifier for the target
    public let id: String

    /// Display name of the target
    public let name: String

    /// Priority order (0 = highest priority, evaluated first)
    public let priority: Int

    /// Rules for matching users to this target
    public let rules: TargetRules

    /// Onboardings to show for matched users (with allocation percentages)
    public let onboardings: [TargetOnboarding]
}

/// Rule matching configuration
public struct TargetRules: Decodable {
    /// Match mode: "all" = AND logic (all rules must match), "any" = OR logic (at least one must match)
    public let match: String

    /// Array of individual rules
    public let rules: [TargetRule]
}

/// Individual targeting rule
public struct TargetRule: Decodable {
    /// Unique rule identifier
    public let id: String

    /// Attribute to evaluate (e.g., "device.country", "user.isNewUser")
    public let attribute: String

    /// Comparison operator (equals, not_equals, contains, etc.)
    public let `operator`: String

    /// Value to compare against
    public let value: String
}

/// Onboarding reference within a target (includes A/B allocation)
public struct TargetOnboarding: Decodable {
    /// Onboarding identifier
    public let id: String

    /// Allocation percentage (0-100) for A/B testing
    public let allocation: Int

    /// URL to fetch the full onboarding JSON
    public let url: String

    /// Version ID for this specific onboarding version
    public let version_id: String?
}

/// Top-level onboarding reference in manifest (metadata only)
public struct ManifestOnboarding: Decodable {
    /// Unique identifier for the onboarding
    public let id: String

    /// Display name of the onboarding
    public let name: String

    /// Status (draft, published, etc.)
    public let status: String?

    /// Version number
    public let version: Int?

    /// URL to fetch the full onboarding JSON
    public let url: String
}
