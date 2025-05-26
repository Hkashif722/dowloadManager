// MARK: - Sources/DownloadManager/Configuration/DownloadConfiguration.swift

import Foundation

/// Configuration for the download manager
public struct DownloadConfiguration {
    public let downloadsDirectory: URL
    public let maxConcurrentDownloads: Int
    public let allowsCellularAccess: Bool
    public let isDiscretionary: Bool
    public let sessionIdentifier: String
    public let retryLimit: Int
    public let retryDelay: TimeInterval
    
    public init(
        downloadsDirectory: URL? = nil,
        maxConcurrentDownloads: Int = 3,
        allowsCellularAccess: Bool = true,
        isDiscretionary: Bool = false,
        sessionIdentifier: String = "com.app.downloadmanager",
        retryLimit: Int = 3,
        retryDelay: TimeInterval = 2.0
    ) {
        self.downloadsDirectory = downloadsDirectory ?? FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Downloads")
        self.maxConcurrentDownloads = maxConcurrentDownloads
        self.allowsCellularAccess = allowsCellularAccess
        self.isDiscretionary = isDiscretionary
        self.sessionIdentifier = sessionIdentifier
        self.retryLimit = retryLimit
        self.retryDelay = retryDelay
    }
}