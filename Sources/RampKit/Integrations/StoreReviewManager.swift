import Foundation
#if canImport(UIKit)
import UIKit
#endif
#if canImport(StoreKit)
import StoreKit
#endif

/// Manager for in-app store review
enum StoreReviewManager {
    
    /// Request in-app review prompt from specific window scene
    static func requestReview(from viewController: UIViewController? = nil) {
        #if os(iOS)
        if #available(iOS 14.0, *) {
            // Get the window scene from the provided view controller or find active one
            var windowScene: UIWindowScene?
            
            if let vc = viewController,
               let scene = vc.view.window?.windowScene {
                windowScene = scene
                RampKitLogger.verbose("StoreReview", "Using view controller's window scene")
            } else {
                windowScene = UIApplication.shared.connectedScenes
                    .first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene
                RampKitLogger.verbose("StoreReview", "Using first active window scene")
            }

            if let scene = windowScene {
                SKStoreReviewController.requestReview(in: scene)
                RampKitLogger.verbose("StoreReview", "Review requested")
            } else {
                RampKitLogger.warn("StoreReview", "No window scene found")
            }
        } else {
            // Fallback to older API
            SKStoreReviewController.requestReview()
        }
        #endif
    }
}

