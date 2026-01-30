import Foundation

/// Main RampKit SDK interface
/// Provides access to the singleton instance and utility functions
public let RampKit = RampKitCore.shared

/// Get or generate a stable user ID
/// - Returns: UUID v4 string stored securely in Keychain
@available(iOS 14.0, macOS 11.0, *)
public func getRampKitUserId() async -> String {
    return await RampKitUserId.getRampKitUserId()
}

