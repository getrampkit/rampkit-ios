import Foundation

/// Manages persistent storage of onboarding variables
enum OnboardingResponseStorage {
    private static let storageKey = "rk_onboarding_variables"

    /// Initialize with initial values from onboarding config
    static func initializeVariables(_ variables: [String: Any]) {
        do {
            let data = try JSONSerialization.data(withJSONObject: variables)
            if let jsonString = String(data: data, encoding: .utf8) {
                try KeychainHelper.save(key: storageKey, value: jsonString)
                RampKitLogger.verbose("Storage", "Initialized variables: \(variables.keys.joined(separator: ", "))")
            }
        } catch {
            RampKitLogger.warn("Storage", "Failed to initialize variables: \(error.localizedDescription)")
        }
    }

    /// Update variables (merges with existing)
    static func updateVariables(_ newVariables: [String: Any]) {
        var current = getVariables()
        for (key, value) in newVariables {
            current[key] = value
        }

        do {
            let data = try JSONSerialization.data(withJSONObject: current)
            if let jsonString = String(data: data, encoding: .utf8) {
                try KeychainHelper.save(key: storageKey, value: jsonString)
                RampKitLogger.verbose("Storage", "Updated variables: \(newVariables.keys.joined(separator: ", "))")
            }
        } catch {
            RampKitLogger.warn("Storage", "Failed to update variables: \(error.localizedDescription)")
        }
    }

    /// Get stored variables
    static func getVariables() -> [String: Any] {
        guard let jsonString = KeychainHelper.retrieve(key: storageKey),
              let data = jsonString.data(using: .utf8) else {
            return [:]
        }

        do {
            if let variables = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                return variables
            }
            return [:]
        } catch {
            RampKitLogger.warn("Storage", "Failed to get variables: \(error.localizedDescription)")
            return [:]
        }
    }

    /// Clear all stored variables
    static func clearVariables() {
        do {
            try KeychainHelper.delete(key: storageKey)
            RampKitLogger.verbose("Storage", "Cleared all variables")
        } catch {
            RampKitLogger.warn("Storage", "Failed to clear variables: \(error.localizedDescription)")
        }
    }
}
