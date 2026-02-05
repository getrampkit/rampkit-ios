import Foundation
#if canImport(UIKit)
import UIKit
#endif
#if canImport(WebKit)
import WebKit
#endif

/// Core singleton class for RampKit SDK
public class RampKitCore {
    /// Shared singleton instance
    public static let shared = RampKitCore()

    /// Configuration
    private var config: RampKitConfig?

    /// App ID from configuration
    private var appId: String?

    /// Cached onboarding data from CDN
    private var onboardingData: OnboardingData?

    /// Generated user ID
    private var userId: String?

    /// Custom App User ID provided by the developer (alias for their user system)
    private var appUserID: String?

    /// Collected device info (available after initialization)
    private(set) var deviceInfo: DeviceInfo?

    /// Callback for when onboarding is finished
    private var onOnboardingFinished: ((Any?) -> Void)?

    /// Callback for when paywall should be shown
    private var onShowPaywall: ((Any?) -> Void)?

    /// Result of target evaluation (for analytics/debugging)
    private var targetingResult: TargetEvaluationResult?

    /// Base URL for fetching app manifests
    private static let manifestBaseURL = "https://dh1psiwzzzkgr.cloudfront.net"
    
    /// Currently presented overlay controller
    #if os(iOS)
    private weak var currentOverlay: RampKitOverlayController?
    
    /// Loading placeholder view shown immediately when autoShowOnboarding is enabled
    private var loadingView: UIView?
    
    /// Pre-warmed WebView to speed up first display (warms up WebKit process)
    private var warmupWebView: CustomWebView?
    #endif
    
    /// Private initializer to enforce singleton
    private init() {}
    
    // MARK: - Public API

    /// Configure RampKit with configuration
    /// - Parameter config: Configuration object including appId, callbacks, and optional appUserID
    @available(iOS 14.0, macOS 11.0, *)
    public func configure(config: RampKitConfig) async {
        // Initialize verbose logging if enabled
        RampKitLogger.setVerboseLogging(config.verboseLogging)

        self.config = config
        self.appId = config.appId
        self.onOnboardingFinished = config.onOnboardingFinished
        self.onShowPaywall = config.onShowPaywall ?? config.showPaywall

        // Store custom App User ID if provided (this is an alias, not the RampKit user ID)
        if let customAppUserID = config.appUserID {
            self.appUserID = customAppUserID
            RampKitLogger.verbose("Configure", "appUserID set to \(customAppUserID)")
        }

        RampKitLogger.verbose("Configure", "starting")
        
        // If autoShowOnboarding is enabled, show loading placeholder AND warm up WebView
        #if os(iOS)
        if config.autoShowOnboarding == true {
            await MainActor.run {
                showLoadingPlaceholder()
                warmupWebViewProcess()
            }
        }
        #endif
        
        // Get or generate user ID (fast - keychain lookup)
        do {
            self.userId = await RampKitUserId.getRampKitUserId()
            RampKitLogger.verbose("Configure", "userId \(self.userId ?? "nil")")
        } catch {
            RampKitLogger.warn("Configure", "failed to resolve user id")
        }

        // Start device info collection and event manager setup in background
        // This runs IN PARALLEL with onboarding fetch below
        if let userId = self.userId {
            let appId = config.appId
            let platformWrapper = config.platformWrapper
            let customAppUserID = self.appUserID

            Task.detached(priority: .utility) { [weak self] in
                // Collect device info (now fast - skips slow operations)
                var deviceInfo = DeviceInfoCollector.collect(
                    appUserId: userId,
                    platformWrapper: platformWrapper
                )

                // Add the custom appUserID to device info
                deviceInfo.appUserID = customAppUserID

                // Store reference
                await MainActor.run {
                    self?.deviceInfo = deviceInfo
                }

                // Initialize EventManager (already uses background queue internally)
                EventManager.shared.initialize(appId: appId, deviceInfo: deviceInfo)

                // Start observing StoreKit transactions
                if #available(iOS 15.0, *) {
                    TransactionObserver.shared.startObserving()
                }

                // Sync to backend (non-blocking)
                try? await BackendAPI.syncAppUser(deviceInfo: deviceInfo, appId: appId)
            }
        }

