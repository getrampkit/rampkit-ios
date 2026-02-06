import Foundation
#if canImport(UIKit)
import UIKit
#endif
#if canImport(WebKit)
import WebKit
#endif

#if os(iOS)
/// Full-screen overlay controller for onboarding flow
public class RampKitOverlayController: UIViewController {
    
    // MARK: - Properties
    
    private let onboardingId: String?
    private let screens: [ScreenPayload]
    private var sharedVariables: [String: Any]
    private let requiredScripts: [String]
    private let context: RampKitContext?
    private let navigation: NavigationData?
    private let components: [String: SDKComponent]?
    
    private let onRequestClose: (() -> Void)?
    private let onOnboardingFinished: ((Any?) -> Void)?
    private let onShowPaywall: ((Any?) -> Void)?
    
    private var currentIndex: Int = 0
    private var isTransitioning: Bool = false
    
    private var webViews: [CustomWebView] = []
    private var pageController: UIPageViewController!
    private var fadeCurtain: UIView!
    
    fileprivate let messageHandler = RampKitMessageHandler()
    
    /// Timestamps for tracking when variables were sent to each WebView
    private var lastVariableSendTime: [Int: Date] = [:]
    
    /// Stale value filtering window (600ms)
    private let staleValueWindow: TimeInterval = 0.6
    
    /// Track which screens are currently active/visible
    private var activeScreenIndex: Int = 0
    
    /// Queue of pending actions per screen (to be triggered when screen becomes active)
    private var pendingActions: [Int: [() -> Void]] = [:]

    /// Prevent duplicate review requests in the same session
    private var hasRequestedReview: Bool = false

    /// Track if initial layout has completed (prevents "slide down" glitch)
    private var hasCompletedInitialLayout: Bool = false

    /// Pending variable_set events for debouncing (fires after 1000ms idle or on blur)
    /// screenName is captured at time of change, not when event fires
    private var pendingVariableEvents: [String: (previousValue: Any?, newValue: Any, screenName: String?, timer: Timer?)] = [:]

    /// Debounce interval for variable_set events (1 second)
    private let variableDebounceInterval: TimeInterval = 1.0

    // MARK: - Initialization
    
    init(
        onboardingId: String?,
        screens: [ScreenPayload],
        variables: [String: Any],
        requiredScripts: [String],
        context: RampKitContext?,
        navigation: NavigationData?,
        components: [String: SDKComponent]?,
        onRequestClose: (() -> Void)?,
        onOnboardingFinished: ((Any?) -> Void)?,
        onShowPaywall: ((Any?) -> Void)?
    ) {
        self.onboardingId = onboardingId
        self.screens = screens
        self.sharedVariables = variables
        self.requiredScripts = requiredScripts
        self.context = context
        self.navigation = navigation
        self.components = components
        self.onRequestClose = onRequestClose
        self.onOnboardingFinished = onOnboardingFinished
        self.onShowPaywall = onShowPaywall

        super.init(nibName: nil, bundle: nil)

        messageHandler.delegate = self
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    // MARK: - Lifecycle
    
    public override func viewDidLoad() {
        super.viewDidLoad()
        
        RampKitLogger.verbose("Overlay", "viewDidLoad - Initial activeScreenIndex: \(activeScreenIndex)")
        
        view.backgroundColor = .white
        view.alpha = 1  // Keep opaque - use fadeCurtain to hide loading content
        view.isUserInteractionEnabled = true
        view.isHidden = false
        view.insetsLayoutMarginsFromSafeArea = false  // Ignore safe areas
        
        setupPageController()
        setupFadeCurtain()
        createWebViews()
        
        RampKitLogger.verbose("Overlay", "mounted: docs= \(screens.count)")
    }
    
    public override var prefersHomeIndicatorAutoHidden: Bool {
        return true  // Hide home indicator for cleaner full-screen look
    }
    
    public override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        
        RampKitLogger.verbose("Overlay", "viewDidAppear - frame: \(view.frame)")
        RampKitLogger.verbose("Overlay", "pageController.view frame: \(pageController.view.frame)")
        RampKitLogger.verbose("Overlay", "fadeCurtain frame: \(fadeCurtain.frame), hidden: \(fadeCurtain.isHidden), alpha: \(fadeCurtain.alpha)")
        RampKitLogger.verbose("Overlay", "Number of webViews: \(webViews.count)")
        RampKitLogger.verbose("Overlay", "View alpha: \(view.alpha)")
        RampKitLogger.verbose("Overlay", "View isUserInteractionEnabled: \(view.isUserInteractionEnabled)")
        RampKitLogger.verbose("Overlay", "View subviews count: \(view.subviews.count)")
        RampKitLogger.verbose("Overlay", "modalPresentationStyle: \(modalPresentationStyle.rawValue)")
        
        // Don't set alpha here - we fade in when WebView is ready
        view.isUserInteractionEnabled = true
    }

    public override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()

