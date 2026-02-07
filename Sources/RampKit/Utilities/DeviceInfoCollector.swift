import Foundation
#if canImport(UIKit)
import UIKit
#endif
#if canImport(AdServices)
import AdServices
#endif

/// Utility for collecting comprehensive device and session information
enum DeviceInfoCollector {
    
    // MARK: - UserDefaults Keys
    
    private static let installDateKey = "rk_install_date"
    private static let launchCountKey = "rk_launch_count"
    private static let lastLaunchKey = "rk_last_launch"
    
    // MARK: - SDK Version
    
    /// Current RampKit SDK version
    static let sdkVersion = "0.0.114"
    
    // MARK: - Cached Values (computed once)
    
    /// Cached device model (expensive to compute via reflection)
    private static var cachedDeviceModel: String?
    
    // MARK: - Main Collection Method
    
    /// Collect all device and session information (fast path - skips slow operations)
    /// - Parameters:
    ///   - appUserId: The RampKit user ID
    ///   - platformWrapper: Optional platform wrapper name (e.g. "React Native", "Flutter")
    /// - Returns: DeviceInfo struct with all collected data
    @available(iOS 14.0, macOS 11.0, *)
    static func collect(appUserId: String, platformWrapper: String? = nil) -> DeviceInfo {
        let now = Date()
        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        
        // Handle install date and launch tracking (fast - just UserDefaults)
        let (installDate, isFirstLaunch, launchCount, lastLaunchAt) = trackLaunchInfo(now: now, formatter: isoFormatter)
        
        // Generate session ID (fast)
        let sessionId = UUID().uuidString.lowercased()
        
        // Get cached or compute device model once
        let deviceModel = cachedDeviceModel ?? {
            let model = getDeviceModelIdentifier()
            cachedDeviceModel = model
            return model
        }()
        
        // Collect FAST info only - skip slow operations
        return DeviceInfo(
            // User & Session
            appUserId: appUserId,
            vendorId: getVendorId(),
            appSessionId: sessionId,
            installDate: installDate,
            isFirstLaunch: isFirstLaunch,
            launchCount: launchCount,
            lastLaunchAt: lastLaunchAt,
            
            // App Info (all cached in Bundle)
            bundleId: Bundle.main.bundleIdentifier,
            appName: getAppName(),
            appVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String,
            buildNumber: Bundle.main.infoDictionary?["CFBundleVersion"] as? String,
            sdkVersion: sdkVersion,
            
            // Platform (fast)
            platform: getPlatformName(),
            platformVersion: getPlatformVersion(),
            platformWrapper: platformWrapper,
            
            // Device (cached)
            deviceModel: deviceModel,
            deviceName: getDeviceName(),
            isSimulator: isRunningOnSimulator(),
            
            // Locale & Language (fast - cached by system)
            deviceLanguageCode: getLanguageCode(),
            deviceLocale: Locale.current.identifier,
            regionCode: getRegionCode(),
            preferredLanguage: Locale.preferredLanguages.first,
            preferredLanguages: Locale.preferredLanguages,
            
            // Currency (fast)
            deviceCurrencyCode: getCurrencyCode(),
            deviceCurrencySymbol: Locale.current.currencySymbol,
            
            // Timezone (fast)
            timezoneIdentifier: TimeZone.current.identifier,
            timezoneOffsetSeconds: TimeZone.current.secondsFromGMT(),
            
            // Display & UI (fast)
            interfaceStyle: getInterfaceStyleFast(),
            screenWidth: getScreenWidth(),
            screenHeight: getScreenHeight(),
            screenScale: getScreenScale(),
            
            // Device State (fast)
            isLowPowerMode: ProcessInfo.processInfo.isLowPowerModeEnabled,
            
            // Storage & Memory - SKIP slow disk queries, use nil
            freeStorageBytes: nil,
            totalStorageBytes: nil,
            totalMemoryBytes: ProcessInfo.processInfo.physicalMemory,
            
            // Attribution - SKIP slow AAAttribution call
            isAppleSearchAdsAttribution: false,
            appleSearchAdsToken: nil,
            
            // Capabilities (fast)
            capabilities: getCapabilities(),
            
            // Network
            connectionType: nil,
            
            // Timestamp
            collectedAt: isoFormatter.string(from: now)
        )
    }
    
    // MARK: - Launch Tracking
    
    private static func trackLaunchInfo(now: Date, formatter: ISO8601DateFormatter) -> (installDate: String, isFirstLaunch: Bool, launchCount: Int, lastLaunchAt: String?) {
        let defaults = UserDefaults.standard
        
        // Check if this is first launch
        let existingInstallDate = defaults.string(forKey: installDateKey)
        let isFirstLaunch = existingInstallDate == nil
        
        // Get or set install date
        let installDate: String
        if let existing = existingInstallDate {
            installDate = existing
        } else {
            installDate = formatter.string(from: now)
            defaults.set(installDate, forKey: installDateKey)
        }
        
        // Get last launch timestamp
        let lastLaunchAt = defaults.string(forKey: lastLaunchKey)
        
        // Increment launch count
        let previousCount = defaults.integer(forKey: launchCountKey)
        let launchCount = previousCount + 1
        defaults.set(launchCount, forKey: launchCountKey)
        
        // Update last launch time (for next session)
        defaults.set(formatter.string(from: now), forKey: lastLaunchKey)
        
        return (installDate, isFirstLaunch, launchCount, lastLaunchAt)
    }
    
    // MARK: - Device Identifiers
    
