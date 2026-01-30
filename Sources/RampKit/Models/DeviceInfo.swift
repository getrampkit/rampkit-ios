import Foundation

/// Comprehensive device and session information for analytics
/// This data is collected during SDK initialization for backend analytics
public struct DeviceInfo: Codable {
    // MARK: - User & Session Identifiers

    /// RampKit generated user ID (persisted in Keychain)
    public let appUserId: String

    /// Custom App User ID provided by the developer.
    /// This is an alias for their own user identification system.
    /// Does NOT replace appUserId - RampKit still uses its own generated ID.
    public var appUserID: String?

    /// Apple's vendor identifier (resets on app reinstall)
    public let vendorId: String?

    /// Unique session ID (generated fresh each app launch)
    public let appSessionId: String
    
    /// First installation date (persisted in UserDefaults)
    public let installDate: String
    
    /// Whether this is the first launch ever
    public let isFirstLaunch: Bool
    
    /// Number of times the app has been launched
    public let launchCount: Int
    
    /// Timestamp of last launch (before this one)
    public let lastLaunchAt: String?
    
    // MARK: - App Information
    
    /// Bundle identifier (e.g. "com.example.app")
    public let bundleId: String?
    
    /// App display name
    public let appName: String?
    
    /// App marketing version (CFBundleShortVersionString)
    public let appVersion: String?
    
    /// App build number (CFBundleVersion)
    public let buildNumber: String?
    
    /// RampKit SDK version
    public let sdkVersion: String
    
    // MARK: - Platform Information
    
    /// Platform name ("iOS", "iPadOS", "macOS", etc.)
    public let platform: String
    
    /// Platform/OS version (e.g. "17.3.0")
    public let platformVersion: String
    
    /// Platform wrapper if using React Native, Flutter, etc.
    public let platformWrapper: String?
    
    // MARK: - Device Information
    
    /// Device model identifier (e.g. "iPhone14,3")
    public let deviceModel: String
    
    /// Device marketing name (e.g. "iPhone", "iPad")
    public let deviceName: String
    
    /// Whether running on simulator
    public let isSimulator: Bool
    
    // MARK: - Locale & Language
    
    /// Device language code (e.g. "en", "fr")
    public let deviceLanguageCode: String?
    
    /// Full locale identifier (e.g. "en_US", "fr_FR")
    public let deviceLocale: String
    
    /// Region code (e.g. "US", "AU")
    public let regionCode: String?
    
    /// User's preferred language (first in list)
    public let preferredLanguage: String?
    
    /// All preferred languages in order
    public let preferredLanguages: [String]
    
    // MARK: - Currency
    
    /// Device currency code (e.g. "USD", "EUR")
    public let deviceCurrencyCode: String?
    
    /// Device currency symbol (e.g. "$", "€")
    public let deviceCurrencySymbol: String?
    
    // MARK: - Timezone
    
    /// Timezone identifier (e.g. "America/New_York")
    public let timezoneIdentifier: String
    
    /// Timezone offset in seconds from GMT
    public let timezoneOffsetSeconds: Int
    
    // MARK: - Display & UI
    
    /// Interface style ("light", "dark", or "unspecified")
    public let interfaceStyle: String
    
    /// Screen width in points
    public let screenWidth: Double
    
    /// Screen height in points
    public let screenHeight: Double
    
    /// Screen scale factor (e.g. 2.0, 3.0)
    public let screenScale: Double
    
    // MARK: - Device State
    
    /// Whether low power mode is enabled
    public let isLowPowerMode: Bool
    
    // MARK: - Storage & Memory
    
    /// Free disk space in bytes
    public let freeStorageBytes: Int64?
    
    /// Total disk space in bytes
    public let totalStorageBytes: Int64?
    
    /// Total physical memory in bytes
    public let totalMemoryBytes: UInt64
    
    // MARK: - Attribution
    
    /// Whether Apple Search Ads attribution is available
    public let isAppleSearchAdsAttribution: Bool
    
    /// Apple Search Ads attribution token (if available)
    public let appleSearchAdsToken: String?
    
    // MARK: - SDK Capabilities
    
    /// List of SDK capabilities/features
    public let capabilities: [String]
    
    // MARK: - Network (basic)
    
    /// Network connection type ("wifi", "cellular", "unknown")
    public let connectionType: String?
    
    // MARK: - Timestamps

    /// When this info was collected (ISO 8601)
    public let collectedAt: String

    // MARK: - Targeting (set after target evaluation)

    /// The ID of the matched target
    public var matchedTargetId: String?

    /// The name of the matched target
    public var matchedTargetName: String?

    /// The ID of the selected onboarding
    public var matchedOnboardingId: String?

    /// The version ID of the selected onboarding
    public var matchedOnboardingVersionId: String?

    /// The A/B test bucket (0-99) for deterministic allocation
    public var abTestBucket: Int?
}

