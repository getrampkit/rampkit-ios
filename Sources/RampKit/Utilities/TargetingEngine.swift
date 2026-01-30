import Foundation

/// Result of target evaluation including metadata for logging/analytics
public struct TargetEvaluationResult {
    /// The selected onboarding
    public let onboarding: TargetOnboarding

    /// The matched target ID
    public let targetId: String

    /// The matched target name
    public let targetName: String

    /// The A/B allocation bucket (0-99)
    public let bucket: Int
}

/// Engine for evaluating targeting rules and handling A/B allocation
public enum TargetingEngine {

    /// Evaluate all targets and return the selected onboarding
    /// Targets are evaluated in priority order (0 = highest priority)
    /// Falls back to lowest priority target if none match
    ///
    /// - Parameters:
    ///   - targets: Array of targets from manifest
    ///   - context: Targeting context built from device info
    ///   - userId: User ID for deterministic A/B allocation
    /// - Returns: Target evaluation result or nil if no targets
    public static func evaluateTargets(
        _ targets: [ManifestTarget],
        context: TargetingContext,
        userId: String
    ) -> TargetEvaluationResult? {
        guard !targets.isEmpty else {
            RampKitLogger.verbose("TargetingEngine", "No targets in manifest")
            return nil
        }

        // Sort by priority ascending (0 = highest priority, evaluated first)
        let sorted = targets.sorted { $0.priority < $1.priority }

        RampKitLogger.verbose("TargetingEngine", "Evaluating \(sorted.count) targets for user \(String(userId.prefix(8)))...")

        for target in sorted {
            let matches = evaluateRules(target.rules, context: context)

            RampKitLogger.verbose(
                "TargetingEngine",
                "Target \"\(target.name)\" (priority \(target.priority)): \(matches ? "MATCHED" : "no match")"
            )

            if matches {
                let (onboarding, bucket) = selectOnboardingByAllocation(target.onboardings, userId: userId)

                RampKitLogger.verbose(
                    "TargetingEngine",
                    "Selected onboarding \(onboarding.id) (bucket \(bucket), allocation \(onboarding.allocation)%)"
                )

                return TargetEvaluationResult(
                    onboarding: onboarding,
                    targetId: target.id,
                    targetName: target.name,
                    bucket: bucket
                )
            }
        }

        // Fallback: use the lowest priority target (last in sorted array)
        let fallbackTarget = sorted[sorted.count - 1]
        RampKitLogger.verbose(
            "TargetingEngine",
            "No targets matched, using fallback target \"\(fallbackTarget.name)\""
        )

        let (onboarding, bucket) = selectOnboardingByAllocation(fallbackTarget.onboardings, userId: userId)

        return TargetEvaluationResult(
            onboarding: onboarding,
            targetId: fallbackTarget.id,
            targetName: fallbackTarget.name,
            bucket: bucket
        )
    }

    /// Evaluate a set of rules against the context
    /// Empty rules = matches all users
    ///
    /// - Parameters:
    ///   - rules: Target rules configuration
    ///   - context: Targeting context
    /// - Returns: true if rules match
    public static func evaluateRules(_ rules: TargetRules, context: TargetingContext) -> Bool {
        // Empty rules array = match all users
        guard !rules.rules.isEmpty else {
            return true
        }

        if rules.match == "all" {
            // AND logic - all rules must match
            return rules.rules.allSatisfy { evaluateRule($0, context: context) }
        } else {
            // OR logic - at least one rule must match
            return rules.rules.contains { evaluateRule($0, context: context) }
        }
    }

    /// Evaluate a single rule against the context
    ///
    /// - Parameters:
    ///   - rule: Individual rule to evaluate
    ///   - context: Targeting context
    /// - Returns: true if rule matches
    public static func evaluateRule(_ rule: TargetRule, context: TargetingContext) -> Bool {
        // Parse attribute path (e.g., "device.country" -> ["device", "country"])
        let parts = rule.attribute.split(separator: ".")
        guard parts.count == 2 else {
            RampKitLogger.verbose("TargetingEngine", "Invalid attribute format: \(rule.attribute)")
            return false
        }

        let category = String(parts[0])
        let attr = String(parts[1])

        // Get the actual value from context
        guard let actualValue = getContextValue(category: category, attribute: attr, context: context) else {
            RampKitLogger.verbose(
                "TargetingEngine",
                "Attribute \(rule.attribute) is null/undefined, rule does not match"
            )
            return false
        }

        // Apply operator
        let result = applyOperator(rule.operator, actualValue: actualValue, expectedValue: rule.value)

        RampKitLogger.verbose(
            "TargetingEngine",
            "Rule: \(rule.attribute) \(rule.operator) \"\(rule.value)\" => actual: \"\(actualValue)\" => \(result)"
        )

        return result
    }

