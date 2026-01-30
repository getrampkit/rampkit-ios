import Foundation

/// Handles communication with the RampKit backend (Supabase Edge Functions)
enum BackendAPI {
    
    // MARK: - Configuration
    
    /// Supabase Functions base URL
    private static let functionsBaseURL = "https://uustlzuvjmochxkxatfx.supabase.co/functions/v1"
    
    /// Supabase anon key (public)
    private static let supabaseAnonKey = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InV1c3RsenV2am1vY2h4a3hhdGZ4Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3NjIxMDM2NTUsImV4cCI6MjA3NzY3OTY1NX0.d5XsIMGnia4n9Pou0IidipyyEfSlwpXFoeDBufMOEwE"
    
    // MARK: - Endpoints
    
    /// Sync app user device info to backend
    /// - Parameters:
    ///   - deviceInfo: The collected device information
    ///   - appId: The app UUID from RampKit dashboard
    /// - Returns: The upserted app user data from backend
    @available(iOS 14.0, macOS 11.0, *)
    static func syncAppUser(
        deviceInfo: DeviceInfo,
        appId: String
    ) async throws -> [String: Any]? {
        // Build URL with appId query parameter
        let urlString = "\(functionsBaseURL)/app-users?appId=\(appId.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? appId)"
        
        guard let url = URL(string: urlString) else {
            throw BackendError.invalidURL
        }
        
        // Encode device info to JSON
        let encoder = JSONEncoder()
        let jsonData: Data
        do {
            jsonData = try encoder.encode(deviceInfo)
        } catch {
            throw BackendError.encodingFailed(error)
        }
        
        // Build request
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = jsonData
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        // Add API key header (required for Supabase gateway)
        request.setValue(supabaseAnonKey, forHTTPHeaderField: "apikey")
        
        request.timeoutInterval = 30
        
        RampKitLogger.verbose("BackendAPI", "Syncing app user to \(urlString)")
        
        // Make request
        let (data, response): (Data, URLResponse)
        
        #if compiler(>=5.5) && (os(iOS) || os(macOS) || os(watchOS) || os(tvOS))
        if #available(iOS 15.0, macOS 12.0, watchOS 8.0, tvOS 15.0, *) {
            (data, response) = try await URLSession.shared.data(for: request)
        } else {
            (data, response) = try await withCheckedThrowingContinuation { continuation in
                URLSession.shared.dataTask(with: request) { data, response, error in
                    if let error = error {
                        continuation.resume(throwing: error)
                        return
                    }
                    guard let data = data, let response = response else {
                        continuation.resume(throwing: BackendError.noResponse)
                        return
                    }
                    continuation.resume(returning: (data, response))
                }.resume()
            }
        }
        #else
        (data, response) = try await withCheckedThrowingContinuation { continuation in
            URLSession.shared.dataTask(with: request) { data, response, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }
                guard let data = data, let response = response else {
                    continuation.resume(throwing: BackendError.noResponse)
                    return
                }
                continuation.resume(returning: (data, response))
            }.resume()
        }
        #endif
        
        // Check HTTP response
        guard let httpResponse = response as? HTTPURLResponse else {
            throw BackendError.invalidResponse
        }
        
        // Parse response JSON
        let json: [String: Any]
        do {
            guard let parsed = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw BackendError.invalidJSON
            }
            json = parsed
        } catch {
            throw BackendError.decodingFailed(error)
        }
        
        // Check for success
        guard httpResponse.statusCode >= 200 && httpResponse.statusCode < 300 else {
            let errorMessage = json["error"] as? String ?? "Unknown error"
            RampKitLogger.warn("BackendAPI", "Error \(httpResponse.statusCode): \(errorMessage)")
            throw BackendError.serverError(statusCode: httpResponse.statusCode, message: errorMessage)
        }
        
        guard let success = json["success"] as? Bool, success else {
            let errorMessage = json["error"] as? String ?? "Request failed"
            throw BackendError.requestFailed(message: errorMessage)
        }
        
        RampKitLogger.verbose("BackendAPI", "App user synced successfully")
        
        // Return the upserted data
        return json["data"] as? [String: Any]
    }
    
    // MARK: - Events
    
    /// Send an event to the backend
    /// - Parameter event: The event to send
    /// - Returns: true if successful
    @available(iOS 14.0, macOS 11.0, *)
    static func sendEvent(_ event: RampKitEvent) async throws -> Bool {
        let urlString = "\(functionsBaseURL)/app-user-events"
        
        guard let url = URL(string: urlString) else {
            throw BackendError.invalidURL
        }
        
        // Encode event to JSON
        let encoder = JSONEncoder()
        let jsonData: Data
        do {
            jsonData = try encoder.encode(event)
        } catch {
            throw BackendError.encodingFailed(error)
        }
        
        // Build request
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = jsonData
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(supabaseAnonKey, forHTTPHeaderField: "apikey")
        request.timeoutInterval = 10 // Shorter timeout for events
        
        // Make request
        let (data, response): (Data, URLResponse)
        
        #if compiler(>=5.5) && (os(iOS) || os(macOS) || os(watchOS) || os(tvOS))
        if #available(iOS 15.0, macOS 12.0, watchOS 8.0, tvOS 15.0, *) {
            (data, response) = try await URLSession.shared.data(for: request)
        } else {
            (data, response) = try await withCheckedThrowingContinuation { continuation in
                URLSession.shared.dataTask(with: request) { data, response, error in
                    if let error = error {
                        continuation.resume(throwing: error)
                        return
                    }
                    guard let data = data, let response = response else {
                        continuation.resume(throwing: BackendError.noResponse)
                        return
                    }
                    continuation.resume(returning: (data, response))
                }.resume()
            }
        }
        #else
        (data, response) = try await withCheckedThrowingContinuation { continuation in
            URLSession.shared.dataTask(with: request) { data, response, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }
                guard let data = data, let response = response else {
                    continuation.resume(throwing: BackendError.noResponse)
                    return
                }
                continuation.resume(returning: (data, response))
            }.resume()
        }
        #endif
        
        // Check HTTP response
        guard let httpResponse = response as? HTTPURLResponse else {
            throw BackendError.invalidResponse
        }
        
        // Parse response JSON
        guard httpResponse.statusCode >= 200 && httpResponse.statusCode < 300 else {
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let errorMessage = json["error"] as? String {
                throw BackendError.serverError(statusCode: httpResponse.statusCode, message: errorMessage)
            }
            throw BackendError.serverError(statusCode: httpResponse.statusCode, message: "Unknown error")
        }
        
        return true
    }
    
    // MARK: - Errors
    
    enum BackendError: LocalizedError {
        case invalidURL
        case encodingFailed(Error)
        case noResponse
        case invalidResponse
        case invalidJSON
        case decodingFailed(Error)
        case serverError(statusCode: Int, message: String)
        case requestFailed(message: String)
        
        var errorDescription: String? {
            switch self {
            case .invalidURL:
                return "Invalid backend URL"
            case .encodingFailed(let error):
                return "Failed to encode request: \(error.localizedDescription)"
            case .noResponse:
                return "No response from server"
            case .invalidResponse:
                return "Invalid response from server"
            case .invalidJSON:
                return "Invalid JSON in response"
            case .decodingFailed(let error):
                return "Failed to decode response: \(error.localizedDescription)"
            case .serverError(let statusCode, let message):
                return "Server error \(statusCode): \(message)"
            case .requestFailed(let message):
                return "Request failed: \(message)"
            }
        }
    }
}

