import Foundation

/// Configuration object for initializing RampKit SDK
public struct RampKitConfig {
    /// App ID for fetching manifest (required)
    public let appId: String

    /// API key for authentication (optional)
    public let apiKey: String?

    /// Environment setting ("production" or "staging")
    public let environment: String?

    /// Whether to automatically show onboarding after initialization
    public let autoShowOnboarding: Bool?

    /// Callback invoked when onboarding is finished
    public let onOnboardingFinished: ((Any?) -> Void)?

    /// Callback invoked when paywall should be shown
    public let onShowPaywall: ((Any?) -> Void)?

    /// Alias for onShowPaywall (for compatibility)
    public let showPaywall: ((Any?) -> Void)?

    /// Custom onboarding URL for testing/staging (overrides manifest fetch)
    public let customOnboardingURL: String?

    /// Enable test mode with mock data
    public let testMode: Bool?

    /// Platform wrapper identifier (e.g. "React Native", "Flutter", "Capacitor", "Cordova")
    /// Used for analytics to understand which wrapper SDK is being used
    public let platformWrapper: String?

    /// Optional custom App User ID to associate with this user.
    /// This is an alias for your own user identification system - it does NOT replace
    /// the RampKit-generated user ID (appUserId). RampKit will continue to generate
    /// and use its own stable UUID for internal tracking.
    ///
    /// Use this to link RampKit analytics with your own user database.
    /// Can also be set later via `RampKit.setAppUserID()`.
    public let appUserID: String?

    /// Enable verbose logging for debugging.
    /// When true, additional debug information will be logged to the console.
    /// Default is false for minimal logging (like RevenueCat SDK).
    public let verboseLogging: Bool

    public init(
        appId: String,
        apiKey: String? = nil,
        environment: String? = nil,
        autoShowOnboarding: Bool? = nil,
        onOnboardingFinished: ((Any?) -> Void)? = nil,
        onShowPaywall: ((Any?) -> Void)? = nil,
        showPaywall: ((Any?) -> Void)? = nil,
        customOnboardingURL: String? = nil,
        testMode: Bool? = nil,
        platformWrapper: String? = nil,
        appUserID: String? = nil,
        verboseLogging: Bool = false
    ) {
        self.appId = appId
        self.apiKey = apiKey
        self.environment = environment
        self.autoShowOnboarding = autoShowOnboarding
        self.onOnboardingFinished = onOnboardingFinished
        self.onShowPaywall = onShowPaywall
        self.showPaywall = showPaywall
        self.customOnboardingURL = customOnboardingURL
        self.testMode = testMode
        self.platformWrapper = platformWrapper
        self.appUserID = appUserID
        self.verboseLogging = verboseLogging
    }
}

/// Options for showing onboarding
public struct ShowOnboardingOptions {
    /// Callback invoked when paywall should be shown
    public let onShowPaywall: ((Any?) -> Void)?
    
    public init(onShowPaywall: ((Any?) -> Void)? = nil) {
        self.onShowPaywall = onShowPaywall
    }
}