        // Fetch onboarding data (STARTS IMMEDIATELY, doesn't wait for device info)
        RampKitLogger.verbose("Configure", "starting onboarding load")
        do {
            // If customOnboardingURL is provided, use it directly (for testing/staging)
            if let customURL = config.customOnboardingURL {
                guard let url = URL(string: customURL) else {
                    throw NSError(domain: "RampKit", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid custom URL"])
                }
                
                let data = try await fetchData(from: url)
                self.onboardingData = try JSONDecoder().decode(OnboardingData.self, from: data)

                let onboardingId = self.onboardingData?.onboardingId ?? "unknown"
                RampKitLogger.verbose("Configure", "onboardingId \(onboardingId)")
                RampKitLogger.verbose("Configure", "onboarding loaded")
            } else {
                // Build manifest URL
                let manifestUrl = "\(Self.manifestBaseURL)/\(config.appId)/manifest.json"
                RampKitLogger.verbose("Configure", "fetching manifest from \(manifestUrl)")

                guard let url = URL(string: manifestUrl) else {
                    throw NSError(domain: "RampKit", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid manifest URL"])
                }

                // Fetch manifest
                let manifestData = try await fetchData(from: url)
                let manifest = try JSONDecoder().decode(Manifest.self, from: manifestData)

                // Validate targets exist
                guard !manifest.targets.isEmpty else {
                    throw NSError(domain: "RampKit", code: -2, userInfo: [NSLocalizedDescriptionKey: "No targets found in manifest"])
                }

                // Build targeting context from device info
                let targetingContext = TargetingContextBuilder.build(from: self.deviceInfo)
                RampKitLogger.verbose("Configure", "targeting context built")

                // Evaluate targets to find matching onboarding
                guard let result = TargetingEngine.evaluateTargets(
                    manifest.targets,
                    context: targetingContext,
                    userId: self.userId ?? "anonymous"
                ) else {
                    throw NSError(domain: "RampKit", code: -2, userInfo: [NSLocalizedDescriptionKey: "No matching target found in manifest"])
                }

                self.targetingResult = result
                RampKitLogger.verbose(
                    "Configure",
                    "target matched: \"\(result.targetName)\" -> onboarding \(result.onboarding.id) (bucket \(result.bucket))"
                )

                // Track target_matched event (also sets targeting context for all future events)
                EventManager.shared.trackTargetMatched(
                    targetId: result.targetId,
                    targetName: result.targetName,
                    onboardingId: result.onboarding.id,
                    bucket: result.bucket,
                    versionId: result.onboarding.version_id
                )

                // Update deviceInfo with targeting data and sync to backend
                if var deviceInfo = self.deviceInfo {
                    deviceInfo.matchedTargetId = result.targetId
                    deviceInfo.matchedTargetName = result.targetName
                    deviceInfo.matchedOnboardingId = result.onboarding.id
                    deviceInfo.matchedOnboardingVersionId = result.onboarding.version_id
                    deviceInfo.abTestBucket = result.bucket
                    self.deviceInfo = deviceInfo

                    // Sync updated targeting info to backend (non-blocking)
                    if let appId = self.appId {
                        Task {
                            try? await BackendAPI.syncAppUser(deviceInfo: deviceInfo, appId: appId)
                            RampKitLogger.verbose("Configure", "targeting info synced to backend")
                        }
                    }
                }

                // Fetch the selected onboarding JSON
                guard let onboardingUrl = URL(string: result.onboarding.url) else {
                    throw NSError(domain: "RampKit", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid onboarding URL"])
                }

                let onboardingData = try await fetchData(from: onboardingUrl)
                self.onboardingData = try JSONDecoder().decode(OnboardingData.self, from: onboardingData)

                let onboardingId = self.onboardingData?.onboardingId ?? "unknown"
                RampKitLogger.verbose("Configure", "onboardingId \(onboardingId)")
                RampKitLogger.verbose("Configure", "onboarding loaded")
            }
        } catch let error as DecodingError {
            RampKitLogger.warn("Configure", "JSON decode error: \(error)")
            switch error {
            case .keyNotFound(let key, let context):
                RampKitLogger.verbose("Configure", "Missing key: \(key.stringValue) - \(context.debugDescription)")
            case .typeMismatch(let type, let context):
                RampKitLogger.verbose("Configure", "Type mismatch: \(type) - \(context.debugDescription)")
            case .valueNotFound(let type, let context):
                RampKitLogger.verbose("Configure", "Value not found: \(type) - \(context.debugDescription)")
            case .dataCorrupted(let context):
                RampKitLogger.verbose("Configure", "Data corrupted: \(context.debugDescription)")
            @unknown default:
                RampKitLogger.verbose("Configure", "Unknown decode error: \(error)")
            }
            RampKitLogger.warn("Configure", "onboarding load failed")
            self.onboardingData = nil
            self.targetingResult = nil
        } catch {
            RampKitLogger.error("Configure", error)
            RampKitLogger.warn("Configure", "onboarding load failed")
            self.onboardingData = nil
            self.targetingResult = nil
        }

        // Auto-show if configured
        if config.autoShowOnboarding == true, onboardingData != nil {
            RampKitLogger.verbose("Configure", "auto-show onboarding")
            showOnboarding()
        }

        // Log SDK configured (always shown - single summary line)
        RampKitLogger.info("Configured - appId: \(config.appId), userId: \(self.userId ?? "pending")")
    }
    
    /// Show the onboarding overlay
    /// - Parameter options: Optional display options
    public func showOnboarding(options: ShowOnboardingOptions? = nil) {
        #if os(iOS)
        guard let onboardingData = self.onboardingData else {
            RampKitLogger.verbose("ShowOnboarding", "no onboarding data available")
            return
        }

        let onboardingId = onboardingData.onboardingId ?? "unknown"
        RampKitLogger.verbose("ShowOnboarding", "onboardingId: \(onboardingId)")
        RampKitLogger.verbose("ShowOnboarding", "screens count: \(onboardingData.screens.count)")
        
        // Use options callback if provided, otherwise use config callback
        let paywallCallback = options?.onShowPaywall ?? self.onShowPaywall
        
        // Initialize variables from onboarding data
        let variables = initializeVariables(from: onboardingData)
        RampKitLogger.verbose("ShowOnboarding", "initialized variables: \(variables)")

        // Initialize storage with initial values
        OnboardingResponseStorage.initializeVariables(variables)

        // Build context from device info (or fallback if not yet available)
        let context: RampKitContext
        if let deviceInfo = self.deviceInfo {
            context = RampKitContext.build(from: deviceInfo)
            RampKitLogger.verbose("ShowOnboarding", "built context from deviceInfo")
        } else {
            context = RampKitContext.buildDefault(userId: self.userId)
            RampKitLogger.verbose("ShowOnboarding", "using default context (deviceInfo not yet available)")
        }
        
        // ALL UI OPERATIONS MUST BE ON MAIN THREAD
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            // Create overlay controller
            let overlay = RampKitOverlayController(
                onboardingId: onboardingData.onboardingId,
                screens: onboardingData.screens,
                variables: variables,
                requiredScripts: onboardingData.requiredScripts ?? [],
                context: context,
                navigation: onboardingData.navigation,
                components: onboardingData.components,
                onRequestClose: { [weak self] in
                    self?.handleOverlayClose()
                },
                onOnboardingFinished: { [weak self] payload in
                    self?.handleOnboardingFinished(payload: payload)
                },
                onShowPaywall: paywallCallback
            )

            // Present as a full-screen modal inside the host app's main window.
            // This keeps the onboarding safely on top of the app UI while still
            // allowing SDK consumers (e.g. Superwall / RevenueCat) to present
            // their own paywalls above our overlay using normal UIKit APIs.
            overlay.modalPresentationStyle = .fullScreen
            overlay.modalTransitionStyle = .crossDissolve
            
            guard let scene = UIApplication.shared.connectedScenes
                .first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene,
                  let hostWindow = scene.windows.first(where: { $0.isKeyWindow }) ?? scene.windows.first,
                  let rootViewController = hostWindow.rootViewController else {
                RampKitLogger.warn("ShowOnboarding", "No active root view controller to present overlay")
                return
            }

            guard self.currentOverlay == nil else {
                RampKitLogger.verbose("ShowOnboarding", "Overlay already presented, ignoring duplicate show request")
                return
            }

            let presenter = self.topViewController(from: rootViewController) ?? rootViewController
            self.currentOverlay = overlay

            RampKitLogger.verbose("ShowOnboarding", "presenting overlay modally from \(type(of: presenter))")
            presenter.present(overlay, animated: false) {
                RampKitLogger.verbose("ShowOnboarding", "Overlay presented modally")
            }
        }
        #endif
    }
    
    #if os(iOS)
    /// Find the top-most view controller starting from a given root.
    /// This is used to present the onboarding overlay modally so that
    /// other SDKs (e.g. paywall frameworks) can stack their UI above it.
    private func topViewController(from root: UIViewController?) -> UIViewController? {
        guard let root = root else { return nil }
        
        if let navigationController = root as? UINavigationController {
            return topViewController(from: navigationController.visibleViewController ?? navigationController.topViewController)
        }
        
        if let tabBarController = root as? UITabBarController {
            if let selected = tabBarController.selectedViewController {
                return topViewController(from: selected)
            }
        }
        
        if let presented = root.presentedViewController {
            return topViewController(from: presented)
        }
        
        return root
    }
    #endif
    
    /// Close the onboarding overlay programmatically
    public func closeOnboarding() {
        #if os(iOS)
        DispatchQueue.main.async { [weak self] in
            self?.currentOverlay?.dismissOverlay()
        }
        #endif
    }

    /// Reset the SDK state and re-initialize
    /// Call this when a user logs out or when you need to clear all cached state
    @available(iOS 14.0, macOS 11.0, *)
    public func reset() async {
        guard let config = self.config else {
            RampKitLogger.warn("Reset", "no config found, cannot re-initialize")
            return
        }

        RampKitLogger.verbose("Reset", "clearing SDK state...")

        // Stop transaction observer
        if #available(iOS 15.0, *) {
            TransactionObserver.shared.stopObserving()
        }

        // Reset event manager
        EventManager.shared.reset()

        // Clear local state
        self.userId = nil
        self.deviceInfo = nil
        self.onboardingData = nil
        self.targetingResult = nil
        self.appUserID = nil

        // Clear stored onboarding variables
        OnboardingResponseStorage.clearVariables()

        #if os(iOS)
        // Clean up any UI state
        await MainActor.run {
            self.currentOverlay = nil
            self.loadingView?.removeFromSuperview()
            self.loadingView = nil
            self.warmupWebView?.stopLoading()
            self.warmupWebView = nil
        }
        #endif

        RampKitLogger.verbose("Reset", "re-initializing SDK...")

        // Re-initialize with stored config
        await configure(config: config)
    }

