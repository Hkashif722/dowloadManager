// MARK: - Download Strategy Protocol
import Foundation

public struct DownloadPreparation {
    public let url: URL
    public let headers: [String: String]?
    public let resumeData: Data? // Added for resuming downloads
    public let additionalData: [String: Any]? // For any other non-standard data
    
    public init(url: URL, headers: [String: String]? = nil, resumeData: Data? = nil, additionalData: [String: Any]? = nil) {
        self.url = url
        self.headers = headers
        self.resumeData = resumeData
        self.additionalData = additionalData
    }
}

/// Allows custom download preparation logic for specific types
public protocol DownloadStrategy {
    associatedtype Item: DownloadableItem
    
    /// Prepares the download, potentially modifying the URL or adding headers.
    func prepareDownload(for item: Item, resumeData: Data?) async throws -> DownloadPreparation
    
    /// Processes the downloaded file (e.g., unzipping, decryption) at a temporary location.
    /// Should return the URL of the final processed file (which might still be temporary before moving to permanent storage).
    func processDownloadedFile(at temporaryURL: URL, for item: Item) async throws -> URL
    
    /// Validates the integrity or content of the downloaded and processed file.
    func validateDownload(at fileURL: URL, for item: Item) async throws -> Bool
}