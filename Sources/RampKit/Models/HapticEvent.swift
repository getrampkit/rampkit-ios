import Foundation

/// Haptic feedback event types
public struct HapticEvent {
    public let hapticType: HapticType
    public let impactStyle: ImpactStyle?
    public let notificationType: NotificationType?
    
    public enum HapticType: String {
        case impact
        case notification
        case selection
    }
    
    public enum ImpactStyle: String {
        case light = "Light"
        case medium = "Medium"
        case heavy = "Heavy"
        case rigid = "Rigid"
        case soft = "Soft"
    }
    
    public enum NotificationType: String {
        case success = "Success"
        case warning = "Warning"
        case error = "Error"
    }
}

/// Notification permission request options
public struct NotificationPermissionOptions {
    public let allowAlert: Bool
    public let allowBadge: Bool
    public let allowSound: Bool
    public let channelId: String?
    public let channelName: String?
    public let importance: String?
    public let shouldShowBanner: Bool?
    public let shouldPlaySound: Bool?
    
    public init(
        allowAlert: Bool = true,
        allowBadge: Bool = true,
        allowSound: Bool = true,
        channelId: String? = nil,
        channelName: String? = nil,
        importance: String? = nil,
        shouldShowBanner: Bool? = nil,
        shouldPlaySound: Bool? = nil
    ) {
        self.allowAlert = allowAlert
        self.allowBadge = allowBadge
        self.allowSound = allowSound
        self.channelId = channelId
        self.channelName = channelName
        self.importance = importance
        self.shouldShowBanner = shouldShowBanner
        self.shouldPlaySound = shouldPlaySound
    }
}

/// Notification permission result
public struct NotificationPermissionResult {
    public let granted: Bool
    public let status: String
    public let canAskAgain: Bool
    public let error: Bool
}







