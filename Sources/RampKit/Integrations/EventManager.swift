import Foundation
#if canImport(UIKit)
import UIKit
#endif

/// Manages event tracking for RampKit SDK
public class EventManager {
    
    // MARK: - Singleton
    
    /// Shared instance
    public static let shared = EventManager()
    
    // MARK: - Background Queue
    
    /// Dedicated serial queue for ALL event work - completely off main thread
    private let eventQueue = DispatchQueue(label: "com.rampkit.events", qos: .utility)
    
    // MARK: - State (accessed only from eventQueue)
    
    /// App ID from configuration
    private var appId: String?
    
    /// User ID
    private var appUserId: String?
    
    /// Session ID (reused from DeviceInfo)
    private var sessionId: String?
    
    /// Device info for events
    private var eventDevice: EventDevice?
    
    /// Base context (locale, region)
    private var baseContext: EventContext?
    
    /// Current onboarding flow ID
    private var currentFlowId: String?
    
    /// Current variant ID
    private var currentVariantId: String?
    
    /// Current screen name
    private var currentScreenName: String?

    /// Session start time
    private var sessionStartTime: Date?

    /// Onboarding start time (for calculating duration)
    private var onboardingStartTime: Date?

    /// Whether onboarding was completed this session (prevents abandoned from firing after completed)
    private var onboardingCompletedForSession = false

    /// Whether the manager is initialized
    private var isInitialized = false

    // MARK: - Targeting State (persists for all events after target match)

    /// Current matched target ID
    private var currentTargetId: String?

    /// Current matched target name
    private var currentTargetName: String?

    /// Current A/B bucket (0-99)
    private var currentBucket: Int?

    /// Current onboarding ID (from targeting)
    private var currentOnboardingId: String?

    /// Current onboarding version ID (from targeting)
    private var currentOnboardingVersionId: String?
    
    // MARK: - Initialization
    
    private init() {}
    
    /// Initialize the event manager with device info
    /// - Parameters:
    ///   - appId: App UUID from RampKit dashboard
    ///   - deviceInfo: Collected device information
    @available(iOS 14.0, macOS 11.0, *)
    public func initialize(appId: String, deviceInfo: DeviceInfo) {
        // Capture values for background initialization
        let userId = deviceInfo.appUserId
        let sessionId = deviceInfo.appSessionId
        let device = EventDevice(from: deviceInfo)
        let context = EventContext(from: deviceInfo)
        let isFirstLaunch = deviceInfo.isFirstLaunch
        let launchCount = deviceInfo.launchCount
        
        // Initialize state on background queue
        eventQueue.async { [weak self] in
            guard let self = self else { return }
            self.appId = appId
            self.appUserId = userId
            self.sessionId = sessionId
            self.eventDevice = device
            self.baseContext = context
            self.sessionStartTime = Date()
            self.isInitialized = true
            
            // Track session started (already on background queue)
            self.trackAppSessionStartedInternal(isFirstLaunch: isFirstLaunch, launchCount: launchCount)
        }
        
        // Set up app lifecycle observers on main thread
        setupLifecycleObservers()
        
        RampKitLogger.log("EventManager", "initialized")
    }
    
    // MARK: - Lifecycle Observers

    private func setupLifecycleObservers() {
        // No lifecycle observers needed - we only track app_session_started
    }

    deinit {
        // No observers to clean up
    }
    
    // MARK: - Context Setters (thread-safe)
    
    /// Set current onboarding flow
    public func setFlow(flowId: String?, variantId: String? = nil) {
        eventQueue.async { [weak self] in
            self?.currentFlowId = flowId
            self?.currentVariantId = variantId
        }
    }
    
    /// Set current screen
    public func setScreen(name: String?) {
        eventQueue.async { [weak self] in
            self?.currentScreenName = name
        }
    }

    // MARK: - Targeting Context

    /// Set targeting context (called after target evaluation)
    /// This persists for all subsequent events
    public func setTargetingContext(
        targetId: String,
        targetName: String,
        onboardingId: String,
        bucket: Int,
        versionId: String? = nil
    ) {
        eventQueue.async { [weak self] in
            self?.currentTargetId = targetId
            self?.currentTargetName = targetName
            self?.currentOnboardingId = onboardingId
            self?.currentBucket = bucket
            self?.currentOnboardingVersionId = versionId
            self?.currentFlowId = onboardingId
        }
        RampKitLogger.verbose("EventManager", "Targeting context set: targetId=\(targetId), bucket=\(bucket), versionId=\(versionId ?? "nil")")
    }

