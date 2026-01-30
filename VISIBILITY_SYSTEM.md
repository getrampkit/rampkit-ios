# 🔒 RampKit Screen Visibility System

## Overview

All screens are **preloaded immediately** for instant transitions, but JavaScript execution is **controlled by visibility flags** to prevent premature actions.

---

## How It Works

### 1. **All Screens Load at Init**
```
[RampKit] Overlay: 📦 Loading screen 0: phone-1 (INACTIVE)
[RampKit] Overlay: 📦 Loading screen 1: phone-2 (INACTIVE)
[RampKit] Overlay: 📦 Loading screen 2: phone-3 (INACTIVE)
[RampKit] Overlay: 📦 Loading screen 3: phone-4 (INACTIVE)
[RampKit] Overlay: 📦 Loading screen 4: phone-5 (INACTIVE)
[RampKit] Overlay: ✅ All screens preloaded, screen 0 activated
```

### 2. **Injected Visibility Flags**

Every screen gets these global variables injected **before** the HTML loads:

```javascript
window.__rampkitScreenVisible = false;  // Initially INACTIVE
window.__rampkitScreenIndex = 0;        // Screen index
```

### 3. **Activation on Navigation**

When a screen becomes visible:

```javascript
window.__rampkitScreenVisible = true;  // NOW ACTIVE
document.dispatchEvent(new CustomEvent('rampkit:screen-visible', {
    detail: { screenIndex: 0, screenId: 'phone-1' }
}));
```

Logs:
```
[RampKit] Overlay: 🔓 Screen 0 ACTIVATED - JavaScript can now run
[RampKit] Overlay: ✅ Screen 0 activated
```

---

## HTML Integration

Your HTML should check visibility before triggering native actions:

### ❌ BAD (Old Way - Runs Immediately)

```javascript
// This runs as soon as the HTML loads, even if screen is not visible!
window.ReactNativeWebView.postMessage(JSON.stringify({
    type: 'request-notification-permission',
    options: { alert: true, sound: true, badge: true }
}));
```

### ✅ GOOD (New Way - Only When Visible)

**Option 1: Check Flag**
```javascript
// Wait for screen to become visible
if (window.__rampkitScreenVisible) {
    // Safe to request permissions
    window.ReactNativeWebView.postMessage(JSON.stringify({
        type: 'request-notification-permission',
        options: { alert: true, sound: true, badge: true }
    }));
} else {
    console.log('Screen not visible yet, skipping auto-actions');
}
```

**Option 2: Listen for Event (Recommended)**
```javascript
// Listen for screen becoming visible
document.addEventListener('rampkit:screen-visible', (event) => {
    console.log('Screen is now visible:', event.detail);
    
    // NOW safe to trigger native actions
    window.ReactNativeWebView.postMessage(JSON.stringify({
        type: 'request-notification-permission',
        options: { alert: true, sound: true, badge: true }
    }));
});

// Or check immediately if already visible
if (window.__rampkitScreenVisible) {
    // Screen was already visible when script ran
    triggerActions();
}
```

**Option 3: Polling (Fallback)**
```javascript
function waitForVisible(callback) {
    if (window.__rampkitScreenVisible) {
        callback();
    } else {
        setTimeout(() => waitForVisible(callback), 100);
    }
}

waitForVisible(() => {
    console.log('Screen is visible, requesting permissions');
    window.ReactNativeWebView.postMessage(JSON.stringify({
        type: 'request-notification-permission',
        options: { alert: true, sound: true, badge: true }
    }));
});
```

---

## Complete Example HTML

```html
<!DOCTYPE html>
<html>
<head>
    <meta charset="UTF-8">
    <title>Onboarding Screen</title>
    <script>
        // VISIBILITY-AWARE INITIALIZATION
        function initScreen() {
            console.log('Initializing screen...');
            console.log('Visible:', window.__rampkitScreenVisible);
            console.log('Index:', window.__rampkitScreenIndex);
            
            // Listen for screen becoming visible
            document.addEventListener('rampkit:screen-visible', handleScreenVisible);
            
            // If already visible, trigger immediately
            if (window.__rampkitScreenVisible) {
                handleScreenVisible();
            }
        }
        
        function handleScreenVisible(event) {
            console.log('🔓 Screen is now visible!');
            
            // NOW safe to trigger native actions
            if (shouldRequestNotifications()) {
                requestNotificationPermission();
            }
            
            if (shouldRequestReview()) {
                requestStoreReview();
            }
        }
        
        function shouldRequestNotifications() {
            // Only request on specific screen (e.g., screen 3)
            return window.__rampkitScreenIndex === 3;
        }
        
        function shouldRequestReview() {
            // Only request on specific screen (e.g., screen 4)
            return window.__rampkitScreenIndex === 4;
        }
        
        function requestNotificationPermission() {
            console.log('Requesting notification permission...');
            window.ReactNativeWebView.postMessage(JSON.stringify({
                type: 'request-notification-permission',
                options: { alert: true, sound: true, badge: true }
            }));
        }
        
        function requestStoreReview() {
            console.log('Requesting store review...');
            window.ReactNativeWebView.postMessage(JSON.stringify({
                type: 'request-review'
            }));
        }
        
        // Initialize when DOM is ready
        document.addEventListener('DOMContentLoaded', initScreen);
    </script>
</head>
<body>
    <h1>Welcome!</h1>
    <button onclick="handleScreenVisible()">Trigger Actions</button>
</body>
</html>
```

---

## Benefits

✅ **No Wait Times** - All screens preloaded, instant transitions  
✅ **No Premature Actions** - JavaScript only runs when screen is visible  
✅ **System Dialogs Work** - Notifications/reviews appear at correct time  
✅ **Bulletproof** - Works with swipe gestures, programmatic navigation, and direct jumps  

---

## Testing

1. **Launch app** → Only screen 0 should activate
2. **Navigate to screen 3** → Notification permission request appears
3. **Navigate to screen 4** → Store review request appears
4. **Swipe back** → Previous screen reactivates

Logs to verify:
```
[RampKit] Overlay: 🔓 Screen 0 ACTIVATED
[User navigates]
[RampKit] Overlay: 🔒 Screen 0 DEACTIVATED
[RampKit] Overlay: 🔓 Screen 3 ACTIVATED
```

---

## Migration Checklist

- [ ] Update HTML to check `window.__rampkitScreenVisible` before triggering native actions
- [ ] Use `rampkit:screen-visible` event listener for visibility changes
- [ ] Test that permissions only request when screen is actually viewed
- [ ] Verify instant transitions still work (no loading delays)
- [ ] Confirm system dialogs appear above overlay

---

## Advanced: Screen-Specific Logic

```javascript
// Different behavior per screen
document.addEventListener('rampkit:screen-visible', (event) => {
    const { screenIndex, screenId } = event.detail;
    
    switch (screenId) {
        case 'notifications-screen':
            requestNotificationPermission();
            break;
        case 'review-screen':
            requestStoreReview();
            break;
        case 'final-screen':
            trackConversion();
            break;
    }
});
```

---

## Debugging

Add this to your HTML to see visibility state:

```javascript
setInterval(() => {
    console.log('Screen', window.__rampkitScreenIndex, 
                'visible:', window.__rampkitScreenVisible);
}, 1000);
```

You should see:
```
Screen 0 visible: true   ← Active screen
Screen 1 visible: false  ← Preloaded but inactive
Screen 2 visible: false  ← Preloaded but inactive
```







