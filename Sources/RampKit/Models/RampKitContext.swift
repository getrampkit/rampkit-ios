import Foundation

/// Context data passed to WebViews for template resolution
/// Contains device and user information that can be used in onboarding templates
/// e.g., ${device.platform}, ${user.id}, ${device.currencySymbol}
public struct RampKitContext: Codable {
    
    // MARK: - Nested Types
    
    /// Device-related context variables
    public struct Device: Codable {
        /// Platform name ("iOS", "iPadOS", "macOS")
        public let platform: String
        
        /// Device model identifier (e.g. "iPhone14,3")
        public let model: String
        
        /// Full locale identifier (e.g. "en_US")
        public let locale: String
        
        /// Language code (e.g. "en")
        public let language: String
        
        /// Country/region code (e.g. "US")
        public let country: String
        
        /// Currency code (e.g. "USD")
        public let currencyCode: String
        
        /// Currency symbol (e.g. "$")
        public let currencySymbol: String
        
        /// App marketing version (e.g. "1.0.0")
        public let appVersion: String
        
        /// App build number (e.g. "123")
        public let buildNumber: String
        
        /// Bundle identifier (e.g. "com.example.app")
        public let bundleId: String
        
        /// Interface style ("light", "dark", or "unspecified")
        public let interfaceStyle: String
        
        /// Timezone offset in seconds from GMT
        public let timezone: Int
        
        /// Days since app was first installed
        public let daysSinceInstall: Int
    }
    
    /// User-related context variables
    public struct User: Codable {
        /// RampKit generated user ID
        public let id: String
        
        /// Whether this is the user's first session
        public let isNewUser: Bool
        
        /// Whether user came from Apple Search Ads
        public let hasAppleSearchAdsAttribution: Bool
        
        /// Current session ID
        public let sessionId: String
        
        /// ISO date string of when app was first installed
        public let installedAt: String
    }
    
    // MARK: - Properties
    
    public let device: Device
    public let user: User
    
    // MARK: - Factory Methods
    
    /// Build context from DeviceInfo
    /// - Parameter deviceInfo: Collected device information
    /// - Returns: RampKitContext ready for WebView injection
    public static func build(from deviceInfo: DeviceInfo) -> RampKitContext {
        let device = Device(
            platform: deviceInfo.platform,
            model: deviceInfo.deviceModel,
            locale: deviceInfo.deviceLocale,
            language: deviceInfo.deviceLanguageCode ?? "en",
            country: deviceInfo.regionCode ?? "US",
            currencyCode: deviceInfo.deviceCurrencyCode ?? "USD",
            currencySymbol: deviceInfo.deviceCurrencySymbol ?? "$",
            appVersion: deviceInfo.appVersion ?? "",
            buildNumber: deviceInfo.buildNumber ?? "",
            bundleId: deviceInfo.bundleId ?? "",
            interfaceStyle: deviceInfo.interfaceStyle,
            timezone: deviceInfo.timezoneOffsetSeconds,
            daysSinceInstall: calculateDaysSinceInstall(from: deviceInfo.installDate)
        )
        
        let user = User(
            id: deviceInfo.appUserId,
            isNewUser: deviceInfo.isFirstLaunch,
            hasAppleSearchAdsAttribution: deviceInfo.isAppleSearchAdsAttribution,
            sessionId: deviceInfo.appSessionId,
            installedAt: deviceInfo.installDate
        )
        
        return RampKitContext(device: device, user: user)
    }
    
    /// Build a default/fallback context when DeviceInfo is not available
    /// This ensures templates still get resolved (with placeholder values)
    public static func buildDefault(userId: String?) -> RampKitContext {
        let now = ISO8601DateFormatter().string(from: Date())
        
        // Use version-compatible locale APIs
        let languageCode: String
        let regionCode: String
        let currencyCode: String
        
        if #available(iOS 16, macOS 13, *) {
            languageCode = Locale.current.language.languageCode?.identifier ?? "en"
            regionCode = Locale.current.region?.identifier ?? "US"
            currencyCode = Locale.current.currency?.identifier ?? "USD"
        } else {
            languageCode = Locale.current.languageCode ?? "en"
            regionCode = Locale.current.regionCode ?? "US"
            currencyCode = Locale.current.currencyCode ?? "USD"
        }
        
        let device = Device(
            platform: "iOS",
            model: "Unknown",
            locale: Locale.current.identifier,
            language: languageCode,
            country: regionCode,
            currencyCode: currencyCode,
            currencySymbol: Locale.current.currencySymbol ?? "$",
            appVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "",
            buildNumber: Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "",
            bundleId: Bundle.main.bundleIdentifier ?? "",
            interfaceStyle: "unspecified",
            timezone: TimeZone.current.secondsFromGMT(),
            daysSinceInstall: 0
        )
        
        let user = User(
            id: userId ?? ("rk_" + UUID().uuidString.lowercased()),
            isNewUser: true,
            hasAppleSearchAdsAttribution: false,
            sessionId: UUID().uuidString.lowercased(),
            installedAt: now
        )
        
        return RampKitContext(device: device, user: user)
    }
    
    // MARK: - Private Helpers
    
    /// Calculate days since install from ISO date string
    private static func calculateDaysSinceInstall(from installDateString: String) -> Int {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        
        guard let installDate = formatter.date(from: installDateString) else {
            // Try without fractional seconds
            formatter.formatOptions = [.withInternetDateTime]
            guard let installDate = formatter.date(from: installDateString) else {
                return 0
            }
            return daysBetween(installDate, and: Date())
        }
        
        return daysBetween(installDate, and: Date())
    }
    
    private static func daysBetween(_ start: Date, and end: Date) -> Int {
        let calendar = Calendar.current
        let components = calendar.dateComponents([.day], from: start, to: end)
        return max(0, components.day ?? 0)
    }
    
    // MARK: - JSON Serialization
    
    /// Serialize to JSON string for JavaScript injection
    public func toJSONString() -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = []  // Compact output for injection
        
        do {
            let data = try encoder.encode(self)
            return String(data: data, encoding: .utf8) ?? "{}"
        } catch {
            return "{}"
        }
    }
    
    /// Build JavaScript code to inject context into window
    public func toInjectionScript() -> String {
        return "window.rampkitContext = \(toJSONString());"
    }
}

