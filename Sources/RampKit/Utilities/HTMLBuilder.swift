import Foundation

/// Builds complete HTML documents from screen payloads
enum HTMLBuilder {
    
    /// Build a complete HTML document for a screen
    /// - Parameters:
    ///   - screen: Screen payload with HTML/CSS/JS
    ///   - variables: State variables from onboarding
    ///   - requiredScripts: External script URLs to include
    ///   - context: Device/User context for template resolution (optional for backwards compatibility)
    ///   - components: Component definitions for expanding <ramp-component/> tags
    static func buildHTMLDocument(
        screen: ScreenPayload,
        variables: [String: Any],
        requiredScripts: [String],
        context: RampKitContext? = nil,
        components: [String: SDKComponent]? = nil
    ) -> String {
        let css = screen.css ?? ""
        let html = extractBodyContent(ComponentExpander.expandHTML(screen.html, components: components))
        let js = screen.js ?? ""

        // Build script tags for required external scripts
        let scriptsHTML = requiredScripts
            .map { "<script src=\"\($0)\"></script>" }
            .joined(separator: "\n")

        // Generate preconnect and DNS prefetch tags for performance
        let preconnectTags = generatePreconnectTags(from: requiredScripts)

        // Serialize variables to JSON
        let variablesJSON = serializeVariables(variables)

        // Serialize context to JSON (or empty object if not provided)
        let contextJSON = context?.toJSONString() ?? "{\"device\":{},\"user\":{}}"

        // Translation support
        let locale = context?.device.locale ?? "en_US"
        let language = context?.device.language ?? "en"
        let rtlLanguages = ["ar", "he", "fa", "ur"]
        let isRTL = rtlLanguages.contains(language)

        let translationCall: String
        if let translations = screen.translations {
            if let data = try? JSONSerialization.data(withJSONObject: translations),
               let jsonString = String(data: data, encoding: .utf8) {
                translationCall = "window.__rampkitApplyTranslations(\(jsonString), \"\(locale)\", \"\(language)\");"
            } else {
                translationCall = ""
            }
        } else {
            translationCall = ""
        }

        let htmlTag = isRTL
            ? "<html dir=\"rtl\" lang=\"\(language)\">"
            : "<html lang=\"\(language)\">"

        return """
        <!doctype html>
        \(htmlTag)
        <head>
        <meta charset="utf-8"/>
        <meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=1, user-scalable=no, viewport-fit=cover"/>
        \(preconnectTags)
        \(scriptsHTML)
        <style>\(css)</style>
        <style>
        html,body{margin:0;padding:0;overflow-x:hidden}
        *{-webkit-tap-highlight-color: rgba(0,0,0,0);}
        ::selection{background:transparent}
        ::-moz-selection{background:transparent}
        
        /* Tap fade effect for interactive elements */
        .rk-tappable {
            transition: opacity 0.1s ease, transform 0.1s ease !important;
            transform: scale(1);
            opacity: 1;
        }
        .rk-tappable:active {
            opacity: 0.7 !important;
            transform: scale(0.98) !important;
        }
        </style>
        </head>
        <body>
        \(html)
        <script>
        // RampKit Context: Device and User variables for template resolution
        window.rampkitContext = \(contextJSON);

        // RampKit State Variables
        window.__rampkitVariables = \(variablesJSON);

        /* RampKit: Translation Support */
        \(InjectedScripts.translationScript)
        \(translationCall)

        /* RampKit: Template Resolution for ${device.*}, ${user.*}, ${state.*} */
        \(InjectedScripts.templateResolver)
        
        /* RampKit: Dynamic Tap Behavior Handler */
        \(InjectedScripts.dynamicTapHandler)

        /* RampKit: On-Open Action Handler for delayed actions */
        \(InjectedScripts.onOpenActionHandler)

        /* RampKit: Auto-detect tappable elements and add fade effect */
        (function() {
            function isTappable(el) {
                if (!el || el.nodeType !== 1) return false;
                // Check for common tappable indicators
                if (el.onclick || el.hasAttribute('onclick')) return true;
                if (el.hasAttribute('data-onclick') || el.hasAttribute('data-tap')) return true;
                if (el.hasAttribute('data-action') || el.hasAttribute('data-navigate')) return true;
                if (el.tagName === 'BUTTON' || el.tagName === 'A') return true;
                if (el.getAttribute('role') === 'button') return true;
                if (el.style.cursor === 'pointer') return true;
                var cs = window.getComputedStyle(el);
                if (cs && cs.cursor === 'pointer') return true;
                return false;
            }
            
            function markTappable(el) {
                if (isTappable(el) && !el.classList.contains('rk-tappable')) {
                    el.classList.add('rk-tappable');
                }
            }
            
            function scanAll() {
                document.querySelectorAll('*').forEach(markTappable);
            }
            
            // Initial scan after DOM ready
            if (document.readyState === 'loading') {
                document.addEventListener('DOMContentLoaded', scanAll);
            } else {
                setTimeout(scanAll, 0);
            }
            
            // Watch for dynamically added elements
            var obs = new MutationObserver(function(muts) {
                muts.forEach(function(m) {
                    m.addedNodes && m.addedNodes.forEach(function(n) {
                        if (n.nodeType === 1) {
                            markTappable(n);
                            n.querySelectorAll && n.querySelectorAll('*').forEach(markTappable);
                        }
                    });
                });
            });
            obs.observe(document.documentElement, { childList: true, subtree: true });
            
            // Re-scan periodically to catch elements with dynamically added handlers
            setInterval(scanAll, 500);
        })();
        
        \(js)
        </script>
        </body>
        </html>
        """
    }
    
