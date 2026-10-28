import Foundation

enum ServiceError: LocalizedError, Equatable {
    /// The token was rejected and could not be refreshed.
    case unauthorized
    case rateLimited
    case http(Int, String)
    case malformedResponse
    case stateMismatch
    case signIn(String)
    case missingCode
    case noFreePort
    case keychain(String)
    /// Antigravity's client secret could not be read from a local install.
    case antigravityClient(String)

    var errorDescription: String? {
        switch self {
        case .unauthorized: "Session expired. Sign in again."
        case .rateLimited: "Rate limited; will retry later."
        case .http(let status, let message): "HTTP \(status): \(message)"
        case .malformedResponse: "Unexpected response from the service."
        case .stateMismatch: "Sign-in state mismatch. Try again."
        case .signIn(let message): "Sign-in failed: \(message)"
        case .missingCode: "No authorization code received."
        case .noFreePort: "Could not open a local port for the sign-in callback."
        case .keychain(let message): "Keychain error: \(message)"
        case .antigravityClient(let message): "Antigravity's sign-in client was not found. \(message)"
        }
    }
}
