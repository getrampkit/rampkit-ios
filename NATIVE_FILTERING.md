# 🛡️ Native-Side Message Filtering

## The Real Problem

Your **CDN HTML is calling native actions immediately** when the HTML loads, without checking visibility:

```javascript
// This runs as soon as the page loads
window.ReactNativeWebView.postMessage(JSON.stringify({
    type: 'request-notification-permission'
}));
```

When all 5 screens load at once, **ALL 5 HTML files send messages immediately**, even though only screen 0 is visible!

---

## ✅ The Solution: Filter Messages by Active Screen

Instead of requiring HTML changes, we **filter messages on the native side** by tracking which screen is currently active.

### How It Works:

1. **Track Active Screen**
   ```swift
   private var activeScreenIndex: Int = 0  // Currently visible screen
   ```

2. **Message Handler Knows Source**
   ```swift
   // Each message includes which screen it came from
   func handleRequestReview(fromIndex: Int) { ... }
   func handleRequestNotificationPermission(fromIndex: Int) { ... }
   ```

3. **Filter Sensitive Actions**
   ```swift
   func handleRequestNotificationPermission(options: ..., fromIndex: Int) {
       // CRITICAL: Only process if message is from the currently ACTIVE screen
       guard isScreenActive(fromIndex) else {
           RampKitLogger.log("Overlay", "🚫 BLOCKED notification from screen \(fromIndex)")
           return
       }
       
       RampKitLogger.log("Overlay", "✅ ALLOWED notification from screen \(fromIndex)")
       // Process the request...
   }
   ```

---

## What Gets Filtered

### 🚫 **Filtered Actions** (only from active screen):
- `request-notification-permission` ← **Most important!**
- `request-review` ← **Most important!**

### ✅ **Always Allowed** (any screen):
- `navigate`, `continue`, `goBack` ← Navigation must work
- `close` ← User should always be able to close
- `haptic` ← Haptics are harmless
- `onboarding-finished` ← Callbacks must work
- `show-paywall` ← Callbacks must work
- `variables` ← State sync must work

---

## Logs You'll See Now

### On App Launch:
```
[RampKit] Overlay: 📦 Loading screen 0
[RampKit] Overlay: 📦 Loading screen 1
[RampKit] Overlay: 📦 Loading screen 2
[RampKit] Overlay: 📦 Loading screen 3
[RampKit] Overlay: 📦 Loading screen 4
[RampKit] Overlay: ✅ All screens preloaded, screen 0 activated

[RampKit] MessageHandler: 📬 Received notification request from screen 0
[RampKit] Overlay: ✅ ALLOWED notification from ACTIVE screen 0

[RampKit] MessageHandler: 📬 Received notification request from screen 1
[RampKit] Overlay: 🚫 BLOCKED notification from INACTIVE screen 1 (current: 0)

[RampKit] MessageHandler: 📬 Received notification request from screen 2
[RampKit] Overlay: 🚫 BLOCKED notification from INACTIVE screen 2 (current: 0)

[RampKit] MessageHandler: 📬 Received notification request from screen 3
[RampKit] Overlay: 🚫 BLOCKED notification from INACTIVE screen 3 (current: 0)

[RampKit] MessageHandler: 📬 Received notification request from screen 4
[RampKit] Overlay: 🚫 BLOCKED notification from INACTIVE screen 4 (current: 0)
```

### On Navigation to Screen 3:
```
[RampKit] Overlay: 🔒 Screen 0 DEACTIVATED
[RampKit] Overlay: 🔓 Screen 3 ACTIVATED

[RampKit] MessageHandler: 📬 Received notification request from screen 3
[RampKit] Overlay: ✅ ALLOWED notification from ACTIVE screen 3
[RampKit] Overlay: 📬 Requesting permission (undetermined)
→ System notification dialog appears!
```

---

## Technical Implementation

### 1. **Protocol Updated**
```swift
protocol RampKitMessageHandlerDelegate: AnyObject {
    func handleRequestReview(fromIndex: Int)  // ← Added fromIndex
    func handleRequestNotificationPermission(options: ..., fromIndex: Int)
    // ... all methods now include fromIndex
}
```

### 2. **Message Proxy Passes Index**
```swift
class WebViewMessageProxy: NSObject, WKScriptMessageHandler {
    let index: Int  // ← Each proxy knows its screen index
    
    func userContentController(...didReceive message: ...) {
        handler?.messageHandler.handleMessage(body: message.body, fromIndex: index)
        //                                                           ↑ passes index
    }
}
```

### 3. **Overlay Controller Filters**
```swift
func handleRequestNotificationPermission(options: ..., fromIndex: Int) {
    guard isScreenActive(fromIndex) else {
        RampKitLogger.log("🚫 BLOCKED from screen \(fromIndex)")
        return  // ← Message is silently ignored
    }
    
    // Only reaches here if screen is active
    NotificationManager.requestNotificationPermission(...)
}
```

### 4. **Active Screen Tracking**
```swift
private func activateScreen(at index: Int) {
    activeScreenIndex = index  // ← Update tracker
    // ... rest of activation logic
}

private func isScreenActive(_ index: Int) -> Bool {
    return index == activeScreenIndex
}
```

---

## Benefits

✅ **No HTML Changes Required** - Works with existing CDN content  
✅ **Bulletproof** - Messages are filtered before processing  
✅ **Instant Transitions** - All screens still preloaded  
✅ **Clear Logs** - Easy to debug with 🚫 BLOCKED / ✅ ALLOWED markers  
✅ **Future-Proof** - Works even if HTML doesn't check visibility  

---

## Verification

Run your app and check the console:

1. **On Launch:**
   - Should see 4x `🚫 BLOCKED` messages (screens 1-4)
   - Should see 1x `✅ ALLOWED` message (screen 0, if it requests)

2. **On Navigate to Screen 3:**
   - Should see `🔓 Screen 3 ACTIVATED`
   - Should see `✅ ALLOWED notification from screen 3`
   - **System dialog should appear!**

3. **On Navigate to Screen 4:**
   - Should see `🔓 Screen 4 ACTIVATED`
   - Should see `✅ ALLOWED review from screen 4`
   - **Store review dialog should appear!**

---

## Combined with Visibility System

You now have **two layers of protection**:

### Layer 1: JavaScript-Side (Optional)
HTML can check `window.__rampkitScreenVisible` before sending messages:
```javascript
if (window.__rampkitScreenVisible) {
    window.ReactNativeWebView.postMessage({...});
}
```

### Layer 2: Native-Side (Always On) 🛡️
Even if HTML doesn't check, native code filters:
```swift
guard isScreenActive(fromIndex) else { return }
```

**Result:** Messages from inactive screens are **always blocked**, regardless of what the HTML does!

---

## Summary

**Problem:** HTML sends notification/review requests as soon as it loads  
**Solution:** Native code filters messages by active screen index  
**Result:** Only the currently visible screen can trigger sensitive actions  

🎉 **No more premature dialogs!**







