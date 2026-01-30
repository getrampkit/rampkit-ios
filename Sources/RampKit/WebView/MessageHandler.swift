import Foundation
#if canImport(WebKit)
import WebKit
#endif

/// Handles messages from WebView content
protocol RampKitMessageHandlerDelegate: AnyObject {
    func handleNavigate(targetScreenId: String?, animation: String?, fromIndex: Int)
    func handleGoBack(animation: String?, fromIndex: Int)
    func handleClose(fromIndex: Int)
    func handleHaptic(event: HapticEvent, fromIndex: Int)
    func handleRequestReview(fromIndex: Int)
    func handleRequestNotificationPermission(options: NotificationPermissionOptions, fromIndex: Int)
    func handleOnboardingFinished(payload: Any?, fromIndex: Int)
    func handleShowPaywall(payload: Any?, fromIndex: Int)
    func handleVariablesUpdate(vars: [String: Any], fromIndex: Int)
    func handleRequestVars(forIndex: Int)
    func handleInputBlur(variableName: String)
    func getScreenName(forIndex: Int) -> String?
}

/// Parser and router for WebView messages
class RampKitMessageHandler {
    weak var delegate: RampKitMessageHandlerDelegate?
    
    /// Handle a message from WebView
    func handleMessage(body: Any, fromIndex: Int) {
        // Try parsing as JSON first
        if let jsonString = body as? String,
           let data = jsonString.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            handleJSONMessage(json, fromIndex: fromIndex)
        } else if let dict = body as? [String: Any] {
            handleJSONMessage(dict, fromIndex: fromIndex)
        } else if let string = body as? String {
            handleStringMessage(string, fromIndex: fromIndex)
        }
    }
    
    /// Handle JSON structured messages
    @available(iOS 14.0, macOS 11.0, *)
    private func handleJSONMessage(_ json: [String: Any], fromIndex: Int) {
        guard let type = json["type"] as? String else { return }
        
        let screenName = delegate?.getScreenName(forIndex: fromIndex)
        
        switch type {
        case "rampkit:continue", "continue":
            let animation = json["animation"] as? String
            trackCtaTap(buttonId: "continue", screenName: screenName)
            delegate?.handleNavigate(targetScreenId: "__continue__", animation: animation, fromIndex: fromIndex)
            
        case "rampkit:navigate":
            let targetScreenId = json["targetScreenId"] as? String
            let animation = json["animation"] as? String
            trackCtaTap(buttonId: targetScreenId ?? "navigate", screenName: screenName)
            delegate?.handleNavigate(targetScreenId: targetScreenId, animation: animation, fromIndex: fromIndex)
            
        case "rampkit:goBack":
            let animation = json["animation"] as? String
            trackCtaTap(buttonId: "back", screenName: screenName)
            delegate?.handleGoBack(animation: animation, fromIndex: fromIndex)
            
        case "rampkit:close":
            delegate?.handleClose(fromIndex: fromIndex)
            
        case "rampkit:haptic":
            if let hapticEvent = parseHapticEvent(from: json) {
                delegate?.handleHaptic(event: hapticEvent, fromIndex: fromIndex)
            }
            
        case "rampkit:request-review", "rampkit:review":
            delegate?.handleRequestReview(fromIndex: fromIndex)
            
        case "rampkit:request-notification-permission":
            RampKitLogger.verbose("MessageHandler", "Received notification permission request from screen \(fromIndex)")
            let options = parseNotificationOptions(from: json)
            delegate?.handleRequestNotificationPermission(options: options, fromIndex: fromIndex)
            
        case "rampkit:onboarding-finished":
            let payload = json["payload"]
            delegate?.handleOnboardingFinished(payload: payload, fromIndex: fromIndex)
            
        case "rampkit:show-paywall":
            let payload = json["payload"]
            let paywallId = (payload as? [String: Any])?["paywallId"] as? String
            EventManager.shared.trackPaywallShown(paywallId: paywallId ?? "unknown", placement: "onboarding")
            delegate?.handleShowPaywall(payload: payload, fromIndex: fromIndex)
            
        case "rampkit:variables":
            if let vars = json["vars"] as? [String: Any] {
                delegate?.handleVariablesUpdate(vars: vars, fromIndex: fromIndex)
            }
            
        case "rampkit:request-vars":
            delegate?.handleRequestVars(forIndex: fromIndex)
            
        // MARK: - Event Messages from WebView
            
        case "rampkit:event":
            handleEventMessage(json, screenName: screenName)

        case "rampkit:option-selected":
            if let optionId = json["optionId"] as? String {
                let optionValue = json["optionValue"] ?? ""
                let questionId = json["questionId"] as? String
                EventManager.shared.trackOptionSelected(
                    optionId: optionId,
                    optionValue: optionValue,
                    questionId: questionId
                )
            }
            
        case "rampkit:cta-tap":
            let buttonId = json["buttonId"] as? String ?? "unknown"
            let buttonText = json["buttonText"] as? String
            EventManager.shared.trackCtaTap(buttonId: buttonId, buttonText: buttonText, screenName: screenName)
            
        case "rampkit:debug":
            let message = json["message"] as? String ?? "no message"
            RampKitLogger.verbose("DynTap", message)

        case "rampkit:input-blur":
            if let variableName = json["variableName"] as? String {
                delegate?.handleInputBlur(variableName: variableName)
            }

        default:
            break
        }
    }
    
    /// Handle explicit event message from WebView
    @available(iOS 14.0, macOS 11.0, *)
    private func handleEventMessage(_ json: [String: Any], screenName: String?) {
        guard let eventName = json["eventName"] as? String else { return }
        
        let properties = json["properties"] as? [String: Any] ?? [:]
        
        // Map to known event types or track as custom
        if let knownEvent = RampKitEventName(rawValue: eventName) {
            EventManager.shared.track(
                knownEvent,
                screenName: screenName,
                properties: properties
            )
        } else {
            EventManager.shared.trackCustom(
                eventName,
                screenName: screenName,
                properties: properties
            )
        }
    }
    
    /// Track CTA tap helper
    @available(iOS 14.0, macOS 11.0, *)
    private func trackCtaTap(buttonId: String, screenName: String?) {
        EventManager.shared.trackCtaTap(buttonId: buttonId, screenName: screenName)
    }
    
    /// Handle string-based legacy messages
    private func handleStringMessage(_ message: String, fromIndex: Int) {
        if message == "rampkit:tap" || message == "next" || message == "continue" {
            delegate?.handleNavigate(targetScreenId: "__continue__", animation: nil, fromIndex: fromIndex)
        } else if message == "rampkit:close" {
            delegate?.handleClose(fromIndex: fromIndex)
        } else if message == "rampkit:goBack" {
            delegate?.handleGoBack(animation: nil, fromIndex: fromIndex)
        } else if message == "rampkit:review" || message == "rampkit:request-review" {
            delegate?.handleRequestReview(fromIndex: fromIndex)
        } else if message == "rampkit:request-notification-permission" {
            RampKitLogger.verbose("MessageHandler", "Received notification permission request from screen \(fromIndex) (string)")
            delegate?.handleRequestNotificationPermission(options: NotificationPermissionOptions(), fromIndex: fromIndex)
        } else if message == "rampkit:show-paywall" {
            delegate?.handleShowPaywall(payload: nil, fromIndex: fromIndex)
        } else if message == "rampkit:onboarding-finished" {
            delegate?.handleOnboardingFinished(payload: nil, fromIndex: fromIndex)
        } else if message.hasPrefix("rampkit:navigate:") {
            let targetId = String(message.dropFirst("rampkit:navigate:".count))
            delegate?.handleNavigate(targetScreenId: targetId, animation: nil, fromIndex: fromIndex)
        } else if message.hasPrefix("haptic:") {
            // Legacy haptic format
            let event = HapticEvent(
                hapticType: .impact,
                impactStyle: .medium,
                notificationType: nil
            )
            delegate?.handleHaptic(event: event, fromIndex: fromIndex)
        }
    }
    
    /// Parse haptic event from JSON
    private func parseHapticEvent(from json: [String: Any]) -> HapticEvent? {
        guard let hapticTypeStr = json["hapticType"] as? String else { return nil }
        
        let hapticType: HapticEvent.HapticType
        switch hapticTypeStr {
        case "impact":
            hapticType = .impact
        case "notification":
            hapticType = .notification
        case "selection":
            hapticType = .selection
        default:
            return nil
        }
        
        var impactStyle: HapticEvent.ImpactStyle?
        if let styleStr = json["impactStyle"] as? String {
            impactStyle = HapticEvent.ImpactStyle(rawValue: styleStr)
        }
        
        var notificationType: HapticEvent.NotificationType?
        if let typeStr = json["notificationType"] as? String {
            notificationType = HapticEvent.NotificationType(rawValue: typeStr)
        }
        
        return HapticEvent(
            hapticType: hapticType,
            impactStyle: impactStyle,
            notificationType: notificationType
        )
    }
    
    /// Parse notification permission options from JSON
    private func parseNotificationOptions(from json: [String: Any]) -> NotificationPermissionOptions {
        var allowAlert = true
        var allowBadge = true
        var allowSound = true
        
        if let ios = json["ios"] as? [String: Any] {
            allowAlert = ios["allowAlert"] as? Bool ?? true
            allowBadge = ios["allowBadge"] as? Bool ?? true
            allowSound = ios["allowSound"] as? Bool ?? true
        }
        
        return NotificationPermissionOptions(
            allowAlert: allowAlert,
            allowBadge: allowBadge,
            allowSound: allowSound
        )
    }
}