    private static func getVendorId() -> String? {
        #if os(iOS)
        return UIDevice.current.identifierForVendor?.uuidString
        #else
        return nil
        #endif
    }
    
    // MARK: - App Info
    
    private static func getAppName() -> String? {
        return Bundle.main.infoDictionary?["CFBundleDisplayName"] as? String
            ?? Bundle.main.infoDictionary?["CFBundleName"] as? String
    }
    
    // MARK: - Platform
    
    private static func getPlatformName() -> String {
        #if os(iOS)
        if UIDevice.current.userInterfaceIdiom == .pad {
            return "iPadOS"
        }
        return "iOS"
        #elseif os(macOS)
        return "macOS"
        #elseif os(watchOS)
        return "watchOS"
        #elseif os(tvOS)
        return "tvOS"
        #elseif os(visionOS)
        return "visionOS"
        #else
        return "unknown"
        #endif
    }
    
    private static func getPlatformVersion() -> String {
        #if os(iOS)
        return UIDevice.current.systemVersion
        #else
        let version = ProcessInfo.processInfo.operatingSystemVersion
        return "\(version.majorVersion).\(version.minorVersion).\(version.patchVersion)"
        #endif
    }
    
    // MARK: - Device Model
    
    private static func getDeviceModelIdentifier() -> String {
        var systemInfo = utsname()
        uname(&systemInfo)
        let machineMirror = Mirror(reflecting: systemInfo.machine)
        let identifier = machineMirror.children.reduce("") { identifier, element in
            guard let value = element.value as? Int8, value != 0 else { return identifier }
            return identifier + String(UnicodeScalar(UInt8(value)))
        }
        return identifier
    }
    
    private static func getDeviceName() -> String {
        #if os(iOS)
        return UIDevice.current.model
        #else
        return Host.current().localizedName ?? "Mac"
        #endif
    }
    
    private static func isRunningOnSimulator() -> Bool {
        #if targetEnvironment(simulator)
        return true
        #else
        return false
        #endif
    }
    
    // MARK: - Locale & Language
    
    private static func getLanguageCode() -> String? {
        if #available(iOS 16, macOS 13, *) {
            return Locale.current.language.languageCode?.identifier
        } else {
            return Locale.current.languageCode
        }
    }
    
    private static func getRegionCode() -> String? {
        if #available(iOS 16, macOS 13, *) {
            return Locale.current.region?.identifier
        } else {
            return Locale.current.regionCode
        }
    }
    
    private static func getCurrencyCode() -> String? {
        if #available(iOS 16, macOS 13, *) {
            return Locale.current.currency?.identifier
        } else {
            return Locale.current.currencyCode
        }
    }
    
    // MARK: - Display & UI
    
    /// Fast interface style check - uses UITraitCollection directly without scene iteration
    private static func getInterfaceStyleFast() -> String {
        #if os(iOS)
        // Use UITraitCollection.current which is faster than iterating scenes
        let style = UITraitCollection.current.userInterfaceStyle
        switch style {
        case .dark:
            return "dark"
        case .light:
            return "light"
        case .unspecified:
            return "unspecified"
        @unknown default:
            return "unspecified"
        }
        #else
        return "unspecified"
        #endif
    }
    
    private static func getScreenWidth() -> Double {
        #if os(iOS)
        return Double(UIScreen.main.bounds.width)
        #else
        return 0
        #endif
    }
    
    private static func getScreenHeight() -> Double {
        #if os(iOS)
        return Double(UIScreen.main.bounds.height)
        #else
        return 0
        #endif
    }
    
    private static func getScreenScale() -> Double {
        #if os(iOS)
        return Double(UIScreen.main.scale)
        #else
        return 1.0
        #endif
    }
    
    // MARK: - Storage
    
    private static func getFreeStorage() -> Int64? {
        do {
            let homeURL = URL(fileURLWithPath: NSHomeDirectory())
            let values = try homeURL.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
            return values.volumeAvailableCapacityForImportantUsage
        } catch {
            return nil
        }
    }
    
    private static func getTotalStorage() -> Int64? {
        do {
            let homeURL = URL(fileURLWithPath: NSHomeDirectory())
            let values = try homeURL.resourceValues(forKeys: [.volumeTotalCapacityKey])
            if let totalCapacity = values.volumeTotalCapacity {
                return Int64(totalCapacity)
            }
            return nil
        } catch {
            return nil
        }
    }
    
    // MARK: - Attribution
    
    private static func getAppleSearchAdsToken() -> String? {
        #if canImport(AdServices)
        if #available(iOS 14.3, *) {
            do {
                return try AAAttribution.attributionToken()
            } catch {
                return nil
            }
        }
        #endif
        return nil
    }
    
    // MARK: - Capabilities
    
    private static func getCapabilities() -> [String] {
        var capabilities: [String] = []
        
        // Core capabilities
        capabilities.append("onboarding")
        capabilities.append("paywall_event_receiver")
        capabilities.append("multiple_paywall_urls")
        capabilities.append("haptic_feedback")
        capabilities.append("push_notifications")
        capabilities.append("store_review")
        capabilities.append("device_info_collection")
        
        #if os(iOS)
        capabilities.append("ios_native")
        #endif
        
        return capabilities
    }
    
    // MARK: - JSON Output
    
    /// Convert DeviceInfo to pretty-printed JSON string
    static func toJSON(_ deviceInfo: DeviceInfo) -> String? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        
        do {
            let data = try encoder.encode(deviceInfo)
            return String(data: data, encoding: .utf8)
        } catch {
            return nil
        }
    }
}

