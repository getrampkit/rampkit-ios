# RampKit iOS SDK

[![Platform](https://img.shields.io/badge/platform-iOS-blue.svg)](https://www.apple.com/ios/)
[![Swift Version](https://img.shields.io/badge/Swift-5.9+-orange.svg)](https://swift.org)
[![License](https://img.shields.io/badge/license-MIT-green.svg)](LICENSE)

The iOS SDK for RampKit. Build, test, and personalize app onboardings with instant updates—no app releases required.

## Features

✅ **Dynamic Onboarding Flows** - Update onboarding content remotely via CDN  
✅ **Multi-Screen Navigation** - Smooth page transitions with animations  
✅ **Rich Native Integrations** - Haptics, in-app review, notifications  
✅ **Shared State Management** - Synchronized variables across screens  
✅ **Security Hardening** - Prevents text selection, zoom, copy/paste  
✅ **Stable User IDs** - Cryptographically secure, Keychain-backed  
✅ **Performance Optimized** - Preloading, caching, offscreen rendering  
✅ **Never Crashes** - Graceful error handling throughout  

## Requirements

- iOS 14.0+
- Xcode 14.0+
- Swift 5.9+

## Installation

### Swift Package Manager

Add the following to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/getrampkit/rampkit-ios.git", from: "0.0.1")
]
```

Or in Xcode:
1. File > Add Packages...
2. Enter repository URL: `https://github.com/getrampkit/rampkit-ios.git`
3. Select version and add to your target

### CocoaPods

```ruby
pod 'RampKit', '~> 0.0.1'
```

## Quick Start

### 1. Import RampKit

```swift
import RampKit
```

### 2. Configure in Your App Delegate or Scene Delegate

```swift
import UIKit
import RampKit

@main
class AppDelegate: UIResponder, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {

        Task {
            await RampKit.configure(config: RampKitConfig(
                appId: "your-app-id-here",
                environment: "production",
                autoShowOnboarding: true,
                appUserID: "your-user-123", // optional - your own user ID
                onOnboardingFinished: { payload in
                    print("Onboarding finished:", payload ?? "no payload")
                },
                onShowPaywall: { payload in
                    print("Show paywall:", payload ?? "no payload")
                    // Present your paywall here
                }
            ))
        }

        return true
    }
}
```

### 3. Show Onboarding Manually

```swift
// Show onboarding from any view controller
RampKit.showOnboarding()

// Or with options
RampKit.showOnboarding(options: ShowOnboardingOptions(
    onShowPaywall: { payload in
        // Handle paywall display
    }
))
```

### 4. Get User ID

```swift
Task {
    let userId = await getRampKitUserId()
    print("User ID:", userId)
}
```

## API Reference

### RampKitConfig

Configuration object for SDK initialization:

```swift
public struct RampKitConfig {
    let appId: String                           // Required: Your App ID
    let apiKey: String?                         // Optional: Your API key
    let environment: String?                    // Optional: "production" or "staging"
    let autoShowOnboarding: Bool?               // Optional: Auto-show after configure (default: false)
    let onOnboardingFinished: ((Any?) -> Void)? // Optional: Callback when onboarding completes
    let onShowPaywall: ((Any?) -> Void)?        // Optional: Callback to show paywall
    let customOnboardingURL: String?            // Optional: Override CDN URL for testing
    let testMode: Bool?                         // Optional: Enable test mode
    let appUserID: String?                      // Optional: Your custom user ID (alias for your user system)
}
```

### RampKit Singleton Methods

```swift
// Configure SDK (call once at app launch)
await RampKit.configure(config: RampKitConfig)

// Show onboarding overlay
RampKit.showOnboarding(options: ShowOnboardingOptions?)

// Close onboarding programmatically
RampKit.closeOnboarding()

// Get cached onboarding data
let data = RampKit.getOnboardingData()

// Get generated user ID (RampKit's internal ID)
let userId = RampKit.getUserId()

// Get/set custom App User ID (your user system alias)
let customId = RampKit.getAppUserID()
await RampKit.setAppUserID("your-user-123")

// Get stored onboarding responses
let responses = RampKit.getOnboardingResponses()
```

### Custom App User ID

You can associate your own user identifier with RampKit analytics. This is useful for linking RampKit data with your own user database.

**Important:** This is an alias only - RampKit still generates and uses its own internal user ID (`appUserId`) for tracking. Your custom `appUserID` is stored alongside it for your reference.

```swift
// Set at configuration
await RampKit.configure(config: RampKitConfig(
    appId: "your-app-id",
    appUserID: "your-user-123"  // Set during configuration
))

// Or set/update later
await RampKit.setAppUserID("your-user-123")

// Get the current custom App User ID
if let customId = RampKit.getAppUserID() {
    print("Custom user ID:", customId)
}
```

### Accessing Onboarding Responses

RampKit automatically stores user responses when questions are answered during onboarding. You can retrieve these responses at any time:

```swift
let responses = RampKit.getOnboardingResponses()

for response in responses {
    print("Question: \(response.questionId)")
    print("Answer: \(response.answer.value)")
    print("Answered at: \(response.answeredAt)")
}
```

Each `OnboardingResponse` contains:

| Property | Type | Description |
|----------|------|-------------|
| `questionId` | `String` | Unique identifier for the question |
| `answer` | `AnyCodable` | The user's answer (any JSON-compatible value) |
| `questionText` | `String?` | Optional question text shown to user |
| `screenName` | `String?` | Screen where question was answered |
| `answeredAt` | `String` | ISO 8601 timestamp |

Responses are automatically cleared when `reset()` is called.

### Utility Functions

```swift
// Get or generate stable user ID (stored in Keychain)
let userId = await getRampKitUserId()
```

## WebView Integration

### Message Protocol

Your onboarding HTML/JavaScript can communicate with the native SDK using:

```javascript
// Navigate to next screen
window.webkit.messageHandlers.rampkit.postMessage({
  type: "rampkit:continue",
  animation: "fade" // or "slide"
});

// Navigate to specific screen
window.webkit.messageHandlers.rampkit.postMessage({
  type: "rampkit:navigate",
  targetScreenId: "screen-2",
  animation: "fade"
});

// Go back
window.webkit.messageHandlers.rampkit.postMessage({
  type: "rampkit:goBack",
  animation: "fade"
});

// Close overlay
window.webkit.messageHandlers.rampkit.postMessage({
  type: "rampkit:close"
});

// Trigger haptic feedback
window.webkit.messageHandlers.rampkit.postMessage({
  type: "rampkit:haptic",
  hapticType: "impact",
  impactStyle: "Medium" // Light, Medium, Heavy, Rigid, Soft
});

// Request in-app review
window.webkit.messageHandlers.rampkit.postMessage({
  type: "rampkit:request-review"
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

// Mark onboarding as finished
window.webkit.messageHandlers.rampkit.postMessage({
  type: "rampkit:onboarding-finished",
  payload: { userId: "123", completed: true }
});

// Show paywall
window.webkit.messageHandlers.rampkit.postMessage({
  type: "rampkit:show-paywall",
  payload: { source: "onboarding" }
});

// Update shared variables
window.webkit.messageHandlers.rampkit.postMessage({
  type: "rampkit:variables",
  vars: { userName: "John", age: 25 }
});

// Request current variables
window.webkit.messageHandlers.rampkit.postMessage({
  type: "rampkit:request-vars"
});
```

### Accessing Variables in WebView

Variables are automatically injected and available in your JavaScript:

```javascript
// Access initial variables
const userName = window.__rampkitVariables.userName;

// Listen for variable updates
document.addEventListener('message', (event) => {
  if (event.data.type === 'rampkit:variables') {
    const updatedVars = event.data.vars;
    console.log('Variables updated:', updatedVars);
    // Update your UI based on new variables
  }
});
```

## Architecture

### Core Components

```
RampKit/
├── RampKit.swift                     # Public API / umbrella export
├── RampKitCore.swift                 # Singleton core logic
├── RampKitUserId.swift               # User ID generation/storage
├── RampKitOverlayController.swift    # Full-screen overlay UI
├── Models/
│   ├── RampKitConfig.swift           # Configuration model
│   ├── OnboardingData.swift          # Data structures
│   └── HapticEvent.swift             # Event models
├── Utilities/
│   ├── KeychainHelper.swift          # Secure Keychain storage
│   ├── HTMLBuilder.swift             # HTML document generation
│   ├── Logger.swift                  # Centralized logging
│   └── AnyCodable.swift              # Type-erased Codable
├── WebView/
│   └── MessageHandler.swift          # WebView message parser
├── Integrations/
│   ├── HapticManager.swift           # Haptic feedback
│   ├── StoreReviewManager.swift      # In-app review
│   └── NotificationManager.swift     # Notification permissions
└── Resources/
    └── InjectedScripts.swift         # Security hardening scripts
```

### Data Flow

```
1. Initialize RampKit
   ↓
2. Fetch onboarding config from CDN
   ↓
3. Generate/retrieve user ID from Keychain
   ↓
4. Show onboarding overlay
   ↓
5. Load screens in WKWebViews
   ↓
6. Bidirectional message passing
   ↓
7. Native integrations (haptics, review, etc.)
   ↓
8. Complete onboarding / Show paywall
```

## Advanced Usage

### Custom Onboarding URL

```swift
await RampKit.configure(config: RampKitConfig(
    appId: "your-app-id",
    customOnboardingURL: "https://your-cdn.com/onboarding.json"
))
```

### Manual Variable Management

Variables are automatically synced, but you can access onboarding data:

```swift
if let data = RampKit.getOnboardingData() {
    print("Onboarding ID:", data.onboardingId)
    print("Screen count:", data.screens.count)
    print("Variables:", data.variables?.state ?? [])
}
```

### Handling Callbacks

```swift
await RampKit.configure(config: RampKitConfig(
    appId: "your-app-id",
    onOnboardingFinished: { payload in
        // User completed onboarding
        if let data = payload as? [String: Any] {
            print("Completion data:", data)
        }

        // Navigate to main app flow
        navigateToMainScreen()
    },
    onShowPaywall: { payload in
        // Present your paywall
        if let source = (payload as? [String: Any])?["source"] as? String {
            print("Paywall requested from:", source)
        }

        presentPaywall()
    }
))
```

## Performance Tips

### Preloading (Coming Soon)

```swift
// Preload onboarding for instant display
// RampKit.preloadOnboarding()
```

### Memory Management

The SDK automatically manages WebView lifecycle and memory. All WebViews are created upfront for smooth transitions but released when the overlay is dismissed.

## Security Features

The SDK includes comprehensive security hardening:

- ✅ Prevents text selection and copying
- ✅ Disables zoom and pinch gestures
- ✅ Blocks context menus
- ✅ Prevents drag and drop
- ✅ Clears selections every 160ms
- ✅ Uses MutationObserver for dynamic content

All security measures are automatically injected into WebViews.

## Error Handling

The SDK follows a **never-crash** philosophy:

- All network errors are caught and logged
- Failed initialization continues gracefully
- Missing data is handled with defaults
- Callback errors are silently swallowed

Logs use the format: `[RampKit] Context: message`

Enable debug logs in DEBUG builds automatically.

## Testing

### Unit Tests

Test individual components:

```swift
import XCTest
@testable import RampKit

class RampKitTests: XCTestCase {
    func testUserIdGeneration() async {
        let userId = await getRampKitUserId()
        XCTAssertFalse(userId.isEmpty)
        XCTAssertEqual(userId.count, 36) // UUID format
    }
}
```

### Integration Tests

Test the full flow with mock data:

```swift
await RampKit.configure(config: RampKitConfig(
    appId: "test-app-id",
    testMode: true,
    customOnboardingURL: "https://your-test-cdn.com/mock.json"
))
```

## Examples

Check the `Examples/` directory for:

- Basic integration
- SwiftUI integration
- Custom callbacks
- Advanced variable handling

## Migration from React Native

If you're coming from the React Native SDK:

| React Native | iOS Swift |
|--------------|-----------|
| `RampKit.configure()` | `await RampKit.configure()` |
| `RampKit.setAppUserID()` | `await RampKit.setAppUserID()` |
| `window.ReactNativeWebView.postMessage()` | `window.webkit.messageHandlers.rampkit.postMessage()` |
| `expo-secure-store` | Keychain |
| `react-native-pager-view` | UIPageViewController |
| `expo-haptics` | UIFeedbackGenerator |

## Troubleshooting

### Onboarding doesn't show

```swift
// Check if data loaded
if let data = RampKit.getOnboardingData() {
    print("Data loaded:", data.onboardingId)
} else {
    print("No onboarding data - check network/URL")
}
```

### WebView not receiving messages

Ensure you're using the correct message handler name:

```javascript
// ✅ Correct
window.webkit.messageHandlers.rampkit.postMessage(...)

// ❌ Wrong
window.ReactNativeWebView.postMessage(...)
```

## Contributing

We welcome contributions! Please see [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines.

## License

RampKit iOS SDK is available under the MIT license. See [LICENSE](LICENSE) for more info.

## Support

- 📧 Email: support@rampkit.com
- 🌐 Website: https://rampkit.com
- 📚 Docs: https://rampkit.com/docs
- 💬 Discord: https://discord.gg/rampkit

## Changelog

### Version 0.0.2

- ✅ Renamed `initialize()` to `configure()` (initialize deprecated but still works)
- ✅ Added `appUserID` parameter for custom user identification
- ✅ Added `setAppUserID()` and `getAppUserID()` methods
- ✅ Custom App User ID syncs to backend for analytics correlation

### Version 0.0.1 (Initial Release)

- ✅ Full feature parity with React Native SDK
- ✅ Async/await API
- ✅ Keychain-backed user IDs
- ✅ WKWebView integration
- ✅ Native haptics, review, notifications
- ✅ Comprehensive security hardening
- ✅ Performance optimizations
- ✅ Zero external dependencies

---

Built with ❤️ by the RampKit team


