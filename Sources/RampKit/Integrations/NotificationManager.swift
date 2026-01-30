import Foundation
#if canImport(UserNotifications)
import UserNotifications
#endif

/// Manager for notification permissions
enum NotificationManager {
    
    /// Request notification permissions
    @available(iOS 10.0, macOS 10.14, *)
    static func requestNotificationPermission(
        options: NotificationPermissionOptions,
        completion: @escaping (NotificationPermissionResult) -> Void
    ) {
        #if os(iOS) || os(macOS)
        var authOptions: UNAuthorizationOptions = []
        
        if options.allowAlert {
            authOptions.insert(.alert)
        }
        if options.allowBadge {
            authOptions.insert(.badge)
        }
        if options.allowSound {
            authOptions.insert(.sound)
        }
        
        UNUserNotificationCenter.current()
            .requestAuthorization(options: authOptions) { granted, error in
                let result = NotificationPermissionResult(
                    granted: granted,
                    status: granted ? "granted" : "denied",
                    canAskAgain: !granted,
                    error: error != nil
                )
                
                DispatchQueue.main.async {
                    completion(result)
                }
            }
        #else
        // Not available on this platform
        let result = NotificationPermissionResult(
            granted: false,
            status: "unavailable",
            canAskAgain: false,
            error: true
        )
        DispatchQueue.main.async {
            completion(result)
        }
        #endif
    }
    
    /// Get current notification permission status
    @available(iOS 10.0, macOS 10.14, *)
    static func getNotificationPermissionStatus(completion: @escaping (NotificationPermissionResult) -> Void) {
        #if os(iOS) || os(macOS)
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            let granted = settings.authorizationStatus == .authorized
            let status: String
            
            switch settings.authorizationStatus {
            case .authorized:
                status = "granted"
            case .denied:
                status = "denied"
            case .notDetermined:
                status = "undetermined"
            case .provisional:
                status = "provisional"
            case .ephemeral:
                status = "ephemeral"
            @unknown default:
                status = "undetermined"
            }
            
            let result = NotificationPermissionResult(
                granted: granted,
                status: status,
                canAskAgain: settings.authorizationStatus == .notDetermined,
                error: false
            )
            
            DispatchQueue.main.async {
                completion(result)
            }
        }
        #else
        // Not available on this platform
        let result = NotificationPermissionResult(
            granted: false,
            status: "unavailable",
            canAskAgain: false,
            error: true
        )
        DispatchQueue.main.async {
            completion(result)
        }
        #endif
    }
}
