import Foundation
import StoreKit

/// Observes StoreKit transactions and tracks purchase events
@available(iOS 15.0, macOS 12.0, *)
public class TransactionObserver {

    // MARK: - Singleton

    public static let shared = TransactionObserver()

    // MARK: - State

    private var updateTask: Task<Void, Never>?
    private var isObserving = false

    /// UserDefaults key for storing sent transaction IDs
    private let sentTransactionsKey = "rk_sent_transaction_ids"

    /// Set of originalTransactionIds that have been successfully sent to backend
    private var sentTransactionIds: Set<String> = []

    // MARK: - Initialization

    private init() {
        loadSentTransactions()
    }

    // MARK: - Persistence

    private func loadSentTransactions() {
        if let stored = UserDefaults.standard.array(forKey: sentTransactionsKey) as? [String] {
            sentTransactionIds = Set(stored)
            RampKitLogger.verbose("TransactionObserver", "loaded \(sentTransactionIds.count) sent transaction IDs")
        }
    }

    private func saveSentTransactions() {
        let array = Array(sentTransactionIds)
        UserDefaults.standard.set(array, forKey: sentTransactionsKey)
    }

    private func markTransactionAsSent(_ originalId: String) {
        sentTransactionIds.insert(originalId)
        saveSentTransactions()
        RampKitLogger.verbose("TransactionObserver", "marked as sent: \(originalId)")
    }

    /// Clear all sent transaction IDs (for testing)
    public func clearSentTransactions() {
        let count = sentTransactionIds.count
        sentTransactionIds.removeAll()
        saveSentTransactions()
        RampKitLogger.verbose("TransactionObserver", "cleared \(count) sent transaction IDs")
    }

    /// Start observing transactions
    /// Also checks currentEntitlements for any purchases we may have missed
    public func startObserving() {
        guard !isObserving else { return }
        isObserving = true

        RampKitLogger.verbose("TransactionObserver", "starting transaction observation")

        // Check current entitlements for any unsent purchases
        Task(priority: .background) {
            await checkAndSendUnsentPurchases()
        }

        // Start listening for future transactions
        updateTask = Task(priority: .background) {
            for await verificationResult in Transaction.updates {
                await handleTransaction(verificationResult)
            }
        }
    }

    /// Check ALL transactions (not just current entitlements) and send any that haven't been sent yet
    /// This catches ALL purchases including expired/superseded ones made by Superwall/RevenueCat
    ///
    /// NOTE: We use Transaction.all instead of Transaction.currentEntitlements because
    /// currentEntitlements only returns ACTIVE entitlements. If a user purchases a subscription
    /// and it expires, or if they upgrade (superseding the old transaction), currentEntitlements
    /// will NOT include the original purchase. Transaction.all returns the complete history.
    private func checkAndSendUnsentPurchases() async {
        RampKitLogger.verbose("TransactionObserver", "checking ALL transactions for unsent purchases...")

        var foundCount = 0
        var alreadySent = 0
        var newlySent = 0

        for await result in Transaction.all {
            foundCount += 1

            guard case .verified(let transaction) = result else {
                RampKitLogger.verbose("TransactionObserver", "unverified transaction skipped")
                continue
            }

            let transactionId = String(transaction.id)

            // Skip if already sent successfully (track by transactionId so renewals are also sent)
            if sentTransactionIds.contains(transactionId) {
                alreadySent += 1
                RampKitLogger.verbose("TransactionObserver", "already sent: \(transaction.productID) (txId: \(transactionId))")
                continue
            }

            // Skip revocations only (NOT renewals - we want to track renewals too!)
            if transaction.revocationDate != nil {
                RampKitLogger.verbose("TransactionObserver", "skipped (revoked): \(transaction.productID)")
                continue
            }

            // Log if this is a renewal
            if transaction.originalID != transaction.id {
                RampKitLogger.verbose("TransactionObserver", "renewal detected: \(transaction.productID)")
            }

            RampKitLogger.verbose("TransactionObserver", "found unsent transaction: \(transaction.productID) (txId: \(transactionId))")

            // Send and track if successful (use transactionId for renewals support)
            let success = await sendPurchaseEventWithConfirmation(transaction)
            if success {
                markTransactionAsSent(transactionId)
                newlySent += 1
            }
        }

        RampKitLogger.verbose("TransactionObserver", "transaction check complete: found=\(foundCount), alreadySent=\(alreadySent), newlySent=\(newlySent)")
    }

    /// Stop observing transactions
    public func stopObserving() {
        updateTask?.cancel()
        updateTask = nil
        isObserving = false
        RampKitLogger.verbose("TransactionObserver", "stopped transaction observation")
    }
    