        // Mark initial layout as complete - this ensures WebViews have correct size
        // before we reveal content (prevents the "slide down" glitch)
        if !hasCompletedInitialLayout {
            hasCompletedInitialLayout = true
            RampKitLogger.verbose("Overlay", "Initial layout completed - bounds: \(view.bounds)")
        }
    }

    // MARK: - Setup
    
    private func setupPageController() {
        pageController = UIPageViewController(
            transitionStyle: .scroll,
            navigationOrientation: .horizontal,
            options: nil
        )
        
        pageController.dataSource = self
        pageController.delegate = self
        
        // Disable default swipe gestures and ensure touches pass through
        for subview in pageController.view.subviews {
            if let scrollView = subview as? UIScrollView {
                scrollView.isScrollEnabled = false
                scrollView.delaysContentTouches = false
                scrollView.canCancelContentTouches = false
                RampKitLogger.verbose("Overlay", "Configured scrollView in pageController")
            }
        }
        
        addChild(pageController)
        view.addSubview(pageController.view)

        // Use Auto Layout instead of frame-based layout
        // This ensures correct sizing during modal presentation before viewDidAppear
        pageController.view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            pageController.view.topAnchor.constraint(equalTo: view.topAnchor),
            pageController.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            pageController.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            pageController.view.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])

        pageController.view.isUserInteractionEnabled = true
        pageController.didMove(toParent: self)
    }
    
    private func setupFadeCurtain() {
        fadeCurtain = UIView()
        fadeCurtain.backgroundColor = .white
        fadeCurtain.alpha = 1  // Start visible - covers WebViews while loading
        fadeCurtain.isUserInteractionEnabled = false
        fadeCurtain.isHidden = false
        view.addSubview(fadeCurtain)

        // Use Auto Layout instead of frame-based layout
        fadeCurtain.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            fadeCurtain.topAnchor.constraint(equalTo: view.topAnchor),
            fadeCurtain.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            fadeCurtain.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            fadeCurtain.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }
    
    private func createWebViews() {
        // Load ALL WebViews immediately for instant transitions
        // BUT mark them as inactive - JavaScript won't auto-trigger
        for (index, screen) in screens.enumerated() {
        let config = WKWebViewConfiguration()
        
        // Enable JavaScript
        config.preferences.javaScriptEnabled = true
        
        // Media playback settings
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []
        
        // Disable data detectors
        config.dataDetectorTypes = []
        
        // Add message handler
        config.userContentController.add(WebViewMessageProxy(handler: self, index: index), name: "rampkit")
        
        // CRITICAL: Polyfill for React Native compatibility
        let polyfillScript = WKUserScript(
            source: """
            window.ReactNativeWebView = {
                postMessage: function(data) {
                    try {
                        window.webkit.messageHandlers.rampkit.postMessage(data);
                    } catch(e) {
                        console.error('Failed to forward message:', e);
                    }
                }
            };
            console.log('✅ ReactNativeWebView polyfill installed');
            """,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: false
        )
            config.userContentController.addUserScript(polyfillScript)
            
            // CRITICAL: Dynamic tap click interceptor - runs BEFORE onclick handlers
            let dynamicTapScript = WKUserScript(
                source: """
                (function() {
                    if (window.__rampkitClickInterceptorInstalled) return;
                    window.__rampkitClickInterceptorInstalled = true;
                    
                    // Decode HTML entities
                    function decodeHtml(str) {
                        if (!str) return str;
                        return str.replace(/&quot;/g, '"').replace(/&#34;/g, '"').replace(/&#x22;/g, '"')
                                  .replace(/&apos;/g, "'").replace(/&#39;/g, "'").replace(/&#x27;/g, "'")
                                  .replace(/&lt;/g, '<').replace(/&gt;/g, '>').replace(/&amp;/g, '&');
                    }
                    
                    // Find dynamic tap config on element or ancestors - check ALL possible attribute names
                    function findDynamicTap(el) {
                        var current = el;
                        var depth = 0;
                        var attrNames = ['data-tap-dynamic', 'data-tapdynamic', 'tapDynamic', 'data-dynamic-tap'];
                        while (current && current !== document.body && current !== document.documentElement && depth < 20) {
                            if (current.getAttribute) {
                                // Check all possible attribute names
                                for (var i = 0; i < attrNames.length; i++) {
                                    var attr = current.getAttribute(attrNames[i]);
                                    if (attr && attr.length > 2) {
                                        console.log('[DynTap] Found attr ' + attrNames[i] + ' at depth ' + depth);
                                        return { element: current, config: attr };
                                    }
                                }
                                // Also check dataset
                                if (current.dataset && current.dataset.tapDynamic) {
                                    console.log('[DynTap] Found dataset.tapDynamic at depth ' + depth);
                                    return { element: current, config: current.dataset.tapDynamic };
                                }
                            }
                            current = current.parentElement;
                            depth++;
                        }
                        return null;
                    }
                    
                    // Get variables for condition evaluation - check ALL possible sources
                    function getVars() {
                        // Try multiple sources - the page might update variables in different places
                        var vars = {};
                        
                        // 1. Check window.__rampkitVariables (set by native broadcasts)
                        if (window.__rampkitVariables) {
                            Object.keys(window.__rampkitVariables).forEach(function(k) {
                                vars[k] = window.__rampkitVariables[k];
                            });
                        }
                        
                        // 2. Check window.__rampkitVars (rebuilt by template resolver)
                        if (window.__rampkitVars) {
                            Object.keys(window.__rampkitVars).forEach(function(k) {
                                vars[k] = window.__rampkitVars[k];
                            });
                        }
                        
                        // 3. Check window.RK_VARS (some editors use this)
                        if (window.RK_VARS) {
                            Object.keys(window.RK_VARS).forEach(function(k) {
                                vars[k] = window.RK_VARS[k];
                            });
                        }
                        
                        // 4. Check for any global state object the page might use
                        if (window.__state) {
                            Object.keys(window.__state).forEach(function(k) {
                                vars[k] = window.__state[k];
                            });
                        }
                        
                        sendDiag('getVars result: ' + JSON.stringify(vars));
                        return vars;
                    }
                    
                    // Evaluate a single rule
                    function evalRule(rule, vars) {
                        if (!rule || !rule.key) return false;
                        var left = vars[rule.key];
                        var right = rule.value;
                        var op = rule.op || '=';
                        if (left === undefined || left === null) left = '';
                        if (right === undefined || right === null) right = '';
                        var leftStr = String(left);
                        var rightStr = String(right);
                        var result = false;
                        switch (op) {
                            case '=': case '==': result = leftStr === rightStr; break;
                            case '!=': case '<>': result = leftStr !== rightStr; break;
                            case '>': result = parseFloat(left) > parseFloat(right); break;
                            case '<': result = parseFloat(left) < parseFloat(right); break;
                            case '>=': result = parseFloat(left) >= parseFloat(right); break;
                            case '<=': result = parseFloat(left) <= parseFloat(right); break;
                            default: result = false;
                        }
                        sendDiag('Rule: ' + rule.key + ' ' + op + ' "' + rightStr + '" | actual="' + leftStr + '" | result=' + result);
                        return result;
                    }
                    
                    // Evaluate all rules (AND logic)
                    function evalRules(rules, vars) {
                        if (!rules || !rules.length) return true;
                        for (var i = 0; i < rules.length; i++) {
                            if (!evalRule(rules[i], vars)) return false;
                        }
                        return true;
                    }
                    
                    // Execute an action
                    function execAction(action) {
                        if (!action || !action.type) return;
                        sendDiag('execAction: ' + action.type + ' | full: ' + JSON.stringify(action));
                        var msg = null;
                        var actionType = action.type.toLowerCase();
                        
                        switch (actionType) {
                            case 'navigate':
                                msg = { type: 'rampkit:navigate', targetScreenId: action.targetScreenId || '__continue__', animation: action.animation || 'fade' };
                                break;
                            case 'continue':
                                msg = { type: 'rampkit:navigate', targetScreenId: '__continue__', animation: action.animation || 'fade' };
                                break;
                            case 'goback':
                                msg = { type: 'rampkit:goBack', animation: action.animation || 'fade' };
                                break;
                            case 'close':
                                msg = { type: 'rampkit:close' };
                                break;
                            case 'haptic':
                                msg = { type: 'rampkit:haptic', hapticType: action.hapticType || 'impact', impactStyle: action.impactStyle || 'Medium', notificationType: action.notificationType };
                                break;
                            case 'showpaywall':
                                msg = { type: 'rampkit:show-paywall', payload: action.payload || { paywallId: action.paywallId } };
                                break;
                            case 'requestreview':
                                // Prevent duplicate review requests in the same session
                                if (!window.__rampkitReviewRequested) {
                                    window.__rampkitReviewRequested = true;
                                    msg = { type: 'rampkit:request-review' };
                                } else {
                                    console.log('[RampKit] Skipping duplicate review request (tap)');
                                    return;
                                }
                                break;
                            case 'requestnotificationpermission':
                                msg = { type: 'rampkit:request-notification-permission' };
                                break;
                            case 'onboardingfinished':
                            case 'finishonboarding':
                            case 'finish':
                                msg = { type: 'rampkit:onboarding-finished', payload: action.payload };
                                break;
                            // Support multiple names for setting variables
                            case 'setvariable':
                            case 'setstate':
                            case 'updatevariable':
                            case 'set':
                            case 'assign':
                                // Try different property names for key/value
                                var varKey = action.key || action.variableName || action.name || action.variable;
                                // Check ALL possible value property names
                                var varValue = action.variableValue !== undefined ? action.variableValue :
                                               action.value !== undefined ? action.value :
                                               action.newValue !== undefined ? action.newValue : undefined;
                                sendDiag('setVariable: key=' + varKey + ' value=' + varValue);
                                if (varKey && varValue !== undefined) {
                                    if (window.__rampkitVariables) window.__rampkitVariables[varKey] = varValue;
                                    if (window.__rampkitVars) window.__rampkitVars[varKey] = varValue;
                                    var updateVars = {};
                                    updateVars[varKey] = varValue;
                                    if (typeof window.rampkitUpdateVariables === 'function') window.rampkitUpdateVariables(updateVars);
                                    msg = { type: 'rampkit:variables', vars: updateVars };
                                    sendDiag('Sending variable update: ' + JSON.stringify(updateVars));
                                }
                                break;
                            case 'addclass':
                                if (action.class) {
                                    var targets = action.selector ? document.querySelectorAll(action.selector) : [window.__rampkitCurrentTapElement];
                                    targets.forEach(function(el) { if (el) el.classList.add(action.class); });
                                }
                                break;
                            case 'removeclass':
                                if (action.class) {
                                    var targets = action.selector ? document.querySelectorAll(action.selector) : [window.__rampkitCurrentTapElement];
                                    targets.forEach(function(el) { if (el) el.classList.remove(action.class); });
                                }
                                break;
                            case 'toggleclass':
                                if (action.class) {
                                    var targets = action.selector ? document.querySelectorAll(action.selector) : [window.__rampkitCurrentTapElement];
                                    targets.forEach(function(el) { if (el) el.classList.toggle(action.class); });
                                }
                                break;
                            case 'selectone':
                                // Radio-button behavior: remove class from all, add to tapped
                                if (action.class && action.selector) {
                                    document.querySelectorAll(action.selector).forEach(function(el) {
                                        el.classList.remove(action.class);
                                    });
                                    if (window.__rampkitCurrentTapElement) {
                                        window.__rampkitCurrentTapElement.classList.add(action.class);
                                    }
                                }
                                break;
                            default:
                                sendDiag('Unknown action type: ' + action.type);
                        }
                        if (msg) {
                            sendDiag('Sending message: ' + msg.type);
                            try { window.webkit.messageHandlers.rampkit.postMessage(JSON.stringify(msg)); } catch(e) { sendDiag('Send error: ' + e); }
                        }
                    }
                    
                    // Evaluate dynamic tap config
                    function evalDynamicTap(config) {
                        console.log('[DynTap] evalDynamicTap called');
                        if (!config || !config.values) {
                            console.log('[DynTap] No config.values');
                            return false;
                        }
                        var vars = getVars();
                        console.log('[DynTap] Current vars:', JSON.stringify(vars));
                        var conditions = config.values;
                        console.log('[DynTap] Checking ' + conditions.length + ' conditions');
                        for (var i = 0; i < conditions.length; i++) {
                            var cond = conditions[i];
                            var condType = cond.conditionType || 'if';
                            var rules = cond.rules || [];
                            var actions = cond.actions || [];
                            console.log('[DynTap] Condition ' + i + ': type=' + condType + ', rules=' + rules.length + ', actions=' + actions.length);
                            if (condType === 'else' || evalRules(rules, vars)) {
                                console.log('[DynTap] Condition ' + i + ' MATCHED!');
                                for (var j = 0; j < actions.length; j++) {
                                    execAction(actions[j]);
                                }
                                return true;
                            }
                        }
                        console.log('[DynTap] No conditions matched');
                        return false;
                    }
                    
                    // Send diagnostic to native (will show in RampKit logs)
                    function sendDiag(msg) {
                        try {
                            window.webkit.messageHandlers.rampkit.postMessage(JSON.stringify({
                                type: 'rampkit:debug',
                                message: msg
                            }));
                        } catch(e) {}
                    }
                    
                    // Click interceptor - capture phase, runs BEFORE onclick handlers
                    function interceptClick(event) {
                        // Store tapped element for CSS class actions
                        window.__rampkitCurrentTapElement = event.target;
                        sendDiag('Click on: ' + event.target.tagName + ' ' + (event.target.className || ''));
                        var result = findDynamicTap(event.target);
                        if (!result) {
                            sendDiag('No data-tap-dynamic found');
                            return;
                        }
                        
                        sendDiag('Found dynamic tap config, length: ' + result.config.length);
                        try {
                            var configStr = decodeHtml(result.config);
                            var config = JSON.parse(configStr);
                            sendDiag('Parsed OK, values: ' + (config.values ? config.values.length : 0));
                            var handled = evalDynamicTap(config);
                            if (handled) {
                                sendDiag('HANDLED - blocking original event');
                                event.stopImmediatePropagation();
                                event.preventDefault();
                                return false;
                            } else {
                                sendDiag('No conditions matched');
                            }
                        } catch (e) {
                            sendDiag('Parse error: ' + e.message);
                        }
                    }
                    
                    // Install interceptor on window in capture phase
                    window.addEventListener('click', interceptClick, true);
                    sendDiag('Click interceptor installed');
                })();
                """,
                injectionTime: .atDocumentStart,
                forMainFrameOnly: false
            )
            config.userContentController.addUserScript(dynamicTapScript)
            
            // CRITICAL: Inject visibility flag - screen starts as INACTIVE
            let visibilityScript = WKUserScript(
                source: """
                window.__rampkitScreenVisible = false;
                window.__rampkitScreenIndex = \(index);
                console.log('🔒 Screen \(index) loaded but INACTIVE');
                """,
                injectionTime: .atDocumentStart,
                forMainFrameOnly: false
            )
            config.userContentController.addUserScript(visibilityScript)
            
            // Inject hardening script before content loads
            // TEMPORARILY DISABLED FOR DEBUGGING
            // let hardeningScript = WKUserScript(
            //     source: InjectedScripts.hardening,
            //     injectionTime: .atDocumentStart,
            //     forMainFrameOnly: true
            // )
            // config.userContentController.addUserScript(hardeningScript)
        
        // Create WebView with CONSOLE LOGGING
        if #available(iOS 16.4, *) {
            config.preferences.isElementFullscreenEnabled = true
        }
        
        // CRITICAL: Use .zero frame initially - Auto Layout will set correct size
        // This prevents the "slide down" glitch caused by frame mismatch during modal presentation
        let webView = CustomWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = self
        webView.scrollView.isScrollEnabled = true
        webView.scrollView.delaysContentTouches = false
        webView.scrollView.canCancelContentTouches = false
        webView.scrollView.contentInsetAdjustmentBehavior = .never  // Don't add safe area insets
        webView.backgroundColor = .white
        webView.isOpaque = true
        webView.isUserInteractionEnabled = true
        
        // Enable console logging
        if #available(iOS 16.4, *) {
            webView.isInspectable = true
        }
        
        // Build and load HTML with context for template resolution
        let html = HTMLBuilder.buildHTMLDocument(
            screen: screen,
            variables: sharedVariables,
            requiredScripts: requiredScripts,
            context: context,
            components: components
        )
        
        webView.loadHTMLString(html, baseURL: nil)
        webViews.append(webView)
        }
        
        // Set initial page - ACTIVATE first screen
        if let firstWebView = webViews.first {
            let wrapperVC = WebViewWrapperController(webView: firstWebView)
            pageController.setViewControllers(
                [wrapperVC],
                direction: .forward,
                animated: false
            )
            
            // Mark first screen as visible
            activateScreen(at: 0)
            
            // Track onboarding started event
            if #available(iOS 14.0, *) {
                EventManager.shared.setFlow(flowId: onboardingId)
                // Set initial screen context for subsequent events (e.g., variable_set)
                let initialScreenName = screens.first?.label ?? screens.first?.id
                EventManager.shared.setScreen(name: initialScreenName)
                EventManager.shared.trackOnboardingStarted(flowId: onboardingId, totalSteps: screens.count)
            }
            
            // Clean up the warmup WebView (no longer needed)
            RampKitCore.shared.cleanupWarmupWebView()
            
            RampKitLogger.verbose("Overlay", "All screens preloaded, screen 0 activated")
        }
    }
    
    /// Activate a screen (make it visible/interactive)
    private func activateScreen(at index: Int) {
        guard index >= 0, index < webViews.count else { return }

        RampKitLogger.verbose("Overlay", "Activating screen \(index) (was: \(activeScreenIndex))")
        
        // Update active screen tracker
        activeScreenIndex = index
        
        let webView = webViews[index]
        
        // Inject visibility flag as TRUE
        let activateScript = """
        (function() {
            window.__rampkitScreenVisible = true;
            console.log('🔓 Screen \(index) ACTIVATED - JavaScript can now run');
            
            // Dispatch custom event that HTML can listen to
            document.dispatchEvent(new CustomEvent('rampkit:screen-visible', {
                detail: { screenIndex: \(index), screenId: '\(screens[index].id)' }
            }));
        })();
        """
        
        webView.evaluateJavaScript(activateScript) { [weak self] _, error in
            if let error = error {
                RampKitLogger.warn("Overlay", "Failed to activate screen \(index): \(error)")
            } else {
                RampKitLogger.verbose("Overlay", "Screen \(index) activated")
                
                // Send onboarding state to the activated screen
                self?.sendOnboardingStateToWebView(at: index)
                
                // Process any pending actions for this screen
                self?.processPendingActions(for: index)
            }
        }
    }
    
    /// Process any actions that were queued while screen was inactive
    private func processPendingActions(for index: Int) {
        guard let actions = pendingActions[index], !actions.isEmpty else { return }

        RampKitLogger.verbose("Overlay", "Processing \(actions.count) pending action(s) for screen \(index)")
        
        for action in actions {
            action()
        }
        
        // Clear the queue
        pendingActions[index] = nil
    }
    
    /// Queue an action to be executed when screen becomes active
    private func queueAction(for index: Int, action: @escaping () -> Void) {
        RampKitLogger.verbose("Overlay", "Queuing action for screen \(index)")
        
        if pendingActions[index] == nil {
            pendingActions[index] = []
        }
        pendingActions[index]?.append(action)
    }
    
    /// Deactivate a screen (mark as not visible)
    private func deactivateScreen(at index: Int) {
        guard index >= 0, index < webViews.count else { return }

        RampKitLogger.verbose("Overlay", "Deactivating screen \(index)")
        
        let webView = webViews[index]
        
        let deactivateScript = """
        window.__rampkitScreenVisible = false;
        console.log('🔒 Screen \(index) DEACTIVATED');
        """
        
        webView.evaluateJavaScript(deactivateScript)
    }
    
    /// Check if a screen index is currently active
    private func isScreenActive(_ index: Int) -> Bool {
        return index == activeScreenIndex
    }
    
    // MARK: - Navigation
    
    private enum NavigationAnimation {
        case fade
        case slide
        case slideFade  // Combined slide + fade for super smooth transitions
    }
    
    private func navigateToIndex(_ index: Int, animation: NavigationAnimation = .fade) {
        guard index != currentIndex,
              index >= 0,
              index < screens.count,
              !isTransitioning else { return }

        let oldIndex = currentIndex
        let direction: UIPageViewController.NavigationDirection = index > currentIndex ? .forward : .reverse

        // Track screen navigation event
        let fromScreen = oldIndex >= 0 && oldIndex < screens.count ? screens[oldIndex] : nil
        let fromScreenName = fromScreen?.label ?? fromScreen?.id
        let toScreenName = screens[index].label ?? screens[index].id
        EventManager.shared.trackScreenNavigated(
            fromScreenName: fromScreenName,
            toScreenName: toScreenName,
            direction: index > oldIndex ? "forward" : "back"
        )

        // Update current screen context for subsequent events (e.g., variable_set)
        EventManager.shared.setScreen(name: toScreenName)

        let targetWebView = webViews[index]
        let wrapperVC = WebViewWrapperController(webView: targetWebView)
        
        // Track screen view event
        // Deactivate old screen, activate new screen
        deactivateScreen(at: oldIndex)
        activateScreen(at: index)
        
        switch animation {
        case .slide:
            pageController.setViewControllers(
                [wrapperVC],
                direction: direction,
                animated: true
            )
            currentIndex = index
            
        case .slideFade:
            // Smooth slide + fade: both screens move together
            isTransitioning = true

            let containerView = pageController.view!
            let slideOffset: CGFloat = 200
            let isForward = direction == .forward

            // Get the current page controller's view (the wrapper VC's view)
            guard let currentVC = pageController.viewControllers?.first else {
                isTransitioning = false
                return
            }
            let currentView = currentVC.view!

            // Add target on top, starting transparent and offset
            // Temporarily enable frame-based layout for animation (WebView may have Auto Layout from previous wrapper)
            targetWebView.translatesAutoresizingMaskIntoConstraints = true
            containerView.addSubview(targetWebView)
            targetWebView.frame = containerView.bounds
            targetWebView.alpha = 0
            targetWebView.transform = CGAffineTransform(translationX: isForward ? slideOffset : -slideOffset, y: 0)

            // Animate both views together - fast and punchy
            UIView.animate(
                withDuration: 0.32,
                delay: 0,
                options: [.curveEaseOut],
                animations: {
                    // Incoming: fade in + slide to center
                    targetWebView.alpha = 1
                    targetWebView.transform = .identity

                    // Outgoing: fade out + slide away
                    currentView.alpha = 0
                    currentView.transform = CGAffineTransform(translationX: isForward ? -slideOffset : slideOffset, y: 0)
                }
            ) { _ in
                // Reset outgoing view
                currentView.transform = .identity
                currentView.alpha = 1

                targetWebView.removeFromSuperview()

                self.pageController.setViewControllers(
                    [wrapperVC],
                    direction: direction,
                    animated: false
                )

                self.currentIndex = index
                self.isTransitioning = false
            }
            
        case .fade:
            // Snapshot crossfade: capture current screen as opaque image, crossfade to new screen
            // This avoids background bleed-through that occurs with alpha-based crossfades
            isTransitioning = true

            let containerView = pageController.view!

            // Get the current view
            guard let currentVC = pageController.viewControllers?.first else {
                isTransitioning = false
                return
            }
            let currentView = currentVC.view!

            // Take a snapshot of current view (fully rasterized, opaque)
            guard let snapshot = currentView.snapshotView(afterScreenUpdates: false) else {
                // Fallback: just do instant switch
                pageController.setViewControllers([wrapperVC], direction: direction, animated: false)
                currentIndex = index
                isTransitioning = false
                return
            }
            snapshot.frame = containerView.bounds

            // Add new screen underneath, fully visible
            targetWebView.translatesAutoresizingMaskIntoConstraints = true
            containerView.addSubview(targetWebView)
            targetWebView.frame = containerView.bounds
            targetWebView.alpha = 1

            // Add snapshot on top - it covers the new screen initially
            containerView.addSubview(snapshot)

            // Fade out snapshot to reveal new screen underneath
            UIView.animate(
                withDuration: 0.28,
                delay: 0,
                options: [.curveEaseInOut],
                animations: {
                    snapshot.alpha = 0
                }
            ) { [weak self] _ in
                guard let self = self else { return }

                // Clean up temporary views
                snapshot.removeFromSuperview()
                targetWebView.removeFromSuperview()

                self.pageController.setViewControllers(
                    [wrapperVC],
                    direction: direction,
                    animated: false
                )

                self.currentIndex = index
                self.isTransitioning = false
            }
        }
        
        RampKitLogger.verbose("Overlay", "onPageSelected \(index)")
    }
    
    // MARK: - Variables
    
    private func sendVariablesToWebView(at index: Int) {
        guard index >= 0, index < webViews.count else { return }
        
        let webView = webViews[index]
        let payload: [String: Any] = [
            "type": "rampkit:variables",
            "vars": sharedVariables
        ]
        
        let script = HTMLBuilder.buildDispatchScript(payload)
        webView.evaluateJavaScript(script) { _, error in
            if let error = error {
                RampKitLogger.warn("Overlay", "Failed to send vars to WebView \(index): \(error)")
            } else {
                RampKitLogger.verbose("Overlay", "sendVarsToWebView \(index)")
            }
        }
        
        // Track send time
        lastVariableSendTime[index] = Date()
    }
    
    /// Send onboarding state update to a WebView
    /// This updates the `onboarding.currentIndex`, `onboarding.progress`, etc. variables
    /// by calling `window.__rampkitUpdateOnboarding(index, screenId)`
    private func sendOnboardingStateToWebView(at index: Int) {
        guard index >= 0, index < webViews.count else { return }
        
        let webView = webViews[index]
        let screenId = screens[index].id
        let totalScreens = screens.count
        
        RampKitLogger.verbose("Overlay", "Sending onboarding state to WebView \(index): screenId=\(screenId), total=\(totalScreens)")
        
        // Call window.__rampkitUpdateOnboarding if it exists
        // Also send via postMessage for redundancy
        let script = """
        (function() {
            try {
                // Set total screens global
                window.RK_TOTAL_SCREENS = \(totalScreens);
                
                // Call the update function if it exists
                if (typeof window.__rampkitUpdateOnboarding === 'function') {
                    window.__rampkitUpdateOnboarding(\(index), '\(screenId)');
                    console.log('[RampKit] Called __rampkitUpdateOnboarding(\(index), \(screenId))');
                }
                
                // Also dispatch a message event for any listeners
                var payload = {
                    type: 'rampkit:onboarding-state',
                    currentIndex: \(index),
                    screenId: '\(screenId)',
                    totalScreens: \(totalScreens)
                };
                
                try {
                    document.dispatchEvent(new MessageEvent('message', { data: payload }));
                } catch(e) {}
                
                // Also dispatch custom event
                try {
                    document.dispatchEvent(new CustomEvent('rampkit:onboarding-state', { detail: payload }));
                } catch(e) {}
                
            } catch(e) {
                console.log('[RampKit] sendOnboardingState error:', e);
            }
        })();
        """
        
        webView.evaluateJavaScript(script) { _, error in
            if let error = error {
                RampKitLogger.warn("Overlay", "Failed to send onboarding state to WebView \(index): \(error)")
            } else {
                RampKitLogger.verbose("Overlay", "Onboarding state sent to WebView \(index)")
            }
        }
    }

    private func broadcastVariables(excluding excludedIndex: Int? = nil) {
        RampKitLogger.verbose("Overlay", "broadcastVars")

        for index in 0..<webViews.count {
            if let excludedIndex = excludedIndex, index == excludedIndex {
                continue
            }
            sendVariablesToWebView(at: index)
        }
    }

    // MARK: - Variable Set Event Debouncing

    /// Compare two Any values for equality
    private func isEqual(_ lhs: Any?, _ rhs: Any?) -> Bool {
        if lhs == nil && rhs == nil { return true }
        guard let lhs = lhs, let rhs = rhs else { return false }

        switch (lhs, rhs) {
        case (let l as String, let r as String): return l == r
        case (let l as Int, let r as Int): return l == r
        case (let l as Double, let r as Double): return l == r
        case (let l as Bool, let r as Bool): return l == r
        case (let l as NSNumber, let r as NSNumber): return l == r
        default:
            // For complex types, use string comparison as fallback
            return String(describing: lhs) == String(describing: rhs)
        }
    }

    /// Schedule a variable_set event with debouncing (fires after 1000ms idle or on blur)
    private func scheduleVariableSetEvent(variableName: String, previousValue: Any?, newValue: Any) {
        // Cancel existing timer for this variable
        let existing = pendingVariableEvents[variableName]
        existing?.timer?.invalidate()

        // Capture current screen name at time of change (not when event fires)
        let currentScreen = currentIndex >= 0 && currentIndex < screens.count ? screens[currentIndex] : nil
        let screenName = existing?.screenName ?? (currentScreen?.label ?? currentScreen?.id)

        // Schedule new timer on main thread
        let timer = Timer.scheduledTimer(withTimeInterval: variableDebounceInterval, repeats: false) { [weak self] _ in
            self?.fireVariableSetEvent(variableName: variableName)
        }

        // Keep original previousValue and screenName if updating existing pending event
        pendingVariableEvents[variableName] = (
            existing?.previousValue ?? previousValue,
            newValue,
            screenName,
            timer
        )
    }

    /// Fire the variable_set event immediately and clear pending state
    private func fireVariableSetEvent(variableName: String) {
        guard let pending = pendingVariableEvents[variableName] else { return }
        pending.timer?.invalidate()

        // Use the screen name captured when the variable was changed
        EventManager.shared.trackVariableSet(
            variableName: variableName,
            previousValue: pending.previousValue,
            newValue: pending.newValue,
            screenName: pending.screenName
        )

        pendingVariableEvents.removeValue(forKey: variableName)
    }

    /// Handle blur event from WebView input - immediately fires any pending variable_set
    func handleInputBlur(variableName: String) {
        if pendingVariableEvents[variableName] != nil {
            fireVariableSetEvent(variableName: variableName)
        }
    }

    private func mergeVariables(
        _ newVars: [String: Any],
        fromIndex: Int,
        forceImmediate: Bool = false
    ) {
        // CRITICAL: Filter out onboarding.* variables
        // These are read-only from the WebView's perspective and should only be
        // controlled by the SDK. Accepting them back creates infinite loops.
        var filteredVars: [String: Any] = [:]
        for (key, value) in newVars {
            if key.hasPrefix("onboarding.") {
                RampKitLogger.verbose("Overlay", "Ignoring read-only onboarding variable: \(key)")
                continue
            }
            filteredVars[key] = value
        }
        
        // If no valid variables remain after filtering, skip merge
        if filteredVars.isEmpty {
            return
        }
        
        if forceImmediate {
            // Active screen updates should always be applied immediately
            for (key, value) in filteredVars {
                let previousValue = sharedVariables[key]
                let valueChanged = !isEqual(previousValue, value)
                sharedVariables[key] = value

                // Schedule variable_set event if value actually changed
                if valueChanged {
                    scheduleVariableSetEvent(variableName: key, previousValue: previousValue, newValue: value)
                }
            }
        } else {
            let now = Date()
            let lastSendTime = lastVariableSendTime[fromIndex] ?? Date.distantPast
            let timeSinceSend = now.timeIntervalSince(lastSendTime)

            // Filter stale values (within 600ms window) to avoid echo loops
            if timeSinceSend < staleValueWindow {
                for (key, value) in filteredVars {
                    if sharedVariables[key] == nil {
                        // New variable, accept it
                        sharedVariables[key] = value
                        scheduleVariableSetEvent(variableName: key, previousValue: nil, newValue: value)
                    } else {
                        // Existing variable within stale window:
                        // keep current host value to avoid echo loops
                    }
                }
            } else {
                // Outside stale window, merge all
                for (key, value) in filteredVars {
                    let previousValue = sharedVariables[key]
                    let valueChanged = !isEqual(previousValue, value)
                    sharedVariables[key] = value

                    // Schedule variable_set event if value actually changed
                    if valueChanged {
                        scheduleVariableSetEvent(variableName: key, previousValue: previousValue, newValue: value)
                    }
                }
            }
        }
        
        RampKitLogger.verbose("Overlay", "received variables from page \(fromIndex)")

        // Persist variable updates to storage
        OnboardingResponseStorage.updateVariables(filteredVars)

        // Broadcast to ALL WebViews including the source
        // The source needs the full merged state for dynamic tap evaluations
        // (its local window.__rampkitVariables must have the latest values)
        // Stale value filtering prevents echo loops
        broadcastVariables()
    }
    
    // MARK: - Dismissal
    
    func dismissOverlay() {
        RampKitLogger.verbose("Overlay", "dismissOverlay called")
        UIView.animate(
            withDuration: 0.32,
            delay: 0.15,
            options: [.curveEaseOut],
            animations: { [weak self] in
                self?.view.alpha = 0
            }
        ) { [weak self] _ in
            self?.onRequestClose?()
        }
    }
}