    /// Get current targeting info (for user profile updates)
    public func getTargetingInfo() -> (targetId: String?, targetName: String?, bucket: Int?) {
        return (currentTargetId, currentTargetName, currentBucket)
    }

    // MARK: - Core Track Method (fire and forget - returns immediately)
    
    /// Track an event - ALL work happens on background queue
    @available(iOS 14.0, macOS 11.0, *)
    public func track(
        _ eventName: RampKitEventName,
        screenName: String? = nil,
        flowId: String? = nil,
        variantId: String? = nil,
        paywallId: String? = nil,
        placement: String? = nil,
        properties: [String: Any] = [:]
    ) {
        // Capture time immediately (cheap)
        let occurredAt = Date()
        
        // Dispatch ALL work to background queue
        eventQueue.async { [weak self] in
            guard let self = self,
                  self.isInitialized,
                  let appId = self.appId,
                  let appUserId = self.appUserId,
                  let sessionId = self.sessionId,
                  let device = self.eventDevice else {
                return
            }
            
            let context = EventContext(
                screenName: screenName ?? self.currentScreenName,
                flowId: flowId ?? self.currentFlowId,
                variantId: variantId ?? self.currentVariantId,
                paywallId: paywallId,
                locale: self.baseContext?.locale,
                regionCode: self.baseContext?.regionCode,
                placement: placement
            )

            // Include targeting info in all events if available
            var enrichedProperties = properties
            if let targetId = self.currentTargetId {
                enrichedProperties["targetId"] = targetId
            }
            if let bucket = self.currentBucket {
                enrichedProperties["bucket"] = bucket
            }
            if let versionId = self.currentOnboardingVersionId {
                enrichedProperties["versionId"] = versionId
            }

            let event = RampKitEvent(
                appId: appId,
                appUserId: appUserId,
                eventName: eventName,
                sessionId: sessionId,
                occurredAt: occurredAt,
                device: device,
                context: context,
                properties: enrichedProperties
            )

            self.logEvent(event)
        }
    }

    /// Track a custom event with raw name
    @available(iOS 14.0, macOS 11.0, *)
    public func trackCustom(
        _ eventName: String,
        screenName: String? = nil,
        properties: [String: Any] = [:]
    ) {
        let occurredAt = Date()
        
        eventQueue.async { [weak self] in
            guard let self = self,
                  self.isInitialized,
                  let appId = self.appId,
                  let appUserId = self.appUserId,
                  let sessionId = self.sessionId,
                  let device = self.eventDevice else {
                return
            }
            
            let context = EventContext(
                screenName: screenName ?? self.currentScreenName,
                flowId: self.currentFlowId,
                variantId: self.currentVariantId,
                locale: self.baseContext?.locale,
                regionCode: self.baseContext?.regionCode
            )
            
            let event = RampKitEvent(
                appId: appId,
                appUserId: appUserId,
                eventNameRaw: eventName,
                sessionId: sessionId,
                occurredAt: occurredAt,
                device: device,
                context: context,
                properties: properties
            )
            
            self.logEvent(event)
        }
    }
    
    // MARK: - App Lifecycle Events (internal - already dispatched)

    @available(iOS 14.0, macOS 11.0, *)
    private func trackAppSessionStartedInternal(isFirstLaunch: Bool, launchCount: Int) {
        // Called from eventQueue, build event directly
        guard isInitialized,
              let appId = appId,
              let appUserId = appUserId,
              let sessionId = sessionId,
              let device = eventDevice else { return }

        let context = EventContext(
            locale: baseContext?.locale,
            regionCode: baseContext?.regionCode
        )

        let event = RampKitEvent(
            appId: appId,
            appUserId: appUserId,
            eventName: .appSessionStarted,
            sessionId: sessionId,
            device: device,
            context: context,
            properties: [
                "isFirstLaunch": isFirstLaunch,
                "launchCount": launchCount
            ]
        )

        logEvent(event)
    }

    // MARK: - Targeting Events

    /// Track target matched event
    /// Called when targeting evaluation completes and a target is selected
    @available(iOS 14.0, macOS 11.0, *)
    public func trackTargetMatched(
        targetId: String,
        targetName: String,
        onboardingId: String,
        bucket: Int,
        versionId: String? = nil
    ) {
        // Set targeting context for all future events
        setTargetingContext(
            targetId: targetId,
            targetName: targetName,
            onboardingId: onboardingId,
            bucket: bucket,
            versionId: versionId
        )

        // Track the target_matched event
        var props: [String: Any] = [
            "targetId": targetId,
            "targetName": targetName,
            "onboardingId": onboardingId,
            "bucket": bucket
        ]
        if let versionId = versionId {
            props["versionId"] = versionId
        }
        track(.targetMatched, properties: props)
    }

