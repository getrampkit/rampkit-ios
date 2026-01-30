# 🔍 Debug: Message Flow

## I've Added Comprehensive Logging

Run your app and check the console for these key indicators:

---

## 1. **Initialization** (App Launch)

You should see:
```
[RampKit] Overlay: 🚀 viewDidLoad - Initial activeScreenIndex: 0
[RampKit] Overlay: 📦 Loading screen 0
[RampKit] Overlay: 📦 Loading screen 1
[RampKit] Overlay: 📦 Loading screen 2
[RampKit] Overlay: 📦 Loading screen 3
[RampKit] Overlay: 📦 Loading screen 4
[RampKit] Overlay: 🔓 Activating screen 0 (was: 0)
[RampKit] Overlay: ✅ Screen 0 activated
[RampKit] Overlay: ✅ All screens preloaded, screen 0 activated
```

---

## 2. **Message Reception**

When a message arrives from ANY screen:
```
[RampKit] MessageProxy: 📨 Message received from WebView[X]: {...}
[RampKit] MessageHandler: [message type specific log]
```

**If you DON'T see `📨 Message received`** → WebView isn't sending messages (check HTML)

---

## 3. **Navigation Messages**

When clicking a button that navigates:
```
[RampKit] MessageProxy: 📨 Message received from WebView[0]: {...}
[RampKit] Overlay: 🧭 Navigate request from screen 0 to '__continue__'
[RampKit] Overlay: 🔒 Deactivating screen 0
[RampKit] Overlay: 🔓 Activating screen 1 (was: 0)
[RampKit] Overlay: ✅ Screen 1 activated
```

**If you DON'T see `🧭 Navigate request`** → Message handler isn't processing it

---

## 4. **Notification Permission Requests**

When HTML tries to request notifications:
```
[RampKit] MessageProxy: 📨 Message received from WebView[3]: {...}
[RampKit] MessageHandler: 📬 Received notification permission request from screen 3
[RampKit] Overlay: 🎯 Notification request from screen 3, activeScreen: 3, isActive: true
[RampKit] Overlay: ✅ ALLOWED notification permission request from ACTIVE screen 3
[RampKit] Overlay: 📬 Notification permission requested - allowAlert: true, ...
```

**If you see `🚫 BLOCKED`** → Message is from inactive screen (expected for screens 1-4 on launch)

---

## 5. **Store Review Requests**

When HTML tries to request review:
```
[RampKit] MessageProxy: 📨 Message received from WebView[4]: {...}
[RampKit] Overlay: 🎯 Review request from screen 4, activeScreen: 4, isActive: true
[RampKit] Overlay: ✅ ALLOWED review request from ACTIVE screen 4
```

---

## 🚨 Common Issues

### Issue: "No messages at all"

**Symptom:** Don't see `📨 Message received` in console

**Cause:** HTML isn't sending messages

**Check:**
1. Is `window.ReactNativeWebView.postMessage()` being called in HTML?
2. Check browser console in the WebView (if inspectable)
3. Look for polyfill message: `✅ ReactNativeWebView polyfill installed`

---

### Issue: "Messages received but nothing happens"

**Symptom:** See `📨 Message received` but no action

**Check:**
1. Look for `⚠️` warnings after the message
2. Check if navigation/action logs appear
3. Verify message format is correct

---

### Issue: "All messages blocked"

**Symptom:** See `🚫 BLOCKED` for ALL messages

**Check logs for:**
```
[RampKit] Overlay: 🎯 Notification request from screen 3, activeScreen: 0, isActive: false
                                                            ↑ different!
```

**This is CORRECT if screen 3 is not visible!**

---

### Issue: "Active screen also blocked"

**Symptom:** See `🚫 BLOCKED` even when screen should be active

**Check logs for:**
```
[RampKit] Overlay: 🎯 Notification request from screen 0, activeScreen: 0, isActive: false
                                                                                      ↑ should be true!
```

**This indicates a bug in `isScreenActive()`** - please share full logs

---

## 📋 What to Share

If still having issues, copy and paste these logs:

1. **Initialization section** (from app launch to "All screens preloaded")
2. **First message that fails** (including the `📨`, `🎯`, and result)
3. **Full navigation sequence** (if trying to navigate)

Example:
```
[RampKit] Overlay: 🚀 viewDidLoad - Initial activeScreenIndex: 0
[RampKit] Overlay: ✅ All screens preloaded, screen 0 activated
[RampKit] MessageProxy: 📨 Message received from WebView[0]: {"type":"continue"}
[RampKit] Overlay: 🧭 Navigate request from screen 0 to '__continue__'
[RampKit] Overlay: 🔒 Deactivating screen 0
[RampKit] Overlay: 🔓 Activating screen 1 (was: 0)
```

---

## 🎯 Expected Behavior

### Scenario 1: App Launch
- ✅ Screen 0: ALL messages allowed
- 🚫 Screens 1-4: Notification/review BLOCKED (navigation OK)

### Scenario 2: Navigate to Screen 3
- 🚫 Screen 0: Notification/review BLOCKED
- ✅ Screen 3: ALL messages allowed
- 🚫 Screens 1,2,4: Notification/review BLOCKED

### Scenario 3: Navigate Back to Screen 0
- ✅ Screen 0: ALL messages allowed (again)
- 🚫 Screens 1-4: Notification/review BLOCKED

---

## 🔧 Quick Test

Add this button to your HTML to test message sending:
```html
<button onclick="testMessage()">Test Message</button>
<script>
function testMessage() {
    console.log('🧪 Testing message...');
    window.ReactNativeWebView.postMessage(JSON.stringify({
        type: 'rampkit:navigate',
        targetScreenId: '__continue__'
    }));
    console.log('✅ Message sent');
}
</script>
```

When clicked, you should see:
```
[RampKit] MessageProxy: 📨 Message received from WebView[0]: {...}
[RampKit] Overlay: 🧭 Navigate request from screen 0 to '__continue__'
```

If you DON'T see this, the issue is in the WebView → Native bridge, not in filtering!







