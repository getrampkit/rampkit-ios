import Foundation
#if canImport(UIKit)
import UIKit
#endif
#if canImport(WebKit)
import WebKit
#endif

#if os(iOS)
/// Custom WKWebView subclass that removes the keyboard accessory bar
class CustomWebView: WKWebView {

    /// Override inputAccessoryView to remove the keyboard accessory bar
    /// This removes the default iOS toolbar that appears above the keyboard
    /// with navigation arrows and a "Done" button
    override var inputAccessoryView: UIView? {
        return nil
    }
}
#endif
