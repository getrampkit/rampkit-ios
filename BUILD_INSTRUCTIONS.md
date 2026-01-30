# RampKit iOS SDK - Build Instructions

## ⚠️ Important: Build Target Selection

The RampKit SDK is **iOS-only**. If you're getting availability errors like:

```
'data(from:delegate:)' is only available in macOS 12.0 or newer
```

This means you're building for the **wrong platform** (macOS instead of iOS).

---

## ✅ Correct Build Setup

### Option 1: Xcode (Recommended)

1. **Open the package:**
   ```bash
   cd /Users/berkeicel/Desktop/ICELPROJECTS/rampkit-ios
   open Package.swift
   ```

2. **Select iOS destination:**
   - Top toolbar in Xcode
   - Click the device selector (next to the scheme name)
   - **Select an iPhone simulator** (e.g., "iPhone 15 Pro")
   - **DO NOT select "My Mac" or "My Mac (Mac Catalyst)"**

3. **Clean and build:**
   - Press `⌘⇧K` (Product → Clean Build Folder)
   - Press `⌘B` (Product → Build)

4. **Verify success:**
   - Should say "Build Succeeded" with no errors

### Option 2: Command Line

```bash
cd /Users/berkeicel/Desktop/ICELPROJECTS/rampkit-ios

# Clean
swift package clean

# Build for iOS
swift build -c release \
  --sdk $(xcrun --sdk iphoneos --show-sdk-path) \
  -Xswiftc "-target" \
  -Xswiftc "arm64-apple-ios14.0"
```

### Option 3: Integration in iOS App

When adding as a dependency to your iOS app:

1. **In your iOS app project:**
   - File → Add Packages...
   - Enter the repository URL or use local path
   - Select version/branch

2. **Build your iOS app:**
   - Select your iOS app scheme
   - Select iPhone simulator or device
   - Build normally

The package will automatically build for iOS when building your iOS app.

---

## 🔍 Troubleshooting

### Still Getting Availability Errors?

#### Check 1: Xcode Build Destination
```
Top toolbar → Should show something like:
"iPhone 15 Pro" or "Any iOS Device (arm64)"

❌ NOT: "My Mac" or "Mac"
```

#### Check 2: Derived Data
If switching from Mac to iOS build, clean derived data:

```bash
# Close Xcode first, then:
rm -rf ~/Library/Developer/Xcode/DerivedData
```

Then reopen Xcode and build.

#### Check 3: Xcode Version
Ensure you have Xcode 14.0 or newer:

```bash
xcodebuild -version
# Should show: Xcode 14.0 or higher
```

#### Check 4: Command Line Tools
Ensure Xcode command line tools are set:

```bash
xcode-select --print-path
# Should show: /Applications/Xcode.app/Contents/Developer

# If not, set it:
sudo xcode-select --switch /Applications/Xcode.app/Contents/Developer
```

#### Check 5: Package Resolution
Sometimes Xcode gets confused. Try:

1. Close Xcode
2. Delete `.swiftpm` folder:
   ```bash
   rm -rf .swiftpm
   ```
3. Reopen Xcode
4. File → Packages → Reset Package Caches
5. Build again

---

## 📱 Using in Your iOS App

### Swift Package Manager

**In Package.swift:**
```swift
dependencies: [
    .package(url: "https://github.com/getrampkit/rampkit-ios.git", from: "0.0.1")
]
```

**Or in Xcode:**
1. Select your project in navigator
2. Select your target
3. General → Frameworks, Libraries, and Embedded Content
4. Click `+` → Add Package Dependency
5. Enter URL or select local package
6. Ensure "Add to Target" shows your iOS app target

### CocoaPods

**In Podfile:**
```ruby
platform :ios, '14.0'

target 'YourApp' do
  use_frameworks!
  pod 'RampKit', '~> 0.0.1'
end
```

Then:
```bash
pod install
```

---

## 🎯 Key Points

### Why iOS Only?

RampKit uses iOS-specific frameworks:
- ✅ **UIKit** - iOS user interface
- ✅ **WKWebView** - iOS web view
- ✅ **UIFeedbackGenerator** - iOS haptics
- ✅ **SKStoreReviewController** - iOS in-app review
- ✅ **UserNotifications** - iOS notifications

These are not available (or work differently) on macOS.

### Minimum Requirements

- **iOS:** 14.0+
- **Xcode:** 14.0+
- **Swift:** 5.9+
- **macOS (for development):** 12.0+

### Supported Destinations

✅ **Supported:**
- iPhone (device)
- iPhone (simulator)
- iPad (device)
- iPad (simulator)

❌ **Not Supported:**
- Mac (macOS)
- Mac Catalyst
- watchOS
- tvOS
- visionOS

---

## 🚀 Quick Start After Successful Build

```swift
import RampKit

// In AppDelegate or SceneDelegate
Task {
    await RampKit.initialize(config: RampKitConfig(
        apiKey: "your-api-key",
        autoShowOnboarding: true,
        onOnboardingFinished: { payload in
            print("Onboarding completed!")
        }
    ))
}
```

---

## 💡 Common Mistakes

### Mistake 1: Building for Mac
**Error:** Availability errors, "No such module UIKit"  
**Solution:** Select iPhone simulator

### Mistake 2: Wrong Swift Version
**Error:** "Expected 'package' keyword"  
**Solution:** Update to Xcode 14+ and Swift 5.9+

### Mistake 3: Cached Build Data
**Error:** Random build failures  
**Solution:** Clean derived data and package caches

---

## ✅ Verification

To verify everything is correct:

1. Open Package.swift in Xcode
2. Select "iPhone 15 Pro" simulator (or any iPhone)
3. Press `⌘B`
4. Should build successfully with 0 errors

If you see **"Build Succeeded"**, you're all set! 🎉

---

## 📞 Still Having Issues?

If you've followed all these steps and still have errors:

1. **Copy the exact error message**
2. **Note which file and line number**
3. **Verify your Xcode version:** `xcodebuild -version`
4. **Verify selected destination:** Screenshot of Xcode toolbar
5. **Check if building in an iOS app or standalone**

The most common issue is simply having "My Mac" selected instead of an iPhone simulator.

---

**Last Updated:** November 27, 2025  
**SDK Version:** 0.0.1  
**Minimum iOS:** 14.0







