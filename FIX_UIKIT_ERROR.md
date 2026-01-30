# Fix for "No such module UIKit" Error

## Problem
Getting "No such module UIKit" error when building the RampKit iOS SDK, even after cleaning.

## Root Cause
The build system was trying to compile for non-iOS platforms (macOS, etc.) where UIKit is not available. Swift Package Manager sometimes defaults to macOS when building.

## Solution Applied

### 1. Downgraded Swift Tools Version
Changed from Swift 6.2 (too new) to Swift 5.9 (stable):

```swift
// Before:
// swift-tools-version: 6.2

// After:
// swift-tools-version: 5.9
```

### 2. Added Conditional Compilation
Added platform checks to all files using UIKit and WebKit:

#### Files Updated:

**HapticManager.swift:**
```swift
import Foundation
#if canImport(UIKit)
import UIKit
#endif

enum HapticManager {
    static func performHaptic(event: HapticEvent) {
        #if os(iOS)
        // ... implementation
        #endif
    }
    
    #if os(iOS)
    // All helper methods wrapped
    #endif
}
```

**StoreReviewManager.swift:**
```swift
import Foundation
#if canImport(UIKit)
import UIKit
#endif
#if canImport(StoreKit)
import StoreKit
#endif

enum StoreReviewManager {
    static func requestReview() {
        #if os(iOS)
        // ... implementation
        #endif
    }
}
```

**RampKitCore.swift:**
```swift
import Foundation
#if canImport(UIKit)
import UIKit
#endif

// ... in showOnboarding():
#if os(iOS)
if let rootVC = UIApplication.shared.windows.first?.rootViewController {
    // ... presentation code
}
#endif
```

**RampKitOverlayController.swift:**
```swift
import Foundation
#if canImport(UIKit)
import UIKit
#endif
#if canImport(WebKit)
import WebKit
#endif

#if os(iOS)
public class RampKitOverlayController: UIViewController {
    // ... entire class
}
#endif
```

**MessageHandler.swift:**
```swift
import Foundation
#if canImport(WebKit)
import WebKit
#endif
```

### 3. Updated Package.swift
Added explicit Swift language version and settings:

```swift
let package = Package(
    name: "RampKit",
    platforms: [
        .iOS(.v14)  // Explicitly iOS only
    ],
    products: [
        .library(name: "RampKit", targets: ["RampKit"])
    ],
    targets: [
        .target(
            name: "RampKit",
            path: "Sources/RampKit",
            swiftSettings: [
                .define("RAMPKIT_IOS")
            ]
        ),
    ],
    swiftLanguageVersions: [.v5]
)
```

## How to Verify the Fix

### Option 1: Using Xcode
1. Open the package in Xcode:
   ```bash
   cd /Users/berkeicel/Desktop/ICELPROJECTS/rampkit-ios
   open Package.swift
   ```

2. Select the correct scheme:
   - In Xcode, select **My Mac (Designed for iPhone)** or an **iPhone simulator**
   - Do NOT select "My Mac" (macOS destination)

3. Clean and build:
   - Press `⌘⇧K` (Product → Clean Build Folder)
   - Press `⌘B` (Product → Build)

### Option 2: Command Line
```bash
cd /Users/berkeicel/Desktop/ICELPROJECTS/rampkit-ios
swift package clean
swift build -c release --destination generic/platform=iOS
```

### Option 3: Xcode Project
If building from an Xcode project that includes this package:
1. Ensure your project's **Deployment Target** is iOS 14.0+
2. Select an **iOS device or simulator** as the build destination
3. Clean derived data: `⌘⇧K`
4. Build: `⌘B`

## Key Points

### Why This Happened
- Swift Package Manager can try to build for macOS by default
- UIKit is iOS-specific and not available on macOS
- Without conditional compilation, the build fails on non-iOS platforms

### What the Fix Does
- `#if canImport(UIKit)` - Only import if UIKit is available
- `#if os(iOS)` - Only compile code when building for iOS
- This allows the package to be more robust and fail gracefully

### Benefits
- ✅ Builds successfully for iOS
- ✅ Gracefully handles non-iOS platforms
- ✅ No compilation errors
- ✅ Better cross-platform compatibility
- ✅ Future-proof for potential macOS Catalyst support

## Testing Checklist

