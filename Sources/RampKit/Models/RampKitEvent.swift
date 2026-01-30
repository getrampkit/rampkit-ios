import Foundation

// MARK: - Event Names

/// All event types that RampKit SDK can track
public enum RampKitEventName: String, Codable {
    // App Lifecycle
    case appSessionStarted = "app_session_started"

    // Targeting
    case targetMatched = "target_matched"

    // Onboarding
    case onboardingStarted = "onboarding_started"
    case onboardingCompleted = "onboarding_completed"
    case onboardingAbandoned = "onboarding_abandoned"

    // Interaction
    case optionSelected = "option_selected"
    case ctaTap = "cta_tap"
    case screenNavigated = "screen_navigated"
    case variableSet = "variable_set"

    // Permissions
    case notificationsResponse = "notifications_response"
    case trackingResponse = "tracking_response"

    // Paywall
    case paywallShown = "paywall_shown"

    // Purchase
    case purchaseStarted = "purchase_started"
    case purchaseCompleted = "purchase_completed"
    case purchaseFailed = "purchase_failed"
    case purchaseRestored = "purchase_restored"

    // Custom event
    case custom = "custom"
}

// MARK: - Event Model

/// Main event payload sent to backend
public struct RampKitEvent: Codable {
    /// App UUID from RampKit dashboard
    public let appId: String
    
    /// RampKit user ID
    public let appUserId: String
    
    /// Unique event ID (UUID)
    public let eventId: String
    
    /// Event type name
    public let eventName: String
    
    /// Session ID (same as appSessionId from DeviceInfo)
    public let sessionId: String
    
    /// When the event occurred (ISO 8601)
    public let occurredAt: String
    
    /// Device information subset
    public let device: EventDevice
    
    /// Event context (screen, flow, etc.)
    public let context: EventContext
    
    /// Event-specific properties
    public let properties: [String: AnyCodable]
    
    public init(
        appId: String,
        appUserId: String,
        eventId: String = UUID().uuidString.lowercased(),
        eventName: RampKitEventName,
        sessionId: String,
        occurredAt: Date = Date(),
        device: EventDevice,
        context: EventContext,
        properties: [String: Any] = [:]
    ) {
        self.appId = appId
        self.appUserId = appUserId
        self.eventId = eventId
        self.eventName = eventName.rawValue
        self.sessionId = sessionId
        
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        self.occurredAt = formatter.string(from: occurredAt)
        
        self.device = device
        self.context = context
        self.properties = properties.mapValues { AnyCodable($0) }
    }
    
    /// Initialize with raw event name string (for custom events)
    public init(
        appId: String,
        appUserId: String,
        eventId: String = UUID().uuidString.lowercased(),
        eventNameRaw: String,
        sessionId: String,
        occurredAt: Date = Date(),
        device: EventDevice,
        context: EventContext,
        properties: [String: Any] = [:]
    ) {
        self.appId = appId
        self.appUserId = appUserId
        self.eventId = eventId
        self.eventName = eventNameRaw
        self.sessionId = sessionId
        
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        self.occurredAt = formatter.string(from: occurredAt)
        
        self.device = device
        self.context = context
        self.properties = properties.mapValues { AnyCodable($0) }
    }
}

// MARK: - Device Info (for events)

/// Subset of device info included with each event
public struct EventDevice: Codable {
    public let platform: String
    public let platformVersion: String
    public let deviceModel: String
    public let sdkVersion: String
    public let appVersion: String?
    public let buildNumber: String?
    
    public init(
        platform: String,
        platformVersion: String,
        deviceModel: String,
        sdkVersion: String,
        appVersion: String?,
        buildNumber: String?
    ) {
        self.platform = platform
        self.platformVersion = platformVersion
        self.deviceModel = deviceModel
        self.sdkVersion = sdkVersion
        self.appVersion = appVersion
        self.buildNumber = buildNumber
    }
    
    /// Create from full DeviceInfo
    public init(from deviceInfo: DeviceInfo) {
        self.platform = deviceInfo.platform
        self.platformVersion = deviceInfo.platformVersion
        self.deviceModel = deviceInfo.deviceModel
        self.sdkVersion = deviceInfo.sdkVersion
        self.appVersion = deviceInfo.appVersion
        self.buildNumber = deviceInfo.buildNumber
    }
}

// MARK: - Event Context

/// Contextual information for the event
public struct EventContext: Codable {
    /// Current screen name
    public let screenName: String?
    
    /// Onboarding flow ID
    public let flowId: String?
    
    /// A/B test variant ID
    public let variantId: String?
    
    /// Paywall ID if applicable
    public let paywallId: String?
    
    /// User's locale
    public let locale: String?
    
    /// User's region code
    public let regionCode: String?
    
    /// Placement context (e.g., "onboarding", "settings", "home")
    public let placement: String?
    
    public init(
        screenName: String? = nil,
        flowId: String? = nil,
        variantId: String? = nil,
        paywallId: String? = nil,
        locale: String? = nil,
        regionCode: String? = nil,
        placement: String? = nil
    ) {
        self.screenName = screenName
        self.flowId = flowId
        self.variantId = variantId
        self.paywallId = paywallId
        self.locale = locale
        self.regionCode = regionCode
        self.placement = placement
    }
    