// MARK: - UIPageViewControllerDataSource

extension RampKitOverlayController: UIPageViewControllerDataSource {
    public func pageViewController(
        _ pageViewController: UIPageViewController,
        viewControllerBefore viewController: UIViewController
    ) -> UIViewController? {
        // Disable manual swiping
        return nil
    }
    
    public func pageViewController(
        _ pageViewController: UIPageViewController,
        viewControllerAfter viewController: UIViewController
    ) -> UIViewController? {
        // Disable manual swiping
        return nil
    }
}

// MARK: - UIPageViewControllerDelegate

extension RampKitOverlayController: UIPageViewControllerDelegate {}

// MARK: - WKNavigationDelegate

extension RampKitOverlayController: WKNavigationDelegate {
    public func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        // Find index of this WebView
        guard let index = webViews.firstIndex(where: { $0 === webView }) else { return }
        
        RampKitLogger.verbose("Overlay", "WebView \(index) finished loading")
        
        // Inject no-select script after load
        webView.evaluateJavaScript(InjectedScripts.noSelect)
        
        // Send initial variables
        sendVariablesToWebView(at: index)
        
        // Send onboarding state to this screen
        sendOnboardingStateToWebView(at: index)
        
        // Fade out the curtain when first screen finishes loading
        if index == 0 && fadeCurtain.alpha == 1 {
            RampKitLogger.verbose("Overlay", "First screen ready, revealing content")

            // Ensure layout is complete before revealing to prevent "slide down" glitch
            // This forces any pending layout to complete with correct bounds
            if !hasCompletedInitialLayout {
                view.setNeedsLayout()
                view.layoutIfNeeded()
                hasCompletedInitialLayout = true
                RampKitLogger.verbose("Overlay", "Forced layout completion before reveal - bounds: \(view.bounds)")
            }

            // Remove loading placeholder immediately (overlay is already opaque)
            RampKitCore.shared.hideLoadingPlaceholder()

            UIView.animate(withDuration: 0.25, delay: 0, options: .curveEaseOut) {
                self.fadeCurtain.alpha = 0
            } completion: { _ in
                self.fadeCurtain.isHidden = true
            }
        }
    }
    
    public func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        RampKitLogger.warn("WebView", "error: \(error.localizedDescription)")
    }

    public func webView(
        _ webView: WKWebView,
        didFailProvisionalNavigation navigation: WKNavigation!,
        withError error: Error
    ) {
        RampKitLogger.warn("WebView", "provisional navigation error: \(error.localizedDescription)")
    }
}