    /// Initialize RampKit with configuration (deprecated)
    /// - Parameter config: Configuration object
    @available(iOS 14.0, macOS 11.0, *)
    @available(*, deprecated, message: "Use configure() instead")
    public func initialize(config: RampKitConfig) async {
        RampKitLogger.warn("Deprecated", "initialize() is deprecated, use configure() instead")
        await configure(config: config)
    }

    /// Set a custom App User ID to associate with this user.
    /// This is an alias for your own user identification system.
    ///
    /// Note: This does NOT replace the RampKit-generated user ID (appUserId).
    /// RampKit will continue to use its own stable UUID for internal tracking.
    /// This custom ID is sent to the backend for you to correlate with your own user database.
    ///
    /// - Parameter appUserID: Your custom user identifier
    @available(iOS 14.0, macOS 11.0, *)
    public func setAppUserID(_ appUserID: String) async {
        self.appUserID = appUserID
        RampKitLogger.verbose("SetAppUserID", appUserID)

        // Update device info with the new appUserID
        if var deviceInfo = self.deviceInfo {
            deviceInfo.appUserID = appUserID
            self.deviceInfo = deviceInfo

            // Sync updated info to backend
            if let appId = self.appId {
                do {
                    try await BackendAPI.syncAppUser(deviceInfo: deviceInfo, appId: appId)
                    RampKitLogger.verbose("SetAppUserID", "synced to backend")
                } catch {
                    RampKitLogger.warn("SetAppUserID", "failed to sync to backend: \(error)")
                }
            }
        }
    }

