import Foundation

/// Centralized logging for RampKit SDK
/// By default, only minimal logs are shown (like RevenueCat SDK).
/// Enable verboseLogging in RampKitConfig for detailed debug output.
public struct RampKitLogger {
    /// Whether verbose logging is enabled (set via RampKitConfig.verboseLogging)
    private(set) static var verboseLogging = false

    /// Enable or disable verbose logging
    /// Called internally by RampKit.configure() based on config
    static func setVerboseLogging(_ enabled: Bool) {
        verboseLogging = enabled
    }

    /// Log an info message (always shown - for SDK lifecycle events)
    /// Format: [RampKit] message
    static func info(_ message: String) {
        print("[RampKit] \(message)")
    }

    /// Log a verbose message (only shown when verboseLogging is enabled)
    /// Format: [RampKit] Context: message
    static func verbose(_ context: String, _ message: String) {
        if verboseLogging {
            print("[RampKit] \(context): \(message)")
        }
    }

    /// Log a warning message (always shown)
    /// Format: [RampKit] ⚠️ Context: message
    static func warn(_ context: String, _ message: String) {
        print("[RampKit] ⚠️ \(context): \(message)")
    }

    /// Log an error with context (always shown)
    /// Format: [RampKit] ❌ Context: error
    static func error(_ context: String, _ error: Error) {
        print("[RampKit] ❌ \(context): \(error.localizedDescription)")
    }

    // MARK: - Legacy API (deprecated, maps to verbose)

    /// Log a message with context (deprecated - use verbose/info/warn instead)
    /// This method maintains backward compatibility but now respects verboseLogging
    @available(*, deprecated, message: "Use verbose(), info(), warn(), or error() instead")
    static func log(_ context: String, _ message: String) {
        verbose(context, message)
    }

    /// Log an error with context (deprecated - use error() instead)
    @available(*, deprecated, message: "Use error() instead")
    static func logError(_ context: String, _ error: Error) {
        self.error(context, error)
    }
}
