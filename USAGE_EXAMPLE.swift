import UIKit
import RampKit

// MARK: - Example 1: Basic Integration in AppDelegate

@main
class AppDelegate: UIResponder, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        
        // Initialize RampKit
        Task {
            await RampKit.initialize(config: RampKitConfig(
                appId: "your-app-id-here",
                apiKey: "your-api-key-here", // optional
                environment: "production",
                autoShowOnboarding: true,
                onOnboardingFinished: { payload in
                    print("✅ Onboarding completed!")
                    if let data = payload as? [String: Any] {
                        print("Payload:", data)
                    }
                },
                onShowPaywall: { payload in
                    print("💰 Show paywall requested")
                    // Present your paywall here
                }
            ))
        }
        
        return true
    }
}

// MARK: - Example 2: Manual Onboarding Display

class OnboardingViewController: UIViewController {
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        // Show onboarding when view loads
        showOnboardingFlow()
    }
    
    private func showOnboardingFlow() {
        // Option 1: Simple show
        RampKit.showOnboarding()
        
        // Option 2: With custom paywall handler
        RampKit.showOnboarding(options: ShowOnboardingOptions(
            onShowPaywall: { [weak self] payload in
                self?.presentPaywall(payload: payload)
            }
        ))
    }
    
    private func presentPaywall(payload: Any?) {
        // Present your paywall UI
        print("Presenting paywall with payload:", payload ?? "none")
    }
}

// MARK: - Example 3: Getting User ID

class AnalyticsManager {
    
    func trackUserEvent() async {
        // Get stable user ID for analytics
        let userId = await getRampKitUserId()
        print("Tracking event for user:", userId)
        
        // Send to your analytics service
        // Analytics.track("event_name", userId: userId)
    }
    
    func getUserFromRampKit() {
        // Or get from RampKit singleton
        if let userId = RampKit.getUserId() {
            print("User ID:", userId)
        }
    }
}

// MARK: - Example 4: Accessing Onboarding Data

class DebugViewController: UIViewController {
    
    func printOnboardingInfo() {
        guard let data = RampKit.getOnboardingData() else {
            print("No onboarding data loaded")
            return
        }
        
        print("Onboarding ID:", data.onboardingId)
        print("Number of screens:", data.screens.count)
        print("Screen IDs:", data.screens.map { $0.id })
        
        if let variables = data.variables?.state {
            print("Variables:", variables.map { "\($0.name): \($0.initialValue)" })
        }
        
        if let scripts = data.requiredScripts {
            print("Required scripts:", scripts)
        }
    }
}

// MARK: - Example 5: SwiftUI Integration

import SwiftUI

struct ContentView: View {
    @State private var showOnboarding = false
    
    var body: some View {
        VStack {
            Button("Show Onboarding") {
                RampKit.showOnboarding()
            }
            
            Button("Close Onboarding") {
                RampKit.closeOnboarding()
            }
        }
        .task {
            // Initialize RampKit when view appears
            await RampKit.initialize(config: RampKitConfig(
                appId: "your-app-id",
                onOnboardingFinished: { _ in
                    print("SwiftUI: Onboarding finished")
                }
            ))
        }
    }
}

// MARK: - Example 6: Custom WebView HTML Integration

/*
In your onboarding HTML/JavaScript, use these message patterns:

// Navigate to next screen
window.webkit.messageHandlers.rampkit.postMessage({
  type: "rampkit:continue",
  animation: "fade"
});

// Trigger haptic feedback
window.webkit.messageHandlers.rampkit.postMessage({
  type: "rampkit:haptic",
  hapticType: "impact",
  impactStyle: "Medium"
});

// Request notification permission
window.webkit.messageHandlers.rampkit.postMessage({
  type: "rampkit:request-notification-permission",
  ios: {
    allowAlert: true,
    allowBadge: true,
    allowSound: true
  }
});

// Update shared variables
window.webkit.messageHandlers.rampkit.postMessage({
  type: "rampkit:variables",
  vars: {
    userName: "John Doe",
    hasCompletedStep1: true
  }
});

// Complete onboarding
window.webkit.messageHandlers.rampkit.postMessage({
  type: "rampkit:onboarding-finished",
  payload: {
    completed: true,
    timestamp: Date.now()
  }
});

// Show paywall
window.webkit.messageHandlers.rampkit.postMessage({
  type: "rampkit:show-paywall",
  payload: {
    source: "onboarding",
    trigger: "step3"
  }
});

// Access variables in WebView
const userName = window.__rampkitVariables.userName;

// Listen for variable updates
document.addEventListener('message', (event) => {
  if (event.data.type === 'rampkit:variables') {
    console.log('Variables updated:', event.data.vars);
  }
});
*/