// MARK: - Navigation Resolution

extension RampKitOverlayController {
    
    /// Resolve `__continue__` to the actual target screen ID using navigation data
    /// - Parameter fromScreenId: The current screen ID
    /// - Returns: The target screen ID, or nil if at the end of the flow
    private func resolveContinue(fromScreenId: String) -> String? {
        // If no navigation data, fall back to array order
        guard let mainFlow = navigation?.mainFlow, !mainFlow.isEmpty else {
            RampKitLogger.verbose("Overlay", "No navigation.mainFlow, using array order for __continue__")
            return nil // Will use fallback
        }

        // Check if current screen is in the main flow
        if let currentFlowIndex = mainFlow.firstIndex(of: fromScreenId) {
            // Navigate to next screen in main flow
            let nextFlowIndex = currentFlowIndex + 1
            if nextFlowIndex < mainFlow.count {
                let nextScreenId = mainFlow[nextFlowIndex]
                RampKitLogger.verbose("Overlay", "__continue__ resolved via mainFlow: \(fromScreenId) -> \(nextScreenId) (flow index \(currentFlowIndex) -> \(nextFlowIndex))")
                return nextScreenId
            } else {
                RampKitLogger.verbose("Overlay", "__continue__: at end of mainFlow (index \(currentFlowIndex))")
                return nil
            }
        }

        // Current screen is NOT in mainFlow (it's a variant screen)
        // Find the appropriate next main screen based on X position
        if let positions = navigation?.screenPositions,
           let currentPosition = positions[fromScreenId] {
            RampKitLogger.verbose("Overlay", "Current screen '\(fromScreenId)' is a variant (row: \(currentPosition.row), x: \(currentPosition.x))")
            
            // Find the main flow screen that comes AFTER this X position
            // (the screen with the smallest X that is > currentPosition.x)
            var bestCandidate: (screenId: String, x: Double)?
            
            for mainScreenId in mainFlow {
                if let mainPos = positions[mainScreenId], mainPos.x > currentPosition.x {
                    if bestCandidate == nil || mainPos.x < bestCandidate!.x {
                        bestCandidate = (mainScreenId, mainPos.x)
                    }
                }
            }
            
            if let next = bestCandidate {
                RampKitLogger.verbose("Overlay", "__continue__ from variant: \(fromScreenId) -> \(next.screenId) (next main screen at x:\(next.x))")
                return next.screenId
            } else {
                RampKitLogger.verbose("Overlay", "__continue__ from variant: no main screen to the right, end of flow")
                return nil
            }
        }

        // Position data not available for current screen, fall back to array
        RampKitLogger.verbose("Overlay", "Screen '\(fromScreenId)' not found in positions, using array fallback")
        return nil
    }
    
