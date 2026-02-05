import Foundation

/// Override properties for component elements
struct ComponentOverride: Codable {
    var text: String?
    var src: String?
    var style: String?
}

/// Expands <ramp-component/> tags in HTML
enum ComponentExpander {

    /// Expand all component tags in HTML
    static func expandHTML(_ html: String, components: [String: SDKComponent]?) -> String {
        guard let components = components, !components.isEmpty else { return html }
        guard hasComponentTags(html) else { return html }

        var result = html
        let pattern = #"<ramp-component\s+([^>]*?)/?>(?:</ramp-component>)?"#

        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return html
        }

        // Process in reverse to preserve indices
        let matches = regex.matches(in: html, range: NSRange(html.startIndex..., in: html))

        for match in matches.reversed() {
            guard let fullRange = Range(match.range, in: result),
                  let attrRange = Range(match.range(at: 1), in: result) else { continue }

            let attributes = String(result[attrRange])

            guard let key = extractAttribute("key", from: attributes),
                  let instance = extractAttribute("instance", from: attributes) else { continue }

            guard let component = components[key] else {
                result.replaceSubrange(fullRange, with: "<!-- Component \"\(key)\" not found -->")
                continue
            }

            let overrides = parseOverrides(from: attributes)
            let expanded = expandComponent(component: component, instance: instance, overrides: overrides)
            result.replaceSubrange(fullRange, with: expanded)
        }

        return result
    }

    private static func hasComponentTags(_ html: String) -> Bool {
        html.range(of: "<ramp-component\\s", options: .regularExpression) != nil
    }

    private static func expandComponent(component: SDKComponent, instance: String, overrides: [String: ComponentOverride]) -> String {
        var expanded = component.html

        // 1. Prefix all data-ramp-id with instance
        expanded = expanded.replacingOccurrences(
            of: #"data-ramp-id="([^"]+)""#,
            with: "data-ramp-id=\"\(instance):$1\"",
            options: .regularExpression
        )

        // 2. Apply overrides
        for (elementId, override) in overrides {
            let fullId = "\(instance):\(elementId)"

            if let text = override.text {
                // Escape special regex characters in the text replacement
                let escapedText = text.replacingOccurrences(of: "$", with: "\\$")
                let pattern = #"(<[^>]*data-ramp-id="\#(fullId)"[^>]*>)([\s\S]*?)(</[^>]+>)"#
                if let regex = try? NSRegularExpression(pattern: pattern) {
                    let range = NSRange(expanded.startIndex..., in: expanded)
                    expanded = regex.stringByReplacingMatches(in: expanded, range: range, withTemplate: "$1\(escapedText)$3")
                }
            }

            if let src = override.src {
                let pattern = #"(<[^>]*data-ramp-id="\#(fullId)"[^>]*)\ssrc="[^"]*""#
                expanded = expanded.replacingOccurrences(of: pattern, with: "$1 src=\"\(src)\"", options: .regularExpression)
            }
        }

        // 3. Wrap with component marker
        return "<div data-ramp-component=\"\(component.key):\(instance)\">\(expanded)</div>"
    }

    private static func extractAttribute(_ name: String, from attributes: String) -> String? {
        let pattern = "\(name)\\s*=\\s*\"([^\"]+)\""
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: attributes, range: NSRange(attributes.startIndex..., in: attributes)),
              let range = Range(match.range(at: 1), in: attributes) else { return nil }
        return String(attributes[range])
    }

    private static func parseOverrides(from attributes: String) -> [String: ComponentOverride] {
        let pattern = #"overrides\s*=\s*'([^']+)'"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: attributes, range: NSRange(attributes.startIndex..., in: attributes)),
              let range = Range(match.range(at: 1), in: attributes) else { return [:] }

        let json = String(attributes[range])
        guard let data = json.data(using: .utf8),
              let dict = try? JSONDecoder().decode([String: ComponentOverride].self, from: data) else { return [:] }

        return dict
    }
}