    /// Get a value from the targeting context by category and attribute
    private static func getContextValue(category: String, attribute: String, context: TargetingContext) -> Any? {
        switch category {
        case "user":
            switch attribute {
            case "isNewUser":
                return context.user.isNewUser
            case "daysSinceInstall":
                return context.user.daysSinceInstall
            case "subscriptionStatus":
                return context.user.subscriptionStatus
            case "hasAppleSearchAdsAttribution":
                return context.user.hasAppleSearchAdsAttribution
            default:
                return nil
            }

        case "device":
            switch attribute {
            case "platform":
                return context.device.platform
            case "model":
                return context.device.model
            case "osVersion":
                return context.device.osVersion
            case "interfaceStyle":
                return context.device.interfaceStyle
            case "country":
                return context.device.country
            case "language":
                return context.device.language
            case "locale":
                return context.device.locale
            case "currencyCode":
                return context.device.currencyCode
            default:
                return nil
            }

        case "app":
            switch attribute {
            case "version":
                return context.app.version
            case "buildNumber":
                return context.app.buildNumber
            case "sdkVersion":
                return context.app.sdkVersion
            default:
                return nil
            }

        case "asa":
            switch attribute {
            case "keyword":
                return context.asa.keyword
            case "campaignId":
                return context.asa.campaignId
            default:
                return nil
            }

        case "cpp":
            switch attribute {
            case "pageId":
                return context.cpp.pageId
            default:
                return nil
            }

        default:
            return nil
        }
    }

    /// Apply an operator to compare actual value with expected value
    private static func applyOperator(_ op: String, actualValue: Any, expectedValue: String) -> Bool {
        switch op {
        // Text operators
        case "equals":
            return String(describing: actualValue) == expectedValue

        case "not_equals":
            return String(describing: actualValue) != expectedValue

        case "contains":
            return String(describing: actualValue).lowercased().contains(expectedValue.lowercased())

        case "starts_with":
            return String(describing: actualValue).lowercased().hasPrefix(expectedValue.lowercased())

        // Number operators
        case "greater_than":
            if let actual = actualValue as? Int, let expected = Int(expectedValue) {
                return actual > expected
            }
            if let actual = actualValue as? Double, let expected = Double(expectedValue) {
                return actual > expected
            }
            return false

        case "less_than":
            if let actual = actualValue as? Int, let expected = Int(expectedValue) {
                return actual < expected
            }
            if let actual = actualValue as? Double, let expected = Double(expectedValue) {
                return actual < expected
            }
            return false

        // Boolean operators
        case "is_true":
            if let actual = actualValue as? Bool {
                return actual == true
            }
            return false

        case "is_false":
            if let actual = actualValue as? Bool {
                return actual == false
            }
            return false

        default:
            RampKitLogger.verbose("TargetingEngine", "Unknown operator: \(op)")
            return false
        }
    }

    /// Select an onboarding based on allocation percentages
    /// Uses deterministic hashing for consistent A/B assignment
    ///
    /// - Parameters:
    ///   - onboardings: Array of onboardings with allocation percentages
    ///   - userId: User ID for deterministic bucket assignment
    /// - Returns: Tuple of selected onboarding and bucket number
    public static func selectOnboardingByAllocation(
        _ onboardings: [TargetOnboarding],
        userId: String
    ) -> (onboarding: TargetOnboarding, bucket: Int) {
        guard !onboardings.isEmpty else {
            fatalError("No onboardings in target")
        }

        // Single onboarding - no allocation needed
        if onboardings.count == 1 {
            return (onboardings[0], 0)
        }

        // Generate deterministic bucket (0-99) from userId
        let bucket = hashUserIdToBucket(userId)

        // Find which allocation bucket the user falls into
        var cumulative = 0
        for onboarding in onboardings {
            cumulative += onboarding.allocation
            if bucket < cumulative {
                return (onboarding, bucket)
            }
        }

        // Fallback to last onboarding (handles rounding errors or allocation < 100)
        return (onboardings[onboardings.count - 1], bucket)
    }

    /// Hash userId to a bucket 0-99 using djb2 algorithm
    /// This is deterministic - same userId always gets same bucket
    private static func hashUserIdToBucket(_ userId: String) -> Int {
        var hash: UInt32 = 5381
        for char in userId.utf8 {
            hash = ((hash << 5) &+ hash) &+ UInt32(char) // hash * 33 + char
        }
        return Int(hash % 100)
    }
}