    /// Resolve `__goBack__` to the actual target screen ID using navigation data
    /// - Parameter fromScreenId: The current screen ID
    /// - Returns: The target screen ID, or nil if at the start of the flow
    private func resolveGoBack(fromScreenId: String) -> String? {
        // If no navigation data, fall back to array order
        guard let mainFlow = navigation?.mainFlow, !mainFlow.isEmpty else {
            RampKitLogger.verbose("Overlay", "No navigation.mainFlow, using array order for __goBack__")
            return nil // Will use fallback
        }

        // Check if current screen is in the main flow
        if let currentFlowIndex = mainFlow.firstIndex(of: fromScreenId) {
            // Navigate to previous screen in main flow
            let prevFlowIndex = currentFlowIndex - 1
            if prevFlowIndex >= 0 {
                let prevScreenId = mainFlow[prevFlowIndex]
                RampKitLogger.verbose("Overlay", "__goBack__ resolved via mainFlow: \(fromScreenId) -> \(prevScreenId) (flow index \(currentFlowIndex) -> \(prevFlowIndex))")
                return prevScreenId
            } else {
                RampKitLogger.verbose("Overlay", "__goBack__: at start of mainFlow (index \(currentFlowIndex))")
                return nil
            }
        }

        // Current screen is NOT in mainFlow (it's a variant screen)
        // Go back to the main flow screen at or before this X position
        if let positions = navigation?.screenPositions,
           let currentPosition = positions[fromScreenId] {
            RampKitLogger.verbose("Overlay", "Current screen '\(fromScreenId)' is a variant (row: \(currentPosition.row), x: \(currentPosition.x))")
            
            // Find the main flow screen that is at or before this X position
            // (the screen with the largest X that is <= currentPosition.x)
            var bestCandidate: (screenId: String, x: Double)?
            
            for mainScreenId in mainFlow {
                if let mainPos = positions[mainScreenId], mainPos.x <= currentPosition.x {
                    if bestCandidate == nil || mainPos.x > bestCandidate!.x {
                        bestCandidate = (mainScreenId, mainPos.x)
                    }
                }
            }
            
            if let prev = bestCandidate {
                RampKitLogger.verbose("Overlay", "__goBack__ from variant: \(fromScreenId) -> \(prev.screenId) (main screen at x:\(prev.x))")
                return prev.screenId
            } else {
                RampKitLogger.verbose("Overlay", "__goBack__ from variant: no main screen to the left, start of flow")
                return nil
            }
        }

        // Position data not available for current screen, fall back to array
        RampKitLogger.verbose("Overlay", "Screen '\(fromScreenId)' not found in positions, using array fallback")
        return nil
    }
    
