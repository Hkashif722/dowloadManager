// MARK: - Download Error
import Foundation

public enum DownloadError: LocalizedError, Equatable {
    case unsupportedType(String)
    case itemNotFound
    case modelNotFound
    case networkError(Error)
    case storageError(Error)
    case missingConfiguration
    case missingStorage
    case fileOperationFailed(String, Error?)
    case downloadFailed(String)
    case unknownNetworkError
    case taskAlreadyExists(UUID)
    case taskNotFound(UUID)
    case strategyError(String)
    case invalidURL(String)
    case maximumDownloadsReached

    public var errorDescription: String? {
        switch self {
        case .unsupportedType(let type):
            return "Unsupported download type: \(type)"
        case .itemNotFound:
            return "Download item not found in storage or cache."
        case .modelNotFound:
            return "Parent model not found in storage or cache."
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .storageError(let error):
            return "Storage error: \(error.localizedDescription)"
        case .missingConfiguration:
            return "DownloadManager configuration is required."
        case .missingStorage:
            return "DownloadManager storage implementation is required."
        case .fileOperationFailed(let reason, let underlyingError):
            var message = "File operation failed: \(reason)"
            if let underlyingError = underlyingError {
                message += " - Underlying error: \(underlyingError.localizedDescription)"
            }
            return message
        case .downloadFailed(let reason):
            return "Download failed: \(reason)"
        case .unknownNetworkError:
            return "An unknown network error occurred."
        case .taskAlreadyExists(let itemId):
            return "A download task for item ID \(itemId) already exists or is queued."
        case .taskNotFound(let itemId):
            return "No active download task found for item ID \(itemId)."
        case .strategyError(let reason):
            return "Download strategy error: \(reason)"
        case .invalidURL(let urlString):
            return "Invalid URL: \(urlString)"
        case .maximumDownloadsReached:
            return "Maximum concurrent download limit reached. Please wait."
        }
    }
    
    // Equatable conformance
    public static func == (lhs: DownloadError, rhs: DownloadError) -> Bool {
        switch (lhs, rhs) {
        case (.unsupportedType(let l), .unsupportedType(let r)): return l == r
        case (.itemNotFound, .itemNotFound): return true
        case (.modelNotFound, .modelNotFound): return true
        case (.networkError(let l), .networkError(let r)): return l.localizedDescription == r.localizedDescription // Basic check
        case (.storageError(let l), .storageError(let r)): return l.localizedDescription == r.localizedDescription // Basic check
        case (.missingConfiguration, .missingConfiguration): return true
        case (.missingStorage, .missingStorage): return true
        case (.fileOperationFailed(let lReason, _), .fileOperationFailed(let rReason, _)): return lReason == rReason // Simplified
        case (.downloadFailed(let l), .downloadFailed(let r)): return l == r
        case (.unknownNetworkError, .unknownNetworkError): return true
        case (.taskAlreadyExists(let l), .taskAlreadyExists(let r)): return l == r
        case (.taskNotFound(let l), .taskNotFound(let r)): return l == r
        case (.strategyError(let l), .strategyError(let r)): return l == r
        case (.invalidURL(let l), .invalidURL(let r)): return l == r
        case (.maximumDownloadsReached, .maximumDownloadsReached): return true
        default: return false
        }
    }
}