// MARK: - Example 7: Testing with Mock Data

class TestingHelpers {
    
    func initializeWithTestData() async {
        // When using customOnboardingURL, the manifest fetch is skipped
        // and the onboarding JSON is loaded directly from the URL
        await RampKit.initialize(config: RampKitConfig(
            appId: "test-app-id",
            apiKey: "test-key",
            environment: "staging",
            customOnboardingURL: "https://your-cdn.com/test-onboarding.json",
            testMode: true,
            onOnboardingFinished: { payload in
                print("TEST: Onboarding finished", payload ?? "")
            }
        ))
    }
}

// MARK: - Example 8: Error Handling

class RobustIntegration {
    
    func safeInitialization() async {
        do {
            await RampKit.initialize(config: RampKitConfig(
                appId: "your-app-id",
                onOnboardingFinished: { payload in
                    // This callback is wrapped in try-catch by SDK
                    // But you can add your own error handling
                    if let error = payload as? Error {
                        print("Error:", error)
                    }
                }
            ))
            
            print("RampKit initialized successfully")
            
        } catch {
            // SDK never throws, but good practice
            print("Unexpected error:", error)
        }
    }
    
    func checkDataAvailability() {
        if let data = RampKit.getOnboardingData() {
            // Data available, show onboarding
            RampKit.showOnboarding()
        } else {
            // Fallback to default onboarding or skip
            print("No onboarding data, using fallback")
            showDefaultOnboarding()
        }
    }
    
    func showDefaultOnboarding() {
        // Your fallback onboarding implementation
    }
}

// MARK: - Example 9: Advanced Callbacks

class AdvancedCallbacks {
    
    func setupWithDetailedCallbacks() async {
        await RampKit.initialize(config: RampKitConfig(
            appId: "your-app-id",
            onOnboardingFinished: { [weak self] payload in
                guard let self = self else { return }
                
                // Parse payload
                if let dict = payload as? [String: Any] {
                    let completed = dict["completed"] as? Bool ?? false
                    let userId = dict["userId"] as? String
                    
                    if completed {
                        self.handleOnboardingCompletion(userId: userId)
                    }
                }
            },
            onShowPaywall: { [weak self] payload in
                guard let self = self else { return }
                
                // Parse trigger information
                if let dict = payload as? [String: Any] {
                    let source = dict["source"] as? String ?? "unknown"
                    let trigger = dict["trigger"] as? String
                    
                    self.presentPaywall(source: source, trigger: trigger)
                }
            }
        ))
    }
    
    func handleOnboardingCompletion(userId: String?) {
        print("User completed onboarding:", userId ?? "unknown")
        
        // Update user defaults
        UserDefaults.standard.set(true, forKey: "has_completed_onboarding")
        
        // Track analytics
        // Analytics.track("onboarding_completed", userId: userId)
        
        // Navigate to main app
        navigateToMainScreen()
    }
    
    func presentPaywall(source: String, trigger: String?) {
        print("Presenting paywall from:", source, "trigger:", trigger ?? "none")
        
        // Present your paywall with context
        let paywallVC = PaywallViewController()
        paywallVC.source = source
        paywallVC.trigger = trigger
        
        // Present modally
        if let topVC = getTopViewController() {
            topVC.present(paywallVC, animated: true)
        }
    }
    
    func navigateToMainScreen() {
        // Navigate to your main app screen
    }
    
    func getTopViewController() -> UIViewController? {
        guard let window = UIApplication.shared.windows.first,
              let rootVC = window.rootViewController else {
            return nil
        }
        
        var topVC = rootVC
        while let presented = topVC.presentedViewController {
            topVC = presented
        }
        return topVC
    }
}

// Placeholder classes for compilation
class PaywallViewController: UIViewController {
    var source: String?
    var trigger: String?
}