    /// Get the screen index for a given screen ID
    private func screenIndex(for screenId: String) -> Int? {
        return screens.firstIndex(where: { $0.id == screenId })
    }
}

// MARK: - RampKitMessageHandlerDelegate

extension RampKitOverlayController: RampKitMessageHandlerDelegate {
    func handleNavigate(targetScreenId: String?, animation: String?, fromIndex: Int) {
        RampKitLogger.verbose("Overlay", "Navigate request from screen \(fromIndex) to '\(targetScreenId ?? "nil")', activeScreen: \(activeScreenIndex), isActive: \(isScreenActive(fromIndex))")

        // Only process navigation from the active screen
        guard isScreenActive(fromIndex) else {
            RampKitLogger.verbose("Overlay", "Ignoring navigate from inactive screen \(fromIndex)")
            return
        }

        guard let targetScreenId = targetScreenId else {
            RampKitLogger.verbose("Overlay", "Navigate: targetScreenId is nil")
            return
        }

        // Navigation is allowed from active screen
        let animationType: NavigationAnimation
        switch animation?.lowercased() {
        case "slide":
            animationType = .slide
        case "slidefade":
            animationType = .slideFade
        default:
            animationType = .fade
        }
        
        let currentScreenId = screens[currentIndex].id
        
        if targetScreenId == "__continue__" {
            // Try to resolve using navigation data
            if let resolvedId = resolveContinue(fromScreenId: currentScreenId),
               let targetIndex = screenIndex(for: resolvedId) {
                navigateToIndex(targetIndex, animation: animationType)
            } else {
                // Fallback to array order
                let nextIndex = currentIndex + 1
                if nextIndex < screens.count {
                    RampKitLogger.verbose("Overlay", "__continue__ fallback to array index \(nextIndex)")
                    navigateToIndex(nextIndex, animation: animationType)
                }
            }
        } else if targetScreenId == "__goBack__" {
            // Try to resolve using navigation data
            if let resolvedId = resolveGoBack(fromScreenId: currentScreenId),
               let targetIndex = screenIndex(for: resolvedId) {
                navigateToIndex(targetIndex, animation: animationType)
            } else {
                // Fallback to array order
                let prevIndex = currentIndex - 1
                if prevIndex >= 0 {
                    RampKitLogger.verbose("Overlay", "__goBack__ fallback to array index \(prevIndex)")
                    navigateToIndex(prevIndex, animation: animationType)
                }
            }
        } else {
            // Find screen by ID
            if let index = screens.firstIndex(where: { $0.id == targetScreenId }) {
                navigateToIndex(index, animation: animationType)
            }
        }
    }
    
