import Foundation

/// Context used for evaluating targeting rules
/// Maps SDK device info to the attribute structure used by targeting rules
public struct TargetingContext {
    public let user: UserContext
    public let device: DeviceContext
    public let app: AppContext
    public let asa: ASAContext
    public let cpp: CPPContext

    public struct UserContext {
        public let isNewUser: Bool
        public let daysSinceInstall: Int
        public let subscriptionStatus: String?
        public let hasAppleSearchAdsAttribution: Bool
    }

    public struct DeviceContext {
        public let platform: String
        public let model: String
        public let osVersion: String
        public let interfaceStyle: String
        public let country: String
        public let language: String
        public let locale: String
        public let currencyCode: String
    }

    public struct AppContext {
        public let version: String
        public let buildNumber: String
        public let sdkVersion: String
    }

    public struct ASAContext {
        public let keyword: String?
        public let campaignId: String?
    }

    public struct CPPContext {
        public let pageId: String?
    }
}

/// Builds targeting context from DeviceInfo
public enum TargetingContextBuilder {

    /// Build targeting context from DeviceInfo
    /// - Parameter deviceInfo: The collected device information (can be nil)
    /// - Returns: TargetingContext for rule evaluation
    public static func build(from deviceInfo: DeviceInfo?) -> TargetingContext {
        guard let deviceInfo = deviceInfo else {
            return buildDefault()
        }

        // Calculate days since install
        let daysSinceInstall = calculateDaysSinceInstall(from: deviceInfo.installDate)

        // Extract country from regionCode or locale
        let country = deviceInfo.regionCode ?? extractCountryFromLocale(deviceInfo.deviceLocale) ?? "US"

        // Extract language from deviceLanguageCode or locale
        let language = deviceInfo.deviceLanguageCode ?? extractLanguageFromLocale(deviceInfo.deviceLocale) ?? "en"

        return TargetingContext(
            user: TargetingContext.UserContext(
                isNewUser: deviceInfo.isFirstLaunch,
                daysSinceInstall: daysSinceInstall,
                subscriptionStatus: nil, // Not yet collected
                hasAppleSearchAdsAttribution: deviceInfo.isAppleSearchAdsAttribution
            ),
            device: TargetingContext.DeviceContext(
                platform: deviceInfo.platform,
                model: deviceInfo.deviceModel,
                osVersion: deviceInfo.platformVersion,
                interfaceStyle: deviceInfo.interfaceStyle,
                country: country,
                language: language,
                locale: deviceInfo.deviceLocale,
                currencyCode: deviceInfo.deviceCurrencyCode ?? "USD"
            ),
            app: TargetingContext.AppContext(
                version: deviceInfo.appVersion ?? "1.0.0",
                buildNumber: deviceInfo.buildNumber ?? "1",
                sdkVersion: deviceInfo.sdkVersion
            ),
            asa: TargetingContext.ASAContext(
                keyword: nil, // Not yet collected
                campaignId: nil // Not yet collected
            ),
            cpp: TargetingContext.CPPContext(
                pageId: nil // Not yet collected
            )
        )
    }

    /// Build default context when DeviceInfo is not available
    private static func buildDefault() -> TargetingContext {
        return TargetingContext(
            user: TargetingContext.UserContext(
                isNewUser: true,
                daysSinceInstall: 0,
                subscriptionStatus: nil,
                hasAppleSearchAdsAttribution: false
            ),
            device: TargetingContext.DeviceContext(
                platform: "iOS",
                model: "unknown",
                osVersion: "0",
                interfaceStyle: "light",
                country: "US",
                language: "en",
                locale: "en_US",
                currencyCode: "USD"
            ),
            app: TargetingContext.AppContext(
                version: "1.0.0",
                buildNumber: "1",
                sdkVersion: DeviceInfoCollector.sdkVersion
            ),
            asa: TargetingContext.ASAContext(
                keyword: nil,
                campaignId: nil
            ),
            cpp: TargetingContext.CPPContext(
                pageId: nil
            )
        )
    }

    /// Calculate days since install from install date string
    private static func calculateDaysSinceInstall(from installDateString: String) -> Int {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        guard let installDate = formatter.date(from: installDateString) else {
            return 0
        }

        let calendar = Calendar.current
        let components = calendar.dateComponents([.day], from: installDate, to: Date())
        return max(0, components.day ?? 0)
    }

    /// Extract country code from locale identifier (e.g., "en_US" -> "US")
    private static func extractCountryFromLocale(_ locale: String) -> String? {
        let parts = locale.split(separator: "_")
        if parts.count >= 2 {
            return String(parts[1])
        }
        return nil
    }

    /// Extract language code from locale identifier (e.g., "en_US" -> "en")
    private static func extractLanguageFromLocale(_ locale: String) -> String? {
        let parts = locale.split(separator: "_")
        if parts.count >= 1 {
            return String(parts[0])
        }
        return nil
    }
}