    /// Get the custom App User ID if one has been set.
    /// - Returns: The custom App User ID or nil if not set
    public func getAppUserID() -> String? {
        return appUserID
    }

    /// Get cached onboarding data
    /// - Returns: Onboarding data if available
    public func getOnboardingData() -> OnboardingData? {
        return onboardingData
    }
    
    /// Get generated user ID
    /// - Returns: User ID if available
    public func getUserId() -> String? {
        return userId
    }

    /// Get configured app ID
    /// - Returns: App ID if configured
    public func getAppId() -> String? {
        return appId
    }
    
    /// Get collected device info
    /// - Returns: DeviceInfo if available (after initialization)
    public func getDeviceInfo() -> DeviceInfo? {
        return deviceInfo
    }

    /// Get the targeting result (which target matched and which onboarding was selected)
    /// - Returns: TargetEvaluationResult if available (after targeting evaluation)
    public func getTargetingResult() -> TargetEvaluationResult? {
        return targetingResult
    }

    /// Get all user answers from onboarding
    public func getAnswers() -> [String: Any] {
        return OnboardingResponseStorage.getVariables()
    }

    /// Get a single answer by key
    public func getAnswer(_ key: String) -> Any? {
        return OnboardingResponseStorage.getVariables()[key]
    }

    // MARK: - Private Methods
    
