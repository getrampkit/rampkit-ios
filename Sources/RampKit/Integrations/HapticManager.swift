import Foundation
#if canImport(UIKit)
import UIKit
#endif

/// Manager for haptic feedback
enum HapticManager {
    
    /// Perform haptic feedback based on event
    static func performHaptic(event: HapticEvent) {
        #if os(iOS)
        switch event.hapticType {
        case .impact:
            performImpact(style: event.impactStyle ?? .medium)
            
        case .notification:
            performNotification(type: event.notificationType ?? .success)
            
        case .selection:
            performSelection()
        }
        #endif
    }
    
    #if os(iOS)
    /// Perform impact haptic
    private static func performImpact(style: HapticEvent.ImpactStyle) {
        let feedbackStyle: UIImpactFeedbackGenerator.FeedbackStyle
        
        switch style {
        case .light:
            feedbackStyle = .light
        case .medium:
            feedbackStyle = .medium
        case .heavy:
            feedbackStyle = .heavy
        case .rigid:
            feedbackStyle = .rigid
        case .soft:
            feedbackStyle = .soft
        }
        
        let generator = UIImpactFeedbackGenerator(style: feedbackStyle)
        generator.impactOccurred()
    }
    
    /// Perform notification haptic
    private static func performNotification(type: HapticEvent.NotificationType) {
        let feedbackType: UINotificationFeedbackGenerator.FeedbackType
        
        switch type {
        case .success:
            feedbackType = .success
        case .warning:
            feedbackType = .warning
        case .error:
            feedbackType = .error
        }
        
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(feedbackType)
    }
    
    /// Perform selection haptic
    private static func performSelection() {
        let generator = UISelectionFeedbackGenerator()
        generator.selectionChanged()
    }
    #endif
}