    // MARK: - Transaction Handling

    private func handleTransaction(_ verificationResult: VerificationResult<Transaction>) async {
        let transaction: Transaction

        switch verificationResult {
        case .verified(let t):
            transaction = t
        case .unverified(let t, _):
            RampKitLogger.verbose("TransactionObserver", "Unverified transaction skipped: \(t.productID)")
            await t.finish()
            return
        }

        let transactionId = String(transaction.id)

        // Skip if already sent successfully (track by transactionId so renewals are also sent)
        if sentTransactionIds.contains(transactionId) {
            RampKitLogger.verbose("TransactionObserver", "already sent: \(transaction.productID) (txId: \(transactionId))")
            await transaction.finish()
            return
        }

        // Skip revocations only (NOT renewals - we want to track renewals too!)
        if transaction.revocationDate != nil {
            RampKitLogger.verbose("TransactionObserver", "skipped (revoked): \(transaction.productID)")
            await transaction.finish()
            return
        }

        // Log if this is a renewal
        if transaction.originalID != transaction.id {
            RampKitLogger.verbose("TransactionObserver", "renewal detected: \(transaction.productID)")
        }

        RampKitLogger.verbose("TransactionObserver", "new transaction detected: \(transaction.productID) (txId: \(transactionId))")

        // Send and only mark as sent if successful (use transactionId for renewals support)
        let success = await sendPurchaseEventWithConfirmation(transaction)
        if success {
            markTransactionAsSent(transactionId)
            RampKitLogger.verbose("TransactionObserver", "transaction sent and tracked: \(transaction.productID) (txId: \(transactionId))")
        } else {
            RampKitLogger.warn("TransactionObserver", "transaction send failed, will retry: \(transaction.productID)")
        }

        // Finish the transaction
        await transaction.finish()
    }

    /// Send purchase event and return true if successfully sent to backend
    private func sendPurchaseEventWithConfirmation(_ transaction: Transaction) async -> Bool {
        let details = await buildPurchaseDetails(from: transaction, isVerified: true)

        do {
            let event = await buildPurchaseEvent(details: details)
            let success = try await BackendAPI.sendEvent(event)
            return success
        } catch {
            RampKitLogger.warn("TransactionObserver", "send failed: \(error.localizedDescription)")
            return false
        }
    }

    /// Build a RampKitEvent for the purchase (on background thread)
    @MainActor
    private func buildPurchaseEvent(details: PurchaseEventDetails) -> RampKitEvent {
        // Get current state from RampKit
        let appId = RampKitCore.shared.getAppId() ?? ""
        let userId = RampKitCore.shared.getUserId() ?? ""
        let sessionId = UUID().uuidString.lowercased()

        let device = EventDevice(
            platform: "iOS",
            platformVersion: ProcessInfo.processInfo.operatingSystemVersionString,
            deviceModel: getDeviceModel(),
            sdkVersion: DeviceInfoCollector.sdkVersion,
            appVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String,
            buildNumber: Bundle.main.infoDictionary?["CFBundleVersion"] as? String
        )

        let context = EventContext(
            locale: Locale.current.identifier,
            regionCode: Locale.current.regionCode
        )

        return RampKitEvent(
            appId: appId,
            appUserId: userId,
            eventName: .purchaseCompleted,
            sessionId: sessionId,
            device: device,
            context: context,
            properties: details.toProperties()
        )
    }

    private func getDeviceModel() -> String {
        var systemInfo = utsname()
        uname(&systemInfo)
        let machineMirror = Mirror(reflecting: systemInfo.machine)
        let identifier = machineMirror.children.reduce("") { id, element in
            guard let value = element.value as? Int8, value != 0 else { return id }
            return id + String(UnicodeScalar(UInt8(value)))
        }
        return identifier
    }

    // MARK: - Build Purchase Details
    
    private func buildPurchaseDetails(from transaction: Transaction, isVerified: Bool) async -> PurchaseEventDetails {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        
        // Get product info for price
        var amount: Decimal?
        var currency: String?
        var priceFormatted: String?
        var subscriptionPeriod: String?
        var subscriptionGroupId: String?
        
        if let product = try? await Product.products(for: [transaction.productID]).first {
            amount = product.price
            currency = product.priceFormatting?.currencyCode
            priceFormatted = product.displayPrice
            
            if let subscription = product.subscription {
                subscriptionPeriod = formatSubscriptionPeriod(subscription.subscriptionPeriod)
                subscriptionGroupId = subscription.subscriptionGroupID
            }
        }
        
        // Determine offer type string
        let offerTypeString = formatOfferType(transaction.offerType)
        
        // Get environment (iOS 16+ only)
        var environmentString: String?
        if #available(iOS 16.0, macOS 13.0, *) {
            environmentString = transaction.environment.rawValue
        }
        