    /// Extract body content from a potentially complete HTML document.
    /// If the screen HTML is a full `<!DOCTYPE html>...<body>...</body></html>` document,
    /// this strips the outer tags and returns only the body content to prevent
    /// nested HTML documents that break inline script execution in WKWebView.
    private static func extractBodyContent(_ html: String) -> String {
        let trimmed = html.trimmingCharacters(in: .whitespacesAndNewlines)

        // If it doesn't look like a complete document, return as-is
        guard trimmed.lowercased().hasPrefix("<!doctype") || trimmed.lowercased().hasPrefix("<html") else {
            return html
        }

        // Try to extract content between <body...> and </body>
        if let bodyOpenRange = html.range(of: "<body[^>]*>", options: [.regularExpression, .caseInsensitive]),
           let bodyCloseRange = html.range(of: "</body>", options: [.caseInsensitive, .backwards]) {
            return String(html[bodyOpenRange.upperBound..<bodyCloseRange.lowerBound])
        }

        // Fallback: strip document wrapper tags but keep content
        var result = html
        if let doctypeRange = result.range(of: "<!doctype[^>]*>", options: [.regularExpression, .caseInsensitive]) {
            result.removeSubrange(doctypeRange)
        }
        result = result.replacingOccurrences(of: "<html[^>]*>", with: "", options: [.regularExpression, .caseInsensitive])
        result = result.replacingOccurrences(of: "</html>", with: "", options: .caseInsensitive)
        if let headStart = result.range(of: "<head[^>]*>", options: [.regularExpression, .caseInsensitive]),
           let headEnd = result.range(of: "</head>", options: .caseInsensitive) {
            result.removeSubrange(headStart.lowerBound..<headEnd.upperBound)
        }
        result = result.replacingOccurrences(of: "<body[^>]*>", with: "", options: [.regularExpression, .caseInsensitive])
        result = result.replacingOccurrences(of: "</body>", with: "", options: .caseInsensitive)

        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Generate preconnect and DNS prefetch tags for external scripts
    private static func generatePreconnectTags(from scripts: [String]) -> String {
        // Use dictionary to deduplicate by host
        var originsByHost: [String: String] = [:]
        
        for urlString in scripts {
            guard let url = URL(string: urlString),
                  let host = url.host else { continue }
            let scheme = url.scheme ?? "https"
            let origin = "\(scheme)://\(host)"
            originsByHost[host] = origin
        }
        
        let preconnect = originsByHost.values.map {
            "<link rel=\"preconnect\" href=\"\($0)\" crossorigin>"
        }.joined(separator: "\n")
        
        let dnsPrefetch = originsByHost.keys.map {
            "<link rel=\"dns-prefetch\" href=\"//\($0)\">"
        }.joined(separator: "\n")
        
        return "\(preconnect)\n\(dnsPrefetch)"
    }
    
    /// Serialize variables dictionary to JSON string
    private static func serializeVariables(_ variables: [String: Any]) -> String {
        guard let jsonData = try? JSONSerialization.data(
            withJSONObject: variables,
            options: []
        ),
        let jsonString = String(data: jsonData, encoding: .utf8) else {
            return "{}"
        }
        return jsonString
    }
    
    /// Build a dispatch script to send messages to WebView
    static func buildDispatchScript(_ payload: [String: Any]) -> String {
        guard let jsonData = try? JSONSerialization.data(withJSONObject: payload),
              let jsonString = String(data: jsonData, encoding: .utf8) else {
            return ""
        }
        
        // Escape for JavaScript injection
        let escaped = jsonString
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "`", with: "\\`")
        
        return """
        (function(){
            try{
                document.dispatchEvent(new MessageEvent('message',{data:\(escaped)}));
            }catch(e){}
        })();
        """
    }
}