    // MARK: - Onboarding Events

    @available(iOS 14.0, macOS 11.0, *)
    public func trackOnboardingStarted(flowId: String? = nil, totalSteps: Int? = nil) {
        eventQueue.async { [weak self] in
            self?.onboardingStartTime = Date()
            self?.onboardingCompletedForSession = false
        }
        var props: [String: Any] = [:]
        if let totalSteps = totalSteps { props["totalSteps"] = totalSteps }
        track(.onboardingStarted, flowId: flowId, properties: props)
    }

    @available(iOS 14.0, macOS 11.0, *)
    public func trackOnboardingAbandoned(
        reason: String,
        lastScreenName: String? = nil,
        completedSteps: Int? = nil,
        totalSteps: Int? = nil
    ) {
        // Skip if onboarding was already completed this session
        guard !onboardingCompletedForSession else {
            RampKitLogger.log("EventManager", "onboarding_abandoned skipped (already completed)")
            return
        }

        let startTime = onboardingStartTime

        eventQueue.async { [weak self] in
            self?.onboardingStartTime = nil
        }

        let timeSpent = startTime.map { Date().timeIntervalSince($0) } ?? 0
        var props: [String: Any] = [
            "reason": reason,
            "timeSpentSeconds": Int(timeSpent)
        ]
        if let lastScreenName = lastScreenName { props["lastScreenName"] = lastScreenName }
        if let completedSteps = completedSteps { props["completedSteps"] = completedSteps }
        if let totalSteps = totalSteps { props["totalSteps"] = totalSteps }
        track(.onboardingAbandoned, screenName: lastScreenName, properties: props)
    }

    // MARK: - Onboarding Completion

    /// Track onboarding completed event
    /// Called when:
    /// 1. User completes the onboarding flow (onboarding-finished action)
    /// 2. User closes the onboarding (close action)
    /// 3. A paywall is shown (show-paywall action)
    ///
    /// - Parameters:
    ///   - trigger: The reason for completion ("finished", "closed", "paywall_shown")
    ///   - completedSteps: Number of steps the user completed
    ///   - totalSteps: Total number of steps in the onboarding
    @available(iOS 14.0, macOS 11.0, *)
    public func trackOnboardingCompleted(
        trigger: String,
        completedSteps: Int? = nil,
        totalSteps: Int? = nil
    ) {
        // Capture start time before dispatching
        let startTime = onboardingStartTime

        eventQueue.async { [weak self] in
            self?.onboardingStartTime = nil
        }

        let timeToComplete = startTime.map { Date().timeIntervalSince($0) } ?? 0
        var props: [String: Any] = [
            "timeToCompleteSeconds": Int(timeToComplete),
            "trigger": trigger
        ]
        if let completedSteps = completedSteps { props["completedSteps"] = completedSteps }
        if let totalSteps = totalSteps { props["totalSteps"] = totalSteps }

        track(.onboardingCompleted, properties: props)

        // Mark as completed so abandoned won't fire for this session
        onboardingCompletedForSession = true
        RampKitLogger.log("EventManager", "📊 onboarding_completed sent (trigger: \(trigger))")
    }
    
    // MARK: - Interaction Events

    @available(iOS 14.0, macOS 11.0, *)
    public func trackOptionSelected(optionId: String, optionValue: Any, questionId: String? = nil) {
        var props: [String: Any] = [
            "optionId": optionId,
            "optionValue": optionValue
        ]
        if let questionId = questionId { props["questionId"] = questionId }
        track(.optionSelected, properties: props)
    }

    @available(iOS 14.0, macOS 11.0, *)
    public func trackCtaTap(buttonId: String, buttonText: String? = nil, screenName: String? = nil) {
        var props: [String: Any] = ["buttonId": buttonId]
        if let buttonText = buttonText { props["buttonText"] = buttonText }
        track(.ctaTap, screenName: screenName, properties: props)
    }