        return PurchaseEventDetails(
            productId: transaction.productID,
            amount: amount,
            currency: currency,
            priceFormatted: priceFormatted,
            originalTransactionId: String(transaction.originalID),
            transactionId: String(transaction.id),
            purchaseDate: formatter.string(from: transaction.purchaseDate),
            expirationDate: transaction.expirationDate.map { formatter.string(from: $0) },
            isTrial: transaction.offerType == .introductory,
            isIntroOffer: transaction.offerType == .introductory,
            subscriptionPeriod: subscriptionPeriod,
            subscriptionGroupId: subscriptionGroupId,
            offerId: transaction.offerID,
            offerType: offerTypeString,
            storefront: transaction.storefrontCountryCode,
            environment: environmentString,
            quantity: transaction.purchasedQuantity,
            webOrderLineItemId: transaction.webOrderLineItemID,
            revocationDate: transaction.revocationDate.map { formatter.string(from: $0) },
            revocationReason: transaction.revocationReason.map { formatRevocationReason($0) }
        )
    }
    
    private func formatOfferType(_ offerType: Transaction.OfferType?) -> String? {
        guard let offerType = offerType else { return nil }
        
        if offerType == .introductory {
            return "introductory"
        } else if offerType == .promotional {
            return "promotional"
        } else if offerType == .code {
            return "code"
        } else {
            // Handles .winBack (iOS 16.4+) and any future cases
            return "unknown"
        }
    }
    
    private func formatSubscriptionPeriod(_ period: Product.SubscriptionPeriod) -> String {
        // ISO 8601 duration format
        let unit = period.unit
        if unit == .day {
            return "P\(period.value)D"
        } else if unit == .week {
            return "P\(period.value)W"
        } else if unit == .month {
            return "P\(period.value)M"
        } else if unit == .year {
            return "P\(period.value)Y"
        } else {
            return "P\(period.value)D"
        }
    }
    
    private func formatRevocationReason(_ reason: Transaction.RevocationReason) -> String {
        if reason == .developerIssue {
            return "developerIssue"
        } else if reason == .other {
            return "other"
        } else {
            return "unknown"
        }
    }
    
    // MARK: - Manual Purchase Tracking
    
    /// Track a purchase started event (call before initiating purchase)
    @MainActor
    public func trackPurchaseStarted(productId: String, paywallId: String? = nil) async {
        var details = PurchaseEventDetails(productId: productId)
        
        // Try to get product info
        if let product = try? await Product.products(for: [productId]).first {
            details = PurchaseEventDetails(
                productId: productId,
                amount: product.price,
                currency: product.priceFormatting?.currencyCode,
                priceFormatted: product.displayPrice
            )
        }
        
        EventManager.shared.trackPurchaseStarted(details: details, paywallId: paywallId)
    }
    
    /// Track a purchase failed event
    @MainActor
    public func trackPurchaseFailed(
        productId: String,
        errorCode: String?,
        errorMessage: String?,
        paywallId: String? = nil
    ) {
        let details = PurchaseEventDetails(
            productId: productId,
            errorCode: errorCode,
            errorMessage: errorMessage
        )
        
        EventManager.shared.trackPurchaseFailed(details: details, paywallId: paywallId)
    }
    
    // MARK: - Check Current Entitlements

    /// Get all current entitlements (for debugging/analytics)
    public func getCurrentEntitlements() async -> [Transaction] {
        var transactions: [Transaction] = []

        for await verificationResult in Transaction.currentEntitlements {
            if case .verified(let transaction) = verificationResult {
                transactions.append(transaction)
            }
        }

        return transactions
    }

    /// Recheck entitlements for any unsent purchases
    /// Call this after onboarding finishes to catch purchases made during the flow
    public func recheckEntitlements() {
        RampKitLogger.verbose("TransactionObserver", "recheckEntitlements called (after onboarding)")
        Task(priority: .background) {
            await checkAndSendUnsentPurchases()
        }
    }
}

// MARK: - Product Extension

@available(iOS 15.0, macOS 12.0, *)
private extension Product {
    var priceFormatting: (currencyCode: String?, currencySymbol: String?)? {
        // Access price formatting info
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.locale = priceFormatStyle.locale
        return (formatter.currencyCode, formatter.currencySymbol)
    }
}
