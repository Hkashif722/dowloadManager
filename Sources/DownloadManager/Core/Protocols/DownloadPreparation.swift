// MARK: - Download Strategy Protocol
import Foundation

public struct DownloadPreparation: Sendable {
    public let url: URL
    public let headers: [String: String]?
    public let resumeData: Data?
    public let additionalParameters: [String: String]?
    
    public init(url: URL, headers: [String: String]? = nil, resumeData: Data? = nil, additionalParameters: [String: String]? = nil) {
        self.url = url
        self.headers = headers
        self.resumeData = resumeData
        self.additionalParameters = additionalParameters
    }
}

/// Allows custom download preparation logic for specific types
public protocol DownloadStrategy: Sendable {
    associatedtype Item: DownloadableItem
    
    /// Prepares the download, potentially modifying the URL or adding headers.
    func prepareDownload(for item: Item, resumeData: Data?) async throws -> DownloadPreparation
    
    /// Processes the downloaded file (e.g., unzipping, decryption) at a temporary location.
    /// Should return the URL of the final processed file (which might still be temporary before moving to permanent storage).
    func processDownloadedFile(at temporaryURL: URL, for item: Item) async throws -> URL
    
    /// Validates the integrity or content of the downloaded and processed file.
    func validateDownload(at fileURL: URL, for item: Item) async throws -> Bool
}