    func handleGoBack(animation: String?, fromIndex: Int) {
        // Use handleNavigate with __goBack__ to leverage navigation resolution
        handleNavigate(targetScreenId: "__goBack__", animation: animation, fromIndex: fromIndex)
    }
    
    func handleClose(fromIndex: Int) {
        // Only process from active screen to prevent duplicate events
        guard isScreenActive(fromIndex) else {
            RampKitLogger.verbose("Overlay", "Ignoring close from inactive screen \(fromIndex)")
            return
        }

        // Track onboarding completed event - close counts as completion
        if #available(iOS 14.0, *) {
            EventManager.shared.trackOnboardingCompleted(
                trigger: "closed",
                completedSteps: fromIndex + 1,
                totalSteps: screens.count
            )
        }

        // Auto-recheck transactions after onboarding closes (catches purchases made before closing)
        if #available(iOS 15.0, *) {
            TransactionObserver.shared.recheckEntitlements()
        }

        // Close is always allowed
        dismissOverlay()
    }
    
    func handleHaptic(event: HapticEvent, fromIndex: Int) {
        // Haptics are always allowed
        HapticManager.performHaptic(event: event)
    }
    
    func handleRequestReview(fromIndex: Int) {
        RampKitLogger.verbose("Overlay", "Review request from screen \(fromIndex), activeScreen: \(activeScreenIndex), isActive: \(isScreenActive(fromIndex))")

        // Prevent duplicate review requests in the same session
        guard !hasRequestedReview else {
            RampKitLogger.verbose("Overlay", "Skipping duplicate review request (already requested)")
            return
        }

        // If screen is not active, QUEUE the action for later
        guard isScreenActive(fromIndex) else {
            RampKitLogger.verbose("Overlay", "Queuing review request from screen \(fromIndex) (will trigger when screen becomes active)")
            queueAction(for: fromIndex) { [weak self] in
                guard let self = self else { return }
                guard !self.hasRequestedReview else {
                    RampKitLogger.verbose("Overlay", "Skipping queued review request (already requested)")
                    return
                }
                self.hasRequestedReview = true
                RampKitLogger.verbose("Overlay", "Executing queued review request for screen \(fromIndex)")
                StoreReviewManager.requestReview(from: self)
            }
            return
        }

        hasRequestedReview = true
        RampKitLogger.verbose("Overlay", "Immediate review request from active screen \(fromIndex)")
        // Present review from this overlay controller so it appears on top
        StoreReviewManager.requestReview(from: self)
    }
    
    func handleRequestNotificationPermission(options: NotificationPermissionOptions, fromIndex: Int) {
        RampKitLogger.verbose("Overlay", "Notification request from screen \(fromIndex), activeScreen: \(activeScreenIndex), isActive: \(isScreenActive(fromIndex))")

        // If screen is not active, QUEUE the action for later
        guard isScreenActive(fromIndex) else {
            RampKitLogger.verbose("Overlay", "Queuing notification request from screen \(fromIndex) (will trigger when screen becomes active)")
            queueAction(for: fromIndex) { [weak self] in
                RampKitLogger.verbose("Overlay", "Executing queued notification request for screen \(fromIndex)")
                self?.executeNotificationPermissionRequest(options: options)
            }
            return
        }

        RampKitLogger.verbose("Overlay", "Immediate notification request from active screen \(fromIndex)")
        executeNotificationPermissionRequest(options: options)
    }

    private func executeNotificationPermissionRequest(options: NotificationPermissionOptions) {
        RampKitLogger.verbose("Overlay", "Executing notification permission request - allowAlert: \(options.allowAlert), allowBadge: \(options.allowBadge), allowSound: \(options.allowSound)")

        // CRITICAL: Only request if not already determined
        NotificationManager.getNotificationPermissionStatus { [weak self] currentStatus in
            RampKitLogger.verbose("Overlay", "Current permission status: \(currentStatus.status)")

            if currentStatus.status == "undetermined" {
                RampKitLogger.verbose("Overlay", "Requesting permission (undetermined)")
                NotificationManager.requestNotificationPermission(options: options) { [weak self] result in
                    RampKitLogger.verbose("Overlay", "Notification permission result: \(result.status)")
                    // Add to shared variables
                    self?.sharedVariables["notificationsPermission"] = [
                        "granted": result.granted,
                        "status": result.status,
                        "canAskAgain": result.canAskAgain
                    ]
                    
                    // Broadcast to all WebViews
                    self?.broadcastVariables()
                }
            } else {
                RampKitLogger.verbose("Overlay", "Permission already determined (\(currentStatus.status)), not requesting again")
                // Just update variables with current status
                self?.sharedVariables["notificationsPermission"] = [
                    "granted": currentStatus.granted,
                    "status": currentStatus.status,
                    "canAskAgain": currentStatus.canAskAgain
                ]
                self?.broadcastVariables()
            }
        }
    }
    
    func handleOnboardingFinished(payload: Any?, fromIndex: Int) {
        // Only process from active screen to prevent duplicate events
        guard isScreenActive(fromIndex) else {
            RampKitLogger.verbose("Overlay", "Ignoring onboarding-finished from inactive screen \(fromIndex)")
            return
        }

        // Track onboarding completed event
        if #available(iOS 14.0, *) {
            EventManager.shared.trackOnboardingCompleted(
                trigger: "finished",
                completedSteps: fromIndex + 1,
                totalSteps: screens.count
            )
        }

        // Auto-recheck transactions after onboarding finishes (catches purchases made during onboarding)
        if #available(iOS 15.0, *) {
            TransactionObserver.shared.recheckEntitlements()
        }

        // These actions are always allowed
        do {
            try onOnboardingFinished?(payload)
        } catch {
            // Silently ignore callback errors
        }
        dismissOverlay()
    }
    
    func handleShowPaywall(payload: Any?, fromIndex: Int) {
        // Only process from active screen to prevent duplicate events
        guard isScreenActive(fromIndex) else {
            RampKitLogger.verbose("Overlay", "Ignoring show-paywall from inactive screen \(fromIndex)")
            return
        }

        // Track onboarding completed event - showing paywall counts as completion
        if #available(iOS 14.0, *) {
            EventManager.shared.trackOnboardingCompleted(
                trigger: "paywall_shown",
                completedSteps: fromIndex + 1,
                totalSteps: screens.count
            )
        }

        // These actions are always allowed
        do {
            try onShowPaywall?(payload)
        } catch {
            // Silently ignore callback errors
        }
    }
    
    func handleVariablesUpdate(vars: [String: Any], fromIndex: Int) {
        // For the ACTIVE screen, always apply updates immediately so UI reacts instantly.
        // Background screens still benefit from stale-value filtering to prevent echo loops.
        let isActiveSource = (fromIndex == activeScreenIndex)
        mergeVariables(vars, fromIndex: fromIndex, forceImmediate: isActiveSource)
        
        // NOTE: Do NOT send vars back to source page - it already has them
        // and would just echo them back again, creating a ping-pong loop
    }
    
    func handleRequestVars(forIndex: Int) {
        sendVariablesToWebView(at: forIndex)
    }
    
    func getScreenName(forIndex index: Int) -> String? {
        guard index >= 0 && index < screens.count else { return nil }
        return screens[index].label ?? screens[index].id
    }
}

// MARK: - WebView Message Proxy

/// Proxy to forward messages with index context
private class WebViewMessageProxy: NSObject, WKScriptMessageHandler {
    weak var handler: RampKitOverlayController?
    let index: Int
    
    init(handler: RampKitOverlayController, index: Int) {
        self.handler = handler
        self.index = index
    }
    
    func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        RampKitLogger.verbose("MessageProxy", "Message received from WebView[\(index)]: \(message.body)")
        handler?.messageHandler.handleMessage(body: message.body, fromIndex: index)
    }
}

// MARK: - WebView Wrapper Controller

/// Simple wrapper view controller for page controller
private class WebViewWrapperController: UIViewController {
    let webView: CustomWebView

    init(webView: CustomWebView) {
        self.webView = webView
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        view.isUserInteractionEnabled = true
        view.insetsLayoutMarginsFromSafeArea = false  // Ignore safe areas
        view.addSubview(webView)

        // Use Auto Layout instead of frame-based layout
        // This ensures the WebView gets correct size BEFORE content renders,
        // preventing the "slide down" glitch during modal presentation
        webView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            webView.topAnchor.constraint(equalTo: view.topAnchor),
            webView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            webView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }
}
#endif

