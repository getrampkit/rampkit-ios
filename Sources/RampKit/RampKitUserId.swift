import Foundation

/// Manager for generating and persisting stable user identifiers
public class RampKitUserId {
    /// Keychain key for storing user ID
    static let userIdKey = "rk_user_id"
    
    /// Prefix for all RampKit user IDs
    private static let userIdPrefix = "rk_"
    
    /// Get or generate a stable user ID
    /// - Returns: Prefixed UUID string (rk_xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx)
    @available(iOS 14.0, macOS 11.0, *)
    public static func getRampKitUserId() async -> String {
        // Check Keychain for existing ID
        if let existingId = KeychainHelper.retrieve(key: userIdKey) {
            // Migrate old IDs without prefix (if any)
            if !existingId.hasPrefix(userIdPrefix) {
                let prefixedId = userIdPrefix + existingId
                do {
                    try KeychainHelper.save(key: userIdKey, value: prefixedId)
                } catch {
                    RampKitLogger.warn("UserId", "Failed to migrate ID: \(error)")
                }
                return prefixedId
            }
            return existingId
        }
        
        // Generate new prefixed UUID v4
        let newId = generatePrefixedUuid()
        
        // Store in Keychain
        do {
            try KeychainHelper.save(key: userIdKey, value: newId)
        } catch {
            RampKitLogger.warn("UserId", "Failed to save to Keychain: \(error)")
        }
        
        return newId
    }
    
    /// Generate a cryptographically secure UUID v4 with rk_ prefix
    /// - Returns: rk_xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx
    private static func generatePrefixedUuid() -> String {
        return userIdPrefix + UUID().uuidString.lowercased()
    }
}