    @available(iOS 14.0, macOS 11.0, *)
    public func trackScreenNavigated(
        fromScreenName: String?,
        toScreenName: String,
        direction: String,
        trigger: String = "button"
    ) {
        var props: [String: Any] = [
            "toScreenName": toScreenName,
            "direction": direction,
            "trigger": trigger
        ]
        if let fromScreenName = fromScreenName {
            props["fromScreenName"] = fromScreenName
        }
        track(.screenNavigated, properties: props)
    }

    /// Track variable set event
    /// - Parameter screenName: The screen where the variable was set (captured at time of change, not firing)
    @available(iOS 14.0, macOS 11.0, *)
    public func trackVariableSet(
        variableName: String,
        previousValue: Any?,
        newValue: Any,
        screenName: String? = nil
    ) {
        let valueType: String
        switch newValue {
        case is String: valueType = "string"
        case is Int, is Double, is Float: valueType = "number"
        case is Bool: valueType = "boolean"
        case is [Any]: valueType = "array"
        case is [String: Any]: valueType = "object"
        default: valueType = "unknown"
        }

        var props: [String: Any] = [
            "variableName": variableName,
            "variableType": "state",
            "valueType": valueType,
            "newValue": newValue,
            "source": "user_input"
        ]
        if let previousValue = previousValue {
            props["previousValue"] = previousValue
        }
        track(.variableSet, screenName: screenName, properties: props)
    }

    // MARK: - Permission Events

    @available(iOS 14.0, macOS 11.0, *)
    public func trackNotificationsResponse(status: String) {
        track(.notificationsResponse, properties: [
            "status": status
        ])
    }

    @available(iOS 14.0, macOS 11.0, *)
    public func trackTrackingResponse(status: String) {
        track(.trackingResponse, properties: [
            "status": status
        ])
    }

    // MARK: - Paywall Events

    @available(iOS 14.0, macOS 11.0, *)
    public func trackPaywallShown(paywallId: String, placement: String? = nil, products: [[String: Any]]? = nil) {
        var props: [String: Any] = ["paywallId": paywallId]
        if let placement = placement { props["placement"] = placement }
        if let products = products { props["products"] = products }
        track(.paywallShown, paywallId: paywallId, placement: placement, properties: props)
    }

    // MARK: - Purchase Events

    @available(iOS 14.0, macOS 11.0, *)
    public func trackPurchaseStarted(details: PurchaseEventDetails, paywallId: String? = nil) {
        track(.purchaseStarted, paywallId: paywallId, properties: details.toProperties())
    }

    @available(iOS 14.0, macOS 11.0, *)
    public func trackPurchaseCompleted(details: PurchaseEventDetails, paywallId: String? = nil) {
        track(.purchaseCompleted, paywallId: paywallId, properties: details.toProperties())
    }

    @available(iOS 14.0, macOS 11.0, *)
    public func trackPurchaseFailed(details: PurchaseEventDetails, paywallId: String? = nil) {
        track(.purchaseFailed, paywallId: paywallId, properties: details.toProperties())
    }

    @available(iOS 14.0, macOS 11.0, *)
    public func trackPurchaseRestored(details: PurchaseEventDetails) {
        track(.purchaseRestored, properties: details.toProperties())
    }

    // MARK: - Reset

    /// Reset all event manager state
    /// Called during SDK reset (e.g., user logout)
    public func reset() {
        eventQueue.async { [weak self] in
            guard let self = self else { return }

            self.appId = nil
            self.appUserId = nil
            self.sessionId = nil
            self.eventDevice = nil
            self.baseContext = nil
            self.currentFlowId = nil
            self.currentVariantId = nil
            self.currentScreenName = nil
            self.sessionStartTime = nil
            self.onboardingStartTime = nil
            self.onboardingCompletedForSession = false
            self.isInitialized = false

            // Clear targeting state
            self.currentTargetId = nil
            self.currentTargetName = nil
            self.currentBucket = nil
            self.currentOnboardingId = nil
            self.currentOnboardingVersionId = nil

            RampKitLogger.log("EventManager", "reset complete")
        }
    }

    // MARK: - Event Processing (runs on eventQueue)

    /// Process and send event - called from background queue only
    private func logEvent(_ event: RampKitEvent) {
        // Log event name
        RampKitLogger.log("Event", "📊 \(event.eventName)")
        
        // Send to backend (fire and forget)
        Task {
            do {
                let success = try await BackendAPI.sendEvent(event)
                if success {
                    RampKitLogger.log("Event", "✅ Sent: \(event.eventName)")
                }
            } catch {
                RampKitLogger.log("Event", "⚠️ Failed to send \(event.eventName): \(error.localizedDescription)")
            }
        }
    }
}