After applying the fix, verify:
- [ ] No "No such module UIKit" errors
- [ ] Package builds successfully
- [ ] Can import RampKit in iOS project
- [ ] All features work as expected
- [ ] Linter shows no errors

## Still Having Issues?

If you're still getting the error after these fixes:

### Check Your Build Destination
Make sure you're building for iOS, not macOS:
```bash
# In Xcode
Top toolbar → Select an iPhone/iPad simulator or device

# Command line
swift build --destination generic/platform=iOS
```

### Clear All Caches
```bash
# Clear Swift PM cache
rm -rf ~/Library/Caches/org.swift.swiftpm
rm -rf .build
rm -rf .swiftpm

# In Xcode
Product → Clean Build Folder (⌘⇧K)
```

### Verify Xcode Command Line Tools
```bash
xcode-select --print-path
# Should show: /Applications/Xcode.app/Contents/Developer

# If not, set it:
sudo xcode-select --switch /Applications/Xcode.app/Contents/Developer
```

### Check Minimum Versions
- **Xcode:** 14.0+
- **macOS:** 12.0+ (for development)
- **Swift:** 5.9+
- **iOS Deployment Target:** 14.0+

## Additional Fixes Applied

### Fix 1: HTMLBuilder - Tuple Hashable Error
**Error:** `Type '(origin: String, host: String)' cannot conform to 'Hashable'`

**Solution:** Changed from using `Set` with tuples to using a `Dictionary` for deduplication:

```swift
// Before: Set with tuple (doesn't work - tuples aren't Hashable by default)
let origins = Set(scripts.compactMap { ... -> (origin: String, host: String)? })

// After: Dictionary for deduplication
var originsByHost: [String: String] = [:]
for urlString in scripts {
    guard let url = URL(string: urlString),
          let host = url.host else { continue }
    let scheme = url.scheme ?? "https"
    let origin = "\(scheme)://\(host)"
    originsByHost[host] = origin
}
```

### Fix 2: RampKitCore - URLSession iOS 14 Compatibility
**Error:** `'data(from:delegate:)' is only available in macOS 12.0 or newer`

**Cause:** The modern async/await `URLSession.shared.data(from:)` API is only available in iOS 15.0+, but we're targeting iOS 14.0+.

**Solution:** Added a backwards-compatible wrapper using availability checks and continuations:

```swift
/// Fetch data from URL (iOS 14 compatible)
private func fetchData(from url: URL) async throws -> Data {
    if #available(iOS 15.0, *) {
        // Use modern async/await API
        let (data, _) = try await URLSession.shared.data(from: url)
        return data
    } else {
        // Use completion handler API for iOS 14
        return try await withCheckedThrowingContinuation { continuation in
            let task = URLSession.shared.dataTask(with: url) { data, response, error in
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
}
```

This allows the SDK to use async/await syntax while maintaining iOS 14 compatibility.

### Fix 3: RampKitCore - RampKitOverlayController Not Found
**Error:** `Cannot find type 'RampKitOverlayController' in scope`

**Cause:** `RampKitOverlayController` is wrapped in `#if os(iOS)` so it doesn't exist when building for non-iOS platforms.

**Solution:** Wrapped all references to `RampKitOverlayController` in `#if os(iOS)`:

```swift
// Wrapped property
#if os(iOS)
private weak var currentOverlay: RampKitOverlayController?
#endif

// Wrapped entire showOnboarding method
public func showOnboarding(options: ShowOnboardingOptions? = nil) {
    #if os(iOS)
    // ... entire implementation
    #endif
}

// Wrapped closeOnboarding
public func closeOnboarding() {
    #if os(iOS)
    currentOverlay?.dismissOverlay()
    #endif
}

// Wrapped helper method
private func handleOverlayClose() {
    #if os(iOS)
    currentOverlay = nil
    #endif
}
```

## Result

✅ **Package now builds successfully with zero errors!**

All UIKit-dependent code is properly wrapped in platform checks, ensuring the SDK only compiles iOS-specific code when building for iOS targets.

### Verification:
- ✅ No "No such module UIKit" errors
- ✅ No Hashable tuple errors
- ✅ No missing type errors
- ✅ No iOS availability errors
- ✅ iOS 14.0+ fully supported
- ✅ Zero linter errors
- ✅ All code properly platform-guarded

---

**Date Fixed:** November 27, 2025  
**Status:** ✅ Complete - All Errors Resolved

