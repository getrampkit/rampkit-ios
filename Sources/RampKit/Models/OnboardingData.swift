import Foundation

/// Complete onboarding data structure from CDN
public struct OnboardingData: Codable {
    /// Unique identifier for this onboarding configuration (optional)
    public let onboardingId: String?
    
    /// Array of screen definitions
    public let screens: [ScreenPayload]
    
    /// Optional state variables
    public let variables: VariableContainer?
    
    /// External script URLs to load
    public let requiredScripts: [String]?
    
    /// Prebuilt HTML documents (for caching)
    public let prebuiltDocs: [String]?
    
    /// Navigation data for resolving __continue__/__goBack__ based on spatial layout
    public let navigation: NavigationData?
    
    /// Container for state variables
    public struct VariableContainer: Codable {
        public let state: [OnboardingVariable]?
    }
}

/// Navigation data structure from the editor's spatial layout
public struct NavigationData: Codable {
    /// Ordered array of screen IDs in the main flow (sorted by X position, main row only)
    public let mainFlow: [String]
    
    /// Map of screen ID to position information
    public let screenPositions: [String: ScreenPosition]?
}

/// Position information for a screen in the editor
public struct ScreenPosition: Codable {
    /// X coordinate in the editor canvas
    public let x: Double
    
    /// Y coordinate in the editor canvas
    public let y: Double
    
    /// Row classification: "main" for main row screens, "variant" for screens below
    public let row: String
}

/// Individual screen definition
public struct ScreenPayload: Codable {
    /// Unique screen identifier
    public let id: String

    /// Human-readable label
    public let label: String?

    /// HTML content
    public let html: String

    /// Optional CSS styles
    public let css: String?

    /// Optional JavaScript code
    public let js: String?

    /// Optional translations keyed by language/locale code (e.g., "es", "ar", "es_MX")
    /// Each translation is a dictionary mapping data-ramp-id to translated text
    public let translations: [String: [String: String]]?
}

/// State variable definition
public struct OnboardingVariable: Codable {
    /// Variable name
    public let name: String
    
    /// Initial value (can be any JSON type) - optional since some variables may not have an initial value
    public let initialValue: AnyCodable?
}