    /// Create from DeviceInfo with optional overrides
    public init(
        from deviceInfo: DeviceInfo,
        screenName: String? = nil,
        flowId: String? = nil,
        variantId: String? = nil,
        paywallId: String? = nil,
        placement: String? = nil
    ) {
        self.screenName = screenName
        self.flowId = flowId
        self.variantId = variantId
        self.paywallId = paywallId
        self.locale = deviceInfo.deviceLocale
        self.regionCode = deviceInfo.regionCode
        self.placement = placement
    }
}

// MARK: - Purchase Event Details

/// Detailed purchase information for purchase events
public struct PurchaseEventDetails: Codable {
    /// Product identifier
    public let productId: String
    
    /// Price amount
    public let amount: Decimal?
    
    /// Currency code (e.g., "USD")
    public let currency: String?
    
    /// Formatted price string (e.g., "$7.99")
    public let priceFormatted: String?
    
    /// Original transaction ID (for subscription tracking)
    public let originalTransactionId: String?
    
    /// Current transaction ID
    public let transactionId: String?
    
    /// Purchase date
    public let purchaseDate: String?
    
    /// Expiration date (for subscriptions)
    public let expirationDate: String?
    
    /// Whether this is a trial
    public let isTrial: Bool?
    
    /// Whether this is an intro offer
    public let isIntroOffer: Bool?
    
    /// Subscription period (e.g., "P1M" for 1 month)
    public let subscriptionPeriod: String?
    
    /// Subscription group ID
    public let subscriptionGroupId: String?
    
    /// Offer ID if using promotional offers
    public let offerId: String?
    
    /// Offer type ("introductory", "promotional", "code")
    public let offerType: String?
    
    /// App Store storefront country
    public let storefront: String?
    
    /// Environment ("Production" or "Sandbox")
    public let environment: String?
    
    /// Quantity purchased
    public let quantity: Int?
    
    /// Error code if purchase failed
    public let errorCode: String?
    
    /// Error message if purchase failed
    public let errorMessage: String?
    
    /// Web order line item ID (for receipt validation)
    public let webOrderLineItemId: String?
    
    /// Revocation date if subscription was refunded
    public let revocationDate: String?
    
    /// Revocation reason
    public let revocationReason: String?
    
    public init(
        productId: String,
        amount: Decimal? = nil,
        currency: String? = nil,
        priceFormatted: String? = nil,
        originalTransactionId: String? = nil,
        transactionId: String? = nil,
        purchaseDate: String? = nil,
        expirationDate: String? = nil,
        isTrial: Bool? = nil,
        isIntroOffer: Bool? = nil,
        subscriptionPeriod: String? = nil,
        subscriptionGroupId: String? = nil,
        offerId: String? = nil,
        offerType: String? = nil,
        storefront: String? = nil,
        environment: String? = nil,
        quantity: Int? = nil,
        errorCode: String? = nil,
        errorMessage: String? = nil,
        webOrderLineItemId: String? = nil,
        revocationDate: String? = nil,
        revocationReason: String? = nil
    ) {
        self.productId = productId
        self.amount = amount
        self.currency = currency
        self.priceFormatted = priceFormatted
        self.originalTransactionId = originalTransactionId
        self.transactionId = transactionId
        self.purchaseDate = purchaseDate
        self.expirationDate = expirationDate
        self.isTrial = isTrial
        self.isIntroOffer = isIntroOffer
        self.subscriptionPeriod = subscriptionPeriod
        self.subscriptionGroupId = subscriptionGroupId
        self.offerId = offerId
        self.offerType = offerType
        self.storefront = storefront
        self.environment = environment
        self.quantity = quantity
        self.errorCode = errorCode
        self.errorMessage = errorMessage
        self.webOrderLineItemId = webOrderLineItemId
        self.revocationDate = revocationDate
        self.revocationReason = revocationReason
    }
    
    /// Convert to properties dictionary for event
    public func toProperties() -> [String: Any] {
        var props: [String: Any] = ["productId": productId]
        
        if let amount = amount { props["amount"] = NSDecimalNumber(decimal: amount).doubleValue }
        if let currency = currency { props["currency"] = currency }
        if let priceFormatted = priceFormatted { props["priceFormatted"] = priceFormatted }
        if let originalTransactionId = originalTransactionId { props["originalTransactionId"] = originalTransactionId }
        if let transactionId = transactionId { props["transactionId"] = transactionId }
        if let purchaseDate = purchaseDate { props["purchaseDate"] = purchaseDate }
        if let expirationDate = expirationDate { props["expirationDate"] = expirationDate }
        if let isTrial = isTrial { props["isTrial"] = isTrial }
        if let isIntroOffer = isIntroOffer { props["isIntroOffer"] = isIntroOffer }
        if let subscriptionPeriod = subscriptionPeriod { props["subscriptionPeriod"] = subscriptionPeriod }
        if let subscriptionGroupId = subscriptionGroupId { props["subscriptionGroupId"] = subscriptionGroupId }
        if let offerId = offerId { props["offerId"] = offerId }
        if let offerType = offerType { props["offerType"] = offerType }
        if let storefront = storefront { props["storefront"] = storefront }
        if let environment = environment { props["environment"] = environment }
        if let quantity = quantity { props["quantity"] = quantity }
        if let errorCode = errorCode { props["errorCode"] = errorCode }
        if let errorMessage = errorMessage { props["errorMessage"] = errorMessage }
        if let webOrderLineItemId = webOrderLineItemId { props["webOrderLineItemId"] = webOrderLineItemId }
        if let revocationDate = revocationDate { props["revocationDate"] = revocationDate }
        if let revocationReason = revocationReason { props["revocationReason"] = revocationReason }
        
        return props
    }
}