    /// Initialize variables from onboarding data
    private func initializeVariables(from data: OnboardingData) -> [String: Any] {
        var variables: [String: Any] = [:]
        
        if let stateArray = data.variables?.state {
            for variable in stateArray {
                // Only add variables that have an initial value
                if let initialValue = variable.initialValue {
                    variables[variable.name] = initialValue.value
                }
            }
        }
        
        return variables
    }
    
    /// Handle overlay close request
    private func handleOverlayClose() {
        #if os(iOS)
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            guard let overlay = self.currentOverlay else {
                RampKitLogger.verbose("CloseOnboarding", "No current overlay to close")
                return
            }

            // If the overlay is currently presented, dismiss it from the
            // presenting view controller. The fade-out animation is handled
            // inside RampKitOverlayController.dismissOverlay().
            if overlay.presentingViewController != nil {
                overlay.dismiss(animated: false) {
                    RampKitLogger.verbose("CloseOnboarding", "Overlay view controller dismissed")
                }
            } else {
                RampKitLogger.verbose("CloseOnboarding", "Overlay not presented, clearing reference only")
            }

            self.currentOverlay = nil
        }
        #endif
    }
    
    #if os(iOS)
    /// Show loading placeholder immediately (for autoShowOnboarding)
    private func showLoadingPlaceholder() {
        guard loadingView == nil else { return }

        RampKitLogger.verbose("Configure", "showing loading placeholder")

        guard let scene = UIApplication.shared.connectedScenes
            .first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene,
              let hostWindow = scene.windows.first(where: { $0.isKeyWindow }) ?? scene.windows.first else {
            RampKitLogger.warn("Configure", "No window for loading placeholder")
            return
        }

        // Create simple loading view and add to window
        let loading = UIView(frame: hostWindow.bounds)
        loading.backgroundColor = .white
        loading.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        hostWindow.addSubview(loading)
        self.loadingView = loading

        RampKitLogger.verbose("Configure", "Loading placeholder shown")
    }

    /// Hide loading placeholder (removes instantly - called after overlay is fully visible)
    func hideLoadingPlaceholder() {
        guard let loading = loadingView else { return }

        RampKitLogger.verbose("Configure", "removing loading placeholder")
        loading.removeFromSuperview()
        self.loadingView = nil
        RampKitLogger.verbose("Configure", "Loading placeholder removed")
    }

    /// Pre-warm the WebView process while network fetch is happening
    /// This spins up WebKit's WebContent process and JS engine in the background
    private func warmupWebViewProcess() {
        guard warmupWebView == nil else { return }

        RampKitLogger.verbose("Configure", "warming up WebView process")

        let config = WKWebViewConfiguration()
        config.preferences.javaScriptEnabled = true

        // Create a small WebView (doesn't need to be visible)
        let webView = CustomWebView(frame: CGRect(x: 0, y: 0, width: 1, height: 1), configuration: config)

        // Load a minimal HTML to fully initialize the JS engine
        webView.loadHTMLString("<html><body></body></html>", baseURL: nil)

        self.warmupWebView = webView
        RampKitLogger.verbose("Configure", "WebView warmup started")
    }

    /// Clean up warmup WebView (called after real WebViews are created)
    func cleanupWarmupWebView() {
        warmupWebView?.stopLoading()
        warmupWebView = nil
        RampKitLogger.verbose("Configure", "Warmup WebView cleaned up")
    }
    #endif
    
    /// Handle onboarding finished event
    private func handleOnboardingFinished(payload: Any?) {
        do {
            try onOnboardingFinished?(payload)
        } catch {
            // Silently ignore callback errors
        }
        
        // Close overlay after callback
        closeOnboarding()
    }
    
    // MARK: - Network Helper
    
    /// Fetch data from URL (iOS 14 compatible) - NO CACHING
    @available(iOS 14.0, macOS 11.0, *)
    private func fetchData(from url: URL) async throws -> Data {
        // Create request with NO CACHE policy
        var request = URLRequest(url: url)
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        request.timeoutInterval = 30
        
        // Add cache-busting headers
        request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
        request.setValue("no-cache", forHTTPHeaderField: "Pragma")
        
        RampKitLogger.verbose("Fetch", "Fetching with NO CACHE: \(url.absoluteString)")
        
        #if compiler(>=5.5) && (os(iOS) || os(macOS) || os(watchOS) || os(tvOS))
        if #available(iOS 15.0, macOS 12.0, watchOS 8.0, tvOS 15.0, *) {
            // Use modern async/await API
            let (data, _) = try await URLSession.shared.data(for: request)
            return data
        } else {
            // Use completion handler API with continuation
            return try await withCheckedThrowingContinuation { continuation in
                let task = URLSession.shared.dataTask(with: request) { data, response, error in
                    if let error = error {
                        continuation.resume(throwing: error)
                        return
                    }
                    
                    guard let data = data else {
                        continuation.resume(throwing: NSError(
                            domain: "RampKit",
                            code: -1,
                            userInfo: [NSLocalizedDescriptionKey: "No data received"]
                        ))
                        return
                    }
                    
                    continuation.resume(returning: data)
                }
                task.resume()
            }
        }
        #else
        // Fallback for older Swift versions
        return try await withCheckedThrowingContinuation { continuation in
            let task = URLSession.shared.dataTask(with: request) { data, response, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }
                
                guard let data = data else {
                    continuation.resume(throwing: NSError(
                        domain: "RampKit",
                        code: -1,
                        userInfo: [NSLocalizedDescriptionKey: "No data received"]
                    ))
                    return
                }
                
                continuation.resume(returning: data)
            }
            task.resume()
        }
        #endif
    }
}

